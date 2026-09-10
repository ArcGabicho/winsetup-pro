BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Import-Module (Join-Path $script:Root 'modules\Core\Core.psm1') -Force
    Initialize-WinSetupLog -Directory (Join-Path $TestDrive 'logs') -Console $false | Out-Null
}

Describe 'Setup engine' {

    BeforeEach {
        $flag = Join-Path $TestDrive ([guid]::NewGuid().ToString() + '.flag')
        $script:Flag = $flag

        $dummy = New-WinSetupComponent -Id 'dummy' -Name 'Dummy Tool' -Category 'Test' `
            -Test {
                param($Context)
                $present = Test-Path -LiteralPath $Context.Extra.Flag
                New-WinSetupDetectionResult -Installed $present -Configured $present -Version '1.0'
            } `
            -Install {
                param($Context)
                $Context.Extra.InstallCount++
                Set-Content -LiteralPath $Context.Extra.Flag -Value 'installed'
            }

        $failing = New-WinSetupComponent -Id 'boom' -Name 'Failing Tool' -Category 'Test' `
            -Test  { param($Context) New-WinSetupDetectionResult -Installed $false } `
            -Install { param($Context) throw 'synthetic install failure' }

        $registry = [ordered]@{ dummy = $dummy; boom = $failing }
        $config   = [ordered]@{
            applications = @()
            settings     = [ordered]@{ errorPolicy = [ordered]@{ critical = 'abort'; nonCritical = 'skip' } }
        }

        $script:Ctx = New-WinSetupContext -Root $TestDrive -Config $config -Interactive $false -Registry $registry
        $script:Ctx | Add-Member -NotePropertyName Extra -NotePropertyValue ([ordered]@{ Flag = $flag; InstallCount = 0 })
    }

    It 'installs a component that is missing' {
        $r = Invoke-WinSetupPlan -Context $script:Ctx -ComponentIds @('dummy')
        $r.Installed | Should -Be 1
        $script:Ctx.Extra.InstallCount | Should -Be 1
        Test-Path $script:Flag | Should -BeTrue
    }

    It 'is idempotent: a second run installs nothing' {
        Invoke-WinSetupPlan -Context $script:Ctx -ComponentIds @('dummy') | Out-Null
        $r2 = Invoke-WinSetupPlan -Context $script:Ctx -ComponentIds @('dummy')
        $r2.Installed | Should -Be 0
        $r2.Skipped   | Should -Be 1
        $script:Ctx.Extra.InstallCount | Should -Be 1
    }

    It 'makes no changes in dry-run mode' {
        $script:Ctx.DryRun = $true
        $r = Invoke-WinSetupPlan -Context $script:Ctx -ComponentIds @('dummy')
        $r.DryRun | Should -BeTrue
        $script:Ctx.Extra.InstallCount | Should -Be 0
        Test-Path $script:Flag | Should -BeFalse
    }

    It 'skips unknown component ids without failing' {
        $r = Invoke-WinSetupPlan -Context $script:Ctx -ComponentIds @('dummy', 'ghost')
        $r.Unknown | Should -Contain 'ghost'
        $r.Failed  | Should -Be 0
        $r.Installed | Should -Be 1
    }

    It 'applies the non-interactive error policy (skip) for a non-critical failure' {
        $r = Invoke-WinSetupPlan -Context $script:Ctx -ComponentIds @('boom', 'dummy')
        $r.Failed    | Should -Be 1
        $r.Aborted   | Should -BeFalse
        $r.Installed | Should -Be 1   # 'dummy' still ran after 'boom' was skipped
    }

    It 'writes a resumable journal' {
        Invoke-WinSetupPlan -Context $script:Ctx -ComponentIds @('dummy') | Out-Null
        $journalPath = Join-Path $script:Ctx.Paths.State 'last-run.json'
        $journalPath | Should -Exist
        $j = Get-WinSetupJournal -Path $journalPath
        $j.Completed | Should -BeTrue
        ($j.Entries | Where-Object Id -eq 'dummy').Status | Should -Be 'Installed'
    }
}

Describe 'Resolve-WinSetupComponentOrder' {

    It 'places dependencies before their dependants' {
        $a = New-WinSetupComponent -Id 'a' -Name 'A' -Category 'T' -DependsOn @('b') -Test { New-WinSetupDetectionResult -Installed $true }
        $b = New-WinSetupComponent -Id 'b' -Name 'B' -Category 'T' -Test { New-WinSetupDetectionResult -Installed $true }
        $reg = [ordered]@{ a = $a; b = $b }
        (Resolve-WinSetupComponentOrder -Registry $reg -Ids @('a'))[0] | Should -Be 'b'
    }

    It 'throws on a circular dependency' {
        $a = New-WinSetupComponent -Id 'a' -Name 'A' -Category 'T' -DependsOn @('b') -Test { New-WinSetupDetectionResult -Installed $true }
        $b = New-WinSetupComponent -Id 'b' -Name 'B' -Category 'T' -DependsOn @('a') -Test { New-WinSetupDetectionResult -Installed $true }
        $reg = [ordered]@{ a = $a; b = $b }
        { Resolve-WinSetupComponentOrder -Registry $reg -Ids @('a') } | Should -Throw
    }
}

Describe 'Component discovery' {

    It 'loads the shipped Git component from modules\' {
        $reg = Import-WinSetupComponents -Path (Join-Path $script:Root 'modules')
        $reg.Contains('git') | Should -BeTrue
        $reg['git'].Category | Should -Be 'Development'
    }

    It 'does not treat Core engine files as components' {
        $reg = Import-WinSetupComponents -Path (Join-Path $script:Root 'modules')
        $reg.Contains('engine') | Should -BeFalse
    }
}
