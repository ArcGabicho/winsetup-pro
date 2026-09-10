# Backup.ps1 - one consolidated place to snapshot a file before a component
# changes it. Every backup lands under backup/<Category>/<timestamp>/.

function Backup-WinSetupFile {
    <#
    .SYNOPSIS
        Copies $Path into backup/<Category>/<timestamp>/ and returns the copy's
        full path (or $null when there is nothing to back up / backups are off).
    .PARAMETER Force
        Take the backup even when settings.createBackups is false.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Category,
        [switch]$Force
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $null }

    $enabled = Get-WinSetupConfigValue -Config $Context.Config -Path 'settings.createBackups' -Default $true
    if (-not $enabled -and -not $Force) { return $null }

    $stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $dir = Join-Path (Join-Path $Context.Paths.Backup $Category) $stamp
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $dest = Join-Path $dir (Split-Path -Leaf $Path)
    Copy-Item -LiteralPath $Path -Destination $dest -Recurse -Force
    Write-WinSetupLog -Level INFO -Module $Category -Message ("Backed up {0} -> {1}" -f $Path, $dest)
    return $dest
}
