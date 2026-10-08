# Install matrix — official methods

The exact command setup-ai runs for each tool, per OS. Everything here is the
vendor's **own, current** method; setup-ai only orchestrates it and verifies the
result.

| Tool | binary | macOS | Linux | Windows |
|---|---|---|---|---|
| Claude Code | `claude` | `curl -fsSL https://claude.ai/install.sh | bash` | same | `npm install -g @anthropic-ai/claude-code` |
| Antigravity | `agy` | `curl -fsSL https://antigravity.google/cli/install.sh \| bash` | same | `irm https://antigravity.google/cli/install.ps1 \| iex` |
| Codex | `codex` | `brew install --cask codex` | `curl -fsSL https://chatgpt.com/codex/install.sh \| sh` | `irm https://chatgpt.com/codex/install.ps1 \| iex` |
| pi | `pi` | `curl -fsSL https://pi.dev/install.sh \| sh` | same | `irm https://pi.dev/install.ps1 \| iex` |
| herdr | `herdr` | `brew install herdr` | `curl -fsSL https://herdr.dev/install.sh \| sh` | `irm https://herdr.dev/install.ps1 \| iex` |
| gentle-ai | `gentle-ai` / `gga` | `brew install gentleman-programming/tap/gentle-ai` | `curl -fsSL https://raw.githubusercontent.com/Gentleman-Programming/gentle-ai/main/scripts/install.sh \| bash` | `irm https://raw.githubusercontent.com/Gentleman-Programming/gentle-ai/main/scripts/install.ps1 \| iex` |
| Go | `go` | `brew install go` | distro pkg | `winget install -e --id GoLang.Go` |
| opencode | `opencode` | `brew install anomalyco/tap/opencode` | `curl -fsSL https://opencode.ai/install \| bash` | `npm i -g opencode-ai` |
| cockpit-tools *(opt-in GUI)* | app | `brew install --cask cockpit-tools` | `.deb`/`.rpm`/`.AppImage` | `.msi` |
| CLIProxyAPI + CPA Usage Keeper *(opt-in)* | existing dotenv Compose stack | Docker Compose v2 | same | same |
| LazyVim | Neovim config | clone `https://github.com/LazyVim/starter`, then `nvim --headless "+Lazy! sync" +qa` | x86_64 tarball + same headless sync; distro Neovim on other architectures | package Neovim + same headless sync |
| Engineering Excellence | skill | `npx skills@latest add darkrei08/Engineering-Excellence --agent <agent>` | same | same |

Back to the [README](../README.md) · Related: [modules](./modules.md).
