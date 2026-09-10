# WinSetup Pro — Architecture

## 1. Goals that shape the design

* Add a tool without touching the core (**open/closed**).
* Run twice, change nothing the second time (**idempotent**).
* Preview before applying (**dry-run as an engine mode, not per-module `if`**).
* Survive interruption (**journal + resume**).
* Never surprise the user (**detect state, back up, ask**).
* Work on PowerShell 5.1 for bootstrap, PowerShell 7 for real use.

## 2. Layers

```
WinSetup.ps1                 Composition root. Parses the CLI, builds config +
                             context, dispatches to one command function.
        │
        ▼
modules/Core/Core.psm1       The engine, imported as a single module.
  ├── Logging.ps1            File sink + level filter.
  ├── Json.ps1               JSON → ordered-hashtable (5.1-safe).
  ├── Configuration.ps1      Layer / merge / lookup / validate / plan.
  ├── Privilege.ps1          Admin detection (never elevates).
  ├── SystemDetection.ps1    OS/winget/WSL/disk/net snapshot + diagnostics.
  ├── UI.ps1                 All console rendering (silenceable).
  ├── ComponentModel.ps1     New-WinSetupComponent / DetectionResult / schema.
  ├── Registry.ps1           Discover components, topological ordering.
  ├── Journal.ps1            Persist run state for -Resume.
  ├── ErrorHandling.ps1      Retry/Skip/Abort decision.
  └── Engine.ps1             Context + Invoke-WinSetupPlan + Get-WinSetupStatus.
        │
        ▼
modules/<Category>/*.ps1     Components. Auto-discovered. Never imported by name.
```

Rationale for a **flat file set inside one module** instead of nested
sub-modules: the core pieces are cohesive and always loaded together; one
`.psm1` keeps a single shared `$script:` scope (logger config, level table) and
one import in the entry point. Sub-folders under `modules/Core/` would add
manifest bookkeeping with no isolation benefit.

## 3. The component model

A component is a plain object (`New-WinSetupComponent`) with metadata and three
script blocks, each receiving the engine `$Context`:

| Block | Contract |
|---|---|
| `Test` | **read-only**; returns `New-WinSetupDetectionResult -Installed -Configured -Version -Summary` |
| `Install` | performs installation; **throws** on failure |
| `Configure` | idempotent configuration; **throws** on failure |

Extra metadata: `Category`, `Description`, `Tags`, `Critical`,
`RequiresAdmin`, `DependsOn`.

Why script blocks in a descriptor rather than classes or one function per verb:
PowerShell classes don't play well with module reload or with being authored in
loose files; a hashtable/descriptor is trivial to validate, discover and unit
test, and keeps a component to a single readable file.

### Discovery

`Import-WinSetupComponents` executes every `modules/**/*.ps1` that is **not**
under `Core/`, **not** `*.Tests.ps1` and does **not** start with `_`, and keeps
whatever valid descriptor(s) it returns. Adding
`modules/Applications/Terraform.ps1` is the entire integration step — no
registration, no core edit.

Component files run inside the module's session state, so their script blocks
can call engine-exported helpers (`Write-WinSetupLog`, `Get-WinSetupConfigValue`,
…) when the engine invokes them later. They must therefore be **self-contained**:
no reliance on functions defined at file scope, which disappear when the file
returns.

## 4. Configuration pipeline

```
config/default.json
      └─(merge)→ profiles/<name>.json        (-Profile)
              └─(merge)→ user file           (-ConfigFile)
                      └─(override)→ applications = <list>   (-Install)
                              └─(override)→ settings.logLevel (-LogLevel)
```

* Documents are ordered hashtables (stable key order, 5.1-compatible).
* `Merge-WinSetupConfig` deep-merges dictionaries, **unions** `applications` /
  `fonts` / `folders`, and replaces everything else.
* `Resolve-WinSetupPlan` turns the document into an ordered id list:
  `applications` plus any enabled feature block (`git`, `wsl`, `ssh`) whose id
  matches a component.

## 5. Execution — `Invoke-WinSetupPlan`

