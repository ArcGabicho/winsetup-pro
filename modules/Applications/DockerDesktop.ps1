# modules/Applications/DockerDesktop.ps1 - Docker Desktop.
#
# RequiresAdmin = $true: the installer registers a service and enables the
# WSL2 / virtualization features - it genuinely cannot proceed unelevated.
# A restart is normally required afterwards.

New-WinSetupComponent -Id 'docker-desktop' -Name 'Docker Desktop' -Category 'Development' `
    -Description 'Docker Desktop (containers, Compose, Kubernetes)' `
    -Tags @('containers') `
    -RequiresAdmin $true `
    -Test {
        param($Context)
        $version = Get-WinSetupExeVersion -Command 'docker'
        $exe = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
        if ($version) {
            return New-WinSetupDetectionResult -Installed $true -Version $version -Summary "docker $version"
        }
        if (Test-Path -LiteralPath $exe) {
            return New-WinSetupDetectionResult -Installed $true -Summary 'installed (docker CLI not on PATH yet)'
        }
        New-WinSetupDetectionResult -Installed $false
    } `
    -Install {
        param($Context)
        Install-WinSetupWingetPackage -Id 'Docker.DockerDesktop' `
            -VerifyCommand 'docker' `
            -VerifyPath '%ProgramFiles%\Docker\Docker\Docker Desktop.exe'
        Write-WinSetupLog -Level WARNING -Module 'docker-desktop' -Message 'Docker Desktop installed. A restart is recommended; then launch Docker Desktop once to finish setup.'
    }
