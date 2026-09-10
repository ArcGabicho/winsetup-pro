#Requires -Version 5.1
<#
.SYNOPSIS
    Registers the `winsetup` command for the current user (no admin required).

.DESCRIPTION
    Two independent, non-destructive registrations:
      1. Adds  launcher\bin  to the USER PATH (de-duplicated) so `winsetup`
         works from cmd, PowerShell 5.1 and 7, in any directory.
      2. Adds a single line to your $PROFILE (inside a marked block) that
         imports the WinSetupPro module, so `winsetup` is a first-class
         function/alias in new PowerShell sessions.
    Sets WINSETUP_HOME (user env var) to this checkout so the launcher can find
    the engine even if the module is imported from elsewhere.

    Run  -Uninstall  to reverse all of it.
#>
[CmdletBinding(SupportsShouldProcess)]
param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$binDir   = Join-Path $repoRoot 'launcher\bin'
$manifest = Join-Path $repoRoot 'launcher\WinSetupPro\WinSetupPro.psd1'
$marker0  = '# >>> WinSetup Pro launcher >>>'
$marker1  = '# <<< WinSetup Pro launcher <<<'

function Set-UserPathEntry {
    param([string]$Entry, [switch]$Remove)
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @($current -split ';' | Where-Object { $_ })
    $norm = { param($p) $p.Trim().TrimEnd('\').ToLowerInvariant() }
    $has = $parts | Where-Object { (& $norm $_) -eq (& $norm $Entry) }
    if ($Remove) {
        if (-not $has) { return $false }
        $parts = $parts | Where-Object { (& $norm $_) -ne (& $norm $Entry) }
    }
    else {
        if ($has) { return $false }
        $parts += $Entry
    }
    [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
    return $true
}

function Set-ProfileBlock {
    param([switch]$Remove)
    $target = $global:PROFILE.CurrentUserAllHosts
    if (-not $target) { $target = [string]$global:PROFILE }
    $dir = Split-Path -Parent $target
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $text = if (Test-Path -LiteralPath $target) { Get-Content -LiteralPath $target -Raw } else { '' }
    $pattern = '(?s)' + [regex]::Escape($marker0) + '.*?' + [regex]::Escape($marker1) + '\r?\n?'
    $clean = [regex]::Replace($text, $pattern, '')
    if ($Remove) {
        if ($clean -ne $text) { Set-Content -LiteralPath $target -Value $clean -Encoding utf8; return $true }
        return $false
    }
    $block = @($marker0, "Import-Module '$manifest' -ErrorAction SilentlyContinue", $marker1) -join "`r`n"
    $sep = if ($clean.Length -gt 0 -and -not $clean.EndsWith("`n")) { "`r`n`r`n" } else { '' }
    Set-Content -LiteralPath $target -Value ($clean.TrimEnd() + $sep + $block + "`r`n") -Encoding utf8
    return $true
}

if ($Uninstall) {
    if ($PSCmdlet.ShouldProcess('winsetup launcher', 'Unregister')) {
        $a = Set-UserPathEntry -Entry $binDir -Remove
        $b = Set-ProfileBlock -Remove
        [Environment]::SetEnvironmentVariable('WINSETUP_HOME', $null, 'User')
        Write-Host ("Removed launcher (PATH: {0}, profile: {1})." -f $a, $b) -ForegroundColor Cyan
        Write-Host 'Open a new terminal for the change to take effect.' -ForegroundColor DarkGray
    }
    return
}

if ($PSCmdlet.ShouldProcess('winsetup launcher', 'Register for the current user')) {
    [Environment]::SetEnvironmentVariable('WINSETUP_HOME', $repoRoot, 'User')
    $pathAdded    = Set-UserPathEntry -Entry $binDir
    $profileAdded = Set-ProfileBlock

    Import-Module $manifest -Force
    Write-Host ''
    Write-Host 'WinSetup Pro launcher registered.' -ForegroundColor Green
    Write-Host ("  WINSETUP_HOME = {0}" -f $repoRoot) -ForegroundColor DarkGray
    Write-Host ("  PATH += {0}   ({1})" -f $binDir, $(if ($pathAdded) { 'added' } else { 'already present' })) -ForegroundColor DarkGray
    Write-Host ("  {0} import      ({1})" -f '$PROFILE', $(if ($profileAdded) { 'added' } else { 'refreshed' })) -ForegroundColor DarkGray
    Write-Host ''
    Write-Host 'Open a NEW terminal, then run:  winsetup' -ForegroundColor White
    Write-Host '(this session already has it: try `winsetup -Status`)' -ForegroundColor DarkGray
}
