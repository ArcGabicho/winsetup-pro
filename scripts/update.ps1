#Requires -Version 5.1
<#
.SYNOPSIS
    Updates the WinSetup Pro working copy.
.DESCRIPTION
    Phase 1 implementation: performs a 'git pull' when the repository is a git
    clone. Component self-update / package refresh is planned for Phase 5.
#>
[CmdletBinding()]
param()

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    if (-not (Test-Path (Join-Path $repoRoot '.git'))) {
        Write-Host 'This copy is not a git clone - update it however you obtained it.' -ForegroundColor Yellow
        return
    }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host 'git is not installed; cannot self-update.' -ForegroundColor Yellow
        return
    }
    Write-Host 'Updating WinSetup Pro (git pull --ff-only)...' -ForegroundColor Cyan
    git pull --ff-only
}
finally {
    Pop-Location
}
