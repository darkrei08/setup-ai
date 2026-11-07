# setup-ai software audit — 2026-11-07

Repository: `@darkrei08/setup-ai` 4.0.5, audit tree branch `audit/installed-software`, base `c596ee9`.
Scope: everything the installer puts on a machine, traced from the repository itself.
Nothing was executed, installed, or committed. Every claim below carries `file:line` from
this tree; upstream-liveness claims carry the command that was run.

---

## 1. Summary and recommendation

setup-ai installs or claims 41 distinct items across 27 modules. 21 are actively owned and
needed, 8 are installed twice by two different places inside the same run, 3 are obsolete,
and 9 need a product decision before anything is removed.

The redundancy is not spread evenly. Almost all of it comes from one structural fact:
**two installers own the same toolchain.** `mod_dotenv` (`setup-ai.sh:1957-2084`) clones
`darkrei08/dotenv` and runs its `setup_env.sh`, which installs bun, `aimem`,
`tree-sitter-cli` and the upstream skill stack — the same things `mod_bun`,
`mod_ai_memory` and `mod_skills` install in the same run. setup-ai then carries four
in-place `sed`/`python` patches (`setup-ai.sh:1980-2070`) purely to make the dotenv copies
behave. That is the single largest source of code and of failure surface in the installer.

Recommended order of work, cheapest first:

1. **Delete the `sqz` module.** It only verifies a binary setup-ai never installs, and no
   `sqz` package exists on npm. The module can never pass on a fresh machine.
   (`setup-ai.sh:1809-1825`, `setup-ai.ps1:1378`, `docs/modules.md:42-44`)
2. **Collapse the three `pi-extensible-workflows` installs into one.**
   `setup-ai.sh:2339`, `:2357`, `:2393` install the same pinned package into three
   different roots in one run, and `link_dotenv_workflow_extensions` (`:2280-2315`) exists
   only to reconcile two of them.
3. **Give each duplicated tool one owner.** Pick dotenv *or* setup-ai for bun, `aimem`,
   `tree-sitter-cli` and the upstream skill stack. Doing so deletes the corresponding
   patches (`:1987-2057`) and roughly 90 lines of grep/patch machinery.
4. **Remove `neovim` and `go` from the `base` package lists.** `mod_lazyvim` and `mod_go`
   already install both, on every package manager.
5. **Move the unrelated global npm packages out of `extras`.** `typescript-express-starter`
   and `@alibaba-group/open-code-review` (`:3879-3880`) are web-dev and AI-code-review
   tools installed by the module whose `MODULES` description is "optional shared Taste,
   Humanizer, HeroUI, Emil design, MJML email and Impeccable skills".

Expected effect: three modules removed or merged, one patch block deleted, one
`MODULE_DESC`/`--list`/menu row set shorter, and no loss of capability that this
repository can demonstrate. Nothing recommended here removes something the repository
shows being consumed, with one exception called out as a decision (`llmlingua`).

---

## 2. Method

- Registries read first: `bin/setup-ai.mjs:34-75` (launcher `MODULES`/`EXTRA_ITEMS`),
  `setup-ai.sh:821-824` (`MODULE_ORDER`, `GENTLE_AI_PRESET`),
  `setup-ai.ps1:1186-1196` (`$ModuleOrder`, `$ModuleDesc`).
- Every `mod_*` body was read and its install commands extracted; pinned versions come
  from the top-level defaults (`setup-ai.sh:79-101`).
- Skill installs are one declarative registry (`setup-ai.sh:110-122`, mirrored at
  `setup-ai.ps1`), so skill items are traced there instead of per module.
- Upstream liveness checks were read-only: `git ls-remote` for the git-sourced items and
  `npm view <pkg> version` for the npm-sourced ones. Results are quoted inline.
- The prior machine dump `docs/software-inventory-2026-10-30.md` (untracked, main
  checkout) was read as context only, for what a real machine ends up holding.

---

## 3. Full inventory

Buckets: **(a)** owned and needed, **(b)** redundant, **(c)** obsolete, **(d)** needs a decision.

