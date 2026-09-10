# modules/Applications/Neovim.ps1

New-WinSetupComponent -Id 'neovim' -Name 'Neovim' -Category 'Development' `
    -Description 'Neovim text editor (nvim)' -Tags @('editor') `
    -Test {
        param($Context)
        $v = Get-WinSetupExeVersion -Command 'nvim'
        if (-not $v) { return New-WinSetupDetectionResult -Installed $false }
        New-WinSetupDetectionResult -Installed $true -Version $v -Summary "nvim $v"
    } `
    -Install {
        param($Context)
        Install-WinSetupWingetPackage -Id 'Neovim.Neovim' -VerifyCommand 'nvim'
    }
