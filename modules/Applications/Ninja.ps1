# modules/Applications/Ninja.ps1

New-WinSetupComponent -Id 'ninja' -Name 'Ninja' -Category 'Development' `
    -Description 'Ninja small build system' -Tags @('build', 'cpp') `
    -Test {
        param($Context)
        $v = Get-WinSetupExeVersion -Command 'ninja'
        if (-not $v) { return New-WinSetupDetectionResult -Installed $false }
        New-WinSetupDetectionResult -Installed $true -Version $v -Summary "ninja $v"
    } `
    -Install {
        param($Context)
        Install-WinSetupWingetPackage -Id 'Ninja-build.Ninja' -VerifyCommand 'ninja'
    }
