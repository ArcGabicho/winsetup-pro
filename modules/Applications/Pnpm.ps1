# modules/Applications/Pnpm.ps1 - pnpm (installed via winget, independent of npm).

New-WinSetupComponent -Id 'pnpm' -Name 'pnpm' -Category 'Development' `
    -Description 'Fast, disk-efficient Node package manager' `
    -Tags @('javascript', 'package-manager') `
    -Test {
        param($Context)
        $version = Get-WinSetupExeVersion -Command 'pnpm'
        if (-not $version) { return New-WinSetupDetectionResult -Installed $false }
        New-WinSetupDetectionResult -Installed $true -Version $version -Summary "pnpm $version"
    } `
    -Install {
        param($Context)
        Install-WinSetupWingetPackage -Id 'pnpm.pnpm' -VerifyCommand 'pnpm'
    }
