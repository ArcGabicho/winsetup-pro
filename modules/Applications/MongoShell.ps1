# modules/Applications/MongoShell.ps1 - the modern MongoDB shell (mongosh).

New-WinSetupComponent -Id 'mongosh' -Name 'MongoDB Shell' -Category 'Database' `
    -Description 'mongosh - the MongoDB shell' -Tags @('mongodb') `
    -Test {
        param($Context)
        $v = Get-WinSetupExeVersion -Command 'mongosh'
        if (-not $v) { return New-WinSetupDetectionResult -Installed $false }
        New-WinSetupDetectionResult -Installed $true -Version $v -Summary "mongosh $v"
    } `
    -Install {
        param($Context)
        Install-WinSetupWingetPackage -Id 'MongoDB.Shell' -VerifyCommand 'mongosh'
    }
