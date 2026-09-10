# modules/Applications/Npm.ps1 - npm.
#
# npm ships with Node.js, so this component has no installer of its own; it
# depends on 'nodejs' and simply verifies that npm ended up on PATH. Listing
# "npm" in a profile therefore pulls in Node.js.

New-WinSetupComponent -Id 'npm' -Name 'npm' -Category 'Development' `
    -Description 'Node package manager (provided by Node.js)' `
    -Tags @('javascript', 'package-manager') `
    -DependsOn @('nodejs') `
    -Test {
        param($Context)
        $version = Get-WinSetupExeVersion -Command 'npm'
        if (-not $version) { return New-WinSetupDetectionResult -Installed $false -Summary 'install Node.js to get npm' }
        New-WinSetupDetectionResult -Installed $true -Version $version -Summary "npm $version"
    }
