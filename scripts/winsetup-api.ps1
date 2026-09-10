#Requires -Version 5.1
<#
.SYNOPSIS
    Transport wrapper: runs one WinSetupApi verb and writes the result as JSON.

.DESCRIPTION
    Contains NO logic - it delegates to Invoke-WinSetupApi (scripts\WinSetupApi.psm1)
    and serializes. stdout carries ONLY machine-readable output:
      * read verbs      -> one JSON envelope
      * apply / resume  -> newline-delimited JSON events, then a final envelope

      pwsh -NoProfile -File scripts\winsetup-api.ps1 -Verb <verb> [-Json <payload> | -JsonFile <file>] [-Path <file>]

    Envelope: { "apiVersion": <int>, "verb": <verb>, "ok": <bool>,
                "data": <object> | "error": <string> }
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('system', 'diagnose', 'profiles', 'components', 'status',
        'plan', 'apply', 'journal', 'resume', 'export', 'import', 'version')]
    [string]$Verb,

    [string]$Json,
    [string]$JsonFile,
    [string]$Path,
    [string]$Root
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
$OutputEncoding = New-Object System.Text.UTF8Encoding($false)

if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
if (-not $Json -and $JsonFile -and (Test-Path -LiteralPath $JsonFile)) {
    $Json = Get-Content -LiteralPath $JsonFile -Raw
}

Import-Module (Join-Path $PSScriptRoot 'WinSetupApi.psm1') -Force -Verbose:$false

function Write-JsonLine {
    param($Object)
    [Console]::Out.WriteLine(($Object | ConvertTo-Json -Depth 12 -Compress))
    [Console]::Out.Flush()
}

$streamSink = {
    param($EventObject)
    [Console]::Out.WriteLine(($EventObject | ConvertTo-Json -Depth 8 -Compress))
    [Console]::Out.Flush()
}

try {
    $sink = if ($Verb -in @('apply', 'resume')) { $streamSink } else { $null }
    $result = Invoke-WinSetupApi -Verb $Verb -Root $Root -Payload $Json -Path $Path -EventSink $sink

    $envelope = [ordered]@{ apiVersion = (Get-WinSetupApiVersion); verb = $Verb; ok = [bool]$result.ok }
    if ($result.ok) { $envelope.data = $result.data } else { $envelope.error = $result.error }
    Write-JsonLine -Object ([pscustomobject]$envelope)
    if (-not $result.ok) { exit 1 }
}
catch {
    Write-JsonLine -Object ([pscustomobject]@{ apiVersion = 1; verb = $Verb; ok = $false; error = $_.Exception.Message })
    exit 1
}
exit 0
