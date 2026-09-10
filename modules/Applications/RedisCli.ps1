# modules/Applications/RedisCli.ps1 - Redis for Windows (server + redis-cli).
#
# "Redis on Windows" (Redis.Redis) is an old Microsoft-era port. For a current
# Redis, running it inside WSL is recommended - this component only covers the
# native package for `redis-cli` availability. Installs a service -> RequiresAdmin.

New-WinSetupComponent -Id 'redis-cli' -Name 'Redis (redis-cli)' -Category 'Database' `
    -Description 'Redis for Windows, including redis-cli' -Tags @('redis', 'cache') `
    -RequiresAdmin $true `
    -Test {
        param($Context)
        if (Get-Command redis-cli -ErrorAction SilentlyContinue) {
            $v = Get-WinSetupExeVersion -Command 'redis-cli'
            return New-WinSetupDetectionResult -Installed $true -Version $v -Summary "redis-cli $v"
        }
        $svc = Get-Service -Name 'Redis*' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($svc) { return New-WinSetupDetectionResult -Installed $true -Summary "service $($svc.Name)" }
        New-WinSetupDetectionResult -Installed $false
    } `
    -Install {
        param($Context)
        Install-WinSetupWingetPackage -Id 'Redis.Redis' -VerifyCommand 'redis-cli'
        Write-WinSetupLog -Level WARNING -Module 'redis-cli' -Message 'Installed the legacy Windows Redis port. For an up-to-date Redis, run it in WSL instead.'
    }
