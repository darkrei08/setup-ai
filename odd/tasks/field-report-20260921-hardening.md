# field report 2026-09-21 hardening — setup-ai + vekexasia extensions

- **Status:** in progress
- **Owner:** setup-ai installer, plus fork-and-PR work on vekexasia repositories
- **Scope:** Bash/PowerShell parity for setup-ai; read-only recon plus fork/PR for the vekexasia extensions
- **Source baseline:** `v3.6.5` (`43ad9fa`), branch `main`, clean tree
- **Source runs:**
  - `20260921T092714Z` — Linux (root, Debian container): `failed`, `modules_success=14;modules_failed=1`, `failed_step=binary_missing: gentle-ai CLI not found on PATH after install`
  - `20260921T093916Z` — same host: `failed`, `modules_failed=1`, `failed_step=gentle-ai install --scope global --agents pi,codex,opencode`, root cause `download engram binary: fetch latest engram version: GitHub API returned HTTP 403`
  - Windows run in the same report: `winget` exit `0x8A150014` (-1978335212) logged twice as `step_failed_optional` WARN during healthy `base` steps
- **Related:** issue #36 (field-report protocol), issue #60 (engram 403 token forwarding), issue #61 (quiet-tools repair ordering)

## Decisions taken before the first write

| Decision | Value |
|---|---|
| Repositories in scope | `darkrei08/setup-ai` (admin, merge allowed) + recon of `vekexasia/pi-codex-image` and `vekexasia/pi-high-availability` |
| npm publishing | Out of scope for this session. Releases are tag + `workflow_dispatch` driven and use npm trusted publishing (OIDC), so no local `npm login` is involved |
| Tracking | One issue per defect, one branch and one PR per work unit |
| Orchestration | Pi workflow with role/model aliases for read-only recon and implementation, plus Herdr panes for the long-running container verification |
| Write concurrency | Single-threaded. No parallel writers in the same worktree |

## Hard constraints discovered in recon

- The `darkrei08` account has `push: false` on both vekexasia repositories. There the deliverable is a
  fork plus a pull request against upstream; merging is the upstream maintainer's decision.
- `.gga` exists but no git hook is installed in this clone (`.git/hooks` holds samples only), so
  `gga run` is not automatically invoked by `git commit` here.
- `.github/workflows/publish.yml` is `workflow_dispatch` only: no CI runs on pull requests.

## Defects and features

### A. gentle-ai binary is not found after a successful install (P0, install-blocking)

- Location: `setup-ai.sh` `mod_gentle_ai` (`:2246` PATH export, `:2260` pre-install check,
  `:2277`-`:2283` post-install verification); `setup-ai.ps1` `Mod-GentleAi` (`:1565`-`:1571`).
- Mechanism: the module exports `${HOME}/.local/bin` and `${HOME}/go/bin` but not the Linux vendor
  target `/usr/local/bin`, which is exactly where `Gentleman-Programming/gentle-ai`'s `install.sh`
  puts the binary. The vendor installer prints `/usr/local/bin is not in your PATH` and exits 0, so
  `command -v gentle-ai` fails afterwards and the module reports `binary_missing` for an install
  that succeeded.
- Acceptance: after the vendor installer returns, the module resolves the binary from the known
  install directories and succeeds when the binary is present anywhere in them; the directory is on
  `PATH` for every later `gentle-ai` call in the same process; Bash and PowerShell behave the same.

### B. Configurator fails the whole run on a transient GitHub API 403 (P1)

- Location: `setup-ai.sh` `mod_gentle_ai` (`:2310`-`:2346`); `setup-ai.ps1` `Mod-GentleAi`
  (configurator invocation and `configurator_failed`).
- Mechanism: `gentle-ai install` downloads the engram binary through the anonymous GitHub API
  (60 requests/hour/IP). Issue #60 forwarded `GITHUB_TOKEN`/`GH_TOKEN`, but a single 403 still
  aborts the configurator, which the module treats as fatal. The run then ends `failed` with all
  agent/MCP wiring incomplete.
