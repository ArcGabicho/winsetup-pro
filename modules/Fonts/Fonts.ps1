# modules/Fonts/Fonts.ps1 - developer fonts, installed per-user (no admin).
#
# The "fonts" array in the configuration names font keys; the catalogue below
# maps each to its OFFICIAL GitHub release. Faces are downloaded from those
# releases (well-known first-party repositories), copied to
# %LOCALAPPDATA%\Microsoft\Windows\Fonts and registered under HKCU - the
# standard per-user font install that needs no elevation. Already-registered
# fonts are skipped, so re-runs are no-ops.

New-WinSetupComponent -Id 'fonts' -Name 'Developer fonts' -Category 'Environment' `
    -Description 'Installs Cascadia Code / Mono, JetBrains Mono, Fira Code (per-user)' `
    -Tags @('fonts') `
    -Test {
        param($Context)
        $catalogue = @{
            'CascadiaCode'  = 'Cascadia Code'
            'CascadiaMono'  = 'Cascadia Mono'
            'JetBrainsMono' = 'JetBrains Mono'
            'FiraCode'      = 'Fira Code'
        }
        $requested = @(Get-WinSetupConfigValue -Config $Context.Config -Path 'fonts' -Default @() | Where-Object { $_ })
        if ($requested.Count -eq 0) {
            return New-WinSetupDetectionResult -Installed $true -Summary 'no fonts configured'
        }

        $registered = New-Object System.Collections.Generic.List[string]
        foreach ($hive in @(
                'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts',
                'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts')) {
            try {
                (Get-ItemProperty -Path $hive -ErrorAction Stop).PSObject.Properties |
                    Where-Object { $_.Name -notlike 'PS*' } |
                    ForEach-Object { $registered.Add(($_.Name -replace '\s', '').ToLowerInvariant()) }
            } catch { }
        }

        $missing = @()
        foreach ($key in $requested) {
            $family = $catalogue[$key]
            if (-not $family) { continue }
            $needle = ($family -replace '\s', '').ToLowerInvariant()
            if (-not ($registered | Where-Object { $_ -like "$needle*" })) { $missing += $key }
        }

        if ($missing.Count -eq 0) {
            return New-WinSetupDetectionResult -Installed $true -Summary ("{0} font families present" -f $requested.Count)
        }
        New-WinSetupDetectionResult -Installed $false -Summary ("missing: " + ($missing -join ', '))
    } `
    -Install {
        param($Context)
        $catalogue = @{
            'CascadiaCode'  = @{ Display = 'Cascadia Code';  Repo = 'microsoft/cascadia-code';  Match = '^CascadiaCode.*\.ttf$' }
            'CascadiaMono'  = @{ Display = 'Cascadia Mono';  Repo = 'microsoft/cascadia-code';  Match = '^CascadiaMono.*\.ttf$' }
            'JetBrainsMono' = @{ Display = 'JetBrains Mono'; Repo = 'JetBrains/JetBrainsMono';  Match = '\.ttf$' }
            'FiraCode'      = @{ Display = 'Fira Code';      Repo = 'tonsky/FiraCode';          Match = '\.ttf$' }
        }
        $requested = @(Get-WinSetupConfigValue -Config $Context.Config -Path 'fonts' -Default @() | Where-Object { $_ })

        $fontsDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
        $regPath  = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
        New-Item -ItemType Directory -Path $fontsDir -Force | Out-Null
        if (-not (Test-Path -LiteralPath $regPath)) { New-Item -Path $regPath -Force | Out-Null }

        $headers = @{ 'User-Agent' = 'WinSetup-Pro' }

        foreach ($key in $requested) {
            $entry = $catalogue[$key]
            if (-not $entry) {
                Write-WinSetupLog -Level WARNING -Module 'fonts' -Message "Unknown font key '$key' - skipped."
                continue
            }

            $work = Join-Path ([System.IO.Path]::GetTempPath()) ("winsetup-font-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $work -Force | Out-Null
            try {
                Write-WinSetupLog -Level INFO -Module 'fonts' -Message ("Resolving latest release of {0}" -f $entry.Repo)
                $release = Invoke-RestMethod -Headers $headers -Uri ("https://api.github.com/repos/{0}/releases/latest" -f $entry.Repo)
                $asset = $release.assets | Where-Object { $_.name -match '\.zip$' } | Sort-Object size -Descending | Select-Object -First 1
                if (-not $asset) { throw "no .zip asset in the latest release of $($entry.Repo)" }

                $zip = Join-Path $work $asset.name
                Invoke-WebRequest -Headers $headers -Uri $asset.browser_download_url -OutFile $zip
                Expand-Archive -LiteralPath $zip -DestinationPath $work -Force

                $faces = Get-ChildItem -LiteralPath $work -Recurse -Filter '*.ttf' -File |
                    Where-Object { $_.Name -match $entry.Match -and $_.FullName -notmatch '[\\/](static|variable)[\\/].*[\\/]' }
                if (-not $faces) { $faces = Get-ChildItem -LiteralPath $work -Recurse -Filter '*.ttf' -File | Where-Object { $_.Name -match $entry.Match } }

                $installed = 0
                foreach ($face in $faces) {
                    $dest = Join-Path $fontsDir $face.Name
                    Copy-Item -LiteralPath $face.FullName -Destination $dest -Force
                    $regName = (($face.BaseName -replace '[-_]', ' ') + ' (TrueType)')
                    New-ItemProperty -Path $regPath -Name $regName -Value $dest -PropertyType String -Force | Out-Null
                    $installed++
                }
                Write-WinSetupLog -Level SUCCESS -Module 'fonts' -Message ("{0}: installed {1} face(s)" -f $entry.Display, $installed)
            }
            finally {
                Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        Write-WinSetupLog -Level INFO -Module 'fonts' -Message 'Restart running apps to pick up the new fonts.'
    }
