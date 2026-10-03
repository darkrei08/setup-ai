#!/usr/bin/env node
// ============================================================================
// AI Dev Suite — cross-OS launcher
//
// Detects the OS and runs the right installer script:
//   win32            -> setup-ai.ps1  (via PowerShell 7.3+)
//   darwin / linux   -> setup-ai.sh   (via bash)
//
// With no selection flag on an interactive terminal it shows an arrow-key
// multi-select menu, then passes the chosen modules to the platform script as
// --only. Zero runtime dependencies.
//
// Usage:
//   npx @darkrei08/setup-ai                 # interactive menu (or core if no TTY)
//   npx @darkrei08/setup-ai --all
//   npx @darkrei08/setup-ai --only pi,codex,opencode
//   npx @darkrei08/setup-ai --yes           # core set, no prompt
//   npx @darkrei08/setup-ai --verbose       # core set, unattended, spaced output
//   npx @darkrei08/setup-ai --dry-run       # report the install plan without writing
//   npx @darkrei08/setup-ai --uninstall [--yes] [--only ...] [--purge]
//   npx @darkrei08/setup-ai --list | --help
// ============================================================================

import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import process from "node:process";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PKG_ROOT = join(__dirname, "..");

// Canonical module list (mirrors the registries in setup-ai.sh / setup-ai.ps1).
// core:false => optional (unchecked by default in the menu).
const MODULES = [
  { name: "base",         core: true,  desc: "System packages (build tools, git, gh, python, neovim, jq, imagemagick, go, clipboard)" },
  { name: "node",         core: true,  desc: "Node.js v22 + npm@latest (nvm on Unix, winget on Windows)" },
  { name: "bun",          core: true,  desc: "Bun runtime" },
  { name: "pi",           core: true,  desc: "pi.dev coding agent CLI" },
  { name: "dotenv",       core: true,  desc: "darkrei08/dotenv dotfiles (Linux only: clones + runs setup_env.sh)" },
  { name: "ai-memory",    core: true,  desc: "ai-memory-kit aimem CLI and templates" },
  { name: "lazyvim",      core: true,  desc: "Neovim x86_64 tarball and LazyVim starter (headless sync)" },
  { name: "pi-packages",  core: true,  desc: "Extra Pi packages from a declarative manifest (pi-packages.txt)" },
  { name: "go",           core: true,  desc: "Go toolchain" },
  { name: "ee",           core: true,  desc: "Engineering Excellence skill (npx skills add, all detected agents)" },
  { name: "skills",       core: true,  desc: "Upstream agent skills (herdr, grilling, research, typescript-advanced, show-me, ...) via npx skills add" },
  { name: "pi-workflows", core: true,  desc: "pi-extensible-workflows (published release + npm 12 remote sources for pi installs)" },
  { name: "herdr",        core: true,  desc: "herdr terminal multiplexer" },
  { name: "claude-code",  core: true,  desc: "Anthropic Claude Code CLI" },
  { name: "codex",        core: true,  desc: "OpenAI Codex CLI" },
  { name: "antigravity",  core: true,  desc: "Google Antigravity CLI (agy)" },
  { name: "opencode",     core: true,  desc: "opencode agent CLI (opencode-ai)" },
  { name: "gentle-ai",    core: true,  desc: "gentle-ai / gga ecosystem configurator (per-agent select + MCP) + gentle-pi" },
  { name: "cockpit",      core: false, desc: "cockpit-tools desktop GUI app (optional, CC BY-NC-SA)" },
  { name: "rotator",      core: false, desc: "tuxevil-rotator multi-account Gemini/Antigravity gateway (installed and started in the background; optional, opt-in)" },
  { name: "extras",       core: false, desc: "Shared Taste, Humanizer, and HeroUI skills plus Impeccable (optional)" },
];

// dotenv is Linux-only; drop it from the Windows menu.
const isWin = process.platform === "win32";
const menuModules = MODULES.filter((m) => !(isWin && m.name === "dotenv"));

const argv = process.argv.slice(2);
const has = (f) => argv.includes(f);
const getVal = (f) => {
  const i = argv.indexOf(f);
  if (i >= 0) {
    const value = argv[i + 1];
    if (value && !value.startsWith("-")) return value;
    return null;
  }
  const eq = argv.find((a) => a.startsWith(f + "="));
  return eq ? eq.split("=").slice(1).join("=") : null;
};

