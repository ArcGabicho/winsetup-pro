# WinSetup Pro profile fragment: docker shortcuts

if (Get-Command docker -ErrorAction SilentlyContinue) {
    if (-not (Get-Command 'dps'  -ErrorAction SilentlyContinue)) { function global:dps  { docker ps @args } }
    if (-not (Get-Command 'dpsa' -ErrorAction SilentlyContinue)) { function global:dpsa { docker ps -a @args } }
    if (-not (Get-Command 'di'   -ErrorAction SilentlyContinue)) { function global:di   { docker images @args } }
    if (-not (Get-Command 'dex'  -ErrorAction SilentlyContinue)) { function global:dex  { docker exec -it @args } }
    if (-not (Get-Command 'dcu'  -ErrorAction SilentlyContinue)) { function global:dcu  { docker compose up @args } }
    if (-not (Get-Command 'dcd'  -ErrorAction SilentlyContinue)) { function global:dcd  { docker compose down @args } }
}
