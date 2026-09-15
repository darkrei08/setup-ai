# setup-ai

Cross-OS installer for an AI coding toolchain. One command bootstraps
[pi](https://pi.dev), [Codex](https://github.com/openai/codex),
[Antigravity](https://antigravity.google), [opencode](https://opencode.ai),
[herdr](https://herdr.dev),
[gentle-ai](https://github.com/Gentleman-Programming/gentle-ai), the
[darkrei08/dotenv](https://github.com/darkrei08/dotenv) dotfiles, and the
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
npx @darkrei08/setup-ai --verbose                   # spaced output with live command logs
```

Three details worth knowing:

- **Use the npm package above.** `npx github:darkrei08/setup-ai` also works, but many npm setups block git fetches (`EALLOWGIT`); the published package avoids that. Run it from any folder except the repo's own source dir.
- **Windows PowerShell 7.3+**: one command per line (no bash `\`). If node or git was just installed, open a **new terminal** so PATH refreshes.
- **What it does**: detects your OS and runs `setup-ai.sh` (macOS/Linux) or `setup-ai.ps1` (Windows). Each module and command is shown with live output, so prompts such as `sudo` remain visible; `--list` shows modules; menu keys: arrows/`j`/`k` move · Space toggle · `a` all · Enter.

### npm vs npx

| | `npm` | `npx` |
|---|---|---|
| Role | **installs / manages** packages | **executes** a package's binary |
| Persistence | keeps it installed (`node_modules` / `-g`) | fetches, runs, discards |
| Here | `npm i -g @darkrei08/setup-ai` (permanent `setup-ai`) | `npx @darkrei08/setup-ai` (one-shot) |

For a one-time installer, `npx` is ideal — nothing is left behind.

## Documentation

Everything below the quick start is split into focused pages. Start from the one
that matches your question.

| Page | What it covers |
|---|---|
| [docs/install-matrix.md](docs/install-matrix.md) | The official install method of every tool, per OS |
| [docs/modules.md](docs/modules.md) | Module list and order, what each module does, the manual `dotenv` setup |
| [docs/pi-extensions.md](docs/pi-extensions.md) | Pi package roots, npm 12 remote sources and install-script approval, models, resource selectors |
| [docs/pi-workflows-guide.md](docs/pi-workflows-guide.md) | `pi-extensible-workflows`: install, `/workflow` picker, roles/aliases, Herdr, Neovim (bilingual) |
| [docs/rdd-review-troubleshooting.md](docs/rdd-review-troubleshooting.md) | When the native RDD review refuses to start (`blocked` / `mutation_outcome: unknown`) |
| [docs/logs.md](docs/logs.md) | `setup_<runid>.log` / `.jsonl` / engineering report, the `run_summary` record, the event stream |
| [docs/opencode-go.md](docs/opencode-go.md) | Reuse an OpenCode Go subscription inside pi |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Real field errors and their fixes (`read` conflict, missing RDD binary, opencode PATH, distro detection, `Shift+Enter`, …) |

`pi-packages.example.txt` in the package root is the starting point for the
declarative Pi package manifest.

## License

MIT (this installer). Installed tools keep their own licenses — note
cockpit-tools is CC BY-NC-SA 4.0 (non-commercial).
