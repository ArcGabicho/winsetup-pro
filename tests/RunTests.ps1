#Requires -Version 5.1
<#
.SYNOPSIS
    Runs the WinSetup Pro Pester test suite.
.EXAMPLE
    pwsh -File .\tests\RunTests.ps1
#>
[CmdletBinding()]
param(
    [ValidateSet('unit', 'integration', 'all')]
    [string]$Suite = 'unit',
    [switch]$CI
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

$pester = Get-Module -ListAvailable Pester | Sort-Object Version -Descending | Select-Object -First 1
if (-not $pester -or $pester.Version.Major -lt 5) {
    throw 'Pester 5+ is required. Install with: Install-Module Pester -Scope CurrentUser -MinimumVersion 5.5.0'
}
Import-Module Pester -MinimumVersion 5.0.0 -Force

$paths = switch ($Suite) {
    'unit'        { Join-Path $repoRoot 'tests\unit' }
    'integration' { Join-Path $repoRoot 'tests\integration' }
    'all'         { Join-Path $repoRoot 'tests' }
}

$config = New-PesterConfiguration
$config.Run.Path = $paths
$config.Output.Verbosity = if ($CI) { 'Detailed' } else { 'Normal' }
if ($CI) {
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputPath = Join-Path $repoRoot 'logs\testresults.xml'
}

Invoke-Pester -Configuration $config
