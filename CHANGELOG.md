# Changelog

All notable changes to WinSetup Pro are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
the project aims for [Semantic Versioning](https://semver.org/).

## [Unreleased]

### GUI groundwork (0.2.0, in progress)

The engine stays the single source of truth; the GUI is a client.

* **Engine event hook** — `Invoke-WinSetupPlan -EventSink <scriptblock>` (new,
  optional). Emits `plan_resolved` / `component_started` / `component_completed`
  / `component_failed` / `run_completed`. With no sink the behaviour is
  byte-for-byte identical. `tests/unit/EngineEvents.Tests.ps1`.
* **JSON adapter** — `scripts/WinSetupApi.psm1` (`Invoke-WinSetupApi`) exposes
  the engine as JSON in / JSON out (verbs: system, diagnose, profiles,
  components, status, plan, apply, journal, resume, export, import). It contains
  **no** install/configure logic. `scripts/winsetup-api.ps1` is the thin
  transport wrapper (NDJSON event stream for apply/resume).
  `tests/unit/Api.Tests.ps1`.
* **`export` / `import`** verbs — serialize / validate the merged config
  document (no new planning logic).
* **`winsetup` launcher** — `launcher/WinSetupPro` module (`Invoke-WinSetup`,
  alias `winsetup`) + `launcher/bin` shims + `scripts/install-launcher.ps1`
  (per-user PATH + `$PROFILE` line, `WINSETUP_HOME`). `winsetup` with no flags
  opens the GUI; any CLI flag is forwarded verbatim to `WinSetup.ps1`. The
  classic CLI is unchanged. `tests/unit/Launcher.Tests.ps1`.
* **WPF app** — `ui/WinSetup.Pro.UI` (`net10.0-windows`, hand-rolled MVVM, **zero
  NuGet dependencies**, `asInvoker` manifest, self-contained `win-x64` publish).
  Pages: Dashboard, Profiles, Components, Review, Run (live progress from the
  engine's events), Result, Diagnostics, History, Settings. `EngineClient`
  spawns the JSON adapter; a `StringListConverter` tolerates the engine's
  scalar-or-array JSON. Elevation via `ElevationService.RestartElevated` (`runas`)
  offered from Review when the plan needs admin — the app itself never runs
  elevated. Long work is async; cancel is blocked mid-component with a clear
  message.
* `docs/GUI.md`; CI builds the GUI on `windows-latest`. Unit suite: 112 tests.

## [0.1.0] - 2026-09-10

First milestone: the Core engine, 40 components, five profiles, an 80-test
Pester suite and CI. Built in eight phases.

### Phase 8 — Documentation

* `docs/SECURITY.md`, `docs/MODULES.md` (component authoring guide with the
  lifecycle diagram, helper reference and pitfalls) and `docs/TROUBLESHOOTING.md`.
* `README.md` reworked: quick start, contents index, profile table, real
  dry-run output, links to the deep-dive docs; sections renumbered.
* `CONTRIBUTING.md`: layout, release process, the `$PROFILE` naming trap.
* `docs/ARCHITECTURE.md`: full Core file list, repository-layout and
  runtime-output tables.
* Removed the empty `modules/Development/` and `modules/Git/` category folders
  (Category is a descriptor field, not the folder).

### Phase 7 — Testing (added / changed)

* **80-test Pester suite** (Pester 5 or 6), all green, host-safe (TestDrive:,
  in-memory registries, synthetic components, `$env:USERPROFILE` / `$global:PROFILE`
  redirection restored in `finally`).
* `tests/unit/Detection.Tests.ps1` — every one of the 40 components' `Test`
  returns a well-formed result and is read-only (HOME dotfiles unchanged after
  running all Tests twice).
* `tests/unit/Idempotency.Tests.ps1` — a full engine plan run 2-3 times:
  second run installs/configures nothing; dry-run first does not perturb it;
  plus a real `folders` round-trip.
* `tests/unit/Resume.Tests.ps1` — abort at a critical failure leaves an
  incomplete journal; `-Resume` re-runs only Pending/Failed and completes;
  already-succeeded entries are not re-run; a completed run has nothing to
  resume; dry-run writes `last-dryrun.json` and never touches `last-run.json`.
* `tests/integration/Winget.Integration.Tests.ps1` — real winget install +
  idempotency of `jqlang.jq`; tagged `Integration`, self-skips unless
  `WINSETUP_ALLOW_INTEGRATION=1`, uninstalls only what it installed.
* `tests/RunTests.ps1` reworked: Pester 5/6 config API, `-Tag` / `-ExcludeTag`
  / `-Coverage` / `-CI`, integration excluded from the default `unit` run.
* `.github/workflows/ci.yml` — syntax check + PSScriptAnalyzer + unit suite on
  `windows-latest`, JUnit results uploaded.

### Phase 6 — Profiles (added / changed)

* **15 new components.** Development: `visualstudio` (admin),
  `jetbrains-toolbox`, `cmake`, `ninja`, `go`, `rust`, `java` (Temurin,
  version-configurable), `neovim`. Database: `sqlserver-tools` (go-sqlcmd),
  `azure-data-studio`, `postgresql` (admin, version-configurable), `mysql`
  (admin), `redis-cli` (admin), `mongodb-tools`, `mongosh`.
* **Profiles reworked** so every id in `minimal`, `frontend`, `dotnet`,
  `fullstack`, `enterprise` resolves to a registered component, with coherent
  feature blocks (`git`, `powershellProfile`, `wsl`, `ssh`, `fonts`,
  `folders`). A new `Profiles.Tests.ps1` enforces "every profile plan resolves
  and dry-runs clean".
* **Fixed a `$PROFILE` corruption bug**: the CLI switch is now `-Profile` as an
  **alias** of `-SetupProfile`. A parameter literally named `Profile` (bound via
  `-Profile <x>`) overwrites the process-wide automatic `$PROFILE` variable,
  which broke the `powershell-profile` component.
* `config` / `schema`: `java.version`, `postgresql.version`.
* Verification suite 57/57; 40 components.

### Phase 5 — Customisation (added)

* **`Backup-WinSetupFile`** (`modules/Core/Backup.ps1`): one consolidated
  snapshot helper — `backup/<category>/<timestamp>/`. Git, SSH and WSL now use
  it.
* **`powershell-profile`** (`modules/PowerShell/Profile.ps1`): copies the
  requested fragments (`aliases`, `functions`, `prompt`, `git`, `docker`,
  `environment` — templates in `templates/powershell/`) into
  `<profile dir>\winsetup-pro\` and maintains a single **marked block** in
  `$PROFILE` that dot-sources them. Content outside the markers is never
  touched; `$PROFILE` is backed up before the block is first added/changed.
  Optional `powershellProfile.modules` are installed with
  `Install-Module -Scope CurrentUser`.
* **`dotfiles`** (`modules/Dotfiles/Dotfiles.ps1`): restores config files from a
  local folder or a git repo (cloned into `state/dotfiles/`). A file is only
  replaced when it differs; the existing file is backed up first — always
  unattended, via a Yes/No/Skip prompt when interactive
  (`dotfiles.backupExisting`). Nothing is ever deleted. `copy` (default) or
  `symlink`; explicit `dotfiles.map` or auto-mapping to `$HOME`.
* **`post-install`** (`modules/PostInstall/PostInstall.ps1`): runs the local
  `.ps1` scripts listed in `postInstall.scripts`, recording each by content
  hash in `state/postinstall.json` so an unchanged script is not re-run
  (`postInstall.always` to override). No remote scripts.
* **CLI**: `-Dotfiles <path>`, `-DotfilesRepository <url>`.
* `config` / `schema`: `powershellProfile`, `dotfiles`, `postInstall` blocks.
* Tests: `tests/unit/Customization.Tests.ps1`; verification suite 51/51.

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

[Unreleased]: https://github.com/<you>/WinSetup-Pro/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/<you>/WinSetup-Pro/releases/tag/v0.1.0
