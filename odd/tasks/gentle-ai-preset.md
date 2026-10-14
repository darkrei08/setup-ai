# Feature: Gentle AI preset and workflow resource safeguards

Issue: #143. Cross-platform launcher/menu change; implementation remains on the issue worktree.

## Specs

- S1: "Add a minimal cross-platform Gentle AI preset to setup-ai. The normal path should install only the required foundation and Gentle AI components; advanced modules remain opt-in."
- S2: "The preset must preserve Vekexasia pi-extensible-workflows practices: model aliases instead of machine-specific IDs, role-specific tool allowlists, bounded concurrency, and context/token safeguards based on provider/model metadata."
- S3: "Selecting the preset yields the same modules on Node, Bash, and PowerShell."
- S4: "Existing Core, Everything, Custom, Minimal, --only, --all, --yes, and --dry-run behavior remains compatible."
- S5: "Do not modify dotenv cleanup here; track it separately in the dotenv repository with a reproducible script excerpt."

## Tasks

- T1 [S1-S4] Define the canonical Gentle AI preset in the Node menu and tests. Route: launcher/menu. Commit: f2fc76b.
- T2 [S1-S4] Mirror preset selection and module order in Bash and PowerShell. Route: cross-platform parity. Commit: f2fc76b.
- T3 [S2-S4] Add focused resource-safety and compatibility verification. Route: tests/docs. Commit: f2fc76b.
- T4 [S5] Keep dotenv cleanup out of scope and record the separate incident boundary. Route: non-goal. Commit: none.

## Log

- L1: "procedi con lo sviluppo e se necessario con altre pane herdr"
- L2: Issue #143 was created before implementation and explicitly excludes dotenv cleanup.
- L3: User preference: use Vekexasia pi-extensible-workflows tools and avoid Gentle AI workflow helpers; use gpt-5.6-luna roles through Herdr when delegating.
- L4: T1 implementation evidence: `bin/menu.mjs` adds the `gentle-ai` preset selecting `base`, `node`, `pi`, `pi-workflows`, and `gentle-ai`; `tests/menu.test.mjs` covers the selection; focused Node tests and syntax/diff checks passed. Bash and PowerShell parity remain T2.
- L5: Commit `f2fc76b` records the completed Gentle AI preset implementation, parity test, ODD task artifacts, host checks, seven-family Linux matrix, GGA review, and native RDD approval.
