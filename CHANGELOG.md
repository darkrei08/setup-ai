# Changelog

All notable changes to `@darkrei08/setup-ai` are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Issue and PR tracking (open vs. closed) lives in the GitHub
[issues](https://github.com/darkrei08/setup-ai/issues) and
[pull requests](https://github.com/darkrei08/setup-ai/pulls).

## [3.1.0] - 2026-09-10

### Added
- **`skills` module (cross-OS).** Closes [#2](https://github.com/darkrei08/setup-ai/issues/2).
  Installs vekexasia/dotenv's agent-skill stack on
  **every OS** via `npx skills add` — previously these skills only landed on Linux
  through the Linux-only `dotenv` delegation. Skills: `herdr` (herdrdev/herdr);
  `triage grill-me grilling wayfinder domain-modeling prototype research`
  (mattpocock/skills); `typescript-advanced` (pedronauck/skills); `show-me`
  (humanlayer/skills). Installed for every detected agent; `skills add --copy` is
  idempotent so it is safe alongside the Linux `dotenv` run. Mirrored across
  `setup-ai.sh`, `setup-ai.ps1`, and `bin/setup-ai.mjs`, with a post-install
  verification gate that checks each skill's `SKILL.md` in the pi skills dir.
- **Bilingual pi-workflows guide** (`docs/pi-workflows-guide.md`, IT/EN). Closes
  [#3](https://github.com/darkrei08/setup-ai/issues/3): install,
  optional `@piewf/*` packages, Herdr extension vs. terminal binary, `/workflow`
  picker vs. `workflow` tool, foreground/background, run IDs, settings, model
  selection, roles/aliases, Neovim boundary, OS notes, troubleshooting.

### Changed
- README: new **pi workflows** section linking the guide; documented the new
  `skills` module; clarified Engram (single `pi-engram init` source of truth) and
  PowerShell 7.3+ requirement.

### Fixed
- Carried forward the 3.0.6 installer hardening (Node ≥ 22.19 guard extracted to a
  reusable check, exact-path install verification, PowerShell failure surfacing).

### Known issues
- **Windows `EPERM` on `state.json` rename** affects both the pi-extensible-workflows
  runtime and the Gentle RDD native review
  ([#1](https://github.com/darkrei08/setup-ai/issues/1)). Root cause is an unretried
  temp-file→rename in the workflow runtime; workaround is a Defender exclusion
  (elevated) or serialized/retried runs.

## [3.0.6] - unreleased on npm (git only)

### Fixed
- npm local/version verification in `setup-ai.sh` / `setup-ai.ps1`; exit-code,
  path, and install-result checks hardened; `AGENTS.md` review rules added; `.gga`
  configured with `PROVIDER=codex`.

## [3.0.4] - prior

### Changed
- Version realignment (npm 3.0.3 frozen); README leads with the npm package to
  avoid `EALLOWGIT` on `github:` installs; header versions synced.

### Fixed
- `fix(engram)`: stop duplicate `gentle-engram`; `pi-engram init` is the sole source.
- `fix(launcher)`: never exit silently; robust menu fallback + UTF-8 on Windows.
- `fix(ee)`: use skills-CLI agent names (`claude-code`, `gemini-cli`) + add
  `codex`/`opencode`.
- `fix(installer)`: unblock nvm on Linux and PATH on Windows.

## [3.0.0] - initial v3

### Added
- v3 cross-OS modular installer (`setup-ai.sh`, `setup-ai.ps1`) + zero-dep npx
  launcher (`bin/setup-ai.mjs`).

[3.1.0]: https://github.com/darkrei08/setup-ai/releases/tag/v3.1.0
