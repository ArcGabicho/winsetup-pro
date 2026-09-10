#Requires -Version 5.1
<#
.SYNOPSIS
    WinSetup Pro - Windows developer setup assistant (composition root / CLI).

.DESCRIPTION
    Turns a declarative profile or component list into an idempotent series of
    detect -> install -> configure steps. This script only wires the CLI to the
    Core engine; all real work lives in modules\.

.EXAMPLE
    .\WinSetup.ps1
    Launches the interactive menu.

.EXAMPLE
    .\WinSetup.ps1 -Profile minimal -DryRun
    Shows what the "minimal" profile would change, without touching the system.

.EXAMPLE
    .\WinSetup.ps1 -Install git

.EXAMPLE
    .\WinSetup.ps1 -Status

.NOTES
    The documented -Profile switch is an alias of the -SetupProfile parameter.
    A parameter literally named Profile would overwrite the process-wide
    automatic $PROFILE variable when a value is bound to it, which breaks the
    PowerShell-profile component; hence the alias.
#>
[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
    # Aliased to -Profile for the documented CLI. The parameter itself is NOT
    # named $Profile: binding a value to a parameter called Profile overwrites
    # the global automatic $PROFILE variable for the whole process.
    [Parameter(ParameterSetName = 'Profile', Mandatory)]
    [Alias('Profile')]
    [string]$SetupProfile,

    [Parameter(ParameterSetName = 'Install', Mandatory)]
    [string[]]$Install,

    [Parameter(ParameterSetName = 'List', Mandatory)]
    [switch]$List,

    [Parameter(ParameterSetName = 'Status', Mandatory)]
    [switch]$Status,

    [Parameter(ParameterSetName = 'Diagnose', Mandatory)]
    [switch]$Diagnose,

    [Parameter(ParameterSetName = 'Resume', Mandatory)]
    [switch]$Resume,

    [Parameter(ParameterSetName = 'Update', Mandatory)]
    [switch]$Update,

    [Parameter(ParameterSetName = 'WSL', Mandatory)]
    [switch]$WSL,

    [Parameter(ParameterSetName = 'Git', Mandatory)]
    [switch]$Git,

    [Parameter(ParameterSetName = 'SSH', Mandatory)]
    [switch]$SSH,

    [Parameter(ParameterSetName = 'Dotfiles', Mandatory)]
    [string]$Dotfiles,

    [Parameter(ParameterSetName = 'DotfilesRepository', Mandatory)]
    [string]$DotfilesRepository,

    [Parameter()][switch]$DryRun,
    [Parameter()][switch]$NonInteractive,
    [Parameter()][string]$ConfigFile,
    [Parameter()][ValidateSet('DEBUG', 'INFO', 'SUCCESS', 'WARNING', 'ERROR')]
    [string]$LogLevel
)

$ErrorActionPreference = 'Stop'
$script:Root = Split-Path -Parent $PSCommandPath
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

Import-Module (Join-Path $script:Root 'modules\Core\Core.psm1') -Force

$script:Interactive = -not $NonInteractive
$script:Operation   = $PSCmdlet.ParameterSetName
$script:ExitCode    = 0

Initialize-WinSetupLog -Directory (Join-Path $script:Root 'logs') `
    -Operation ($script:Operation.ToLower()) `
    -MinLevel ($(if ($LogLevel) { $LogLevel } else { 'INFO' })) | Out-Null

Write-WinSetupLog -Level INFO -Module 'CLI' -Message ("Start: operation={0} dryRun={1} interactive={2}" -f $script:Operation, [bool]$DryRun, $script:Interactive)


function New-CliContext {
    param([string]$ProfileName, [string[]]$InstallOnly)
    $config = Get-WinSetupConfig -Root $script:Root `
        -ProfileName $ProfileName -ConfigPath $ConfigFile `
        -InstallOnly $InstallOnly -LogLevelOverride $LogLevel

    foreach ($issue in (Test-WinSetupConfig -Config $config)) {
        Write-WinSetupLog -Level WARNING -Module 'Config' -Message $issue
    }
    return @{
        Config  = $config
        Context = New-WinSetupContext -Root $script:Root -Config $config -DryRun:([bool]$DryRun) -Interactive:$script:Interactive
    }
}

