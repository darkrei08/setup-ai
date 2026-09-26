# Setup-AI Windows lifecycle ownership

## Goal
Finish the authorized setup-ai #98 lifecycle work on `feat/setup-ai-98-windows-lifecycle`, ensuring uninstall removes only resources setup-ai can prove it created and preserving the primary worktree.

## Scope and constraints
- Work only in `/tmp/setup-ai-98-lifecycle`; leave `/root/git/personale/setup-ai` and its staged/unstaged changes untouched.
- Preserve cross-platform behavior where Bash and PowerShell expose the same module behavior. Keep receipts separate for npm packages, Pi registrations, scheduled tasks, and other resources.
- Never claim a pre-existing or upgraded resource as setup-ai-owned. Preserve shared Pi roots, `auth.json`, sessions, user settings, credentials, and unsupported vendor-managed resources. Existing explicit `--purge` behavior is not widened.
- TDD is enabled per the existing setup-ai task configuration. Use fake package/resource state only for focused tests; do not run real installers, uninstallers, package managers, or Task Scheduler during unit work.
- Use about 400 authored changed lines as a planning target, not a hard cap. Split only at a coherent behavior boundary; never omit tests or code-golf to fit.
- No push, PR, merge, issue closure, release, tag, workflow dispatch, or publication. User authorized work-unit commits only when the candidate is stable; every commit uses `GGA_PROVIDER=codex gga run`. Do not use OpenCode/Alibaba review.
- Receipt-driven development is enabled globally. The native review facade currently fails before lineage creation because the verified package-local binary is missing. Do not modify installed gentle-pi assets without user authorization; after implementation, try native ASSESS and follow its risk-gated fallback if unavailable.

## Work units
1. **#58, in progress: Rotator npm receipt-backed inventory/removal.** Use an exclusive per-install marker so an old receipt cannot authorize removal of a later same-name/same-version reinstall. Reject package-directory symlinks/reparse points before writing the marker. Inventory must report task dependency blockers; an unowned, unreadable, or surviving Windows task blocks npm removal. Recheck task state immediately before npm uninstall. Verify schema migration, revalidation, failure preservation, inventory/dry-run non-mutation, Bash/PowerShell parity, and PowerShell assertion syntax.
2. **New slice, pending: Linux systemd unit ownership and removal order (user-approved).** Record ownership only for a fresh unit created at the exact path; never overwrite or remove a pre-existing/modified unit. Remove a matching receipt-owned unit before npm package removal, and preserve the package if the service remains or cannot be safely stopped/removed. Cover with fake `systemctl` tests.
3. **#54, pending: Pi package/resource cleanup.** Record ownership only for exact registrations setup-ai creates after proving absence. Remove only those registrations; preserve shared roots, settings, auth, sessions, and package data. Keep Bash/PowerShell semantics aligned.
4. **#55, in progress: Remaining Windows-owned artifacts.** Receipt-backed removal of the setup-ai-written `OPENCODE_PI_BIN` user environment value exists and is covered by `tests/powershell-lifecycle.ps1`. No PowerShell profile-block remover exists, and no complete audit of the remaining Windows artifacts is recorded yet.
5. **#57, pending: Remaining package managers.** Add per-resource ownership only for fresh global npm/winget installs. Never claim pre-installed packages or upgrades; protect vendor-managed/ambiguous resources.
6. **#48, pending: Final verification, review, and commits.** Run focused checks and the applicable platform matrix; record unavailable Windows/macOS runtime honestly. Run GGA with Codex, then Codex-only review on the exact work-unit candidates. Commit only stable work units with Conventional Commit messages. No delivery beyond local commits is authorized.

## Verification plan
- #58 focused checks from `odd/tasks/rotator-npm-ownership.md`: `bash tests/rotator-npm-ownership.sh`, `bash tests/agent-install-parity.sh`, `bash -n setup-ai.sh`, `pwsh -NoProfile -File tests/powershell-lifecycle.ps1`, PowerShell parse check, and `git diff --check`.
- New Linux systemd slice: `bash tests/rotator-systemd-ownership.sh`, `bash -n setup-ai.sh`, and `git diff --check`; fake `systemctl` only.
- Add test-first regressions for same-version reinstallation and package/task dependency; use fake state only.
- Each later work unit adds a focused fake-state regression before implementation, then runs the existing parity and syntax checks.
- Final matrix follows `container-test-matrix`: supported Linux distribution families and derivatives, both Bash and PowerShell implementations, Node/npm/Bun/launcher entrypoints as applicable, plus Windows/macOS runtime where an appropriate host exists. Record host/image, exact command, exit code, proving output, and unavailable rows.
- Runtime boundary for simulated package/resource tests: `N/A` (fakes only); no live package manager or Task Scheduler operation is authorized in focused tests.

## Current evidence and progress
- Candidate worktree is `/tmp/setup-ai-98-lifecycle`, branch `feat/setup-ai-98-windows-lifecycle`, based on `5495227`. It already contains staged and unstaged lifecycle changes from completed work units; do not discard or overwrite them.
- The prior read-only analysis confirmed #58's original receipt matched global root, path, package name, and version, but not a distinct installation instance. The first writer pass added exclusive in-package markers, stale-reinstall tests, and a Windows task dependency guard. The second pass added schema-v2 receipts, pre-marker path checks, read-only task-aware inventory, and a final task recheck before npm uninstall.
- Writer TDD RED/GREEN evidence and all six focused checks passed; independent `gentle-ai-verify` repeated them successfully. The PowerShell parse check passed with single-quoted shell input. Real npm, Task Scheduler, Windows, and container checks were not run.
- Independent verification found two remaining gaps: task inventory may mislabel a task whose removal/query fails as missing or unmatched, and PowerShell lacks an explicit symlinked `package.json` regression. These remain open.
- Read-only source mapping confirmed Bash removes the global npm package before attempting systemd-unit removal, and the unit removal has no ownership receipt; a surviving/unowned unit can be deleted or left pointing to an already-removed package. The user approved a separate Linux systemd ownership/removal-order slice; keep its changes distinct from #58.
- A Claude Opus 5.5 workflow review and source mapper also identified test-log/counter gaps, stale-receipt/orphan-marker behavior, and reliance on a specific Windows missing-task error ID. Treat these as scoped follow-ups only after verifying each against source/tests. Real Windows behavior remains unverified.
- User-confirmed original #58 size is 375 changed lines, but no discrete current #58 baseline is available. Do not claim a current count or force artificial splitting; preserve the existing mixed staged/unstaged work.
- The task notes `odd/tasks/rotator-npm-ownership.md` and `odd/tasks/rotator-task-hardening.md` are historical work-unit notes; update the #58 note when its outcome changes.
- Pi workflow read-only mapping initially resolved the primary checkout instead of this candidate. That result was discarded; a scoped explorer subsequently confirmed the candidate worktree before the current writer pass.

## Progress
- [x] #58 Rotator npm receipt identity and dependency-safe removal.
- [x] New Linux systemd unit ownership and safe removal order.
- [x] #54 Pi registration/resource ownership.
- [ ] #55 Remaining Windows artifacts.
- [ ] #57 Remaining global npm/winget ownership.
- [ ] #48 Final verification, GGA/Codex review, and stable work-unit commits.

## Next step
Consolidate the complete worktree candidate without treating the older partial index as authoritative, then implement #57 remaining package-manager ownership slices before final verification.