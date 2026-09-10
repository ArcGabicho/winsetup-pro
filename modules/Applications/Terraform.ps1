# modules/Applications/Terraform.ps1 - HashiCorp Terraform.

New-WinSetupComponent -Id 'terraform' -Name 'Terraform' -Category 'Cloud' `
    -Description 'HashiCorp Terraform infrastructure-as-code CLI' `
    -Tags @('cloud', 'iac') `
    -Test {
        param($Context)
        $version = Get-WinSetupExeVersion -Command 'terraform' -VersionArgs @('version')
        if (-not $version) { return New-WinSetupDetectionResult -Installed $false }
        New-WinSetupDetectionResult -Installed $true -Version $version -Summary "terraform $version"
    } `
    -Install {
        param($Context)
        Install-WinSetupWingetPackage -Id 'Hashicorp.Terraform' -VerifyCommand 'terraform'
    }
