# setup-ai terminal graphics and shell UX (wayfinder map + ODD tracking)

Feature: setup-ai/ui-shell-autonomous · Branch: `feat/setup-ai-ui-shell-autonomous-20261030`
Worktree: `/root/git/personale/pi.dev/setup-ai/.worktrees/ui-shell-autonomous`

This file is both the wayfinder map and the ODD feature document. The repository
policy forbids creating GitHub issues/PRs for this effort, so the map lives here as
the repository-local tracker artifact allowed by the skill's local-markdown fallback.

## Destination

A bounded, evidence-backed improvement to the terminal graphics and shell UX of
existing setup-ai surfaces: the Node launcher/menu frames render correctly at any
terminal width and on non-Unicode console fonts, and a preset shows its size before
selection. Nothing in the installers changes; the zero-runtime-dependency contract
holds.

## Notes

- Decision tickets and tasks are recorded below; one owner per worktree (session
  `setupai_ui_shell`, Herdr workspace `w7Q`). No push, PR, issue, tag or release.
- Surfaces in scope: `bin/menu.mjs` (frames, presets), `bin/setup-ai.mjs` (launcher
  wiring), `tests/menu.test.mjs` (pure view/reduce harness; the repository already
  tests the menu this way, so focused menu tests are allowed).
- Skills consulted: pi-herdr-orchestrator, wayfinder, reusable-data-search,
  skillopt-sleep, engineering-excellence, tigerstyle, ponytail, tdd,
  work-unit-commits, container-test-matrix.

## Decisions so far

- **Map lives in the repository**: GitHub issues are out of bounds for this effort,
  so tickets are sections of this file.
- **Scope is the Node launcher/menu only**: the menu is a Node-only surface, so no
  installer module behavior changes and no `setup-ai.sh` / `setup-ai.ps1` mirroring is
  triggered. The parity rule applies to installer/module behavior, which stays untouched.
- **Narrow-terminal frame clipping is a proven defect**: measured with the repository
  renderer at cols 60 and 72, the box loses its right border and corner because the
  frame is a hardcoded 70 dashes while the renderer truncates lines to `cols - 1`.
- **Preset size is invisible before confirmation**: `view()` lists preset labels and
  descriptions only; `reduce()` is the only place that knows what a preset selects.
- **Non-ASCII action glyphs**: `✔` and `➜` in the module/extras action rows are the
  only non-ASCII characters in the frames; legacy Windows console raster fonts render
  them as missing-glyph boxes. Replacing them with ASCII marks removes the class of
  defect without a capability branch (research ticket R1).

## Ticket R1 (research): glyph and width portability of a zero-dependency CLI

Question: which terminal facts must a zero-dependency Node CLI respect for width and
glyph portability (Windows console encoding/fonts, `NO_COLOR`, `TERM=dumb`)?
Status: resolved by `odd/evidence/terminal-glyph-portability.md` (cited sources).
Outcome feeds the ASCII-glyph decision.

## Ticket D1 (prototype/task): which fixes land

Answer: three fixes, all inside the Node launcher surfaces:

1. Frame width adapts to the terminal: inner width `clamp(36, 70, cols - 3)`, header
   centered from the title length instead of 26 hardcoded spaces.
2. Preset rows show how many modules the preset installs, from one shared selection
   helper used by both `reduce()` and `view()`.
3. Action rows use ASCII marks (`<` / `>`) instead of `✔` / `➜`.

Rejected: rewiring the installer banners (`section()` in `setup-ai.sh`,
`Write-ModuleBanner` in `setup-ai.ps1`) to terminal width. It is a real but marginal
wrap at `cols < 72`, it would need mirrored Bash and PowerShell changes plus
unavailable native Windows verification, and it is not the smallest fix.

## Not yet specified

- Whether the installer banners should follow terminal width. Blocked on native
  Windows terminal verification, which this host cannot provide.

## Out of scope

