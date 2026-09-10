BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Import-Module (Join-Path $script:Root 'modules\Core\Core.psm1') -Force
    Initialize-WinSetupLog -Directory (Join-Path $TestDrive 'logs') -Console $false | Out-Null
    $script:Registry = Import-WinSetupComponents -Path (Join-Path $script:Root 'modules')
}

function New-IsolatedContext {
    param($Config)
    $ctx = New-WinSetupContext -Root $TestDrive -Config $Config -Interactive $false -Registry $script:Registry
    $ctx.Paths['Templates'] = Join-Path $script:Root 'templates'
    return $ctx
}

Describe 'Phase 5 components registered' {
    It 'discovers powershell-profile, dotfiles and post-install' {
        foreach ($id in @('powershell-profile', 'dotfiles', 'post-install')) {
            $script:Registry.Contains($id) | Should -BeTrue
        }
    }
}

Describe 'Plan resolution for customisation' {
    It 'adds powershell-profile when powershellProfile.enabled' {
        Resolve-WinSetupPlan -Config ([ordered]@{ applications = @(); powershellProfile = [ordered]@{ enabled = $true } }) |
            Should -Contain 'powershell-profile'
    }
    It 'adds dotfiles when a source is configured' {
        Resolve-WinSetupPlan -Config ([ordered]@{ applications = @(); dotfiles = [ordered]@{ path = 'C:\dots' } }) |
            Should -Contain 'dotfiles'
    }
    It 'adds post-install when scripts are listed' {
        Resolve-WinSetupPlan -Config ([ordered]@{ applications = @(); postInstall = [ordered]@{ scripts = @('x.ps1') } }) |
            Should -Contain 'post-install'
    }
    It 'adds none of them for the default config' {
        $plan = Resolve-WinSetupPlan -Config (Get-WinSetupConfig -Root $script:Root)
        $plan | Should -Not -Contain 'powershell-profile'
        $plan | Should -Not -Contain 'dotfiles'
        $plan | Should -Not -Contain 'post-install'
    }
}

Describe 'Backup-WinSetupFile' {
    It 'copies the file under backup/<category>/<timestamp>/ and returns the path' {
        $f = Join-Path $TestDrive 'thing.conf'
        Set-Content -LiteralPath $f -Value 'v1'
        $ctx = New-IsolatedContext (Get-WinSetupConfig -Root $script:Root)
        $dest = Backup-WinSetupFile -Context $ctx -Path $f -Category 'demo'
        $dest | Should -Exist
        $dest | Should -Match 'backup[\\/]demo[\\/]'
        (Get-Content -LiteralPath $dest -Raw).Trim() | Should -Be 'v1'
    }
    It 'returns $null when the source does not exist' {
        $ctx = New-IsolatedContext (Get-WinSetupConfig -Root $script:Root)
        Backup-WinSetupFile -Context $ctx -Path (Join-Path $TestDrive 'nope') -Category 'demo' | Should -BeNullOrEmpty
    }
    It 'honours settings.createBackups = false' {
        $f = Join-Path $TestDrive 'thing2.conf'; Set-Content -LiteralPath $f -Value 'x'
        $cfg = Get-WinSetupConfig -Root $script:Root
        $cfg['settings']['createBackups'] = $false
        $ctx = New-IsolatedContext $cfg
        Backup-WinSetupFile -Context $ctx -Path $f -Category 'demo' | Should -BeNullOrEmpty
    }
}

Describe 'powershell-profile component' {
    It 'adds a managed block to $PROFILE, preserves other content, and is idempotent' {
        $fake = Join-Path $TestDrive 'Microsoft.PowerShell_profile.ps1'
        Set-Content -LiteralPath $fake -Value "# my own stuff`r`nSet-Alias foo bar`r`n"
        $saved = $global:PROFILE
        $global:PROFILE = [pscustomobject]@{ CurrentUserAllHosts = $fake; CurrentUserCurrentHost = $fake }
        try {
            $cfg = Get-WinSetupConfig -Root $script:Root
            $cfg['powershellProfile']['enabled'] = $true
            $cfg['settings']['createBackups'] = $false
            $ctx = New-IsolatedContext $cfg

            & $script:Registry['powershell-profile'].Configure $ctx
            $text = Get-Content -LiteralPath $fake -Raw
            $text | Should -Match 'WinSetup Pro managed block'
            $text | Should -Match 'my own stuff'
            Test-Path (Join-Path $TestDrive 'winsetup-pro\aliases.ps1') | Should -BeTrue

            $after1 = Get-Content -LiteralPath $fake -Raw
            & $script:Registry['powershell-profile'].Configure $ctx
            (Get-Content -LiteralPath $fake -Raw) | Should -Be $after1
            (& $script:Registry['powershell-profile'].Test $ctx).Configured | Should -BeTrue
        }
        finally { $global:PROFILE = $saved }
    }
}

Describe 'dotfiles component' {
    It 'installs from a folder, backs up the existing target, and is idempotent' {
        $src = Join-Path $TestDrive 'dots'; New-Item -ItemType Directory -Path $src -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $src '.myrc') -Value 'NEW'
        $target = Join-Path $TestDrive 'home\.myrc'
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Set-Content -LiteralPath $target -Value 'OLD'

        $cfg = Get-WinSetupConfig -Root $script:Root
        $cfg['dotfiles']['path'] = $src
        $cfg['dotfiles']['map'] = [ordered]@{ '.myrc' = $target }
        $cfg['dotfiles']['backupExisting'] = 'always'
        $ctx = New-IsolatedContext $cfg

        (& $script:Registry['dotfiles'].Test $ctx).Configured | Should -BeFalse
        & $script:Registry['dotfiles'].Configure $ctx

        (Get-Content -LiteralPath $target -Raw).Trim() | Should -Be 'NEW'
        $backups = Get-ChildItem -Path (Join-Path $TestDrive 'backup\dotfiles') -Recurse -File -ErrorAction SilentlyContinue
        $backups | Should -Not -BeNullOrEmpty
        ($backups | Get-Content -Raw) -join '' | Should -Match 'OLD'

        (& $script:Registry['dotfiles'].Test $ctx).Configured | Should -BeTrue
    }
}

Describe 'post-install component' {
    It 'runs a script once, records it, and does not re-run it unchanged' {
        $s = Join-Path $TestDrive 'p1.ps1'
        Set-Content -LiteralPath $s -Value '$global:WSP_PI = [int]$global:WSP_PI + 1'
        $cfg = Get-WinSetupConfig -Root $script:Root
        $cfg['postInstall']['scripts'] = @($s)
        $ctx = New-IsolatedContext $cfg
        $global:WSP_PI = 0
        try {
            & $script:Registry['post-install'].Configure $ctx
            $global:WSP_PI | Should -Be 1
            & $script:Registry['post-install'].Configure $ctx
            $global:WSP_PI | Should -Be 1
            (& $script:Registry['post-install'].Test $ctx).Configured | Should -BeTrue
        }
        finally { Remove-Variable -Name WSP_PI -Scope Global -ErrorAction SilentlyContinue }
    }
}
