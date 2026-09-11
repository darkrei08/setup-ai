#!/usr/bin/env node
// ============================================================================
// AI Dev Suite — cross-OS launcher
//
// Detects the OS and runs the right installer script:
//   win32            -> setup-ai.ps1  (via PowerShell 7.3+)
//   darwin / linux   -> setup-ai.sh   (via bash)
//
// With no selection flag on an interactive terminal it shows an arrow-key
// arrow-key multi-select menu, then passes the chosen modules to the platform
// script as --only. Zero runtime dependencies.
//
// Usage:
//   npx @darkrei08/setup-ai                 # interactive menu (or core if no TTY)
//   npx @darkrei08/setup-ai --all
//   npx @darkrei08/setup-ai --only pi,codex,opencode
//   npx @darkrei08/setup-ai --yes           # core set, no prompt
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
  { name: "base",         core: true,  desc: "System packages (build tools, git, gh, python, neovim, jq, imagemagick, go)" },
  { name: "node",         core: true,  desc: "Node.js v22 + npm@latest (nvm on Unix, winget on Windows)" },
  { name: "bun",          core: true,  desc: "Bun runtime" },
  { name: "pi",           core: true,  desc: "pi.dev coding agent CLI" },
  { name: "go",           core: true,  desc: "Go toolchain" },
  { name: "dotenv",       core: true,  desc: "vekexasia/dotenv dotfiles (Linux only: clones + runs setup_env.sh)" },
  { name: "ee",           core: true,  desc: "Engineering Excellence skill (npx skills add, all detected agents)" },
  { name: "skills",       core: true,  desc: "Upstream agent skills (herdr, grilling, research, typescript-advanced, show-me, ...) via npx skills add" },
  { name: "pi-workflows", core: true,  desc: "pi-extensible-workflows (fix module resolution for pi extensions)" },
  { name: "herdr",        core: true,  desc: "herdr terminal multiplexer" },
  { name: "gentle-ai",    core: true,  desc: "gentle-ai / gga ecosystem configurator (per-agent select + MCP) + gentle-pi" },
  { name: "codex",        core: true,  desc: "OpenAI Codex CLI" },
  { name: "antigravity",  core: true,  desc: "Google Antigravity CLI (agy)" },
  { name: "opencode",     core: true,  desc: "opencode agent CLI (opencode-ai)" },
  { name: "cockpit",      core: false, desc: "cockpit-tools desktop GUI app (optional, CC BY-NC-SA)" },
  { name: "rotator",      core: false, desc: "tuxevil-rotator multi-account Gemini/Antigravity gateway (optional, opt-in)" },
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
function toScriptArgs(mode, csv) {
  if (isWin) {
    if (mode === "all") return ["-All"];
    if (mode === "only") return ["-Only", csv];
    if (mode === "yes") return ["-Yes"];
    if (mode === "list") return ["-List"];
    if (mode === "help") return ["-Help"];
    return [];
  }
  if (mode === "all") return ["--all"];
  if (mode === "only") return ["--only", csv];
  if (mode === "yes") return ["--yes"];
  if (mode === "list") return ["--list"];
  if (mode === "help") return ["--help"];
  return [];
}

// ---- interactive multi-select ---------------------------------------------
function interactiveMenu() {
  return new Promise((resolve, reject) => {
    const items = menuModules.map((m) => ({ ...m, checked: m.core }));
    let cursor = 0;
    const out = process.stdout;

    const render = (first) => {
      if (!first) out.write(`\x1b[${items.length + 3}A`); // move up to redraw
      out.write("\x1b[0J"); // clear below
      out.write("\x1b[1mAI Dev Suite — select modules\x1b[0m  (↑/↓ move · Space toggle · a all · Enter confirm · q quit)\n\n");
      items.forEach((it, i) => {
        const pointer = i === cursor ? "\x1b[36m>\x1b[0m " : "  ";
        const box = it.checked ? "\x1b[32m[x]\x1b[0m" : "[ ]";
        const tag = it.core ? "" : " \x1b[33m(optional)\x1b[0m";
        out.write(`${pointer}${box} ${it.name.padEnd(14)} ${it.desc}${tag}\n`);
      });
      out.write("\n");
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
    render(true);

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
  if (has("--all")) return runScript(toScriptArgs("all"));

  const hasOnly = argv.some((arg) => arg === "--only" || arg.startsWith("--only="));
  if (hasOnly) {
    const only = getVal("--only");
    if (!only || !only.trim()) {
      console.error("--only requires a non-empty comma-separated module list.");
      process.exitCode = 2;
      return;
    }
    return runScript(toScriptArgs("only", only));
  }

  if (has("--yes") || has("-y")) return runScript(toScriptArgs("yes"));

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
  return runScript(toScriptArgs("only", chosen.join(",")));
}

main().catch((err) => {
  console.error(`setup-ai launcher error: ${err?.message || err}`);
  process.exit(1);
});
