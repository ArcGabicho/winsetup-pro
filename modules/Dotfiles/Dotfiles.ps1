# modules/Dotfiles/Dotfiles.ps1 - restore personal config files.
#
# Source: a local folder or a git repository (cloned into state/dotfiles/).
# Mapping: an explicit dotfiles.map, or every file in the source (minus .git,
#          README*, LICENSE*, install*/setup*) mapped to the same relative path
#          under $HOME.
#
# Safety:
#   * A file is only replaced when its content differs from the source.
#   * Before replacing, the existing file is backed up - always in
#     non-interactive mode; via a Yes/No/Skip prompt when interactive
#     (dotfiles.backupExisting = prompt | always | never).
#   * Nothing is ever deleted.
#
# Config (dotfiles.*):
#   path | repository | source   where the dotfiles come from
#   map                          { "rel/in/source": "%USERPROFILE%\\target" }
#   backupExisting               prompt (default) | always | never
#   link                         copy (default) | symlink

New-WinSetupComponent -Id 'dotfiles' -Name 'Dotfiles' -Category 'Customization' `
    -Description 'Restores personal config files from a folder or git repo' `
    -Tags @('dotfiles') `
    -Test {
        param($Context)
        $source = [string](Get-WinSetupConfigValue -Config $Context.Config -Path 'dotfiles.path' -Default '')
        if (-not $source) { $source = [string](Get-WinSetupConfigValue -Config $Context.Config -Path 'dotfiles.source' -Default '') }
        $repo = [string](Get-WinSetupConfigValue -Config $Context.Config -Path 'dotfiles.repository' -Default '')

        if (-not $source -and -not $repo) {
            return New-WinSetupDetectionResult -Installed $true -Summary 'no dotfiles source configured'
        }

        # A configured git repo that has not been cloned yet is "work pending".
        $isGit = $repo -or ($source -match '^(https?://|git@).+' -or $source -match '\.git/?$')
        if ($isGit) {
            $cacheRoot = Join-Path $Context.Paths.State 'dotfiles'
            $url = if ($repo) { $repo } else { $source }
            $key = ([System.BitConverter]::ToString(
                        [System.Security.Cryptography.MD5]::Create().ComputeHash(
                            [System.Text.Encoding]::UTF8.GetBytes($url))) -replace '-', '').Substring(0, 12)
            $local = Join-Path $cacheRoot $key
            if (-not (Test-Path -LiteralPath (Join-Path $local '.git'))) {
                return New-WinSetupDetectionResult -Installed $true -Configured $false -Summary "repo not cloned yet ($url)"
            }
            $source = $local
        }

        if (-not (Test-Path -LiteralPath $source)) {
            return New-WinSetupDetectionResult -Installed $true -Configured $false -Summary "source not found: $source"
        }

        $map = Get-WinSetupConfigValue -Config $Context.Config -Path 'dotfiles.map' -Default $null
        $pairs = @()
        if ($map -is [System.Collections.IDictionary] -and $map.Count -gt 0) {
            foreach ($k in $map.Keys) {
                $pairs += , @((Join-Path $source $k), [Environment]::ExpandEnvironmentVariables([string]$map[$k]))
            }
        }
        else {
            foreach ($f in Get-ChildItem -LiteralPath $source -Recurse -File -Force -ErrorAction SilentlyContinue) {
                if ($f.FullName -match '[\\/]\.git[\\/]' -or $f.Name -match '^(README|LICENSE|install|setup|bootstrap)') { continue }
                $rel = $f.FullName.Substring($source.Length).TrimStart('\', '/')
                $pairs += , @($f.FullName, (Join-Path $HOME $rel))
            }
        }

        $pending = 0
        foreach ($pair in $pairs) {
            $src, $dst = $pair
            if (-not (Test-Path -LiteralPath $dst)) { $pending++; continue }
            if ((Get-FileHash -LiteralPath $src).Hash -ne (Get-FileHash -LiteralPath $dst).Hash) { $pending++ }
        }

        if ($pending -eq 0) {
            return New-WinSetupDetectionResult -Installed $true -Summary ("{0} files in sync" -f $pairs.Count)
        }
        New-WinSetupDetectionResult -Installed $true -Configured $false -Summary ("{0} of {1} files pending" -f $pending, $pairs.Count)
    } `
    -Configure {
        param($Context)
        $source = [string](Get-WinSetupConfigValue -Config $Context.Config -Path 'dotfiles.path' -Default '')
        if (-not $source) { $source = [string](Get-WinSetupConfigValue -Config $Context.Config -Path 'dotfiles.source' -Default '') }
        $repo = [string](Get-WinSetupConfigValue -Config $Context.Config -Path 'dotfiles.repository' -Default '')
        if (-not $source -and -not $repo) { return }

        $isGit = $repo -or ($source -match '^(https?://|git@).+' -or $source -match '\.git/?$')
        if ($isGit) {
            if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'git is required to use a dotfiles repository.' }
            $url = if ($repo) { $repo } else { $source }
            $cacheRoot = Join-Path $Context.Paths.State 'dotfiles'
            if (-not (Test-Path -LiteralPath $cacheRoot)) { New-Item -ItemType Directory -Path $cacheRoot -Force | Out-Null }
            $key = ([System.BitConverter]::ToString(
                        [System.Security.Cryptography.MD5]::Create().ComputeHash(
                            [System.Text.Encoding]::UTF8.GetBytes($url))) -replace '-', '').Substring(0, 12)
            $local = Join-Path $cacheRoot $key
            if (Test-Path -LiteralPath (Join-Path $local '.git')) {
                Write-WinSetupLog -Level INFO -Module 'dotfiles' -Message "git -C $local pull --ff-only"
                & git -C $local pull --ff-only | Out-Null
            }
            else {
                Write-WinSetupLog -Level INFO -Module 'dotfiles' -Message "git clone $url"
                & git clone --depth 1 $url $local | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "git clone of '$url' failed." }
            }
            $source = $local
        }

        if (-not (Test-Path -LiteralPath $source)) { throw "Dotfiles source not found: $source" }

        $backupMode = [string](Get-WinSetupConfigValue -Config $Context.Config -Path 'dotfiles.backupExisting' -Default 'prompt')
        $link = [string](Get-WinSetupConfigValue -Config $Context.Config -Path 'dotfiles.link' -Default 'copy')

        $map = Get-WinSetupConfigValue -Config $Context.Config -Path 'dotfiles.map' -Default $null
        $pairs = @()
        if ($map -is [System.Collections.IDictionary] -and $map.Count -gt 0) {
            foreach ($k in $map.Keys) {
                $pairs += , @((Join-Path $source $k), [Environment]::ExpandEnvironmentVariables([string]$map[$k]))
            }
        }
        else {
            foreach ($f in Get-ChildItem -LiteralPath $source -Recurse -File -Force -ErrorAction SilentlyContinue) {
                if ($f.FullName -match '[\\/]\.git[\\/]' -or $f.Name -match '^(README|LICENSE|install|setup|bootstrap)') { continue }
                $rel = $f.FullName.Substring($source.Length).TrimStart('\', '/')
                $pairs += , @($f.FullName, (Join-Path $HOME $rel))
            }
        }

        foreach ($pair in $pairs) {
            $src, $dst = $pair
            if (-not (Test-Path -LiteralPath $src)) { continue }

            if ((Test-Path -LiteralPath $dst) -and
                (Get-FileHash -LiteralPath $src).Hash -eq (Get-FileHash -LiteralPath $dst).Hash) {
                continue
            }

            if (Test-Path -LiteralPath $dst) {
                $doBackup = switch ($backupMode) {
                    'never'  { $false }
                    'always' { $true }
                    default {
                        if ($Context.Interactive) {
                            Confirm-WinSetupAction -Question "Back up existing '$dst' before replacing it?" -DefaultYes $true
                        }
                        else { $true }
                    }
                }
                if ($doBackup) {
                    $rel = if ($dst.StartsWith($HOME, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $dst.Substring($HOME.Length).TrimStart('\', '/')
                    } else {
                        Split-Path -Leaf $dst
                    }
                    $bdir = Join-Path (Join-Path $Context.Paths.Backup 'dotfiles') (Get-Date -Format 'yyyy-MM-dd_HHmmss')
                    $bdst = Join-Path $bdir $rel
                    New-Item -ItemType Directory -Path (Split-Path -Parent $bdst) -Force | Out-Null
                    Copy-Item -LiteralPath $dst -Destination $bdst -Force
                    Write-WinSetupLog -Level INFO -Module 'dotfiles' -Message "backed up $dst -> $bdst"
                }
            }

            $parent = Split-Path -Parent $dst
            if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

            if ($link -eq 'symlink') {
                try {
                    if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Force }
                    New-Item -ItemType SymbolicLink -Path $dst -Target $src -Force | Out-Null
                    Write-WinSetupLog -Level INFO -Module 'dotfiles' -Message "linked $dst -> $src"
                    continue
                }
                catch {
                    Write-WinSetupLog -Level WARNING -Module 'dotfiles' -Message "symlink failed ($($_.Exception.Message)); copying instead."
                }
            }

            Copy-Item -LiteralPath $src -Destination $dst -Force
            Write-WinSetupLog -Level INFO -Module 'dotfiles' -Message "installed $dst"
        }
    }
