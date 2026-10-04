# Modules

Run `--list` to see them. Core modules install by default; optional ones
(GUI apps) only via `--all` or an explicit `--only`.

The order below is the execution order (`MODULE_ORDER` in `setup-ai.sh`,
`$ModuleOrder` in `setup-ai.ps1`, `MODULES` in the Node launcher — the three must
stay identical):

```
base node bun pi dotenv ai-memory lazyvim pi-packages go ee skills pi-workflows herdr claude-code codex antigravity opencode gentle-ai [cockpit] [rotator] [extras]
```

## base

System packages (build tools, `git`, `gh`, `python`, `neovim`, `jq`,
`imagemagick`, `go`, plus the clipboard tools `wl-clipboard` and `xclip` and the
desktop helpers `x11-apps`, `gedit`, `pulseaudio-utils` and `mesa-utils` on Linux)
through the platform package manager: `apt-get`, `dnf`, `pacman`, `zypper`, or
`brew` on macOS. On Debian/Ubuntu the module first upgrades the installed
packages non-interactively (`--force-confold`, so local conffile edits are kept)
and installs `nala`, then performs the bulk install through `nala install`.

## node / bun / go / pi

The runtimes the rest of the toolchain needs. Node.js v22 via `nvm` on
Unix/macOS, `winget` on Windows; `bun`; the Go toolchain; the `pi` CLI through
`pi.dev/install.sh` (or `install.ps1`).

## dotenv

