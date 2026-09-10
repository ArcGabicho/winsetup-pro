# modules/Environment/EnvironmentVariables.ps1 - declarative environment variables.
#
# Applies config.environment:
#   user    : { NAME: value, ... }   -> User scope
#   machine : { NAME: value, ... }   -> Machine scope (requires elevation)
#   path    : [ "C:\tools\bin", ... ] -> appended to the User PATH, de-duplicated
#
# Existing values are backed up to backup/environment/ before any change, and a
# value that already matches is left untouched (idempotent). PATH entries are
# compared case-insensitively with trailing separators normalised so nothing is
# ever duplicated.

New-WinSetupComponent -Id 'env-vars' -Name 'Environment variables' -Category 'Environment' `
    -Description 'Applies the configured user/machine variables and PATH entries' `
    -Tags @('environment') `
    -Test {
        param($Context)
        $env = Get-WinSetupConfigValue -Config $Context.Config -Path 'environment' -Default $null
        if (-not ($env -is [System.Collections.IDictionary])) {
            return New-WinSetupDetectionResult -Installed $true -Summary 'no environment config'
        }

        $pending = New-Object System.Collections.Generic.List[string]

        if ($env['user'] -is [System.Collections.IDictionary]) {
            foreach ($k in $env['user'].Keys) {
                if ([Environment]::GetEnvironmentVariable($k, 'User') -ne [string]$env['user'][$k]) { $pending.Add("user:$k") }
            }
        }
        if ($env['machine'] -is [System.Collections.IDictionary]) {
            foreach ($k in $env['machine'].Keys) {
                if ([Environment]::GetEnvironmentVariable($k, 'Machine') -ne [string]$env['machine'][$k]) { $pending.Add("machine:$k") }
            }
        }

        $desiredPath = @($env['path'] | Where-Object { $_ })
        if ($desiredPath.Count -gt 0) {
            $have = @{}
            foreach ($e in @([Environment]::GetEnvironmentVariable('Path', 'User') -split ';' | Where-Object { $_ })) {
                $have[$e.Trim().TrimEnd('\').ToLowerInvariant()] = $true
            }
            foreach ($p in $desiredPath) {
                $norm = [Environment]::ExpandEnvironmentVariables([string]$p).Trim().TrimEnd('\').ToLowerInvariant()
                if (-not $have.ContainsKey($norm)) { $pending.Add("path:$p") }
            }
        }

        if ($pending.Count -eq 0) {
            return New-WinSetupDetectionResult -Installed $true -Summary 'all variables/PATH entries already set'
        }
        New-WinSetupDetectionResult -Installed $true -Configured $false -Summary ("pending -> " + ($pending -join ', '))
    } `
    -Configure {
        param($Context)
        $env = Get-WinSetupConfigValue -Config $Context.Config -Path 'environment' -Default $null
        if (-not ($env -is [System.Collections.IDictionary])) { return }

        if ((Get-WinSetupConfigValue -Config $Context.Config -Path 'settings.createBackups' -Default $true)) {
            $dir = Join-Path $Context.Paths.Backup 'environment'
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            $snapshot = [ordered]@{
                timestampUtc = (Get-Date).ToUniversalTime().ToString('o')
                userPath     = [Environment]::GetEnvironmentVariable('Path', 'User')
                user         = [ordered]@{}
                machine      = [ordered]@{}
            }
            if ($env['user'] -is [System.Collections.IDictionary]) {
                foreach ($k in $env['user'].Keys) { $snapshot['user'][$k] = [Environment]::GetEnvironmentVariable($k, 'User') }
            }
            if ($env['machine'] -is [System.Collections.IDictionary]) {
                foreach ($k in $env['machine'].Keys) { $snapshot['machine'][$k] = [Environment]::GetEnvironmentVariable($k, 'Machine') }
            }
            $file = Join-Path $dir ("env-{0}.json" -f (Get-Date -Format 'yyyy-MM-dd_HHmmss'))
            ($snapshot | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $file -Encoding utf8
            Write-WinSetupLog -Level INFO -Module 'env-vars' -Message "Environment snapshot saved to $file"
        }

        if ($env['user'] -is [System.Collections.IDictionary]) {
            foreach ($k in $env['user'].Keys) {
                $want = [string]$env['user'][$k]
                if ([Environment]::GetEnvironmentVariable($k, 'User') -eq $want) { continue }
                Write-WinSetupLog -Level INFO -Module 'env-vars' -Message "USER $k = $want"
                [Environment]::SetEnvironmentVariable($k, $want, 'User')
                Set-Item -Path ("Env:" + $k) -Value $want -ErrorAction SilentlyContinue
            }
        }

        if ($env['machine'] -is [System.Collections.IDictionary] -and $env['machine'].Count -gt 0) {
            Assert-WinSetupAdmin -Reason 'setting machine-scoped environment variables.'
            foreach ($k in $env['machine'].Keys) {
                $want = [string]$env['machine'][$k]
                if ([Environment]::GetEnvironmentVariable($k, 'Machine') -eq $want) { continue }
                Write-WinSetupLog -Level INFO -Module 'env-vars' -Message "MACHINE $k = $want"
                [Environment]::SetEnvironmentVariable($k, $want, 'Machine')
            }
        }

        $desiredPath = @($env['path'] | Where-Object { $_ })
        if ($desiredPath.Count -gt 0) {
            $entries = New-Object System.Collections.Generic.List[string]
            foreach ($e in @([Environment]::GetEnvironmentVariable('Path', 'User') -split ';' | Where-Object { $_ })) { $entries.Add($e) }
            $have = @{}
            foreach ($e in $entries) { $have[$e.Trim().TrimEnd('\').ToLowerInvariant()] = $true }

            $added = @()
            foreach ($p in $desiredPath) {
                $expanded = [Environment]::ExpandEnvironmentVariables([string]$p)
                $norm = $expanded.Trim().TrimEnd('\').ToLowerInvariant()
                if ($have.ContainsKey($norm)) { continue }
                if (-not (Test-Path -LiteralPath $expanded)) {
                    Write-WinSetupLog -Level WARNING -Module 'env-vars' -Message "PATH entry '$expanded' does not exist yet - adding it anyway."
                }
                $entries.Add($expanded)
                $have[$norm] = $true
                $added += $expanded
            }
            if ($added.Count -gt 0) {
                [Environment]::SetEnvironmentVariable('Path', ($entries -join ';'), 'User')
                Update-WinSetupSessionPath
                Write-WinSetupLog -Level INFO -Module 'env-vars' -Message ("Added to USER PATH: " + ($added -join ', '))
            }
        }
    }
