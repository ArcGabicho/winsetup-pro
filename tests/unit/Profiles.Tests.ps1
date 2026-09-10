BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Import-Module (Join-Path $script:Root 'modules\Core\Core.psm1') -Force
    Initialize-WinSetupLog -Directory (Join-Path $TestDrive 'logs') -Console $false | Out-Null
    $script:Registry = Import-WinSetupComponents -Path (Join-Path $script:Root 'modules')
}

Describe 'Every shipped profile resolves to real components' {

    It 'has a JSON file for each documented profile' {
        foreach ($name in @('minimal', 'frontend', 'dotnet', 'fullstack', 'enterprise')) {
            Test-Path (Join-Path $script:Root "profiles\$name.json") | Should -BeTrue
        }
    }

    It 'resolves every profile plan entry to a registered component id' {
        $problems = @()
        foreach ($file in Get-ChildItem (Join-Path $script:Root 'profiles') -Filter '*.json') {
            $cfg = Get-WinSetupConfig -Root $script:Root -ProfileName $file.BaseName
            $plan = Resolve-WinSetupPlan -Config $cfg
            if ($plan.Count -eq 0) { $problems += "$($file.BaseName): empty plan" }
            foreach ($id in $plan) {
                if (-not $script:Registry.Contains($id)) { $problems += "$($file.BaseName): unknown id '$id'" }
            }
            if ((Test-WinSetupConfig -Config $cfg).Count -ne 0) { $problems += "$($file.BaseName): config invalid" }
        }
        $problems | Should -BeNullOrEmpty -Because ($problems -join '; ')
    }

    It 'dry-runs each profile end to end with no failures and no changes' {
        foreach ($file in Get-ChildItem (Join-Path $script:Root 'profiles') -Filter '*.json') {
            $cfg = Get-WinSetupConfig -Root $script:Root -ProfileName $file.BaseName
            $ctx = New-WinSetupContext -Root $TestDrive -Config $cfg -Interactive $false -Registry $script:Registry -DryRun $true
            $ctx.Paths['Templates'] = Join-Path $script:Root 'templates'
            $result = Invoke-WinSetupPlan -Context $ctx -ComponentIds (Resolve-WinSetupPlan -Config $cfg) -ProfileName $file.BaseName
            $result.Failed    | Should -Be 0 -Because "$($file.BaseName) dry-run"
            $result.Installed | Should -Be 0 -Because "$($file.BaseName) dry-run must not install"
        }
    }
}

Describe 'Phase 6 components registered' {
    It 'discovers the new development and database tools' {
        foreach ($id in @('visualstudio', 'jetbrains-toolbox', 'cmake', 'ninja', 'go', 'rust', 'java', 'neovim',
                          'sqlserver-tools', 'azure-data-studio', 'postgresql', 'mysql', 'redis-cli',
                          'mongodb-tools', 'mongosh')) {
            $script:Registry.Contains($id) | Should -BeTrue -Because "'$id' should be registered"
        }
    }

    It 'marks service-installing database components as admin-only' {
        foreach ($id in @('postgresql', 'mysql', 'redis-cli', 'visualstudio')) {
            $script:Registry[$id].RequiresAdmin | Should -BeTrue -Because "$id needs elevation"
        }
    }
}
