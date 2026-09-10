# modules/Applications/GcloudCli.ps1 - Google Cloud CLI (gcloud).

New-WinSetupComponent -Id 'gcloud-cli' -Name 'Google Cloud CLI' -Category 'Cloud' `
    -Description 'Google Cloud SDK command-line interface (gcloud)' `
    -Tags @('cloud', 'gcp') `
    -Test {
        param($Context)
        $version = Get-WinSetupExeVersion -Command 'gcloud'
        if (-not $version) { return New-WinSetupDetectionResult -Installed $false }
        New-WinSetupDetectionResult -Installed $true -Version $version -Summary "gcloud $version"
    } `
    -Install {
        param($Context)
        Install-WinSetupWingetPackage -Id 'Google.CloudSDK' -VerifyCommand 'gcloud'
    }
