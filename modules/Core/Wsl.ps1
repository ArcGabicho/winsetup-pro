# Wsl.ps1 - shared helpers for the WSL component.
#
# wsl.exe historically emits UTF-16LE and localises its status text, which makes
# scraping fragile. These helpers force UTF-8 (WSL_UTF8 + console encoding),
# strip stray NUL bytes, and read locale-independent facts from the registry
# where possible.

function Invoke-WinSetupWsl {
    <#
    .SYNOPSIS
        Runs wsl.exe with clean UTF-8 capture. Returns { ExitCode; Lines; Text }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        # Timeboxed: on a host where WSL isn't set up, `wsl --list` can hang for
        # tens of seconds waiting on LxssManager.
        [int]$TimeoutMs = 15000
    )

    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if (-not $wsl) { throw 'wsl.exe is not available on this system.' }

    $env:WSL_UTF8 = '1'
    $res = Invoke-WinSetupProcess -FilePath $wsl.Source -Arguments $Arguments -TimeoutMs $TimeoutMs `
        -StdoutEncoding ([System.Text.Encoding]::UTF8) -PassThru

    $lines = @()
    if ($res.StdOut) {
        $lines = @(
            ($res.StdOut -split "`n") |
                ForEach-Object { ($_ -replace "`0", '').TrimEnd("`r") } |
                Where-Object { $_ -ne '' }
        )
    }
    [pscustomobject]@{
        ExitCode = $res.ExitCode
        Lines    = $lines
        Text     = ($lines -join "`n")
        TimedOut = $res.TimedOut
    }
}

function Get-WinSetupWslInfo {
    <#
    .SYNOPSIS
        Read-only snapshot of the WSL state. Fields that cannot be determined
        (e.g. optional-feature state when not elevated) are left $null.
    #>
    [CmdletBinding()]
    param()

    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    $info = [pscustomobject]@{
        Present             = [bool]$wsl
        FeatureWsl          = $null
        FeatureVmPlatform   = $null
        DefaultVersion      = $null
        Distributions       = @()
        DefaultDistribution = $null
    }
    if (-not $wsl) { return $info }

    try {
        $lxss = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss' -ErrorAction Stop
        if ($null -ne $lxss.DefaultVersion) { $info.DefaultVersion = [int]$lxss.DefaultVersion }
    } catch { }

    foreach ($pair in @(
            @('Microsoft-Windows-Subsystem-Linux', 'FeatureWsl'),
            @('VirtualMachinePlatform', 'FeatureVmPlatform'))) {
        try {
            $feature = Get-WindowsOptionalFeature -Online -FeatureName $pair[0] -ErrorAction Stop
            $info.$($pair[1]) = ($feature.State -eq 'Enabled')
        } catch { }
    }

    try {
        $list = Invoke-WinSetupWsl -Arguments @('--list', '--quiet')
        if ($list.ExitCode -eq 0) {
            $info.Distributions = @($list.Lines | Where-Object { $_ -and $_ -notmatch '\s' })
        }
    } catch { }

    try {
        $verbose = Invoke-WinSetupWsl -Arguments @('--list', '--verbose')
        foreach ($line in $verbose.Lines) {
            if ($line -match '^\s*\*\s+(\S+)') { $info.DefaultDistribution = $Matches[1] }
        }
    } catch { }

    return $info
}

function Format-WinSetupWslConfig {
    <#
    .SYNOPSIS
        Renders a [wsl2] .wslconfig body from a settings dictionary.
    #>
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Wsl2Settings)

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Managed by WinSetup Pro')
    $lines.Add('[wsl2]')
    foreach ($key in $Wsl2Settings.Keys) {
        $value = $Wsl2Settings[$key]
        if ($value -is [bool]) { $value = ([string]$value).ToLowerInvariant() }
        $lines.Add(('{0}={1}' -f $key, $value))
    }
    return (($lines -join "`r`n") + "`r`n")
}
