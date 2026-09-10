# modules/Applications/Kubectl.ps1 - Kubernetes CLI (kubectl).

New-WinSetupComponent -Id 'kubectl' -Name 'kubectl' -Category 'Cloud' `
    -Description 'Kubernetes command-line tool' `
    -Tags @('cloud', 'kubernetes') `
    -Test {
        param($Context)
        $version = Get-WinSetupExeVersion -Command 'kubectl' -VersionArgs @('version', '--client')
        if (-not $version) { return New-WinSetupDetectionResult -Installed $false }
        New-WinSetupDetectionResult -Installed $true -Version $version -Summary "kubectl $version"
    } `
    -Install {
        param($Context)
        Install-WinSetupWingetPackage -Id 'Kubernetes.kubectl' -VerifyCommand 'kubectl'
    }
