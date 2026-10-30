# Change & refactor log

## 2026-10-30 — PowerShell dotenv workflow parity

`setup-ai.ps1` now matches `setup-ai.sh` on the dotenv workflow path: it installs and version-verifies `pi-extensible-workflows` inside the dotenv extensions directory (with `ignore-scripts=false` and the npm 12 opt-in), probes all three install roots for the transient-rename retry, and repoints stale extension/barrel symlinks. Covered by `tests/powershell-dotenv-workflows.ps1` (fake npm/pi), which fails against the previous `setup-ai.ps1`, and the pwsh container row now runs it. Native Windows runtime verification not run.

## 2026-10-30 — Launcher menu frame portability

`bin/menu.mjs` now derives the frame width from the terminal (`frameWidth`, clamp 18-70 on `columns - 3`), centres the banner title from its length, shows each preset's module count from the shared preset-selection helper, and uses ASCII action marks. `bin/setup-ai.mjs` passes the live `process.stdout.columns` on every draw. Covered by `tests/menu.test.mjs`. No installer or module behavior changed, so Bash/PowerShell needed no mirroring; native Windows console rendering was not verified.

## 2026-10-06 — Issue #83 Windows gentle-ai resolver

`Resolve-GentleAiCli` now probes `GOBIN`, `GOPATH\bin`, `%USERPROFILE%\go\bin` (where the vendor `go install` writes) before the legacy `%LOCALAPPDATA%\gentle-ai\bin`. Covered by `tests/gentle-ai-cli-resolution-pwsh.sh` (Linux pwsh). Native Windows verification not run.

## 2026-10-05 — Release alignment

GitHub `main` contains the v4.0.0 release line, and `setup-ai` v4.0.0 is released and published. The old dirty branch remains a preserved candidate and is not the release branch. Native Windows/macOS runtime verification is still unavailable. Gentle/Engram integration is pinned globally for agent workflows, but is not committed source.

## 2026-10-04 — Historical issue #105 review

The issue #105 candidate passed the recorded ownership, lifecycle, parity, syntax, diff, and available container checks. Its native review was later approved and acknowledged. Native Windows/macOS runtime verification remained unavailable. This entry is historical and does not describe the release branch.
