# WinSetup Pro

> Windows developer setup assistant — turn a clean Windows install into a
> configured development workstation, reproducibly, in minutes.

WinSetup Pro is a small, modular PowerShell product. You describe the machine
you want (a **profile** or a list of **components**) and the engine works out
what is missing and applies only that. Running it twice changes nothing the
second time.

**Status:** Phases 1–3 are implemented and tested — the Core engine/CLI, the
application components (PowerShell 7, Windows Terminal, VS Code, GitHub CLI,
.NET SDK, Node.js, npm, pnpm, Python, Docker Desktop), the cloud/infra CLIs
(Azure, AWS, gcloud, Terraform, kubectl, Helm) and the developer-environment
modules (SSH, environment variables, folders, fonts). WSL, customisation and the
remaining profiles land in later phases — see [CHANGELOG.md](CHANGELOG.md) and
the roadmap below.

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
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap.ps1
```

There is intentionally **no `irm ... | iex` one-liner** — see [Security](#12-security).

## 4. Usage

```powershell
.\WinSetup.ps1                       # interactive menu
.\WinSetup.ps1 -Profile minimal      # apply a profile
.\WinSetup.ps1 -Profile dotnet -DryRun
.\WinSetup.ps1 -Install git          # just these components
.\WinSetup.ps1 -WSL                  # WSL 2 only  (also -Git, -SSH)
.\WinSetup.ps1 -List                 # list available components
.\WinSetup.ps1 -Status               # what is installed / configured
.\WinSetup.ps1 -Diagnose             # host readiness checks
.\WinSetup.ps1 -Resume               # continue an interrupted run
```

Global switches: `-DryRun`, `-NonInteractive`, `-ConfigFile <path>`, `-LogLevel <DEBUG|INFO|SUCCESS|WARNING|ERROR>`.

Exit codes: `0` success · `1` completed with failures / checks to address · `2` fatal error.

## 5. Profiles

Declarative files in `profiles/`. Ship: `minimal`, `frontend`, `dotnet`,
`fullstack`, `enterprise`. A profile is layered on top of `config/default.json`;
your own `-ConfigFile` is layered on top of that; `-Install` overrides the
application list entirely.

```jsonc
// profiles/minimal.json
{
  "profile": "minimal",
  "applications": ["git", "pwsh", "windows-terminal", "vscode", "github-cli"],
  "git": { "enabled": true }
}
```

## 6. Configuration

`config/default.json` is the base document (validated against
`config/schema.json`). Every key can be overridden by a profile or a user
config file. Example user config:

```jsonc
{
  "applications": ["git", "vscode"],
  "git": { "enabled": true, "defaultBranch": "main", "pullRebase": "true" },
  "environment": { "user": { "EDITOR": "code" }, "path": ["%USERPROFILE%\\bin"] },
  "folders": ["Dev\\Projects", "Dev\\OpenSource"]
}
```

WinSetup Pro **never** asks for `user.name` / `user.email`; set them in config if
you want them applied, otherwise Git identity is left untouched.

## 7. WSL

`.\WinSetup.ps1 -WSL` (or `wsl.enabled` in a profile — needs an elevated
session):

* enables the **WSL** and **Virtual Machine Platform** features
  (`wsl --install --no-distribution`, DISM fallback) and tells you to restart;
* runs `wsl --set-default-version 2` when `wsl.setDefaultVersion2` (default);
* installs `wsl.distribution` (validated against `wsl --list --online`,
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
It **never overwrites** an existing `user.name` / `user.email`. Authentication is
delegated to Git Credential Manager / SSH / GitHub CLI — no passwords are stored.

## 9. SSH

`.\WinSetup.ps1 -Install ssh` (or `ssh.enabled` in a profile):

* detects the OpenSSH client; installs it via the Windows capability when
  missing (needs an elevated session).
* discovers existing keys in `~/.ssh` and **never overwrites or regenerates
  them**.
* offers to create a key only when none exists — interactively (`ssh-keygen`
  then prompts for a passphrase), or unattended only if
  `ssh.generateKeyUnattended: true`.
* `ssh.providers: ["github.com", "gitlab.com", …]` appends the missing
  `~/.ssh/config` Host blocks (never rewrites existing ones) after backing the
  file up, and locks down permissions with `icacls`.
* never stores a passphrase or password.

## 9a. Environment variables, folders, fonts

* **`env-vars`** — applies `environment.user` / `environment.machine` (machine
  scope needs elevation) and appends `environment.path` entries to the User
  PATH without duplicates. Previous values are snapshotted to
  `backup/environment/`.
* **`folders`** — creates the `folders` tree under your user profile; only ever
  creates, never deletes.
* **`fonts`** — per-user install (no admin) of Cascadia Code / Mono, JetBrains
  Mono and Fira Code from their official GitHub releases; already-installed
  families are skipped.

These run automatically when a profile/config gives them work; otherwise they
report "nothing to do" and are skipped.

## 10. Dotfiles — *Phase 5*

Local folder or remote repo, with a Yes/No/Skip prompt and versioned backups
before any existing file is replaced.

## 11. Dry-run

`-DryRun` runs every component's read-only `Test`, prints the intended
`INSTALL` / `CONFIGURE` actions, writes a preview journal to
`state/last-dryrun.json`, and makes no changes.

## 12. Security

* No remote script execution. `bootstrap.ps1` only prepares prerequisites and
  launches the local entry point; review the tree before running it.
* Installs go through `winget` / official sources only — no arbitrary downloads.
* No credentials, tokens or passwords are requested, printed or stored.
* SSH keys are never overwritten; identity settings are never silently changed.
* Windows Defender, the firewall and security policies are never modified.
* Machine-scope changes require an elevated session and each component says why.

## 13. Troubleshooting

| Symptom | Fix |
|---|---|
| `running scripts is disabled` | `powershell -ExecutionPolicy Bypass -File .\WinSetup.ps1 ...` or `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |
| `winget not found` | Install **App Installer** from the Microsoft Store |
| A component needs admin | Re-run from an elevated PowerShell session |
| A run stopped half-way | `.\WinSetup.ps1 -Resume` |
| Need detail | check the newest file in `logs/`, or pass `-LogLevel DEBUG` |

