BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Import-Module (Join-Path $script:Root 'modules\Core\Core.psm1') -Force
    Initialize-WinSetupLog -Directory (Join-Path $TestDrive 'logs') -Console $false | Out-Null
    $script:Registry = Import-WinSetupComponents -Path (Join-Path $script:Root 'modules')

    # Synthetic component whose Install/Configure record how often they run and
    # whose Test is a real file check - so the engine's detect->act loop is
    # exercised for real.
    function New-SyntheticComponent {
        param([string]$Id)
        $captured = $Id
        New-WinSetupComponent -Id $Id -Name $Id -Category 'Test' `
            -Test {
                param($c)
                $present = Test-Path -LiteralPath (Join-Path $c.Extra.Dir "$captured.flag")
                New-WinSetupDetectionResult -Installed $present -Configured $present -Version '1'
            }.GetNewClosure() `
            -Install {
                param($c)
                $c.Extra.Counts["$captured/install"] = [int]$c.Extra.Counts["$captured/install"] + 1
                Set-Content -LiteralPath (Join-Path $c.Extra.Dir "$captured.flag") -Value 'x'
            }.GetNewClosure() `
            -Configure {
                param($c)
                $c.Extra.Counts["$captured/configure"] = [int]$c.Extra.Counts["$captured/configure"] + 1
            }.GetNewClosure()
    }

    function New-SyntheticContext {
        param([System.Collections.IDictionary]$Registry, [string]$Dir)
        $ctx = New-WinSetupContext -Root $Dir -Config ([ordered]@{ settings = [ordered]@{} }) `
            -Interactive $false -Registry $Registry
        $ctx | Add-Member -NotePropertyName Extra -NotePropertyValue ([ordered]@{ Dir = $Dir; Counts = @{} })
        return $ctx
    }
}

Describe 'End-to-end idempotency (engine)' {

    BeforeEach {
        $script:Dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:Dir -Force | Out-Null
        $script:Reg = [ordered]@{}
        foreach ($id in @('syn-a', 'syn-b', 'syn-c')) { $script:Reg[$id] = New-SyntheticComponent -Id $id }
        $script:Ctx = New-SyntheticContext -Registry $script:Reg -Dir $script:Dir
    }

    It 'first run installs+configures everything' {
        $r = Invoke-WinSetupPlan -Context $script:Ctx -ComponentIds @('syn-a', 'syn-b', 'syn-c')
        $r.Installed | Should -Be 3
        $r.Failed    | Should -Be 0
        $script:Ctx.Extra.Counts['syn-a/install']   | Should -Be 1
        $script:Ctx.Extra.Counts['syn-a/configure'] | Should -Be 1
    }

    It 'second run is a complete no-op (nothing installed, nothing configured)' {
        Invoke-WinSetupPlan -Context $script:Ctx -ComponentIds @('syn-a', 'syn-b', 'syn-c') | Out-Null
        $r2 = Invoke-WinSetupPlan -Context $script:Ctx -ComponentIds @('syn-a', 'syn-b', 'syn-c')
        $r2.Installed  | Should -Be 0
        $r2.Configured | Should -Be 0
        $r2.Skipped    | Should -Be 3
        $script:Ctx.Extra.Counts['syn-a/install']   | Should -Be 1
        $script:Ctx.Extra.Counts['syn-b/install']   | Should -Be 1
        $script:Ctx.Extra.Counts['syn-c/configure'] | Should -Be 1
    }

    It 'a third run still changes nothing' {
        1..2 | ForEach-Object { Invoke-WinSetupPlan -Context $script:Ctx -ComponentIds @('syn-a', 'syn-b', 'syn-c') | Out-Null }
        $r3 = Invoke-WinSetupPlan -Context $script:Ctx -ComponentIds @('syn-a', 'syn-b', 'syn-c')
        $r3.Skipped | Should -Be 3
        ($script:Ctx.Extra.Counts.Values | Measure-Object -Sum).Sum | Should -Be 6
    }

    It 'dry-run before a real run does not affect idempotency' {
        $script:Ctx.DryRun = $true
        Invoke-WinSetupPlan -Context $script:Ctx -ComponentIds @('syn-a', 'syn-b', 'syn-c') | Out-Null
        ($script:Ctx.Extra.Counts.Count) | Should -Be 0
        $script:Ctx.DryRun = $false
        $r = Invoke-WinSetupPlan -Context $script:Ctx -ComponentIds @('syn-a', 'syn-b', 'syn-c')
        $r.Installed | Should -Be 3
        $r2 = Invoke-WinSetupPlan -Context $script:Ctx -ComponentIds @('syn-a', 'syn-b', 'syn-c')
        $r2.Skipped | Should -Be 3
    }
}

Describe 'Idempotency of a real config component (folders)' {

    It 'creating the folder tree twice is a no-op the second time' {
        $home2 = Join-Path $TestDrive ('home-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $home2 -Force | Out-Null
        $saved = $env:USERPROFILE
        $env:USERPROFILE = $home2
        try {
            $cfg = [ordered]@{ folders = @('Dev\Projects', 'Dev\Labs', 'Tools') }
            $ctx = New-WinSetupContext -Root $TestDrive -Config $cfg -Interactive $false -Registry $script:Registry

            $r1 = Invoke-WinSetupPlan -Context $ctx -ComponentIds @('folders')
            $r1.Installed | Should -Be 1
            $r2 = Invoke-WinSetupPlan -Context $ctx -ComponentIds @('folders')
            $r2.Installed | Should -Be 0
            $r2.Skipped   | Should -Be 1
            (Get-ChildItem -Path $home2 -Recurse -Directory).Count | Should -Be 4
        }
        finally { $env:USERPROFILE = $saved }
    }
}
