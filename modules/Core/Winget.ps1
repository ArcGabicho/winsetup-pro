# Winget.ps1 - shared helpers for components that install via winget.
#
# Components stay self-contained by calling these engine-exported functions
# rather than each re-implementing winget invocation and exit-code handling.

function Update-WinSetupSessionPath {
    <#
    .SYNOPSIS
        Rebuilds $env:Path from the Machine + User registry values so a freshly
        installed tool is reachable in the current session.
    #>
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = @($machine, $user | Where-Object { $_ }) -join ';'
}

function Get-WinSetupExeVersion {
    <#
    .SYNOPSIS
        Runs "<command> <version args>" and extracts a version string, or $null
        when the command is missing / produces no match. Read-only - safe in a
        component's Test block.
    #>
    param(
        [Parameter(Mandatory)][string]$Command,
        [string]$Pattern = '(\d+\.\d+(?:\.\d+){0,2})',
        [string[]]$VersionArgs = @('--version')
    )
    $cmd = Get-Command $Command -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cmd) { return $null }
    try {
        $raw = (& $cmd.Source @VersionArgs 2>$null | Out-String)
        if ($raw -match $Pattern) { return $Matches[1] }
    } catch { }
    return $null
}

function Install-WinSetupWingetPackage {
    <#
    .SYNOPSIS
        Installs a winget package silently and idempotently.
    .DESCRIPTION
        On a non-zero exit code the helper re-checks for the package (via
        -VerifyCommand / -VerifyPath); if it is now present the exit code is
        treated as benign (covers "already installed" / "no applicable upgrade"),
        otherwise it throws with an elevation hint.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [string]$Source = 'winget',
        [ValidateSet('user', 'machine', 'any')][string]$Scope = 'any',
        [string[]]$AdditionalArgs = @(),
        [string]$VerifyCommand,
        [string]$VerifyPath
    )

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'winget (App Installer) is not available. Install "App Installer" from the Microsoft Store and retry.'
    }

    $wingetArgs = @(
        'install', '--id', $Id, '--exact',
        '--source', $Source,
        '--accept-package-agreements', '--accept-source-agreements',
        '--silent', '--disable-interactivity'
    )
    if ($Scope -ne 'any') { $wingetArgs += @('--scope', $Scope) }
    if ($AdditionalArgs)  { $wingetArgs += $AdditionalArgs }

    Write-WinSetupLog -Level INFO -Module 'winget' -Message ('winget ' + ($wingetArgs -join ' '))
    $output = & winget @wingetArgs 2>&1
    $code = $LASTEXITCODE
    foreach ($line in @($output)) {
        $text = ([string]$line).Trim()
        if ($text) { Write-WinSetupLog -Level DEBUG -Module 'winget' -Message $text }
    }

    Update-WinSetupSessionPath

    if ($code -eq 0) { return }

    $present = $false
    if ($VerifyCommand -and (Get-Command $VerifyCommand -ErrorAction SilentlyContinue)) { $present = $true }
    if ($VerifyPath) {
        $expanded = [Environment]::ExpandEnvironmentVariables($VerifyPath)
        if (Test-Path -LiteralPath $expanded) { $present = $true }
    }

    if ($present) {
        Write-WinSetupLog -Level WARNING -Module 'winget' -Message ("winget exit code {0} for '{1}', but the package is present - treating as success." -f $code, $Id)
        return
    }

    throw ("winget could not install '{0}' (exit code {1}). If it is a machine-wide package, retry from an elevated PowerShell session." -f $Id, $code)
}