- Acceptance: a rate-limit signature is retried a bounded number of times with backoff; a persistent
  failure still fails the module (no silent downgrade) with a message that names the quota and the
  remedy; no more than one retry sequence per run.

### C. Expected winget probe exits are logged as failures (P2, log noise)

- Location: `setup-ai.ps1` `Test-WingetInstalled` (`:463`, `-ExpectedExitCodes -1978335212`), and the
  failure path of `Invoke-Step` (`:445`-`:450`).
- Mechanism: `0x8A150014` means "no installed package matches", already declared expected, but the
  optional branch logs `step_failed_optional` at WARN. Two of the first eight steps of a healthy
  Windows run therefore look like failures, and the run summary counts them as `skipped` without
  saying why.
- Acceptance: an expected exit code is logged at INFO with an event that names it; the `skipped`
  accounting is unchanged; a genuinely unexpected optional failure still logs WARN.

### D. Compact, AI-optimized JSONL schema (P3, feature)

- Location: `setup-ai.sh` `json_log` (`:197`-`:222`); `setup-ai.ps1` `Write-Log` (`:167`-`:183`);
  `docs/logs.md`.
- Change: short stable keys (`ts`, `lvl`, `ph`, `ev`, `msg`, `rc`, `rid`, `pid`) plus a structured
  `err` object for failures, keeping `meta` and `summary`. Both writers emit the same keys in the
  same order.
- Acceptance: both writers emit the new keys; `docs/logs.md` and its copy-paste reader match; the
  `run_summary` record and the engineering report still parse; a sample `.jsonl` validates as one
  JSON object per line.

### E. Claude Code and Gemini CLI are configured but never installed (open question)

- Evidence: no `claude`/`gemini` entry exists in `MODULE_ORDER`, `$ModuleOrder`, or the launcher
  `MODULES`; `docs/modules.md:62` and `.gga` note that those agents are detected and configured
  (`npx skills add`) only when already present.
- Status: product decision required. Tracked as an issue; no code change until the maintainer decides
  whether the installer should install them.

## Task order and outcome

1. [done] Open one issue per defect. Filed 78 (P0 PATH), 79 (P1 403), 80 (P2 winget), 81 (P3 JSONL),
   82 (question, claude/gemini), and later 83 (Windows resolver probe), 84 (PowerShell logging divergence),
   85 (developIssues never loaded).
2. [done] A, resolve the gentle-ai binary through known install dirs. `6b9417d` + `d1b34f8`,
   PR #86, merged as `369a11b`.
3. [done] B, bounded retry plus actionable failure for the GitHub API rate limit. Six commits
   (`0cef2dc`, `f69badf`, `5ad25c3`, `bba11af`, `52ea0d2`, `f26079c`), PR #87, merged as `fc41c70`.
   Five corrective rounds, each driven by a blocking review finding.
4. [rejected] C, the winget WARN. **Not merged.** Verified that the defect was already fixed by
   `ac5947a` on 2026-09-12, which is an ancestor of `main`, and that the proposed change would have
   introduced a WARN `step_result` where the baseline had none and moved the counter from verified to
   skipped. Issue #80 closed as not planned with the full analysis. My own error: the issue attributed
   the field run to 3.6.5 (`43ad9fa`, 2026-09-19) while the log itself says `"ver":"3.2.0"` and is dated
   2026-09-10.
5. [done] D, compact JSONL schema. Three commits (`218e4d5`, `39f9319`, `fbdad2e`), PR #88,
   merged as `5d94770`. Two corrective rounds removed a fabricated `err` classification that
   contradicted the documentation written in the same diff.
6. [done] Local gates on the merged `main`: `bash -n setup-ai.sh`, `node --check bin/setup-ai.mjs`,
   `node bin/setup-ai.mjs --list`, `npm run check:retry-marker`, `git diff --check`, and all four test
   scripts including `tests/pi-startup-check.sh`.
