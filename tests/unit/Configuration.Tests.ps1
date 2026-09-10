BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Import-Module (Join-Path $script:Root 'modules\Core\Core.psm1') -Force
    Initialize-WinSetupLog -Directory (Join-Path $TestDrive 'logs') -Console $false | Out-Null
}

Describe 'Merge-WinSetupConfig' {

    It 'deep-merges nested dictionaries' {
        $base = [ordered]@{ settings = [ordered]@{ a = 1; b = 2 } }
        $over = [ordered]@{ settings = [ordered]@{ b = 20; c = 30 } }
        $m = Merge-WinSetupConfig -Base $base -Override $over
        $m['settings']['a'] | Should -Be 1
        $m['settings']['b'] | Should -Be 20
        $m['settings']['c'] | Should -Be 30
    }

    It 'unions the applications list without duplicates' {
        $base = [ordered]@{ applications = @('git', 'vscode') }
        $over = [ordered]@{ applications = @('vscode', 'docker') }
        $m = Merge-WinSetupConfig -Base $base -Override $over
        @($m['applications'] | Sort-Object) | Should -Be @('docker', 'git', 'vscode')
    }

    It 'replaces scalar values' {
        $m = Merge-WinSetupConfig -Base ([ordered]@{ profile = 'a' }) -Override ([ordered]@{ profile = 'b' })
        $m['profile'] | Should -Be 'b'
    }
}

Describe 'Get-WinSetupConfigValue' {

    It 'resolves a dotted path' {
        $c = [ordered]@{ git = [ordered]@{ defaultBranch = 'main' } }
        Get-WinSetupConfigValue -Config $c -Path 'git.defaultBranch' | Should -Be 'main'
    }

    It 'returns the default when a segment is missing' {
        Get-WinSetupConfigValue -Config ([ordered]@{}) -Path 'x.y.z' -Default 'fallback' | Should -Be 'fallback'
    }
}

Describe 'Get-WinSetupConfig' {

    It 'layers default.json under the requested profile' {
        $c = Get-WinSetupConfig -Root $script:Root -ProfileName 'minimal'
        $c['profile'] | Should -Be 'minimal'
        $c['applications'] | Should -Contain 'git'
        # value inherited from default.json
        Get-WinSetupConfigValue -Config $c -Path 'settings.errorPolicy.critical' | Should -Be 'abort'
    }

    It 'throws for an unknown profile' {
        { Get-WinSetupConfig -Root $script:Root -ProfileName 'does-not-exist-xyz' } | Should -Throw
    }

    It 'honours the -InstallOnly override' {
        $c = Get-WinSetupConfig -Root $script:Root -InstallOnly @('git', 'docker-desktop')
        @($c['applications']) | Should -Be @('git', 'docker-desktop')
    }
}

Describe 'Resolve-WinSetupPlan' {

    It 'includes an enabled feature block as a component id' {
        $c = [ordered]@{ applications = @('vscode'); git = [ordered]@{ enabled = $true } }
        $plan = Resolve-WinSetupPlan -Config $c
        $plan | Should -Contain 'git'
        $plan | Should -Contain 'vscode'
    }

    It 'de-duplicates the plan' {
        $c = [ordered]@{ applications = @('git', 'git', 'vscode') }
        (Resolve-WinSetupPlan -Config $c).Count | Should -Be 2
    }
}

Describe 'Test-WinSetupConfig' {

    It 'accepts the shipped default configuration' {
        $c = Get-WinSetupConfig -Root $script:Root
        (Test-WinSetupConfig -Config $c).Count | Should -Be 0
    }

    It 'flags an invalid log level' {
        $c = [ordered]@{ applications = @(); settings = [ordered]@{ logLevel = 'LOUD' } }
        (Test-WinSetupConfig -Config $c) | Should -Not -BeNullOrEmpty
    }
}
