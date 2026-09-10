#Requires -Version 5.1
<#
.SYNOPSIS
    Standalone diagnostics report (same content as 'WinSetup.ps1 -Diagnose').
#>
[CmdletBinding()]
param()

$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repoRoot 'modules\Core\Core.psm1') -Force
Initialize-WinSetupLog -Directory (Join-Path $repoRoot 'logs') -Operation 'diagnose' | Out-Null

$config  = Get-WinSetupConfig -Root $repoRoot
$context = New-WinSetupContext -Root $repoRoot -Config $config

Write-Host 'WinSetup Pro - Diagnostics' -ForegroundColor White
Write-Host ''
$checks = Get-WinSetupDiagnostics -Context $context
foreach ($check in $checks) {
    Write-WinSetupStatusLine -Name $check.Name -Ok $check.Ok -Detail $check.Detail
}

$failed = @($checks | Where-Object { -not $_.Ok })
Write-Host ''
if ($failed.Count -gt 0) {
    Write-Host ('{0} check(s) need attention.' -f $failed.Count) -ForegroundColor Yellow
    exit 1
}
Write-Host 'All readiness checks passed.' -ForegroundColor Green
exit 0
