# Troubleshooting — errors seen in the field

Every entry is a real failure from a field run, with the fix. Line references are
to `setup-ai.sh` unless stated otherwise.

## `ai-memory-kit` returns 404 for `v0.1.0`

```text
Fetching darkrei08/ai-memory-kit@v0.1.0 ...
curl: (22) The requested URL returned error: 404
gzip: stdin: unexpected end of file
tar: Child returned status 1
```

`ai-memory-kit` v0.1.0 used GitHub's `refs/heads/<ref>` codeload URL even
when `<ref>` was a release tag. GitHub returns 404 for that combination. The
installer now patches this known upstream path to the ref-neutral codeload URL
before running the dotenv setup script. The skill installation shown before the
404 can already have succeeded; the failed part is the `aimem` CLI/templates
bootstrap.

## `pi` does not start: `Tool "read" conflicts with …`

```text
Error: Failed to load extension ".../gentle-pi/extensions/quiet-tools.ts":
Tool "read" conflicts with .../pi-hashline-edit-pro/index.ts
Hint: Start without extensions using "pi -ne".
```

Pi rejects two extensions registering the same tool name. gentle-pi's
`quiet-tools` re-registers the built-in `read`/`edit`/`grep` tools, and
`pi-hashline-edit-pro` owns `read`/`grep`.

**Fix** — pick one:

- keep hashline-edit and disable the quiet renderers:
  `export GENTLE_PI_QUIET_TOOLS=0` (the dotenv fork appends this to `~/.bashrc`);
- or remove `git:github.com/YuGiMob/pi-hashline-edit-pro` from
  `~/.pi/agent/settings.json`.

Only the exact string `0` disables quiet-tools (`false`/`off`/unset keep it on).
Since **3.4.2** the `gentle-ai` module **persists** `GENTLE_PI_QUIET_TOOLS=0`
itself (the shell rc files and `~/.config/environment.d/50-gentle-pi.conf`) and
logs `quiet_tools_disabled`, so a shell that never sourced an rc still starts
`pi`.

## `Ctrl+V` does not attach a clipboard image

`pi` reads the clipboard through a backend: `wl-clipboard` (`wl-paste`) on
Wayland, `xclip`/`xsel` on X11. Without one, `Ctrl+V` (`Alt+V` on Windows/WSL)
silently attaches nothing, and text paste does nothing either. The `base` module
installs both on Linux; on a machine set up before that, install it yourself:

```bash
sudo pacman -S --needed wl-clipboard xclip     # Arch
sudo apt-get install -y wl-clipboard xclip     # Debian/Ubuntu
```

Alternative without a clipboard backend: save the screenshot to a file and
reference it in the prompt (`@/path/shot.png`).

## `Warning: Gentle AI: receipt-driven-development status is unavailable …`

npm 12 blocks gentle-pi's `postinstall`, which is what installs the
**package-local** review binary `gentle-pi/.gentle-ai/<version>/gentle-ai`. The
install-script approval pass runs only after every selected module succeeds, so a
run that fails earlier leaves it blocked.

```bash
npm install-scripts ls --prefix ~/.pi/agent/npm     # gentle-pi listed = blocked
```

**Fix**:

```bash
npm install-scripts approve --no-allow-scripts-pin gentle-pi --prefix ~/.pi/agent/npm
npm rebuild gentle-pi --prefix ~/.pi/agent/npm
~/.pi/agent/npm/node_modules/gentle-pi/.gentle-ai/*/gentle-ai review mode status --cwd <repo> --json
# expect: "effective": "on"
```

## `Error: FFF init failed … file system root or home directories`

From `@heyhuynhgiabuu/pi-pretty` (a gentle-pi dependency): the fuzzy file picker
refuses to run when the working directory is `/` or the home directory.

**Fix**: launch pi from a project directory, not `~`.

## Debian: opencode installed but `Required command not found: opencode` (127)

The opencode installer appends `$HOME/.opencode/bin` to the shell rc only, so the
running process cannot see it. Fixed in **3.4.1** (`refresh_opencode_path`).
Manual workaround:

```bash
export PATH="$HOME/.opencode/bin:$PATH"
```

## Arch / CachyOS: `sudo: apt-get: comando non trovato` in `dotenv`

The module runs `darkrei08/dotenv`'s `setup_env.sh`, which detects the
distribution (Arch/Omarchy vs Debian/Ubuntu). If an older `vekexasia/dotenv`
checkout is still in `~/git/personale/dotenv`, setup-ai **preserves** it and you
get the apt-only script.

**Fix**: point the module at the fork, or replace the checkout:

```bash
mv ~/git/personale/dotenv ~/git/personale/dotenv.old
git clone https://github.com/darkrei08/dotenv.git ~/git/personale/dotenv
```

## Arch / CachyOS: `github-cli` and `github-cli-git` are in conflict

`pacman -Sy --needed --noconfirm` cannot answer pacman's "remove `github-cli-git`?"
prompt, so the `base` module fails. If `gh` already exists, skip `github-cli` (or
remove the alternative provider) before re-running.

## `sed: impossibile leggere ~/.pi/agent.json`

There is no `~/.pi/agent.json`. Pi's configuration lives at
`~/.pi/agent/settings.json` (with `~/.pi/agent/npm` and
`~/.pi/agent/extensions`).

## `Shift+Enter` does not insert a newline

Pi distinguishes `Shift+Enter` only if the terminal reports the modifier (Kitty
keyboard protocol, or xterm `modifyOtherKeys`). Tabby and other terminals with
limited escape support send plain `Enter`.

**Fix**: `Ctrl+J` — a default `tui.input.newLine` alias that works everywhere. In
WezTerm, `shift+enter` works out of the box; set
`config.enable_kitty_keyboard = true` to use the Kitty protocol explicitly. In
tmux keep `set -g extended-keys on`. Note `Alt+Enter` is **not** a newline: it is
`app.message.followUp` (queue a follow-up message).

## The questions dialog does not appear

The options + **Submit** dialog is the `ask_user_question` tool from
`@juicesharp/rpiv-ask-user-question`. It appears only when the model **calls the
tool**; a question written as prose has no dialog. It is removed from the model's
tool list in non-interactive runs.

Back to the [README](../README.md) · Related: [logs](./logs.md) ·
[rdd review troubleshooting](./rdd-review-troubleshooting.md).
