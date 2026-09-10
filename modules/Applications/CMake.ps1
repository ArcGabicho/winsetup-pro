# modules/Applications/CMake.ps1

New-WinSetupComponent -Id 'cmake' -Name 'CMake' -Category 'Development' `
    -Description 'CMake build system generator' -Tags @('build', 'cpp') `
    -Test {
        param($Context)
        $v = Get-WinSetupExeVersion -Command 'cmake'
        if (-not $v) { return New-WinSetupDetectionResult -Installed $false }
        New-WinSetupDetectionResult -Installed $true -Version $v -Summary "cmake $v"
    } `
    -Install {
        param($Context)
        Install-WinSetupWingetPackage -Id 'Kitware.CMake' -VerifyCommand 'cmake'
    }
