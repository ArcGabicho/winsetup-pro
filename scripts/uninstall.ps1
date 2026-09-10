#Requires -Version 5.1
<#
.SYNOPSIS
    Removes WinSetup Pro's own working data (logs, state, backups).

.DESCRIPTION
    This does NOT uninstall any software that components installed - removing
    developer tools is deliberately left to the user (via winget uninstall or
    Apps & Features) so that nothing is removed by surprise.

    Use -Purge to also delete the backup\ directory.
#>
[CmdletBinding(SupportsShouldProcess)]
param([switch]$Purge)

$repoRoot = Split-Path -Parent $PSScriptRoot
$targets  = @('logs', 'state')
if ($Purge) { $targets += 'backup' }

foreach ($name in $targets) {
    $path = Join-Path $repoRoot $name
    if (Test-Path -LiteralPath $path) {
        if ($PSCmdlet.ShouldProcess($path, 'Remove directory contents')) {
            Get-ChildItem -LiteralPath $path -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "Cleared $path" -ForegroundColor Green
        }
    }
}
Write-Host 'WinSetup Pro working data removed. Installed software was left untouched.' -ForegroundColor Cyan
