# Install all requested agents and LazyVim

- **Status:** ready for integration
- **Issue:** #93 (https://github.com/darkrei08/setup-ai/issues/93)
- **Branch:** `fix/install-all-agents`
- **Goal:** Make setup-ai install the requested agent CLIs (pi, Claude Code, Codex, Antigravity, OpenCode, herdr) and bootstrap LazyVim from the official starter without breaking Bash/PowerShell/Node parity.

## Tasks

1. Open an approved GitHub bug issue with exact scope and acceptance commands.
2. Add the missing Claude Code module and LazyVim bootstrap; mirror registries and behavior across `setup-ai.sh`, `setup-ai.ps1`, and `bin/setup-ai.mjs`.
3. Update module documentation and focused tests.
4. Run syntax, launcher, shell, PowerShell, and container gates.
5. Commit through the repository workflow and deliver the worktree for integration; PR/merge/issue closure remain outside this session.

## Decisions

- Follow the user-provided official installer URLs for the six requested tools.
- Do not add Gemini or Cursor because they were not requested.
- Preserve an existing Neovim config; clone LazyVim only when `~/.config/nvim` is absent, and remove only the cloned checkout's `.git` metadata. In the default Linux run, `dotenv` runs first and its existing Neovim config wins, so the LazyVim starter is cloned only when dotenv is not selected or no config exists.
- Keep distro Neovim packages installed as fallback, but on Linux x86_64 install the official tarball under `/opt`, export and persist `/opt/nvim-linux-x86_64/bin` ahead of `/usr/bin`, and use that binary for headless sync and verification.
- Keep the module order dependency-safe: agent CLIs before `gentle-ai`; LazyVim after base.
- Use the x86_64 Neovim tarball only on x86_64; retain distro packages as the fallback on other architectures, and run LazyVim headlessly with `nvim --headless "+Lazy! sync" +qa`.
- Update the installed/configured-agent documentation in the same change so it no longer contradicts the new Claude module.
- Claude's installer has no documented non-interactive env var; reuse `run_vendor_installer`/`Invoke-RemoteScriptNoPrompt`, and use `https://claude.ai/install.ps1` on Windows with npm fallback documented.

## Evidence

- Baseline: `main` at `bfa8135`, version `3.6.5`.
- Existing working-tree file `tests/pi-session-container.sh` is unrelated and must remain untouched.
- LazyVim sync is isolated to a staged config and only runs again in quality gates after a fresh clone; existing configs get a non-mutating `nvim --version` check.
- Claude Code uses the vendor installer first on every OS, with the npm fallback using `--allow-scripts` on npm 12+.

## Verification

- Local gates passed: `bash -n setup-ai.sh`, PowerShell parse, Node syntax/list, retry-marker check, and `tests/agent-install-parity.sh`.
- `gga run --no-cache` passed with `GGA_PROVIDER=codex`; the configured OpenCode provider returned server errors and was not bypassed.
- Container matrix was attempted; every row was blocked by the unavailable Docker daemon (exit 125). ShellCheck is not installed. Windows and macOS remain unrun from this Linux host.
