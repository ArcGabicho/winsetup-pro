# WinSetup Pro — GUI architecture

The GUI is a **client of the existing engine**, not a second engine. It never
contains install/configure logic; every action goes through the same
`modules/Core` code the CLI uses.

```
PowerShell
   │ winsetup                       launcher\WinSetupPro  (Invoke-WinSetup / alias)
   ▼
WinSetup Pro GUI  (ui\WinSetup.Pro.UI, WPF, net10.0-windows, self-contained)
   │  per request:  pwsh -NoProfile -File scripts\winsetup-api.ps1 -Verb <verb> ...
   ▼
scripts\winsetup-api.ps1            thin transport: JSON in / JSON (+ NDJSON) out
   │  Import-Module scripts\WinSetupApi.psm1  →  Invoke-WinSetupApi
   ▼
Setup Engine (modules\Core, UNCHANGED)
   Test → Plan → Apply → Journal → Backup → Logs
```

## Launcher — `winsetup`

`launcher/WinSetupPro/` is a PowerShell module exposing `Invoke-WinSetup`
(alias `winsetup`). `scripts/install-launcher.ps1` registers it for the current
user (adds `launcher\bin` to the User PATH and an import line to `$PROFILE`; sets
`WINSETUP_HOME`). No admin, no `irm | iex`.

| Invocation | Behaviour |
|---|---|
| `winsetup` (interactive host, no flags) | opens the GUI |
| `winsetup --gui [-Profile x]` | opens the GUI, profile preselected |
| `winsetup -Profile dotnet` / `-Status` / `-Diagnose` / `-DryRun` / `-Resume` / `-NonInteractive` / `-ConfigFile` / `-Install` / `-WSL` / `-Git` / `-SSH` / `-Dotfiles` | delegated **verbatim** to `WinSetup.ps1` — the classic CLI is unchanged |
| GUI not built | falls back to `dotnet run`, then to the interactive console |

The classic CLI (`.\WinSetup.ps1 ...`) keeps working exactly as before.

## JSON contract  (`scripts/WinSetupApi.psm1` · `apiVersion: 1`)

`Invoke-WinSetupApi -Verb <verb> -Root <repo> [-Payload <obj|json>] [-Path <file>] [-EventSink <sb>]`
returns `[pscustomobject]{ ok; data; error }`. The transport script wraps it as
an envelope `{ apiVersion, verb, ok, data | error }`.

| Verb | Payload | Returns |
|---|---|---|
| `version` | — | `{ apiVersion, root }` |
| `system` | — | host snapshot (OS, PowerShell, winget, WSL, admin, disk, internet) |
| `diagnose` | — | `[ { Name, Ok, Detail } ]` |
| `profiles` | — | `[ { name, description, componentCount, components[], unknown[], compatible } ]` |
| `components` | `{ profile? }` | `[ { id, name, category, requiresAdmin, dependsOn[], selected, state, installed, configured, version, summary } ]` — `state` ∈ `Installed \| Missing \| NeedsConfiguration \| RequiresAdministrator \| Unknown` |
| `status` | — | `Get-WinSetupStatus` rows |
| `plan` | `{ profile?, components?, configFile? }` | `{ dryRun:true, changes:[{component,name,action,requiresAdmin}], counts, requiresAdmin[], backups[], preserve[], unknown[], journalPath }` |
| `apply` | `{ profile?, components?, configFile? }` | **NDJSON events** then `{ total, installed, configured, skipped, failed, aborted, journalPath, results[] }` |
| `resume` | `{ configFile? }` | as `apply`, over the pending set from `state/last-run.json` |
| `journal` | — | `null` or `{ profile, completed, counts, entries[], resumable }` |
| `export` | `{ profile?, components? }` + `-Path` | `{ written }` — writes the merged config document |
| `import` | `-Path` | `{ valid, issues[], plan[] }` |

### Events (from the engine's optional `-EventSink`)

```jsonc
{ "type": "plan_resolved",      "components": ["git", ...], "unknown": [], "total": 5, "dryRun": false }
{ "type": "component_started",  "component": "dotnet-sdk", "name": ".NET SDK", "index": 3, "total": 5 }
{ "type": "component_completed","component": "dotnet-sdk", "action": "Installed", "detail": "v10.0.100" }
{ "type": "component_failed",   "component": "postgresql", "error": "operation failed", "aborted": false }
{ "type": "run_completed",      "installed": 4, "configured": 1, "skipped": 3, "failed": 0, "aborted": false }
```

`Invoke-WinSetupPlan -EventSink <scriptblock>` is the **only** engine change —
purely additive: with no sink the behaviour is byte-for-byte identical.

## Privileges

The GUI runs **non-elevated**. `plan` reports `requiresAdmin[]`; if the user
applies a plan that needs elevation, the GUI offers *Restart as Administrator*
(relaunches its own exe via `runas`). Components that are not admin-only still
run in the non-elevated instance. `RequiresAdmin` on a component is enforced by
the engine, unchanged.

## Building the GUI

```powershell
dotnet publish ui\WinSetup.Pro.UI\WinSetup.Pro.UI.csproj -c Release -r win-x64 --self-contained
```

Self-contained → end users need no .NET install. `winsetup` finds the published
exe automatically (or set `WINSETUP_GUI_EXE`).

## What did NOT change

The engine, the component model, profiles, config schema, the journal, dry-run,
resume, backups, logging, the Pester suite, and every existing CLI command.
