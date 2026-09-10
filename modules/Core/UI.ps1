# UI.ps1 - console presentation. Every function is a no-op when console output
# has been disabled (Set-WinSetupLogConsole $false), which keeps test runs quiet.

function Test-WinSetupConsole { return [bool]$script:WinSetupLog.Console }

function Write-WinSetupBanner {
    param([string]$Subtitle)
    if (-not (Test-WinSetupConsole)) { return }
    $lines = @(
        '+--------------------------------------+'
        '|             WINSETUP PRO             |'
        '|   Windows Developer Setup Assistant  |'
        '+--------------------------------------+'
    )
    foreach ($l in $lines) { Write-Host $l -ForegroundColor Cyan }
    if ($Subtitle) { Write-Host ("  $Subtitle") -ForegroundColor DarkCyan }
    Write-Host ''
}

function Write-WinSetupStep {
    <#
    .SYNOPSIS
        Renders one "[ i/n ] Label ...... [ OK ]" progress line.
    #>
    param(
        [int]$Index,
        [int]$Total,
        [Parameter(Mandatory)][string]$Label,
        [ValidateSet('run', 'ok', 'skip', 'fail', 'warn', 'dry')][string]$Status = 'run',
        [string]$Detail
    )
    if (-not (Test-WinSetupConsole)) { return }

    $prefix = if ($Total -gt 0) { '[{0}/{1}]' -f $Index, $Total } else { '      ' }
    $dots   = '.' * [math]::Max(3, 34 - $Label.Length)
    $map = @{
        run  = @{ Tag = '[ .. ]'; Color = 'Gray' }
        ok   = @{ Tag = '[ OK ]'; Color = 'Green' }
        skip = @{ Tag = '[SKIP]'; Color = 'DarkGray' }
        fail = @{ Tag = '[FAIL]'; Color = 'Red' }
        warn = @{ Tag = '[WARN]'; Color = 'Yellow' }
        dry  = @{ Tag = '[DRY ]'; Color = 'Cyan' }
    }
    $entry = $map[$Status]
    Write-Host ('{0} {1} {2} {3}' -f $prefix, $Label, $dots, $entry.Tag) -ForegroundColor $entry.Color
    if ($Detail) { Write-Host ('        -> {0}' -f $Detail) -ForegroundColor DarkGray }
}

function Write-WinSetupStatusLine {
    param(
        [Parameter(Mandatory)][string]$Name,
        [bool]$Ok,
        [string]$Detail
    )
    if (-not (Test-WinSetupConsole)) { return }
    $tag   = if ($Ok) { '[ OK ]' } else { '[ -- ]' }
    $color = if ($Ok) { 'Green' } else { 'DarkGray' }
    $line  = '  {0} {1}' -f $Name.PadRight(22), $tag
    if ($Detail) { $line += '  ' + $Detail }
    Write-Host $line -ForegroundColor $color
}

function Write-WinSetupSummary {
    param(
        [Parameter(Mandatory)]$Result,
        [switch]$DryRun
    )
    if (-not (Test-WinSetupConsole)) { return }
    Write-Host ''
    Write-Host ('-' * 42) -ForegroundColor DarkGray
    if ($DryRun) {
        Write-Host 'DRY RUN - no changes were made.' -ForegroundColor Cyan
        Write-Host ('  Planned    : {0}' -f $Result.Planned) -ForegroundColor Cyan
    }
    Write-Host ('  Installed  : {0}' -f $Result.Installed)  -ForegroundColor Green
    Write-Host ('  Configured : {0}' -f $Result.Configured) -ForegroundColor Green
    Write-Host ('  Skipped    : {0}' -f $Result.Skipped)    -ForegroundColor DarkGray
    $failColor = if ($Result.Failed -gt 0) { 'Red' } else { 'Gray' }
    Write-Host ('  Failed     : {0}' -f $Result.Failed) -ForegroundColor $failColor
    if ($Result.Aborted) { Write-Host '  Run was ABORTED before completion.' -ForegroundColor Red }
    Write-Host ('-' * 42) -ForegroundColor DarkGray
    if ($Result.JournalPath) {
        Write-Host ('  Journal: {0}' -f $Result.JournalPath) -ForegroundColor DarkGray
    }
}

function Read-WinSetupChoice {
    <#
    .SYNOPSIS
        Presents a numbered menu and returns the 1-based selection. In
        non-interactive mode it returns $Default without prompting.
    #>
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string[]]$Options,
        [int]$Default = 1,
        [switch]$NonInteractive
    )

    if (Test-WinSetupConsole) {
        Write-Host ''
        Write-Host $Title -ForegroundColor White
        for ($i = 0; $i -lt $Options.Count; $i++) {
            Write-Host ('  [{0}] {1}' -f ($i + 1), $Options[$i])
        }
    }

    if ($NonInteractive) {
        if (Test-WinSetupConsole) {
            Write-Host ('  -> non-interactive: selecting [{0}] {1}' -f $Default, $Options[$Default - 1]) -ForegroundColor DarkGray
        }
        return $Default
    }

    while ($true) {
        $answer = Read-Host ('Select [1-{0}] (default {1})' -f $Options.Count, $Default)
        if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
        $n = 0
        if ([int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le $Options.Count) { return $n }
        Write-Host 'Invalid selection, try again.' -ForegroundColor Yellow
    }
}

function Confirm-WinSetupAction {
    <#
    .SYNOPSIS
        Yes/No/Skip confirmation used before any potentially destructive change.
        Non-interactive sessions fall back to $DefaultYes.
    #>
    param(
        [Parameter(Mandatory)][string]$Question,
        [switch]$NonInteractive,
        [bool]$DefaultYes = $false
    )
    if ($NonInteractive) { return $DefaultYes }
    $choice = Read-WinSetupChoice -Title $Question -Options @('Yes', 'No', 'Skip') -Default $(if ($DefaultYes) { 1 } else { 2 })
    return ($choice -eq 1)
}
