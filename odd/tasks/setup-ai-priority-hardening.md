# setup-ai priority hardening — fresh-machine initialization

- **Status:** implementation plan
- **Owner:** setup-ai installer
- **Scope:** Bash/Linux/macOS parity, PowerShell parity, and a separately staged dotenv migration
- **Source baseline:** `v3.5.1` (`5bf0bf7`)
- **Incident:** Debian 13 LXC `herdr-ai`, npm 12.0.2, Node 22.23.2
- **Related migration analysis:** `/home/ema/odd/tasks/setup-ai-dotenv-migration.md`

## Goal

Make a fresh-machine `setup-ai` run predictable and rerunnable without hiding failures, while removing only proven duplicate setup work. Preserve the existing npm-root safety, exact package readbacks, install-script approvals, module order, and Bash/PowerShell parity.

## Task order

1. **[done] Fix the version readback root cause.** Change Bash `capture_cmd` so stdout is the value compared by callers and stderr remains visible/logged separately. Preserve the original exit code, `--optional` behavior, and step accounting. The Debian failure was a false mismatch: npm warnings were concatenated with expected `5.14.0`, while the installed package was actually `5.14.0`. Verified with `bash -n`, isolated stdout/stderr and optional-failure reproduction, and `git diff --check`.
2. **[done] Close the fresh-run RDD availability gap.** After `gentle-pi` is installed by the `gentle-ai` module, run the existing npm 12 approval/rebuild helper immediately in the managed Pi root and retain the final convergence pass. The call is mirrored in PowerShell. Delegated placement/parity verification passed; the local PowerShell parse check remains pending because `pwsh` is unavailable on the host.
3. **[done] Remove only redundant npm-root scaffolding.** `ensure_npm_remote_sources` / `Enable-NpmRemoteSources` already creates the package root, so the three repeated `package.json` creation blocks were removed from the workflow extension roots. Separate roots, `.npmrc` policy, exact target-path verification, and install-script approval remain. Delegated diff/syntax verification passed; `pwsh` remains unavailable locally.
4. **[done] Verify the deliverable locally and on Debian 13.** Local syntax, launcher, diff, and capture regressions passed. The authorized Debian 13 LXC ran `/root/setup-ai-test.sh --only pi-workflows --yes` successfully in 273 seconds: clean `5.14.0` readback, `modules_success=1`, `steps_failed=0`. The optional patched build was unavailable then, so the published workflow release remained active (that path was deleted afterwards, see 8); no destructive dotenv script ran.
5. **Stage dotenv migration separately.** Use the existing migration analysis to inventory and merge the target configuration with active integrations. Do not activate `vekexasia/dotenv/setup_env.sh` directly: it has destructive `rm -rf`, `rsync --delete`, overwrite, update, and unresolved local path behavior.

## Release automation task

6. **[done] Prepare one version for publication through GitHub and npm.** Updated all four version locations to `3.5.2` (`package.json`, `setup-ai.sh`, `setup-ai.ps1`, and `CHANGELOG.md`), made `.github/workflows/publish.yml` create an idempotent GitHub Release with generated notes before trusted OIDC npm publication, and documented the one-time trust setup plus the repeatable tag/dispatch/watch/verification sequence in `docs/releasing.md`. README Quick start now recommends the full unattended command and links the releasing guide. Expected evidence: four-place version parity, JSON parse, `node --check bin/setup-ai.mjs`, `bash -n setup-ai.sh`, workflow/docs inspection, and `git diff --check`; runtime publication remains pending and was not claimed or run.

7. **[done] Resolve the gga findings before release.** Removed the unsupported `SETUP_AI_SKIP_SKILLS` claim and preserved the upstream dotenv integration, split cockpit asset extraction from matching so the no-asset warning is reachable, guarded the optional `ProgramFiles(x86)` PowerShell path, restored Bun to the PowerShell report for cross-OS parity, ensured the npm project marker exists before the immediate gentle-pi approval even with `--only gentle-ai`, forwarded unattended flags for `--all` and `--only`, tightened Windows registration checks, normalized scheduled-task durations, made the dotenv override create its own parent, and logged degraded PowerShell interrupt-handler setup. Explicitly ignored all generated log extensions. Re-run `gga` and all available local checks before committing.

## Work stream C (parallel): obsolete patched-build removal

8. **[done] Remove the obsolete patched-workflow build path (C4).** Deleted `install_patched_pi_workflows`, `rollback_published_pi_workflows` and the dead `PI_WORKFLOWS_SOURCE_DIR` / `PI_WORKFLOWS_FIX_REF` / `PI_WORKFLOWS_REMOTE` variables from `setup-ai.sh`, with `Install-PatchedPiWorkflows` / `Restore-PublishedPiWorkflows` and the now-unreachable `-Expectation absent` mode of `Assert-PiPackageRegistered` removed in `setup-ai.ps1`. The premise was proven before deleting: npm's published `5.15.0` carries `renameWithRetry` in `dist/src/io.js`, `fix/windows-atomic-persistence` resolves on neither remote, and `darkrei08/pi-extensible-workflows` `main` is the stale `3.4.2` fork while `vekexasia` `main` is current. The surviving verification reads the marker from the installed `dist/src/io.js` of every root the module writes and WARNs with an actionable remedy, guarded by `npm run check:retry-marker`.

## Exact edit surfaces

- `setup-ai.sh`: `capture_cmd`, `mod_gentle_ai`, cockpit asset selection, and redundant workflow-root scaffolding only.
- `setup-ai.ps1`: matching `Mod-GentleAi` approval call, redundant workflow-root scaffolding, base-path guard, and report parity only; do not alter scalar capture unless a PowerShell reproduction proves contamination.
- `odd/tasks/setup-ai-priority-hardening.md`: update task evidence after each completed task.

No new dependency, framework, package manager, global installation helper, or broad module refactor is in scope.

## Acceptance criteria

- A command that prints a version to stdout and a warning to stderr captures only the version; warning output is still visible in the human log.
- A failed capture still returns its command status; optional captures remain skipped rather than fatal.
- After `gentle-ai` installs `gentle-pi`, npm 12 install scripts are approved/rebuilt and the package-local `.gentle-ai/*/gentle-ai*` artifact is present or the run fails with the existing actionable error.
- Re-running setup does not duplicate `package.json` or `.npmrc` policy lines.
- `bash -n setup-ai.sh` passes.
- PowerShell parses with the project-required command.
- `bin/setup-ai.mjs --list` remains consistent with `MODULE_ORDER`, `$ModuleOrder`, and `docs/modules.md`.
- The Debian 13 container reaches the workflow version check without reporting a mismatch when expected and actual versions are equal.
- No `rm -rf ~/.pi/agent`, `rsync --delete`, `pi update --extensions`, or dotenv activation is performed by the verification run.

## Stop conditions

Stop and report instead of continuing if stdout/stderr ordering changes the user-visible diagnostics, if any package root loses its project marker, if a package is verified through ancestor resolution, if Bash/PowerShell behavior diverges, if remote commands require an additional credential, or if the target dotenv path/config cannot be resolved without guessing.
