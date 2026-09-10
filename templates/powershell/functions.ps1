# WinSetup Pro profile fragment: functions

if (-not (Get-Command 'mkcd' -ErrorAction SilentlyContinue)) {
    function global:mkcd {
        param([Parameter(Mandatory)][string]$Path)
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Set-Location -LiteralPath $Path
    }
}

if (-not (Get-Command 'touch' -ErrorAction SilentlyContinue)) {
    function global:touch {
        param([Parameter(Mandatory)][string]$Path)
        if (Test-Path -LiteralPath $Path) { (Get-Item -LiteralPath $Path).LastWriteTime = Get-Date }
        else { New-Item -ItemType File -Path $Path | Out-Null }
    }
}

if (-not (Get-Command 'Update-Profile' -ErrorAction SilentlyContinue)) {
    function global:Update-Profile { . $PROFILE }
}
