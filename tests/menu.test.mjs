// Drives the progressive menu with scripted keys and a tiny terminal emulator.
// Run: node tests/menu.test.mjs
import assert from "node:assert/strict";
import { chosenNames, createRenderer, initState, reduce, view } from "../bin/menu.mjs";

const modules = [
  { name: "base", category: "System", core: true, desc: "d" },
  { name: "node", category: "System", core: true, desc: "d" },
  { name: "pi", category: "Agents", core: true, desc: "d" },
  { name: "codex", category: "Agents", core: false, desc: "x".repeat(300) },
  { name: "cliproxyapi", category: "Gateway", core: false, desc: "d" },
];
const ENTER = "\r", DOWN = "j", SPACE = " ", ESC = "\x1b";

function run(keys) {
  let s = initState(modules);
  const frames = [view(s, modules)];
  for (const k of keys) { s = reduce(s, k, modules); if (s.done) break; frames.push(view(s, modules)); }
  return { s, frames };
}

// Terminal emulator: handles ESC[nA, \r, ESC[J and newlines.
function screenAfter(frames, cols = 80) {
  const rows = [];
  let y = 0;
  const out = { columns: cols, write(data) {
    for (const m of data.replace(/\x1b\[[0-9;]*m/g, "").matchAll(/\x1b\[(\d*)([AJ])|\r|\n|([^\x1b\r\n]+)/g)) {
      if (m[2] === "A") y -= Number(m[1] || 1);
      else if (m[2] === "J") rows.length = y;
      else if (m[0] === "\n") y++;
      else if (m[3] !== undefined) {
        const plain = m[3].replace(/\x1b\[[0-9;]*m/g, "");
        assert.ok(plain.length < cols, "line would wrap");
        rows[y] = plain;
      }
    }
  } };
  const draw = createRenderer(out);
  frames.forEach(draw);
  return rows.filter((r) => r !== undefined);
}

// Presets
assert.deepEqual(chosenNames(run([DOWN, ENTER]).s, modules), modules.map((m) => m.name)); // Everything
assert.deepEqual(chosenNames(run([ENTER]).s, modules), ["base", "node", "pi"]); // Core
assert.deepEqual(chosenNames(run([DOWN, DOWN, DOWN, ENTER]).s, modules), ["base", "node", "pi"]); // Minimal
// Custom: Agents category (2nd), toggle codex, back, continue, confirm
let r = run([DOWN, DOWN, ENTER, DOWN, ENTER, DOWN, SPACE, ESC, DOWN, DOWN, ENTER, ENTER]);
assert.equal(r.s.done, "confirm");
assert.deepEqual(chosenNames(r.s, modules), ["base", "node", "pi", "codex"]);
// 'a' toggles all/none within the category
r = run([DOWN, DOWN, ENTER, ENTER, "a"]);
assert.equal(r.s.screen, "modules");
assert.deepEqual(chosenNames(r.s, modules), ["pi"]);
// Backspace goes back, q quits, summary Esc returns to categories for Custom
assert.equal(run([DOWN, DOWN, ENTER, ENTER, "\x7f"]).s.screen, "categories");
assert.equal(run(["q"]).s.done, "quit");
assert.equal(run([DOWN, DOWN, ENTER, DOWN, DOWN, DOWN, ENTER, ESC]).s.screen, "categories");

// Rendering: banner appears once however many frames are drawn, no wrapping.
const long = run(Array(6).fill(DOWN).concat([ENTER, DOWN, ENTER, ESC, ESC])).frames;
assert.ok(long.length > 6);
for (const cols of [80, 40]) {
  const rows = screenAfter(long, cols);
  assert.equal(rows.filter((x) => x.includes("AI Dev Suite")).length, 1);
}
console.log("menu tests passed");
