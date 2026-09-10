# modules/Applications/Go.ps1

New-WinSetupComponent -Id 'go' -Name 'Go' -Category 'Development' `
    -Description 'Go programming language toolchain' -Tags @('go', 'runtime') `
    -Test {
        param($Context)
        $v = Get-WinSetupExeVersion -Command 'go' -VersionArgs @('version')
        if (-not $v) { return New-WinSetupDetectionResult -Installed $false }
        New-WinSetupDetectionResult -Installed $true -Version $v -Summary "go $v"
    } `
    -Install {
        param($Context)
        Install-WinSetupWingetPackage -Id 'GoLang.Go' -VerifyCommand 'go'
    }
