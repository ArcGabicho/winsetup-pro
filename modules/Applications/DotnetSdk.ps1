# modules/Applications/DotnetSdk.ps1 - .NET SDK.
# The channel is configurable: dotnet.channel = "9" (default) | "8" | "10" ...
# maps to the winget id Microsoft.DotNet.SDK.<channel>.

New-WinSetupComponent -Id 'dotnet-sdk' -Name '.NET SDK' -Category 'Development' `
    -Description '.NET SDK (dotnet CLI, runtime and build tools)' `
    -Tags @('dotnet', 'sdk') `
    -Test {
        param($Context)
        $version = Get-WinSetupExeVersion -Command 'dotnet'
        if (-not $version) { return New-WinSetupDetectionResult -Installed $false }
        # Any installed SDK counts; the channel just drives which one to add.
        $hasSdk = $false
        try { $hasSdk = @(& dotnet --list-sdks 2>$null).Count -gt 0 } catch { }
        New-WinSetupDetectionResult -Installed ($hasSdk -or [bool]$version) -Version $version -Summary "dotnet $version"
    } `
    -Install {
        param($Context)
        $channel = [string](Get-WinSetupConfigValue -Config $Context.Config -Path 'dotnet.channel' -Default '9')
        Install-WinSetupWingetPackage -Id ("Microsoft.DotNet.SDK.{0}" -f $channel) -VerifyCommand 'dotnet'
    }
