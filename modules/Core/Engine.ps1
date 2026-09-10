# Engine.ps1 - the Setup Engine.
#
# Responsibilities:
#   * build an execution Context (paths, config, system snapshot, registry)
#   * turn a list of component ids into an ordered plan
#   * for each component: detect state -> decide action -> execute (or simulate)
#   * enforce dry-run, idempotency, admin gating and the error policy
#   * record progress to a resumable journal and return a summary

function New-WinSetupContext {
    <#
    .SYNOPSIS
        Creates the immutable-ish execution context shared by every component.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Config,
        [bool]$DryRun = $false,
        [bool]$Interactive = $true,
        [System.Collections.IDictionary]$Registry
    )

    $paths = [ordered]@{
        Root      = $Root
        Config    = Join-Path $Root 'config'
        Modules   = Join-Path $Root 'modules'
        Profiles  = Join-Path $Root 'profiles'
        Templates = Join-Path $Root 'templates'
        Logs      = Join-Path $Root 'logs'
        State     = Join-Path $Root 'state'
        Backup    = Join-Path $Root 'backup'
    }
    foreach ($dir in @($paths.Logs, $paths.State, $paths.Backup)) {
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            try { New-Item -ItemType Directory -Path $dir -Force | Out-Null } catch { }
        }
    }

    if (-not $Registry) {
        $Registry = Import-WinSetupComponents -Path $paths.Modules
    }

    [pscustomobject]@{
        Root        = $Root
        Paths       = $paths
        Config      = $Config
        DryRun      = [bool]$DryRun
        Interactive = [bool]$Interactive
        Registry    = $Registry
        System      = Get-WinSetupSystemInfo
        IsAdmin     = Test-WinSetupAdmin
        Answers     = @{}
        StartedUtc  = (Get-Date).ToUniversalTime()
    }
}

function Get-WinSetupStatus {
    <#
    .SYNOPSIS
        Runs every component's (read-only) Test block and returns status rows.
    #>
    param(
        [Parameter(Mandatory)]$Context,
        [string[]]$ComponentIds
    )

    $ids = if ($ComponentIds) { $ComponentIds } else { @($Context.Registry.Keys) }
    $rows = New-Object System.Collections.Generic.List[object]

    foreach ($id in $ids) {
        $component = $Context.Registry[$id]
        if (-not $component) { continue }
        $detection = $null
        try { $detection = & $component.Test $Context } catch {
            Write-WinSetupLog -Level WARNING -Module $id -Message ("Detection failed: {0}" -f $_.Exception.Message)
        }
        if (-not $detection) { $detection = New-WinSetupDetectionResult -Installed $false }
        $rows.Add([pscustomobject]@{
            Id         = $component.Id
            Name       = $component.Name
            Category   = $component.Category
            Installed  = [bool]$detection.Installed
            Configured = [bool]$detection.Configured
            Version    = $detection.Version
            Summary    = $detection.Summary
        })
    }
    return $rows.ToArray()
}

