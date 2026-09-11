<div align="center">

<img src="ui/WinSetup.Pro.UI/Assets/app-256.png" width="120" alt="WinSetup Pro logo" />

# WinSetup Pro

**Turn a clean Windows install into a configured developer workstation — reproducibly, in minutes.**

[![CI](https://github.com/ArcGabicho/winsetup-pro/actions/workflows/ci.yml/badge.svg)](https://github.com/ArcGabicho/winsetup-pro/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![PowerShell 7+](https://img.shields.io/badge/PowerShell-7%2B-5391FE?logo=powershell&logoColor=white)](https://learn.microsoft.com/powershell/)
[![.NET 10](https://img.shields.io/badge/.NET-10-512BD4?logo=dotnet&logoColor=white)](https://dotnet.microsoft.com/)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

[Quick start](#quick-start) · [How it works](#how-it-works) · [Docs](docs/) · [Architecture](docs/ARCHITECTURE.md) · [Security](docs/SECURITY.md) · [Changelog](CHANGELOG.md) · [Contributing](CONTRIBUTING.md)

</div>

---

WinSetup Pro is a small, modular PowerShell product with an optional WPF desktop
app. You describe the machine you want — a **profile** or a list of
**components** — and the engine detects what is missing and applies **only
that**. Running it a second time changes nothing.

**Current status:** `0.1.0` — phases 1–8 complete, plus a Windows 11-style
desktop app (`0.2.0`). Core engine and CLI, **40 components** across
Development / Cloud / Database / Environment / Customisation, five built-in
profiles, a 117-test Pester suite, and CI on `windows-latest`.

## Table of contents

- [Highlights](#highlights)
- [Quick start](#quick-start)
- [Requirements](#requirements)
- [How it works](#how-it-works)
- [Usage](#usage)
- [Profiles](#profiles)
- [Configuration](#configuration)
- [What it sets up](#what-it-sets-up)
- [Dry-run and safety](#dry-run-and-safety)
- [Troubleshooting](#troubleshooting)
- [Project layout](#project-layout)
- [Development](#development)
- [Roadmap](#roadmap)
- [Versioning](#versioning)
- [Contributing](#contributing)
- [Security](#security)
- [License](#license)
- [Acknowledgements](#acknowledgements)

## Highlights

| | |
|---|---|
| **Idempotent** | Every component runs a read-only `Test` before it `Install`s or `Configure`s. A second run is a no-op. |
| **Dry-run first** | `-DryRun` prints the full plan and touches nothing — it is an engine mode, not a per-module `if`. |
| **Reversible** | A per-run **journal** enables `-Resume` after an interruption; risky changes are backed up under `backup/` before they happen. |
| **Safe by default** | No silent overwrites, no credentials requested or stored, and Windows Defender / firewall / security policy are never touched. |
| **Declarative** | Machines are described in JSON (`config/`, `profiles/`); layers deep-merge. |
| **Modular** | Each tool or config task is a self-describing **component** file. The core never changes when you add one. |
| **Two front ends, one engine** | The CLI and the desktop app are both clients of the same `modules/Core` engine — no duplicated install logic. |
| **Observable** | Structured, level-based logs per run under `logs/`. |

## Quick start

### Graphical app — one command

```powershell
git clone https://github.com/ArcGabicho/winsetup-pro.git
cd winsetup-pro
pwsh -File .\scripts\gui.ps1
```

`gui.ps1` builds the app on first run (needs the
[.NET SDK 10+](https://dotnet.microsoft.com/download); about 10 s) and then
launches it. The window walks you through **Profile → Customize → Review →
Apply**. Nothing changes until you confirm.

### Command line — no build, no SDK

```powershell
pwsh -File .\WinSetup.ps1 -Diagnose                 # is this machine ready?
pwsh -File .\WinSetup.ps1 -Profile minimal -DryRun  # preview the plan
pwsh -File .\WinSetup.ps1 -Profile minimal          # apply it
pwsh -File .\WinSetup.ps1 -Profile enterprise -ConfigFile company.json -NonInteractive
```

On a fresh machine, bootstrap the prerequisites first:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap.ps1
```

`bootstrap.ps1` checks PowerShell, execution policy and `winget`, then hands off
to the local `WinSetup.ps1`. There is intentionally **no `irm … | iex`
one-liner** — see [Security](#security).

### Global `winsetup` command

```powershell
.\scripts\install-launcher.ps1     # per-user PATH + $PROFILE line, no admin
# open a new terminal:
winsetup                            # -> graphical app
winsetup -Profile dotnet -DryRun    # -> CLI, every flag forwarded verbatim
```

For distribution, publish a self-contained executable (end users need no .NET):

```powershell
dotnet publish ui\WinSetup.Pro.UI\WinSetup.Pro.UI.csproj -c Release -r win-x64 --self-contained
```

Details in [docs/GUI.md](docs/GUI.md).

## Requirements

- Windows 10 (build 19041+) or Windows 11
- Windows PowerShell 5.1 for bootstrap — **PowerShell 7 recommended** for daily use
- [`winget`](https://learn.microsoft.com/windows/package-manager/) (App Installer) for automated installs
- .NET SDK 10+ **only** to build the desktop app from source
- Administrator rights **only** for components that change machine scope — each one declares it

## How it works

```
profile / -Install list
        │
        ▼
   detect  ──▶  plan  ──▶  [confirm]  ──▶  apply  ──▶  journal + logs + backups
  (read-only Test)      (-DryRun stops here)                 │
                                                       -Resume continues here
```

| Layer | Responsibility |
|---|---|
| `WinSetup.ps1` | Composition root. Parses the CLI, builds config + context, dispatches to one command. |
| `modules/Core/` | The engine, imported as a single module: detection, config layering, planning, execution, journal, backups, logging. |
| `modules/<name>/*.ps1` | Components. Auto-discovered, never imported by name. `Category` is a field, not the folder. |
| `ui/WinSetup.Pro.UI/` | WPF desktop app (`net10.0-windows`, self-contained). Talks to the engine through a JSON adapter. |

Full design notes — the component contract, the config pipeline, the safety
model and the extensibility story — are in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Usage

```powershell
.\WinSetup.ps1                       # interactive menu
.\WinSetup.ps1 -Profile minimal      # apply a profile   (alias of -SetupProfile)
.\WinSetup.ps1 -Profile dotnet -DryRun
.\WinSetup.ps1 -Install git,nodejs   # just these components
.\WinSetup.ps1 -WSL                  # one feature area   (also -Git, -SSH)
.\WinSetup.ps1 -Dotfiles "C:\path\to\dotfiles"
.\WinSetup.ps1 -List                 # available components
.\WinSetup.ps1 -Status               # what is installed / configured
.\WinSetup.ps1 -Diagnose             # host readiness checks
.\WinSetup.ps1 -Resume               # continue an interrupted run
.\WinSetup.ps1 -Update               # update managed tools via winget
```

Global switches: `-DryRun`, `-NonInteractive`, `-ConfigFile <path>`,
`-LogLevel <DEBUG|INFO|SUCCESS|WARNING|ERROR>`.

Exit codes: `0` success · `1` completed with failures or checks to address ·
`2` fatal error.

## Profiles

Declarative files in `profiles/`, layered on top of `config/default.json`. Your
`-ConfigFile` layers on top of that; `-Install` overrides the app list entirely.

| Profile | For | Adds on top of the previous row |
|---|---|---|
| `minimal` | any developer | git, PowerShell 7, Windows Terminal, VS Code, GitHub CLI |
| `frontend` | web / front-end | Node.js, npm, pnpm, Python, PowerShell profile, Cascadia + Fira Code |
| `dotnet` | .NET | Visual Studio, .NET SDK, Docker, Azure CLI, sqlcmd, Azure Data Studio, WSL |
| `fullstack` | web + services | PostgreSQL, Redis, mongosh, Docker, WSL |
| `enterprise` | standardised corp workstation | AWS / gcloud / Terraform / kubectl / Helm, Java, SSH, PSReadLine, more fonts |

```jsonc
// profiles/minimal.json
{
  "profile": "minimal",
  "applications": ["git", "pwsh", "windows-terminal", "vscode", "github-cli"],
  "git": { "enabled": true }
}
```

Component ids that a profile lists but this build does not provide are
**reported and skipped**, never failed.

## Configuration

`config/default.json` is the base document, validated against
`config/schema.json`. Every key can be overridden by a profile or by a user
config passed with `-ConfigFile`:

```jsonc
{
  "applications": ["git", "vscode", "nodejs"],
  "git": { "enabled": true, "defaultBranch": "main", "pullRebase": "true" },
  "environment": { "user": { "EDITOR": "code" }, "path": ["%USERPROFILE%\\bin"] },
  "folders": ["Dev\\Projects", "Dev\\OpenSource"],
  "fonts": ["CascadiaCode"],
  "powershellProfile": { "enabled": true }
}
```

Layering: `config/default.json ← profiles/<name>.json ← -ConfigFile ← -Install`.
Nested objects deep-merge; `applications` / `fonts` / `folders` union without
duplicates; other values are replaced.

WinSetup Pro **never** asks for `user.name` / `user.email`. Set `git.userName` /
`git.userEmail` in config if you want a *missing* identity filled in — an
existing one is never overwritten.

## What it sets up

<details>
<summary><strong>Applications</strong> — 30+ tools via winget, official sources only</summary>

Editors and runtimes (VS Code, Visual Studio, JetBrains Toolbox, Neovim, .NET
SDK, Node.js + npm + pnpm, Python, Go, Rust, Java), cloud CLIs (Azure, AWS,
gcloud, Terraform, kubectl, Helm), databases and clients (PostgreSQL, MySQL,
Redis, mongosh, MongoDB tools, SQL Server tools, Azure Data Studio),
containers (Docker Desktop), build tools (CMake, Ninja) and the base developer
set (Git, PowerShell 7, Windows Terminal, GitHub CLI). Each component detects
its own presence and version; already-installed tools are skipped.
</details>

<details>
<summary><strong>WSL 2</strong></summary>

`-WSL` (or `wsl.enabled` in a profile; needs an elevated session) enables the
WSL and Virtual Machine Platform features, sets default version 2, and installs
a validated distribution with `--no-launch`. `~/.wslconfig` is written **only if
absent** (unless `wsl.overwriteWslConfig: true`, which backs it up first). An
existing distribution is **never** unregistered, reset or overwritten.
</details>

<details>
<summary><strong>Git</strong></summary>

Installs Git and applies an idempotent global config (`init.defaultBranch`,
`pull.rebase`, `credential.helper`, `core.editor`). It **never overwrites** an
existing `user.name` / `user.email`, and backs up `~/.gitconfig` before the
first change. Authentication is delegated to Git Credential Manager / SSH /
GitHub CLI — no passwords stored.
</details>

<details>
<summary><strong>SSH</strong></summary>

`-SSH` (or `ssh.enabled`) installs the OpenSSH client when missing, discovers
existing keys in `~/.ssh` and **never overwrites or regenerates them**, and
offers to create a key only when none exists. `ssh.providers` appends the
**missing** `~/.ssh/config` Host blocks after a backup, and locks permissions
down with `icacls`. No passphrase or password is ever stored.
</details>

<details>
<summary><strong>Environment variables, folders, fonts</strong></summary>

`env-vars` applies `environment.user` / `environment.machine` and appends
de-duplicated entries to the **User** PATH (previous values snapshotted to
`backup/environment/`). `folders` creates the `folders` tree under your profile
— only ever creates, never deletes. `fonts` does a per-user install (no admin)
of Cascadia Code / Mono, JetBrains Mono and Fira Code from their official GitHub
releases.
</details>

<details>
<summary><strong>PowerShell profile and dotfiles</strong></summary>

`powershellProfile.enabled` copies the requested fragments into
`<profile dir>\winsetup-pro\` and keeps **one marked block** in your `$PROFILE`
that loads them; everything outside the markers is left untouched and the
profile is backed up first. `-Dotfiles <path>` / `-DotfilesRepository <url>`
maps each file to `$HOME`, replacing only when it differs and backing up the
original first. Nothing is ever deleted.
</details>

<details>
<summary><strong>Post-install scripts</strong></summary>

`postInstall.scripts` runs **local** `.ps1` files last, each recorded by content
hash so an unchanged script is not re-run. Remote scripts are never fetched.
</details>

## Dry-run and safety

`-DryRun` runs every component's read-only `Test`, prints the intended
`INSTALL` / `CONFIGURE` actions (admin-only components flagged *needs
elevation*), writes a preview journal to `state/last-dryrun.json`, and makes no
changes.

```text
Profile : dotnet
Plan    : git, pwsh, windows-terminal, vscode, visualstudio, dotnet-sdk, ...
Mode    : DRY RUN

[1/12]  Git ............................. [SKIP]  already present (v2.55.0)
[7/12]  Node.js ......................... [DRY ]  INSTALL
[11/12] Docker Desktop .................. [DRY ]  INSTALL + CONFIGURE (needs elevation)
...
DRY RUN - no changes were made.
  Planned : 6   Installed : 0   Failed : 0
```

The safety model, in short — full detail in [docs/SECURITY.md](docs/SECURITY.md):

- **No remote code execution.** `bootstrap.ps1` only prepares prerequisites and
  runs the local, reviewable `WinSetup.ps1`. No `irm | iex`.
- **Official sources only.** `winget` (default source) or the Microsoft Store;
  fonts from official GitHub releases. No arbitrary downloads.
- **No secrets.** Nothing asks for, prints, logs or stores a password, token or
  passphrase.
- **Non-destructive.** Detect, back up, then change. SSH keys, Git identity and
  existing `$PROFILE` / `.wslconfig` / `.ssh/config` content are never
  overwritten.
- **Least privilege.** Only the components that must, request elevation, and
  each says why. The desktop app runs non-elevated.
- Windows Defender, the firewall and security policy are **never** touched.

## Troubleshooting

Full table in [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md). The quick hits:

| Symptom | Fix |
|---|---|
| `running scripts is disabled` | `powershell -ExecutionPolicy Bypass -File .\WinSetup.ps1 …` |
| `winget … is not available` | Install **App Installer** from the Microsoft Store |
| `[WARN] requires an elevated session - skipped` | Re-run from an elevated PowerShell |
| Tool installed but "not found" this session | Open a new terminal (PATH is stale) |
| A run stopped half-way | `.\WinSetup.ps1 -Resume` |
| Need detail | newest file in `logs/`, or `-LogLevel DEBUG` |

## Project layout

```
WinSetup.ps1            Composition root / CLI
modules/Core/           The engine, loaded as one module (Core.psm1)
modules/<name>/         Component files, auto-discovered (Category is a field)
config/                default.json + schema.json + example configs
profiles/              Declarative install profiles
scripts/               bootstrap / install / update / uninstall / diagnose / gui
launcher/              The global `winsetup` command (PowerShell module + PATH shims)
ui/WinSetup.Pro.UI/     WPF desktop app (net10.0-windows, self-contained)
templates/powershell/   PowerShell profile fragments
tests/unit/             Pester unit specs (TestDrive only, host-safe)
tests/integration/      Real-install specs, tagged 'Integration', opt-in
docs/                  Architecture · GUI · Security · Modules · Troubleshooting · Overview
```

## Development

```powershell
# once
Install-Module Pester -Scope CurrentUser -MinimumVersion 5.5.0 -Force -SkipPublisherCheck

pwsh -File .\tests\RunTests.ps1                    # unit suite (117 tests, host-safe)
pwsh -File .\tests\RunTests.ps1 -Suite all -CI     # + JUnit results in logs\
pwsh -File .\tests\RunTests.ps1 -Coverage          # + code coverage
$env:WINSETUP_ALLOW_INTEGRATION = '1'
pwsh -File .\tests\RunTests.ps1 -Suite integration # real winget install/uninstall
```

Unit tests never modify the host — `TestDrive:`, in-memory registries, synthetic
components, redirections restored in `finally`. They run on Pester 5 and 6.

**Adding a component:** copy `modules/Applications/_Template.ps1`, implement
`Test` (read-only) and `Install` / `Configure` (throw on failure), and return
the descriptor as the file's last statement — no side effects at load time. The
full contract, lifecycle and helper reference are in
[docs/MODULES.md](docs/MODULES.md).

**CI** (`.github/workflows/ci.yml`) runs on every push and PR: parse check,
PSScriptAnalyzer, the GUI build, and the unit suite on `windows-latest`.

## Roadmap

| Phase | Scope | State |
|---|---|---|
| 1 | Core engine, CLI, logging, config, dry-run, status, journal / resume | ✅ done |
| 2 | pwsh, Windows Terminal, VS Code, GitHub CLI, .NET SDK, Node.js, npm, pnpm, Python, Docker | ✅ done |
| 3 | Cloud CLIs (Azure/AWS/gcloud/Terraform/kubectl/Helm) · SSH · env vars · folders · fonts | ✅ done |
| 4 | WSL 2 module (features, default version, `.wslconfig`, distributions) | ✅ done |
| 5 | Modular PowerShell profile · dotfiles · consolidated backups · post-install scripts | ✅ done |
| 6 | Full profile set + 15 more components (VS, JetBrains, Go, Rust, Java, CMake/Ninja, Neovim, SQL/Postgres/MySQL/Redis/Mongo) | ✅ done |
| 7 | 100+-test Pester suite (unit + idempotency + resume), integration scaffold, GitHub Actions CI | ✅ done |
| 8 | Documentation set (README, Architecture, Security, Modules, Troubleshooting) | ✅ done |
| — | **WPF desktop app** over the same engine API | ✅ done |

**Next (post-0.1.0):** publish to winget · remote / multi-machine execution ·
YAML config · a component marketplace. The core is designed so these do not
require a rewrite — see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) §10.

## Versioning

Releases follow [Semantic Versioning](https://semver.org/). User-visible changes
are recorded in [CHANGELOG.md](CHANGELOG.md); phases 1–8 constitute `0.1.0`. To
cut a release, move the `[Unreleased]` entries under a dated `[x.y.z]` heading
and tag `vX.Y.Z`.

## Contributing

Contributions are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md) and
[docs/MODULES.md](docs/MODULES.md). In short: keep changes modular, idempotent
and host-safe; official sources only; the core is closed for modification — new
tools are new component files. CI must be green and PRs should include the
`RunTests.ps1` summary line.

## Security

Please report vulnerabilities privately rather than in a public issue — see
[docs/SECURITY.md](docs/SECURITY.md) for the reporting process and the full
threat model.

## License

[MIT](LICENSE) © 2026 WinSetup Pro contributors.

## Acknowledgements

Built on [PowerShell](https://github.com/PowerShell/PowerShell),
[Pester](https://pester.dev/), the
[Windows Package Manager](https://github.com/microsoft/winget-cli) and WPF on
.NET. Icons use Segoe Fluent Icons.
