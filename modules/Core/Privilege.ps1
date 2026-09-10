# Privilege.ps1 - administrator detection. WinSetup Pro never elevates silently;
# it detects the situation and explains why elevation is required.

function Test-WinSetupAdmin {
    <#
    .SYNOPSIS
        Returns $true when the current session is running elevated.
    #>
    try {
        $identity  = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Get-WinSetupPrivilegeReport {
    <#
    .SYNOPSIS
        Summarises the elevation state and which components asked for it.
    #>
    param([string[]]$RequiredBy = @())
    [pscustomobject]@{
        IsAdmin    = Test-WinSetupAdmin
        RequiredBy = @($RequiredBy)
    }
}

function Assert-WinSetupAdmin {
    <#
    .SYNOPSIS
        Throws a descriptive error when the session is not elevated.
    #>
    param([string]$Reason = 'this operation changes machine-scoped settings.')
    if (-not (Test-WinSetupAdmin)) {
        throw ("Administrator privileges are required because {0} " -f $Reason) +
              'Re-run WinSetup Pro from an elevated PowerShell session (Run as administrator).'
    }
}
