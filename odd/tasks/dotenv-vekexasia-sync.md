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

- [ ] T1. Meticulous analysis of the 6 upstream commits / 27 files, mapped
      against the 33 own commits: what to bring, conflicts, breakage risk.
- [ ] T2. Redesign `~/.pi/agent` management: selective rsync in
      `dotenv/setup_env.sh` (or setup-ai module) preserving auth/sessions.
- [ ] T3. Fix setup-ai `DOTENV_DIR` + dedup skills (single source of truth).
- [ ] T4. Merge vekexasia into `darkrei08/dotenv` preserving the 33 integrations.
- [ ] T5. Verify: `workflow` resolves roles+aliases post-install; no broken plugins.

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
