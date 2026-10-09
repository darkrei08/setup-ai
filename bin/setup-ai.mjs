#!/usr/bin/env node
// ============================================================================
// AI Dev Suite — cross-OS launcher
//
// Detects the OS and runs the right installer script:
//   win32            -> setup-ai.ps1  (via PowerShell 7.3+)
//   darwin / linux   -> setup-ai.sh   (via bash)
//
// With no selection flag on an interactive terminal it shows an progressive
// preset/category menu, then passes the chosen modules to the platform script as
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
import { chosenNames, createRenderer, initState, reduce, view } from "./menu.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PKG_ROOT = join(__dirname, "..");

// Canonical module list (mirrors the registries in setup-ai.sh / setup-ai.ps1).
// core:false => optional (unchecked by default in the menu).
const MODULES = [
  { name: "base",         core: true,  category: "System", desc: "System packages (build tools, git, gh, python, neovim, jq, imagemagick, go, clipboard)" },
  { name: "node",         core: true,  category: "System", desc: "Node.js v22 + npm@latest (nvm on Unix, winget on Windows)" },
  { name: "bun",          core: true,  category: "System", desc: "Bun runtime" },
  { name: "pi",           core: true,  category: "Agents", desc: "pi.dev coding agent CLI" },
  { name: "dotenv",       core: true,  category: "System", desc: "darkrei08/dotenv dotfiles (Linux only: clones + runs setup_env.sh)" },
  { name: "ai-memory",    core: true,  category: "Memory & review", desc: "ai-memory-kit aimem CLI and templates" },
  { name: "lazyvim",      core: true,  category: "Editors", desc: "Neovim x86_64 tarball and LazyVim starter (headless sync)" },
  { name: "pi-packages",  core: true,  category: "Skills & workflows", desc: "Extra Pi packages from a declarative manifest (pi-packages.txt)" },
  { name: "go",           core: true,  category: "System", desc: "Go toolchain" },
  { name: "ee",           core: true,  category: "Skills & workflows", desc: "Engineering Excellence skill (npx skills add, all detected agents)" },
  { name: "skills",       core: true,  category: "Skills & workflows", desc: "Upstream agent skills (herdr, grilling, research, typescript-advanced, show-me, ...) via npx skills add" },
  { name: "pi-workflows", core: true,  category: "Skills & workflows", desc: "pi-extensible-workflows (published release + npm 12 remote sources for pi installs)" },
  { name: "herdr",        core: true,  category: "System", desc: "herdr terminal multiplexer" },
  { name: "claude-code",  core: true,  category: "Agents", desc: "Anthropic Claude Code CLI" },
  { name: "codex",        core: true,  category: "Agents", desc: "OpenAI Codex CLI" },
  { name: "antigravity",  core: true,  category: "Agents", desc: "Google Antigravity CLI (agy)" },
  { name: "opencode",     core: true,  category: "Agents", desc: "opencode agent CLI (opencode-ai)" },
  { name: "gentle-ai",    core: true,  category: "Memory & review", desc: "gentle-ai / gga ecosystem configurator (per-agent select + MCP) + gentle-pi" },
  { name: "cockpit",      core: false, category: "Extras", desc: "cockpit-tools desktop GUI app (optional, CC BY-NC-SA)" },
  { name: "rotator",      core: false, category: "Gateway", desc: "tuxevil-rotator multi-account Gemini/Antigravity gateway (installed and started in the background; optional, opt-in)" },
  { name: "extras",       core: false, category: "Extras", desc: "Shared Taste, Humanizer, and HeroUI skills plus Impeccable (optional)" },
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

// ---- interactive progressive menu -----------------------------------------
function interactiveMenu() {
  return new Promise((resolve, reject) => {
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

    const draw = createRenderer(process.stdout);
    let state = initState(menuModules);
    draw(view(state, menuModules));

    const cleanup = () => {
      try {
        stdin.setRawMode(false);
      } catch (err) {
        console.error(`Could not restore terminal mode: ${err instanceof Error ? err.message : err}`);
      }
      stdin.pause();
      stdin.removeListener("data", onData);
      stdin.removeListener("end", onEnd);
    };

    // If stdin closes before a choice (e.g. npx consumed it), fall back instead
    // of hanging or exiting silently.
    const onEnd = () => { cleanup(); reject(new Error("stdin closed before a choice was made")); };

    const onData = (key) => {
      state = reduce(state, key, menuModules);
      if (state.done === "quit") {
        cleanup();
        process.stdout.write("\nAborted.\n");
        process.exit(130);
      } else if (state.done === "confirm") {
        cleanup();
        resolve(chosenNames(state, menuModules));
      } else {
        draw(view(state, menuModules));
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
