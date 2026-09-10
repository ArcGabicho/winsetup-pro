#Requires -Version 5.1
<#
.SYNOPSIS
    Prepares a freshly installed Windows machine to run WinSetup Pro.

.DESCRIPTION
    Verifies prerequisites (PowerShell version, execution policy, winget) and then
    hands control to the local WinSetup.ps1.

    SECURITY: this script never downloads and executes remote code. The supported
    way to get WinSetup Pro onto a new machine is:

        git clone https://github.com/<you>/WinSetup-Pro.git
        cd WinSetup-Pro
        powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap.ps1

    A "curl | iex" style one-liner is intentionally NOT provided: piping an
    unauthenticated script straight into the shell gives the remote server full
    control of your machine with no chance to review what runs.

.EXAMPLE
    .\scripts\bootstrap.ps1 -InstallPwsh -Forward '-Profile','minimal','-DryRun'
#>
[CmdletBinding()]
param(
    [switch]$InstallPwsh,
    [string[]]$Forward = @()
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

Write-Host 'WinSetup Pro - bootstrap' -ForegroundColor Cyan
Write-Host ''

# 1. PowerShell version -------------------------------------------------------
if ($PSVersionTable.PSVersion.Major -lt 5) {
    throw 'Windows PowerShell 5.1 or newer is required to bootstrap WinSetup Pro.'
}
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host 'PowerShell 7 is recommended (WinSetup Pro also runs on 5.1).' -ForegroundColor Yellow
    if ($InstallPwsh -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host 'Installing PowerShell 7 via winget...' -ForegroundColor Cyan
        winget install --id Microsoft.PowerShell --exact --source winget `
            --accept-package-agreements --accept-source-agreements --silent
    }
}

# 2. Execution policy (process scope only - not persisted) -------------------
$policy = Get-ExecutionPolicy -Scope Process
if ($policy -in @('Restricted', 'Undefined', 'AllSigned')) {
    Write-Host 'Relaxing execution policy for THIS process only (RemoteSigned).' -ForegroundColor Yellow
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force
}

# 3. winget / App Installer -------------------------------------------------
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host 'winget (App Installer) was not found.' -ForegroundColor Yellow
    Write-Host 'Install "App Installer" from the Microsoft Store, then re-run this script.' -ForegroundColor Yellow
}

# 4. Hand off to the local entry point -----------------------------------------
$entry = Join-Path $repoRoot 'WinSetup.ps1'
if (-not (Test-Path -LiteralPath $entry)) {
    throw "WinSetup.ps1 was not found at the repository root ($entry)."
}

Write-Host ''
Write-Host "Launching $entry" -ForegroundColor Cyan
Write-Host ''
& $entry @Forward
exit $LASTEXITCODE
