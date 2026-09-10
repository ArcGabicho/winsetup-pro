BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Import-Module (Join-Path $script:Root 'modules\Core\Core.psm1') -Force
    Initialize-WinSetupLog -Directory (Join-Path $TestDrive 'logs') -Console $false | Out-Null
    $script:Registry = Import-WinSetupComponents -Path (Join-Path $script:Root 'modules')
}

Describe 'Shipped components' {

    It 'discovers the expected Phase 2 component ids' {
        foreach ($id in @('git', 'pwsh', 'windows-terminal', 'vscode', 'github-cli',
                          'dotnet-sdk', 'nodejs', 'npm', 'pnpm', 'python', 'docker-desktop')) {
            $script:Registry.Contains($id) | Should -BeTrue -Because "component '$id' should be registered"
        }
    }

    It 'produces schema-valid descriptors with unique ids' {
        $seen = @{}
        foreach ($c in $script:Registry.Values) {
            (Test-WinSetupComponentSchema -Component $c) | Should -BeNullOrEmpty -Because "$($c.Id) must be schema-valid"
            $seen.ContainsKey($c.Id) | Should -BeFalse
            $seen[$c.Id] = $true
        }
    }

    It 'declares Docker Desktop as an admin-only component' {
        $script:Registry['docker-desktop'].RequiresAdmin | Should -BeTrue
    }

    It 'wires npm to depend on nodejs' {
        $script:Registry['npm'].DependsOn | Should -Contain 'nodejs'
    }

    It 'gives every install-capable component a Test block' {
        foreach ($c in $script:Registry.Values) {
            if ($c.Install) { $c.Test | Should -BeOfType ([scriptblock]) }
        }
    }
}

Describe 'Get-WinSetupExeVersion' {

    It 'returns $null for a command that does not exist' {
        Get-WinSetupExeVersion -Command 'definitely-not-a-real-exe-xyz' | Should -BeNullOrEmpty
    }

    It 'extracts a version from a real command when available' -Skip:(-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Get-WinSetupExeVersion -Command 'git' | Should -Match '^\d+\.\d+'
    }
}

Describe 'Component Test blocks are side-effect free' {

    It 'can run every Test block without throwing and without changing state' {
        $config = Get-WinSetupConfig -Root $script:Root
        $ctx = New-WinSetupContext -Root $TestDrive -Config $config -Interactive $false -Registry $script:Registry
        foreach ($c in $script:Registry.Values) {
            $result = & $c.Test $ctx
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'Installed'
        }
    }
}
