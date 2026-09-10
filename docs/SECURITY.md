# WinSetup Pro — Security

WinSetup Pro configures developer machines. That means it installs software,
edits `$PROFILE`, writes environment variables and touches `~/.ssh`. This
document states exactly what it will and will not do, and why.

## 1. Principles

1. **No remote code execution.** WinSetup Pro never downloads a script and pipes
   it into a shell. `scripts/bootstrap.ps1` only checks prerequisites and then
   runs the **local** `WinSetup.ps1` from your checkout, which you can read
   first.
2. **Official sources only.** Software is installed through `winget` against its
   default `winget` source (or the Microsoft Store where noted). No arbitrary
   `.exe`/`.msi` URLs. Fonts are pulled from the official GitHub *releases* of
   `microsoft/cascadia-code`, `JetBrains/JetBrainsMono` and `tonsky/FiraCode`.
3. **No secrets.** WinSetup Pro never asks for, prints, logs or stores a
   password, passphrase, token or API key. Git and GitHub authentication are
   delegated to Git Credential Manager, SSH or `gh auth login` (which you run
   yourself).
4. **Non-destructive by default.** Existing files are detected and backed up
   before they are changed; existing SSH keys and Git identity are never
   overwritten; existing WSL distributions are never unregistered.
5. **Least privilege.** Elevation is only requested by the components that
   genuinely need it, and each explains why. The bootstrap relaxes the
   execution policy for the **current process only**, never persistently.
6. **Reversible.** Every risky change is preceded by a timestamped copy under
   `backup/<area>/`. A run journal (`state/last-run.json`) records what was
   done.

## 2. What WinSetup Pro will NOT do

* disable or reconfigure **Windows Defender**, SmartScreen, the **firewall**, or
  UAC;
* change security policy, BitLocker, or account/credential settings;
* generate an SSH key without your say-so (interactive prompt, or the explicit
  `ssh.generateKeyUnattended` flag — which then warns that the key has no
  passphrase);
* overwrite `~/.ssh/config`, `~/.gitconfig`, `~/.wslconfig` or your `$PROFILE`
  wholesale — only its own marked block / missing entries are touched;
* run scripts fetched from the network. `postInstall.scripts` are **local**
  paths you list yourself.

## 3. Elevation

`Test-WinSetupAdmin` decides whether the session is elevated. Components that
set `RequiresAdmin` are, on a non-elevated real run, **skipped with a message**
(a dry run still previews them, flagged *needs elevation*). Components that need
admin:

| Component | Why |
|---|---|
| `wsl` | enables the WSL / Virtual Machine Platform Windows features |
| `visualstudio` | machine-wide installer |
| `postgresql`, `mysql`, `redis-cli` | register a Windows service |
| `env-vars` (only when `environment.machine` is set) | writes machine-scoped variables |
| `ssh` (only when the OpenSSH client is missing) | adds the OpenSSH Windows capability |

`pwsh`, `dotnet-sdk`, `docker-desktop`, `github-cli`, etc. are **not** gated:
winget elevates itself with a UAC prompt when needed, and an unattended failure
is handled by the error policy (retry / skip / abort) rather than a silent skip.

## 4. Bootstrapping a new machine — the risks of `irm | iex`

A one-liner like `irm https://…/install.ps1 | iex` hands the remote server
**full control of your machine** with no chance to review what runs, no
signature check, and no pinned version. WinSetup Pro deliberately does not offer
one. The supported path is:

```powershell
git clone https://github.com/<you>/WinSetup-Pro.git
cd WinSetup-Pro
#  ... read scripts\bootstrap.ps1 and WinSetup.ps1 ...
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap.ps1
```

If you must distribute a bootstrap URL internally, host a **pinned, reviewed**
copy, serve it over HTTPS from infrastructure you control, and still prefer
`git clone` so the whole tree is auditable.

## 5. Data & telemetry

WinSetup Pro has **no telemetry** and makes no network calls of its own beyond:
`winget` package installs, the connectivity probe (`TCP github.com:443`), and —
only for the `fonts` and `dotfiles` (git) components — GitHub over HTTPS. Logs
(`logs/`), the journal (`state/`) and backups (`backup/`) stay on the machine
and are git-ignored.

## 6. Reporting a vulnerability

Open a **private** security advisory on the repository (GitHub → *Security* →
*Report a vulnerability*), or email the maintainers listed in the repo. Please
describe the class of issue and impact; do not include a working exploit or a
step-by-step extraction path in a public issue.
