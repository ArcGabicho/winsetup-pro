#Requires -Version 5.1
<#
.SYNOPSIS
    Runs the WinSetup Pro Pester test suite (Pester 5 or 6).

.EXAMPLE
    pwsh -File .\tests\RunTests.ps1
    pwsh -File .\tests\RunTests.ps1 -Suite all -CI
    pwsh -File .\tests\RunTests.ps1 -Suite integration      # needs WINSETUP_ALLOW_INTEGRATION=1

.NOTES
    Unit tests never modify the host: they use TestDrive:, in-memory component
    registries and synthetic components. Integration tests (tagged 'Integration')
    install real packages and are skipped unless the suite is 'integration'/'all'
    AND WINSETUP_ALLOW_INTEGRATION=1.
#>
[CmdletBinding()]
param(
    [ValidateSet('unit', 'integration', 'all')]
    [string]$Suite = 'unit',
    [string[]]$Tag,
    [string[]]$ExcludeTag,
    [switch]$Coverage,
    [switch]$CI
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

$pester = Get-Module -ListAvailable Pester | Sort-Object Version -Descending | Select-Object -First 1
if (-not $pester -or $pester.Version.Major -lt 5) {
    throw 'Pester 5+ is required. Install with: Install-Module Pester -Scope CurrentUser -MinimumVersion 5.5.0 -Force -SkipPublisherCheck'
}
Import-Module Pester -MinimumVersion 5.0.0 -Force

$paths = switch ($Suite) {
    'unit'        { , (Join-Path $repoRoot 'tests\unit') }
    'integration' { , (Join-Path $repoRoot 'tests\integration') }
    'all'         { , (Join-Path $repoRoot 'tests') }
}

$excluded = @()
if ($ExcludeTag) { $excluded += $ExcludeTag }
if ($Suite -eq 'unit') { $excluded += 'Integration' }
if ($Suite -ne 'unit' -and $env:WINSETUP_ALLOW_INTEGRATION -ne '1') {
    Write-Warning 'Integration tests will self-skip: set WINSETUP_ALLOW_INTEGRATION=1 to run them.'
}

$config = New-PesterConfiguration
$config.Run.Path = $paths
$config.Run.PassThru = $true
$config.Run.Exit = $false
$config.Output.Verbosity = if ($CI) { 'Detailed' } else { 'Normal' }
if ($Tag)          { $config.Filter.Tag = $Tag }
if ($excluded)     { $config.Filter.ExcludeTag = ($excluded | Select-Object -Unique) }
if ($CI) {
    $resultsDir = Join-Path $repoRoot 'logs'
    if (-not (Test-Path $resultsDir)) { New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null }
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputPath = Join-Path $resultsDir 'testresults.xml'
}
if ($Coverage) {
    $config.CodeCoverage.Enabled = $true
    $config.CodeCoverage.Path = Join-Path $repoRoot 'modules'
    $config.CodeCoverage.OutputPath = Join-Path $repoRoot 'logs\coverage.xml'
}

$result = Invoke-Pester -Configuration $config

Write-Host ''
Write-Host ("{0} passed, {1} failed, {2} skipped in {3:n1}s" -f `
        $result.PassedCount, $result.FailedCount, $result.SkippedCount, $result.Duration.TotalSeconds) `
    -ForegroundColor ($(if ($result.FailedCount -gt 0) { 'Red' } else { 'Green' }))

exit $result.FailedCount
