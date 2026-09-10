# modules/Applications/JetBrainsToolbox.ps1 - JetBrains Toolbox (manages IDEs).

New-WinSetupComponent -Id 'jetbrains-toolbox' -Name 'JetBrains Toolbox' -Category 'Development' `
    -Description 'JetBrains Toolbox App (installs/updates IntelliJ, Rider, PyCharm, ...)' `
    -Tags @('ide') `
    -Test {
        param($Context)
        $exe = Join-Path $env:LOCALAPPDATA 'JetBrains\Toolbox\bin\jetbrains-toolbox.exe'
        if (Test-Path -LiteralPath $exe) { return New-WinSetupDetectionResult -Installed $true -Summary 'installed' }
        New-WinSetupDetectionResult -Installed $false
    } `
    -Install {
        param($Context)
        Install-WinSetupWingetPackage -Id 'JetBrains.Toolbox' -Scope 'user' `
            -VerifyPath '%LOCALAPPDATA%\JetBrains\Toolbox\bin\jetbrains-toolbox.exe'
    }
