# SystemDetection.ps1 - read-only inspection of the host: OS, architecture,
# PowerShell, winget, WSL, connectivity and free disk space.

function Get-WinSetupSystemInfo {
    <#
    .SYNOPSIS
        Returns a snapshot object describing the current machine.
    #>
    [CmdletBinding()]
    param()

    $os = $null; $cs = $null
    try { $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop } catch { }
    try { $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop } catch { }

    $systemDrive = if ($env:SystemDrive) { $env:SystemDrive.TrimEnd(':') } else { 'C' }
    $freeGb = $null
    try {
        $drive = Get-PSDrive -Name $systemDrive -ErrorAction Stop
        if ($null -ne $drive.Free) { $freeGb = [math]::Round($drive.Free / 1GB, 1) }
    } catch { }

    $winget = Get-Command winget -ErrorAction SilentlyContinue
    $wingetVersion = $null
    if ($winget) {
        try { $wingetVersion = ((& winget --version) 2>$null | Select-Object -First 1) } catch { }
    }

    $build = if ($os) { [int]$os.BuildNumber } else { [System.Environment]::OSVersion.Version.Build }

    [pscustomobject]@{
        OsCaption     = if ($os) { $os.Caption } else { 'Unknown Windows' }
        OsVersion     = if ($os) { $os.Version } else { [System.Environment]::OSVersion.Version.ToString() }
        OsBuild       = $build
        IsWindows11   = ($build -ge 22000)
        Architecture  = $env:PROCESSOR_ARCHITECTURE
        PSVersion     = $PSVersionTable.PSVersion.ToString()
        PSEdition     = $PSVersionTable.PSEdition
        IsAdmin       = (Test-WinSetupAdmin)
        WingetPresent = [bool]$winget
        WingetVersion = $wingetVersion
        WingetPath    = if ($winget) { $winget.Source } else { $null }
        WslPresent    = [bool](Get-Command wsl.exe -ErrorAction SilentlyContinue)
        FreeDiskGB    = $freeGb
        SystemDrive   = $env:SystemDrive
        Manufacturer  = if ($cs) { $cs.Manufacturer } else { $null }
        Model         = if ($cs) { $cs.Model } else { $null }
        Hostname      = [System.Environment]::MachineName
        User          = [System.Environment]::UserName
    }
}

function Test-WinSetupInternet {
    <#
    .SYNOPSIS
        Attempts a short TCP connection to verify outbound connectivity.
    #>
    param(
        [string]$TargetHost = 'github.com',
        [int]$Port = 443,
        [int]$TimeoutMs = 3000
    )
    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $async  = $client.BeginConnect($TargetHost, $Port, $null, $null)
        $ok     = $async.AsyncWaitHandle.WaitOne($TimeoutMs)
        if ($ok -and $client.Connected) {
            $client.EndConnect($async)
            return $true
        }
        return $false
    } catch {
        return $false
    } finally {
        if ($client) { $client.Close() }
    }
}

function Get-WinSetupDiagnostics {
    <#
    .SYNOPSIS
        Produces a list of pass/fail readiness checks for the host.
    #>
    param([Parameter(Mandatory)]$Context)

    $sys = $Context.System
    $checks = New-Object System.Collections.Generic.List[object]

    $checks.Add([pscustomobject]@{
        Name = 'Windows 10 / 11'
        Ok   = ($sys.OsCaption -match 'Windows (10|11)')
        Detail = ('{0} (build {1})' -f $sys.OsCaption, $sys.OsBuild)
    })
    $checks.Add([pscustomobject]@{
        Name = 'PowerShell 5.1+'
        Ok   = ($PSVersionTable.PSVersion.Major -ge 5)
        Detail = ('v{0} ({1})' -f $sys.PSVersion, $sys.PSEdition)
    })
    $checks.Add([pscustomobject]@{
        Name = 'PowerShell 7'
        Ok   = ($PSVersionTable.PSVersion.Major -ge 7)
        Detail = if ($PSVersionTable.PSVersion.Major -ge 7) { 'present (recommended)' } else { 'recommended - install PowerShell 7 for the full feature set' }
    })
    $checks.Add([pscustomobject]@{
        Name = '64-bit architecture'
        Ok   = ($sys.Architecture -in @('AMD64', 'ARM64'))
        Detail = $sys.Architecture
    })
    $checks.Add([pscustomobject]@{
        Name = 'Administrator session'
        Ok   = $sys.IsAdmin
        Detail = if ($sys.IsAdmin) { 'elevated' } else { 'not elevated - needed for machine-scope changes' }
    })
    $checks.Add([pscustomobject]@{
        Name = 'winget (App Installer)'
        Ok   = $sys.WingetPresent
        Detail = if ($sys.WingetPresent) { [string]$sys.WingetVersion } else { 'not found - install "App Installer" from the Microsoft Store' }
    })
    $checks.Add([pscustomobject]@{
        Name = 'Internet connectivity'
        Ok   = (Test-WinSetupInternet)
        Detail = 'tcp github.com:443'
    })
    $checks.Add([pscustomobject]@{
        Name = 'Free disk space > 10 GB'
        Ok   = ($null -ne $sys.FreeDiskGB -and $sys.FreeDiskGB -ge 10)
        Detail = ('{0} GB free on {1}' -f $sys.FreeDiskGB, $sys.SystemDrive)
    })
    $checks.Add([pscustomobject]@{
        Name = 'Execution policy'
        Ok   = ((Get-ExecutionPolicy) -ne 'Restricted')
        Detail = (Get-ExecutionPolicy).ToString()
    })

    return $checks.ToArray()
}