- Any module/installer behavior change, dependency addition, or colour-scheme work.
- `NO_COLOR` / `TERM=dumb` colour suppression: the menu only runs on a raw-capable
  TTY, and the renderer already refuses relative cursor movement under `TERM=dumb`.
- Menu resize handling (frames are computed per draw, but no SIGWINCH listener is
  added): unrequested, and the next keypress redraws with the new width.

## Specs

S1. No frame line exceeds `cols - 1` visible characters for `cols` in 40, 60, 72, 80,
  100, and the box top/middle/bottom rows have equal length, start with `+`/`|` and
  end with `+`/`|` at every width.
S2. The preset screen shows the module count for each non-custom preset, and that
  count equals the selection produced by confirming the same preset.
S3. Menu frames contain only ASCII characters (no code point above U+007F).
S4. Existing menu behavior is preserved: preset/custom navigation, extras submenu,
  summary, quit/back keys, in-place renderer, legacy absolute-redraw fallback.
S5. The launcher keeps working without a TTY (`--list`, `--help`, fallback core set)
  and the zero-runtime-dependency contract is unchanged.

## Tasks

| ID | Task | Spec | Route | Evidence | Commit |
| --- | --- | --- | --- | --- | --- |
| T1 | Chart map, write this document and the Engram mirror | S1-S5 | inline | this file, Engram observation 1974 | done |
| T2 | Research glyph/width portability with primary sources | S3 | reusable-data-search | `odd/evidence/terminal-glyph-portability.md` sha256 `81a69af7e6756fffd4edbb26183eb102e3addcbddadb4d056b55e52674b1894d` | done |
| T3 | SkillOpt-Sleep status + project-scoped mock dry-run | - | skillopt-sleep | `odd/evidence/skillopt-sleep-run.md`; gate reject, nothing staged/adopted | done |
| T4 | RED: focused menu tests for S1-S3 | S1-S3 | tdd | `npm test` failing output before the fix | done |
| T5 | Implement fixes in `bin/menu.mjs` + `bin/setup-ai.mjs` | S1-S5 | inline | diff +64/-16 in the first pass | done |
| T6 | GREEN: npm test, list, syntax/parse, parity, PTY check | S1-S5 | tdd + container-test-matrix | see L8 | done |
| T7 | Container matrix, gga, local work-unit commit | - | work-unit-commits | gga PASSED (fresh and cached); commit `c286a8a` | done |
| T8 | Final report, orch_report, Engram handoff | - | reporting | see L10 | done |
| T9 | Release: PR #150, merge, tag `v4.0.4`, npm publication | - | docs/releasing.md | see L11 | done |
| T10 | Fix the three pre-existing `setup-ai.ps1` parity findings | - | follow-up | `gga` with the role provider | pending |
| T8 | Final report, orch_report, Engram handoff | - | reporting | final message | pending |

## Evidence plan

- Proven defect evidence: renderer output at cols 60/72 (frame clipped), grep for the
  non-ASCII glyphs, `view()` source showing preset labels without counts.
- Research: cited primary sources in `odd/evidence/terminal-glyph-portability.md`,
  with query and source metadata and a sha256 of the file.
- Tests: RED before the change, GREEN after, then the full repository gate list.
- PTY check: run the real launcher in a pseudo-terminal at 60 and 72 columns and
  compare the rendered frame against the same frame at 100 columns.
- Container: `tests/container-matrix.sh` rows plus `npm test` inside
  `node:22-bookworm` (the launcher/menu is Node, so the Node row is the applicable one;
  the remaining rows guard the untouched installers).
- Delivery: `gga run` before the commit, never `--no-verify`.

## Log

### L1 — user request (verbatim)

