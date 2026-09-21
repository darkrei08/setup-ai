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

## Task order

1. [pending] Open one issue per defect (A-E) following the issue-ops/`#36` contract.
2. [pending] A: resolve the gentle-ai binary through known install dirs (Bash + PowerShell parity).
3. [pending] B: bounded retry plus actionable failure for the GitHub API rate limit.
4. [pending] C: stop logging expected winget exits as warnings.
5. [pending] D: compact JSONL schema in both writers, plus `docs/logs.md`.
6. [pending] Local gates: `bash -n setup-ai.sh`, PowerShell parse check, `node --check bin/setup-ai.mjs`,
   `bin/setup-ai.mjs --list` parity with `MODULE_ORDER`/`$ModuleOrder`/`docs/modules.md`,
   `npm run check:retry-marker`, `git diff --check`.
7. [pending] Container verification of A and C on the distribution families the project claims.
8. [pending] One PR per work unit against `main`, then merge.
9. [pending] vekexasia recon results: fork plus PR for each accepted defect.
10. [pending] Report E to the maintainer with a recommendation.

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
