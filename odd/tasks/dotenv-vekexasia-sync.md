# Feature: dotenv ↔ vekexasia sync + pi config install fix

## Problem

1. **Workflows have no roles/aliases.** `~/.pi/agent` is a live real directory
   (holds `auth.json`, `sessions/`, `agents/`, `chains/`) and lacks
   `pi-extensible-workflows/roles/` and the workflow `settings.json`
   `modelAliases`. So `workflow` cannot resolve `developer`, `reviewer`,
   `scout`, `summarizer`, `tests-expert`, nor aliases (`cheap-model`,
   `reviewer-model`, `developer-model`, `oracle-model`, `researcher-model`, ...).

2. **Two conflicting philosophies for `~/.pi/agent`:**
   - dotenv `setup_env.sh` `sync_pi()` does `rm -rf ~/.pi/agent && ln -s repo`
     → would DESTROY live `auth.json` and `sessions/`.
   - setup-ai treats `~/.pi/agent` as a real dir managed by modules
     (`pi`, `pi-packages`, `pi-workflows`, `gentle-ai`).

3. **Duplicated installs.** `npx skills add` for the same skills runs twice:
   setup-ai `skills` + `ee` modules AND dotenv `setup_env.sh`.

4. **Path mismatch.** setup-ai `DOTENV_DIR=${HOME}/git/personale/dotenv`
   (`/home/ema/...`) does not exist; the real checkout is
   `/mnt/nvme-1/git/personale/dotenv`.

5. **Fork drift.** `darkrei08/dotenv` = 33 own commits ahead, 6 behind
   `vekexasia/dotenv` (upstream/master). Upstream added `pi-codex-context`
   package + changes to `models.json`, `modes.json`, `settings.json`,
   workflow `settings.json`, removed `hashline-tool-display-bridge.ts`,
   changed `compact-tools.ts` and `pi-omplike-advisor`.

## Decisions (user-approved)

- **D1:** Manage `~/.pi/agent` via **selective rsync copy** of versionable
  parts from the dotenv repo; preserve `auth.json`/`sessions/`. Drop the
  destructive `sync_pi()` symlink.
- **D2:** **Full sync** with vekexasia, preserving the 33 own commits;
  meticulous per-file analysis with conflict/breakage flags.
- **D3:** **Deduplicate skills** to a single source of truth.

## Tasks

All five are done. Evidence for each:

- [x] T1. Analysis of the upstream commits against the 33 own commits, per file,
      with the conflict and breakage flags: `odd/tasks/vekexasia-divergence.md`.
- [x] T2. `~/.pi/agent` is now managed by a selective rsync allowlist in
      `dotenv/setup_env.sh` `sync_pi()` (config files, packages, prompts, skills,
      themes, extensions minus the workflow wrappers); `auth.json`, `sessions/`,
      `agents/` and the caches are never touched, and the function re-reads the
      workflow roles and aliases it just copied.
- [x] T3. `DOTENV_DIR` is overridable and the skills are installed once:
      `mod_dotenv` sets `SETUP_AI_SKIP_SKILLS=1` when the `ee` or `skills` module
      runs in the same pass (setup-ai 3.6.1, issue #62), and `dotenv`'s own block
      keeps a `</dev/null` stdin so a non-interactive run cannot abort (dotenv #18).
- [x] T4. Merged: `dotenv` master `f2de886` (`chore/vekexasia-alignment`) and then
      `7a747d1`.
- [x] T5. Verified on the Debian 13 LXC with the published 3.6.2: a full
      `--all --verbose --yes` run is green (17/17 modules, TTY 155s and non-TTY
      148s), and `sync_pi`'s own check proves the copied
      `pi-extensible-workflows/roles` and `settings.json` are in place.

## Follow-up found by the 3.6.2 container run

The optional `rotator` module reported `success` while the gateway could not
start at all: `tuxevil-rotator` exits immediately when no account is configured,
so the port never opens and the Pi extension warns at session start while the
closing summary says nothing. The module now reads `gateway.log`, logs
`rotator accounts_missing` and queues an actionable line that the closing
summary prints as `Then : …`, naming the interactive login, the OAuth browser
callback on `localhost:51121` and the following `status`/`start` steps (both
platforms).

## Progress

- Sharpened the Language directive in `dotenv/pi/agent/AGENTS.md` (all
  inter-agent/subagent work always English, only final user reply Italian).
  NOT active yet: `~/.pi/agent/AGENTS.md` does not exist in the live dir;
  it lands only after the selective sync (T2/T3).

## Constraints

- Cross-OS parity (AGENTS.md golden rule): mirror any module behavior change in
  `setup-ai.sh` AND `setup-ai.ps1`, keep `bin/setup-ai.mjs` MODULES in sync.
- Idempotent, re-runnable installs; never `rm -rf` live pi state.
- No commit without explicit user request; never `--no-verify`.