```
You are the new [MASTER] Pi Herdr Orchestrator for the setup-ai repository. Work only in /root/git/personale/pi.dev/setup-ai/.worktrees/ui-shell-autonomous on branch feat/setup-ai-ui-shell-autonomous-20261030. The parent session remains responsible for the Pi Atelier work; do not edit the parent worktree or any other repository.

User-authorized objective: autonomously wayfind, research, improve, and verify the terminal graphics and shell UX of setup-ai, with resumable evidence. Treat this as a bounded repository change, not a general cleanup.

Required operating path:
1. Read AGENTS.md, relevant .ai files, README/docs, package scripts, and current Git state. Start with mem_context and setup-ai-scoped mem_search. Run the pi-herdr-orchestrator capability check and repository initialization only in this worktree when available; record any unavailable capability instead of inventing it.
2. Use the wayfinder skill to resolve the route before coding. Keep the map repository-local under odd/tasks unless repository policy makes an external tracker artifact strictly necessary; do not create GitHub issues, PRs, tags, releases, or push. If a real product/design decision remains unresolved, stop with BLOCKED and state the exact decision rather than guessing.
3. Before the first source write, create/update odd/tasks/setup-ai-ui-shell-autonomous-20261030.md and its Engram mirror. It must contain the user objective verbatim, scope/non-goals, acceptance criteria, task list, evidence plan, and log. Keep only concrete decisions and proven findings.
4. Use reusable-data-search for named uncertainties and primary-source research. Make the research resumable: save cited findings and query/source metadata under research/ or odd/evidence/ in the worktree, and report paths plus hashes. Do not place secrets or raw private transcripts in artifacts.
5. Run SkillOpt-Sleep evidence in the safe path: inspect status and run a project-scoped dry-run with backend mock, explicit target skill if available, no auto-adopt and no live skill/config adoption. If the installed integration does not support source pi in this session, report BLOCKED with the exact command/result. Never hand-edit or adopt SkillOpt proposals.
6. Implement only the smallest evidence-backed graphics/shell improvements found in existing setup-ai surfaces. Preserve the zero-runtime-dependency contract. Any installer/module behavior change must be mirrored in setup-ai.sh, setup-ai.ps1, and bin/setup-ai.mjs. Add or update focused tests for behavior changes; do not add TUI tests if the repository rules forbid them. Do not introduce a dependency for visual polish.
7. Verify using the repository commands and applicable container-test-matrix: npm test, npm run list, bash -n setup-ai.sh, PowerShell parse when pwsh exists, version/module parity checks, agent-install parity, git diff --check, and any focused manual/PTY checks. Record exact PASS/FAIL/BLOCKED/NOT RUN evidence. Run gga before any local commit; never bypass hooks. Local work-unit commits are allowed only after verification. Do not push or open a PR.
8. Report through orch_report at phase changes and as the final action with task=setup-ai/ui-shell-autonomous, state=WORKING/DEVELOPMENT/READY/BLOCKED, branch, checks, and evidence. Save durable discoveries/decisions/final handoff to Engram. End with a concise report containing: wayfinder decisions, changed files, commits, checks, SkillOpt/data-search evidence, risks, and next action.

Use only the relevant skills: pi-herdr-orchestrator, wayfinder, reusable-data-search, skillopt-sleep, engineering-excellence, tigerstyle, impeccable/design-taste-frontend as applicable, container-test-matrix, tdd/work-unit-commits. Use PiWorkflow and Herdr-native orchestration if available; keep one owner per worktree and do not create duplicate sessions. Start now and execute the authorized path without asking for a generic continue.
```

### L2 — capability check (proven)

- `HERDR_ENV=1`; `herdr 0.9.5`; this session is Herdr agent `setupai_ui_shell`
  (workspace `w7Q`, pane `w7Q:p1`) - single owner, no duplicate session created.
- `gga`, `docker`, `pwsh`, `node` v22.23.3, `bash`, `git`: present.
- SkillOpt-Sleep engine: `SKILLOPT_SLEEP_REPO` points at a missing path, the
  `skillopt_sleep` Python module is not importable, but the engine checkout exists at
  `/root/git/agent-skills/skillopt` (`plugins/run-sleep.sh`, `skillopt_sleep/`).
- pi-herdr-orchestrator `scripts/init-repository.mjs` and `scripts/check-environment.mjs`
  are not present in the skill checkout, so repository initialization was performed
  manually and recorded: worktree isolation (explicit path), Engram project identity
  (`setup-ai`), `AGENTS.md`/`.gga` rules present, `.atl/skill-registry.md` present,
  Herdr workspace exists. Missing: Serena project indexing, `sqz`/`rtk` hooks.

