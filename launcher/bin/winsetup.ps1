#Requires -Version 5.1
# PATH shim for `winsetup`. install-launcher.ps1 adds this folder to the user
# PATH, so `winsetup ...` works from any directory and any shell.
[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments = $true)] [string[]]$Arguments)

$module = Join-Path (Split-Path -Parent $PSScriptRoot) 'WinSetupPro\WinSetupPro.psd1'
Import-Module $module -Force
Invoke-WinSetup @Arguments
exit $LASTEXITCODE
