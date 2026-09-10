BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Import-Module (Join-Path $script:Root 'scripts\WinSetupApi.psm1') -Force
    Import-Module (Join-Path $script:Root 'modules\Core\Core.psm1') -Force
    Initialize-WinSetupLog -Directory (Join-Path $TestDrive 'logs') -Console $false | Out-Null

    function Api {
        param([string]$Verb, $Payload, [string]$Path, [scriptblock]$EventSink)
        Invoke-WinSetupApi -Verb $Verb -Root (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path `
            -Payload $Payload -Path $Path -EventSink $EventSink
    }
}

Describe 'Invoke-WinSetupApi - read verbs' {

    It 'version -> ok, with apiVersion and root' {
        $r = Api version
        $r.ok | Should -BeTrue
        $r.data.apiVersion | Should -Be (Get-WinSetupApiVersion)
        Test-Path $r.data.root | Should -BeTrue
    }

    It 'system -> host snapshot' {
        $r = Api system
        $r.ok | Should -BeTrue
        $r.data.OsCaption | Should -Match 'Windows'
        $r.data.PSObject.Properties.Name | Should -Contain 'WingetPresent'
        $r.data.PSObject.Properties.Name | Should -Contain 'Internet'
    }

    It 'diagnose -> a list of checks' {
        $r = Api diagnose
        $r.ok | Should -BeTrue
        @($r.data).Count | Should -BeGreaterThan 3
        ($r.data | ForEach-Object { $_.Name }) | Should -Contain 'winget (App Installer)'
    }

    It 'profiles -> the five shipped profiles, all compatible' {
        $r = Api profiles
        $names = @($r.data | ForEach-Object { $_.name })
        foreach ($p in 'minimal', 'frontend', 'dotnet', 'fullstack', 'enterprise') { $names | Should -Contain $p }
        ($r.data | Where-Object { -not $_.compatible }) | Should -BeNullOrEmpty
        ($r.data | Where-Object { $_.name -eq 'minimal' }).componentCount | Should -BeGreaterThan 0
    }

    It 'components (minimal) -> git selected, aws-cli not; state is a known value' {
        $r = Api components @{ profile = 'minimal' }
        $git = $r.data | Where-Object { $_.id -eq 'git' }
        $git.selected | Should -BeTrue
        $git.state | Should -BeIn @('Installed', 'Missing', 'NeedsConfiguration', 'RequiresAdministrator')
        ($r.data | Where-Object { $_.id -eq 'aws-cli' }).selected | Should -BeFalse
    }

    It 'status -> rows including git' {
        (Api status).data | ForEach-Object { $_.Id } | Should -Contain 'git'
    }

    It 'plan (minimal) -> dry-run, every change action is a known string' {
        $r = Api plan @{ profile = 'minimal' }
        $r.ok | Should -BeTrue
        $r.data.dryRun | Should -BeTrue
        @($r.data.changes).Count | Should -BeGreaterThan 0
        $valid = @('skip', 'skip (needs elevation)', 'install', 'configure', 'install+configure')
        foreach ($c in $r.data.changes) {
            $c.action | Should -BeOfType ([string])
            $c.action | Should -BeIn $valid -Because "component '$($c.component)'"
        }
        # git is present on any dev machine -> it is never a fresh 'install'
        ($r.data.changes | Where-Object { $_.component -eq 'git' }).action |
            Should -BeIn @('skip', 'configure') -Because 'git is installed; only its config may differ'
        $r.data.preserve | Should -Not -BeNullOrEmpty
    }

    It 'plan carries a requiresAdmin list and backup hints' {
        $r = Api plan @{ profile = 'dotnet' }
        $r.data.Keys | Should -Contain 'requiresAdmin'
        $r.data.Keys | Should -Contain 'backups'
        @($r.data.requiresAdmin) | Should -Not -BeNull
    }

    It 'journal -> null or a resumable-flagged object' {
        $r = Api journal
        $r.ok | Should -BeTrue
        if ($null -ne $r.data) { $r.data.Keys | Should -Contain 'resumable' }
    }

    It 'export then import round-trips a config the engine accepts' {
        $file = Join-Path $TestDrive 'ws.json'
        (Api export @{ profile = 'minimal' } $file).ok | Should -BeTrue
        $file | Should -Exist
        $imp = Api import $null $file
        $imp.ok | Should -BeTrue
        $imp.data.valid | Should -BeTrue
        @($imp.data.plan) | Should -Contain 'git'
    }

    It 'import reports an invalid config' {
        $bad = Join-Path $TestDrive 'bad.json'
        Set-Content -LiteralPath $bad -Value '{ "applications": "not-an-array" }'
        (Api import $null $bad).data.valid | Should -BeFalse
    }
}

Describe 'Invoke-WinSetupApi - apply (event stream, no-op path)' {

    It 'runs an already-installed component: events fire, nothing installed or failed' -Skip:(-not (Get-Command git -ErrorAction SilentlyContinue)) {
        $events = New-Object System.Collections.Generic.List[object]
        $r = Api apply @{ components = @('git') } $null { param($e) $events.Add($e) }
        $r.ok | Should -BeTrue
        $r.data.installed | Should -Be 0
        $r.data.failed | Should -Be 0
        ($events | ForEach-Object { $_.type }) | Should -Contain 'run_completed'
        ($events | ForEach-Object { $_.type }) | Should -Contain 'component_started'
    }
}

Describe 'winsetup-api.ps1 transport wrapper' {

    It 'the script parses and declares the version verb' {
        $script = Join-Path $script:Root 'scripts\winsetup-api.ps1'
        $tokens = $null; $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$tokens, [ref]$errors) | Out-Null
        @($errors) | Should -BeNullOrEmpty
        (Get-Content -LiteralPath $script -Raw) | Should -Match "ValidateSet\('system'"
    }
}