function runScript(passArgs) {
  let cmd, cmdArgs;
  if (isWin) {
    const ps1 = join(PKG_ROOT, "setup-ai.ps1");
    const psExe = process.env.SETUP_AI_PWSH || "pwsh";
    cmdArgs = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ps1, ...passArgs];
    cmd = psExe;
  } else {
    const sh = join(PKG_ROOT, "setup-ai.sh");
    cmd = "bash";
    cmdArgs = [sh, ...passArgs];
  }
  const child = spawn(cmd, cmdArgs, { stdio: "inherit" });
  child.on("error", (err) => {
    if (isWin && cmd === "pwsh") {
      console.error("PowerShell 7.3+ is required to run setup-ai.ps1. Install PowerShell 7.3 or newer and retry.");
    } else {
      console.error(`Failed to launch installer: ${err.message}`);
    }
    process.exit(1);
  });
  child.on("exit", (code, signal) => {
    // A signal-terminated child reports code === null; that is a failure, not
    // success, so never collapse it to 0.
    if (code === null) {
      console.error(`Installer terminated by signal ${signal ?? "unknown"}.`);
      process.exit(1);
    }
    process.exit(code);
  });
}

// Translate a chosen module list into the platform script's flag.
function toScriptArgs(mode, csv, unattended = false) {
  let args;
  if (isWin) {
    if (mode === "all") args = ["-All"];
    else if (mode === "only") args = ["-Only", csv];
    else if (mode === "yes") args = ["-Yes"];
    else if (mode === "list") args = ["-List"];
    else if (mode === "help") args = ["-Help"];
    else args = [];
  } else {
    if (mode === "all") args = ["--all"];
    else if (mode === "only") args = ["--only", csv];
    else if (mode === "yes") args = ["--yes"];
    else if (mode === "list") args = ["--list"];
    else if (mode === "help") args = ["--help"];
    else args = [];
  }
  if (unattended) args.push(isWin ? "-Yes" : "--yes");
  if (has("--verbose") || has("-v")) args.push(isWin ? "-Verbose" : "--verbose");
  if (has("--dry-run")) args.push(isWin ? "-DryRun" : "--dry-run");
  return args;
}

// ---- interactive multi-select ---------------------------------------------
function interactiveMenu() {
  return new Promise((resolve, reject) => {
    const items = menuModules.map((m) => ({ ...m, checked: m.core }));
    let cursor = 0;
    const out = process.stdout;

    const render = () => {
      const selected = items.filter((it) => it.checked).length;
      out.write("\x1b[2J\x1b[H");
      out.write("\x1b[1;36m+----------------------------------------------------------------------+\x1b[0m\n");
      out.write("\x1b[1;36m|\x1b[0m                    \x1b[1mAI Dev Suite setup\x1b[0m                         \x1b[1;36m|\x1b[0m\n");
      out.write("\x1b[1;36m+----------------------------------------------------------------------+\x1b[0m\n");
      out.write(`  Select modules to install: \x1b[1m${selected}/${items.length}\x1b[0m selected\n`);
      out.write("  Arrow keys/j-k move   Space toggle   a all   Enter confirm   q quit\n\n");
      items.forEach((it, i) => {
        const pointer = i === cursor ? "\x1b[36m>\x1b[0m" : " ";
        const box = it.checked ? "\x1b[32m[x]\x1b[0m" : "[ ]";
        const tag = it.core ? "" : " \x1b[33m(optional)\x1b[0m";
        out.write(`${pointer} ${box} ${String(i + 1).padStart(2, " ")} ${it.name.padEnd(16)}${tag}\n`);
        out.write(`       ${it.desc}\n\n`);
      });
      out.write("  Selected modules run in dependency order.\n");
    };

    const stdin = process.stdin;
    if (typeof stdin.setRawMode !== "function") {
      return reject(new Error("stdin is not a raw-capable TTY"));
    }
    try {
      stdin.setRawMode(true);
    } catch (err) {
      return reject(err);
    }
    stdin.resume();
    stdin.setEncoding("utf8");
    render();

    const cleanup = () => {
      let cleanupError = null;
      try {
        stdin.setRawMode(false);
      } catch (err) {
        cleanupError = err instanceof Error ? err : new Error(String(err));
        console.error(`Could not restore terminal mode: ${cleanupError.message}`);
      }
      stdin.pause();
      stdin.removeListener("data", onData);
      stdin.removeListener("end", onEnd);
      return cleanupError;
    };

    // If stdin closes before a choice (e.g. npx consumed it), fall back instead
    // of hanging or exiting silently.
    const onEnd = () => { cleanup(); reject(new Error("stdin closed before a choice was made")); };

    const onData = (key) => {
      if (key === "\x03" || key === "q") { // ctrl-c / q
        cleanup();
        out.write("\nAborted.\n");
        process.exit(130);
      } else if (key === "\x1b[A" || key === "k") {
        cursor = (cursor - 1 + items.length) % items.length; render();
      } else if (key === "\x1b[B" || key === "j") {
        cursor = (cursor + 1) % items.length; render();
      } else if (key === " ") {
        items[cursor].checked = !items[cursor].checked; render();
      } else if (key === "a") {
        const allOn = items.every((i) => i.checked);
        items.forEach((i) => (i.checked = !allOn)); render();
      } else if (key === "\r" || key === "\n") {
        cleanup();
        resolve(items.filter((i) => i.checked).map((i) => i.name));
      }
    };
    stdin.on("data", onData);
    stdin.on("end", onEnd);
  });
}

