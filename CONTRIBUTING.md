# Contributing to WinSetup Pro

Thanks for helping! WinSetup Pro is built as a small product, not a mega-script.
Please keep changes modular, safe and testable.

## Ground rules

1. **Never take destructive action by default.** Detect current state first;
   back up before replacing; prompt (Yes/No/Skip) in interactive mode.
2. **No secrets.** Do not request, print, log or store passwords or tokens.
3. **Idempotent.** A second run must be a no-op.
4. **Official sources only.** Prefer `winget`; never download arbitrary EXEs.
5. **The core is closed for modification.** New tools are new component files,
   not edits to `modules/Core/`.

## Project layout

```
WinSetup.ps1          Composition root / CLI
modules/Core/         The engine (loaded as one module, Core.psm1)
modules/<Category>/   Component files (auto-discovered)
config/              default.json + schema.json + example configs
profiles/            Declarative install profiles
scripts/             bootstrap / install / update / uninstall / diagnose
tests/unit/          Pester 5 unit specs (TestDrive only)
```

## Adding a component

1. Copy `modules/Applications/_Template.ps1`.
2. Implement `Test` (read-only), and `Install` / `Configure` (throw on failure).
3. Return the descriptor as the file's last statement — do not assign it.
4. No side effects at load time.
5. Add a Pester spec if the component has non-trivial detection/config logic.

### Detection result contract

`New-WinSetupDetectionResult -Installed <bool> [-Configured <bool>] [-Version <string>] [-Summary <string>]`

* `Installed = $false` → engine runs `Install` then `Configure`.
* `Installed = $true`, `Configured = $false` → engine runs `Configure` only.
* both `$true` → engine skips.

## Coding style

* PowerShell 7 target; keep parsing valid on 5.1 (no `??`, `?:`, `-AsHashtable`,
  3-argument `Join-Path`).
* Small functions, explicit parameters, `try/catch/finally`, comment-based help
  on public functions.
* Public names are `Verb-WinSetupNoun`.
* Prefer objects over formatted strings for return values.
* Comments explain *why*, not *what*.

## Tests

```powershell
pwsh -File .\tests\RunTests.ps1
```

Unit tests must not modify the host machine. Use `TestDrive:`, in-memory
registries and synthetic components.

## Commit / PR

* One logical change per PR; update `CHANGELOG.md` under *Unreleased*.
* Describe the safety implications of the change.
* Include test output.
