# WinSetup Pro profile fragment: aliases
# Loaded from the managed block in your $PROFILE. Safe to run repeatedly; every
# alias/function is only defined when the name is still free.

function Set-WSPAliasIfFree {
    param([string]$Name, [string]$Value)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        Set-Alias -Name $Name -Value $Value -Scope Global
    }
}

Set-WSPAliasIfFree 'which' 'Get-Command'

if (-not (Get-Command 'll' -ErrorAction SilentlyContinue)) {
    function global:ll { Get-ChildItem -Force @args }
}
if (-not (Get-Command 'la' -ErrorAction SilentlyContinue)) {
    function global:la { Get-ChildItem -Force -Hidden @args }
}
if (-not (Get-Command '..' -ErrorAction SilentlyContinue)) {
    function global:.. { Set-Location .. }
}
if (-not (Get-Command '...' -ErrorAction SilentlyContinue)) {
    function global:... { Set-Location ../.. }
}
