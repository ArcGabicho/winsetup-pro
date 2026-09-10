# WinSetup Pro

> Windows developer setup assistant — turn a clean Windows install into a
> configured development workstation, reproducibly, in minutes.

WinSetup Pro is a small, modular PowerShell product. You describe the machine
you want (a **profile** or a list of **components**) and the engine works out
what is missing and applies **only that**. Running it twice changes nothing the
second time.

**Status:** Phases 1–8 complete. Core engine + CLI, **40 components** across
Development / Cloud / Database / Environment / Customisation, five profiles, an
80-test Pester suite, and CI. See [CHANGELOG.md](CHANGELOG.md).

## Quick start

```powershell
git clone https://github.com/<you>/WinSetup-Pro.git
cd WinSetup-Pro

.\WinSetup.ps1 -Diagnose                 # is this machine ready?
.\WinSetup.ps1 -Profile minimal -DryRun  # what would "minimal" do?
.\WinSetup.ps1 -Profile minimal          # do it
```

---

## Contents

1. [What it is](#1-what-it-is) · 2. [Requirements](#2-requirements) ·
3. [Installation](#3-installation) · 4. [Usage](#4-usage) ·
5. [Profiles](#5-profiles) · 6. [Configuration](#6-configuration) ·
7. [WSL](#7-wsl) · 8. [Git](#8-git) · 9. [SSH](#9-ssh) ·
10. [Environment / folders / fonts](#10-environment-variables-folders-fonts) ·
11. [PowerShell profile](#11-powershell-profile) · 12. [Dotfiles](#12-dotfiles) ·
13. [Post-install scripts](#13-post-install-scripts) · 14. [Dry-run](#14-dry-run) ·
15. [Security](#15-security) · 16. [Troubleshooting](#16-troubleshooting) ·
17. [Developing a component](#17-developing-a-component) · 18. [Testing](#18-testing) ·
19. [Contributing](#19-contributing)

Deep-dive docs: [Architecture](docs/ARCHITECTURE.md) ·
[Security](docs/SECURITY.md) · [Writing a component](docs/MODULES.md) ·
[Troubleshooting](docs/TROUBLESHOOTING.md)

---

## 1. What it is

| Principle | How WinSetup Pro applies it |
|---|---|
| Modular | Every tool/config task is a self-describing **component** file. The core never changes when you add one. |
| Idempotent | Each component must `Test` before it `Install`/`Configure`s. Nothing is redone. |
| Declarative | Machines are described in JSON (`config/`, `profiles/`). |
| Safe by default | No silent overwrites, no credentials stored, no security features disabled. Backups before risky changes. |
| Observable | Structured, level-based logs per run under `logs/`. |
| Reversible | A run **journal** allows `-Resume`; risky changes are backed up under `backup/`. |
| Dry-run first | `-DryRun` prints the plan and touches nothing. |

## 2. Requirements

* Windows 10 (build 19041+) or Windows 11
* Windows PowerShell 5.1 (bootstrap) — **PowerShell 7 recommended** for daily use
* `winget` (App Installer) for automated installs
* Administrator rights **only** for components that change machine scope (each one declares it)

## 3. Installation

```powershell
git clone https://github.com/<you>/WinSetup-Pro.git
cd WinSetup-Pro
#  read scripts\bootstrap.ps1 and WinSetup.ps1, then:
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap.ps1
```

`bootstrap.ps1` checks PowerShell / execution policy / winget and then launches
the local `WinSetup.ps1`. There is intentionally **no `irm … | iex` one-liner**
— see [Security](#15-security).

## 4. Usage

```powershell
.\WinSetup.ps1                       # interactive menu
.\WinSetup.ps1 -Profile minimal      # apply a profile   (alias of -SetupProfile)
.\WinSetup.ps1 -Profile dotnet -DryRun
.\WinSetup.ps1 -Install git,nodejs   # just these components
.\WinSetup.ps1 -WSL                  # one component      (also -Git, -SSH)
.\WinSetup.ps1 -Dotfiles "C:\path\to\dotfiles"
.\WinSetup.ps1 -List                 # list available components
.\WinSetup.ps1 -Status               # what is installed / configured
.\WinSetup.ps1 -Diagnose             # host readiness checks
.\WinSetup.ps1 -Resume               # continue an interrupted run
```

Global switches: `-DryRun`, `-NonInteractive`, `-ConfigFile <path>`,
`-LogLevel <DEBUG|INFO|SUCCESS|WARNING|ERROR>`.

Exit codes: `0` success · `1` completed with failures / checks to address ·
`2` fatal error.

## 5. Profiles

Declarative files in `profiles/`, layered on top of `config/default.json`
(your `-ConfigFile` layers on top of that; `-Install` overrides the app list
entirely).

| Profile | For | Highlights |
|---|---|---|
| `minimal` | any developer | git, PowerShell 7, Windows Terminal, VS Code, GitHub CLI |
| `frontend` | web / front-end | + Node.js, npm, pnpm, Python, profile, Cascadia + Fira Code |
| `dotnet` | .NET | + Visual Studio, .NET SDK, Docker, Azure CLI, sqlcmd, Azure Data Studio, WSL |
| `fullstack` | web + services | + PostgreSQL, Redis, mongosh, Docker, WSL |
| `enterprise` | standardised corp workstation | + AWS/gcloud/Terraform/kubectl/Helm, Java, SSH, `PSReadLine`, more fonts |

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

## 6. Configuration

`config/default.json` is the base document (validated against
`config/schema.json`). Every key can be overridden by a profile or a user
config file passed with `-ConfigFile`:

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

WinSetup Pro **never** asks for `user.name` / `user.email`; set `git.userName` /
`git.userEmail` in config if you want a *missing* identity filled in — an
existing one is never overwritten.

## 7. WSL

`.\WinSetup.ps1 -WSL` (or `wsl.enabled` in a profile — needs an elevated
session):

* enables the **WSL** and **Virtual Machine Platform** features
  (`wsl --install --no-distribution`, DISM fallback) and tells you to restart;
* runs `wsl --set-default-version 2` when `wsl.setDefaultVersion2` (default);
* installs `wsl.distribution` (validated against `wsl --list --online`, with
  `--no-launch`); with no distribution set, an interactive run shows a menu;
* writes `~/.wslconfig` from `wsl.wslConfig` **only if the file does not exist**
  — an existing one is left untouched unless `wsl.overwriteWslConfig: true`
  (and is backed up first);
* **never** unregisters, resets or overwrites an existing distribution.

```jsonc
"wsl": {
  "enabled": true,
  "distribution": "Ubuntu",
  "setDefaultVersion2": true,
  "wslConfig": { "memory": "6GB", "processors": 4, "swap": "0" }
}
```

## 8. Git

The `git` component installs Git via winget and applies an idempotent global
config (`init.defaultBranch`, `pull.rebase`, `credential.helper`, `core.editor`).
It **never overwrites** an existing `user.name` / `user.email`, and it backs up
`~/.gitconfig` (to `backup/git/`) before the first change. Authentication is
delegated to Git Credential Manager / SSH / GitHub CLI — no passwords stored.

## 9. SSH

`.\WinSetup.ps1 -SSH` (or `ssh.enabled` in a profile):

* detects the OpenSSH client; installs it via the Windows capability when
  missing (needs an elevated session);
* discovers existing keys in `~/.ssh` and **never overwrites or regenerates
  them**;
* offers to create a key only when none exists — interactively (`ssh-keygen`
  then prompts for a passphrase), or unattended only if
  `ssh.generateKeyUnattended: true` (which warns the key has no passphrase);
* `ssh.providers: ["github.com", "gitlab.com", …]` appends the **missing**
  `~/.ssh/config` Host blocks (never rewrites existing ones) after backing the
  file up, and locks down permissions with `icacls`;
* never stores a passphrase or password.

## 10. Environment variables, folders, fonts

* **`env-vars`** — applies `environment.user` / `environment.machine` (machine
  scope needs elevation) and appends `environment.path` entries to the **User**
  PATH, de-duplicated (case-insensitive). Previous values are snapshotted to
  `backup/environment/`.
* **`folders`** — creates the `folders` tree under your user profile; only ever
  creates, never deletes.
* **`fonts`** — per-user install (no admin) of Cascadia Code / Mono, JetBrains
  Mono and Fira Code from their **official GitHub releases**; already-installed
  families are skipped.

These run automatically when a profile/config gives them work; otherwise they
report "nothing to do" and are skipped.

## 11. PowerShell profile

`powershellProfile.enabled` (or `-Install powershell-profile`). WinSetup Pro
copies the requested fragments into `<profile dir>\winsetup-pro\` and keeps
**one marked block** in your `$PROFILE` that loads them:

```
# >>> WinSetup Pro managed block >>>
#   loads winsetup-pro\{aliases,functions,prompt,git,docker,environment}.ps1
# <<< WinSetup Pro managed block <<<
```

Everything outside the markers is left exactly as it was; the profile is backed
up (to `backup/powershell/`) before the block is first written.
`powershellProfile.modules` (e.g. `["PSReadLine", "Terminal-Icons"]`) are
installed with `Install-Module -Scope CurrentUser`.

## 12. Dotfiles

```powershell
.\WinSetup.ps1 -Dotfiles "C:\Users\me\dotfiles"
.\WinSetup.ps1 -DotfilesRepository "https://github.com/me/dotfiles.git"
```

* a repo is cloned into `state/dotfiles/`; a folder is used in place;
* each file maps to the same relative path under `$HOME` (or use `dotfiles.map`)
  and is only replaced when it differs;
* before replacing, the existing file is backed up to
  `backup/dotfiles/<timestamp>/` — always in `-NonInteractive`, or via a
  **Yes / No / Skip** prompt (`dotfiles.backupExisting: prompt | always | never`);
* nothing is ever deleted; `dotfiles.link: symlink` is available (falls back to
  copy if it can't create the link).

## 13. Post-install scripts

`postInstall.scripts: ["scripts/my-finish.ps1"]` — **local** `.ps1` files run
after the rest, each recorded by content hash so an unchanged script is not
re-run (`postInstall.always: true` to force). Remote scripts are never fetched.

## 14. Dry-run

`-DryRun` runs every component's read-only `Test`, prints the intended
`INSTALL` / `CONFIGURE` actions (admin-only components flagged *needs
elevation*), writes a preview journal to `state/last-dryrun.json`, and makes no
changes.

```text
Profile : dotnet
Plan    : git, pwsh, windows-terminal, vscode, visualstudio, dotnet-sdk, ...
Mode    : DRY RUN

[1/12] Git ............................... [SKIP]  already present (v2.55.0)
[7/12] Node.js .......................... [DRY ]  INSTALL
[11/12] Docker Desktop .................. [DRY ]  INSTALL + CONFIGURE (needs elevation)
...
DRY RUN - no changes were made.
  Planned : 6   Installed : 0   Failed : 0
```

## 15. Security

Full detail in [docs/SECURITY.md](docs/SECURITY.md). In short:

* **No remote code execution** — `bootstrap.ps1` only prepares prerequisites and
  runs the local, reviewable `WinSetup.ps1`. No `irm | iex`.
* **Official sources only** — `winget` (default source) or the Microsoft Store;
  fonts from official GitHub releases. No arbitrary downloads.
* **No secrets** — nothing asks for, prints, logs or stores a password, token or
  passphrase.
* **Non-destructive** — detect, back up, then change; SSH keys, Git identity and
  existing `$PROFILE` / `.wslconfig` / `.ssh/config` content are never
  overwritten.
* **Least privilege** — only the components that must, request elevation, and
  each says why; the execution policy is relaxed for the current process only.
* Windows Defender, the firewall and security policy are **never** touched.

## 16. Troubleshooting

Full table in [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md). The quick hits:

| Symptom | Fix |
|---|---|
| `running scripts is disabled` | `powershell -ExecutionPolicy Bypass -File .\WinSetup.ps1 …` |
| `winget … is not available` | Install **App Installer** from the Microsoft Store |
| `[WARN] requires an elevated session - skipped` | Re-run from an elevated PowerShell |
| Tool installed but "not found" this session | Open a new terminal (PATH is stale) |
| A run stopped half-way | `.\WinSetup.ps1 -Resume` |
| Need detail | newest file in `logs/`, or `-LogLevel DEBUG` |

## 17. Developing a component

Full guide: [docs/MODULES.md](docs/MODULES.md). Copy
`modules/Applications/_Template.ps1` to `modules/<Category>/<Name>.ps1`; the
file **returns** a descriptor and has **no side effects at load time**.

```powershell
New-WinSetupComponent -Id 'ripgrep' -Name 'ripgrep' -Category 'Development' `
    -Description 'Fast recursive search (rg)' `
    -Test {
        param($Context)
        $v = Get-WinSetupExeVersion -Command 'rg'
        if (-not $v) { return New-WinSetupDetectionResult -Installed $false }
        New-WinSetupDetectionResult -Installed $true -Version $v -Summary "rg $v"
    } `
    -Install {
        param($Context)
        Install-WinSetupWingetPackage -Id 'BurntSushi.ripgrep.MSVC' -VerifyCommand 'rg'
    }
```

Contract: `Test` is read-only and returns `New-WinSetupDetectionResult`;
`Install` / `Configure` **throw** on failure (the engine handles
retry/skip/abort); set `-RequiresAdmin $true` for machine-scope work,
`-Critical $true` to abort the run on failure; order with
`-DependsOn @('other-id')`.

## 18. Testing

```powershell
Install-Module Pester -Scope CurrentUser -MinimumVersion 5.5.0 -Force -SkipPublisherCheck   # once

pwsh -File .\tests\RunTests.ps1                       # unit suite (80 tests)
pwsh -File .\tests\RunTests.ps1 -Suite all -CI        # + JUnit results in logs\
pwsh -File .\tests\RunTests.ps1 -Coverage             # + code coverage
$env:WINSETUP_ALLOW_INTEGRATION = '1'
pwsh -File .\tests\RunTests.ps1 -Suite integration    # real winget install/uninstall
```

Works on Pester 5 and 6. **Unit tests never modify the host** — `TestDrive:`,
in-memory registries, synthetic components, redirections restored in `finally`.
They cover: software detection, install idempotency (a plan run 2-3×), PATH &
environment variables, folder creation, backups, Git config, WSL detection,
dry-run, the error policy, and journal / `-Resume`.

Integration tests (`tests/integration/`, tagged `Integration`) install a real
package and **self-skip** unless `WINSETUP_ALLOW_INTEGRATION=1`; they remove
only what they installed.

CI (`.github/workflows/ci.yml`) runs the syntax check, PSScriptAnalyzer and the
unit suite on `windows-latest`.

## 19. Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and [docs/MODULES.md](docs/MODULES.md).

## Roadmap

| Phase | Scope | State |
|---|---|---|
| 1 | Core engine, CLI, logging, config, dry-run, status, journal/resume | **done** |
| 2 | pwsh, Windows Terminal, VS Code, GitHub CLI, .NET SDK, Node.js, npm, pnpm, Python, Docker Desktop | **done** |
| 3 | Azure/AWS/gcloud/Terraform/kubectl/Helm CLIs · SSH · environment variables · folders · fonts | **done** |
| 4 | WSL 2 module (features, default version, `.wslconfig`, distributions) | **done** |
| 5 | Modular PowerShell profile · dotfiles · consolidated backups · post-install scripts | **done** |
| 6 | Full profile set + 15 more components (VS, JetBrains, Go, Rust, Java, CMake/Ninja, Neovim, SQL/Postgres/MySQL/Redis/Mongo) | **done** |
| 7 | 80-test Pester suite (unit + idempotency + resume), integration scaffold, GitHub Actions CI | **done** |
| 8 | Documentation set (README, Architecture, Security, Modules, Troubleshooting) | **done** |

**Next (post-0.1.0):** GUI/TUI front ends over the same engine API · remote /
multi-machine execution · YAML config · a component marketplace. The core is
designed so these do not require a rewrite — see
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) §10.

## License

MIT — see [LICENSE](LICENSE).
