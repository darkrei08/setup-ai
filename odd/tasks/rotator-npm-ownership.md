# Cross-platform rotator npm ownership

## Goal
Add receipt-backed ownership for only the global `tuxevil-rotator` npm package, with equivalent fail-closed behavior in Bash and PowerShell. Keep recording and removal as independently reviewable work units; use about 400 authored changed lines as a planning target, not a hard cap.

## Work units
1. **#53, done: record fresh installs only.** Capture ownership only when setup-ai observes the exact global package absent before this install, installation succeeds, and exact npm root/package metadata readback verifies the new package. Uninstall inventory and removal remain unchanged and fail-closed.
2. **#58, in progress: receipt-gated inventory and removal.** Inventory and `-Yes`/`--yes` may remove only the exact package instance represented by a valid schema-v2 receipt and matching in-package marker. Reject linked/reparse package paths before marker creation. Unowned, unreadable, or surviving Windows tasks block removal and must be accurately reported without inventory side effects. Revalidate receipt/root/path/package/marker and recheck task dependency immediately before npm uninstall; remove the receipt only after confirming package and marker absence. Keep task and npm receipts independent; `-Purge` does not expand scope. Linux systemd unit ownership/order is a separate user-approved slice; do not mix its implementation into #58.

Winget and other global npm packages stay protected for later slices.

## Allowed edit surfaces for #58
setup-ai.sh
setup-ai.ps1
tests/powershell-lifecycle.ps1
tests/rotator-npm-ownership.sh
docs/modules.md


## Verification
TDD is enabled. Tests use fake package roots only.
- `bash tests/rotator-npm-ownership.sh`
- `bash tests/agent-install-parity.sh`
- `bash -n setup-ai.sh`
- `pwsh -NoProfile -File tests/powershell-lifecycle.ps1`
- `pwsh -NoProfile -Command '$null=[ScriptBlock]::Create((Get-Content -Raw setup-ai.ps1))'`
- `git diff --check`
No package manager, installer/uninstaller, Task Scheduler, containers, GGA, OCR, Alibaba/OpenCode Review, or Git delivery commands.

## Progress
- [x] Record fresh-install ownership in both shells only after absence and exact metadata readback.
- [x] Reject whitespace-only package versions consistently in Bash and PowerShell.
- [x] Run focused checks, independent review, parent spot-check, and authorized baseline comparison.
- [x] Close #58 after resolving the independent-review inventory and symlink-test gaps, and validating the additional source-review concerns.

The original #58 was reported as 375 changed lines, but no discrete current #58 baseline has been identified; do not claim a current line count. The first #58 writer added exclusive in-package identity markers, stale-reinstall checks, and a task dependency guard. A second pass added schema-v2 receipts, package-directory/package-metadata link rejection before marker writes, read-only inventory dependency checks, an immediate pre-uninstall task recheck, accurate task-query failure reporting, and an explicit PowerShell `package.json` symlink regression. Fake-state TDD RED/GREEN and the six required focused checks passed. No real npm, Task Scheduler, Windows runtime, container, GGA, or delivery command ran.

Independent verification passed `bash tests/rotator-npm-ownership.sh`, `bash tests/agent-install-parity.sh`, `bash -n setup-ai.sh`, the PowerShell lifecycle suite, the PowerShell parse check, and both staged/unstaged `git diff --check` variants. The worktree candidate contains the complete #58 behavior, while the index still contains an older partial lifecycle snapshot; do not treat the staged snapshot alone as the final #58 candidate. Read-only source mapping confirmed Linux systemd ownership/order as a separate slice, now tracked independently. Real Windows task-query behavior and package-manager operations remain unverified.

## Open boundaries
Existing packages without valid schema-v2 marker receipts remain protected. The npm marker is separate from the scheduled-task receipt. Winget and all other global npm packages remain protected until their own pre-install absence and exact installed-package fingerprints can be recorded and verified. Real Windows task-query behavior and real package-manager operations remain unverified. Linux systemd ownership/removal-order changes are tracked separately from #58 in the user-approved follow-up slice.
