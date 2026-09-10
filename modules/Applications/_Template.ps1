# modules/Applications/_Template.ps1
#
# Copy this file to modules/<Category>/<Name>.ps1 and fill it in.
# Files whose name starts with "_" are ignored by the component loader.
# Full guide: docs/MODULES.md
#
# Rules:
#   * Return the descriptor (last statement) - do not assign it to a variable.
#   * No side effects at load time.
#   * Test must be READ-ONLY and return New-WinSetupDetectionResult.
#   * Install / Configure THROW on failure; the engine handles retry/skip/abort.
#   * A script block may use engine-exported helpers, $Context and its own local
#     variables only - never a function defined at file scope.
#   * Idempotent: a second run must be a no-op.

New-WinSetupComponent -Id 'example-tool' -Name 'Example Tool' -Category 'Development' `
    -Description 'One-line description shown by -List' `
    -Tags @('example') `
    -Critical $false `
    -RequiresAdmin $false `
    -DependsOn @() `
    -Test {
        param($Context)
        $version = Get-WinSetupExeVersion -Command 'example'
        if (-not $version) { return New-WinSetupDetectionResult -Installed $false }
        # For a config task, keep Installed $true always and drive work via -Configured.
        New-WinSetupDetectionResult -Installed $true -Version $version -Summary "example $version"
    } `
    -Install {
        param($Context)
        # winget path (preferred). -VerifyCommand / -VerifyPath make a non-zero
        # "already installed" exit code benign; anything else throws with an
        # elevation hint.
        Install-WinSetupWingetPackage -Id 'Publisher.Example' -VerifyCommand 'example'
    } `
    -Configure {
        param($Context)
        # Idempotent configuration only. Compare desired vs. current before writing.
        # Back up anything you might replace:  Backup-WinSetupFile -Context $Context -Path <file> -Category 'example'
        $want = [string](Get-WinSetupConfigValue -Config $Context.Config -Path 'example.setting' -Default '')
        if (-not $want) { return }
        # ...apply $want only if it differs from the current value...
    }
