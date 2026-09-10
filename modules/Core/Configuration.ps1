# Configuration.ps1 - declarative configuration: layering, lookup, validation
# and translation of a config document into an ordered list of component ids.

function Merge-WinSetupConfig {
    <#
    .SYNOPSIS
        Deep-merges $Override onto $Base. Nested dictionaries merge recursively;
        the known list keys (applications / fonts / folders) union without
        duplicates; every other value is replaced by the override.
    #>
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Base,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Override
    )

    $unionKeys = @('applications', 'fonts', 'folders')
    $result = [ordered]@{}
    foreach ($key in $Base.Keys) { $result[$key] = $Base[$key] }

    foreach ($key in $Override.Keys) {
        $ov = $Override[$key]
        if ($result.Contains($key)) {
            $bv = $result[$key]
            if ($bv -is [System.Collections.IDictionary] -and $ov -is [System.Collections.IDictionary]) {
                $result[$key] = Merge-WinSetupConfig -Base $bv -Override $ov
            }
            elseif ($unionKeys -contains $key -and $bv -is [System.Collections.IEnumerable] -and $bv -isnot [string]) {
                $result[$key] = @(@($bv) + @($ov) | Where-Object { $_ } | Select-Object -Unique)
            }
            else {
                $result[$key] = $ov
            }
        }
        else {
            $result[$key] = $ov
        }
    }
    return $result
}

function Get-WinSetupConfigValue {
    <#
    .SYNOPSIS
        Resolves a dotted path (e.g. 'settings.errorPolicy.critical') against a
        config graph, returning $Default when any segment is missing.
    #>
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$Path,
        $Default = $null
    )

    $node = $Config
    foreach ($seg in $Path.Split('.')) {
        if ($null -eq $node) { return $Default }
        if ($node -is [System.Collections.IDictionary]) {
            if ($node.Contains($seg)) { $node = $node[$seg] } else { return $Default }
        }
        elseif ($node.PSObject -and $node.PSObject.Properties[$seg]) {
            $node = $node.$seg
        }
        else {
            return $Default
        }
    }
    if ($null -eq $node) { return $Default }
    # Note: an empty collection collapses to $null through PowerShell's
    # return-value unrolling. Callers that expect a list must wrap with @()
    # and pass -Default @().
    return $node
}

function Get-WinSetupConfig {
    <#
    .SYNOPSIS
        Builds the effective configuration by layering:
        config/default.json  <-  profile file  <-  user config file  <-  CLI overrides.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$ProfileName,
        [string]$ConfigPath,
        [string[]]$InstallOnly,
        [string]$LogLevelOverride
    )

    $defaultPath = [System.IO.Path]::Combine($Root, 'config', 'default.json')
    $cfg = Read-WinSetupJsonFile -Path $defaultPath

    if ($ProfileName) {
        $candidates = @(
            [System.IO.Path]::Combine($Root, 'profiles', "$ProfileName.json")
            [System.IO.Path]::Combine($Root, 'config', "$ProfileName.json")
        )
        $profileFile = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if (-not $profileFile) {
            throw "Profile '$ProfileName' not found (looked in profiles\ and config\)."
        }
        $cfg = Merge-WinSetupConfig -Base $cfg -Override (Read-WinSetupJsonFile -Path $profileFile)
        $cfg['profile'] = $ProfileName
    }

    if ($ConfigPath) {
        $cfg = Merge-WinSetupConfig -Base $cfg -Override (Read-WinSetupJsonFile -Path $ConfigPath)
    }

    if ($InstallOnly) {
        $cfg['applications'] = @($InstallOnly)
    }

    if ($LogLevelOverride) {
        if (-not ($cfg['settings'] -is [System.Collections.IDictionary])) { $cfg['settings'] = [ordered]@{} }
        $cfg['settings']['logLevel'] = $LogLevelOverride
    }

    return $cfg
}

function Test-WinSetupConfig {
    <#
    .SYNOPSIS
        Lightweight structural validation. Returns an array of human-readable
        issue strings (empty when the document is acceptable).
    #>
    param([Parameter(Mandatory)]$Config)

    $issues = New-Object System.Collections.Generic.List[string]

    $apps = Get-WinSetupConfigValue -Config $Config -Path 'applications' -Default @()
    if ($null -ne $apps -and (($apps -is [string]) -or ($apps -isnot [System.Collections.IEnumerable]))) {
        $issues.Add("'applications' must be an array of component ids.")
    }

    $level = Get-WinSetupConfigValue -Config $Config -Path 'settings.logLevel' -Default 'INFO'
    if ($level -notin @('DEBUG', 'INFO', 'SUCCESS', 'WARNING', 'ERROR')) {
        $issues.Add("settings.logLevel '$level' is not a recognised level.")
    }

    return $issues.ToArray()
}

function Resolve-WinSetupPlan {
    <#
    .SYNOPSIS
        Converts a configuration document into a de-duplicated, ordered list of
        component ids to process.
    #>
    param([Parameter(Mandatory)]$Config)

    $plan = New-Object System.Collections.Generic.List[string]

    foreach ($app in @(Get-WinSetupConfigValue -Config $Config -Path 'applications' -Default @())) {
        if ($app) { $plan.Add([string]$app) }
    }

    # Feature blocks that map 1:1 onto a component id when enabled.
    foreach ($feature in @('git', 'wsl', 'ssh')) {
        if ((Get-WinSetupConfigValue -Config $Config -Path "$feature.enabled" -Default $false) -eq $true) {
            $plan.Add($feature)
        }
    }

    # Config-driven environment components: included when they have work to do.
    if (@(Get-WinSetupConfigValue -Config $Config -Path 'folders' -Default @() | Where-Object { $_ }).Count -gt 0) {
        $plan.Add('folders')
    }
    if (@(Get-WinSetupConfigValue -Config $Config -Path 'fonts' -Default @() | Where-Object { $_ }).Count -gt 0) {
        $plan.Add('fonts')
    }
    $environment = Get-WinSetupConfigValue -Config $Config -Path 'environment' -Default $null
    if ($environment -is [System.Collections.IDictionary]) {
        $hasUser    = ($environment['user']    -is [System.Collections.IDictionary]) -and ($environment['user'].Count -gt 0)
        $hasMachine = ($environment['machine'] -is [System.Collections.IDictionary]) -and ($environment['machine'].Count -gt 0)
        $hasPath    = @($environment['path'] | Where-Object { $_ }).Count -gt 0
        if ($hasUser -or $hasMachine -or $hasPath) { $plan.Add('env-vars') }
    }

    return @($plan | Where-Object { $_ } | Select-Object -Unique)
}
