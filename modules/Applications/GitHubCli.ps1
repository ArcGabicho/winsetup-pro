# modules/Applications/GitHubCli.ps1 - GitHub CLI (gh).
#
# Optional Configure: sets `gh config` git_protocol only when the configuration
# asks for it (githubCli.gitProtocol = "ssh" | "https"). Authentication
# (`gh auth login`) is deliberately NOT automated - it is interactive and must
# not store tokens on the user's behalf.

New-WinSetupComponent -Id 'github-cli' -Name 'GitHub CLI' -Category 'Development' `
    -Description 'GitHub command-line tool (gh)' `
    -Tags @('git', 'github') `
    -Test {
        param($Context)
        $version = Get-WinSetupExeVersion -Command 'gh'
        if (-not $version) { return New-WinSetupDetectionResult -Installed $false }

        $wantProtocol = [string](Get-WinSetupConfigValue -Config $Context.Config -Path 'githubCli.gitProtocol' -Default '')
        $configured = $true
        if ($wantProtocol) {
            $current = (& gh config get git_protocol) 2>$null
            if ($current -ne $wantProtocol) { $configured = $false }
        }
        New-WinSetupDetectionResult -Installed $true -Version $version -Configured $configured -Summary "gh $version"
    } `
    -Install {
        param($Context)
        Install-WinSetupWingetPackage -Id 'GitHub.cli' -VerifyCommand 'gh'
    } `
    -Configure {
        param($Context)
        $wantProtocol = [string](Get-WinSetupConfigValue -Config $Context.Config -Path 'githubCli.gitProtocol' -Default '')
        if (-not $wantProtocol) { return }
        $current = (& gh config get git_protocol) 2>$null
        if ($current -eq $wantProtocol) { return }
        Write-WinSetupLog -Level INFO -Module 'github-cli' -Message "gh config set git_protocol $wantProtocol"
        & gh config set git_protocol $wantProtocol
        if ($LASTEXITCODE -ne 0) { throw 'gh config set git_protocol failed.' }
    }