function Invoke-CliRun {
    param([string]$ProfileName, [string[]]$InstallOnly)

    $built  = New-CliContext -ProfileName $ProfileName -InstallOnly $InstallOnly
    $config = $built.Config
    $ctx    = $built.Context

    $plan = if ($InstallOnly) { @($InstallOnly) } else { Resolve-WinSetupPlan -Config $config }
    if (-not $plan -or $plan.Count -eq 0) {
        Write-Host 'Nothing to do - the resolved plan is empty.' -ForegroundColor Yellow
        return
    }

    Write-Host ('Profile : {0}' -f $(if ($ProfileName) { $ProfileName } else { 'custom' })) -ForegroundColor White
    Write-Host ('Plan    : {0}' -f ($plan -join ', ')) -ForegroundColor DarkGray
    if ($DryRun) { Write-Host 'Mode    : DRY RUN' -ForegroundColor Cyan }
    Write-Host ''

    $result = Invoke-WinSetupPlan -Context $ctx -ComponentIds $plan -ProfileName $ProfileName
    Write-WinSetupSummary -Result $result -DryRun:([bool]$DryRun)

    if ($result.Failed -gt 0 -or $result.Aborted) { $script:ExitCode = 1 }

    $restartPrompt = Get-WinSetupConfigValue -Config $config -Path 'settings.restartPrompt' -Default $true
    if ($restartPrompt -and -not $DryRun -and $result.Installed -gt 0) {
        Write-Host ''
        Write-Host 'A restart is recommended so PATH and environment changes take full effect.' -ForegroundColor Yellow
    }
}

function Invoke-CliDotfiles {
    param([string]$Path, [string]$Repository)

    $config = Get-WinSetupConfig -Root $script:Root -ConfigPath $ConfigFile -LogLevelOverride $LogLevel
    if (-not ($config['dotfiles'] -is [System.Collections.IDictionary])) { $config['dotfiles'] = [ordered]@{} }
    if ($Path)       { $config['dotfiles']['path'] = $Path }
    if ($Repository) { $config['dotfiles']['repository'] = $Repository }

    $ctx = New-WinSetupContext -Root $script:Root -Config $config -DryRun:([bool]$DryRun) -Interactive:$script:Interactive
    Write-Host ('Dotfiles source: {0}' -f $(if ($Repository) { $Repository } else { $Path })) -ForegroundColor White
    Write-Host ''
    $result = Invoke-WinSetupPlan -Context $ctx -ComponentIds @('dotfiles')
    Write-WinSetupSummary -Result $result -DryRun:([bool]$DryRun)
    if ($result.Failed -gt 0 -or $result.Aborted) { $script:ExitCode = 1 }
}

function Invoke-CliResume {
    $journalPath = Join-Path $script:Root 'state\last-run.json'
    $journal = Get-WinSetupJournal -Path $journalPath
    if (-not $journal) { Write-Host 'No previous run found to resume.' -ForegroundColor Yellow; return }
    if ($journal.Completed) { Write-Host 'The previous run already completed - nothing to resume.' -ForegroundColor Green; return }

    $pending = @($journal.Entries | Where-Object { $_.Status -in @('Pending', 'Failed', 'Planned') } | ForEach-Object { $_.Id })
    if (-not $pending -or $pending.Count -eq 0) { Write-Host 'No pending components in the previous run.' -ForegroundColor Green; return }

    $config = Get-WinSetupConfig -Root $script:Root -ProfileName $journal.Profile -ConfigPath $ConfigFile -LogLevelOverride $LogLevel
    $ctx = New-WinSetupContext -Root $script:Root -Config $config -DryRun:([bool]$DryRun) -Interactive:$script:Interactive

    Write-Host ('Resuming: {0}' -f ($pending -join ', ')) -ForegroundColor White
    Write-Host ''
    $result = Invoke-WinSetupPlan -Context $ctx -ComponentIds $pending -ProfileName $journal.Profile -ResumeJournal $journal
    Write-WinSetupSummary -Result $result -DryRun:([bool]$DryRun)
    if ($result.Failed -gt 0 -or $result.Aborted) { $script:ExitCode = 1 }
}