Linux-only: clones and runs [darkrei08/dotenv](https://github.com/darkrei08/dotenv),
whose `setup_env.sh` detects **Arch/Omarchy vs Debian/Ubuntu** and installs the
dotfiles (neovim, herdr, tmux, wezterm) plus the Pi configuration. It runs
**before** `pi-packages`, so the manifest is already in place in the live
`~/.pi/agent/pi-packages.txt`.

Manual equivalent, without the installer:

```bash
git clone https://github.com/darkrei08/dotenv.git ~/git/personale/dotenv
~/git/personale/dotenv/setup_env.sh
```

`setup_env.sh` populates `~/.pi/agent` with a selective `rsync` from the checkout's
`pi/agent` directory (settings, models, prompts, skills, themes, ...). It is a real
directory, not a symlink, and it never deletes runtime state (`auth.json`,
`sessions/`, pi-managed installs), so re-runs are idempotent.

For provider setup, use dotenv's canonical guides for [Tuxevil](https://github.com/darkrei08/dotenv/blob/main/pi/agent/README.md) and [CLIProxyAPI](https://github.com/darkrei08/dotenv/blob/main/cliproxyapi/README.md). setup-ai's optional `rotator` module covers Tuxevil; CLIProxyAPI remains a manual dotenv setup and is not configured by setup-ai.

Any other distro exits 1 with an explicit message, and on Windows the module logs
`skipped_non_linux`.

## ai-memory

Provides the `ai-memory-kit` `aimem` CLI and templates at
v0.1.0. The installer uses `AIMEM_REF` for the source ref (default `v0.1.0`),
`AIMEM_VERSION` for the expected installed version (default `0.1.0`), and
`AIMEM_PREFIX` for the install root (default `$HOME/.local`). It verifies the
exact paths `${AIMEM_PREFIX}/bin/aimem` and, on Windows,
`${AIMEM_PREFIX}/bin/aimem.cmd`; missing files or a version mismatch trigger a
repair and the installed version is checked again.

The tagged codeload URL is patched from `/tar.gz/refs/heads/$Ref` to
`/tar.gz/$Ref` before the upstream installer runs, because GitHub rejects the
branch-shaped URL for release tags. On Linux/macOS, the current `ai-memory`
module invokes the ai-memory-kit installer with `--no-skill`. Its uninstall-owned
paths are `${AIMEM_PREFIX}/bin/aimem` and `${AIMEM_PREFIX}/share/ai-memory-kit`;
`--uninstall --yes --only ai-memory` removes them without `--purge`; keep `AIMEM_PREFIX` under `$HOME` so the uninstall safety boundary can remove the owned paths.

## lazyvim

Installs the official Neovim x86_64 tarball under `/opt/nvim-linux-x86_64` on
Linux x86_64 and puts its `bin` directory ahead of the distro package for the
current run and future shells. Other Linux architectures use their platform
Neovim package; macOS and Windows use their platform package. When
`~/.config/nvim` is absent, it clones the [LazyVim starter](https://github.com/LazyVim/starter),
removes only the starter's `.git` metadata, and runs `nvim --headless "+Lazy! sync" +qa`.
An existing Neovim configuration is preserved. On Linux, the `dotenv` module runs
first and owns its own Neovim configuration, so the starter clone is skipped when
that configuration already exists.

## pi-packages

Reads a declarative manifest, one source per line (`npm:<pkg>[@<version>]`,
`git:<host>/<owner>/<repo>[@<ref>]`, or a local path), and verifies every package
by reading `~/.pi/agent/settings.json` back instead of trusting the install
command. Start from `pi-packages.example.txt`; see
[pi-extensions.md](./pi-extensions.md).

## ee

Installs the Engineering Excellence skill for every detected agent
(pi, claude, gemini, cursor, antigravity-cli, codex, opencode) via `npx skills add`.

## skills

Installs darkrei08/dotenv's agent-skill stack on **every OS** via `npx skills add`
(dotenv itself is Linux-only): `herdr` (herdrdev/herdr);
`triage grill-me grilling wayfinder domain-modeling prototype research`
(mattpocock/skills); `typescript-advanced` (pedronauck/skills); `show-me`
(humanlayer/skills) — for every detected agent. `skills add --copy` is
idempotent, so it is safe alongside the Linux `dotenv` run.

## Agent modules

The core registry installs the requested agent CLIs: `pi`, `claude-code`, `codex`,
`antigravity`, `opencode`, and `herdr`. The `ee`, `skills`, and `gentle-ai`
modules continue to target every detected compatible agent, including Gemini CLI
and Cursor when they are already installed by their vendors.

Claude Code uses Anthropic's official Unix installer (`https://claude.ai/install.sh`).
Unattended Unix runs use the installer helper without a controlling TTY; the
installer has no separate documented non-interactive environment variable. On
Windows, setup-ai uses Anthropic's documented `npm install -g @anthropic-ai/claude-code`
method. Authentication remains a user action: run `claude` once after installation
when login is required.

The other modules use the vendor commands listed in
[install-matrix.md](./install-matrix.md). Vendor-owned launchers and auth/config
state are not removed by setup-ai's Bash uninstall catalog.

## pi-workflows

Installs `pi-extensible-workflows` (published release, verified down to the
loaded artifact) and enables npm 12 remote sources for pi installs. The optional
`@piewf/cli` and `@piewf/herdr` companions are **not** installed: full guide and
opt-in instructions in [pi-workflows-guide.md](./pi-workflows-guide.md) §3.

## herdr

The herdr terminal multiplexer, through its official installer.

## extras *(opt-in)*

Stages Taste (`design-taste-frontend`), Humanizer, and HeroUI (`heroui-react`) in
`~/.agents/skills`, the canonical shared-skill root. Existing canonical or
agent-specific copies and links are preserved when they conflict; matching
copies are left in place. The skills are linked for Claude Code, Codex, OpenCode,
Gemini CLI, and Antigravity CLI under its `.gemini/antigravity-cli/skills` root.
The `skills` CLI harness key is `antigravity-cli`, distinct from setup-ai's
`antigravity` module key and gentle-ai's `antigravity` harness name. Pi reads the
canonical root directly. Impeccable is installed globally with
`--no-hooks`, so the installer does not create project-local hook files.

The module also runs HyperFrames' core skills update (`npx hyperframes skills
update`, with stdin redirected so it never waits on a prompt) and installs `typescript-express-starter`
and `@alibaba-group/open-code-review` globally. Each package is verified by reading
`<npm root -g>/<package>/package.json` and matching its exact `name`. A package that
was already present is verified and left in place; only a package installed by this
run receives a `.setup-ai-owned` marker. setup-ai never runs Open Code Review,
configures an LLM provider for it, or submits code anywhere.

CLI-Anything's Pi extension is fetched at the pinned revision
`34f519533bc175d2fe287ab8316b0dd99bb9cc43`, the checkout is verified against the pin,
and `.pi-extension/cli-anything` is copied to
`${PI_CODING_AGENT_DIR:-~/.pi/agent}/extensions/cli-anything` with a
`.setup-ai-owned` marker. An existing target that does not match the pinned assets is
preserved and the module fails instead of overwriting it.

## gentle-ai

Installs the gentle-ai / `gga` ecosystem configurator, then runs
`gentle-ai install` — its own **interactive per-agent/per-IDE selector** (Pi,
Claude Code, Cursor, Codex, ...) that also wires each selected agent's **MCP**
servers, so the tools show up under `/mcp`. For pi it additionally installs the
first-class `gentle-pi` harness and `pi-mcp-adapter`, so pi reads gentle-ai in
its own MCP list. The interactive selector runs only with a real TTY;
non-interactive/CI runs execute `gentle-ai install --scope global --agents
<detected>` over the detected agents, so they never hang. In
non-interactive/CI mode, a matching HTTP 403 from the GitHub API gets two
bounded retries (15s, then 45s); after exhaustion, the module fails and names
`gh auth login` or `GITHUB_TOKEN`/`GH_TOKEN` as the remedies. In interactive TTY
mode, any non-zero selector exit gets the same two bounded retries because its
TTY-owned output cannot be captured to identify the 403 signature. Idempotent:
safe to re-run.

When the native RDD review refuses to start (`blocked` / `mutation_outcome: unknown`),
the read-only checks and the two continuations are in
[rdd-review-troubleshooting.md](./rdd-review-troubleshooting.md).

The module runs **after** `codex`, `antigravity` and `opencode`: `gentle-ai
install` fails with `install OpenCode Gentle Logo plugin: OpenCode runtime
version unavailable or unsupported` when a CLI it configures is still absent, so
the run has to install them first.

## codex / antigravity / opencode

The other agent CLIs, each through its official installer.

**opencode** installs the `opencode-ai` CLI and makes the `opencode-pi` Pi
extension able to use it. On Linux, the vendor installer resolves its version
through GitHub with `GITHUB_TOKEN` or `gh auth token` when a token is available;
if that path fails, the module falls back to the npm registry with
`npm install -g opencode-ai` (and `--allow-scripts=opencode-ai` on npm 12+). If
both paths fail, setup-ai reports the opencode module as failed and the log
contains the vendor and npm errors. macOS installs it through Homebrew, and
Windows through the npm registry directly.

That extension starts the CLI with `child_process.spawn` and no shell, so on
Windows the npm `.cmd`/`.ps1` shims in `%APPDATA%\npm` are not executable for it
and Node fails with `spawn opencode ENOENT` even when `opencode --version` works
in a terminal. The module probes that same no-shell spawn, resolves the packaged
`node_modules/opencode-ai/bin/opencode.exe` behind the shim, and persists
`OPENCODE_PI_BIN` for the current user. On Linux/macOS the installer appends its
bin dir to the shell rc only, so the module resolves `$HOME/.opencode/bin` for
the run and verifies it.

## cockpit *(opt-in)*

The cockpit-tools desktop GUI app (CC BY-NC-SA).

## rotator *(opt-in)*

Installs the multi-account `tuxevil-rotator` Gemini/Antigravity gateway,
registers it to start at boot (a `systemd --user` unit on Linux, a logon
scheduled task on Windows), starts it in the background when nothing answers on
port 51200, and installs the `pi-cockpit-tools-sync` Pi extension (source
`git:github.com/darkrei08/pi-cockpit-tools-sync`). Login is never run and no
tokens are read: add an account once with `tuxevil-rotator login`. Where the
machine offers neither unit nor task, the gateway is still started as a detached
process and the module logs `INFO rotator service_skipped`. On the dotenv side the `rotator-autostart`
Pi extension does the same at session start when the port is dead, so the
`gemini-*` aliases keep working; concurrent sessions coordinate through one start
claim (one start, not one per session) and the detached process log is
`~/.tuxevil-rotator/gateway.log`. Reruns preserve an existing unit or task
rather than replacing it; Linux uses the systemd unit only while its exact
setup-ai-generated content matches the current executable, otherwise it leaves the
unit untouched and uses the detached fallback. Windows uses the scheduled task only
while its setup-ai receipt still matches. Both registrations also bring back a
gateway that dies, by different means: the Linux unit leaves it to systemd
(`Restart=on-failure`, `RestartSec=5`), while the Windows task repeats every five
minutes with `-MultipleInstances IgnoreNew`, so a tick is skipped while the
gateway it started still runs, and each tick checks the port first so a gateway
started by a session or by the detached fallback is never doubled.

## Uninstall

Use `--uninstall` to print the owned-item inventory; removal requires `--yes`.
Use `--only` to restrict modules, and `--purge` to remove destructive items such as
`~/.nvm`, `~/.bun`, and the dotenv checkout. `--uninstall --dry-run` reports removals
without deleting anything. The catalog never touches
`~/.pi/agent/auth.json` or `~/.pi/agent/sessions/`.

For `extras`, the two global packages are removed only when their `package.json`
name and `.setup-ai-owned` marker both match exactly, and the CLI-Anything extension
directory only when its marker names the pinned revision and `--purge` is given.
Anything else is reported as `skipped (not verified as setup-ai-owned)`. The shared
skills, Impeccable files, and HyperFrames skill updates are not removed.

On Windows, `setup-ai.ps1` refuses `-DryRun` and `-Uninstall` with exit 2 and points
users to `setup-ai.sh`; Windows lifecycle operations are not implemented yet.

Back to the [README](../README.md) · Related:
[install matrix](./install-matrix.md) · [logs](./logs.md) ·
[troubleshooting](./troubleshooting.md).
