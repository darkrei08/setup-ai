#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${ROOT}" node <<'NODE'
const fs = require('node:fs');
const path = require('node:path');
const root = process.env.ROOT;
const sh = fs.readFileSync(path.join(root, 'setup-ai.sh'), 'utf8');
const ps = fs.readFileSync(path.join(root, 'setup-ai.ps1'), 'utf8');
const mjs = fs.readFileSync(path.join(root, 'bin/menu.mjs'), 'utf8');
const parse = (value) => value.replaceAll(',', ' ').trim().split(/\s+/).filter(Boolean);
const bashPreset = parse(sh.match(/GENTLE_AI_PRESET=\(([^)]+)\)/)?.[1] ?? '');
const powershellPreset = ps.match(/\$GentleAiPreset = @\(([^)]+)\)/)?.[1]
  .split(',').map((item) => item.replaceAll("'", '').trim()) ?? [];
const nodePreset = parse(mjs.match(/const GENTLE_AI = \[([^\]]+)\]/)?.[1].replaceAll('"', '') ?? '');
const expected = ['base', 'node', 'pi', 'pi-workflows', 'gentle-ai'];
if (JSON.stringify(bashPreset) !== JSON.stringify(expected) ||
    JSON.stringify(powershellPreset) !== JSON.stringify(expected) ||
    JSON.stringify(nodePreset) !== JSON.stringify(expected)) {
  throw new Error(JSON.stringify({ bashPreset, powershellPreset, nodePreset, expected }, null, 2));
}
for (const file of [sh, ps]) {
  if (!file.includes('gentle-ai =') && !file.includes("'gentle-ai'")) {
    throw new Error('gentle-ai registry entry is missing');
  }
}
console.log('Gentle AI preset parity passed');
NODE
