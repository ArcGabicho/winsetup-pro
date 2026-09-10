BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Import-Module (Join-Path $script:Root 'modules\Core\Core.psm1') -Force
    Initialize-WinSetupLog -Directory (Join-Path $TestDrive 'logs') -Console $false | Out-Null
    $script:Registry = Import-WinSetupComponents -Path (Join-Path $script:Root 'modules')
}

Describe 'Phase 3 components are registered' {
    It 'discovers the cloud CLIs and environment components' {
        foreach ($id in @('azure-cli', 'aws-cli', 'gcloud-cli', 'terraform', 'kubectl', 'helm',
                          'ssh', 'env-vars', 'folders', 'fonts')) {
            $script:Registry.Contains($id) | Should -BeTrue -Because "'$id' should be registered"
        }
    }
}

Describe 'Plan resolution for environment features' {

    It 'adds folders when the profile declares folders' {
        $cfg = [ordered]@{ applications = @(); folders = @('Dev\Projects') }
        Resolve-WinSetupPlan -Config $cfg | Should -Contain 'folders'
    }

    It 'adds fonts when the profile declares fonts' {
        $cfg = [ordered]@{ applications = @(); fonts = @('CascadiaCode') }
        Resolve-WinSetupPlan -Config $cfg | Should -Contain 'fonts'
    }

    It 'adds env-vars for a non-empty environment block' {
        $cfg = [ordered]@{ applications = @(); environment = [ordered]@{ user = [ordered]@{ EDITOR = 'code' } } }
        Resolve-WinSetupPlan -Config $cfg | Should -Contain 'env-vars'
    }

    It 'does not add env-vars / folders / fonts for the empty default config' {
        $plan = Resolve-WinSetupPlan -Config (Get-WinSetupConfig -Root $script:Root)
        $plan | Should -Not -Contain 'env-vars'
        $plan | Should -Not -Contain 'folders'
        $plan | Should -Not -Contain 'fonts'
    }
}

Describe 'folders component' {

    It 'creates missing directories and is idempotent' {
        $base = Join-Path $TestDrive 'home'
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        $old = $env:USERPROFILE
        $env:USERPROFILE = $base
        try {
            $cfg = [ordered]@{ folders = @('Dev\Projects', 'Tools') }
            $ctx = New-WinSetupContext -Root $TestDrive -Config $cfg -Interactive $false -Registry $script:Registry
            (& $script:Registry['folders'].Test $ctx).Installed | Should -BeFalse
            & $script:Registry['folders'].Install $ctx
            (Test-Path (Join-Path $base 'Dev\Projects')) | Should -BeTrue
            (Test-Path (Join-Path $base 'Tools')) | Should -BeTrue
            (& $script:Registry['folders'].Test $ctx).Installed | Should -BeTrue
        }
        finally { $env:USERPROFILE = $old }
    }
}

Describe 'env-vars component (User scope only)' {

    It 'reports pending work, applies it, then reports clean' {
        $name = 'WINSETUP_TEST_' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        $cfg = [ordered]@{ environment = [ordered]@{ user = [ordered]@{ $name = 'hello' } }; settings = [ordered]@{ createBackups = $false } }
        $ctx = New-WinSetupContext -Root $TestDrive -Config $cfg -Interactive $false -Registry $script:Registry
        try {
            (& $script:Registry['env-vars'].Test $ctx).Configured | Should -BeFalse
            & $script:Registry['env-vars'].Configure $ctx
            [Environment]::GetEnvironmentVariable($name, 'User') | Should -Be 'hello'
            (& $script:Registry['env-vars'].Test $ctx).Configured | Should -BeTrue
        }
        finally {
            [Environment]::SetEnvironmentVariable($name, $null, 'User')
        }
    }
}

Describe 'ssh component' {

    It 'never creates ~/.ssh from a Test call' {
        $sshDir = Join-Path $HOME '.ssh'
        $before = Test-Path -LiteralPath $sshDir
        $ctx = New-WinSetupContext -Root $TestDrive -Config (Get-WinSetupConfig -Root $script:Root) -Interactive $false -Registry $script:Registry
        & $script:Registry['ssh'].Test $ctx | Out-Null
        (Test-Path -LiteralPath $sshDir) | Should -Be $before
    }

    It 'does not generate a key unattended unless explicitly allowed' {
        # generateKeyUnattended defaults to $false -> Configure must not shell out to ssh-keygen.
        $script:Registry['ssh'].Source | Should -Match 'OpenSsh\.ps1$'
        (Get-Content -LiteralPath $script:Registry['ssh'].Source -Raw) | Should -Match 'generateKeyUnattended'
    }
}
