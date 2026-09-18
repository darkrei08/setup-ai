# Changelog

All notable changes to `@darkrei08/setup-ai` are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.6.0] - 2026-09-18

### Added

- `--dry-run`: reports the whole plan and installs nothing. Mutations routed through the command choke points plus every direct file writer report `would run` / `would do`, no sudo or secret prompt is reached, and the run ends with an explicit `nothing was installed, nothing was written` summary.
- `--uninstall [--yes] [--purge] [--only <csv>]`: one declared catalog of what the suite owns, with one generic remover per item kind instead of a function per module. `--yes` is required, destructive entries additionally need `--purge`, and `~/.pi/agent` (including `auth.json` and `sessions/`) is refused by a guard that compares both the literal and the resolved path.
- A Pi startup acceptance check: after the gentle-ai repair the installer runs `PI_OFFLINE=1 pi </dev/null` under a bounded timeout and fails the module with the first diagnostic when pi cannot load its extensions, instead of reporting success on a machine where `pi` aborts.
- `tests/pi-startup-check.sh`, the acceptance harness for that check (11 checks, no model call, no network), and `bin/check-workflow-retry-marker.mjs`, which fails when the retry-marker assertion or its call site is dropped.

### Fixed

- The installer no longer persists `GENTLE_PI_QUIET_TOOLS=0`, and it repairs the `npm:gentle-pi` entry into the object form excluding `-extensions/quiet-tools.ts` and `-extensions/pi-pretty.ts`. Both registrants collide with `npm:pi-tool-display` on the built-in tool names, and pi aborts with `Tool "read" conflicts`.
- The effective Pi config directory is resolved from `PI_CODING_AGENT_DIR` in every consumer instead of being rebuilt from `$HOME`: two PowerShell sites verified a directory the installer never created, and `$SkillAgentRoots`/`$piSettings` now follow the same resolution as the Bash siblings.
- The rotator module refuses to install `tuxevil-rotator` below Node 20 in **both** shells, instead of installing a gateway that crashes at startup with `ReferenceError: File is not defined` and reporting success.
- `base` no longer requests `github-cli` when another package already provides `gh`.
- `skills` and `ee` report the shared skills root at INFO for codex, instead of one `skill_not_copied_to_agent_root` WARN per agent and skill.
- Documented how to read the install log and the real live Pi config path, `~/.pi/agent/settings.json`, including the leftover symlink claim the README still carried.
- `TMP_DIR` was assigned twice, so `cleanup` removed only the second directory and the first leaked on every run; under `--dry-run` that leaked the log directory as well, because `LOG_DIR` derives from the first value.

### Changed

- The local patched workflow build is gone. The published `pi-extensible-workflows` already ships the transient-rename retry, so the module installs the published release and asserts the `renameWithRetry` marker against the loaded artifact, with a WARN plus remedy when it is missing. A local build from a checkout could not produce a better artifact than the published release.
- `--list`, the Windows refusal for the lifecycle flags, and the launcher are documented and keep all four version locations and the module registries in step.

### Removed

- `PI_WORKFLOWS_SOURCE_DIR`, `PI_WORKFLOWS_FIX_REF` (its default ref existed on no remote), `PI_WORKFLOWS_REMOTE`, `install_patched_pi_workflows`/`Install-PatchedPiWorkflows`, their rollback helpers, the Git-Bash relay bridge and the now-callerless modes of `assert_pi_package_registered`/`Assert-PiPackageRegistered`.

### Known

- `-DryRun` and `-Uninstall` are refused on Windows with exit 2 rather than silently doing nothing; the Windows implementation is still to be written.

## [3.5.2] - 2026-09-15

### Fixed

- Fixed stdout/stderr capture so command warnings remain visible without corrupting captured values.
- Approved and rebuilt `gentle-pi` immediately after installation for npm 12.
- Removed redundant npm-root marker setup where the existing remote-source helper already creates it.
- Forwarded unattended flags for `--all`, tightened cross-OS Pi registration checks, and hardened Windows task/path verification.

## [3.5.1] - 2026-09-15

### Fixed

