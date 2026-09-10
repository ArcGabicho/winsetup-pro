# modules/Applications/MongoDbTools.ps1 - MongoDB Database Tools (mongodump, ...).

New-WinSetupComponent -Id 'mongodb-tools' -Name 'MongoDB Database Tools' -Category 'Database' `
    -Description 'mongodump / mongorestore / mongoexport / mongoimport / bsondump' -Tags @('mongodb') `
    -Test {
        param($Context)
        $v = Get-WinSetupExeVersion -Command 'mongodump' -Pattern '(\d+\.\d+\.\d+)'
        if (-not $v -and -not (Get-Command mongodump -ErrorAction SilentlyContinue)) {
            return New-WinSetupDetectionResult -Installed $false
        }
        New-WinSetupDetectionResult -Installed $true -Version $v -Summary 'mongodb database tools present'
    } `
    -Install {
        param($Context)
        Install-WinSetupWingetPackage -Id 'MongoDB.DatabaseTools' -VerifyCommand 'mongodump'
    }