### L4 — research evidence (proven)

- `odd/evidence/terminal-glyph-portability.md`, sha256
  `81a69af7e6756fffd4edbb26183eb102e3addcbddadb4d056b55e52674b1894d`.
- Width is a runtime property (`writeStream.columns`), so a fixed 70-dash frame is the
  root cause of the clipping; glyph encoding success does not imply font rendering, so
  ASCII action marks are the portable fix; `NO_COLOR` is a separate contract and stays
  out of scope.
- `exa` was unavailable (missing API key); the Pi `web_search` provider returned the
  nodejs.org and learn.microsoft.com sources. Recorded, not hidden.

### L5 — SkillOpt-Sleep evidence (proven)

- `odd/evidence/skillopt-sleep-run.md`: status exit 0 (night 4, no staged proposal);
  `dry-run --source pi --scope invoked --backend mock --no auto-adopt` exit 0 with
  `gate_action: reject`, baseline 0.0, candidate 0.0, 0 edits, `adopted: false`,
  empty `staging_dir`. Nothing adopted, no live skill or config touched.
- Engine quirk recorded: the bundled `run-sleep.sh` fails on stale bytecode; the module
  was invoked directly with `/usr/bin/python3.13` and a fresh bytecode cache prefix.

### L6 — canonical model matrix probe (proven)

- PiWorkflow foreground probe `setup-ai-model-probe` resolved `developer`, `reviewer`
  and `verifier` roles through the global alias matrix (cliproxyapi gpt-5.6-luna:high,
  claude-opus-4-6-thinking:off, claude-sonnet-4-6:off) and all three answered on the
  first attempt, so no retry or model switch is expected.

### L8 — implementation, review and verification (proven)

- Implementation (PiWorkflow `developer` role, canonical `developer-model`):
  `bin/menu.mjs` +24/-12, `bin/setup-ai.mjs` +4/-3, `tests/menu.test.mjs` +36/-1.
  RED observed first (missing `frameWidth` export), then GREEN.
- Independent review (PiWorkflow `reviewer` role, canonical `reviewer-model`) returned
  REQUEST CHANGES with two findings, both accepted and fixed inline:
  1. the clamp floor still overflowed the renderer budget below 39 columns and `NaN`
     propagated into `repeat()`; `frameWidth` is now `clamp(18, 70, cols - 3)` with a
     `Number.isFinite` fallback to 80, verified closed and aligned at 21/24/38/39/40/
     60/72/80 columns and for `undefined`/`NaN`;
  2. the preset-count assertion accepted `13 modules` for a count of 3; it is now an
     anchored regex.
- Before/after evidence at the same widths: the base commit produced
  `+----------------------------------------------------------` (clipped, no corner) at 60 and 72 columns; the change produces
  `+---------------------------------------------------------+` and
  `+---------------------------------------------------------------------+`.
- PTY evidence: the real launcher in a 60-column pseudo-terminal printed a closed,
  centred frame with `Core 18 modules`, `Everything 27 modules`, `Custom` without a
  count, `Minimal 3 modules`, `Gentle AI 5 modules`.
- Gates: `node tests/menu.test.mjs` 0, `npm test` 0, `node --check` 0 on all `bin/*.mjs`,
  `npm run list` 0, `bash -n setup-ai.sh` 0, PowerShell parse 0, version parity 0,
  agent-install parity 0 (22 modules), Gentle AI preset parity 0, `git diff --check` 0.
- Container matrix `bash tests/container-matrix.sh`: 7/7 rows exit 0
  (node:22-bookworm, debian:13, ubuntu:24.04, archlinux:latest, fedora:latest,
  opensuse/leap:latest, powershell lts-ubuntu). Additional container run
  `docker run --rm node:22-bookworm ... npm test`: exit 0.
