# Pi registration and resource ownership

## Goal
Record and remove only Pi package registrations setup-ai can prove it created, while preserving shared Pi roots, settings, auth, sessions, package data, and unowned legacy registrations across Bash and PowerShell.

## Allowed edit surfaces
setup-ai.sh
setup-ai.ps1
tests/pi-ownership.sh
tests/powershell-lifecycle.ps1
docs/modules.md
odd/tasks/pi-ownership.md

## Ownership rules
- Use a separate receipt from npm, systemd, and Windows task receipts.
- Record a package/resource only after exact identity is absent before the current `pi install` call, the call succeeds, and Pi settings readback proves the exact identity.
- Never claim a pre-existing, upgraded, ambiguous, malformed, or shared registration.
- Inventory and dry-run are read-only. Removal requires a matching receipt and exact current settings identity; a failed read/write/removal preserves the receipt and registration.
- Never delete Pi roots, `settings.json`, `auth.json`, sessions, package data, or unrelated registrations. `--purge` does not widen this scope.

## Verification
- Add fake `pi` state and observe RED before implementation, then GREEN.
- `bash tests/pi-ownership.sh`
- `bash tests/rotator-npm-ownership.sh`
- `bash -n setup-ai.sh`
- `pwsh -NoProfile -File tests/powershell-lifecycle.ps1`
- `pwsh -NoProfile -Command '$null=[ScriptBlock]::Create((Get-Content -Raw setup-ai.ps1))'`
- `git diff --check` and `git diff --cached --check`
- No real pi, npm, installers, containers, GGA, or delivery commands.

## Progress
- [x] Add fake Bash/PowerShell registration ownership regressions and observe RED.
- [x] Implement receipt-backed fresh-only registration capture and safe removal parity.
- [x] Run independent verification and record unavailable host/runtime checks.

## Evidence
- RED: the new ownership regressions failed before implementation because the shared Pi ownership helpers were absent.
- GREEN: `bash tests/pi-ownership.sh` and `pwsh -NoProfile -File tests/powershell-lifecycle.ps1` passed using fake Pi/npm commands.
- `bash tests/rotator-npm-ownership.sh`, `bash -n setup-ai.sh`, PowerShell parse, `git diff --check`, and `git diff --cached --check` passed.
- Native Windows and macOS rows were unavailable on this Linux host. Container runs, real Pi/npm commands, installers, and delivery commands were explicitly excluded.
