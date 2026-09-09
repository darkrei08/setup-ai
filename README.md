# setup-ai

Cross-OS installer for an AI coding toolchain. One command bootstraps
[pi](https://pi.dev), [Codex](https://github.com/openai/codex),
[Antigravity](https://antigravity.google), [opencode](https://opencode.ai),
[herdr](https://herdr.dev), [gentle-ai](https://github.com/Gentleman-Programming/gentle-ai),
[Engram](https://github.com/Gentleman-Programming/engram) memory, and the
[Engineering Excellence](https://github.com/micio86dev/Engineering-Excellence)
skill — each via its **official, current** method for your OS.

## Quick start

```bash
# no install needed — runs the launcher once, then discards it
npx github:darkrei08/setup-ai
```

or, once published to npm:

```bash
npx @darkrei08/setup-ai                    # interactive module menu
npx @darkrei08/setup-ai --only pi,codex,opencode
npx @darkrei08/setup-ai --all              # everything incl. optional GUI apps
npm i -g @darkrei08/setup-ai && setup-ai   # global command
```

The launcher (`bin/setup-ai.mjs`, zero dependencies) detects your OS and runs
the right script: `setup-ai.ps1` on Windows (via `pwsh`), `setup-ai.sh` on
macOS/Linux (via `bash`). With no selection flag on an interactive terminal it
opens an arrow-key **multi-select menu** (↑/↓ move · Space toggle · `a` all ·
Enter confirm); on a non-interactive shell it installs the core set.

> **Windows / PowerShell**: paste each command on a **single line** — the bash
> `\` line-continuation is not valid in PowerShell. If a runtime (node, git) was
> just installed this run, open a **new terminal** before re-running so the
> updated PATH is picked up.

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
| gentle-ai | `gentle-ai` | `brew install gentleman-programming/tap/gentle-ai` | `curl -fsSL .../scripts/install.sh \| bash` | `go install github.com/gentleman-programming/gentle-ai/v2/cmd/gentle-ai@latest` |
| Engram | `engram` | `brew install gentleman-programming/tap/engram` | `go install github.com/Gentleman-Programming/engram/cmd/engram@latest` | same (go install) |
| opencode | `opencode` | `brew install anomalyco/tap/opencode` | `curl -fsSL https://opencode.ai/install \| bash` | `npm i -g opencode-ai` |
| cockpit-tools *(opt-in GUI)* | app | `brew install --cask cockpit-tools` | `.deb`/`.rpm`/`.AppImage` | `.msi` |
| Engineering Excellence | skill | `npx skills@latest add micio86dev/Engineering-Excellence --agent <agent>` | same | same |

## Modules

Run `--list` to see them. Core modules install by default; optional ones
(GUI apps) only via `--all` or an explicit `--only`.

```
base node bun pi go dotenv ee pi-workflows herdr gentle-ai engram codex antigravity opencode [cockpit]
```

- **dotenv** is Linux-only (it runs vekexasia/dotenv's apt/pacman `setup_env.sh`).
- **ee** installs the Engineering Excellence skill for every detected agent
  (pi, claude, gemini, cursor, antigravity) via `npx skills add`.

## Engram in pi (the gotcha)

`gentle-engram` is an **in-process pi extension** that auto-starts `engram serve`.
It therefore needs the **Engram Go binary on `PATH`** — if it's missing, the
extension loads but silently does nothing (the "engram doesn't work in pi"
symptom). The `engram` module installs the binary first, then:

```bash
pi install npm:gentle-engram
pi install npm:pi-mcp-adapter      # optional MCP gateway
pi-engram init
# then RESTART pi, and verify:
#   mem_current_project   mem_doctor   engram tui
```

MCP is only an optional gateway — the primary path for pi is the in-process
extension, so don't rely on the MCP-only choice.

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
