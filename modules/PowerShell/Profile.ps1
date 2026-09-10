# modules/PowerShell/Profile.ps1 - modular PowerShell profile setup.
#
# WinSetup Pro NEVER rewrites your whole $PROFILE. It:
#   * copies the requested fragments (aliases / functions / prompt / git /
#     docker / environment) into <profile dir>\winsetup-pro\
#   * maintains a single marked block in $PROFILE that dot-sources them
#   * touches nothing outside "# >>> WinSetup Pro managed block >>>" ...
#     "# <<< WinSetup Pro managed block <<<"
# The existing $PROFILE is backed up before the block is first added/changed.
#
# Config (powershellProfile.*):
#   enabled    include in a profile run
#   allHosts   target $PROFILE.CurrentUserAllHosts (default true) vs CurrentHost
#   fragments  subset of the six fragment names (default: all)
#   modules    module names to Install-Module -Scope CurrentUser if missing

New-WinSetupComponent -Id 'powershell-profile' -Name 'PowerShell profile' -Category 'Customization' `
    -Description 'Modular $PROFILE fragments in a self-contained managed block' `
    -Tags @('powershell', 'shell') `
    -Test {
        param($Context)
        $catalogue = @('aliases', 'functions', 'prompt', 'git', 'docker', 'environment')
        $requested = @(Get-WinSetupConfigValue -Config $Context.Config -Path 'powershellProfile.fragments' -Default $catalogue | Where-Object { $_ -in $catalogue })
        if ($requested.Count -eq 0) { $requested = $catalogue }

        $allHosts = (Get-WinSetupConfigValue -Config $Context.Config -Path 'powershellProfile.allHosts' -Default $true) -eq $true
        $target = if ($allHosts) { $global:PROFILE.CurrentUserAllHosts } else { $global:PROFILE.CurrentUserCurrentHost }
        $managedDir = Join-Path (Split-Path -Parent $target) 'winsetup-pro'

        $pending = @()

        $blockPresent = $false
        if (Test-Path -LiteralPath $target) {
            $blockPresent = (Get-Content -LiteralPath $target -Raw) -match 'WinSetup Pro managed block'
        }
        if (-not $blockPresent) { $pending += 'managed block not in $PROFILE' }

        foreach ($frag in $requested) {
            if (-not (Test-Path -LiteralPath (Join-Path $managedDir "$frag.ps1"))) { $pending += "fragment '$frag' missing" }
        }

        foreach ($mod in @(Get-WinSetupConfigValue -Config $Context.Config -Path 'powershellProfile.modules' -Default @() | Where-Object { $_ })) {
            if (-not (Get-Module -ListAvailable -Name $mod)) { $pending += "module '$mod' not installed" }
        }

        $summary = "target: $target"
        if ($pending.Count -gt 0) { $summary += '; pending -> ' + ($pending -join ', ') }
        New-WinSetupDetectionResult -Installed $true -Configured ($pending.Count -eq 0) -Summary $summary
    } `
    -Configure {
        param($Context)
        $catalogue = @('aliases', 'functions', 'prompt', 'git', 'docker', 'environment')
        $requested = @(Get-WinSetupConfigValue -Config $Context.Config -Path 'powershellProfile.fragments' -Default $catalogue | Where-Object { $_ -in $catalogue })
        if ($requested.Count -eq 0) { $requested = $catalogue }

        $allHosts = (Get-WinSetupConfigValue -Config $Context.Config -Path 'powershellProfile.allHosts' -Default $true) -eq $true
        $target = if ($allHosts) { $global:PROFILE.CurrentUserAllHosts } else { $global:PROFILE.CurrentUserCurrentHost }
        $managedDir = Join-Path (Split-Path -Parent $target) 'winsetup-pro'
        $sourceDir = Join-Path $Context.Paths.Templates 'powershell'

        if (-not (Test-Path -LiteralPath $managedDir)) { New-Item -ItemType Directory -Path $managedDir -Force | Out-Null }

        # 1. sync fragment files (our own directory - safe to overwrite / prune)
        foreach ($frag in $catalogue) {
            $src = Join-Path $sourceDir "$frag.ps1"
            $dst = Join-Path $managedDir "$frag.ps1"
            if ($requested -contains $frag) {
                if (-not (Test-Path -LiteralPath $src)) { continue }
                $srcText = Get-Content -LiteralPath $src -Raw
                $dstText = if (Test-Path -LiteralPath $dst) { Get-Content -LiteralPath $dst -Raw } else { $null }
                if ($srcText -ne $dstText) {
                    Copy-Item -LiteralPath $src -Destination $dst -Force
                    Write-WinSetupLog -Level INFO -Module 'powershell-profile' -Message "wrote fragment $dst"
                }
            }
            elseif (Test-Path -LiteralPath $dst) {
                Remove-Item -LiteralPath $dst -Force
                Write-WinSetupLog -Level INFO -Module 'powershell-profile' -Message "removed unused fragment $dst"
            }
        }

        # 2. build the managed block
        $fragList = "'" + ($requested -join "', '") + "'"
        $marker0 = '# >>> WinSetup Pro managed block >>>'
        $marker1 = '# <<< WinSetup Pro managed block <<<'
        $block = @(
            $marker0
            '# Managed by WinSetup Pro - do not edit between the markers.'
            ('$WinSetupProfileDir = ''{0}''' -f $managedDir)
            'if (Test-Path -LiteralPath $WinSetupProfileDir) {'
            ("    foreach (`$__wsp in @($fragList)) {")
            '        $__p = Join-Path $WinSetupProfileDir "$__wsp.ps1"'
            '        if (Test-Path -LiteralPath $__p) { . $__p }'
            '    }'
            '}'
            $marker1
        ) -join "`r`n"

        # 3. splice it into $PROFILE without disturbing anything else
        $existing = ''
        if (Test-Path -LiteralPath $target) {
            $existing = Get-Content -LiteralPath $target -Raw
        }
        else {
            $dir = Split-Path -Parent $target
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        }

        # (?s) so '.' spans newlines for both the test and the replace.
        $pattern = '(?s)' + [regex]::Escape($marker0) + '.*?' + [regex]::Escape($marker1)
        if ([regex]::IsMatch($existing, $pattern)) {
            # MatchEvaluator so '$' in $block is not treated as a substitution token.
            $updated = [regex]::Replace($existing, $pattern, { param($m) $block })
            if ($updated -ne $existing) {
                Backup-WinSetupFile -Context $Context -Path $target -Category 'powershell' | Out-Null
                Set-Content -LiteralPath $target -Value $updated -Encoding utf8
                Write-WinSetupLog -Level INFO -Module 'powershell-profile' -Message "refreshed managed block in $target"
            }
        }
        else {
            if (Test-Path -LiteralPath $target) {
                Backup-WinSetupFile -Context $Context -Path $target -Category 'powershell' | Out-Null
            }
            $sep = if ($existing.Length -gt 0 -and -not $existing.EndsWith("`n")) { "`r`n`r`n" } else { "`r`n" }
            Add-Content -LiteralPath $target -Value ($sep + $block + "`r`n") -Encoding utf8
            Write-WinSetupLog -Level INFO -Module 'powershell-profile' -Message "added managed block to $target"
        }

        # 4. optional modules
        foreach ($mod in @(Get-WinSetupConfigValue -Config $Context.Config -Path 'powershellProfile.modules' -Default @() | Where-Object { $_ })) {
            if (Get-Module -ListAvailable -Name $mod) { continue }
            Write-WinSetupLog -Level INFO -Module 'powershell-profile' -Message "Install-Module $mod -Scope CurrentUser"
            try {
                Install-Module -Name $mod -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
            }
            catch {
                throw ("Install-Module '{0}' failed: {1}" -f $mod, $_.Exception.Message)
            }
        }
    }
