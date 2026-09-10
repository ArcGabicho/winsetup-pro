# modules/Folders/Folders.ps1 - creates the standard developer folder tree.
#
# Reads the "folders" array from the configuration (paths relative to the user
# profile, e.g. "Dev\Projects"). Only ever CREATES directories - never deletes
# or moves anything.

New-WinSetupComponent -Id 'folders' -Name 'Folder structure' -Category 'Environment' `
    -Description 'Creates the configured folder tree under the user profile' `
    -Tags @('filesystem') `
    -Test {
        param($Context)
        $items = @(Get-WinSetupConfigValue -Config $Context.Config -Path 'folders' -Default @() | Where-Object { $_ })
        if ($items.Count -eq 0) {
            return New-WinSetupDetectionResult -Installed $true -Summary 'no folders configured'
        }
        $base = if ($env:USERPROFILE) { $env:USERPROFILE } else { [Environment]::GetFolderPath('UserProfile') }
        $missing = @($items | Where-Object { -not (Test-Path -LiteralPath (Join-Path $base $_)) })
        if ($missing.Count -eq 0) {
            return New-WinSetupDetectionResult -Installed $true -Summary ("{0} folders present" -f $items.Count)
        }
        New-WinSetupDetectionResult -Installed $false -Summary ("{0} of {1} missing" -f $missing.Count, $items.Count)
    } `
    -Install {
        param($Context)
        $items = @(Get-WinSetupConfigValue -Config $Context.Config -Path 'folders' -Default @() | Where-Object { $_ })
        $base = if ($env:USERPROFILE) { $env:USERPROFILE } else { [Environment]::GetFolderPath('UserProfile') }
        foreach ($rel in $items) {
            $full = Join-Path $base $rel
            if (Test-Path -LiteralPath $full) { continue }
            New-Item -ItemType Directory -Path $full -Force | Out-Null
            Write-WinSetupLog -Level INFO -Module 'folders' -Message "created $full"
        }
    }