```
requested ids
  → split known / unknown        (unknown → warn + skip, never fail)
  → topological sort (DependsOn), cycle = error
  → new or resumed journal (state/last-run.json)
  → for each component:
        RequiresAdmin & !admin ......... skip (warn)
        run Test → detection
        decide:
          !Installed & has Install ................ INSTALL (+ CONFIGURE)
          Installed & !Configured & has Configure . CONFIGURE
          else .................................... SKIP
        DryRun? ................................... record intent, continue
        execute; on throw → ErrorHandling → retry | skip | abort
        re-run Test, record result + duration in journal
  → mark journal complete (unless aborted)
  → return summary { Installed, Configured, Skipped, Failed, Planned, Aborted, Results }
```

Idempotency is structural: `Install`/`Configure` are only reached when `Test`
says they are needed, and `Test` is authored to compare desired vs. current.

## 6. Dry-run

`$Context.DryRun` is set once. The engine still runs every `Test` (read-only),
prints `[DRY ] → INSTALL / CONFIGURE`, writes `state/last-dryrun.json`, and never
calls `Install`/`Configure`. Components contain **no** dry-run logic.

## 7. Error handling

* Each component runs in `try/catch`.
* `Resolve-WinSetupError` returns `retry` / `skip` / `abort`.
  * Interactive → prompt.
  * Non-interactive → `settings.errorPolicy` (`critical` default `abort`,
    `nonCritical` default `skip`).
* `abort` stops the run leaving the journal incomplete → `-Resume` picks up the
  `Pending` / `Failed` / `Planned` entries.

## 8. Logging

One timestamped file per run: `logs/YYYY-MM-DD_HHMMSS-<operation>.log`.
Levels `DEBUG < INFO < SUCCESS < WARNING < ERROR`; `-LogLevel` sets the file
threshold. The logger is a file sink only; WARNING/ERROR are also mirrored to
the console. Rich console output comes from `UI.ps1`, which is fully silenceable
so tests stay quiet. No secret is ever passed to the logger.

## 9. Safety model

| Risk | Mitigation |
|---|---|
| Remote code execution | No `irm | iex`. `bootstrap.ps1` only checks prerequisites and launches the local script. |
| Arbitrary binaries | Installs via `winget` / official sources only. |
| Credential leakage | Never requested/printed/logged/stored. Auth delegated to GCM / SSH / gh. |
| Losing config | Backup to `backup/<area>/<file>.<timestamp>` before replacing; Yes/No/Skip prompt. |
| Overwriting SSH keys / Git identity | Explicitly never done automatically. |
| Silent elevation | `Test-WinSetupAdmin`; components declare `RequiresAdmin` and are skipped (with reason) when not elevated. |
| Weakening the OS | Defender / firewall / security policy are out of scope by design. |

## 10. Extensibility (no core rewrite required)

* **New tools** → new files under `modules/<Category>/`.
* **New profiles** → JSON in `profiles/`.
* **New feature blocks** → extend `Resolve-WinSetupPlan`'s feature list.
* **GUI / TUI** → alternative front ends over the same
  `New-WinSetupContext` + `Invoke-WinSetupPlan` API.
* **Remote / multi-machine / CI** → drive `WinSetup.ps1 -NonInteractive
  -ConfigFile` and collect the journal + logs; `Invoke-WinSetupPlan` already
  returns a structured result.
* **YAML config, package cache, plugins** → add a loader that produces the same
  ordered-hashtable document; the engine is format-agnostic below `Read-*`.

## 11. Compatibility notes / known constraints

* Target PS7; keep syntax valid on 5.1 — no `??`, `?:`,
  `ConvertFrom-Json -AsHashtable`, or 3-argument `Join-Path`
  (`[IO.Path]::Combine` instead).
* An empty JSON array read via `Get-WinSetupConfigValue` collapses to `$null`
  through PowerShell's return-value unrolling; list callers wrap with `@()` and
  pass `-Default @()`.
* The CLI switch `-Profile` is an **alias** of the `-SetupProfile` parameter.
  A parameter literally named `Profile` is a trap: binding `-Profile <x>`
  overwrites the process-wide automatic `$PROFILE` string, which the
  `powershell-profile` component depends on.
* `$PROFILE`'s note properties (`CurrentUserAllHosts`, …) are usually present
  even under `pwsh -File`, but the `powershell-profile` component still derives
  the paths from the bare string and falls back to `Documents\PowerShell\` so it
  never dies on a host that strips them.
