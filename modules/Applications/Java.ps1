# modules/Applications/Java.ps1 - Eclipse Temurin JDK.
# java.version = "21" (default) -> winget id EclipseAdoptium.Temurin.21.JDK

New-WinSetupComponent -Id 'java' -Name 'Java (Temurin JDK)' -Category 'Development' `
    -Description 'Eclipse Temurin OpenJDK' -Tags @('java', 'runtime') `
    -Test {
        param($Context)
        $j = Get-Command java -ErrorAction SilentlyContinue
        if (-not $j) { return New-WinSetupDetectionResult -Installed $false }
        $v = $null
        try {
            $raw = (& $j.Source -version 2>&1 | Out-String)
            if ($raw -match '"(\d+(?:\.\d+)+)') { $v = $Matches[1] }
            elseif ($raw -match 'version "?(\d+)') { $v = $Matches[1] }
        } catch { }
        New-WinSetupDetectionResult -Installed $true -Version $v -Summary "java $v"
    } `
    -Install {
        param($Context)
        $ver = [string](Get-WinSetupConfigValue -Config $Context.Config -Path 'java.version' -Default '21')
        Install-WinSetupWingetPackage -Id ("EclipseAdoptium.Temurin.{0}.JDK" -f $ver) -VerifyCommand 'java'
    }