7. [done, with a repair] One PR per work unit plus merge. Merging the three approved branches left two
   tests red on `main` although each passed on its own branch, and no textual conflict showed it:
   `tests/gentle-ai-cli-resolution.sh` died on `STEP_FAILED: unbound variable` because the extracted
   `mod_gentle_ai` reads run-summary state the sandbox did not provide, and
   `tests/configurator-retry-check.sh` asserted on the pre-rename JSONL keys `"event"` and `"message"`.
   Repaired in `dd520e7`, PR #89, merged as `1a11227`, and re-proven by mutation for both.
8. [done] vekexasia recon and delivery: PR #1 on `pi-codex-image`, PR #36 and issue #37 on
   `pi-high-availability`, all verified open. `darkrei08` has no push access upstream, so the merge is
   the maintainer's decision.
9. [pending, needs a decision] E, the Claude Code and Gemini CLI modules. Tracked as #82 with the
   recommendation to document the "configured, not installed" boundary rather than add modules.

## Outcome

- `main` at `1a11227`, containing PRs #86, #87, #88 and the integration repair #89.
- Issues #78, #79 and #81 closed by their merge; #80 closed as already fixed; #82, #83, #84 and #85 open.
- Two defects were found only because the review was adversarial, and both were introduced by the fixes
  themselves: the false quota diagnosis in the TTY branch, and the recovered-retry step accounting that
  named a successful step as the failing one. A third class, an `err` object claiming a classification
  no caller supplied, was found by the same route.
- A fourth defect was found only by the post-merge verification: the integration break described in item 7.

## Verification that could not run on this host

- The PowerShell parse check: `pwsh` is absent. Declared pending in every pull request.
- The container matrix: **Docker is not installed** on this host (`dockerd` is absent), so neither the
  per-distribution runs nor the `mcr.microsoft.com/powershell` parse check could be executed.
- The live winget path: not runnable on a Linux host, not even in a container.
- The live GitHub API 403 and the real 15s/45s waits: exercised against fixtures and stubs only.

## Related work outside this repository

- vekexasia: PR #1, PR #36, issue #37.
- dotenv: `19d95ad`, `1a95ac8`, `e6a414e`, `d9315f3` on `master` (default model, monokai-pro, the reviewer
  alias moved to `anthropic/claude-opus-5:high`, and the wrong Fable diagnosis corrected in `MODELS.md`).
  Then `f33e54d` delivered as PR #21, merged as `eba8a6b`.
- A configuration gap found while resolving an unrelated open review: `/root/.pi/agent/subagents.json` did
  not exist and the four `review-*` agent profiles declare no model, so the Pi host relay refused to
  launch any reviewer with `reviewer-config-invalid`. The file now carries explicit `model_profiles` for
  the four lenses and a `default_model` for the other subagents.
- The `gga` commit gate on this machine is fail-open: it exits 0 even when its provider fails with
  `Unexpected server error`, so the pre-commit hook blocks nothing and reviews nothing.

## Exact edit surfaces

- `setup-ai.sh`: `mod_gentle_ai`, `json_log`, and the helpers those two call.
- `setup-ai.ps1`: `Mod-GentleAi`, `Write-Log`, `Test-WingetInstalled`, `Invoke-Step`'s failure path,
  and the helpers those call.
- `docs/logs.md`, `CHANGELOG.md`, `odd/tasks/field-report-20260921-hardening.md`.

No new dependency, framework, package manager, or broad module refactor is in scope. No version bump,
tag, or release in this session: publishing is a separate maintainer decision.

## Acceptance criteria

- `bash -n setup-ai.sh` passes.
- `pwsh -NoProfile -Command "$null=[ScriptBlock]::Create((Get-Content -Raw setup-ai.ps1))"` passes.
- `node --check bin/setup-ai.mjs` passes and `bin/setup-ai.mjs --list` stays consistent with
  `MODULE_ORDER`, `$ModuleOrder`, and `docs/modules.md`.
- `npm run check:retry-marker` passes.
- The gentle-ai module reaches its configurator on a host where `/usr/local/bin` is not on `PATH`.
- No module reports success for work it did not verify.

## Stop conditions

Stop and report instead of continuing if a fix would need a new dependency, if Bash and PowerShell
cannot be kept in parity, if the JSONL rename would break a consumer that cannot be updated in the
same work unit, or if a verification requires a credential this session does not have.
