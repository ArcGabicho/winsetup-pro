# WinSetup Pro - Core module.
# Aggregates the engine's building blocks. Load with:
#   Import-Module .\modules\Core\Core.psm1 -Force

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $PSCommandPath

$ordered = @(
    'Logging.ps1'
    'Json.ps1'
    'Configuration.ps1'
    'Privilege.ps1'
    'SystemDetection.ps1'
    'Winget.ps1'
    'Wsl.ps1'
    'UI.ps1'
    'ComponentModel.ps1'
    'Registry.ps1'
    'Journal.ps1'
    'ErrorHandling.ps1'
    'Engine.ps1'
)

foreach ($file in $ordered) {
    . (Join-Path $here $file)
}

Export-ModuleMember -Function @(
    # Logging
    'Initialize-WinSetupLog', 'Write-WinSetupLog', 'Set-WinSetupLogConsole'
    # Json / configuration
    'ConvertTo-WinSetupHashtable', 'Read-WinSetupJsonFile'
    'Merge-WinSetupConfig', 'Get-WinSetupConfig', 'Get-WinSetupConfigValue'
    'Test-WinSetupConfig', 'Resolve-WinSetupPlan'
    # Privilege
    'Test-WinSetupAdmin', 'Assert-WinSetupAdmin', 'Get-WinSetupPrivilegeReport'
    # System
    'Get-WinSetupSystemInfo', 'Test-WinSetupInternet', 'Get-WinSetupDiagnostics'
    # winget helpers
    'Install-WinSetupWingetPackage', 'Update-WinSetupSessionPath', 'Get-WinSetupExeVersion'
    # WSL helpers
    'Invoke-WinSetupWsl', 'Get-WinSetupWslInfo', 'Format-WinSetupWslConfig'
    # UI
    'Write-WinSetupBanner', 'Write-WinSetupStep', 'Write-WinSetupStatusLine'
    'Write-WinSetupSummary', 'Read-WinSetupChoice', 'Confirm-WinSetupAction', 'Test-WinSetupConsole'
    # Component model / registry
    'New-WinSetupComponent', 'New-WinSetupDetectionResult', 'Test-WinSetupComponentSchema'
    'Import-WinSetupComponents', 'Resolve-WinSetupComponentOrder'
    # Journal
    'New-WinSetupJournal', 'Save-WinSetupJournal', 'Get-WinSetupJournal', 'Update-WinSetupJournalEntry'
    # Error handling
    'Resolve-WinSetupError'
    # Engine
    'New-WinSetupContext', 'Get-WinSetupStatus', 'Invoke-WinSetupPlan'
)
