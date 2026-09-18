# Fresh-machine hardening: setup-ai + dotenv

- **Status:** implemented and merged to `main` (`70484cd`); `dotenv` merged to `master` (`a2a6e50`)
- **Baseline:** setup-ai `8de5094` (v3.5.2) + dirty working tree; dotenv `789f4de` + dirty working tree
- **Incident class:** a fresh machine finishes the run without a usable `pi`, and two independent
  installers abort on unauthenticated GitHub API rate limiting.
- **Related:** `odd/tasks/setup-ai-priority-hardening.md`, `buugg/issue-index.md`

## Verified root causes (source-verified in this session)

### C1 — `pi` cannot start after setup-ai registers `gentle-pi` (P0, blocks everything)

- `dotenv/pi/agent/settings.json` registers `npm:pi-tool-display`; `pi-tool-display@0.5.0`
  registers `read`/`bash`/`find`/`grep`/`ls`.
- `gentle-pi@3.2.1` bundles `extensions/quiet-tools.ts`, which registers the same built-in names,
  and `extensions/pi-pretty.ts`, which registers `read`/`bash`/`ls`/`find`/`grep` again unless
  quiet tools are enabled.
- `gentle-pi/lib/quiet-tools-config.ts`: `quietToolsEnabled()` returns `env.GENTLE_PI_QUIET_TOOLS !== "0"`.
  So the historical `GENTLE_PI_QUIET_TOOLS=0` that setup-ai persisted DISABLES quiet tools and is
  exactly what makes pi-pretty re-register the names. pi then aborts with
  `Tool "read" conflicts with .../pi-tool-display/index.ts`.
- The working tree already replaces the persisted switch
  (`remove_stale_quiet_tools_switch`) and rewrites the `npm:gentle-pi` entry in object form with
  `-extensions/quiet-tools.ts` and `-extensions/pi-pretty.ts` excluded
  (`handle_quiet_tools_conflict`). Uncommitted.
- Gap that remains: no step proves `pi` actually starts after the repair, so the module can still
  report success on a machine where pi aborts.

### C2 — `dotenv` config for a fresh machine is not in the repository (P0, new machines)

- The uncommitted `dotenv/pi/agent/settings.json` diff removes the two dead relative paths
  (`../../git/personale/pi-workflows`, `../../git/personale/pi-workflows/packages/extensions/herdr`)
  and adds `npm:pi-extensible-workflows`, `npm:gentle-pi`, `npm:gentle-engram`, `npm:pi-mcp-adapter`.
- `dotenv/setup_env.sh` `sync_pi` rsyncs `settings.json` over `~/.pi/agent`, so an entry only
  setup-ai added is dropped by the next dotenv run and setup-ai's own readback verification then fails.
- `pi-packages.txt` gains `npm:gentle-engram` plus the package-ownership comment.

### C3 — unauthenticated GitHub API 403 aborts two installers (P0/P1)

- `dotenv/setup_env.sh` `install_release()` calls
  `curl -fsSL https://api.github.com/repos/$repository/releases/latest`; under rate limiting this
  returns 403 and `curl -f` exits **22**, which is the reported
  `Return code: 22` / `failed_step=bash .../dotenv/setup_env.sh`.
- The upstream gentle-ai `scripts/install.sh` fetches the latest release the same way and prints
  `[error] GitHub API returned HTTP 403`, which fails `mod_gentle_ai`.
- Both need a redirect-based or token-aware fallback; neither may fail the module for a rate limit.

### C4 — obsolete patched-workflow-build machinery (P1, simplification)

- `PI_WORKFLOWS_FIX_REF=fix/windows-atomic-persistence` exists on no remote (checked
  `vekexasia/pi-extensible-workflows` and `darkrei08/pi-extensible-workflows` heads).
- `vekexasia/pi-extensible-workflows` `main` is `5.15.0` and already contains the
  `renameWithRetry` marker in `packages/core/src/io.ts`; npm's published version is `5.15.0`; the
  version installed on this host is `5.15.0` and its `dist/src/io.js` carries the marker.
- The fork `darkrei08/pi-extensible-workflows` is the stale one at `v3.4.2` with no marker.
- So the EPERM patch is upstream. The build-from-local-checkout path can no longer produce a
  better artifact than the published release and should be reduced to a version/marker check.

### C5 — missing lifecycle flags (P2)

No `--uninstall` and no `--dry-run`. Every module leaves state behind and there is no supported
removal path.

### C6 — Windows/PowerShell parity gaps (P2)

- The rotator Node >= 20 guard exists only in `setup-ai.sh` (`mod_rotator`), not in `setup-ai.ps1`.
- `buugg` issues #42 and #44 (WSL bash relay, menu redraw) remain open and out of the Linux matrix.

### C7 — repository hygiene (P3)

- `setup-ai`: 510 uncommitted lines across 7 files, plus untracked `3` (empty), `buugg/`, `odd/`.
- `dotenv`: 2 uncommitted files that are the C2 fix.

## Active streams (herdr)

