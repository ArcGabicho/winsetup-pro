# WinSetup Pro profile fragment: git shortcuts
# Functions (not aliases) so they accept arguments naturally.

if (Get-Command git -ErrorAction SilentlyContinue) {
    if (-not (Get-Command 'gs'  -ErrorAction SilentlyContinue)) { function global:gs  { git status @args } }
    if (-not (Get-Command 'ga'  -ErrorAction SilentlyContinue)) { function global:ga  { git add @args } }
    if (-not (Get-Command 'gc'  -ErrorAction SilentlyContinue)) { function global:gc  { git commit @args } }
    if (-not (Get-Command 'gco' -ErrorAction SilentlyContinue)) { function global:gco { git checkout @args } }
    if (-not (Get-Command 'gp'  -ErrorAction SilentlyContinue)) { function global:gp  { git pull @args } }
    if (-not (Get-Command 'gpu' -ErrorAction SilentlyContinue)) { function global:gpu { git push @args } }
    if (-not (Get-Command 'gl'  -ErrorAction SilentlyContinue)) { function global:gl  { git log --oneline --graph --decorate -20 @args } }
    if (-not (Get-Command 'gd'  -ErrorAction SilentlyContinue)) { function global:gd  { git diff @args } }
}