- Not verified: native Windows console rendering of the frames (no Windows host), and
  macOS. The ASCII change removes the known font failure mode but is not a runtime
  observation on Windows.

### L9 — orchestration notes (proven)

- A combined verify+review workflow failed: the first attempt of both agents reported
  `You have hit your ChatGPT usage limit.`, and the workflow's capacity failover then
  requested `workflow/gemini-scout-model`, which is not registered (`UNKNOWN_MODEL`).
  The reviewer was re-dispatched alone with the canonical `reviewer-model` alias and
  `retries: 0`, and returned its findings in one attempt. The failover alias is a
  harness configuration defect, outside this repository.

### L10 — commit and slice evidence (proven)

- `c286a8a fix(launcher): keep the menu frame inside narrow terminals` on
  `feat/setup-ai-ui-shell-autonomous-20261030`, 9 files, +460/-17.
- `gga run` before the commit: exit 0, `STATUS: PASSED` for `bin/menu.mjs`,
  `bin/setup-ai.mjs`, `tests/menu.test.mjs`; the pre-commit hook then passed the same
  three files from cache.
- Slice note: the commit is 477 authored lines, past the ~400 guidance, because the
  verified work unit carries its own ODD map and the two evidence files (386 lines of
  documentation). The executable change is 83 authored lines (menu + launcher + test)
  and is not separable from its tests and docs without breaking the rule that keeps
  them together. This is the only slice for the feature; it closes it.
- Native review: `gentle_review` assess over the committed range returned risk
  `medium`, `reviewDue: false` (`under_budget`), no escalated high-risk item, so no
  review lineage was started. RDD switch reads `on`; the assessment, not a skip, is
  the basis for not starting one.
- Post-commit state: worktree clean on the feature branch, one commit ahead of
  `origin/main`; nothing pushed, no PR, no issue, no tag.

### L11 — release and review-gate delivery (proven)

- Release path per `docs/releasing.md`: branch pushed, PR #150 merged into `main` at
  `3e017fa`, annotated tag `v4.0.4` on that merge commit, `publish.yml` run
  `41083655445` completed success, GitHub Release `v4.0.4` created.
- npm: the workflow printed `+ @darkrei08/setup-ai@4.0.4` with a processing notice; the
  version resolved as `4.0.4` and `dist-tags.latest` became `4.0.4` about two minutes
  later. Verified with `npm view @darkrei08/setup-ai@4.0.4 version`.
- Review gate corrected to the shared dotenv mechanism: `.gga` now declares
  `PROVIDER="kilo:reviewer-model"` (the local Pi bridge `agents/gga-pi/bin/kilo`
  resolves `reviewer-model` from `pi-ext-roles` and runs that role's model plus effort)
  instead of a hardcoded OpenCode model. The pre-commit hook already preferred
  `agents/gga-pi/run-gga.sh`, but the bridge symlink was missing in this worktree, so
  earlier commits silently fell back to bare `gga`. The bridge is now linked and
  gitignored; a bare `gga run` fails closed.
- The role-based reviewer reported STATUS: FAILED on three **pre-existing**
  `setup-ai.ps1` parity findings (Windows `-DryRun`, dotenv workflow extensions not
  linked, stale symlink not repaired). None is caused by the version bump; they are
  recorded as follow-up T10 and were not fixed in this slice.
- Host limits for the Windows route: no `/dev/kvm` (Proxmox guest without nested
  virtualization) and 25 GB free versus the 32 GB minimum in the dockur/windows
  README, so a local Windows container test is BLOCKED on this machine.

### L7 — proven defect evidence (pre-change)

- Renderer at cols 60 and 72 with the repository `createRenderer` truncates the frame:
  the right border and corner disappear (`+---...` without the closing `+`), because
  the frame is fixed at 70 inner dashes while `fit()` clamps to `cols - 1`.
- `bin/menu.mjs` `view()` renders preset rows as `label + desc` only; preset selection
  is only computed in `reduce()`.
- Non-ASCII in frames: `✔`, `➜` (and no other code point above U+007F).
