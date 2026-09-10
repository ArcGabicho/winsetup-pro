# modules/Applications/NodeJs.ps1 - Node.js (bundles npm).
# node.channel = "LTS" (default) | "Current".

New-WinSetupComponent -Id 'nodejs' -Name 'Node.js' -Category 'Development' `
    -Description 'Node.js JavaScript runtime (includes npm)' `
    -Tags @('javascript', 'runtime') `
    -Test {
        param($Context)
        $version = Get-WinSetupExeVersion -Command 'node'
        if (-not $version) { return New-WinSetupDetectionResult -Installed $false }
        New-WinSetupDetectionResult -Installed $true -Version $version -Summary "node $version"
    } `
    -Install {
        param($Context)
        $channel = [string](Get-WinSetupConfigValue -Config $Context.Config -Path 'node.channel' -Default 'LTS')
        $id = if ($channel -eq 'Current') { 'OpenJS.NodeJS' } else { 'OpenJS.NodeJS.LTS' }
        Install-WinSetupWingetPackage -Id $id -VerifyCommand 'node'
    }
