BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Import-Module (Join-Path $script:Root 'modules\Core\Core.psm1') -Force
}

Describe 'Logging' {

    It 'creates a timestamped, operation-named log file' {
        $dir  = Join-Path $TestDrive 'logs-a'
        $path = Initialize-WinSetupLog -Directory $dir -Operation 'unit' -Console $false
        $path | Should -Exist
        $path | Should -Match 'unit\.log$'
    }

    It 'writes entries at or above the minimum level and drops the rest' {
        $dir  = Join-Path $TestDrive 'logs-b'
        $path = Initialize-WinSetupLog -Directory $dir -Operation 'unit' -MinLevel 'WARNING' -Console $false

        Write-WinSetupLog -Level INFO    -Module 'T' -Message 'quiet-info-line'
        Write-WinSetupLog -Level WARNING -Module 'T' -Message 'loud-warning-line'
        Write-WinSetupLog -Level ERROR   -Module 'T' -Message 'loud-error-line'

        $content = Get-Content -LiteralPath $path -Raw
        $content | Should -Not -Match 'quiet-info-line'
        $content | Should -Match 'loud-warning-line'
        $content | Should -Match 'loud-error-line'
    }

    It 'never throws when the logger was not initialised' {
        # Fresh module instance with a pristine (uninitialised) logger.
        Import-Module (Join-Path $script:Root 'modules\Core\Core.psm1') -Force
        { Write-WinSetupLog -Level INFO -Module 'T' -Message 'no sink' } | Should -Not -Throw
    }
}
