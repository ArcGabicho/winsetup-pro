# WinSetup Pro — Troubleshooting

The newest file in `logs/` has the full detail for a run. Re-run with
`-LogLevel DEBUG` for more. The run journal is `state/last-run.json`.

## Running the script

| Symptom | Cause / fix |
|---|---|
| `running scripts is disabled on this system` | Execution policy. `powershell -ExecutionPolicy Bypass -File .\WinSetup.ps1 ...`, or once: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`. |
| `The term 'WinSetup.ps1' is not recognized` | Run it as `.\WinSetup.ps1` from the repo root, or give the full path. |
| Nothing happens / only a menu, in a script/CI | You passed no operation. Use `-Profile`, `-Install`, `-Status`, … . `-NonInteractive` with no operation just prints status. |
| Unicode boxes / checkmarks look wrong | Old console. WinSetup sets UTF-8 output; use Windows Terminal, or ignore — it is cosmetic. |

## winget

| Symptom | Cause / fix |
|---|---|
| `winget (App Installer) is not available` | Install **App Installer** from the Microsoft Store, then re-run. `-Diagnose` confirms it. |
| `winget could not install '<id>' (exit code N)… retry from an elevated session` | The package is machine-wide. Re-run from an **elevated** PowerShell (`Run as administrator`). |
| A package installs but the CLI is "not found" right after | PATH in the current session is stale. Open a new terminal, or the component already called `Update-WinSetupSessionPath` and the next run will detect it. |
| `msstore` source prompts for sign-in | Not used by default; all components use the `winget` source. |

## Elevation

| Symptom | Fix |
|---|---|
| `[WARN] requires an elevated session - skipped` | Expected for `wsl`, `visualstudio`, `postgresql`, `mysql`, `redis-cli` (and `env-vars` with machine variables) when not elevated. Re-run elevated, or use `-DryRun` to preview what they would do. |
| `Administrator privileges are required because …` | A component asserted elevation mid-run. Re-run elevated. |

## PATH & environment variables

| Symptom | Fix |
|---|---|
| A tool works in a new terminal but not the one that ran WinSetup | Environment changes reach new processes. Restart the shell (WinSetup already suggests a restart when it installed something). |
| A PATH entry I configured "does not exist yet" warning | `env-vars` still adds it; create the folder or ignore. Entries are stored **expanded** (absolute), de-duplicated case-insensitively. |
| I need to undo an environment change | See `backup/environment/env-<timestamp>.json` for the previous values. |

## WSL

| Symptom | Fix |
|---|---|
| `A RESTART is required before WSL 2 works` | Reboot Windows, then run `.\WinSetup.ps1 -WSL` again to set the default version and install a distribution. |
| `wsl.exe not available yet - restart Windows and re-run` | The features were just enabled; reboot. |
| `Distribution 'X' is not available` | Use a name from `wsl --list --online` (the error lists the valid ones). |
| An existing distro was not touched | By design — WinSetup never resets or unregisters a distribution. |
| `~/.wslconfig already exists - left untouched` | Set `wsl.overwriteWslConfig: true` (the old file is backed up to `backup/wsl/`). |

## SSH

| Symptom | Fix |
|---|---|
| No key was generated | Key creation is opt-in: answer **Yes** to the interactive prompt, or set `ssh.generateKeyUnattended: true` (which creates a key **without a passphrase** and says so). |
| My existing key was not replaced | By design. WinSetup never overwrites `id_ed25519` / `id_rsa` / `id_ecdsa`. |
| `~/.ssh/config` permissions warnings from ssh | WinSetup runs `icacls` to lock the file to your user; re-run `.\WinSetup.ps1 -SSH`. |

## Git

| Symptom | Fix |
|---|---|
| `user.name is already set to '…' - left unchanged` | Expected. Set `git.userName` / `git.userEmail` in your config only if you want WinSetup to fill a **missing** identity; it never overwrites one. |
| Where is the old config? | `backup/git/<timestamp>/.gitconfig`. |

## PowerShell profile

| Symptom | Fix |
|---|---|
| My `$PROFILE` customisations disappeared | They did not — WinSetup only edits its own `# >>> WinSetup Pro managed block >>>` … `<<<` section and backs up the file first (`backup/powershell/`). |
| Fragments not loading | Open a new PowerShell session (the block is added to `$PROFILE`, which loads at startup). Check `<profile dir>\winsetup-pro\`. |
| `Install-Module '<x>' failed` | `powershellProfile.modules` needs PSGallery + internet. `Set-PSRepository PSGallery -InstallationPolicy Trusted` and retry. |

## Dotfiles

| Symptom | Fix |
|---|---|
| A file was not copied | It already matched the source (hash compare), or you answered **Skip** at the backup prompt. |
| I want no prompts | `dotfiles.backupExisting: always` (or `never`), or run `-NonInteractive`. |
| `git is required to use a dotfiles repository` | Install Git first (`-Install git`) or use a local `-Dotfiles <path>`. |
| Where are my replaced files? | `backup/dotfiles/<timestamp>/`. |

## Resuming / journal

| Symptom | Fix |
|---|---|
| A run stopped part-way | `.\WinSetup.ps1 -Resume` — it re-runs only the `Pending` / `Failed` entries. |
| `The previous run already completed - nothing to resume` | Expected; start a fresh run. |
| I want to see what a run did | `state/last-run.json` (per-component status, action, duration). |

## Fonts

| Symptom | Fix |
|---|---|
| Fonts not visible in an app | Restart the app (or sign out/in). WinSetup registers them per-user under `HKCU`. |
| A GitHub rate-limit error | The API allows ~60 unauthenticated requests/hour/IP; wait, or install the fonts manually from the same official releases. |

## Tests

| Symptom | Fix |
|---|---|
| `Pester 5+ is required` | `Install-Module Pester -Scope CurrentUser -MinimumVersion 5.5.0 -Force -SkipPublisherCheck`. |
| Integration tests all skipped | Expected. `WINSETUP_ALLOW_INTEGRATION=1` and `-Suite integration` to run them. |
