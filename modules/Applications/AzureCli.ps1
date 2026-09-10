# modules/Applications/AzureCli.ps1 - Azure CLI (az).

New-WinSetupComponent -Id 'azure-cli' -Name 'Azure CLI' -Category 'Cloud' `
    -Description 'Microsoft Azure command-line interface (az)' `
    -Tags @('cloud', 'azure') `
    -Test {
        param($Context)
        $version = Get-WinSetupExeVersion -Command 'az'
        if (-not $version) { return New-WinSetupDetectionResult -Installed $false }
        New-WinSetupDetectionResult -Installed $true -Version $version -Summary "az $version"
    } `
    -Install {
        param($Context)
        Install-WinSetupWingetPackage -Id 'Microsoft.AzureCLI' -VerifyCommand 'az'
    }
