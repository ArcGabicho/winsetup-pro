# modules/SSH/OpenSsh.ps1 - OpenSSH client, key handling and ~/.ssh/config.
#
# Safety rules honoured here:
#   * Existing private keys are NEVER overwritten or regenerated.
#   * A new key is only created when none exists AND the run is interactive and
#     the user answers "Yes" (ssh-keygen then prompts for a passphrase).
#     Unattended runs only generate a key when ssh.generateKeyUnattended = true;
#     otherwise they log a note and skip.
#   * ~/.ssh/config is appended to (missing Host blocks only), never rewritten,
#     and is backed up first.
#   * No passwords or passphrases are stored or logged.
#
# Config:
#   ssh.enabled                  : include this component in a profile run
#   ssh.keyType                  : ed25519 (default) | rsa | ecdsa
#   ssh.providers                : ["github.com", "gitlab.com", ...] Host blocks
#   ssh.generateKeyUnattended    : allow key creation in non-interactive mode

New-WinSetupComponent -Id 'ssh' -Name 'SSH (OpenSSH client)' -Category 'Environment' `
    -Description 'OpenSSH client, key discovery/creation and ~/.ssh/config' `
    -Tags @('ssh', 'git') `
    -Test {
        param($Context)
        $ssh = Get-Command ssh.exe -ErrorAction SilentlyContinue
        if (-not $ssh) {
            return New-WinSetupDetectionResult -Installed $false -Summary 'OpenSSH client not installed'
        }

        $version = $null
        try {
            $raw = (& $ssh.Source -V 2>&1 | Out-String)
            if ($raw -match 'OpenSSH[_a-zA-Z]*[ _](\d+\.\d+)') { $version = $Matches[1] }
        } catch { }

        $sshDir = Join-Path $HOME '.ssh'
        $keys = @()
        if (Test-Path -LiteralPath $sshDir) {
            $keys = @(Get-ChildItem -LiteralPath $sshDir -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^id_(ed25519|rsa|ecdsa)$' } | Select-Object -ExpandProperty Name)
        }

        $providers = @(Get-WinSetupConfigValue -Config $Context.Config -Path 'ssh.providers' -Default @() | Where-Object { $_ })
        $missingHosts = @()
        if ($providers.Count -gt 0) {
            $configPath = Join-Path $sshDir 'config'
            $cfgText = if (Test-Path -LiteralPath $configPath) { Get-Content -LiteralPath $configPath -Raw } else { '' }
            foreach ($h in $providers) {
                if ($cfgText -notmatch ("(?im)^\s*Host\s+" + [regex]::Escape($h) + "\s*$")) { $missingHosts += $h }
            }
        }

        $configured = ($missingHosts.Count -eq 0)
        $summary = if ($keys.Count -gt 0) { "keys: $($keys -join ', ')" } else { 'no keys found' }
        if ($missingHosts.Count -gt 0) { $summary += "; config blocks missing: $($missingHosts -join ', ')" }

        New-WinSetupDetectionResult -Installed $true -Configured $configured -Version $version -Summary $summary
    } `
    -Install {
        param($Context)
        if (Get-Command ssh.exe -ErrorAction SilentlyContinue) { return }
        Assert-WinSetupAdmin -Reason 'installing the OpenSSH client Windows capability.'
        Write-WinSetupLog -Level INFO -Module 'ssh' -Message 'Add-WindowsCapability -Online OpenSSH.Client'
        Add-WindowsCapability -Online -Name 'OpenSSH.Client~~~~0.0.1.0' | Out-Null
        if (-not (Get-Command ssh.exe -ErrorAction SilentlyContinue)) {
            throw 'OpenSSH client capability did not register.'
        }
    } `
    -Configure {
        param($Context)
        $sshDir = Join-Path $HOME '.ssh'
        if (-not (Test-Path -LiteralPath $sshDir)) { New-Item -ItemType Directory -Path $sshDir -Force | Out-Null }
        try { & icacls $sshDir /inheritance:r /grant:r ("{0}:(OI)(CI)F" -f $env:USERNAME) | Out-Null } catch { }

        $keyType = [string](Get-WinSetupConfigValue -Config $Context.Config -Path 'ssh.keyType' -Default 'ed25519')
        if ($keyType -notin @('ed25519', 'rsa', 'ecdsa')) { $keyType = 'ed25519' }
        $keyPath = Join-Path $sshDir ("id_" + $keyType)

        $existing = @(Get-ChildItem -LiteralPath $sshDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^id_(ed25519|rsa|ecdsa)$' })

        if ($existing.Count -gt 0) {
            Write-WinSetupLog -Level INFO -Module 'ssh' -Message ("Existing key(s) detected ({0}) - left untouched." -f (($existing.Name) -join ', '))
        }
        elseif (Test-Path -LiteralPath $keyPath) {
            Write-WinSetupLog -Level INFO -Module 'ssh' -Message "Key $keyPath already exists - left untouched."
        }
        else {
            $comment = "{0}@{1}" -f $env:USERNAME, $env:COMPUTERNAME
            $generate = $false
            if ($Context.Interactive) {
                $generate = Confirm-WinSetupAction -Question "No SSH key found. Generate a new $keyType key at $keyPath now?" -DefaultYes $false
            }
            elseif ((Get-WinSetupConfigValue -Config $Context.Config -Path 'ssh.generateKeyUnattended' -Default $false) -eq $true) {
                $generate = $true
            }
            else {
                Write-WinSetupLog -Level INFO -Module 'ssh' -Message 'No SSH key found. Run interactively (or set ssh.generateKeyUnattended) to create one.'
            }

            if ($generate) {
                if ($Context.Interactive) {
                    Write-WinSetupLog -Level INFO -Module 'ssh' -Message "ssh-keygen -t $keyType (you will be prompted for a passphrase)"
                    & ssh-keygen -t $keyType -f $keyPath -C $comment
                }
                else {
                    Write-WinSetupLog -Level WARNING -Module 'ssh' -Message 'Creating an SSH key WITHOUT a passphrase (unattended request).'
                    & ssh-keygen -t $keyType -f $keyPath -C $comment -N '' -q
                }
                if ($LASTEXITCODE -ne 0) { throw "ssh-keygen failed (exit $LASTEXITCODE)." }
                try { & icacls $keyPath /inheritance:r /grant:r ("{0}:F" -f $env:USERNAME) | Out-Null } catch { }
                Write-WinSetupLog -Level SUCCESS -Module 'ssh' -Message "Created $keyPath (public key: $keyPath.pub)"
            }
        }

        $providers = @(Get-WinSetupConfigValue -Config $Context.Config -Path 'ssh.providers' -Default @() | Where-Object { $_ })
        if ($providers.Count -eq 0) { return }

        $configPath = Join-Path $sshDir 'config'
        $cfgText = if (Test-Path -LiteralPath $configPath) { Get-Content -LiteralPath $configPath -Raw } else { '' }
        $identity = if (Test-Path -LiteralPath $keyPath) { $keyPath } else { Join-Path $sshDir ("id_" + $keyType) }

        $append = New-Object System.Collections.Generic.List[string]
        foreach ($h in $providers) {
            if ($cfgText -match ("(?im)^\s*Host\s+" + [regex]::Escape($h) + "\s*$")) { continue }
            $append.Add('')
            $append.Add("Host $h")
            $append.Add("    HostName $h")
            $append.Add('    User git')
            $append.Add("    IdentityFile $identity")
            $append.Add('    IdentitiesOnly yes')
        }
        if ($append.Count -eq 0) {
            Write-WinSetupLog -Level INFO -Module 'ssh' -Message 'All requested ~/.ssh/config Host blocks already present.'
            return
        }

        if ((Get-WinSetupConfigValue -Config $Context.Config -Path 'settings.createBackups' -Default $true) -and (Test-Path -LiteralPath $configPath)) {
            $bdir = Join-Path $Context.Paths.Backup 'ssh'
            if (-not (Test-Path -LiteralPath $bdir)) { New-Item -ItemType Directory -Path $bdir -Force | Out-Null }
            Copy-Item -LiteralPath $configPath -Destination (Join-Path $bdir ("config.{0}" -f (Get-Date -Format 'yyyy-MM-dd_HHmmss'))) -Force
            Write-WinSetupLog -Level INFO -Module 'ssh' -Message "Backed up ~/.ssh/config"
        }

        Add-Content -LiteralPath $configPath -Value ($append -join "`r`n") -Encoding utf8
        try { & icacls $configPath /inheritance:r /grant:r ("{0}:F" -f $env:USERNAME) | Out-Null } catch { }
        Write-WinSetupLog -Level INFO -Module 'ssh' -Message ("Added ~/.ssh/config Host blocks: " + ($providers -join ', '))
    }
