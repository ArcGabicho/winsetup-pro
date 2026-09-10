# WinSetupPro launcher module.
#
# Provides the `winsetup` command. It is a thin dispatcher:
#   * no arguments (interactive host)  -> open the GUI
#   * any CLI flag / -NonInteractive   -> delegate verbatim to WinSetup.ps1
#   * --gui [ -Profile x ]             -> open the GUI, optionally preselected
#
# The engine (WinSetup.ps1 / modules\Core) is never bypassed or duplicated.

function Get-WinSetupHome {
    # 1. explicit override  2. env var set by install-launcher.ps1
    # 3. repo layout relative to this module
    if ($env:WINSETUP_HOME -and (Test-Path -LiteralPath (Join-Path $env:WINSETUP_HOME 'WinSetup.ps1'))) {
        return (Resolve-Path -LiteralPath $env:WINSETUP_HOME).Path
    }
    $candidate = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..') -ErrorAction SilentlyContinue
    if ($candidate -and (Test-Path -LiteralPath (Join-Path $candidate 'WinSetup.ps1'))) {
        return $candidate.Path
    }
    throw 'Could not locate the WinSetup Pro repository. Set $env:WINSETUP_HOME to the checkout path.'
}

function Get-WinSetupGuiExe {
    param([string]$RepoHome)
    if ($env:WINSETUP_GUI_EXE -and (Test-Path -LiteralPath $env:WINSETUP_GUI_EXE)) {
        return $env:WINSETUP_GUI_EXE
    }
    $names = @('WinSetup.Pro.UI.exe')
    $roots = @(
        (Join-Path $RepoHome 'ui\WinSetup.Pro.UI\bin\Release\net10.0-windows\win-x64\publish'),
        (Join-Path $RepoHome 'ui\WinSetup.Pro.UI\bin\Release\net10.0-windows\win-x64'),
        (Join-Path $RepoHome 'ui\WinSetup.Pro.UI\bin\Release\net10.0-windows'),
        (Join-Path $RepoHome 'ui\WinSetup.Pro.UI\bin\Debug\net10.0-windows'),
        (Join-Path $RepoHome 'ui\publish')
    )
    foreach ($r in $roots) {
        foreach ($n in $names) {
            $p = Join-Path $r $n
            if (Test-Path -LiteralPath $p) { return $p }
        }
    }
    return $null
}

