#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${ROOT}" node <<'NODE'
const fs = require('node:fs');
const path = require('node:path');
const root = process.env.ROOT;
const sh = fs.readFileSync(path.join(root, 'setup-ai.sh'), 'utf8');
const ps = fs.readFileSync(path.join(root, 'setup-ai.ps1'), 'utf8');
const mjs = fs.readFileSync(path.join(root, 'bin/setup-ai.mjs'), 'utf8');
const bashModules = sh.match(/MODULE_ORDER=\(([^)]+)\)/)[1].trim().split(/\s+/);
const powershellModules = ps.match(/\$ModuleOrder = @\(([^)]+)\)/)[1]
  .split(',').map((item) => item.replaceAll("'", '').trim());
const nodeModules = [...mjs.matchAll(/\{ name: "([^"]+)"/g)].map((match) => match[1]);
if (JSON.stringify(bashModules) !== JSON.stringify(powershellModules) ||
    JSON.stringify(bashModules) !== JSON.stringify(nodeModules)) {
  throw new Error(JSON.stringify({ bashModules, powershellModules, nodeModules }, null, 2));
}
for (const needle of [
  'https://claude.ai/install.sh',
  'run_vendor_installer "claude-code"',
  'nvim --headless "+Lazy! sync" +qa',
  'LAZYVIM_CLONED',
  '/opt/nvim-linux-x86_64/bin',
]) {
  if (!sh.includes(needle)) throw new Error(`Bash missing ${needle}`);
}
for (const needle of [
  'https://claude.ai/install.ps1',
  'Invoke-RemoteScriptNoPrompt',
  'npm install -g @anthropic-ai/claude-code',
  'function Mod-ClaudeCode',
  'nvim --headless "+Lazy! sync" +qa',
  '$script:LazyVimCloned',
]) {
  if (!ps.includes(needle)) throw new Error(`PowerShell missing ${needle}`);
}
console.log(`PASS: ${bashModules.length} module entries match across Bash, PowerShell, and Node`);
NODE
