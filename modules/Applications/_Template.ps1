# modules/Applications/_Template.ps1
#
# Copy this file to modules/<Category>/<Name>.ps1 and fill it in.
# Files whose name starts with "_" are ignored by the component loader.
#
# Rules:
#   * Return the descriptor (last statement) - do not assign it to a variable.
#   * No side effects at load time.
#   * Test must be read-only and return New-WinSetupDetectionResult.
#   * Install / Configure throw on failure; the engine handles retry/skip/abort.
#   * Only rely on engine-exported helpers, $Context and local variables.

New-WinSetupComponent -Id 'example-tool' -Name 'Example Tool' -Category 'Development' `
    -Description 'One-line description shown by -List' `
    -Tags @('example') `
    -Critical $false `
    -RequiresAdmin $false `
    -DependsOn @() `
    -Test {
        param($Context)
        $cmd = Get-Command example.exe -ErrorAction SilentlyContinue
        if (-not $cmd) { return New-WinSetupDetectionResult -Installed $false }
        New-WinSetupDetectionResult -Installed $true -Configured $true -Version 'unknown'
    } `
    -Install {
        param($Context)
        if (-not $Context.System.WingetPresent) { throw 'winget is required.' }
        & winget install --id 'Publisher.Example' --exact --source winget `
            --accept-package-agreements --accept-source-agreements --silent | Out-Null
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {
            throw "winget exited with code $LASTEXITCODE"
        }
    } `
    -Configure {
        param($Context)
        # Idempotent configuration only. Compare desired vs current before writing.
    }
