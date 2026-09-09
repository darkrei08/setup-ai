#!/usr/bin/env node
// ============================================================================
// AI Dev Suite — cross-OS launcher
//
// Detects the OS and runs the right installer script:
//   win32            -> setup-ai.ps1  (via pwsh, falling back to powershell)
//   darwin / linux   -> setup-ai.sh   (via bash)
//
// With no selection flag on an interactive terminal it shows a gentle-ai-style
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
  { name: "base",         core: true,  desc: "System dev tools (git, gh, python, neovim, ...)" },
  { name: "node",         core: true,  desc: "Node.js + npm@latest" },
  { name: "bun",          core: true,  desc: "Bun runtime" },
  { name: "pi",           core: true,  desc: "pi.dev coding agent CLI" },
  { name: "go",           core: true,  desc: "Go toolchain" },
  { name: "dotenv",       core: true,  desc: "vekexasia/dotenv dotfiles (Linux only)" },
  { name: "ee",           core: true,  desc: "Engineering Excellence skill (all agents)" },
  { name: "pi-workflows", core: true,  desc: "pi-extensible-workflows resolution fix" },
  { name: "herdr",        core: true,  desc: "herdr terminal multiplexer" },
  { name: "gentle-ai",    core: true,  desc: "gentle-ai / gga + gentle-pi package" },
  { name: "engram",       core: true,  desc: "Engram persistent memory for pi" },
  { name: "codex",        core: true,  desc: "OpenAI Codex CLI" },
  { name: "antigravity",  core: true,  desc: "Google Antigravity CLI (agy)" },
  { name: "opencode",     core: true,  desc: "opencode agent CLI" },
  { name: "cockpit",      core: false, desc: "cockpit-tools desktop GUI (optional)" },
];

// dotenv is Linux-only; drop it from the Windows menu.
const isWin = process.platform === "win32";
const menuModules = MODULES.filter((m) => !(isWin && m.name === "dotenv"));

const argv = process.argv.slice(2);
const has = (f) => argv.includes(f);
const getVal = (f) => {
  const i = argv.indexOf(f);
  if (i >= 0 && argv[i + 1]) return argv[i + 1];
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
      // Fall back to Windows PowerShell 5.
      const ps1 = join(PKG_ROOT, "setup-ai.ps1");
      const fb = spawn("powershell", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ps1, ...passArgs], { stdio: "inherit" });
      fb.on("exit", (c) => process.exit(c ?? 0));
      return;
    }
    console.error(`Failed to launch installer: ${err.message}`);
    process.exit(1);
  });
  child.on("exit", (code) => process.exit(code ?? 0));
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

// ---- interactive multi-select (gentle-ai style) ---------------------------
function interactiveMenu() {
  return new Promise((resolve) => {
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
    stdin.setRawMode(true);
    stdin.resume();
    stdin.setEncoding("utf8");
    render(true);

    const cleanup = () => {
      stdin.setRawMode(false);
      stdin.pause();
      stdin.removeListener("data", onData);
    };

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
  });
}

// ---- numbered fallback (no TTY) -------------------------------------------
function defaultSelection() {
  return menuModules.filter((m) => m.core).map((m) => m.name);
}

async function main() {
  if (has("--help") || has("-h")) return runScript(toScriptArgs("help"));
  if (has("--list")) return runScript(toScriptArgs("list"));
  if (has("--all")) return runScript(toScriptArgs("all"));

  const only = getVal("--only");
  if (only) return runScript(toScriptArgs("only", only));

  if (has("--yes") || has("-y")) return runScript(toScriptArgs("yes"));

  // No selection flag: interactive menu if we have a TTY, else core defaults.
  if (process.stdin.isTTY && process.stdout.isTTY) {
    const chosen = await interactiveMenu();
    if (!chosen.length) {
      console.log("Nothing selected — exiting.");
      process.exit(0);
    }
    return runScript(toScriptArgs("only", chosen.join(",")));
  }

  console.log("No TTY detected — installing the core module set. Use --only/--all to customize.");
  return runScript(toScriptArgs("only", defaultSelection().join(",")));
}

main();
