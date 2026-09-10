# modules/Applications/PostgreSql.ps1 - PostgreSQL server + client.
# postgresql.version = "17" (default) -> winget id PostgreSQL.PostgreSQL.17
# Registers a Windows service -> RequiresAdmin.

New-WinSetupComponent -Id 'postgresql' -Name 'PostgreSQL' -Category 'Database' `
    -Description 'PostgreSQL database server and psql client' -Tags @('sql', 'postgres') `
    -RequiresAdmin $true `
    -Test {
        param($Context)
        if (Get-Command psql -ErrorAction SilentlyContinue) {
            $v = Get-WinSetupExeVersion -Command 'psql'
            return New-WinSetupDetectionResult -Installed $true -Version $v -Summary "psql $v"
        }
        $svc = Get-Service -Name 'postgresql*' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($svc) { return New-WinSetupDetectionResult -Installed $true -Summary "service $($svc.Name) ($($svc.Status))" }
        if (Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'PostgreSQL')) {
            return New-WinSetupDetectionResult -Installed $true -Summary 'installed (psql not on PATH)'
        }
        New-WinSetupDetectionResult -Installed $false
    } `
    -Install {
        param($Context)
        $ver = [string](Get-WinSetupConfigValue -Config $Context.Config -Path 'postgresql.version' -Default '17')
        Install-WinSetupWingetPackage -Id ("PostgreSQL.PostgreSQL.{0}" -f $ver) `
            -VerifyCommand 'psql' -VerifyPath '%ProgramFiles%\PostgreSQL'
        Write-WinSetupLog -Level WARNING -Module 'postgresql' -Message 'PostgreSQL installed. Set a superuser password and add its bin\ folder to PATH if psql is not found.'
    }
