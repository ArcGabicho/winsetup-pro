# ComponentModel.ps1 - the unit of work in WinSetup Pro.
#
# A component is a self-describing object with three script blocks:
#   Test      -> [pscustomobject] detection result (MUST be read-only)
#   Install   -> performs installation; throws on failure
#   Configure -> idempotent configuration; throws on failure
#
# Every script block receives the engine $Context as its first argument.

function New-WinSetupComponent {
    <#
    .SYNOPSIS
        Creates a validated component descriptor.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Category,
        [string]$Description = '',
        [string[]]$Tags = @(),
        [bool]$Critical = $false,
        [bool]$RequiresAdmin = $false,
        [string[]]$DependsOn = @(),
        [Parameter(Mandatory)][scriptblock]$Test,
        [scriptblock]$Install,
        [scriptblock]$Configure
    )

    [pscustomobject]@{
        Id            = $Id.ToLowerInvariant()
        Name          = $Name
        Category      = $Category
        Description   = $Description
        Tags          = @($Tags)
        Critical      = $Critical
        RequiresAdmin = $RequiresAdmin
        DependsOn     = @($DependsOn | ForEach-Object { $_.ToLowerInvariant() })
        Test          = $Test
        Install       = $Install
        Configure     = $Configure
        Source        = $null
    }
}

function New-WinSetupDetectionResult {
    <#
    .SYNOPSIS
        Standard return value for a component's Test block.
    .PARAMETER Installed
        Whether the software/feature is present.
    .PARAMETER Configured
        Whether it also matches the desired configuration. When $false and the
        component has a Configure block, the engine will (re)configure it.
    #>
    param(
        [Parameter(Mandatory)][bool]$Installed,
        [bool]$Configured = $true,
        [string]$Version,
        [string]$Summary
    )
    [pscustomobject]@{
        Installed  = $Installed
        Configured = $Configured
        Version    = $Version
        Summary    = $Summary
    }
}

function Test-WinSetupComponentSchema {
    <#
    .SYNOPSIS
        Returns an array of problems with a component descriptor (empty = valid).
    #>
    param($Component)

    $issues = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Component) { return @('component is null') }

    foreach ($prop in @('Id', 'Name', 'Category', 'Test')) {
        if (-not $Component.PSObject.Properties[$prop] -or -not $Component.$prop) {
            $issues.Add("missing required property '$prop'")
        }
    }
    foreach ($prop in @('Test', 'Install', 'Configure')) {
        $value = if ($Component.PSObject.Properties[$prop]) { $Component.$prop } else { $null }
        if ($value -and $value -isnot [scriptblock]) {
            $issues.Add("'$prop' must be a scriptblock")
        }
    }
    return $issues.ToArray()
}
