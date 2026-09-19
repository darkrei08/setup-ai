# AGENTS.md — setup-ai coding standards

These are the review rules for this repository. `gga` reads this file (`RULES_FILE`
in `.gga`) to review changes before every commit. Review against **these** rules,
not generic TypeScript conventions.

## What this project is

`@darkrei08/setup-ai` is a **cross-OS installer** for an AI coding toolchain.
The stack is deliberately dependency-free:

- `bin/setup-ai.mjs` — Node ESM launcher (OS detection + interactive menu). **Zero runtime deps.**
- `setup-ai.sh` — the Linux/macOS installer (bash).
- `setup-ai.ps1` — the Windows installer (PowerShell).

The two platform scripts are **parallel implementations of the same behavior**.

## Golden rule: cross-OS parity

Any change to a module's behavior (module list, order, descriptions, install
logic, verification) **must be mirrored** in both `setup-ai.sh` and
`setup-ai.ps1`. A change to one without the other is a defect. The Node launcher's
`MODULES` array must stay consistent with `MODULE_ORDER` (sh) and `$ModuleOrder` (ps1).

## Bash (`setup-ai.sh`)

- Start scripts with `set -euo pipefail`; keep that guarantee — do not silently
  swallow failures.
- Quote all expansions: `"${VAR}"`, `"$@"`. No unquoted word-splitting.
- Prefer `local` variables inside functions. No accidental globals.
- Every external command that can fail must be checked or routed through the
  existing helpers (`run_cmd`, `capture_cmd`, `require_command`, `log_event`).
- Installs must be **idempotent** and safe to re-run.
- **Never** install into an ambiguous location. When running `npm install` in a
  directory, ensure a `package.json` marks that directory as the project root, so
  npm cannot walk up the tree into an unrelated project.
- **Verify what you installed** by reading the exact target path
  (`<dir>/node_modules/<pkg>/package.json`), not by `require.resolve` walking up
  the directory tree (it can resolve a shadowing ancestor copy).
- `bash -n setup-ai.sh` must pass. Prefer `shellcheck` clean where available.

## PowerShell (`setup-ai.ps1`)

- Keep `Set-StrictMode` / error handling consistent with the existing file.
- Mirror the bash module semantics exactly (names, order, descriptions, verify).
- Use the existing logging/step helpers (`Write-Log`, `Invoke-Step`).
- The file must parse: `pwsh -NoProfile -Command "$null=[ScriptBlock]::Create((Get-Content -Raw setup-ai.ps1))"`.

## Node launcher (`bin/setup-ai.mjs`)

- ESM only, **no runtime dependencies** (this is a hard constraint — `npx` must work
  with nothing installed).
- Must never exit silently: always print a first line, and fall back cleanly when
  the interactive TTY menu is unavailable.
- Keep `MODULES` in sync with the shell/PowerShell registries.

## General

- **No dead code**: no unreachable branches, no commented-out blocks left behind,
  no unused variables/functions.
- **No error hiding**: do not mask failures with `|| true` unless the step is
  explicitly optional and logged as such (`run_optional`).
- Logs are artifacts, not source: `logs/`, `*.log`, `*.jsonl` are git-ignored.
- Keep changes small and reviewable; explain non-obvious logic with a short comment.
- Business logic that can silently break the install (version resolution,
  path/symlink handling, OS detection) must be **verified in-script** after it runs.
- **One branch per review**: do not `git checkout` / `git switch` / create branches
  while an RDD review is being negotiated. The review target is a snapshot of the
  live workspace, so a checkout in that window makes every `start` reconcile to
  `mutation_outcome: unknown` and then fail with `stale_target_identity`. Commit,
  review, and only then move on; see
  [rdd-review-troubleshooting.md](docs/rdd-review-troubleshooting.md#operational-rule-do-not-switch-branches-during-a-review).

## Commits

- Every commit goes through `gga run` (the pre-commit hook). **Never** use
  `git commit --no-verify` / `-n`. If review fails, fix the code — do not bypass.
