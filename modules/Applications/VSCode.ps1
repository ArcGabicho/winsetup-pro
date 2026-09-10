# modules/Applications/VSCode.ps1 - Visual Studio Code (user-scope install).

New-WinSetupComponent -Id 'vscode' -Name 'Visual Studio Code' -Category 'Development' `
    -Description 'Visual Studio Code editor' `
    -Tags @('editor') `
    -Test {
        param($Context)
        $version = Get-WinSetupExeVersion -Command 'code'
        $userExe = Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\Code.exe'
        $systemExe = Join-Path $env:ProgramFiles 'Microsoft VS Code\Code.exe'
        if ($version) {
            return New-WinSetupDetectionResult -Installed $true -Version $version -Summary "code $version"
        }
        if ((Test-Path -LiteralPath $userExe) -or (Test-Path -LiteralPath $systemExe)) {
            return New-WinSetupDetectionResult -Installed $true -Summary 'installed (code CLI not on PATH)'
        }
        New-WinSetupDetectionResult -Installed $false
    } `
    -Install {
        param($Context)
        Install-WinSetupWingetPackage -Id 'Microsoft.VisualStudioCode' -Scope 'user' `
            -VerifyCommand 'code' `
            -VerifyPath '%LOCALAPPDATA%\Programs\Microsoft VS Code\Code.exe'
    }
