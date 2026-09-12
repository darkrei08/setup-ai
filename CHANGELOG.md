# Changelog

All notable changes to `@darkrei08/setup-ai` are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Issue and PR tracking (open vs. closed) lives in the GitHub
[issues](https://github.com/darkrei08/setup-ai/issues) and
[pull requests](https://github.com/darkrei08/setup-ai/pulls).

## [3.3.2] - 2026-09-12

### Added

- **`pi-packages` module: declarative Pi extension injection.** Closes
  [#18](https://github.com/darkrei08/setup-ai/issues/18) (partly). A manifest
  (`pi-packages.txt`) lists the extra Pi packages a machine needs, one source per
  line (`npm:<pkg>[@<version>]`, `git:<host>/<owner>/<repo>[@<ref>]`, or a local
  path). It is resolved from `PI_PACKAGES_FILE`, then `<pi agent dir>/pi-packages.txt`
  (the dotenv/config repo, since `~/.pi/agent` is normally a symlink into it), then
  the installer directory; nothing found installs nothing. Every entry is verified
  by reading `pi`'s own `settings.json` back, and `pi-extensible-workflows` is
  skipped because the `pi-workflows` module owns it. See `docs/pi-extensions.md`
  and `pi-packages.example.txt`.

### Fixed

- **npm 12 `EALLOWREMOTE` broke `pi install` and `pi update --extensions`.** Closes
  [#18](https://github.com/darkrei08/setup-ai/issues/18). npm 12 defaults
  `allow-remote=none`, so any managed install that resolves a URL/tarball
  dependency aborted. setup-ai now writes `allow-remote=all` (append-only, only for
  npm >= 12) into the `.npmrc` of each npm root Pi installs into —
  `~/.pi/agent/npm` (the prefix `pi` passes) and the `extensions` / dotenv
  extension roots — and verifies the file by reading it back. Never written
  globally.

- **`EPERM` on workflow state writes (Windows/WSL).** Closes
  [#18](https://github.com/darkrei08/setup-ai/issues/18) (partly). The published
  `pi-extensible-workflows` writes `state.json` as a bare `write(.tmp)` + `rename()`
  with no retry, so a transient lock fails the run. The `pi-workflows` module now
  builds the patched local checkout (`PI_WORKFLOWS_SOURCE_DIR`, fix ref
  `PI_WORKFLOWS_FIX_REF`) and installs it into both Pi roots, proving the retry in
  the source, in the built artifact and in the installed artifact. It never pushes,
  publishes, or switches the branch of a checkout the user owns; when the patch
  cannot be produced it reports `patched_build_unavailable` and keeps the published
  release. Windows uses a detected Git Bash for the POSIX-only core build script.
  Two defects found by running the installer on a real machine are covered by tests:
  `npm install` now runs **only** in directories with a local `package.json` (a root
  without a manifest is skipped with `root_not_npm_project`, because npm otherwise walks
  up and rewrites an ancestor project's manifest — observed rewriting
  `<dotenv>/pi/agent/package.json` and creating ~169 MB of `node_modules` there), and the
  swap of the published package for the patched build is now performed **after** every
  failure-prone step and rolls back when it fails, so the environment is never left
  without a registered workflow package.

- **The bash package readback could never match, so `pi-packages` and the patched
  workflow both aborted.** Closes
  [#19](https://github.com/darkrei08/setup-ai/issues/19). The bash verifier reduced every
  source to its basename, and the embedded Node helper then resolved that basename as a
  local path, so no `npm:`/`git:` source could equal pi's recorded entry: the first
  manifest line failed with `package_not_registered`, the swap rolled back on its own
  post-install check, and the rollback's restored-state check reached `exit 1` even when
  the published release had actually come back. Both sides now compare the same full
  identity against the agent directory, a leading `~` is expanded in both
  implementations, and the dead basename helper is gone.

  Five more defects around the same invariant (prove what was installed, fail closed
  when that proof is unavailable, keep both platform scripts interchangeable) are fixed
  with it: the published install in `mod_pi_workflows` is now read back on bash too, as
  the PowerShell sibling already did; a managed root that carries the package without its
  entry point fails closed instead of being skipped; a PowerShell rollback that cannot
  read a root's `package.json` sets the rollback-failure latch instead of throwing past
  it and degrading to an unproven published release; a rerun with the local source
  already registered converges instead of rolling back forever; and the
  `pushd`/`Push-Location` calls before every `npm install` are now checked, so a failed
  directory change can no longer make npm write into an unrelated project.

- **The skill verification failed for every agent the upstream CLI does not copy into.**
  `npx skills add --global` installs into `${HOME}/.agents/skills` and copies into an agent's own
  config directory only when it supports that agent, so the Codex-only special case added for
  [#8](https://github.com/darkrei08/setup-ai/issues/8) broke the next agent instead of fixing the
  class: a full install on Windows stopped at `ee` with "engineering-excellence SKILL.md missing
  for targeted agent 'opencode'", and then at `skills` with the same message for `gemini-cli`,
  after the CLI had installed both skills and reported where they went. Both platform scripts now
  accept the shared root for every detected agent, next to that agent's own directory, and report
  a WARN naming each agent whose own directory the CLI skipped, so a shared artifact never stands
  silently in for a per-agent copy.

## [3.3.1] - 2026-09-12

### Fixed

- **Linux dotenv symlink-safe scans.** Closes [#16](https://github.com/darkrei08/setup-ai/issues/16).
  The compatibility probes no longer follow dangling symlinks in an existing
  `vekexasia/dotenv` checkout, so installation reaches `setup_env.sh` as expected.

## [3.3.0] - 2026-09-12

### Added
- **Optional `rotator` module.** Closes [#14](https://github.com/darkrei08/setup-ai/issues/14).
  Detects cockpit-tools data markers, probes the local tuxevil-rotator gateway, installs
  the multi-account `tuxevil-rotator` CLI idempotently, and installs the
  `pi-cockpit-tools-sync` Pi extension when Pi is available. Login, import, and start
  remain explicit user actions; setup-ai never writes tokens, auth.json, or provider
  configuration.

### Fixed
- **Codex skills verification.** Closes [#8](https://github.com/darkrei08/setup-ai/issues/8).
  `skills add --global --agent codex` exits `0` and really installs the skill, but to the
  shared `~/.agents/skills/` directory, not the `~/.codex/skills/` path the post-install gate
  asserted — so the `ee`/`skills` modules failed with a false `module_failed`. The gate now
  verifies each agent against a set of candidate skill roots (codex: `~/.codex/skills` **or**
  `~/.agents/skills`) in both `setup-ai.sh` and `setup-ai.ps1`, and still fails loudly when the
  skill is present in none of them.

## [3.2.0] - 2026-09-10

### Added
- **`gentle-ai` module (cross-OS).** Closes [#6](https://github.com/darkrei08/setup-ai/issues/6).
  Reinstates the gentle-ai / `gga` ecosystem configurator (removed from the 3.1.0
  module set) across `setup-ai.sh`, `setup-ai.ps1` and `bin/setup-ai.mjs`. The
  module installs the CLI via each OS's official method, then runs
  `gentle-ai install` — gentle-ai's own **interactive per-agent/per-IDE selector**
  (Pi, Claude Code, Cursor, Codex, ...) that also wires each selected agent's
  **MCP** servers so the tools show up under `/mcp`. For pi it additionally
  installs the first-class `gentle-pi` harness and `pi-mcp-adapter`, then verifies
  `gentle-pi` is registered in pi's `settings.json`. The interactive selector runs
  only with a real TTY; non-interactive/CI runs log the exact command instead of
  hanging. A quality gate verifies the binary is on PATH and gentle-pi is
  registered. Idempotent and safe to re-run.

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
  `skills` module and clarified the PowerShell 7.3+ requirement.

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

[3.3.2]: https://github.com/darkrei08/setup-ai/releases/tag/v3.3.2
[3.3.1]: https://github.com/darkrei08/setup-ai/releases/tag/v3.3.1
[3.1.0]: https://github.com/darkrei08/setup-ai/releases/tag/v3.1.0
