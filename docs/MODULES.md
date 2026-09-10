# WinSetup Pro — Writing a component

A **component** is one unit of work: install a tool, configure a subsystem,
create folders. Adding one is the entire integration step — no registration, no
edit to `modules/Core/`.

## 1. Anatomy

Create `modules/<Category>/<Name>.ps1`. The file **returns** one or more
descriptors and must have **no side effects at load time**.

```powershell
New-WinSetupComponent -Id 'ripgrep' -Name 'ripgrep' -Category 'Development' `
    -Description 'Fast recursive search (rg)' `
    -Tags @('cli', 'search') `
    -Critical $false `
    -RequiresAdmin $false `
    -DependsOn @() `
    -Test {
        param($Context)
        $v = Get-WinSetupExeVersion -Command 'rg'
        if (-not $v) { return New-WinSetupDetectionResult -Installed $false }
        New-WinSetupDetectionResult -Installed $true -Version $v -Summary "rg $v"
    } `
    -Install {
        param($Context)
        Install-WinSetupWingetPackage -Id 'BurntSushi.ripgrep.MSVC' -VerifyCommand 'rg'
    } `
    -Configure {
        param($Context)
        # optional; idempotent configuration only
    }
```

| Field | Meaning |
|---|---|
| `Id` | lowercase, stable, unique — used in profiles, `-Install`, the journal |
| `Category` | free text for `-List` grouping (`Development`, `Cloud`, `Database`, `Environment`, `Customization`) — **not** tied to the folder |
| `Critical` | `$true` → a failure aborts the whole run (default: non-critical → skip) |
| `RequiresAdmin` | `$true` → skipped on a non-elevated real run (previewed in dry-run) |
| `DependsOn` | ids that must be ordered before this one (topological sort; cycles error) |

## 2. Lifecycle

```
                 ┌─────────────┐
   plan id  ───▶ │    Test     │  read-only. returns New-WinSetupDetectionResult
                 └──────┬──────┘
                        │
        ┌───────────────┼────────────────────────────┐
        ▼               ▼                             ▼
  not Installed    Installed &&                 Installed &&
   && has Install   !Configured && has Configure   Configured
        │               │                             │
        ▼               ▼                             ▼
   Install → Configure   Configure only            SKIP
        │               │
        └──────┬────────┘
               ▼
        Test again (record version) ──▶ journal entry
```

* **Dry-run**: the engine runs `Test` only, prints the intended
  `INSTALL` / `CONFIGURE`, and stops. Your blocks are never called — do **not**
  add your own dry-run branch.
* On a thrown error the engine asks `Resolve-WinSetupError` → `retry` / `skip` /
  `abort` (interactive prompt, or `settings.errorPolicy` when non-interactive).

## 3. The detection result

`New-WinSetupDetectionResult -Installed <bool> [-Configured <bool>] [-Version <string>] [-Summary <string>]`

| `Installed` | `Configured` | engine does |
|---|---|---|
| `$false` | — | `Install` then `Configure` |
| `$true` | `$false` | `Configure` |
| `$true` | `$true` | nothing (SKIP) |

For a pure "software" component, `Configured` can stay at its default `$true`.
For a "config task" component (folders, env-vars, profile) return
`Installed = $true` always and drive the work through `Configured`.

## 4. Rules

1. **`Test` is read-only.** No installs, no file writes, no registry writes. It
   runs on every `-Status` and twice per real action.
2. **`Install` / `Configure` throw on failure.** Don't swallow errors and return
   quietly — the engine's retry/skip/abort depends on the throw.
3. **Idempotent.** Compare desired vs. current before writing. A second run must
   be a no-op.
4. **Self-contained.** A script block may use engine-exported helpers, `$Context`
   and its own local variables — never a function defined at file scope (it is
   gone by the time the engine calls the block). Duplicate a few lines instead,
   or capture with `.GetNewClosure()`.
