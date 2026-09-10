# modules/Applications/PowerShell7.ps1 - PowerShell 7 (pwsh).
#
# RequiresAdmin is left $false so a non-elevated run still attempts the install
# and reports a clear, actionable failure (retry elevated) rather than silently
# skipping. Only components that cannot work at all without elevation set it.

New-WinSetupComponent -Id 'pwsh' -Name 'PowerShell 7' -Category 'Development' `
    -Description 'Cross-platform PowerShell 7 (recommended shell for WinSetup Pro)' `
    -Tags @('shell', 'core') `
    -Test {
        param($Context)
        $version = Get-WinSetupExeVersion -Command 'pwsh'
        if (-not $version) { return New-WinSetupDetectionResult -Installed $false -Summary 'pwsh not on PATH' }
        New-WinSetupDetectionResult -Installed $true -Version $version -Summary "pwsh $version"
    } `
    -Install {
        param($Context)
        Install-WinSetupWingetPackage -Id 'Microsoft.PowerShell' -VerifyCommand 'pwsh'
    }
