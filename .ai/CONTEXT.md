# Project context

## Purpose
`@darkrei08/setup-ai` is a dependency-free cross-platform installer for an AI coding toolchain. It exposes a Node ESM launcher and parallel Bash and PowerShell implementations.

## Current status
GitHub `main` contains the v4.0.0 release line, and `setup-ai` v4.0.0 is released and published. The old dirty branch is a preserved candidate, not the release branch. Native Windows/macOS runtime verification remains unavailable. Gentle/Engram integration is pinned globally for agent workflows, but is not committed source.

## Architecture & structure
- `bin/setup-ai.mjs` — Node launcher, OS detection, module menu, and fallback behavior.
- `setup-ai.sh` — Linux/macOS installer and uninstall flows.
- `setup-ai.ps1` — Windows installer and uninstall flows.
- `tests/` — parity, lifecycle, ownership, launcher, startup, and container-matrix checks.
- `docs/` — module and operational documentation.
- `.gga` — repository review configuration.

Behavioral module registries must remain aligned across Node, Bash, and PowerShell. Global npm installs are verified at their exact npm-root package path and are removed only when setup-ai ownership evidence still matches.

## Tech stack
Node.js ESM, Bash, PowerShell, npm, Docker-based Linux distribution checks, and the repository `gga` review hook. Runtime dependencies are intentionally avoided by the launcher.

## Boundaries & non-goals
Do not mutate packages, tasks, services, or files that setup-ai cannot prove it owns. Native Windows runtime verification is required when available; Linux/WSL or Windows containers on this Linux host are not substitutes. Do not commit, push, merge, publish, or close issues until repository review gates pass and the action is authorized.

## External dependencies & services
The installer may invoke npm, system package managers, Docker, PowerShell, and optional external agent CLIs. Tests use isolated fake tools where mutation would be unsafe. GitHub, GGA, and Gentle native review are delivery/review services, not runtime installer dependencies. Gentle/Engram integration is pinned globally for agent workflows and is not committed source.

## Where memory lives

- `.ai/CONTEXT.md` — this file
- `.ai/conventions.md` — conventions adopted
- `.ai/decisions/` — ADRs
- `.ai/changelog.md` — notable changes
- `.ai/problems.md` — problems and solutions
- `.ai/reviews/` — review outcomes
- `.ai/todo.md` — open work
- `.ai/directives.md` — repository directives
- `.engram/chunks/` — machine-readable Engram cache