| tab | pane | agent | tree | branch / scope |
|-----|------|-------|------|----------------|
| `w6:t2` | `w6:p3` | `core` | `/mnt/nvme-1/git/personale/setup-ai` | `fix/fresh-machine-core` — C1 + C2, container matrix |
| `w6:t3` | `w6:p4` | `dotenv` | `/mnt/nvme-1/git/personale/dotenv` | `fix/dotenv-fresh-machine` — C2 source fix + C3 |
| `w6:t4` | `w6:p5` | `simplify` | `/mnt/nvme-1/git/wt/setup-ai-persist` | `fix/workflow-patcher-obsolescence` — C4 + hygiene |
| `w6:t5` | `w6:p6` | `ux` | `/mnt/nvme-1/git/wt/setup-ai-ux` | `feat/uninstall-dry-run` — C5 + C6 |

One stream per tab, so a stream that needs a fix or a side investigation splits **its own** tab rather
than crowding a shared one:

```sh
pane=$(herdr pane split --current --direction right --cwd "$PWD" --no-focus \
  | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s).result.pane.pane_id))')
herdr agent start <unique-name> --kind pi --pane "$pane"
```

Integration order at the end: land `fix/fresh-machine-core` first, then rebase `simplify` and `ux`
onto it, then merge the `dotenv` branch independently.

## Task order

1. **C1 + C2 land as work-unit commits.** No new behavior beyond the pending repair; add the
   missing `pi` startup verification.
2. **C3 403 resilience** in `dotenv/setup_env.sh` and in `mod_gentle_ai`'s call to the upstream
   installer.
3. **C4 simplification**: delete the obsolete patched-build path and its dead refs.
4. **C5 `--uninstall` / `--dry-run`.**
5. **C6 parity**: rotator Node guard in `setup-ai.ps1`.
6. **Container matrix** for every claim the changed scripts make.
7. **C7 hygiene**: ignore/commit the stray artifacts, keep the diff reviewable.

## Acceptance criteria

- `bash -n setup-ai.sh` passes; `pwsh -NoProfile -Command "$null=[ScriptBlock]::Create((Get-Content -Raw setup-ai.ps1))"` passes.
- `node --check bin/setup-ai.mjs` passes and `MODULES` stays consistent with `MODULE_ORDER`/`$ModuleOrder`.
- A container that has `npm:pi-tool-display` in `settings.json` and then registers `npm:gentle-pi`
  starts `pi` (non-zero process start is a failure), with the `npm:gentle-pi` entry rewritten to the
  object form.
- `dotenv/setup_env.sh` survives a 403 from `api.github.com` without a non-zero exit, and a fresh
  `settings.json` still carries the four module-owned packages after `sync_pi`.
- Removing the patched-build path removes no verification: the marker check still runs against the
  installed artifact.
- Container rows recorded with host, image tag, exact command, exit code, proving output.

## Stop conditions

Stop and report instead of continuing if: a fix would require switching a user-owned checkout, if
the 403 fallback needs a credential the run does not have, if a container row would need `systemd`
or `sudo` semantics that Docker cannot provide, or if a parity change cannot be reproduced on both
shells.

## Outcome

Merged and pushed. setup-ai `main` `98d6ee4` -> `70484cd`; dotenv `master` `789f4de` -> `a2a6e50`.
All merged remote branches deleted, so `origin` carries only `main`.

| stream | branch | integrated in |
|---|---|---|
| C4 patched-build removal + hygiene | `fix/workflow-patcher-obsolescence` | `98d6ee4` |
| C1 + C2 core (repair, Pi config dir, startup check, rotator guard, base gh, skills INFO) | `fix/fresh-machine-core` | `9e1e7d0` |
| C5 + C6 lifecycle flags (`--dry-run`, `--uninstall`, ps1 rotator guard) | `feat/uninstall-dry-run` | `70484cd` |
| C2 + C3 dotenv (config, 403 resilience, regression check) | `fix/dotenv-fresh-machine` | `a2a6e50` |

Issues closed with evidence: #42, #32, #45, #46, #47. Still open and why: #37 (its fix is declared
not reproduced on Arch: the `github-cli`/`github-cli-git` conflict needs an AUR provider that
`archlinux:latest` cannot supply), #57 / #44 / #1 (Windows-native behaviour unverified), #12 / #36
(tracking and docs).

Integration notes worth keeping:

- Both streams independently introduced a top-level `remove_line_from_file`; only one
  implementation survives, from `fix/fresh-machine-core`, because Bash keeps the last definition
  and the uninstall copy would have silently changed the quiet-tools repair's contract.
- `persist_env_line` stays deleted: it is what persisted the harmful `GENTLE_PI_QUIET_TOOLS=0`
  switch. The dry-run guarantee moved to `remove_stale_quiet_tools_switch`.
- C1 is broader than first diagnosed: with quiet tools at their default, `quiet-tools.ts` itself
  collides with `pi-tool-display` on 7 names, so the object entry must exclude both of gentle-pi's
  registrants, not only disable the switch.
- `PI_OFFLINE=1 pi </dev/null` does load extensions with no model call, TTY or network, which is
  what makes the startup check real rather than static.
- The gga pre-commit hook stagnated the shared git index three times
  (`error: invalid object ... for 'docs/logs.md'`); the commits were built with plumbing and
  `gga run` was executed separately per commit. Worth its own issue.
- Residual review notes, not blocking: `bin/setup-ai.mjs` and `README.md` advertise
  `--dry-run`/`--uninstall`/`--purge` without the Windows caveat and `--purge` is dropped silently
  on win32; `Test-PiStartup` does not mirror the Bash human-log append the acceptance test asserts
  for Bash.
