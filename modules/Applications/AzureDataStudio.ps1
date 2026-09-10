# modules/Applications/AzureDataStudio.ps1

New-WinSetupComponent -Id 'azure-data-studio' -Name 'Azure Data Studio' -Category 'Database' `
    -Description 'Cross-platform database GUI for SQL Server / PostgreSQL' -Tags @('sql', 'gui') `
    -Test {
        param($Context)
        if (Get-Command azuredatastudio -ErrorAction SilentlyContinue) {
            return New-WinSetupDetectionResult -Installed $true -Summary 'on PATH'
        }
        foreach ($p in @(
                (Join-Path $env:LOCALAPPDATA 'Programs\Azure Data Studio\azuredatastudio.exe'),
                (Join-Path $env:ProgramFiles 'Azure Data Studio\azuredatastudio.exe'))) {
            if (Test-Path -LiteralPath $p) { return New-WinSetupDetectionResult -Installed $true -Summary 'installed' }
        }
        New-WinSetupDetectionResult -Installed $false
    } `
    -Install {
        param($Context)
        Install-WinSetupWingetPackage -Id 'Microsoft.Azure.DataStudio' -VerifyCommand 'azuredatastudio' `
            -VerifyPath '%LOCALAPPDATA%\Programs\Azure Data Studio\azuredatastudio.exe'
    }