| # | Item | Installed by | Source (bash; ps1 mirrors) | Bucket | Action |
|---|------|--------------|----------------------------|--------|--------|
| 1 | base packages: build-essential/gcc, rsync, curl, wget, git, unzip, tar, ca-certificates, gnupg, jq, python3, neovim, gh, go, imagemagick, clipboard tools, x11 | `mod_base` | `setup-ai.sh:1485-1531` (brew list `:1489`, apt list `:1497-1498`, dnf `:1509-1511`, pacman `:1513-1529`, zypper `:1523-1525`) | b | drop `neovim`, `go`/`golang-go` (owned by #5, #6) |
| 2 | nala (apt frontend) | `mod_base` | `setup-ai.sh:1506-1508` | a | none |
| 3 | Node.js v22 (nvm on Unix) + `npm@latest` | `mod_node` | `setup-ai.sh:1683-1720` | a | none |
| 4 | Bun runtime | `mod_bun` | `setup-ai.sh:1749-1767` | b | one owner with dotenv's bun install (`:1987-1994`) |
| 5 | Go toolchain | `mod_go` | `setup-ai.sh:1932-1956` (`:1943` brew, `:1947` apt) | b | one owner with #1 |
| 6 | Neovim (x86_64 tarball, or brew/apt fallback) + LazyVim starter | `mod_lazyvim` | `setup-ai.sh:1610-1682` (`:1625` tarball, `:1641-1644` fallback, `:1672` starter clone) | b | one owner with #1; decide nvim-config owner vs dotenv |
| 7 | `tree-sitter-cli` | dotenv `setup_env.sh`, reached through `mod_dotenv`, patched by setup-ai | `setup-ai.sh:2020-2070` | d | decide owner; today setup-ai maintains a patch for a tool it does not install |
| 8 | `python3` / `uv` / `npx` prerequisites | not installed — `require_command` only | `setup-ai.sh:544-560`, `:1827`, `:1863` | a | none (documented prerequisite) |
| 9 | TOON CLI `@toon-format/cli@2.3.0` (bun global) | `mod_toon` | `setup-ai.sh:83`, `:1768-1789`; consumed by `vendor/wz-ai-context-formats.cjs:19-22` | a | keep; refresh the pin (see §6) |
| 10 | LEA vendored formatter (`wz-ai-context-formats.cjs`) | `mod_lea` | `setup-ai.sh:1790-1808`, `vendor/wz-ai-context-formats.cjs` | a | none |
| 11 | `sqz` CLI | `mod_sqz` — verifies only, never installs | `setup-ai.sh:1809-1825` (expected `sqz 1.9.0` at `:1818`), `setup-ai.ps1:1378` | c | delete module |
| 12 | `graphifyy[mcp]` + `graphify-mcp` | `mod_graphify` | `setup-ai.sh:1860-1899` (`:1873` `uv tool install`) | a | keep; consider a pin (see §6) |
| 13 | LLMLingua venv: `llmlingua==0.2.2` + `torch==2.6.0+cpu` (~853 MiB) | `mod_llmlingua` | `setup-ai.sh:88-95`, `:1826-1859` | d | decide: keep opt-in or drop |
| 14 | pi CLI | `mod_pi` | `setup-ai.sh:1900-1931` | a | none |
| 15 | Pi packages from a manifest | `mod_pi_packages` | `setup-ai.sh:2444-2488`, `pi-packages.example.txt` | a | none |
| 16 | Claude Code | `mod_claude_code` | `setup-ai.sh:2514-2574` (`:2556` npm fallback) | a | none |
| 17 | Codex CLI | `mod_codex` | `setup-ai.sh:3211-3233` | a | none |
| 18 | Antigravity CLI (`agy`) | `mod_antigravity` | `setup-ai.sh:3234-3253` | a | none |
| 19 | opencode (`opencode-ai`) | `mod_opencode` | `setup-ai.sh:3304-3421` (`:3316` brew tap, `:3385` npm fallback) | a | none |
| 20 | herdr terminal multiplexer | `mod_herdr` | `setup-ai.sh:2489-2513` | a | none |
| 21 | `herdr` agent skill | registry entry | `setup-ai.sh:111` | a | none |
| 22 | Upstream skill stack: mattpocock (triage, grill-me, grilling, wayfinder, domain-modeling, prototype, research), pedronauck `typescript-advanced`, humanlayer `show-me` | `mod_skills` | `setup-ai.sh:2234-2279` + registry `:112-114` | b | one owner with dotenv's copy (`:2253-2254`) |
| 23 | `pi-extensible-workflows` | `mod_pi_workflows` — three roots | `setup-ai.sh:2339` (pi install), `:2357` (`PI_EXTENSIONS_DIR`), `:2393` (`DOTENV_EXT_DIR`) | b | collapse to one root |
| 24 | dotenv workflow extension symlink/barrel | `link_dotenv_workflow_extensions`, called from `mod_pi_workflows` | `setup-ai.sh:2280-2315` | b | disappears with #23 |
| 25 | `gentle-ai` CLI (`gga` ecosystem configurator) | `mod_gentle_ai` | `setup-ai.sh:2983-2991` | a | none |
| 26 | `gentle-pi` (Pi harness for gentle-ai) | `mod_gentle_ai` | `setup-ai.sh:3174` | a | none |
| 27 | `pi-mcp-adapter` | `mod_gentle_ai` | `setup-ai.sh:3182` | d | decide vs harness-native MCP |
| 28 | `ai-memory-kit` / `aimem` CLI + templates (`v0.1.0`) | `mod_ai_memory`, and again by dotenv `setup_env.sh` | `setup-ai.sh:79-81`, `:1542-1581`; dotenv copy patched at `:1996-2018` | b | one owner |
| 29 | SkillOpt-Sleep fork (clone `main`, editable pip install) | `mod_skillopt_sleep` | `setup-ai.sh:82-87`, `:1582-1609` | a | none (floating branch noted in §6) |
| 30 | dotenv dotfiles + `setup_env.sh` + 4 in-place patches | `mod_dotenv` | `setup-ai.sh:1957-2084`, patches `:1980-2070` | d | decide what dotenv still owns after #4/#22/#28 |
| 31 | Engineering Excellence skill | `mod_ee` | `setup-ai.sh:2197-2233` | a | none |
| 32 | Extras skills: `design-taste-frontend`, `humanizer`, `heroui-react`, `emil-design-eng` + `animation-vocabulary` + `apple-design`, `email-html-mjml` | `mod_extras` / `install_extras_registry` | `setup-ai.sh:116-121`, `:3838-3855`, `install_extras_skill:3666`, `link_extras_skill:3708` | a | none |
| 33 | Impeccable | `mod_extras` | `setup-ai.sh:3871` | d | decide: separate module or drop |
| 34 | HyperFrames skills update | `mod_extras` | `setup-ai.sh:3872` | d | same |
| 35 | `typescript-express-starter` (npm global) | `mod_extras` | `setup-ai.sh:3879` | d | decide: unrelated to extras |
| 36 | `@alibaba-group/open-code-review` (npm global) | `mod_extras` | `setup-ai.sh:3880` | d | decide: unrelated to extras |
| 37 | CLI-Anything Pi extension at pinned `34f5195` | `install_cli_anything` from `mod_extras` | `setup-ai.sh:139`, `:3799-3837` | a | keep; re-pin when a release exists |
| 38 | cockpit-tools (AppImage / GitHub release) | `mod_cockpit` | `setup-ai.sh:3422-3508` | a | none (opt-in) |
| 39 | CLIProxyAPI + CPA Usage Keeper Compose stack (`:latest` images) | `mod_cliproxyapi` | `setup-ai.sh:3509-3665`, `templates/cliproxyapi/*/docker-compose.yml:5-6,17,28` | d | decide a tag policy |
| 40 | Legacy `tuxevil-rotator` uninstall path | `uninstall_catalog` + `uninstall_remove_legacy_rotator_unit` | `setup-ai.sh:4087-4090`, `:4280-4321`, `tests/legacy-rotator-uninstall.sh` | c | drop once machines are migrated |
| 41 | Quiet-tools switch and rpiv-question migration cleanups | `mod_gentle_ai` | `setup-ai.sh:2613-2656`, `:2657-2731`, `:2732-2845` | c | drop when the affected versions are gone |

Counts: **(a) 21, (b) 8, (c) 3, (d) 9** — 41 items.

---

## 4. Redundant findings (b)

### 4.1 `pi-extensible-workflows` is installed three times per run

```
setup-ai.sh:2339  install_pi_package_owned "pi-workflows" "npm:pi-extensible-workflows@${PI_WORKFLOW_VERSION}"
setup-ai.sh:2357  run_cmd "pi-workflows-node" npm install --save-exact ... "pi-extensible-workflows@${PI_WORKFLOW_VERSION}"
setup-ai.sh:2393  run_cmd "dotenv-workflows"   npm install --save-exact ... "pi-extensible-workflows@${PI_WORKFLOW_VERSION}"
```

One package, one version, three install roots, each with its own readback assertion
(`:2364-2372`, `:2397-2410`). `link_dotenv_workflow_extensions` (`:2280-2315`) then exists
to repoint a symlink/barrel between two of those roots. `pi-packages.example.txt` even
documents the split ("`pi-extensible-workflows` is intentionally NOT listed here: the
`pi-workflows` module owns that package"), which shows the intent is one owner — the
implementation has three.

Removal risk: low. Simplification: high — removes one install/verify block and the whole
link reconciler, and shrinks the npm 12 `.npmrc` handling from three roots to one.
Open question for the merge target: which root does `pi update --extensions` actually
reinstall from (unverified outside this repo, see §7).

### 4.2 The upstream skill stack is installed twice

`setup-ai.sh:2232-2234` states it in the source:

```
# Installs the shared skill stack via `npx skills add`; the upstream dotenv
# setup also installs its own copy, and both paths are idempotent.
```

The loop at `:2250-2272` runs `skills@latest add` per source per detected agent, and
`mod_dotenv` (`:1957-2084`) runs `setup_env.sh` in the same run. Both are called
idempotent, which is true of `skills add` but still means two network installs of the
same seven skills for up to five agents per run, and two places to update when a source
is renamed.

Removal risk: low-medium (the dotenv copy is in another repository, so removing the
setup-ai side needs a one-line rationale recorded there). Simplification: medium.

### 4.3 bun, `aimem` and `tree-sitter-cli` are installed twice, and setup-ai patches the copy it does not own

- bun: `mod_bun` (`:1749-1767`) installs it; dotenv's `setup_env.sh` installs it too, and
  setup-ai rewrites that line in place at `:1987-1994`.
- `aimem`: `mod_ai_memory` (`:1542-1581`) installs it; dotenv installs it too, and
  setup-ai rewrites that line at `:1996-2018`.
- `tree-sitter-cli`: dotenv installs it; setup-ai rewrites the line at `:2020-2057` to
  force `--foreground-scripts --include=optional` and to verify the real binary.

Three `grep_probe` + `sed`/`python` patches in the installer's hot path exist only because
of this double ownership, each one a mutator of an external checkout with its own
"upstream changed unexpectedly" failure mode. Choosing one owner per tool deletes the
patch and the duplicate install together.

Removal risk: medium (the dotenv checkout is the user's dotfiles; the patch removal must
land only after the corresponding deterministic install exists). Simplification: highest
of all findings — this is the largest block of code in `mod_dotenv`.

### 4.4 `base` installs what `lazyvim` and `go` install

```
setup-ai.sh:1489  brew install git curl wget jq unzip gnupg python neovim gh go imagemagick
setup-ai.sh:1497  ... neovim gh golang-go imagemagick ...
setup-ai.sh:1641  brew) run_cmd "lazyvim" brew install neovim
setup-ai.sh:1644  sudo apt-get install -y neovim
setup-ai.sh:1943  run_cmd "go" brew install go
setup-ai.sh:1947  apt-get) run_cmd "go" sudo apt-get install -y golang-go
```

Same packages, two modules, four package managers. `mod_go` and `mod_lazyvim` exist for
version control of their tool, so the `base` entries are the ones to drop. Note the
interaction: `mod_lazyvim`'s tarball path runs before its `require_command nvim` fallback
(`:1658`), so removing `neovim` from `base` makes that fallback load-bearing — it is
already written for exactly that case.

Removal risk: low. Simplification: medium (two package lists shrink, one fallback path
becomes the only path and should be exercised in the container matrix).

### 4.5 Neovim configuration has two possible owners (evidence insufficient to call it a duplicate)

`mod_lazyvim` clones `LazyVim/starter` into `${config_dir}` only when that directory is
absent (`:1663-1680`), and `mod_dotenv` brings `darkrei08/dotenv`, which ships an `nvim/`
tree (visible in the prior inventory dump, `docs/software-inventory-2026-10-30.md:1764`).
Whichever runs first wins, silently. Not classified as (b) because the dotenv checkout
was out of read scope; recorded as a decision in §5.

---

## 5. Obsolete findings (c)

### 5.1 `sqz` module — dead in both directions

```
setup-ai.sh:1811-1813  require_command sqz
setup-ai.sh:1818       [[ "${version}" == "sqz 1.9.0" ]]
setup-ai.ps1:1378      if ($script:SetupAiSqzVersion -ne 'sqz 1.9.0') { throw ... }
docs/modules.md:42-44  "sqz is declared-only by setup-ai: it is not downloaded or replaced."
```

Verification: `npm view sqz version` → `E404 Not Found - GET https://registry.npmjs.org/sqz`.
The module therefore (1) never installs anything, (2) fails `require_command` on any
machine that does not already have a `sqz` binary, and (3) pins a version string no
installer in this repository can produce. It is an `--only sqz` no-op-with-failure and an
option in the menu.

Removal risk: low. Simplification: high for its size — one module row in `MODULE_ORDER`
(`:821`), `$ModuleOrder` (`setup-ai.ps1:1186`), `MODULE_DESC`/`$ModuleDesc`, the launcher
`MODULES` entry (`bin/setup-ai.mjs:39`), a `tests/context-tools.test.mjs` case, an
`docs/install-matrix.md` row, and the parity test.

### 5.2 Legacy `tuxevil-rotator` uninstall path

`setup-ai.sh:4087-4090` keeps `legacy-rotator` entries and `:4280-4321` implements them;
`CHANGELOG.md` 4.0.2 records `cliproxyapi` replacing the module. This is deliberate
migration code ("Legacy entries are uninstall-only"), correct to keep while machines still
carry the old unit, and safe to delete once they do not. Classified obsolete, action
deferred rather than immediate: deleting it now would strand the `tuxevil-rotator.service`
unit on migrated machines.

Removal risk: medium (irreversible for uninstalled machines). Simplification: low-medium.

### 5.3 Quiet-tools switch and rpiv-question migration cleanups

`setup-ai.sh:2613-2656` (`remove_stale_quiet_tools_switch`), `:2657-2731`
(`remove_stale_rpiv_question_extension`), `:2732-2845` (`handle_quiet_tools_conflict`).
These remove shell-profile lines and Pi settings entries written by earlier setup-ai
versions. Same disposition as 5.2: obsolete by design, retained for migration.

---

## 6. Decisions I could not make

1. **`llmlingua` (#13).** 853 MiB of CPU PyTorch for `llmlingua==0.2.2`, opt-in
   (`bin/setup-ai.mjs:38`). Nothing in this repository invokes it; the consumer lives in
   `pi-extensible-workflows` or nowhere. Missing evidence: a consumer. If none, delete the
   module, which is the single biggest byte reduction available.
2. **TOON pin (#9).** `TOON_VERSION=2.3.0` (`setup-ai.sh:83`), while `npm view
   @toon-format/cli version` returns **4.4.0**. The CLI is genuinely consumed
   (`vendor/wz-ai-context-formats.cjs:19-22` shells out to `toon`), so the module is not
   obsolete, but the pin is two majors stale. Missing evidence: whether the vendored
   formatter's `toTOON`/`fromTOON` output still round-trips through 4.x. Needs one
   compatibility check, not a guess.
3. **`graphifyy` is unpinned (#12).** `uv tool install "graphifyy[mcp]"` (latest 0.10.0 at
   audit time). Every other tool in the context group is pinned. Decision: pin or
   consciously float.
4. **`pi-mcp-adapter` (#27).** Installed so `gentle-pi` appears in Pi's `/mcp`
   (`setup-ai.sh:3168-3189`, `docs/pi-extensions.md`). Whether the current Pi runtime
   needs the adapter or has native MCP support is not answerable from this repository.
5. **`impeccable`, `hyperframes`, `typescript-express-starter`,
   `@alibaba-group/open-code-review` (#33-#36).** All four are documented as deliberate
   (`docs/modules.md:206-213`, `CHANGELOG.md` 4.0.0 / issue #98), and the last two are
   web-development and AI-code-review tools with no relationship to the extras skills.
   Evidence for removal is a scope argument, not a defect: they are installed by a module
   whose name, description and menu category say "skills". Decision needed: move them to
   a `devtools` module, or accept the misplacement.
6. **dotenv module ownership (#30).** After fixing 4.2/4.3, what does `mod_dotenv` still
   own? The answer depends on the contents of `darkrei08/dotenv`, which is outside this
   audit's read scope.
7. **CLIProxyAPI image tags (#39).** `templates/cliproxyapi/{local,gitstore}/docker-compose.yml`
   use `eceasy/cli-proxy-api:latest` and `ghcr.io/willxup/cpa-usage-keeper:latest`. Floating
   tags in a generated stack are a reproducibility decision, not a bug I can settle here.
8. **Neovim config owner (#6/4.5).** `mod_lazyvim` vs the dotenv `nvim/` tree: first one to
   run wins, silently. Which one should win is a product decision.
9. **`skillopt-sleep` floats on `main` (#29).** `SKILLOPT_REF=main` (`setup-ai.sh:86`),
   verified reachable (`git ls-remote --heads ... SkillOpt.git` → `refs/heads/main`
   `b91a5f0`). A fork tracking a moving branch is a supply-chain choice, not a defect.

---

## 7. What I did NOT verify

- **No installer was run.** No `setup-ai.sh`, no `setup-ai.ps1`, no container, no dry run.
  Everything above is static reading plus registry/`ls-remote` liveness checks.
- **Windows parity is textual only.** `setup-ai.ps1` was grepped to confirm the same items
  exist (`:94`, `:1378`, `:2955-2959`), never executed. Per this repository's own
  `CHANGELOG.md`, native Windows runtime verification is already pending.
- **`darkrei08/dotenv` was not read.** Redundancy claims 4.2/4.3 rest on setup-ai's own
  source (`:2232-2234` comment and the patch sites) describing what dotenv does. Whether
  dotenv still does it today is unconfirmed.
- **Consumers outside the repository.** Whether `pi-extensible-workflows` uses the LEA
  formatter, the TOON CLI or the LLMLingua venv is not established; only the vendored
  file's `execFileSync` call to `toon` is evidence, and that proves a reference, not a
  live consumer.
- **Vendor install hosts.** `pi.dev/install.sh`, `bun.sh/install`, `claude.ai/install.sh`,
  `chatgpt.com/codex/install.sh`, `antigravity.google/cli/install.sh`, `herdr.dev/install.sh`,
  `opencode.ai/install`, the gentle-ai raw install script, and the `anomalyco/tap` brew tap
  were not fetched. Their continued existence is assumed, not proven.
- **Docker image contents/ownership** behind `eceasy/cli-proxy-api` and
  `ghcr.io/willxup/cpa-usage-keeper`.
- **Uninstall coverage was not audited item by item.** Spot observation only: `toon`,
  `sqz`, `graphify`, `skillopt-sleep` and `herdr` have no `uninstall_catalog` entry
  (`setup-ai.sh:4076-4135`), while `lea`, `llmlingua`, `ai-memory` and `dotenv` do. That
  asymmetry looks intentional for third-party CLIs but was not confirmed against
  `docs/` or tests.
- **Impact on already-installed machines.** Removing a module (e.g. `sqz`) leaves whatever
  its earlier runs created; no migration plan was designed here.
- **Test coverage mapping.** Which of `tests/` (28 files) would fail for each proposed
  removal was not run; `tests/context-tools.test.mjs`, `tests/extras-*`,
  `tests/agent-install-parity.sh` and `tests/version-parity.sh` are the ones to expect.

---

## 8. Removal risk × simplification, condensed

| Change | Removal risk | Simplification | Evidence |
|--------|--------------|----------------|----------|
| Delete `sqz` module | low | high (relative to size) | `:1809-1825`, `ps1:1378`, npm E404 |
| Collapse 3 `pi-extensible-workflows` roots to 1 | low | high | `:2339`, `:2357`, `:2393`, `:2280-2315` |
| One owner for bun / `aimem` / `tree-sitter-cli` | medium | highest | `:1749-1767`, `:1542-1581`, `:1987-2057` |
| One owner for the upstream skill stack | low-medium | medium | `:2232-2234`, `:2234-2279` |
| Drop `neovim` + `go` from `base` | low | medium | `:1489`, `:1497`, `:1641-1644`, `:1943-1947` |
| Move the 2 global npm devtools out of `extras` | low | medium | `:3879-3880`, `docs/modules.md:206-213` |
| Delete `llmlingua` (if no consumer) | low | high (853 MiB) | `:1826-1859` |
| Delete legacy rotator + migration cleanups | medium | low-medium | `:4087-4090`, `:2613-2845` |
