# T1 — Meticulous analysis: vekexasia upstream sync

Evidence base: `/mnt/nvme-1/git/personale/dotenv`, merge-base `b101fd9`,
`upstream/master` = `40b31ff`. You: 33 own commits ahead, 6 behind.

Upstream's 6 commits: `faa40b4 a`, `836f689 updates`, `9acf68d agents`,
`6c0205e context management`, `e8069ee todo`, `40b31ff a`.

## Per-file merge table

| File | Upstream change | You touched? | Risk | Action |
|---|---|---|---|---|
| `pi/agent/packages/pi-codex-context/**` (11 new) | NEW "context management" package | no | none | **take-upstream** (add new files) |
| `pi/agent/packages/pi-omplike-advisor/*` | controller/runtime/test tweaks | no | low | **take-upstream** |
| `pi/agent/extensions/compact-tools.ts` | comment-only edit (drops hashline mention) | no | low | **take-upstream** |
| `pi/agent/extensions/hashline-tool-display-bridge.ts` | **removed** | no | **HIGH** | **decision D-A** (coupled to your commit 8f21d7b) |
| `pi/agent/extensions/pi-tool-display/config.json` | removed 6 lines | no | med | tied to D-A |
| `herdr/config.toml` | -17 lines | no | low | **take-upstream** (verify your herdr prefs) |
| `nvim/lua/config/keymaps.lua` | -5 lines | no | low | **take-upstream** |
| `pi/agent/models.json` | deepseek id `v4-flash-0731`->`v4.1-flash`, route deepinfra->deepseek | 1 commit (added `tuxevil-rotator` provider, different hunk) | low | **manual-merge** (non-overlapping; take both) |
| `pi/agent/modes.json` | advisor -> `opencode-go/deepseek-v4-flash` (+ whitespace glitch) | 1 commit (kept advisor openrouter, added `opencode-max`) | med | **manual-merge** (decision D-F) |
| `pi/agent/pi-extensible-workflows/settings.json` | extensions: drop `pi-openai-fast`, `pi-hashline-edit-pro`; rename `pi-anthropic-oauth`->`pi-anthropic-auth` | 5 commits (added gemini/opencode aliases, skills list, ponytail ext) | **HIGH** | **manual-merge** (your aliases/skills are here) |
| `pi/agent/settings.json` | drop visual-explainer, anthropic-oauth, hashline, vcc(pkg), orcarouter, plannotator, openai-fast; add pi-codex-context, pi-anthropic-auth, `compaction.enabled` | 4 commits (defaultProvider opencode-go, cockpit-sync pkg, modelThinkingLevels) | **HIGH** | **manual-merge** (decisions D-B..D-E) |
| `pi/agent/npm/package.json` | dep list matches settings churn | 2 commits | med | **manual-merge** then regenerate lock |
| `pi/agent/npm/package-lock.json` | 16k-line churn | 2 commits | n/a | **regenerate** (`npm install` after package.json settled) |
| `pi/agent/AGENTS.md` | small edits | 6 commits (+ my Language edit today) | med | **manual-merge** (keep your directive) |
| `setup_env.sh` | removed 1 line (`herdr plugin install plannotator/herdr-annotate/lite`) | 9 commits (rotator, ai-memory-kit, skills, sync_pi) | low | **keep-ours** + drop that 1 line |

## Decisions that block T4 (merge execution)

- **D-A hashline-edit-pro**: upstream removes it entirely (bridge + pi-tool-display
  lines + settings entries). Your commit `8f21d7b` exists to stop gentle-pi
  quiet-tools colliding with hashline-edit. If you drop hashline (follow upstream)
  your workaround becomes dead code to remove; if you keep it, reject the upstream
  removals. *Rec: follow upstream (drop hashline + your workaround) unless you
  actively use hashline-edit's editor.*
- **D-B auth extension**: upstream swaps `pi-anthropic-oauth` -> `gotgenes/pi-anthropic-auth`.
  Affects Anthropic login. *Rec: adopt pi-anthropic-auth (upstream's direction),
  test login once after.*
- **D-C dropped extras**: upstream removed `visual-explainer`, `@plannotator/pi-extension`,
  `pi-orcarouter`, `@benvargas/pi-openai-fast`. *Rec: KEEP visual-explainer and
  plannotator (you use them); let orcarouter/openai-fast go unless needed.*
- **D-D default model**: keep YOURS (`opencode-go/deepseek-v4.1-flash`, high/max) —
  upstream's `openai-codex/gpt-5.6-sol` is their preference. *Rec: keep-ours.*
- **D-E adopt new features**: `pi-codex-context` package + `compaction.enabled`.
  *Rec: adopt both (this is the "context management" upstream added).*
- **D-F advisor mode**: upstream moves advisor to `opencode-go/deepseek-v4-flash`;
  you kept it on openrouter. You already run opencode-go elsewhere. *Rec: take
  upstream advisor provider, keep your `opencode-max` mode, fix the whitespace glitch.*

## Decisions taken (user)

- D-A = follow upstream: drop hashline-edit-pro + bridge + config + the 8f21d7b workaround.
- D-B = adopt `gotgenes/pi-anthropic-auth`, drop `pi-anthropic-oauth`.
- D-C = match vekexasia's plugin list (drop visual-explainer, plannotator,
  orcarouter, openai-fast); take his model/role updates; **do NOT touch the
  user's tuxevil-rotator gemini provider + gemini aliases**. Also preserve the
  user's opencode-go provider/aliases/modes and the AGENTS.md Language directive.
  Open flag: keep the user's `cockpit-tools-sync` package (personal integration).
- D-E/D-F = adopt `pi-codex-context` + `compaction.enabled` + advisor on
  `opencode-go/deepseek-v4-flash`, keeping the user's `opencode-max` mode.

## Recommended merge sequence

Do NOT `git merge upstream/master` blind (it conflicts on 5 hot files and can
clobber your aliases). Instead:

1. Branch: `git switch -c sync/vekexasia-upstream`.
2. Clean bring-ins first (low risk), via `git checkout upstream/master -- <path>`:
   `pi/agent/packages/pi-codex-context`, `pi/agent/packages/pi-omplike-advisor`,
   `pi/agent/extensions/compact-tools.ts`, `herdr/config.toml`,
   `nvim/lua/config/keymaps.lua`.
3. Manual-merge the JSON hot files by hand (keep your aliases/skills/provider,
   apply upstream's rename/removals per D-A..D-F): `pi-extensible-workflows/settings.json`,
   `settings.json`, `models.json`, `modes.json`, `package.json`, `AGENTS.md`.
4. Apply D-A removals only if D-A = follow-upstream.
5. `cd pi/agent/npm && npm install` to regenerate the lock.
6. `setup_env.sh`: keep-ours, delete the plannotator-lite line.
7. Validate: `bash -n setup_env.sh`; JSON parse all edited files; launch a
   `workflow` and confirm roles + aliases resolve.

## Files that MUST reach ~/.pi/agent for workflow roles/aliases

`pi/agent/pi-extensible-workflows/settings.json` (modelAliases + skills + extensions)
and `pi/agent/pi-extensible-workflows/roles/*.md` (7 roles: developer, oracle,
researcher, reviewer, scout, summarizer, tests-expert), plus the registries the
aliases dereference: `pi/agent/models.json`, `pi/agent/modes.json`,
`pi/agent/settings.json`, and `pi/agent/AGENTS.md`. The selective rsync (T2)
must copy these while preserving live `auth.json`/`sessions/`.
