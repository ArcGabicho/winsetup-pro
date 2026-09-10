# modules/Applications/Python.ps1 - CPython.
# python.version = "3.12" (default) -> winget id Python.Python.3.12
#
# Detection ignores the Windows "App execution alias" stub in WindowsApps, which
# resolves as python.exe but only opens the Store.

New-WinSetupComponent -Id 'python' -Name 'Python' -Category 'Development' `
    -Description 'Python interpreter and pip' `
    -Tags @('python', 'runtime') `
    -Test {
        param($Context)
        $real = Get-Command python.exe -ErrorAction SilentlyContinue |
            Where-Object { $_.Source -and $_.Source -notmatch 'WindowsApps' } | Select-Object -First 1
        if (-not $real) {
            $launcher = Get-Command py.exe -ErrorAction SilentlyContinue
            if ($launcher) {
                $v = $null
                try { if ((& $launcher.Source -3 --version 2>$null) -match '(\d+\.\d+\.\d+)') { $v = $Matches[1] } } catch { }
                if ($v) { return New-WinSetupDetectionResult -Installed $true -Version $v -Summary "python $v (via py launcher)" }
            }
            return New-WinSetupDetectionResult -Installed $false
        }
        $version = $null
        try { if ((& $real.Source --version 2>$null) -match '(\d+\.\d+\.\d+)') { $version = $Matches[1] } } catch { }
        New-WinSetupDetectionResult -Installed $true -Version $version -Summary "python $version"
    } `
    -Install {
        param($Context)
        $ver = [string](Get-WinSetupConfigValue -Config $Context.Config -Path 'python.version' -Default '3.12')
        Install-WinSetupWingetPackage -Id ("Python.Python.{0}" -f $ver) -VerifyCommand 'python'
        if (-not (Get-Command python.exe -ErrorAction SilentlyContinue | Where-Object { $_.Source -notmatch 'WindowsApps' })) {
            Write-WinSetupLog -Level WARNING -Module 'python' -Message 'Python installed - open a new terminal so PATH picks it up.'
        }
    }
