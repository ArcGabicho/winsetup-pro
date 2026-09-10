# ErrorHandling.ps1 - decides what to do when a component operation throws.
#
# Interactive sessions prompt Retry / Skip / Abort.
# Non-interactive sessions apply settings.errorPolicy from the configuration:
#   critical components -> 'abort'  (default)
#   other components    -> 'skip'   (default)

function Resolve-WinSetupError {
    <#
    .SYNOPSIS
        Returns one of 'retry', 'skip' or 'abort'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Component,
        [Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $isCritical = [bool]$Component.Critical
    Write-WinSetupLog -Level ERROR -Module $Component.Id -Message ("Operation failed: {0}" -f $ErrorRecord.Exception.Message)

    if (-not $Context.Interactive) {
        $decision = if ($isCritical) {
            [string](Get-WinSetupConfigValue -Config $Context.Config -Path 'settings.errorPolicy.critical' -Default 'abort')
        } else {
            [string](Get-WinSetupConfigValue -Config $Context.Config -Path 'settings.errorPolicy.nonCritical' -Default 'skip')
        }
        $decision = $decision.ToLowerInvariant()
        if ($decision -notin @('retry', 'skip', 'abort')) { $decision = if ($isCritical) { 'abort' } else { 'skip' } }
        Write-WinSetupLog -Level WARNING -Module $Component.Id -Message ("Non-interactive error policy -> {0}" -f $decision)
        return $decision
    }

    if (Test-WinSetupConsole) {
        Write-Host ''
        Write-Host ('{0} operation failed: {1}' -f $Component.Name, $ErrorRecord.Exception.Message) -ForegroundColor Red
    }
    $choice = Read-WinSetupChoice -Title 'How do you want to proceed?' `
        -Options @('Retry', 'Skip this component', 'Abort setup') `
        -Default $(if ($isCritical) { 3 } else { 2 })
    switch ($choice) {
        1 { return 'retry' }
        2 { return 'skip' }
        default { return 'abort' }
    }
}