5. **Non-destructive.** Back up before replacing (`Backup-WinSetupFile`); never
   overwrite an existing SSH key, Git identity, or a user's own `$PROFILE`
   content; prompt with `Confirm-WinSetupAction` in interactive mode.
6. **No secrets.** Ever.

## 5. Helpers available to a block

| Helper | Use |
|---|---|
| `Install-WinSetupWingetPackage -Id <x> [-Scope user] [-VerifyCommand] [-VerifyPath]` | silent, idempotent winget install; verifies presence on a non-zero exit and hints elevation otherwise |
| `Get-WinSetupExeVersion -Command <x> [-VersionArgs] [-Pattern]` | read-only version probe (returns `$null` if missing) |
| `Update-WinSetupSessionPath` | refresh `$env:Path` from the registry after an install |
| `Get-WinSetupConfigValue -Config $Context.Config -Path 'a.b.c' -Default <x>` | read a dotted config path |
| `Backup-WinSetupFile -Context $Context -Path <file> -Category <name>` | timestamped copy under `backup/<name>/` |
| `Confirm-WinSetupAction -Question <q> [-DefaultYes]` | Yes/No/Skip; returns `$DefaultYes` when non-interactive |
| `Write-WinSetupLog -Level INFO|DEBUG|SUCCESS|WARNING|ERROR -Module <id> -Message <m>` | structured log line |
| `Invoke-WinSetupWsl` / `Get-WinSetupWslInfo` / `Format-WinSetupWslConfig` | WSL specifics |
| `Assert-WinSetupAdmin -Reason <why>` | throw a clear error if not elevated |

`$Context` carries: `.Config`, `.DryRun`, `.Interactive`, `.IsAdmin`,
`.System` (OS / winget / arch snapshot), `.Paths` (`Root`, `Backup`, `State`,
`Templates`, …), `.Registry`.

## 6. Making it part of a profile

Add the `Id` to `applications` in `profiles/<name>.json`, or expose a
feature block. Feature blocks that `Resolve-WinSetupPlan` already understands:
`git.enabled`, `wsl.enabled`, `ssh.enabled`, a non-empty `folders` / `fonts`,
a non-empty `environment.{user,machine,path}`, `powershellProfile.enabled`, a
`dotfiles.{path,repository,source}`, a non-empty `postInstall.scripts`.

## 7. Testing a component

Add a spec under `tests/unit/`. Never touch the real machine — build an
in-memory registry and an isolated `$Context`:

```powershell
BeforeAll {
    $root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Import-Module (Join-Path $root 'modules\Core\Core.psm1') -Force
    Initialize-WinSetupLog -Directory (Join-Path $TestDrive 'logs') -Console $false | Out-Null
    $registry = Import-WinSetupComponents -Path (Join-Path $root 'modules')
}

It 'ripgrep Test is read-only and well-formed' {
    $ctx = New-WinSetupContext -Root $TestDrive -Config (Get-WinSetupConfig -Root $root) `
        -Interactive $false -Registry $registry
    $r = & $registry['ripgrep'].Test $ctx
    $r.Installed | Should -BeOfType ([bool])
}
```

Run: `pwsh -File .\tests\RunTests.ps1`.

## 8. Common pitfalls

* **`$PROFILE` collision** — never name a script parameter `Profile`; binding a
  value to it clobbers the process-wide automatic `$PROFILE`.
* **Empty-array config** — `Get-WinSetupConfigValue` returns `$null` for an
  empty JSON array (PowerShell unrolls it). Wrap call sites with `@()` and pass
  `-Default @()`.
* **winget UTF / exit codes** — don't parse `winget list`; detect via the real
  command or an install path. `Install-WinSetupWingetPackage` already tolerates
  "already installed" exit codes.
* **`wsl.exe` output** — UTF-16 and localised; always go through
  `Invoke-WinSetupWsl`.
* **stderr versions** — `java -version`, `ssh -V` print to stderr;
  `Get-WinSetupExeVersion` uses `2>$null`, so handle those inline with `2>&1`.