## 14. Developing a component

Copy `modules/Applications/_Template.ps1` to `modules/<Category>/<Name>.ps1`.
A component file **returns** one or more descriptors and has **no side effects at
load time**.

```powershell
New-WinSetupComponent -Id 'ripgrep' -Name 'ripgrep' -Category 'Development' `
    -Description 'Fast recursive search' `
    -Test {
        param($Context)
        $rg = Get-Command rg -ErrorAction SilentlyContinue
        if (-not $rg) { return New-WinSetupDetectionResult -Installed $false }
        New-WinSetupDetectionResult -Installed $true -Version ((rg --version) -split ' ')[1]
    } `
    -Install {
        param($Context)
        & winget install --id BurntSushi.ripgrep.MSVC --exact --source winget `
            --accept-package-agreements --accept-source-agreements --silent | Out-Null
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) { throw "winget: $LASTEXITCODE" }
    }
```

Contract:
* `Test` is **read-only** and returns `New-WinSetupDetectionResult`.
* `Install` / `Configure` **throw** on failure — the engine handles retry/skip/abort.
* Set `-RequiresAdmin $true` for machine-scope work; `-Critical $true` to abort the run on failure.
* Declare ordering with `-DependsOn @('other-id')`.

## 15. Testing

```powershell
Install-Module Pester -Scope CurrentUser -MinimumVersion 5.5.0   # once
pwsh -File .\tests\RunTests.ps1                                   # unit suite
```

Unit tests use `TestDrive:` and in-memory registries — they never modify the
host. Integration tests (Phase 7) are opt-in via `WINSETUP_ALLOW_INTEGRATION=1`.

A network-free sanity script also exists at `tests/RunTests.ps1 -Suite unit`.

## 16. Contribution

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Roadmap

| Phase | Scope | State |
|---|---|---|
| 1 | Core engine, CLI, logging, config, dry-run, status, journal/resume | **done** |
| 2 | Application components: pwsh, Windows Terminal, VS Code, GitHub CLI, .NET SDK, Node.js, npm, pnpm, Python, Docker Desktop | **done** |
| 3 | Azure/AWS/gcloud/Terraform/kubectl/Helm CLIs · SSH · environment variables · folders · fonts | **done** |
| 4 | WSL 2 module (features, default version, `.wslconfig`, distributions) | **done** |
| 5 | PowerShell profile · dotfiles · backups · post-install | planned |
| 6 | Full profile set | in progress (declarative files shipped) |
| 7 | Pester unit + integration + idempotency suites | in progress |
| 8 | Full documentation set | in progress |

## License

MIT — see [LICENSE](LICENSE).
