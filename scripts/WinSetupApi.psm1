# WinSetupApi.psm1 - the JSON adapter as an in-process, testable function.
#
# Invoke-WinSetupApi returns a [pscustomobject] { ok; data; error } (never
# writes to the console). winsetup-api.ps1 is the thin transport wrapper that
# serializes it; tests call this module directly.
#
# NO install / configure logic lives here - it only shapes engine results.

$script:ApiVersion = 1

$script:BackupHints = @{
    'git'                = '~/.gitconfig'
    'ssh'                = '~/.ssh/config'
    'wsl'                = '~/.wslconfig'
    'powershell-profile' = '$PROFILE'
    'env-vars'           = 'environment snapshot (backup/environment/)'
    'dotfiles'           = 'each replaced file (backup/dotfiles/)'
}
$script:PreserveNotes = @(
    'Existing Git identity (user.name / user.email)',
    'Existing SSH private keys',
    'Existing files (backed up, then replaced only when different)',
    'Content of your $PROFILE outside the WinSetup Pro managed block'
)

function Get-WinSetupApiVersion { return $script:ApiVersion }

function New-ApiResult {
    param($Data, [string]$ErrorText)
    if ($PSBoundParameters.ContainsKey('ErrorText')) {
        return [pscustomobject]@{ ok = $false; data = $null; error = $ErrorText }
    }
    return [pscustomobject]@{ ok = $true; data = $Data; error = $null }
}

