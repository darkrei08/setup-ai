# Linux systemd unit ownership and safe removal

## Goal
Make the optional Rotator's systemd user unit removable only when setup-ai can prove it created the exact current unit, and ensure the package is not removed while a service dependency remains.

## Scope
- Change only `setup-ai.sh`, `tests/rotator-systemd-ownership.sh`, and `docs/modules.md`.
- This is a separate user-approved slice after #58; do not mix its implementation into #58.
- Keep ownership evidence independent from npm package and Windows scheduled-task receipts.
- Do not run a real npm package manager, systemd command, service, container, GGA, or delivery command. All tests use temporary paths and fake executables.
- TDD is enabled by task configuration. Add focused regression first, observe RED, implement, observe GREEN, refactor.
- Use about 400 authored changed lines as a planning target, not a hard cap; do not omit tests or split artificial code.

## Ownership rules
- The canonical unit path is `${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/tuxevil-rotator.service`.
- Setup-ai may record ownership only after proving the exact unit path was absent before this run, creating it exclusively, and reading back the exact content it wrote.
- Never overwrite, claim, or remove an existing, unreceipted, unreadable, or modified unit. A receipt must be separate from the unit and independent from npm/task receipts.
- Inventory and dry-run are read-only. `--yes` may remove only a receipt-backed exact unit; if stopping/disabling/removing it fails, the unit remains, its receipt remains, and npm package removal is blocked.
- Remove a verified unit and confirm it is absent before removing the matching npm package. Never let a unit or enabled dependency remain pointing at a removed package.
- Preserve unrelated systemd units, wants symlinks, user configuration, package data, and credentials. `--purge` does not broaden scope.

## Verification
- `bash tests/rotator-systemd-ownership.sh`
- `bash tests/rotator-npm-ownership.sh`
- `bash -n setup-ai.sh`
- `git diff --check`
- Use fake `systemctl`/npm programs and temporary `HOME`, `XDG_CONFIG_HOME`, and `XDG_STATE_HOME`; confirm the tests do not invoke host systemd or npm.

## Regression cases
- Fresh absent unit is created exclusively and gets a separate receipt after exact readback.
- Existing unit, symlink, or modified unit is preserved and never claimed.
- Receipt write failure does not leave an unowned service unit or uninstallable dependency.
- Inventory/dry-run causes no unit, receipt, enable/disable, or npm-uninstall mutation.
- Matching receipt-owned unit is stopped/disabled, removed, verified absent, then the package may be removed.
- Unowned/mismatched unit, failed systemctl operation, or surviving unit blocks npm removal and preserves relevant evidence.
- `--purge` does not expand the selected ownership scope.

## Progress
- [x] Add fake-systemd regression tests and observe RED.
- [x] Implement fresh-only unit ownership and removal-before-package ordering.
- [x] Run focused checks, review diff, and record any unavailable host-level verification.

## Evidence
The fake-state TDD regression first failed because fresh unit creation published no receipt, then passed after implementation. The final focused checks passed: `bash tests/rotator-systemd-ownership.sh`, `bash tests/rotator-npm-ownership.sh`, `bash -n setup-ai.sh`, and both staged/unstaged `git diff --check` variants. The implementation creates only an absent exact unit, records a separate SHA-256 receipt after exclusive read-back, preserves existing/symlinked/modified units, distinguishes protected inventory, and clears the unit and receipt before allowing matching npm removal. Failed systemctl, removal, receipt, or ownership checks preserve evidence and block npm cleanup. Real systemd, npm, Windows, and container behavior remain unverified; the candidate's index still contains older partial staged lifecycle content, so the complete worktree must be consolidated before delivery.
