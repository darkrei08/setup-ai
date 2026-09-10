# setup-ai

Cross-OS installer for an AI coding toolchain. One command bootstraps
[pi](https://pi.dev), [Codex](https://github.com/openai/codex),
[Antigravity](https://antigravity.google), [opencode](https://opencode.ai),
[herdr](https://herdr.dev), and the
[Engineering Excellence](https://github.com/darkrei08/Engineering-Excellence)
skill — each via its **official, current** method for your OS.

## Quick start

One command — opens a menu to choose what to set up:

```bash
npx @darkrei08/setup-ai
```

Non-interactive:

```bash
npx @darkrei08/setup-ai --only pi,codex,opencode   # just these
npx @darkrei08/setup-ai --all                       # everything
```

That's the whole thing. Three details worth knowing:

- **Use the npm package above.** `npx github:darkrei08/setup-ai` also works, but many npm setups block git fetches (`EALLOWGIT`); the published package avoids that. Run it from any folder except the repo's own source dir.
- **Windows PowerShell 7.3+**: one command per line (no bash `\`). If node or git was just installed, open a **new terminal** so PATH refreshes.
- **What it does**: detects your OS and runs `setup-ai.sh` (macOS/Linux) or `setup-ai.ps1` (Windows). `--list` shows modules; menu keys: ↑/↓ move · Space toggle · `a` all · Enter.

### npm vs npx

| | `npm` | `npx` |
|---|---|---|
| Role | **installs / manages** packages | **executes** a package's binary |
| Persistence | keeps it installed (`node_modules` / `-g`) | fetches, runs, discards |
| Here | `npm i -g @darkrei08/setup-ai` (permanent `setup-ai`) | `npx @darkrei08/setup-ai` (one-shot) |

For a one-time installer, `npx` is ideal — nothing is left behind.

## Install matrix (official methods)

| Tool | binary | macOS | Linux | Windows |
|---|---|---|---|---|
| Antigravity | `agy` | `curl -fsSL https://antigravity.google/cli/install.sh \| bash` | same | `irm https://antigravity.google/cli/install.ps1 \| iex` |
| Codex | `codex` | `brew install --cask codex` | `curl -fsSL https://chatgpt.com/codex/install.sh \| sh` | `irm https://chatgpt.com/codex/install.ps1 \| iex` |
| pi | `pi` | `curl -fsSL https://pi.dev/install.sh \| sh` | same | `irm https://pi.dev/install.ps1 \| iex` |
| herdr | `herdr` | `brew install herdr` | `curl -fsSL https://herdr.dev/install.sh \| sh` | `irm https://herdr.dev/install.ps1 \| iex` |
| Go | `go` | `brew install go` | distro pkg | `winget install -e --id GoLang.Go` |
| opencode | `opencode` | `brew install anomalyco/tap/opencode` | `curl -fsSL https://opencode.ai/install \| bash` | `npm i -g opencode-ai` |
| cockpit-tools *(opt-in GUI)* | app | `brew install --cask cockpit-tools` | `.deb`/`.rpm`/`.AppImage` | `.msi` |
| Engineering Excellence | skill | `npx skills@latest add darkrei08/Engineering-Excellence --agent <agent>` | same | same |

## Modules

Run `--list` to see them. Core modules install by default; optional ones
(GUI apps) only via `--all` or an explicit `--only`.

```
base node bun pi go dotenv ee skills pi-workflows herdr codex antigravity opencode [cockpit]
```

- **dotenv** is Linux-only (it runs vekexasia/dotenv's apt/pacman `setup_env.sh`); on Windows, explicit selection or `-All` logs and skips it.
- **ee** installs the Engineering Excellence skill for every detected agent
  (pi, claude, gemini, cursor, antigravity, codex, opencode) via `npx skills add`.
- **skills** installs vekexasia/dotenv's agent-skill stack on **every OS** via
  `npx skills add` (dotenv itself is Linux-only): `herdr` (herdrdev/herdr);
  `triage grill-me grilling wayfinder domain-modeling prototype research`
  (mattpocock/skills); `typescript-advanced` (pedronauck/skills); `show-me`
  (humanlayer/skills) — for every detected agent. `skills add --copy` is
  idempotent, so it's safe alongside the Linux `dotenv` run.

## pi workflows (pi-extensible-workflows)

**Italiano** — Il modulo `pi-workflows` installa l'estensione pi per i workflow. Per
installazione completa, pacchetti opzionali (`@piewf/cli`, `@piewf/herdr`), integrazione
Herdr, picker `/workflow`, tool `workflow`, selezione modelli, ruoli/alias e Neovim, vedi
la guida bilingue: [docs/pi-workflows-guide.md](docs/pi-workflows-guide.md).

**English** — The `pi-workflows` module installs the pi workflows extension. For full
install, optional packages (`@piewf/cli`, `@piewf/herdr`), Herdr integration, the
`/workflow` picker, the `workflow` tool, model selection, roles/aliases, and Neovim, see
the bilingual guide: [docs/pi-workflows-guide.md](docs/pi-workflows-guide.md).

## OpenCode Go inside pi

An OpenCode Go subscription is reusable in pi (no lock-in). After
`opencode auth login`, add a custom provider in pi:

```js
pi.registerProvider("opencode-go", {
  baseUrl: "https://opencode.ai/zen/v1",
  apiKey: "$OPENCODE_API_KEY",
  authHeader: true,
  api: "openai-completions",
  models: [ /* your Go plan model ids */ ],
});
```

or run `/provider add` in pi. Docs: <https://pi.dev/docs/latest/custom-provider>.

## Logs

Each run writes `logs/setup_<runid>.log` (human), `.jsonl` (structured), and an
`engineering-report_<runid>.md`.

## License

MIT (this installer). Installed tools keep their own licenses — note
cockpit-tools is CC BY-NC-SA 4.0 (non-commercial).
