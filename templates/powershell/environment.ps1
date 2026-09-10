# WinSetup Pro profile fragment: environment / shell behaviour

if (-not $env:EDITOR) {
    if (Get-Command code -ErrorAction SilentlyContinue) { $env:EDITOR = 'code --wait' }
    elseif (Get-Command nvim -ErrorAction SilentlyContinue) { $env:EDITOR = 'nvim' }
}

if (Get-Module -ListAvailable -Name PSReadLine) {
    Import-Module PSReadLine -ErrorAction SilentlyContinue
    try {
        Set-PSReadLineOption -HistoryNoDuplicates -HistorySearchCursorMovesToEnd
        Set-PSReadLineOption -PredictionSource History
        Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
        Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    } catch { }
}

if ($PSVersionTable.PSVersion.Major -ge 7 -and $PSStyle) {
    $PSStyle.FileInfo.Directory = $PSStyle.Foreground.Cyan
}