- **An interrupted run no longer reports success**
  ([#58](https://github.com/darkrei08/setup-ai/issues/58)). `setup-ai.sh` traps
  `HUP`/`INT`/`TERM`, reports `outcome=interrupted` with
  `interrupted=true;signal=<name>`, marks the in-flight module failed and exits
  `128+signal`. `setup-ai.ps1` records Ctrl+C through a .NET SIGINT handler and
  produces the same summary with exit code 130.
- **`-Only <single module>` runs again on Windows.** `$selected.Count` threw under
  `Set-StrictMode` when the selection resolved to one module; it is
  `@($selected).Count` now.
- **The npm publish workflow works with trusted publishing.** It installs the npm
  that supports the OIDC exchange (>= 11.5.1) and skips provenance while the
  repository is private, which npm rejects with 422.

## [3.5.0] - 2026-09-15

### Added

- **npm publishing through GitHub Actions.** `.github/workflows/publish.yml` publishes a
  version tag to npm with trusted publishing (OIDC) and provenance, so a release never
  depends on a local npm login.

### Fixed

- **`--yes` / `-Yes` is now truly unattended**
  ([#54](https://github.com/darkrei08/setup-ai/issues/54)). It selects the non-interactive
  vendor path in both scripts: gentle-ai installs over its detected agents instead of the
  TTY selector, the pi installer runs detached from the controlling terminal (`setsid`,
  with a `python3` fallback where `setsid` is absent; a child PowerShell with an empty
  stdin pipe on Windows) so its keypress menu takes the no-TTY default, and codex runs
  with `CODEX_NON_INTERACTIVE=1`.
- **The launcher refuses unknown flags** instead of silently opening the module menu, and
  `--verbose` / `-v` runs the core set unattended.
- **WSL runs stay Linux-native**
  ([#55](https://github.com/darkrei08/setup-ai/issues/55)). When `setup-ai.sh` runs under
  WSL, the preflight removes every `/mnt/*` PATH entry (verified by readback) and refuses
  a `HOME` on the Windows filesystem, so a WSL install can no longer resolve the Windows
  `node`/`npm`/`pi` or write to the Windows profile.

## 3.4.4

- Stream command output live so package installs and sudo prompts are visible.
- Add clearer module progress banners and a spaced module-selection menu.

Issue and PR tracking (open vs. closed) lives in the GitHub
[issues](https://github.com/darkrei08/setup-ai/issues) and
[pull requests](https://github.com/darkrei08/setup-ai/pulls).

## [3.4.3] - 2026-09-15

### Fixed

- **ai-memory-kit release downloads.** Patch existing dotenv checkouts that use
  GitHub's branch-only codeload URL with a tagged `AIMEM_REF`, which caused a 404.

### Added

- **Verbose terminal output.** `--verbose` / `-v` renders spaced event blocks and
  indents child-command output while preserving the human and JSONL log artifacts.

## [3.4.2] - 2026-09-14

### Changed

- **Documentation split into focused pages.** The README is now a short overview with a
  `Documentation` index that links each section; the install matrix, the module reference,
  the logs, OpenCode Go and a new troubleshooting page live under `docs/`, which is now
  published (`package.json#files`). Fixes
  [#43](https://github.com/darkrei08/setup-ai/issues/43).

### Fixed

- **`docs/modules.md` matched to the code.** The `gentle-ai` module *executes*
  `gentle-ai install --scope global --agents <detected>` in non-interactive runs (it does
  not just log the command), and the `rotator` module logs `INFO service_skipped`, not a
  `WARN`, when the machine offers neither a unit nor a task.
- **`base` installs a clipboard backend on Linux.** `wl-clipboard` (Wayland) and
  `xclip` (X11) were missing, so `Ctrl+V` in `pi` attached nothing. Fixes
  [#51](https://github.com/darkrei08/setup-ai/issues/51).
- **`gentle-ai` persists `GENTLE_PI_QUIET_TOOLS=0` instead of only warning.**
  With `pi-hashline-edit-pro` installed, `pi` aborted at startup in any shell
  that had not sourced an rc file; the module now writes the switch to the shell
  rc files and `~/.config/environment.d/50-gentle-pi.conf` and logs
  `quiet_tools_disabled`. Fixes
  [#52](https://github.com/darkrei08/setup-ai/issues/52).

## [3.4.1] - 2026-09-14

### Changed

- **`dotenv` defaults to the `darkrei08/dotenv` fork and now runs before `pi-packages`.**
  The fork's `setup_env.sh` detects Arch/Omarchy vs. Debian instead of hardcoding
  `apt-get`, so the module can succeed on both. Running `dotenv` before
  `pi-packages` means the first run installs the manifest into the symlinked
  dotenv config instead of a directory `sync_pi` replaces later. Override the
  clone source with `DOTENV_REPO`. Fixes
  [#40](https://github.com/darkrei08/setup-ai/issues/40).

### Fixed

- **`opencode` resolves its install dir after the remote installer.** The
  installer appends `$HOME/.opencode/bin` to the shell rc only, so the
  non-interactive run could not see the binary and the module failed with
  `missing_command` (127), aborting the whole run. Fixes
  [#38](https://github.com/darkrei08/setup-ai/issues/38).
- **`gentle-ai` warns when a shadowing extension is installed.** `pi` aborts at
  startup when another extension registers the same `read`/`edit` tools as
  gentle-pi quiet-tools; the module now names the package and the
  `GENTLE_PI_QUIET_TOOLS=0` escape hatch. Partial fix for
  [#41](https://github.com/darkrei08/setup-ai/issues/41).

## [3.4.0] - 2026-09-14

### Added

- **Machine-readable run summary.** Every run now ends with one `run_summary` JSONL record
  and every executed step adds a `step_result` record: run id, outcome, started/ended
  timestamps, duration, per-module outcome with the failing step and its return code, and
  step counts. A failed run writes it too - the bash side does it from the exit trap,
  which also covers the failure paths that `exit` directly - the engineering report ends
  with the same summary, and both scripts emit the same fields in the same order. Existing
  event names and payloads are unchanged. See the README `Logs` section. Implements
  [#10](https://github.com/darkrei08/setup-ai/issues/10).
- **`rotator` module: the gateway is started, not just installed.** The module keeps a
  `systemd --user` unit (Linux) or a logon scheduled task (Windows) so the gateway
  survives a reboot, starts `tuxevil-rotator` in the background only when nothing answers
  on port 51200, and proves that start with a bounded re-probe before reporting it. A
  machine with neither mechanism still gets a detached process and a `WARN`, never a
  failed install.
- **`rotator` module: the Windows task supervises the gateway.** The task now also carries a
  five-minute repeating trigger, with `-MultipleInstances IgnoreNew` so a tick is skipped while
  the gateway it started is still running and `-ExecutionTimeLimit 0` so the scheduler never
  kills a long-running one. Each tick checks the port before it starts anything, so a gateway
  owned by a session or by the detached fallback is not doubled, and a gateway that dies comes
  back without waiting for the next logon, the next `setup-ai` run, or the next Pi session.
  Linux already restarts through the unit's `Restart=on-failure`/`RestartSec=5` and needs no
  code change.
- **`rotator` module: Linux detection verified across distributions.** The apt/dnf/pacman/
  zypper families and their derivatives resolve through `ID_LIKE`, including CachyOS ->
  pacman; a distribution the installer cannot map still fails closed at preflight with
  `unsupported_distribution`.
- **`pi` npm 12 install-script approval.** npm 12 blocks a dependency's install
  scripts until that package is explicitly approved, and `pi install` runs a plain
  `npm install` with no post-processing, so gentle-pi's postinstall was silently
  skipped on a fresh machine. The installer now approves and rebuilds the packages it
  depends on, and verifies the result. See `docs/pi-extensions.md`.
- **Native RDD review troubleshooting note.** Documents the `start` failure that
  reconciles to `status: blocked` / `outcome: native-mutation-status-reconciled` /
  `mutation_outcome: unknown` with a clean authority store, the read-only commands that
  prove the store is untouched, the one verified candidate cause (the provider's pinned
  package-local reviewer binary is not installed), the hypotheses ruled out, and the two
  continuations. See `docs/rdd-review-troubleshooting.md`.

### Fixed

- **`rotator` module: the gateway restart loop is bounded.** The `systemd --user` unit
  carried `Restart=on-failure` with no start limit, so a machine with no account logged in
  (the state the module documents and expects) respawned `tuxevil-rotator` every 5s forever:
  measured at 8 starts per minute, ~1.6-3.5s CPU and ~43-53MB per attempt, with the unit
  enabled at boot. The unit now carries `StartLimitIntervalSec=300` and `StartLimitBurst=5`,
  and the module clears the resulting `failed` state with `systemctl --user reset-failed`
  before starting, so a unit that burned through its burst is still startable after
  `tuxevil-rotator login`.
- **`opencode` module: the `opencode-pi` Pi extension could not spawn the CLI on Windows.**
  The extension runs `child_process.spawn("opencode")` with no shell, so the npm `.cmd`/`.ps1`
  shims in `%APPDATA%\npm` are not executable for it: every Pi session warned
  `spawn opencode ENOENT` while `opencode --version` worked in a terminal. The module now probes
  that no-shell spawn, resolves the packaged `node_modules/opencode-ai/bin/opencode.exe` behind
  the shim, and persists `OPENCODE_PI_BIN` for the current user (idempotent: an already
  spawnable launcher is kept and a re-run writes the same value, and a re-run on an install
  that already spawns writes nothing). On Linux/macOS the same probe verifies the PATH entry
  instead of assuming it.
- **`rotator` module: the cockpit-sync Pi extension source was uninstallable.** It
  passed `github:darkrei08/pi-cockpit-tools-sync`, which `pi install` resolves as a local
  path (`Path does not exist: <cwd>/github:darkrei08/pi-cockpit-tools-sync`). The accepted
  form is `git:github.com/darkrei08/pi-cockpit-tools-sync`, and the readback checks that
  source instead of a string an earlier run may have left in settings.
- **`pi` install-script approval is verified, not assumed.** The rebuild of a present
  package is no longer an optional step, so a blocked postinstall that fails now fails
  the run; an unreadable npm state fails closed instead of continuing on a warning; and
  the load-bearing `gentle-pi` review binary is read back from disk after the rebuild.
- **`pi` install-script approval survives a package update.** Approving with npm's
  default `allow-scripts-pin=true` wrote `gentle-pi@<version>`, so the next `pi update
  --extensions` moved the package onto a version that no longer matched the entry: the
  postinstall was re-blocked, the package-local `gentle-ai` review binary disappeared, and
  every pi session rendered `Receipt-driven development: unknown` (and could not start a
  native review) until setup-ai ran again. Approval is now name-only
  (`--no-allow-scripts-pin`), which covers the versions pi installs later, and npm converts
  an existing pin into the name-only entry. Closes
  [#26](https://github.com/darkrei08/setup-ai/issues/26).

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