function Invoke-WinSetupApi {
    <#
    .SYNOPSIS
        Executes one API verb against the engine and returns { ok; data; error }.
    .PARAMETER EventSink
        For 'apply' / 'resume': a scriptblock invoked per engine lifecycle event.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('version', 'system', 'diagnose', 'profiles', 'components',
            'status', 'plan', 'apply', 'journal', 'resume', 'export', 'import')]
        [string]$Verb,

        [string]$Root,
        $Payload,
        [string]$Path,
        [scriptblock]$EventSink
    )

    if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
    if ($Payload -is [string] -and $Payload) { $Payload = $Payload | ConvertFrom-Json }
    if ($null -eq $Payload) { $Payload = [pscustomobject]@{} }

    Import-Module (Join-Path $Root 'modules\Core\Core.psm1') -Force -Verbose:$false
    if (-not (Test-WinSetupConsole)) { } # touch export
    $null = Initialize-WinSetupLog -Directory (Join-Path $Root 'logs') -Operation ("api-" + $Verb) -Console $false
    Set-WinSetupLogConsole $false

    $newContext = {
        param($ProfileName, $ConfigPath, $InstallOnly, $DryRun)
        $config = Get-WinSetupConfig -Root $Root -ProfileName $ProfileName -ConfigPath $ConfigPath -InstallOnly $InstallOnly
        [pscustomobject]@{
            Config  = $config
            Context = New-WinSetupContext -Root $Root -Config $config -DryRun:([bool]$DryRun) -Interactive:$false
        }
    }
    $planIds = {
        param($Pl, $Config)
        $explicit = @()
        if ($Pl.components) { $explicit = @($Pl.components | Where-Object { $_ }) }
        if ($explicit.Count -gt 0) { return $explicit }
        return @(Resolve-WinSetupPlan -Config $Config)
    }

    try {
        switch ($Verb) {

            'version' { return New-ApiResult -Data ([ordered]@{ apiVersion = $script:ApiVersion; root = $Root }) }

            'system' {
                $sys = Get-WinSetupSystemInfo
                $sys | Add-Member -NotePropertyName Internet -NotePropertyValue (Test-WinSetupInternet) -Force
                return New-ApiResult -Data $sys
            }

            'diagnose' {
                $ctx = (& $newContext $null $null $null $false).Context
                return New-ApiResult -Data (Get-WinSetupDiagnostics -Context $ctx)
            }

            'profiles' {
                $rows = New-Object System.Collections.Generic.List[object]
                $registry = (& $newContext $null $null $null $false).Context.Registry
                foreach ($file in (Get-ChildItem (Join-Path $Root 'profiles') -Filter '*.json' -ErrorAction SilentlyContinue | Sort-Object Name)) {
                    try {
                        $cfg = Get-WinSetupConfig -Root $Root -ProfileName $file.BaseName
                        $raw = Read-WinSetupJsonFile -Path $file.FullName
                        $plan = @(Resolve-WinSetupPlan -Config $cfg)
                        $unknown = @($plan | Where-Object { -not $registry.Contains($_) })
                        $rows.Add([ordered]@{
                            name = $file.BaseName; description = [string]$raw['description']
                            componentCount = $plan.Count; components = $plan; unknown = $unknown
                            compatible = ($unknown.Count -eq 0)
                        })
                    } catch {
                        $rows.Add([ordered]@{ name = $file.BaseName; error = $_.Exception.Message; compatible = $false })
                    }
                }
                return New-ApiResult -Data $rows.ToArray()
            }

            'components' {
                $profileName = if ($Payload.profile) { [string]$Payload.profile } else { $null }
                $built = & $newContext $profileName $null $null $false
                $ctx = $built.Context
                $inPlan = @(& $planIds $Payload $built.Config)
                $status = @{}
                foreach ($row in (Get-WinSetupStatus -Context $ctx)) { $status[$row.Id] = $row }

                $rows = New-Object System.Collections.Generic.List[object]
                foreach ($component in ($ctx.Registry.Values | Sort-Object Category, Id)) {
                    $s = $status[$component.Id]
                    $state =
                        if (-not $s) { 'Unknown' }
                        elseif ($s.Installed -and $s.Configured) { 'Installed' }
                        elseif ($s.Installed) { 'NeedsConfiguration' }
                        else { 'Missing' }
                    if ($component.RequiresAdmin -and $state -ne 'Installed') { $state = 'RequiresAdministrator' }
                    $rows.Add([ordered]@{
                        id = $component.Id; name = $component.Name; category = $component.Category
                        description = $component.Description; requiresAdmin = [bool]$component.RequiresAdmin
                        critical = [bool]$component.Critical; dependsOn = @($component.DependsOn)
                        selected = ($inPlan -contains $component.Id); state = $state
                        installed = [bool]($s -and $s.Installed); configured = [bool]($s -and $s.Configured)
                        version = if ($s) { $s.Version } else { $null }
                        summary = if ($s) { $s.Summary } else { $null }
                    })
                }
                return New-ApiResult -Data $rows.ToArray()
            }

            'status' {
                $ctx = (& $newContext $null $null $null $false).Context
                return New-ApiResult -Data (Get-WinSetupStatus -Context $ctx)
            }

            'plan' {
                $profileName = if ($Payload.profile) { [string]$Payload.profile } else { $null }
                $configPath = if ($Payload.configFile) { [string]$Payload.configFile } else { $null }
                $built = & $newContext $profileName $configPath $null $true
                $ids = @(& $planIds $Payload $built.Config)
                $result = Invoke-WinSetupPlan -Context $built.Context -ComponentIds $ids -ProfileName $profileName

                $changes = foreach ($r in $result.Results) {
                    $a = [string]$r.Action
                    $action =
                        if ($a -like 'DryRun:*INSTALL*CONFIGURE*') { 'install+configure' }
                        elseif ($a -like 'DryRun:*INSTALL*')        { 'install' }
                        elseif ($a -like 'DryRun:*CONFIGURE*')      { 'configure' }
                        elseif ($a -eq 'Skip')                      { 'skip' }
                        elseif ($a -eq 'SkipNoAdmin')               { 'skip (needs elevation)' }
                        else                                        { $a }
                    [ordered]@{
                        component = $r.Id; name = $r.Name; action = $action
                        requiresAdmin = [bool]($built.Context.Registry[$r.Id].RequiresAdmin)
                    }
                }
                $requiresAdmin = @($changes | Where-Object { $_.requiresAdmin -and $_.action -notlike 'skip*' } | ForEach-Object { $_.component })
                $backups = @($ids | Where-Object { $script:BackupHints.ContainsKey($_) } |
                    ForEach-Object { [ordered]@{ component = $_; file = $script:BackupHints[$_] } })

                return New-ApiResult -Data ([ordered]@{
                    profile = $profileName; dryRun = $true; changes = @($changes)
                    counts = [ordered]@{ planned = $result.Planned; skip = $result.Skipped; total = $result.Total }
                    requiresAdmin = $requiresAdmin; backups = $backups; preserve = $script:PreserveNotes
                    unknown = @($result.Unknown); journalPath = $result.JournalPath
                })
            }

            { $_ -in @('apply', 'resume') } {
                $profileName = if ($Payload.profile) { [string]$Payload.profile } else { $null }
                $configPath = if ($Payload.configFile) { [string]$Payload.configFile } else { $null }
                $sink = if ($EventSink) { $EventSink } else { { param($e) } }

                if ($Verb -eq 'resume') {
                    $journal = Get-WinSetupJournal -Path (Join-Path $Root 'state\last-run.json')
                    if (-not $journal) { return New-ApiResult -ErrorText 'No previous run to resume.' }
                    if ($journal.Completed) { return New-ApiResult -Data ([ordered]@{ nothingToResume = $true }) }
                    $pending = @($journal.Entries | Where-Object { $_.Status -in @('Pending', 'Failed', 'Planned') } | ForEach-Object { $_.Id })
                    if ($pending.Count -eq 0) { return New-ApiResult -Data ([ordered]@{ nothingToResume = $true }) }
                    $built = & $newContext $journal.Profile $configPath $null $false
                    $result = Invoke-WinSetupPlan -Context $built.Context -ComponentIds $pending -ProfileName $journal.Profile -ResumeJournal $journal -EventSink $sink
                }
                else {
                    $built = & $newContext $profileName $configPath $null $false
                    $ids = @(& $planIds $Payload $built.Config)
                    $result = Invoke-WinSetupPlan -Context $built.Context -ComponentIds $ids -ProfileName $profileName -EventSink $sink
                }

                return New-ApiResult -Data ([ordered]@{
                    total = $result.Total; installed = $result.Installed; configured = $result.Configured
                    skipped = $result.Skipped; failed = $result.Failed; aborted = [bool]$result.Aborted
                    journalPath = $result.JournalPath
                    results = @($result.Results | ForEach-Object { [ordered]@{ component = $_.Id; action = $_.Action; error = $_.Error; durationMs = $_.DurationMs } })
                })
            }

            'journal' {
                $j = Get-WinSetupJournal -Path (Join-Path $Root 'state\last-run.json')
                if (-not $j) { return New-ApiResult -Data $null }
                $completed = @($j.Entries | Where-Object { $_.Status -in @('Installed', 'Configured', 'Skipped') }).Count
                $pending = @($j.Entries | Where-Object { $_.Status -in @('Pending', 'Planned') }).Count
                $failed = @($j.Entries | Where-Object { $_.Status -eq 'Failed' }).Count
                return New-ApiResult -Data ([ordered]@{
                    profile = $j.Profile; dryRun = [bool]$j.DryRun
                    startedUtc = $j.StartedUtc; updatedUtc = $j.UpdatedUtc; completed = [bool]$j.Completed
                    counts = [ordered]@{ completed = $completed; pending = $pending; failed = $failed }
                    entries = @($j.Entries | ForEach-Object { [ordered]@{ id = $_.Id; status = $_.Status; action = $_.Action; error = $_.Error } })
                    resumable = (-not $j.Completed -and ($pending + $failed) -gt 0)
                })
            }

            'export' {
                if (-not $Path) { return New-ApiResult -ErrorText '-Path is required for export.' }
                $profileName = if ($Payload.profile) { [string]$Payload.profile } else { $null }
                $config = Get-WinSetupConfig -Root $Root -ProfileName $profileName -InstallOnly ($Payload.components)
                ($config | ConvertTo-Json -Depth 12) | Set-Content -LiteralPath $Path -Encoding utf8
                return New-ApiResult -Data ([ordered]@{ written = $Path })
            }

            'import' {
                if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return New-ApiResult -ErrorText "File not found: $Path" }
                $config = Read-WinSetupJsonFile -Path $Path
                $issues = @(Test-WinSetupConfig -Config $config)
                return New-ApiResult -Data ([ordered]@{ valid = ($issues.Count -eq 0); issues = $issues; plan = @(Resolve-WinSetupPlan -Config $config) })
            }
        }
    }
    catch {
        try { Write-WinSetupLog -Level ERROR -Module 'api' -Message $_.Exception.Message } catch { }
        return New-ApiResult -ErrorText $_.Exception.Message
    }
}

Export-ModuleMember -Function 'Invoke-WinSetupApi', 'Get-WinSetupApiVersion'
