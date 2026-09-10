BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Import-Module (Join-Path $script:Root 'modules\Core\Core.psm1') -Force
    Initialize-WinSetupLog -Directory (Join-Path $TestDrive 'logs') -Console $false | Out-Null
    $script:Registry = Import-WinSetupComponents -Path (Join-Path $script:Root 'modules')
    $script:Ctx = New-WinSetupContext -Root $TestDrive -Config (Get-WinSetupConfig -Root $script:Root) `
        -Interactive $false -Registry $script:Registry
    $script:Ctx.Paths['Templates'] = Join-Path $script:Root 'templates'
}

Describe 'Software detection contract' {

    It 'discovers a healthy component set' {
        $script:Registry.Count | Should -BeGreaterOrEqual 35
        $script:Registry.Contains('git') | Should -BeTrue
    }

    It 'every component Test returns a well-formed detection result' {
        foreach ($component in $script:Registry.Values) {
            $result = & $component.Test $script:Ctx
            $result | Should -Not -BeNullOrEmpty -Because $component.Id
            ($result.PSObject.Properties.Name) | Should -Contain 'Installed'
            $result.Installed  | Should -BeOfType ([bool]) -Because "$($component.Id).Installed"
            $result.Configured | Should -BeOfType ([bool]) -Because "$($component.Id).Configured"
        }
    }

    It 'running every Test twice leaves HOME dotfiles untouched (Test is read-only)' {
        $probe = { @(
            (Test-Path -LiteralPath (Join-Path $HOME '.ssh')),
            (Test-Path -LiteralPath (Join-Path $HOME '.wslconfig')),
            (Test-Path -LiteralPath (Join-Path $HOME '.gitconfig'))
        ) }
        $before = & $probe
        foreach ($component in $script:Registry.Values) { & $component.Test $script:Ctx | Out-Null }
        foreach ($component in $script:Registry.Values) { & $component.Test $script:Ctx | Out-Null }
        (& $probe) | Should -Be $before
    }

    It 'detects the tools that are genuinely present on this machine' {
        # git is a hard dependency of the test environment.
        (& $script:Registry['git'].Test $script:Ctx).Installed | Should -BeTrue
    }
}

Describe 'Get-WinSetupExeVersion' {

    It 'returns $null for a command that does not exist' {
        Get-WinSetupExeVersion -Command 'winsetup-no-such-exe-zzz' | Should -BeNullOrEmpty
    }

    It 'extracts a dotted version from a real command' -Skip:(-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Get-WinSetupExeVersion -Command 'git' | Should -Match '^\d+\.\d+'
    }
}
