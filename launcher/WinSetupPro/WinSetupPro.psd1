@{
    RootModule        = 'WinSetupPro.psm1'
    ModuleVersion     = '0.2.0'
    GUID              = 'a3f1b6c2-9d4e-4a7b-8c1d-2e6f0a9b3c5d'
    Author            = 'WinSetup Pro contributors'
    Description       = 'Launcher for WinSetup Pro - `winsetup` opens the GUI or runs the CLI.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Invoke-WinSetup', 'Get-WinSetupLaunchMode', 'Get-WinSetupHome', 'Get-WinSetupGuiExe')
    AliasesToExport   = @('winsetup')
    CmdletsToExport   = @()
    VariablesToExport = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('windows', 'setup', 'provisioning', 'developer-environment')
            ProjectUri = 'https://github.com/ArcGabicho/winsetup-pro'
            LicenseUri = 'https://github.com/ArcGabicho/winsetup-pro/blob/main/LICENSE'
        }
    }
}
