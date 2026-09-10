# modules/Applications/SqlServerTools.ps1 - the modern cross-platform sqlcmd.

New-WinSetupComponent -Id 'sqlserver-tools' -Name 'SQL Server tools (sqlcmd)' -Category 'Database' `
    -Description 'go-sqlcmd command-line tools for SQL Server / Azure SQL' -Tags @('sql', 'mssql') `
    -Test {
        param($Context)
        $v = Get-WinSetupExeVersion -Command 'sqlcmd'
        if (-not $v) { return New-WinSetupDetectionResult -Installed $false }
        New-WinSetupDetectionResult -Installed $true -Version $v -Summary "sqlcmd $v"
    } `
    -Install {
        param($Context)
        Install-WinSetupWingetPackage -Id 'Microsoft.Sqlcmd' -VerifyCommand 'sqlcmd'
    }
