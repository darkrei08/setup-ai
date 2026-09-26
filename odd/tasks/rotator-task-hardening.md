# Rotator task ownership hardening

## Goal
Close the independent review gaps in the receipt-backed Windows rotator scheduled-task lifecycle without exceeding the existing 400-line work-unit boundary.

## Scope
- Keep uninstall limited to a valid sidecar receipt plus the exact current scheduled-task fingerprint.
- Extend the fingerprint to the principal properties and stable task settings that could change who runs the task or how it runs; test mismatches.
- Make receipt creation fail closed without leaving a partial final receipt that blocks retries; preserve any receipt not provably created by this call.
- Compare executable command paths using Windows path case semantics so casing-only differences do not churn an owned task.
- Do not run installer/uninstaller, Task Scheduler, containers, GGA, OCR, Alibaba/OpenCode review, or Git delivery operations.

## Verification
- TDD: `pwsh -NoProfile -File tests/powershell-lifecycle.ps1` (test-first RED, implementation GREEN).
- Parse: `pwsh -NoProfile -Command '$null=[ScriptBlock]::Create((Get-Content -Raw setup-ai.ps1))'`.
- `git diff --check`.
- Keep this remediation a distinct work unit below the feature's 400 authored additions-plus-deletions ceiling; reduce or narrow the behavior rather than exceeding that boundary.

## Progress
- [x] Add focused regression cases for principal/settings identity, receipt-write failure cleanup, and case-insensitive executable path comparison.
- [x] Implement the smallest fail-closed corrections.
- [x] Run focused checks, an independent read-only review, and the parent spot-check.

The core receipt-backed task lifecycle is tracked as completed work unit #52 (398 changed lines). Follow-up #56 is complete; package-removal work may proceed as the next separate work unit.

## Verification results
- `pwsh -NoProfile -File tests/powershell-lifecycle.ps1`: passed during TDD, independent verification, and parent spot-check.
- `pwsh -NoProfile -Command '$null=[ScriptBlock]::Create((Get-Content -Raw setup-ai.ps1))'`: passed.
- `git diff --check`: passed.
- No actual Task Scheduler operation ran. The compare-and-delete TOCTOU limitation remains documented.

## Review evidence
The independent review of the first task-ownership slice found: incomplete principal fingerprint coverage; an invalid partial receipt could block retry after receipt-write/readback failure; executable path comparison is case-sensitive. It also confirmed revalidation before unregister and identified the remaining Task Scheduler compare-and-delete TOCTOU window, which cannot be eliminated with the current API.
