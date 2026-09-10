# modules/Applications/AwsCli.ps1 - AWS CLI (aws).

New-WinSetupComponent -Id 'aws-cli' -Name 'AWS CLI' -Category 'Cloud' `
    -Description 'Amazon Web Services command-line interface (aws)' `
    -Tags @('cloud', 'aws') `
    -Test {
        param($Context)
        $version = Get-WinSetupExeVersion -Command 'aws'
        if (-not $version) { return New-WinSetupDetectionResult -Installed $false }
        New-WinSetupDetectionResult -Installed $true -Version $version -Summary "aws $version"
    } `
    -Install {
        param($Context)
        Install-WinSetupWingetPackage -Id 'Amazon.AWSCLI' -VerifyCommand 'aws'
    }
