BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Import-Module (Join-Path $script:Root 'modules\Core\Core.psm1') -Force
    Initialize-WinSetupLog -Directory (Join-Path $TestDrive 'logs') -Console $false | Out-Null

    function New-EventComponent {
        param([string]$Id, [switch]$Fail)
        $captured = $Id
        $failFlag = [bool]$Fail
        New-WinSetupComponent -Id $Id -Name $Id -Category 'Test' `
            -Test {
                param($c)
                New-WinSetupDetectionResult -Installed (Test-Path -LiteralPath (Join-Path $c.Extra.Dir "$captured.flag"))
            }.GetNewClosure() `
            -Install {
                param($c)
                if ($failFlag) { throw 'synthetic failure' }
                Set-Content -LiteralPath (Join-Path $c.Extra.Dir "$captured.flag") -Value 'x'
            }.GetNewClosure()
    }
}

Describe 'Invoke-WinSetupPlan -EventSink' {

    BeforeEach {
        $script:Dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:Dir -Force | Out-Null
        $script:Reg = [ordered]@{ 'a' = New-EventComponent -Id 'a'; 'b' = New-EventComponent -Id 'b' }
        $script:Ctx = New-WinSetupContext -Root $script:Dir -Config ([ordered]@{ settings = [ordered]@{} }) `
            -Interactive $false -Registry $script:Reg
        $script:Ctx | Add-Member -NotePropertyName Extra -NotePropertyValue ([ordered]@{ Dir = $script:Dir })
        $global:WSP_TestEvents = New-Object System.Collections.Generic.List[object]
        $script:Sink = { param($e) $global:WSP_TestEvents.Add($e) }
    }

    AfterEach { Remove-Variable -Name WSP_TestEvents -Scope Global -ErrorAction SilentlyContinue }

    It 'emits plan_resolved, component_started/completed and run_completed' {
        Invoke-WinSetupPlan -Context $script:Ctx -ComponentIds @('a', 'b') -EventSink $script:Sink | Out-Null
        $types = @($global:WSP_TestEvents | ForEach-Object { $_.type })
        $types | Should -Contain 'plan_resolved'
        $types | Should -Contain 'component_started'
        $types | Should -Contain 'component_completed'
        $types | Should -Contain 'run_completed'
        @($global:WSP_TestEvents | Where-Object { $_.type -eq 'component_started' }).Count | Should -Be 2
        ($global:WSP_TestEvents | Where-Object { $_.type -eq 'run_completed' } | Select-Object -First 1).installed | Should -Be 2
    }

    It 'emits component_failed on a failing component' {
        $script:Reg['b'] = New-EventComponent -Id 'b' -Fail
        $r = Invoke-WinSetupPlan -Context $script:Ctx -ComponentIds @('a', 'b') -EventSink $script:Sink
        @($global:WSP_TestEvents | ForEach-Object { $_.type }) | Should -Contain 'component_failed'
        $r.Failed | Should -Be 1
    }

    It 'behaves identically with no sink (returns the same summary shape)' {
        $r = Invoke-WinSetupPlan -Context $script:Ctx -ComponentIds @('a', 'b')
        $r.Installed | Should -Be 2
        $r.PSObject.Properties.Name | Should -Contain 'Results'
        $r.PSObject.Properties.Name | Should -Contain 'JournalPath'
    }

    It 'a throwing sink never breaks the run' {
        $bad = { param($e) throw 'sink blew up' }
        { Invoke-WinSetupPlan -Context $script:Ctx -ComponentIds @('a') -EventSink $bad } | Should -Not -Throw
        (Test-Path (Join-Path $script:Dir 'a.flag')) | Should -BeTrue
    }
}