function Invoke-CliList {
    $ctx = (New-CliContext).Context
    $rows = @($ctx.Registry.Values | Sort-Object Category, Id)
    if ($rows.Count -eq 0) { Write-Host 'No components are registered.' -ForegroundColor Yellow; return }
    Write-Host 'Available components:' -ForegroundColor White
    Write-Host ''
    $rows | Format-Table -AutoSize `
        @{ Label = 'Id'; Expression = { $_.Id } },
        @{ Label = 'Name'; Expression = { $_.Name } },
        @{ Label = 'Category'; Expression = { $_.Category } },
        @{ Label = 'Admin'; Expression = { if ($_.RequiresAdmin) { 'yes' } else { '' } } },
        @{ Label = 'Description'; Expression = { $_.Description } } | Out-Host
}

function Invoke-CliStatus {
    $ctx = (New-CliContext).Context
    $sys = $ctx.System

    Write-Host 'WinSetup Pro - System Status' -ForegroundColor White
    Write-Host ''
    Write-WinSetupStatusLine -Name 'Windows'        -Ok ($sys.OsCaption -match 'Windows (10|11)') -Detail $sys.OsCaption
    Write-WinSetupStatusLine -Name 'PowerShell 7'   -Ok ($PSVersionTable.PSVersion.Major -ge 7)   -Detail ("v$($sys.PSVersion)")
    Write-WinSetupStatusLine -Name 'winget'         -Ok $sys.WingetPresent                        -Detail ([string]$sys.WingetVersion)
    Write-WinSetupStatusLine -Name 'Administrator'  -Ok $sys.IsAdmin                              -Detail $(if ($sys.IsAdmin) { 'elevated' } else { 'not elevated' })
    Write-Host ''

    $rows = Get-WinSetupStatus -Context $ctx
    $ready = 0
    foreach ($row in $rows) {
        $ok = $row.Installed -and $row.Configured
        if ($ok) { $ready++ }
        $detail = if ($row.Version) { "v$($row.Version)" } elseif ($row.Summary) { $row.Summary } else { '' }
        Write-WinSetupStatusLine -Name $row.Name -Ok $ok -Detail $detail
    }
    Write-Host ''
    Write-Host ('{0} / {1} components configured' -f $ready, $rows.Count) -ForegroundColor White
    if ($rows.Count -gt 0 -and $ready -lt $rows.Count) { $script:ExitCode = 1 }
}

function Invoke-CliDiagnose {
    $ctx = (New-CliContext).Context
    Write-Host 'WinSetup Pro - Diagnostics' -ForegroundColor White
    Write-Host ''
    $checks = Get-WinSetupDiagnostics -Context $ctx
    foreach ($check in $checks) { Write-WinSetupStatusLine -Name $check.Name -Ok $check.Ok -Detail $check.Detail }
    $failed = @($checks | Where-Object { -not $_.Ok })
    Write-Host ''
    if ($failed.Count -gt 0) {
        Write-Host ('{0} check(s) need attention.' -f $failed.Count) -ForegroundColor Yellow
        $script:ExitCode = 1
    } else {
        Write-Host 'All readiness checks passed.' -ForegroundColor Green
    }
}

function Invoke-CliInteractiveMenu {
    if (-not $script:Interactive) {
        # No operation requested and no console to drive a menu: show status and
        # usage rather than silently applying anything.
        Write-Host 'No operation specified. Nothing was changed.' -ForegroundColor Yellow
        Write-Host ''
        Invoke-CliStatus
        Write-Host ''
        Write-Host 'Run one of: -Profile <name> | -Install <ids> | -List | -Status | -Diagnose | -Resume  (add -DryRun to preview)' -ForegroundColor DarkGray
        return
    }

    $choice = Read-WinSetupChoice -Title 'What would you like to do?' -Options @(
        'Run a profile'
        'Show component status'
        'List available components'
        'Run system diagnostics'
        'Exit'
    ) -Default 1 -NonInteractive:(-not $script:Interactive)

    switch ($choice) {
        1 {
            $profiles = @(Get-ChildItem (Join-Path $script:Root 'profiles') -Filter '*.json' -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty BaseName)
            if ($profiles.Count -eq 0) { Write-Host 'No profiles found in profiles\.' -ForegroundColor Yellow; return }

            $pick = Read-WinSetupChoice -Title 'Select a profile' -Options $profiles -Default 1 -NonInteractive:(-not $script:Interactive)

            if ($script:Interactive -and -not $DryRun) {
                $mode = Read-WinSetupChoice -Title 'Execution mode' -Options @('Dry run (preview only)', 'Apply changes') -Default 1
                if ($mode -eq 1) { $script:DryRun = [switch]$true }
            }
            Invoke-CliRun -ProfileName $profiles[$pick - 1]
        }
        2 { Invoke-CliStatus }
        3 { Invoke-CliList }
        4 { Invoke-CliDiagnose }
        default { Write-Host 'Nothing to do. Bye.' -ForegroundColor DarkGray }
    }
}


Write-WinSetupBanner

try {
    switch ($script:Operation) {
        'List'     { Invoke-CliList }
        'Status'   { Invoke-CliStatus }
        'Diagnose' { Invoke-CliDiagnose }
        'Resume'   { Invoke-CliResume }
        'Update'   {
            Write-Host 'Self-update arrives in a later phase (Phase 5).' -ForegroundColor Yellow
            Write-Host 'For now, update with: git pull' -ForegroundColor DarkGray
        }
        'Profile'  { Invoke-CliRun -ProfileName $SetupProfile }
        'Install'  { Invoke-CliRun -InstallOnly $Install }
        'WSL'      { Invoke-CliRun -InstallOnly @('wsl') }
        'Git'      { Invoke-CliRun -InstallOnly @('git') }
        'SSH'      { Invoke-CliRun -InstallOnly @('ssh') }
        'Dotfiles'           { Invoke-CliDotfiles -Path $Dotfiles }
        'DotfilesRepository' { Invoke-CliDotfiles -Repository $DotfilesRepository }
        default    { Invoke-CliInteractiveMenu }
    }
}
catch {
    Write-WinSetupLog -Level ERROR -Module 'CLI' -Message $_.Exception.Message
    Write-Host ''
    Write-Host ('ERROR: {0}' -f $_.Exception.Message) -ForegroundColor Red
    $script:ExitCode = 2
}

Write-Host ''
Write-WinSetupLog -Level INFO -Module 'CLI' -Message ("Finished with exit code {0}" -f $script:ExitCode)
exit $script:ExitCode
