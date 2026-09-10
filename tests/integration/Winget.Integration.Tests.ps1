# Integration tests - these install a REAL package via winget.
# They self-skip unless WINSETUP_ALLOW_INTEGRATION=1, and are tagged
# 'Integration' so the default unit run excludes them.
#
# Package used: jqlang.jq - tiny, CLI-only, no service, no elevation.

BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Import-Module (Join-Path $script:Root 'modules\Core\Core.psm1') -Force
    Initialize-WinSetupLog -Directory (Join-Path $script:Root 'logs') -Operation 'integration' | Out-Null
    $script:Allowed = ($env:WINSETUP_ALLOW_INTEGRATION -eq '1') -and [bool](Get-Command winget -ErrorAction SilentlyContinue)
}

Describe 'winget install + idempotency (real package)' -Tag 'Integration' -Skip:(-not ($env:WINSETUP_ALLOW_INTEGRATION -eq '1')) {

    BeforeAll {
        $script:PkgId = 'jqlang.jq'
        $script:WasPresent = [bool](Get-Command jq -ErrorAction SilentlyContinue)
    }

    It 'installs the package and it becomes detectable' {
        if (-not $script:Allowed) { Set-ItResult -Skipped -Because 'WINSETUP_ALLOW_INTEGRATION!=1 or winget missing'; return }
        Install-WinSetupWingetPackage -Id $script:PkgId -VerifyCommand 'jq'
        Update-WinSetupSessionPath
        (Get-Command jq -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
        Get-WinSetupExeVersion -Command 'jq' | Should -Match '\d'
    }

    It 'a second install call is a no-op (idempotent) and does not throw' {
        if (-not $script:Allowed) { Set-ItResult -Skipped -Because 'not allowed'; return }
        { Install-WinSetupWingetPackage -Id $script:PkgId -VerifyCommand 'jq' } | Should -Not -Throw
    }

    AfterAll {
        # Only remove it if this run is what installed it.
        if ($script:Allowed -and -not $script:WasPresent) {
            try { & winget uninstall --id $script:PkgId --exact --silent --disable-interactivity | Out-Null } catch { }
        }
    }
}
