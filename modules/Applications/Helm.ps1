# modules/Applications/Helm.ps1 - Helm (Kubernetes package manager).

New-WinSetupComponent -Id 'helm' -Name 'Helm' -Category 'Cloud' `
    -Description 'Helm - the Kubernetes package manager' `
    -Tags @('cloud', 'kubernetes') `
    -Test {
        param($Context)
        $version = Get-WinSetupExeVersion -Command 'helm' -VersionArgs @('version')
        if (-not $version) { return New-WinSetupDetectionResult -Installed $false }
        New-WinSetupDetectionResult -Installed $true -Version $version -Summary "helm $version"
    } `
    -Install {
        param($Context)
        Install-WinSetupWingetPackage -Id 'Helm.Helm' -VerifyCommand 'helm'
    }
