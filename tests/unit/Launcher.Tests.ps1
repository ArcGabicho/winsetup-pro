BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:Manifest = Join-Path $script:Root 'launcher\WinSetupPro\WinSetupPro.psd1'
    Import-Module $script:Manifest -Force
    $script:Pwsh = Join-Path $PSHOME ($(if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }))
    if (-not (Test-Path -LiteralPath $script:Pwsh)) {
        $script:Pwsh = (Get-Command pwsh, powershell -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    }
}

AfterAll { Remove-Module WinSetupPro -Force -ErrorAction SilentlyContinue }

Describe 'WinSetupPro module' {

    It 'exports the winsetup alias -> Invoke-WinSetup' {
        $a = Get-Alias winsetup -ErrorAction SilentlyContinue
        $a | Should -Not -BeNullOrEmpty
        $a.ResolvedCommand.Name | Should -Be 'Invoke-WinSetup'
    }

    It 'Get-WinSetupHome resolves the repo checkout' {
        $repoHome = Get-WinSetupHome
        Test-Path (Join-Path $repoHome 'WinSetup.ps1') | Should -BeTrue
        Test-Path (Join-Path $repoHome 'modules\Core\Core.psm1') | Should -BeTrue
    }

    It 'the manifest version is 0.2.0' {
        (Import-PowerShellDataFile $script:Manifest).ModuleVersion | Should -Be '0.2.0'
    }
}

Describe 'Get-WinSetupLaunchMode (dispatch rules)' {

    It 'no arguments + interactive host -> GUI' {
        (Get-WinSetupLaunchMode -Arguments @() -InteractiveHost).Gui | Should -BeTrue
    }

    It 'no arguments + non-interactive host -> CLI' {
        (Get-WinSetupLaunchMode -Arguments @() -InteractiveHost:$false).Gui | Should -BeFalse
    }

    It 'any CLI flag -> CLI, forwarded verbatim' {
        $m = Get-WinSetupLaunchMode -Arguments @('-Status') -InteractiveHost
        $m.Gui | Should -BeFalse
        $m.Forward | Should -Be @('-Status')
    }

    It '-Profile x -DryRun -> CLI (not GUI) and forwarded' {
        $m = Get-WinSetupLaunchMode -Arguments @('-Profile', 'dotnet', '-DryRun', '-NonInteractive') -InteractiveHost
        $m.Gui | Should -BeFalse
        $m.Forward | Should -Be @('-Profile', 'dotnet', '-DryRun', '-NonInteractive')
    }

    It '--gui forces the GUI and is not forwarded' {
        $m = Get-WinSetupLaunchMode -Arguments @('--gui', '-Profile', 'dotnet') -InteractiveHost:$false
        $m.Gui | Should -BeTrue
        $m.Forward | Should -Be @('-Profile', 'dotnet')
        $m.GuiArgs | Should -Be @('--profile', 'dotnet')
    }

    It 'strips empty / null arguments' {
        (Get-WinSetupLaunchMode -Arguments @('', $null) -InteractiveHost).Forward.Count | Should -Be 0
    }
}

Describe 'CLI delegation primitive' {

    BeforeAll {
        $script:Mod = Get-Module WinSetupPro
        $script:Entry = Join-Path $script:Root 'WinSetup.ps1'
    }

    It 'Invoke-WinSetupCli forwards a switch to WinSetup.ps1 and returns its exit code' {
        # -Status exits 1 when the workstation is not fully configured.
        $code = & $script:Mod { param($e) Invoke-WinSetupCli -Entry $e -ForwardArgs @('-Status') } $script:Entry 6>$null 5>$null 4>$null 3>$null 2>$null |
            Select-Object -Last 1
        $code | Should -Be 1
    }

    It 'Invoke-WinSetupCli forwards -Profile ... -DryRun and returns exit 0, leaving last-run.json untouched' {
        $j = Join-Path $script:Root 'state\last-run.json'
        $before = if (Test-Path $j) { (Get-Item $j).LastWriteTimeUtc } else { $null }
        $code = & $script:Mod { param($e) Invoke-WinSetupCli -Entry $e -ForwardArgs @('-Profile', 'minimal', '-DryRun', '-NonInteractive') } $script:Entry 6>$null 5>$null 4>$null 3>$null 2>$null |
            Select-Object -Last 1
        $code | Should -Be 0
        if ($before) { (Get-Item $j).LastWriteTimeUtc | Should -Be $before }
    }
}
