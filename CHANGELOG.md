# Changelog

All notable changes to WinSetup Pro are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
the project aims for [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Phase 4 — WSL 2 (added)

* **WSL helpers** (`modules/Core/Wsl.ps1`): `Invoke-WinSetupWsl` (forces
  `WSL_UTF8` + UTF-8 console, strips NUL bytes), `Get-WinSetupWslInfo`
  (locale-independent state from the `Lxss` registry key + optional-feature
  query + distro list), `Format-WinSetupWslConfig`.
* **`wsl` component** (`modules/WSL/Wsl.ps1`, `RequiresAdmin`): enables the WSL
  and Virtual Machine Platform features (`wsl --install --no-distribution`, DISM
  fallback) and tells the user to restart; runs `wsl --set-default-version 2`;
  writes `~/.wslconfig` **create-only** (left untouched unless
  `wsl.overwriteWslConfig`, backed up first); installs `wsl.distribution` from
  `wsl --list --online` with `--no-launch` (interactive menu when unset).
  Existing distributions are never unregistered or reset.
* **CLI**: `-WSL`, `-Git`, `-SSH` switches (run just that component).
* Dry-run now previews admin-only components (flagged "needs elevation")
  instead of skipping them; real runs still skip when not elevated.
* `config` / `schema`: `wsl.wslConfig`, `wsl.overwriteWslConfig`.
* Tests: `tests/unit/Wsl.Tests.ps1`; verification suite 43/43.

### Phase 3 — Developer environment (added)

* **Cloud / infra CLI components** (`Cloud` category): `azure-cli`
  (`Microsoft.AzureCLI`), `aws-cli`, `gcloud-cli`, `terraform`, `kubectl`,
  `helm` — all winget-backed.
* **`ssh`** (`modules/SSH/OpenSsh.ps1`): detects the OpenSSH client, installs it
  via the Windows capability when missing (elevation asserted), discovers
  existing keys and **never overwrites them**. Key creation is opt-in —
  interactive prompt (ssh-keygen then asks for a passphrase) or
  `ssh.generateKeyUnattended`. `ssh.providers` appends missing `~/.ssh/config`
  Host blocks only, after backing the file up; key/dir permissions are locked
  down with `icacls`.
* **`env-vars`** (`modules/Environment/EnvironmentVariables.ps1`): applies
  `environment.user` / `environment.machine` (machine scope asserts admin) and
  appends `environment.path` entries to the **User** PATH, de-duplicated
  (case-insensitive, trailing-separator-normalised). Snapshots the previous
  values to `backup/environment/` first.
* **`folders`** (`modules/Folders/Folders.ps1`): creates the `folders` tree
  under the user profile. Only ever creates - never deletes.
* **`fonts`** (`modules/Fonts/Fonts.ps1`): per-user install (no admin) of
  Cascadia Code / Mono, JetBrains Mono, Fira Code from their official GitHub
  releases; skips already-registered families.
* `Resolve-WinSetupPlan` now also pulls in `folders` / `fonts` / `env-vars`
  when the effective configuration gives them work to do.
* `config` / `schema`: `ssh.providers`, `ssh.generateKeyUnattended`.
* Tests: `tests/unit/Environment.Tests.ps1`; verification suite 36/36.

### Phase 2 — Applications (added)

* **Shared winget helpers** (`modules/Core/Winget.ps1`):
  `Install-WinSetupWingetPackage` (silent, idempotent, verifies presence on a
  non-zero exit code and gives an elevation hint otherwise),
  `Update-WinSetupSessionPath`, `Get-WinSetupExeVersion`.
* **Application components** (`modules/Applications/`): `pwsh` (PowerShell 7),
  `windows-terminal`, `vscode` (user scope), `github-cli` (optional
  `git_protocol` config, never runs `gh auth login`), `dotnet-sdk`
  (channel-configurable), `nodejs`, `npm` (provided-by-nodejs, `DependsOn`),
  `pnpm`, `python` (ignores the WindowsApps alias stub), `docker-desktop`
  (`RequiresAdmin`, restart notice).
* `config/default.json` / `schema.json` gain `githubCli`, `dotnet`, `node`,
  `python` blocks.
* `minimal` and `frontend` profiles are now fully backed by real components.
* Tests: `tests/unit/Applications.Tests.ps1` — discovery, schema validity,
  unique ids, dependency wiring, and that every `Test` block is side-effect free.

### Phase 1 — Core (added)

* **Setup Engine** (`modules/Core/`): execution context, plan resolution,
  detect → install → configure loop, idempotency, admin gating, dry-run.
* **Component model**: `New-WinSetupComponent` / `New-WinSetupDetectionResult`
  descriptors with `Test` / `Install` / `Configure` script blocks and
  `DependsOn` ordering (topological sort with cycle detection).
* **Convention-based registry**: any `modules/**/*.ps1` (excluding `Core/`,
  `_*` and `*.Tests.ps1`) is discovered as a component with no core changes.
* **CLI** (`WinSetup.ps1`): `-Profile`, `-Install`, `-List`, `-Status`,
  `-Diagnose`, `-Resume`, `-Update` (stub), plus `-DryRun`, `-NonInteractive`,
  `-ConfigFile`, `-LogLevel`; interactive menu when run with no arguments.
* **Declarative configuration**: `config/default.json` + `config/schema.json`,
  layered `default ← profile ← user config ← CLI` with deep merge and
  list-union for `applications` / `fonts` / `folders`.
* **Structured logging**: timestamped per-run files in `logs/`, levels
  `DEBUG|INFO|SUCCESS|WARNING|ERROR`, no secrets.
* **Run journal & resume**: `state/last-run.json` / `state/last-dryrun.json`;
  `-Resume` continues after an interruption.
* **Error handling**: per-component try/catch, `settings.errorPolicy`
  (`critical`/`nonCritical` → `retry|skip|abort`), interactive Retry/Skip/Abort.
* **System detection & diagnostics**: OS/build, architecture, PowerShell,
  winget, WSL presence, connectivity, free disk, execution policy.
* **Privilege detection**: `Test-WinSetupAdmin` / `Assert-WinSetupAdmin` — never
  elevates silently.
* **Reference component**: `modules/Applications/Git.ps1` — winget install plus
  safe idempotent global config; never overwrites an existing Git identity.
* **Profiles** (declarative): `minimal`, `frontend`, `dotnet`, `fullstack`,
  `enterprise`. Component ids not yet implemented are reported and skipped.
* **Secure bootstrap** (`scripts/bootstrap.ps1`) plus `install`, `update`,
  `uninstall`, `diagnose` helper scripts.
* **Tests**: Pester 5 unit specs for logging, configuration and the engine
  (idempotency, dry-run, error policy, dependency order, discovery); `TestDrive:`
  only, no host mutation.

### Known limitations

* `dotnet`, `fullstack` and `enterprise` profiles still reference components that
  arrive in Phase 3+ (`visualstudio`, `azure-cli`, `postgresql`, …); those are
  reported and skipped, not failed.
* `-Update` is a placeholder (`git pull`).
* An empty JSON array read through `Get-WinSetupConfigValue` collapses to
  `$null`; callers wrap with `@()` and `-Default @()`.

[Unreleased]: https://github.com/<you>/WinSetup-Pro/commits/main
