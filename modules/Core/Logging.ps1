# Logging.ps1 - structured, level-based logging for WinSetup Pro.
# The logger owns a single file sink. Rich console output is produced by the
# UI helpers (UI.ps1); this function only mirrors WARNING/ERROR to the console
# so nothing important is lost when the UI layer is silent.

$script:WinSetupLogLevels = @{
    DEBUG   = 0
    INFO    = 1
    SUCCESS = 2
    WARNING = 3
    ERROR   = 4
}

$script:WinSetupLog = [pscustomobject]@{
    Path        = $null
    MinLevel    = 'INFO'
    Console     = $true
    Initialized = $false
}

function Initialize-WinSetupLog {
    <#
    .SYNOPSIS
        Opens a timestamped log file and configures logging thresholds.
    .OUTPUTS
        [string] Full path of the log file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Directory,
        [string]$Operation = 'run',
        [ValidateSet('DEBUG', 'INFO', 'SUCCESS', 'WARNING', 'ERROR')]
        [string]$MinLevel = 'INFO',
        [bool]$Console = $true
    )

    if (-not (Test-Path -LiteralPath $Directory)) {
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    }

    $stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $script:WinSetupLog.Path        = Join-Path $Directory ('{0}-{1}.log' -f $stamp, $Operation)
    $script:WinSetupLog.MinLevel    = $MinLevel
    $script:WinSetupLog.Console     = $Console
    $script:WinSetupLog.Initialized = $true

    try { New-Item -ItemType File -Path $script:WinSetupLog.Path -Force | Out-Null } catch { }

    Write-WinSetupLog -Level INFO -Module 'Logging' -Message ("Session log opened at {0}" -f $script:WinSetupLog.Path)
    return $script:WinSetupLog.Path
}

function Write-WinSetupLog {
    <#
    .SYNOPSIS
        Writes a single structured entry to the session log.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('DEBUG', 'INFO', 'SUCCESS', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO',
        [string]$Module = 'Core',
        [Parameter(Mandatory)][AllowEmptyString()][string]$Message,
        [int]$DurationMs
    )

    $lvl = $script:WinSetupLogLevels[$Level]
    $min = $script:WinSetupLogLevels[$script:WinSetupLog.MinLevel]
    $ts  = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
    $dur = if ($PSBoundParameters.ContainsKey('DurationMs')) { ' ({0} ms)' -f $DurationMs } else { '' }
    $line = '{0} [{1,-7}] [{2}] {3}{4}' -f $ts, $Level, $Module, $Message, $dur

    if ($script:WinSetupLog.Initialized -and $script:WinSetupLog.Path -and $lvl -ge $min) {
        try { Add-Content -LiteralPath $script:WinSetupLog.Path -Value $line -Encoding utf8 } catch { }
    }

    if ($script:WinSetupLog.Console) {
        switch ($Level) {
            'WARNING' { Write-Host ('  ! ' + $Message) -ForegroundColor Yellow }
            'ERROR'   { Write-Host ('  x ' + $Message) -ForegroundColor Red }
            default   { Write-Verbose $line }
        }
    }
}

function Set-WinSetupLogConsole {
    <#
    .SYNOPSIS
        Enables or disables console mirroring / UI output at runtime.
    #>
    param([Parameter(Mandatory)][bool]$Enabled)
    $script:WinSetupLog.Console = $Enabled
}
