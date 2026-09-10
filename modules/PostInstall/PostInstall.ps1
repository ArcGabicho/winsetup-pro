# modules/PostInstall/PostInstall.ps1 - runs the user's own finishing scripts.
#
# Config (postInstall.*):
#   scripts   array of .ps1 paths (absolute, or relative to the repo root)
#   always    re-run every time instead of only when the script changed
#
# Each script is dot-sourced with $Context available. A run is recorded in
# state/postinstall.json by content hash, so an unchanged script is not
# re-run unless postInstall.always is true. WinSetup never downloads a remote
# script - only local paths you list yourself are executed.

New-WinSetupComponent -Id 'post-install' -Name 'Post-install scripts' -Category 'Customization' `
    -Description 'Runs the finishing scripts listed in postInstall.scripts' `
    -Tags @('scripts') `
    -Test {
        param($Context)
        $scripts = @(Get-WinSetupConfigValue -Config $Context.Config -Path 'postInstall.scripts' -Default @() | Where-Object { $_ })
        if ($scripts.Count -eq 0) {
            return New-WinSetupDetectionResult -Installed $true -Summary 'no post-install scripts'
        }
        if ((Get-WinSetupConfigValue -Config $Context.Config -Path 'postInstall.always' -Default $false) -eq $true) {
            return New-WinSetupDetectionResult -Installed $true -Configured $false -Summary "$($scripts.Count) script(s), always re-run"
        }

        $statePath = Join-Path $Context.Paths.State 'postinstall.json'
        $done = @{}
        if (Test-Path -LiteralPath $statePath) {
            try {
                (Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json).PSObject.Properties |
                    ForEach-Object { $done[$_.Name] = $_.Value }
            } catch { }
        }

        $pending = 0
        foreach ($rel in $scripts) {
            $path = if ([System.IO.Path]::IsPathRooted($rel)) { $rel } else { Join-Path $Context.Root $rel }
            if (-not (Test-Path -LiteralPath $path)) { continue }
            $hash = (Get-FileHash -LiteralPath $path).Hash
            if ($done[$path] -ne $hash) { $pending++ }
        }

        if ($pending -eq 0) {
            return New-WinSetupDetectionResult -Installed $true -Summary "$($scripts.Count) script(s) already run"
        }
        New-WinSetupDetectionResult -Installed $true -Configured $false -Summary "$pending script(s) pending"
    } `
    -Configure {
        param($Context)
        $scripts = @(Get-WinSetupConfigValue -Config $Context.Config -Path 'postInstall.scripts' -Default @() | Where-Object { $_ })
        if ($scripts.Count -eq 0) { return }
        $always = (Get-WinSetupConfigValue -Config $Context.Config -Path 'postInstall.always' -Default $false) -eq $true

        $statePath = Join-Path $Context.Paths.State 'postinstall.json'
        $done = [ordered]@{}
        if (Test-Path -LiteralPath $statePath) {
            try {
                (Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json).PSObject.Properties |
                    ForEach-Object { $done[$_.Name] = $_.Value }
            } catch { }
        }

        foreach ($rel in $scripts) {
            $path = if ([System.IO.Path]::IsPathRooted($rel)) { $rel } else { Join-Path $Context.Root $rel }
            if (-not (Test-Path -LiteralPath $path)) {
                Write-WinSetupLog -Level WARNING -Module 'post-install' -Message "script not found: $path"
                continue
            }
            $hash = (Get-FileHash -LiteralPath $path).Hash
            if (-not $always -and $done[$path] -eq $hash) {
                Write-WinSetupLog -Level DEBUG -Module 'post-install' -Message "unchanged, skipping: $path"
                continue
            }

            Write-WinSetupLog -Level INFO -Module 'post-install' -Message "running $path"
            try {
                & $path $Context
                if ($LASTEXITCODE -is [int] -and $LASTEXITCODE -ne 0) {
                    throw "script exited with code $LASTEXITCODE"
                }
            }
            catch {
                throw ("post-install script '{0}' failed: {1}" -f $path, $_.Exception.Message)
            }
            $done[$path] = $hash
        }

        ($done | ConvertTo-Json) | Set-Content -LiteralPath $statePath -Encoding utf8
    }
