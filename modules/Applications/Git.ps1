# modules/Applications/Git.ps1
#
# Reference component. A component file MUST:
#   * return one or more descriptors created with New-WinSetupComponent
#   * have no side effects at load time (no installs, no config writes)
#   * keep the Test block read-only
#   * be self-contained - each script block may only rely on the engine's
#     exported helpers (Write-WinSetupLog, Get-WinSetupConfigValue, ...) and its
#     own local variables, never on functions defined at file scope.
#
# This component installs Git via winget and applies a safe, idempotent global
# configuration. It never asks for or stores credentials, and it never
# overwrites an existing user.name / user.email.

New-WinSetupComponent -Id 'git' -Name 'Git' -Category 'Development' `
    -Description 'Git distributed version control' `
    -Tags @('vcs', 'core') `
    -Critical $false `
    -RequiresAdmin $false `
    -Test {
        param($Context)

        $cmd = Get-Command git.exe -ErrorAction SilentlyContinue
        if (-not $cmd) {
            return New-WinSetupDetectionResult -Installed $false -Summary 'git not found on PATH'
        }

        $version = $null
        try {
            $raw = (& git.exe --version) 2>$null
            if ($raw -match '(\d+\.\d+(\.\d+)?)') { $version = $Matches[1] }
        } catch { }

        $desired = [ordered]@{
            'init.defaultBranch' = [string](Get-WinSetupConfigValue -Config $Context.Config -Path 'git.defaultBranch' -Default 'main')
            'pull.rebase'        = [string](Get-WinSetupConfigValue -Config $Context.Config -Path 'git.pullRebase' -Default 'false')
            'credential.helper'  = [string](Get-WinSetupConfigValue -Config $Context.Config -Path 'git.credentialHelper' -Default 'manager')
            'core.editor'        = [string](Get-WinSetupConfigValue -Config $Context.Config -Path 'git.editor' -Default '')
            'user.name'          = [string](Get-WinSetupConfigValue -Config $Context.Config -Path 'git.userName' -Default '')
            'user.email'         = [string](Get-WinSetupConfigValue -Config $Context.Config -Path 'git.userEmail' -Default '')
        }

        $configured = $true
        foreach ($key in $desired.Keys) {
            $want = $desired[$key]
            if ([string]::IsNullOrWhiteSpace($want)) { continue }
            $have = (& git.exe config --global --get $key) 2>$null
            if ($key -in @('user.name', 'user.email')) {
                if ([string]::IsNullOrWhiteSpace([string]$have)) { $configured = $false }
            }
            elseif ($have -ne $want) {
                $configured = $false
            }
        }

        $name  = (& git.exe config --global --get user.name)  2>$null
        $email = (& git.exe config --global --get user.email) 2>$null
        $summary = if (-not [string]::IsNullOrWhiteSpace([string]$name) -and -not [string]::IsNullOrWhiteSpace([string]$email)) {
            "identity: $name <$email>"
        } else {
            'identity not set (configure git.userName / git.userEmail)'
        }

        New-WinSetupDetectionResult -Installed $true -Configured $configured -Version $version -Summary $summary
    } `
    -Install {
        param($Context)

        if (-not $Context.System.WingetPresent) {
            throw 'winget (App Installer) is required to install Git automatically.'
        }

        $wingetArgs = @(
            'install', '--id', 'Git.Git', '--exact',
            '--source', 'winget',
            '--accept-package-agreements', '--accept-source-agreements',
            '--silent', '--disable-interactivity'
        )
        Write-WinSetupLog -Level INFO -Module 'git' -Message ('winget ' + ($wingetArgs -join ' '))
        & winget @wingetArgs | Out-Null

        # -1978335189 = "no applicable update / package already installed"
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {
            throw "winget exited with code $LASTEXITCODE while installing Git."
        }

        # Make git.exe reachable in this session so Configure can run immediately.
        $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        $userPath    = [Environment]::GetEnvironmentVariable('Path', 'User')
        $env:Path = @($machinePath, $userPath | Where-Object { $_ }) -join ';'
    } `
    -Configure {
        param($Context)

        $git = Get-Command git.exe -ErrorAction SilentlyContinue
        if (-not $git) { throw 'git was not found on PATH after installation.' }

        # Back up the existing global config before the first write.
        $gitConfigPath = Join-Path $HOME '.gitconfig'
        $doBackup = Get-WinSetupConfigValue -Config $Context.Config -Path 'settings.createBackups' -Default $true
        if ($doBackup -and (Test-Path -LiteralPath $gitConfigPath)) {
            $backupDir = Join-Path $Context.Paths.Backup 'git'
            if (-not (Test-Path -LiteralPath $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
            $stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
            Copy-Item -LiteralPath $gitConfigPath -Destination (Join-Path $backupDir ".gitconfig.$stamp") -Force
            Write-WinSetupLog -Level INFO -Module 'git' -Message "Backed up .gitconfig to $backupDir"
        }

        $desired = [ordered]@{
            'init.defaultBranch' = [string](Get-WinSetupConfigValue -Config $Context.Config -Path 'git.defaultBranch' -Default 'main')
            'pull.rebase'        = [string](Get-WinSetupConfigValue -Config $Context.Config -Path 'git.pullRebase' -Default 'false')
            'credential.helper'  = [string](Get-WinSetupConfigValue -Config $Context.Config -Path 'git.credentialHelper' -Default 'manager')
            'core.editor'        = [string](Get-WinSetupConfigValue -Config $Context.Config -Path 'git.editor' -Default '')
            'user.name'          = [string](Get-WinSetupConfigValue -Config $Context.Config -Path 'git.userName' -Default '')
            'user.email'         = [string](Get-WinSetupConfigValue -Config $Context.Config -Path 'git.userEmail' -Default '')
        }

        foreach ($key in $desired.Keys) {
            $value = $desired[$key]
            if ([string]::IsNullOrWhiteSpace($value)) { continue }

            $current = (& git.exe config --global --get $key) 2>$null
            if ($current -eq $value) { continue }

            if ($current -and $key -in @('user.name', 'user.email')) {
                Write-WinSetupLog -Level WARNING -Module 'git' -Message "$key is already set to '$current' - left unchanged."
                continue
            }

            Write-WinSetupLog -Level INFO -Module 'git' -Message "git config --global $key `"$value`""
            & git.exe config --global $key $value
            if ($LASTEXITCODE -ne 0) { throw "Failed to set git config '$key'." }
        }
    }
