#Requires -Version 5.1
<#
.SYNOPSIS
    Thin wrapper around WinSetup.ps1 for callers that expect an "install" verb.
.EXAMPLE
    .\scripts\install.ps1 -Profile minimal
#>
[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments)] [string[]]$Args)

$entry = Join-Path (Split-Path -Parent $PSScriptRoot) 'WinSetup.ps1'
& $entry @Args
exit $LASTEXITCODE
