# modules/Applications/MySql.ps1 - MySQL Community server + client.
# Registers a Windows service -> RequiresAdmin.

New-WinSetupComponent -Id 'mysql' -Name 'MySQL' -Category 'Database' `
    -Description 'MySQL Community Server and mysql client' -Tags @('sql', 'mysql') `
    -RequiresAdmin $true `
    -Test {
        param($Context)
        if (Get-Command mysql -ErrorAction SilentlyContinue) {
            $v = Get-WinSetupExeVersion -Command 'mysql'
            return New-WinSetupDetectionResult -Installed $true -Version $v -Summary "mysql $v"
        }
        $svc = Get-Service -Name 'MySQL*' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($svc) { return New-WinSetupDetectionResult -Installed $true -Summary "service $($svc.Name) ($($svc.Status))" }
        New-WinSetupDetectionResult -Installed $false
    } `
    -Install {
        param($Context)
        Install-WinSetupWingetPackage -Id 'Oracle.MySQL' -VerifyCommand 'mysql'
        Write-WinSetupLog -Level WARNING -Module 'mysql' -Message 'MySQL installed. Run the MySQL Configurator to set the root password and start the service.'
    }
