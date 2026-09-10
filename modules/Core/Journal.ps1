# Journal.ps1 - a run journal persisted to state\ so that an interrupted run
# can be continued with 'WinSetup.ps1 -Resume'.

function New-WinSetupJournal {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$ProfileName,
        [Parameter(Mandatory)][string[]]$ComponentIds,
        [bool]$DryRun = $false
    )
    [pscustomobject]@{
        Path       = $Path
        StartedUtc = (Get-Date).ToUniversalTime().ToString('o')
        UpdatedUtc = (Get-Date).ToUniversalTime().ToString('o')
        Profile    = $ProfileName
        DryRun     = $DryRun
        Completed  = $false
        Entries    = @(
            $ComponentIds | ForEach-Object {
                [pscustomobject]@{ Id = $_; Status = 'Pending'; Action = $null; Error = $null; DurationMs = 0 }
            }
        )
    }
}

function Save-WinSetupJournal {
    param([Parameter(Mandatory)]$Journal)
    $Journal.UpdatedUtc = (Get-Date).ToUniversalTime().ToString('o')
    $dir = Split-Path -Parent $Journal.Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    ($Journal | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $Journal.Path -Encoding utf8
}

function Get-WinSetupJournal {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        return (Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json)
    } catch {
        Write-WinSetupLog -Level WARNING -Module 'Journal' -Message ("Could not read journal '{0}': {1}" -f $Path, $_.Exception.Message)
        return $null
    }
}

function Update-WinSetupJournalEntry {
    param(
        [Parameter(Mandatory)]$Journal,
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Status,
        [string]$Action,
        [string]$ErrorText,
        [int]$DurationMs
    )
    $entry = $Journal.Entries | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if ($entry) {
        $entry.Status = $Status
        if ($PSBoundParameters.ContainsKey('Action'))     { $entry.Action = $Action }
        if ($PSBoundParameters.ContainsKey('ErrorText'))  { $entry.Error = $ErrorText }
        if ($PSBoundParameters.ContainsKey('DurationMs')) { $entry.DurationMs = $DurationMs }
    }
    Save-WinSetupJournal -Journal $Journal
}
