# Json.ps1 - JSON helpers that produce ordered hashtables instead of
# PSCustomObjects. Ordered dictionaries keep key order stable across merges and
# work identically on Windows PowerShell 5.1 (which lacks ConvertFrom-Json -AsHashtable).

function ConvertTo-WinSetupHashtable {
    <#
    .SYNOPSIS
        Recursively converts PSCustomObject / array graphs into ordered
        dictionaries and plain arrays.
    #>
    param($InputObject)

    if ($null -eq $InputObject) { return $null }

    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $ht = [ordered]@{}
        foreach ($p in $InputObject.PSObject.Properties) {
            $ht[$p.Name] = ConvertTo-WinSetupHashtable $p.Value
        }
        return $ht
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $ht = [ordered]@{}
        foreach ($key in $InputObject.Keys) {
            $ht[$key] = ConvertTo-WinSetupHashtable $InputObject[$key]
        }
        return $ht
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $list = New-Object System.Collections.Generic.List[object]
        foreach ($item in $InputObject) { $list.Add((ConvertTo-WinSetupHashtable $item)) }
        return , $list.ToArray()
    }

    return $InputObject
}

function Read-WinSetupJsonFile {
    <#
    .SYNOPSIS
        Loads a JSON file as an ordered hashtable graph.
    #>
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Configuration file not found: $Path"
    }

    $raw = Get-Content -LiteralPath $Path -Raw -Encoding utf8
    try {
        $obj = $raw | ConvertFrom-Json
    } catch {
        throw ("Invalid JSON in {0}: {1}" -f $Path, $_.Exception.Message)
    }
    return ConvertTo-WinSetupHashtable $obj
}