function Invoke-WinSetupPlan {
    <#
    .SYNOPSIS
        Executes (or simulates) a plan of component ids and returns a summary.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string[]]$ComponentIds,
        [string]$ProfileName,
        $ResumeJournal
    )

    $requested = @($ComponentIds | ForEach-Object { $_.ToString().ToLowerInvariant() } | Select-Object -Unique)
    $known     = @($requested | Where-Object { $Context.Registry.Contains($_) })
    $unknown   = @($requested | Where-Object { -not $Context.Registry.Contains($_) })

    foreach ($u in $unknown) {
        Write-WinSetupLog -Level WARNING -Module 'Engine' -Message ("Component '{0}' is not available in this build - skipped." -f $u)
        Write-WinSetupStep -Label $u -Status 'skip' -Detail 'not available yet'
    }

    if ($known.Count -eq 0) {
        Write-WinSetupLog -Level WARNING -Module 'Engine' -Message 'No known components in the plan.'
        return [pscustomobject]@{
            Total = 0; Installed = 0; Configured = 0; Skipped = 0; Failed = 0; Planned = 0
            DryRun = $Context.DryRun; Aborted = $false; Results = @(); Unknown = $unknown; JournalPath = $null
        }
    }

    $ordered = Resolve-WinSetupComponentOrder -Registry $Context.Registry -Ids $known

    $journalPath = if ($Context.DryRun) {
        Join-Path $Context.Paths.State 'last-dryrun.json'
    } else {
        Join-Path $Context.Paths.State 'last-run.json'
    }
    $journal = if ($ResumeJournal) {
        $ResumeJournal
    } else {
        New-WinSetupJournal -Path $journalPath -ProfileName $ProfileName -ComponentIds $ordered -DryRun $Context.DryRun
    }
    Save-WinSetupJournal -Journal $journal

    $results = New-Object System.Collections.Generic.List[object]
    $total   = $ordered.Count
    $index   = 0
    $aborted = $false

    foreach ($id in $ordered) {
        $index++
        $component = $Context.Registry[$id]
        $entry = $journal.Entries | Where-Object { $_.Id -eq $id } | Select-Object -First 1

        if ($ResumeJournal -and $entry -and $entry.Status -in @('Installed', 'Configured', 'Skipped')) {
            Write-WinSetupStep -Index $index -Total $total -Label $component.Name -Status 'skip' -Detail 'already completed in the previous run'
            continue
        }

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        # Real runs skip an admin-only component when not elevated. Dry runs still
        # show what it would do, flagged as needing elevation.
        if ($component.RequiresAdmin -and -not $Context.IsAdmin -and -not $Context.DryRun) {
            $stopwatch.Stop()
            Write-WinSetupStep -Index $index -Total $total -Label $component.Name -Status 'warn' -Detail 'requires an elevated session - skipped'
            Update-WinSetupJournalEntry -Journal $journal -Id $id -Status 'Skipped' -Action 'skip-noadmin' -DurationMs $stopwatch.ElapsedMilliseconds
            $results.Add([pscustomobject]@{ Id = $id; Name = $component.Name; Action = 'SkipNoAdmin'; Error = $null; DurationMs = $stopwatch.ElapsedMilliseconds })
            continue
        }
        $adminNote = if ($component.RequiresAdmin -and -not $Context.IsAdmin) { ' (needs elevation)' } else { '' }

        $detection = $null
        try { $detection = & $component.Test $Context } catch {
            Write-WinSetupLog -Level WARNING -Module $id -Message ("Detection failed: {0}" -f $_.Exception.Message)
        }
        if (-not $detection) { $detection = New-WinSetupDetectionResult -Installed $false }

        $needInstall   = (-not $detection.Installed) -and ($null -ne $component.Install)
        $needConfigure = ($detection.Installed -or $needInstall) -and ($null -ne $component.Configure) -and ((-not $detection.Configured) -or $needInstall)

        if (-not $needInstall -and -not $needConfigure) {
            $stopwatch.Stop()
            $detailText = if ($detection.Version) { "already present (v$($detection.Version))" } else { 'already configured' }
            Write-WinSetupStep -Index $index -Total $total -Label $component.Name -Status 'skip' -Detail $detailText
            Update-WinSetupJournalEntry -Journal $journal -Id $id -Status 'Skipped' -Action 'skip' -DurationMs $stopwatch.ElapsedMilliseconds
            $results.Add([pscustomobject]@{ Id = $id; Name = $component.Name; Action = 'Skip'; Error = $null; DurationMs = $stopwatch.ElapsedMilliseconds })
            continue
        }

        if ($Context.DryRun) {
            $stopwatch.Stop()
            $planned = @()
            if ($needInstall)   { $planned += 'INSTALL' }
            if ($needConfigure) { $planned += 'CONFIGURE' }
            Write-WinSetupStep -Index $index -Total $total -Label $component.Name -Status 'dry' -Detail (($planned -join ' + ') + $adminNote)
            Update-WinSetupJournalEntry -Journal $journal -Id $id -Status 'Planned' -Action ($planned -join '+') -DurationMs $stopwatch.ElapsedMilliseconds
            $results.Add([pscustomobject]@{ Id = $id; Name = $component.Name; Action = ('DryRun:' + ($planned -join '+')); Error = $null; DurationMs = $stopwatch.ElapsedMilliseconds })
            continue
        }

        Write-WinSetupStep -Index $index -Total $total -Label $component.Name -Status 'run'
        $succeeded = $false
        $action    = 'Skip'

        while ($true) {
            try {
                if ($needInstall) {
                    Write-WinSetupLog -Level INFO -Module $id -Message 'Installing...'
                    & $component.Install $Context
                    $action = 'Install'
                }
                if ($needConfigure) {
                    Write-WinSetupLog -Level INFO -Module $id -Message 'Configuring...'
                    & $component.Configure $Context
                    if ($action -ne 'Install') { $action = 'Configure' }
                }
                $succeeded = $true
                break
            } catch {
                $decision = Resolve-WinSetupError -Context $Context -Component $component -ErrorRecord $_
                if ($decision -eq 'retry') { continue }
                $action = 'Fail'
                if ($decision -eq 'abort') { $aborted = $true }
                break
            }
        }
        $stopwatch.Stop()

        if ($succeeded) {
            $post = $null
            try { $post = & $component.Test $Context } catch { }
            $status = if ($action -eq 'Install') { 'Installed' } else { 'Configured' }
            $detailText = if ($post -and $post.Version) { "v$($post.Version)" } else { $status.ToLowerInvariant() }
            Write-WinSetupStep -Index $index -Total $total -Label $component.Name -Status 'ok' -Detail $detailText
            Update-WinSetupJournalEntry -Journal $journal -Id $id -Status $status -Action $action -DurationMs $stopwatch.ElapsedMilliseconds
            $results.Add([pscustomobject]@{ Id = $id; Name = $component.Name; Action = $status; Error = $null; DurationMs = $stopwatch.ElapsedMilliseconds })
        }
        else {
            Write-WinSetupStep -Index $index -Total $total -Label $component.Name -Status 'fail' -Detail 'see session log for details'
            Update-WinSetupJournalEntry -Journal $journal -Id $id -Status 'Failed' -Action 'fail' -ErrorText 'operation failed' -DurationMs $stopwatch.ElapsedMilliseconds
            $results.Add([pscustomobject]@{ Id = $id; Name = $component.Name; Action = 'Fail'; Error = 'operation failed'; DurationMs = $stopwatch.ElapsedMilliseconds })
        }

        if ($aborted) {
            Write-WinSetupLog -Level ERROR -Module 'Engine' -Message 'Run aborted (error policy or user choice).'
            break
        }
    }

    if (-not $aborted) {
        $journal.Completed = $true
        Save-WinSetupJournal -Journal $journal
    }

    $arr = $results.ToArray()
    [pscustomobject]@{
        Total       = $arr.Count
        Installed   = @($arr | Where-Object { $_.Action -eq 'Installed' }).Count
        Configured  = @($arr | Where-Object { $_.Action -eq 'Configured' }).Count
        Skipped     = @($arr | Where-Object { $_.Action -in @('Skip', 'SkipNoAdmin') }).Count
        Failed      = @($arr | Where-Object { $_.Action -eq 'Fail' }).Count
        Planned     = @($arr | Where-Object { $_.Action -like 'DryRun:*' }).Count
        DryRun      = $Context.DryRun
        Aborted     = $aborted
        Results     = $arr
        Unknown     = $unknown
        JournalPath = $journal.Path
    }
}
