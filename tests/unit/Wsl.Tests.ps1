BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Import-Module (Join-Path $script:Root 'modules\Core\Core.psm1') -Force
    Initialize-WinSetupLog -Directory (Join-Path $TestDrive 'logs') -Console $false | Out-Null
    $script:Registry = Import-WinSetupComponents -Path (Join-Path $script:Root 'modules')
}

Describe 'wsl component' {

    It 'is registered as an admin-only WSL component' {
        $script:Registry.Contains('wsl') | Should -BeTrue
        $script:Registry['wsl'].RequiresAdmin | Should -BeTrue
        $script:Registry['wsl'].Category | Should -Be 'WSL'
    }

    It 'is pulled into the plan when wsl.enabled is true' {
        $cfg = [ordered]@{ applications = @(); wsl = [ordered]@{ enabled = $true } }
        Resolve-WinSetupPlan -Config $cfg | Should -Contain 'wsl'
    }

    It 'runs its Test block read-only without throwing' {
        $ctx = New-WinSetupContext -Root $TestDrive -Config (Get-WinSetupConfig -Root $script:Root) -Interactive $false -Registry $script:Registry
        $result = & $script:Registry['wsl'].Test $ctx
        $result.PSObject.Properties.Name | Should -Contain 'Installed'
    }
}

Describe 'Format-WinSetupWslConfig' {

    It 'renders a [wsl2] section with key=value pairs' {
        $lines = (Format-WinSetupWslConfig -Wsl2Settings ([ordered]@{ memory = '4GB'; processors = 2 })) -split "`r?`n"
        $lines | Should -Contain '[wsl2]'
        $lines | Should -Contain 'memory=4GB'
        $lines | Should -Contain 'processors=2'
    }

    It 'lower-cases boolean values' {
        $lines = (Format-WinSetupWslConfig -Wsl2Settings ([ordered]@{ swap = $false })) -split "`r?`n"
        $lines | Should -Contain 'swap=false'
    }
}

Describe 'Get-WinSetupWslInfo' {

    It 'returns a snapshot object without throwing' {
        $info = Get-WinSetupWslInfo
        $info.PSObject.Properties.Name | Should -Contain 'Present'
        $info.PSObject.Properties.Name | Should -Contain 'Distributions'
        $info.Present | Should -BeOfType ([bool])
    }
}
