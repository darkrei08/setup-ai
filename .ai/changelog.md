# Change & refactor log

## 2026-10-06 — Issue #83 Windows gentle-ai resolver

`Resolve-GentleAiCli` now probes `GOBIN`, `GOPATH\bin`, `%USERPROFILE%\go\bin` (where the vendor `go install` writes) before the legacy `%LOCALAPPDATA%\gentle-ai\bin`. Covered by `tests/gentle-ai-cli-resolution-pwsh.sh` (Linux pwsh). Native Windows verification not run.

## 2026-10-05 — Release alignment

GitHub `main` contains the v4.0.0 release line, and `setup-ai` v4.0.0 is released and published. The old dirty branch remains a preserved candidate and is not the release branch. Native Windows/macOS runtime verification is still unavailable. Gentle/Engram integration is pinned globally for agent workflows, but is not committed source.

## 2026-10-04 — Historical issue #105 review

The issue #105 candidate passed the recorded ownership, lifecycle, parity, syntax, diff, and available container checks. Its native review was later approved and acknowledged. Native Windows/macOS runtime verification remained unavailable. This entry is historical and does not describe the release branch.
