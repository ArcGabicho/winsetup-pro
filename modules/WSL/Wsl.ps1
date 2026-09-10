# modules/WSL/Wsl.ps1 - Windows Subsystem for Linux 2.
#
# Safety rules honoured here:
#   * Existing distributions are NEVER unregistered, reset or overwritten.
#   * An existing ~/.wslconfig is left untouched unless wsl.overwriteWslConfig
#     is true (and is backed up first when it is).
#   * Feature enablement never triggers an automatic restart - the user is told
#     to reboot and re-run.
#
# Config (wsl.*):
#   enabled              include in a profile run
#   setDefaultVersion2   run `wsl --set-default-version 2` (default true)
#   distribution         name from `wsl --list --online` to install
#   wslConfig            { key: value, ... } written as the [wsl2] section
#   overwriteWslConfig   allow replacing an existing ~/.wslconfig (default false)

New-WinSetupComponent -Id 'wsl' -Name 'WSL 2' -Category 'WSL' `
    -Description 'WSL 2 features, default version, distributions and .wslconfig' `
    -Tags @('wsl', 'linux') `
    -Critical $false `
    -RequiresAdmin $true `
    -Test {
        param($Context)
        $info = Get-WinSetupWslInfo

        if (-not $info.Present) {
            return New-WinSetupDetectionResult -Installed $false -Summary 'wsl.exe not present'
        }

        # $null (unknown, e.g. non-elevated query) is treated as "probably ok"
        # because wsl.exe already exists.
        $featuresOk = ($info.FeatureWsl -ne $false) -and ($info.FeatureVmPlatform -ne $false)

        $wantV2      = (Get-WinSetupConfigValue -Config $Context.Config -Path 'wsl.setDefaultVersion2' -Default $true) -eq $true
        $wantDistro  = [string](Get-WinSetupConfigValue -Config $Context.Config -Path 'wsl.distribution' -Default '')
        $wantWslConf = Get-WinSetupConfigValue -Config $Context.Config -Path 'wsl.wslConfig' -Default $null

        $pending = @()
        if (-not $featuresOk) { $pending += 'features disabled (restart pending)' }
        if ($wantV2 -and $info.DefaultVersion -ne 2) { $pending += 'default version != 2' }
        if ($wantDistro -and ($info.Distributions -notcontains $wantDistro)) { $pending += "distro '$wantDistro' not installed" }
        if (($wantWslConf -is [System.Collections.IDictionary]) -and $wantWslConf.Count -gt 0 -and -not (Test-Path -LiteralPath (Join-Path $HOME '.wslconfig'))) {
            $pending += '.wslconfig not created'
        }

        $distroText = if ($info.Distributions.Count -gt 0) { $info.Distributions -join ', ' } else { 'none' }
        $summary = "distros: $distroText; default v$($info.DefaultVersion)"
        if ($pending.Count -gt 0) { $summary += '; pending -> ' + ($pending -join ', ') }

        New-WinSetupDetectionResult -Installed ($info.Present -and $featuresOk) `
            -Configured ($pending.Count -eq 0) `
            -Version ([string]$info.DefaultVersion) -Summary $summary
    } `
    -Install {
        param($Context)
        Assert-WinSetupAdmin -Reason 'enabling the WSL and Virtual Machine Platform Windows features.'
        $info = Get-WinSetupWslInfo

        $needFeatures = (-not $info.Present) -or ($info.FeatureWsl -eq $false) -or ($info.FeatureVmPlatform -eq $false)
        if (-not $needFeatures) {
            Write-WinSetupLog -Level INFO -Module 'wsl' -Message 'WSL features already enabled.'
            return
        }

        $done = $false
        if (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
            $result = Invoke-WinSetupWsl -Arguments @('--install', '--no-distribution')
            if ($result.ExitCode -eq 0) {
                $done = $true
                Write-WinSetupLog -Level INFO -Module 'wsl' -Message 'wsl --install --no-distribution completed.'
            }
            else {
                Write-WinSetupLog -Level WARNING -Module 'wsl' -Message ("wsl --install returned {0}: {1}" -f $result.ExitCode, $result.Text)
            }
        }

        if (-not $done) {
            Write-WinSetupLog -Level INFO -Module 'wsl' -Message 'Enabling Windows optional features via DISM...'
            foreach ($feature in @('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform')) {
                $state = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue
                if ($state -and $state.State -ne 'Enabled') {
                    Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart | Out-Null
                    Write-WinSetupLog -Level INFO -Module 'wsl' -Message "Enabled feature $feature"
                }
            }
        }

        Write-WinSetupLog -Level WARNING -Module 'wsl' -Message 'A RESTART is required before WSL 2 works. Reboot, then re-run WinSetup to set the default version and install a distribution.'
    } `
    -Configure {
        param($Context)
        $info = Get-WinSetupWslInfo
        if (-not $info.Present) {
            Write-WinSetupLog -Level WARNING -Module 'wsl' -Message 'wsl.exe not available yet - restart Windows and re-run to finish WSL setup.'
            return
        }
        if ($info.FeatureWsl -eq $false -or $info.FeatureVmPlatform -eq $false) {
            Write-WinSetupLog -Level WARNING -Module 'wsl' -Message 'WSL features are enabled but a restart is pending - re-run after rebooting.'
            return
        }

        # 1. default version 2
        if ((Get-WinSetupConfigValue -Config $Context.Config -Path 'wsl.setDefaultVersion2' -Default $true) -eq $true -and $info.DefaultVersion -ne 2) {
            Write-WinSetupLog -Level INFO -Module 'wsl' -Message 'wsl --set-default-version 2'
            $result = Invoke-WinSetupWsl -Arguments @('--set-default-version', '2')
            if ($result.ExitCode -ne 0) {
                Write-WinSetupLog -Level WARNING -Module 'wsl' -Message ("set-default-version failed: {0}" -f $result.Text)
            }
        }

        # 2. ~/.wslconfig  (create-only unless overwrite is explicitly allowed)
        $wslConf = Get-WinSetupConfigValue -Config $Context.Config -Path 'wsl.wslConfig' -Default $null
        if (($wslConf -is [System.Collections.IDictionary]) -and $wslConf.Count -gt 0) {
            $path = Join-Path $HOME '.wslconfig'
            $overwrite = (Get-WinSetupConfigValue -Config $Context.Config -Path 'wsl.overwriteWslConfig' -Default $false) -eq $true
            if ((Test-Path -LiteralPath $path) -and -not $overwrite) {
                Write-WinSetupLog -Level WARNING -Module 'wsl' -Message "$path already exists - left untouched (set wsl.overwriteWslConfig=true to replace it)."
            }
            else {
                Backup-WinSetupFile -Context $Context -Path $path -Category 'wsl' | Out-Null
                Set-Content -LiteralPath $path -Value (Format-WinSetupWslConfig -Wsl2Settings $wslConf) -Encoding utf8 -NoNewline
                Write-WinSetupLog -Level INFO -Module 'wsl' -Message "Wrote $path"
            }
        }

        # 3. distribution
        $wantDistro = [string](Get-WinSetupConfigValue -Config $Context.Config -Path 'wsl.distribution' -Default '')

        if (-not $wantDistro -and $Context.Interactive) {
            $available = @()
            try {
                $online = Invoke-WinSetupWsl -Arguments @('--list', '--online')
                foreach ($line in $online.Lines) {
                    if ($line -match '^\s*([A-Za-z0-9._-]+)\s{2,}\S') { $available += $Matches[1] }
                }
            } catch { }
            $available = @($available | Where-Object { $_ -and $_ -notin @('NAME') } | Select-Object -Unique | Select-Object -First 8)
            if ($available.Count -gt 0) {
                $choice = Read-WinSetupChoice -Title 'WSL - install a Linux distribution' -Options (@($available) + @('Skip')) -Default ($available.Count + 1)
                if ($choice -le $available.Count) { $wantDistro = $available[$choice - 1] }
            }
        }

        if (-not $wantDistro) { return }

        if ($info.Distributions -contains $wantDistro) {
            Write-WinSetupLog -Level INFO -Module 'wsl' -Message "Distribution '$wantDistro' already installed - left untouched."
            return
        }

        $onlineNames = @()
        try {
            $online = Invoke-WinSetupWsl -Arguments @('--list', '--online')
            foreach ($line in $online.Lines) {
                if ($line -match '^\s*([A-Za-z0-9._-]+)\s{2,}\S') { $onlineNames += $Matches[1] }
            }
        } catch { }
        if ($onlineNames.Count -gt 0 -and ($onlineNames -notcontains $wantDistro)) {
            throw ("Distribution '{0}' is not available. Choose one of: {1}" -f $wantDistro, ($onlineNames -join ', '))
        }

        Write-WinSetupLog -Level INFO -Module 'wsl' -Message "wsl --install --distribution $wantDistro --no-launch"
        $result = Invoke-WinSetupWsl -Arguments @('--install', '--distribution', $wantDistro, '--no-launch')
        if ($result.ExitCode -ne 0) {
            $fallback = Invoke-WinSetupWsl -Arguments @('--install', '--distribution', $wantDistro)
            if ($fallback.ExitCode -ne 0) {
                throw ("wsl --install -d {0} failed: {1}" -f $wantDistro, $fallback.Text)
            }
        }
        Write-WinSetupLog -Level SUCCESS -Module 'wsl' -Message "Installed '$wantDistro'. Launch it once to create your Linux user account."
    }