function Invoke-WinSetupCli {
    # Forward args to WinSetup.ps1 through a child PowerShell so that tokens like
    # -Status / -DryRun are parsed as switches (array splatting would pass them
    # as positional values). No Invoke-Expression, no string building.
    param([string]$Entry, [string[]]$ForwardArgs)
    $exeName = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
    $psExe = Join-Path $PSHOME $exeName
    if (-not (Test-Path -LiteralPath $psExe)) {
        $psExe = try { (Get-Process -Id $PID -ErrorAction Stop).Path } catch { $null }
    }
    if (-not $psExe) {
        $psExe = (Get-Command pwsh, powershell -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    }
    & $psExe -NoLogo -NoProfile -File $Entry @ForwardArgs
    return $LASTEXITCODE
}

function Test-WinSetupInteractiveHost {
    # A real console the user can see. Not a CI / -NonInteractive / redirected run.
    if ([Environment]::UserInteractive -eq $false) { return $false }
    if ($Host.Name -eq 'Default Host') { return $false }
    return $true
}

$script:CliFlagPattern =
    '^-{1,2}(profile|setupprofile|install|list|status|diagnose|resume|update|wsl|git|ssh|dotfiles|dotfilesrepository|dryrun|noninteractive|configfile|loglevel|export|import)$'

function Get-WinSetupLaunchMode {
    <#
    .SYNOPSIS
        Decides GUI vs CLI from the argument list. Pure - no side effects - so
        it can be unit tested.
    .OUTPUTS
        [pscustomobject] @{ Gui = <bool>; ForceGui = <bool>; Forward = <string[]>; GuiArgs = <string[]> }
    #>
    param([string[]]$Arguments, [switch]$InteractiveHost)

    $argList = @($Arguments | Where-Object { $null -ne $_ -and $_ -ne '' })
    $forceGui = $false
    $forward = @()
    foreach ($a in $argList) {
        if ($a -eq '--gui' -or $a -eq '-Gui') { $forceGui = $true } else { $forward += $a }
    }
    $forward = @($forward)

    $hasCliFlag = [bool](@($forward | Where-Object { $_ -match $script:CliFlagPattern }).Count)
    $nonInteractive = ($forward -contains '-NonInteractive')
    $gui = $forceGui -or (-not $hasCliFlag -and -not $nonInteractive -and $InteractiveHost)

    $guiArgs = @()
    for ($i = 0; $i -lt $forward.Count; $i++) {
        if ($forward[$i] -match '^-{1,2}(profile|setupprofile)$' -and $i + 1 -lt $forward.Count) {
            $guiArgs += @('--profile', $forward[$i + 1]); $i++
        }
        elseif ($forward[$i] -match '^-{1,2}dryrun$') { $guiArgs += '--dry-run' }
    }

    [pscustomobject]@{ Gui = $gui; ForceGui = $forceGui; Forward = $forward; GuiArgs = @($guiArgs) }
}

function Invoke-WinSetup {
    <#
    .SYNOPSIS
        WinSetup Pro entry point. `winsetup` with no arguments opens the GUI;
        with CLI flags it runs the classic scriptable flow.
    .EXAMPLE
        winsetup
    .EXAMPLE
        winsetup -Profile dotnet
    .EXAMPLE
        winsetup -Profile enterprise -ConfigFile .\company.json -NonInteractive
    .EXAMPLE
        winsetup --gui -Profile dotnet
    #>
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments = $true)] [string[]]$Arguments)

    $repoHome = Get-WinSetupHome
    $entry = Join-Path $repoHome 'WinSetup.ps1'

    $mode = Get-WinSetupLaunchMode -Arguments $Arguments -InteractiveHost:(Test-WinSetupInteractiveHost)
    $forwarded = $mode.Forward

    if ($mode.Gui) {
        $exe = Get-WinSetupGuiExe -RepoHome $repoHome
        $guiArgs = $mode.GuiArgs

        if ($exe) {
            Write-Verbose "Launching GUI: $exe $($guiArgs -join ' ')"
            Start-Process -FilePath $exe -ArgumentList $guiArgs -WorkingDirectory $repoHome
            return
        }

        $dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
        $proj = Join-Path $repoHome 'ui\WinSetup.Pro.UI\WinSetup.Pro.UI.csproj'
        if ($dotnet -and (Test-Path -LiteralPath $proj)) {
            Write-Host 'GUI is not published yet; running it from source (first run may take a moment)...' -ForegroundColor Yellow
            $runArgs = @('run', '--project', $proj, '-c', 'Release')
            if ($guiArgs.Count) { $runArgs += @('--') + $guiArgs }
            Start-Process -FilePath $dotnet.Source -ArgumentList $runArgs -WorkingDirectory $repoHome
            return
        }

        Write-Host 'The WinSetup Pro GUI is not built. Falling back to the interactive console.' -ForegroundColor Yellow
        Write-Host "Build it with:  dotnet publish `"$proj`" -c Release -r win-x64 --self-contained" -ForegroundColor DarkGray
        Write-Host ''
        $global:LASTEXITCODE = Invoke-WinSetupCli -Entry $entry -ForwardArgs $forwarded
        return
    }

    # CLI mode: run the classic flow and surface its exit code without killing
    # the caller's session. The bin\winsetup shim turns this into a real exit.
    $global:LASTEXITCODE = Invoke-WinSetupCli -Entry $entry -ForwardArgs $forwarded
}

Set-Alias -Name winsetup -Value Invoke-WinSetup
Export-ModuleMember -Function 'Invoke-WinSetup', 'Get-WinSetupLaunchMode', 'Get-WinSetupHome', 'Get-WinSetupGuiExe' -Alias 'winsetup'
