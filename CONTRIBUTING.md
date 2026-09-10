# Contributing to WinSetup Pro

Thanks for helping! WinSetup Pro is built as a small product, not a mega-script.
Keep changes modular, safe and testable.

## Ground rules

1. **Never take destructive action by default.** Detect current state first;
   back up before replacing (`Backup-WinSetupFile`); prompt Yes/No/Skip
   (`Confirm-WinSetupAction`) in interactive mode.
2. **No secrets.** Do not request, print, log or store passwords or tokens.
3. **Idempotent.** A second run must be a no-op.
4. **Official sources only.** Prefer `winget`; never download arbitrary EXEs.
5. **The core is closed for modification.** New tools are new component files,
   not edits to `modules/Core/`.

## Project layout

```
WinSetup.ps1          Composition root / CLI
modules/Core/         The engine (loaded as one module, Core.psm1)
modules/<name>/       Component files, auto-discovered (Category is a field, not the folder)
config/              default.json + schema.json + example configs
profiles/            Declarative install profiles
scripts/             bootstrap / install / update / uninstall / diagnose
templates/powershell/ PowerShell profile fragments
tests/unit/          Pester unit specs (TestDrive only)
tests/integration/   Real-install specs, tagged 'Integration', opt-in
docs/               Architecture · Security · Modules · Troubleshooting
```

## Adding a component

See **[docs/MODULES.md](docs/MODULES.md)** for the full contract, the lifecycle,
the helper reference and common pitfalls.

1. Copy `modules/Applications/_Template.ps1`.
2. Implement `Test` (read-only), and `Install` / `Configure` (throw on failure).
3. Return the descriptor as the file's last statement — do not assign it.
4. No side effects at load time.
5. Add a Pester spec if detection/config is non-trivial.
6. If a profile should use it, add the id to `profiles/<name>.json` and mention
   it in the profile table in `README.md` §5.

## Coding style

* PowerShell 7 target; keep parsing valid on 5.1 — no `??`, `?:`,
  `ConvertFrom-Json -AsHashtable`, or 3-argument `Join-Path`
  (`[IO.Path]::Combine` instead).
* Small functions, explicit parameters, `try/catch/finally`, comment-based help
  on public functions.
* Public names are `Verb-WinSetupNoun`.
* Prefer objects over formatted strings for return values.
* Comments explain *why*, not *what*.
* Never name a parameter `Profile` — binding `-Profile <x>` overwrites the
  process-wide automatic `$PROFILE`. Use an alias (see `WinSetup.ps1`).

## Tests

```powershell
pwsh -File .\tests\RunTests.ps1            # unit (host-safe)
pwsh -File .\tests\RunTests.ps1 -Suite all # + integration (self-skips without opt-in)
```

Unit tests must not modify the host. Use `TestDrive:`, in-memory registries and
synthetic components; restore any `$env:*` / `$global:*` redirection in
`finally`.

## Docs

* One topic per file; connected prose, not scratch notes.
* Update `CHANGELOG.md` under the current heading for every user-visible change.
* Keep `README.md` §5 (profile table) and the roadmap in sync with reality.

## Commit / PR

* One logical change per PR.
* Describe the safety implications of the change.
* Include test output (`RunTests.ps1` summary line).
* CI (`.github/workflows/ci.yml`) must be green: syntax check + unit suite.

## Releases

Versions follow [SemVer](https://semver.org/). To cut a release: move the
`CHANGELOG.md` `[Unreleased]` entries under a dated `[x.y.z]` heading, then
`git tag vX.Y.Z`. Phases 1–8 constitute **0.1.0**.
