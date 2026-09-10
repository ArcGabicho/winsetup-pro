BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Import-Module (Join-Path $script:Root 'modules\Core\Core.psm1') -Force
    Initialize-WinSetupLog -Directory (Join-Path $TestDrive 'logs') -Console $false | Out-Null

    function New-OkComponent {
        param([string]$Id)
        $captured = $Id
        New-WinSetupComponent -Id $Id -Name $Id -Category 'Test' `
            -Test {
                param($c)
                New-WinSetupDetectionResult -Installed (Test-Path -LiteralPath (Join-Path $c.Extra.Dir "$captured.flag"))
            }.GetNewClosure() `
            -Install {
                param($c)
                $c.Extra.Counts[$captured] = [int]$c.Extra.Counts[$captured] + 1
                Set-Content -LiteralPath (Join-Path $c.Extra.Dir "$captured.flag") -Value 'x'
            }.GetNewClosure()
    }
}

Describe 'Journal and -Resume' {

    BeforeEach {
        $script:Dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:Dir -Force | Out-Null

        $boom = New-WinSetupComponent -Id 'boom' -Name 'boom' -Category 'Test' -Critical $true `
            -Test { param($c) New-WinSetupDetectionResult -Installed $false } `
            -Install {
                param($c)
                if (-not $c.Extra.Fixed) { throw 'synthetic critical failure' }
                $c.Extra.Counts['boom'] = [int]$c.Extra.Counts['boom'] + 1
            }

        $script:Reg = [ordered]@{
            'ok1'  = New-OkComponent -Id 'ok1'
            'boom' = $boom
            'ok2'  = New-OkComponent -Id 'ok2'
        }
        $cfg = [ordered]@{ settings = [ordered]@{ errorPolicy = [ordered]@{ critical = 'abort'; nonCritical = 'skip' } } }
        $script:Ctx = New-WinSetupContext -Root $script:Dir -Config $cfg -Interactive $false -Registry $script:Reg
        $script:Ctx | Add-Member -NotePropertyName Extra -NotePropertyValue ([ordered]@{ Dir = $script:Dir; Fixed = $false; Counts = @{} })
    }

    It 'aborts at the critical failure and leaves an incomplete journal' {
        $r = Invoke-WinSetupPlan -Context $script:Ctx -ComponentIds @('ok1', 'boom', 'ok2')
        $r.Aborted | Should -BeTrue
        $r.Failed  | Should -Be 1
        $script:Ctx.Extra.Counts.ContainsKey('ok2') | Should -BeFalse   # never reached

        $journal = Get-WinSetupJournal -Path (Join-Path $script:Ctx.Paths.State 'last-run.json')
        $journal.Completed | Should -BeFalse
        ($journal.Entries | Where-Object { $_.Id -eq 'ok1' }).Status | Should -Be 'Installed'
        ($journal.Entries | Where-Object { $_.Id -eq 'boom' }).Status | Should -Be 'Failed'
        ($journal.Entries | Where-Object { $_.Id -eq 'ok2' }).Status | Should -Be 'Pending'
    }

    It 'resume re-runs only the pending/failed entries and then completes' {
        Invoke-WinSetupPlan -Context $script:Ctx -ComponentIds @('ok1', 'boom', 'ok2') | Out-Null
        $script:Ctx.Extra.Fixed = $true

        $journal = Get-WinSetupJournal -Path (Join-Path $script:Ctx.Paths.State 'last-run.json')
        $pending = @($journal.Entries | Where-Object { $_.Status -in @('Pending', 'Failed') } | ForEach-Object { $_.Id })
        $pending | Should -Be @('boom', 'ok2')

        $r2 = Invoke-WinSetupPlan -Context $script:Ctx -ComponentIds $pending -ResumeJournal $journal
        $r2.Failed | Should -Be 0
        $script:Ctx.Extra.Counts['boom'] | Should -Be 1
        $script:Ctx.Extra.Counts['ok2']  | Should -Be 1

        (Get-WinSetupJournal -Path $journal.Path).Completed | Should -BeTrue
    }

    It 'does not re-run an entry that already succeeded (ok1 stays at install count 1)' {
        Invoke-WinSetupPlan -Context $script:Ctx -ComponentIds @('ok1', 'boom', 'ok2') | Out-Null
        $script:Ctx.Extra.Fixed = $true
        $journal = Get-WinSetupJournal -Path (Join-Path $script:Ctx.Paths.State 'last-run.json')

        # resume with the full list; the engine must skip 'ok1' from the journal
        Invoke-WinSetupPlan -Context $script:Ctx -ComponentIds @('ok1', 'boom', 'ok2') -ResumeJournal $journal | Out-Null
        $script:Ctx.Extra.Counts['ok1'] | Should -Be 1
    }

    It 'a completed run leaves nothing to resume' {
        $script:Ctx.Extra.Fixed = $true
        $r = Invoke-WinSetupPlan -Context $script:Ctx -ComponentIds @('ok1', 'boom', 'ok2')
        $r.Aborted | Should -BeFalse

        $journal = Get-WinSetupJournal -Path (Join-Path $script:Ctx.Paths.State 'last-run.json')
        $journal.Completed | Should -BeTrue
        @($journal.Entries | Where-Object { $_.Status -in @('Pending', 'Failed') }) | Should -BeNullOrEmpty
    }

    It 'a dry run writes a separate journal and never touches last-run.json' {
        $script:Ctx.DryRun = $true
        Invoke-WinSetupPlan -Context $script:Ctx -ComponentIds @('ok1') | Out-Null
        Test-Path (Join-Path $script:Ctx.Paths.State 'last-dryrun.json') | Should -BeTrue
        Test-Path (Join-Path $script:Ctx.Paths.State 'last-run.json')    | Should -BeFalse
    }
}
