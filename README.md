# setup-ai

Cross-OS installer for an AI coding toolchain. One command bootstraps
[pi](https://pi.dev), [Codex](https://github.com/openai/codex),
[Antigravity](https://antigravity.google), [opencode](https://opencode.ai),
[herdr](https://herdr.dev),
[gentle-ai](https://github.com/Gentleman-Programming/gentle-ai), and the
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
| gentle-ai | `gentle-ai` / `gga` | `brew install gentleman-programming/tap/gentle-ai` | `curl -fsSL https://raw.githubusercontent.com/Gentleman-Programming/gentle-ai/main/scripts/install.sh \| bash` | `irm https://raw.githubusercontent.com/Gentleman-Programming/gentle-ai/main/scripts/install.ps1 \| iex` |
| Go | `go` | `brew install go` | distro pkg | `winget install -e --id GoLang.Go` |
| opencode | `opencode` | `brew install anomalyco/tap/opencode` | `curl -fsSL https://opencode.ai/install \| bash` | `npm i -g opencode-ai` |
| cockpit-tools *(opt-in GUI)* | app | `brew install --cask cockpit-tools` | `.deb`/`.rpm`/`.AppImage` | `.msi` |
| tuxevil-rotator *(opt-in)* | `tuxevil-rotator` | `npm i -g tuxevil-rotator` | same | same |
| Engineering Excellence | skill | `npx skills@latest add darkrei08/Engineering-Excellence --agent <agent>` | same | same |

## Modules

Run `--list` to see them. Core modules install by default; optional ones
(GUI apps) only via `--all` or an explicit `--only`.

```
base node bun pi dotenv pi-packages go ee skills pi-workflows herdr gentle-ai codex antigravity opencode [cockpit] [rotator]
```

- **dotenv** is Linux-only (it runs darkrei08/dotenv's apt/pacman `setup_env.sh`); on Windows, explicit selection or `-All` logs and skips it.
- **ee** installs the Engineering Excellence skill for every detected agent
  (pi, claude, gemini, cursor, antigravity, codex, opencode) via `npx skills add`.
- **skills** installs darkrei08/dotenv's agent-skill stack on **every OS** via
  `npx skills add` (dotenv itself is Linux-only): `herdr` (herdrdev/herdr);
  `triage grill-me grilling wayfinder domain-modeling prototype research`
  (mattpocock/skills); `typescript-advanced` (pedronauck/skills); `show-me`
  (humanlayer/skills) — for every detected agent. `skills add --copy` is
  idempotent, so it's safe alongside the Linux `dotenv` run.
- **gentle-ai** installs the gentle-ai / `gga` ecosystem configurator, then runs
  `gentle-ai install` — its own **interactive per-agent/per-IDE selector** (Pi,
  Claude Code, Cursor, Codex, ...) that also wires each selected agent's **MCP**
  servers, so the tools show up under `/mcp`. For pi it additionally installs the
  first-class `gentle-pi` harness and `pi-mcp-adapter`, so pi reads gentle-ai in
  its own MCP list. The interactive selector runs only with a real TTY;
  non-interactive/CI runs log the exact `gentle-ai install` command instead of
  hanging. Idempotent: safe to re-run.

  When the native RDD review refuses to start (`blocked` / `mutation_outcome: unknown`),
  the read-only checks and the two continuations are in
  [docs/rdd-review-troubleshooting.md](docs/rdd-review-troubleshooting.md).
- **rotator** (opt-in) installs the multi-account `tuxevil-rotator` Gemini/Antigravity
  gateway, registers it to start at boot (a `systemd --user` unit on Linux, a logon
  scheduled task on Windows), starts it in the background when nothing answers on port
  51200, and installs the `pi-cockpit-tools-sync` Pi extension (source
  `git:github.com/darkrei08/pi-cockpit-tools-sync`). Login is never run and no tokens are
  read: add an account once with `tuxevil-rotator login`. Where the machine offers
  neither unit nor task, the gateway is still started as a detached process and the
  module logs a `WARN`. On the dotenv side the `rotator-autostart` Pi extension does the
  same at session start when the port is dead, so the `gemini-*` aliases keep working;
  concurrent sessions coordinate through one start claim (one start, not one per
  session) and the detached process log is `~/.tuxevil-rotator/gateway.log`.
  Both registrations also bring back a gateway that dies, by different means: the Linux unit
  leaves it to systemd (`Restart=on-failure`, `RestartSec=5`), while the Windows task repeats
  every five minutes with `-MultipleInstances IgnoreNew`, so a tick is skipped while the
  gateway it started still runs, and each tick checks the port first so a gateway started by a
  session or by the detached fallback is never doubled. The Linux side needs no code change.
- **opencode** installs the `opencode-ai` CLI and makes the `opencode-pi` Pi extension able to
  use it. That extension starts the CLI with `child_process.spawn` and no shell, so on Windows
  the npm `.cmd`/`.ps1` shims in `%APPDATA%\npm` are not executable for it and Node fails with
  `spawn opencode ENOENT` even when `opencode --version` works in a terminal. The module probes
  that same no-shell spawn, resolves the packaged
  `node_modules/opencode-ai/bin/opencode.exe` behind the shim, and persists `OPENCODE_PI_BIN`
  for the current user: a re-run leaves the value unchanged and an install that already spawns
  is left alone. On Linux/macOS the npm shim resolves through its shebang, so a `spawn` of the
  PATH entry works and the module only verifies and logs it.

## pi workflows (pi-extensible-workflows)

**Italiano** — Il modulo `pi-workflows` installa l'estensione pi per i workflow. Per
installazione completa, pacchetti opzionali (`@piewf/cli`, `@piewf/herdr`), integrazione
Herdr, picker `/workflow`, tool `workflow`, selezione modelli, ruoli/alias e Neovim, vedi
la guida bilingue: [docs/pi-workflows-guide.md](docs/pi-workflows-guide.md).

**English** — The `pi-workflows` module installs the pi workflows extension. For full
install, optional packages (`@piewf/cli`, `@piewf/herdr`), Herdr integration, the
`/workflow` picker, the `workflow` tool, model selection, roles/aliases, and Neovim, see
the bilingual guide: [docs/pi-workflows-guide.md](docs/pi-workflows-guide.md).

## Pi packages and extensions

pi reads packages from two user-scope npm roots — `~/.pi/agent/npm` (the managed root
`pi install` and `pi update --extensions` write and load) and `~/.pi/agent/extensions`
(the shared resolution root setup-ai installs into) — and both must hold the same build.
The **`pi-packages`** module reads a declarative manifest, one source per line
(`npm:<pkg>[@<version>]`, `git:<host>/<owner>/<repo>[@<ref>]`, or a local path), and
verifies every package by reading `~/.pi/agent/settings.json` back instead of trusting
the install command. Start from `pi-packages.example.txt`; the reference page
[docs/pi-extensions.md](docs/pi-extensions.md) covers npm 12 `EALLOWREMOTE` and
install-script approval, where configuration lives (dotenv vs the extension), models and
resource selectors, and troubleshooting.

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

The JSONL ends with one `run_summary` record per run, and every step that goes through
the installer's command helpers adds a `step_result` record. Both are additive: existing
event names and payloads are unchanged, and `setup-ai.sh` and `setup-ai.ps1` emit the
same fields in the same order. The engineering report ends with the same summary.

```json
{
  "event": "run_summary",
  "run_id": "20260913T150742Z",
  "return_code": 0,
  "summary": {
    "run_id": "20260913T150742Z",
    "outcome": "success",
    "started_at": "2026-09-13T15:07:42Z",
    "ended_at": "2026-09-13T15:07:48Z",
    "duration_seconds": 6,
    "modules": [{ "name": "rotator", "status": "success" }],
    "steps": { "installed": 1, "verified": 3, "skipped": 0, "failed": 0 }
  }
}
```

- `summary.modules[].status` is `success`, `failed`, or `skipped` (never reached). A
  failed entry also carries `failed_step` (the command that failed) and `return_code`.
- `summary.steps` counts the step records: `installed` (a state-changing step ran),
  `verified` (a readback step ran), `skipped` (an optional step failed, or the step never
  ran) and `failed` (a mandatory step returned a failure). Both flags a caller can use stay
  in the log: `--optional` (`-Optional`) marks a failure the run recovers from, so it is
  counted as skipped, and `--verify` (`-Verify`) marks a read-back, so a successful one is
  counted as verified instead of installed. A recovered attempt therefore never inflates
  the failed count.
- `summary.outcome` is `success` only when the whole run exited 0, so a failed run still
  says which module and step failed and with which return code. A failure outside the
  selected modules (a quality gate, the npm install-script approval) is listed with its
  phase name.

Reading a run without paging the log:

```bash
node -e 'const s=require("fs").readFileSync(process.argv[1],"utf8").trim().split("\n").map(JSON.parse).filter(r=>r.event==="run_summary").pop().summary;console.log(s.outcome, JSON.stringify(s.modules), JSON.stringify(s.steps))' logs/setup_<runid>.jsonl
```

## License

MIT (this installer). Installed tools keep their own licenses — note
cockpit-tools is CC BY-NC-SA 4.0 (non-commercial).
