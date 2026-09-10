# modules/Applications/WindowsTerminal.ps1 - Windows Terminal.
# Often preinstalled on Windows 11; detection uses the MSIX package so a
# preinstalled copy is correctly reported as present.

New-WinSetupComponent -Id 'windows-terminal' -Name 'Windows Terminal' -Category 'Development' `
    -Description 'Modern terminal for the Windows command-line tools' `
    -Tags @('terminal') `
    -Test {
        param($Context)
        $pkg = $null
        try { $pkg = Get-AppxPackage -Name 'Microsoft.WindowsTerminal*' -ErrorAction SilentlyContinue | Select-Object -First 1 } catch { }
        if (-not $pkg) {
            if (Get-Command wt -ErrorAction SilentlyContinue) {
                return New-WinSetupDetectionResult -Installed $true -Summary 'wt.exe present'
            }
            return New-WinSetupDetectionResult -Installed $false
        }
        New-WinSetupDetectionResult -Installed $true -Version ([string]$pkg.Version) -Summary $pkg.Name
    } `
    -Install {
        param($Context)
        Install-WinSetupWingetPackage -Id 'Microsoft.WindowsTerminal' -VerifyCommand 'wt'
    }