// ---- numbered fallback (no TTY) -------------------------------------------
function defaultSelection() {
  return menuModules.filter((m) => m.core).map((m) => m.name);
}

async function main() {
  // Always emit a first line so the user sees the launcher started, even if
  // something downstream fails (this is what "npx returns to prompt silently"
  // needed).
  console.log(`setup-ai launcher · ${process.platform}`);

  if (has("--help") || has("-h")) return runScript(toScriptArgs("help"));
  if (has("--list")) return runScript(toScriptArgs("list"));

  // An unknown flag is a mistake, not a reason to open the module menu: `--verbose`
  // used to be forwarded while the run still turned interactive.
  const knownFlags = new Set(["--help", "-h", "--list", "--all", "--only", "--yes", "-y", "--verbose", "-v", "--dry-run", "--uninstall", "--purge"]);
  const unknown = argv.filter((arg, i) => {
    if (arg === "--only" || arg.startsWith("--only=") || argv[i - 1] === "--only") return false;
    return !knownFlags.has(arg);
  });
  if (unknown.length > 0) {
    console.error(`Unknown argument(s): ${unknown.join(", ")}. Run with --help to see the supported flags.`);
    process.exitCode = 2;
    return;
  }

  if (has("--purge") && !has("--uninstall")) {
    console.error("--purge is only valid with --uninstall.");
    process.exitCode = 2;
    return;
  }

  const unattended = has("--yes") || has("-y") || has("--verbose") || has("-v") || has("--dry-run");
  if (has("--uninstall")) {
    const uninstallArgs = [isWin ? "-Uninstall" : "--uninstall"];
    const hasOnly = argv.some((arg) => arg === "--only" || arg.startsWith("--only="));
    const only = getVal("--only");
    if (hasOnly && (!only || !only.trim())) {
      console.error("--only requires a non-empty comma-separated module list.");
      process.exitCode = 2;
      return;
    }
    if (only) uninstallArgs.push(isWin ? "-Only" : "--only", only);
    if (has("--yes") || has("-y")) uninstallArgs.push(isWin ? "-Yes" : "--yes");
    if (has("--purge") && !isWin) uninstallArgs.push("--purge");
    if (has("--dry-run")) uninstallArgs.push(isWin ? "-DryRun" : "--dry-run");
    if (has("--verbose") || has("-v")) uninstallArgs.push(isWin ? "-Verbose" : "--verbose");
    return runScript(uninstallArgs);
  }
  if (has("--all")) return runScript(toScriptArgs("all", undefined, unattended));

  const hasOnly = argv.some((arg) => arg === "--only" || arg.startsWith("--only="));
  if (hasOnly) {
    const only = getVal("--only");
    if (!only || !only.trim()) {
      console.error("--only requires a non-empty comma-separated module list.");
      process.exitCode = 2;
      return;
    }
    return runScript(toScriptArgs("only", only, unattended));
  }

  // --verbose and --dry-run ask for output, not for a menu: they run the core set unattended.
  if (has("--yes") || has("-y") || has("--verbose") || has("-v") || has("--dry-run")) return runScript(toScriptArgs("yes")); // toScriptArgs forwards --dry-run.

  // No selection flag: try the interactive menu; fall back cleanly if the
  // terminal/stdin can't drive it (common under some npx/CI shells).
  let chosen = null;
  if (process.stdin.isTTY && process.stdout.isTTY) {
    try {
      chosen = await interactiveMenu();
    } catch (err) {
      console.log(`\n(interactive menu unavailable: ${err.message})`);
      chosen = null;
    }
  } else {
    console.log("No interactive terminal detected.");
  }

  if (!chosen) {
    console.log("Installing the CORE set. Customize with:");
    console.log("  npx github:darkrei08/setup-ai --only pi,codex,opencode");
    console.log("  npx github:darkrei08/setup-ai --all        (everything)");
    console.log("  npx github:darkrei08/setup-ai --list       (see modules)\n");
    chosen = defaultSelection();
  }

  if (!chosen.length) {
    console.log("Nothing selected — exiting.");
    process.exit(0);
  }
  return runScript(toScriptArgs("only", chosen.join(","), unattended));
}

main().catch((err) => {
  console.error(`setup-ai launcher error: ${err?.message || err}`);
  process.exit(1);
});
