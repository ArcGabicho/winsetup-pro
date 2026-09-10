# modules/Applications/VisualStudio.ps1 - Visual Studio 2022 Community.
# Large machine-wide installer -> RequiresAdmin. Workloads are added afterwards
# with the Visual Studio Installer (or a vsconfig file) - not by WinSetup.

New-WinSetupComponent -Id 'visualstudio' -Name 'Visual Studio 2022' -Category 'Development' `
    -Description 'Visual Studio 2022 Community IDE' `
    -Tags @('ide', 'dotnet') `
    -RequiresAdmin $true `
    -Test {
        param($Context)
        $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
        if (Test-Path -LiteralPath $vswhere) {
            $ver = & $vswhere -products * -property installationVersion -nologo 2>$null | Select-Object -First 1
            if ($ver) { return New-WinSetupDetectionResult -Installed $true -Version ([string]$ver) -Summary 'Visual Studio present' }
        }
        foreach ($p in @(
                (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\2022'),
                (Join-Path $env:ProgramFiles 'Microsoft Visual Studio\2022'))) {
            if (Test-Path -LiteralPath $p) { return New-WinSetupDetectionResult -Installed $true -Summary 'Visual Studio 2022 present' }
        }
        New-WinSetupDetectionResult -Installed $false
    } `
    -Install {
        param($Context)
        Install-WinSetupWingetPackage -Id 'Microsoft.VisualStudio.2022.Community' -VerifyPath '%ProgramFiles%\Microsoft Visual Studio\2022'
        Write-WinSetupLog -Level WARNING -Module 'visualstudio' -Message 'Visual Studio installed. Add workloads (".NET desktop", "ASP.NET", "Desktop C++", ...) via the Visual Studio Installer.'
    }
