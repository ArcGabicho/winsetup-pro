# Registry.ps1 - convention-based discovery of components.
#
# Any *.ps1 under modules\ (except modules\Core\, *.Tests.ps1 and files whose
# name starts with "_") is executed once and expected to RETURN one or more
# component descriptors. Component files must have no side effects at load time.

function Import-WinSetupComponents {
    <#
    .SYNOPSIS
        Loads every component file under $Path into an ordered id -> descriptor map.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $registry = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Path)) { return $registry }

    $files = Get-ChildItem -LiteralPath $Path -Recurse -Filter '*.ps1' -File |
        Where-Object {
            $_.FullName -notmatch '[\\/]Core[\\/]' -and
            $_.Name -notlike '_*' -and
            $_.Name -notlike '*.Tests.ps1'
        }

    foreach ($file in $files) {
        $produced = $null
        try {
            $produced = & $file.FullName
        } catch {
            Write-WinSetupLog -Level ERROR -Module 'Registry' -Message ("Component file '{0}' failed to load: {1}" -f $file.Name, $_.Exception.Message)
            continue
        }

        foreach ($component in @($produced)) {
            if (-not $component) { continue }
            $problems = Test-WinSetupComponentSchema -Component $component
            if ($problems.Count -gt 0) {
                Write-WinSetupLog -Level WARNING -Module 'Registry' -Message ("Ignoring invalid component in '{0}': {1}" -f $file.Name, ($problems -join '; '))
                continue
            }
            if ($registry.Contains($component.Id)) {
                Write-WinSetupLog -Level WARNING -Module 'Registry' -Message ("Duplicate component id '{0}' from '{1}' ignored." -f $component.Id, $file.Name)
                continue
            }
            $component.Source = $file.FullName
            $registry[$component.Id] = $component
        }
    }

    Write-WinSetupLog -Level INFO -Module 'Registry' -Message ("Discovered {0} component(s)." -f $registry.Count)
    return $registry
}

function Resolve-WinSetupComponentOrder {
    <#
    .SYNOPSIS
        Topologically sorts the requested ids so that DependsOn entries run
        first. Throws on circular dependencies; warns on unknown dependencies.
    #>
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Registry,
        [Parameter(Mandatory)][string[]]$Ids
    )

    $ordered  = New-Object System.Collections.Generic.List[string]
    $visited  = @{}
    $visiting = @{}

    function Resolve-One {
        param([string]$Id)
        if ($visited[$Id]) { return }
        if ($visiting[$Id]) { throw "Circular dependency detected involving component '$Id'." }
        $visiting[$Id] = $true

        $component = $Registry[$Id]
        if ($component) {
            foreach ($dep in $component.DependsOn) {
                if ($Registry.Contains($dep)) {
                    Resolve-One -Id $dep
                } else {
                    Write-WinSetupLog -Level WARNING -Module 'Registry' -Message ("Component '{0}' depends on unknown component '{1}'." -f $Id, $dep)
                }
            }
        }

        $visiting[$Id] = $false
        $visited[$Id]  = $true
        if (-not $ordered.Contains($Id)) { $ordered.Add($Id) }
    }

    foreach ($id in $Ids) { Resolve-One -Id $id.ToLowerInvariant() }
    return $ordered.ToArray()
}
