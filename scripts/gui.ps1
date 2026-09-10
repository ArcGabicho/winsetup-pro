#Requires -Version 5.1
<#
.SYNOPSIS
    Opens the WinSetup Pro graphical app. Builds it automatically the first time.

.DESCRIPTION
    One command, from a fresh clone:

        pwsh -File .\scripts\gui.ps1

    Finds the built GUI (or builds it once with `dotnet build`), then launches it.
    Falls back to the interactive console if the .NET SDK is not installed.

.EXAMPLE
    pwsh -File .\scripts\gui.ps1

.EXAMPLE
    pwsh -File .\scripts\gui.ps1 -SetupProfile dotnet -DryRun
#>
[CmdletBinding()]
param(
    # -Profile is an alias; a parameter literally named Profile would clobber
    # the automatic $PROFILE variable when a value is bound.
    [Alias('Profile')]
    [string]$SetupProfile,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$env:WINSETUP_HOME = $root
$proj = Join-Path $root 'ui\WinSetup.Pro.UI\WinSetup.Pro.UI.csproj'

function Find-GuiExe {
    $bin = Join-Path $root 'ui\WinSetup.Pro.UI\bin'
    if (-not (Test-Path -LiteralPath $bin)) { return $null }
    Get-ChildItem -Path $bin -Recurse -Filter 'WinSetup.Pro.UI.exe' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}

$exe = Find-GuiExe
if (-not $exe) {
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        Write-Host 'The .NET SDK (10+) is needed to build the GUI the first time.' -ForegroundColor Yellow
        Write-Host 'Get it from https://dotnet.microsoft.com/download  -  or use the console:' -ForegroundColor Yellow
        Write-Host "    pwsh -File `"$(Join-Path $root 'WinSetup.ps1')`"" -ForegroundColor DarkGray
        exit 1
    }
    Write-Host 'Building the WinSetup Pro GUI (first run only, ~10s)...' -ForegroundColor Cyan
    & dotnet build $proj -c Debug --nologo
    if ($LASTEXITCODE -ne 0) { throw 'GUI build failed.' }
    $exe = Find-GuiExe
}
if (-not $exe) { throw 'The GUI build did not produce WinSetup.Pro.UI.exe.' }

$guiArgs = @()
if ($SetupProfile) { $guiArgs += @('--profile', $SetupProfile) }
if ($DryRun)       { $guiArgs += '--dry-run' }

Write-Host "Opening WinSetup Pro..." -ForegroundColor Cyan
Start-Process -FilePath $exe -ArgumentList $guiArgs -WorkingDirectory $root
