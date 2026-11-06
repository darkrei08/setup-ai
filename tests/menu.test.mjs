// Drives the progressive menu with scripted keys and a tiny terminal emulator.
// Run: node tests/menu.test.mjs
import assert from "node:assert/strict";
import { chosenNames, createRenderer, frameWidth, initState, reduce, supportsCursorUp, view } from "../bin/menu.mjs";

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

// Terminal emulator: handles ESC[nA, ESC[2J, ESC[H, \r, ESC[J and newlines.
function screenAfter(frames, cols = 80, relative = true) {
  const rows = [];
  let y = 0;
  const out = { columns: cols, write(data) {
    for (const m of data.replace(/\x1b\[[0-9;]*m/g, "").matchAll(/\x1b\[(\d*)([AJH])|\r|\n|([^\x1b\r\n]+)/g)) {
      if (m[2] === "A") y -= Number(m[1] || 1);
      else if (m[2] === "H") y = 0;
      else if (m[2] === "J") rows.length = m[1] === "2" ? (y = 0) : y;
      else if (m[0] === "\n") y++;
      else if (m[3] !== undefined) {
        const plain = m[3].replace(/\x1b\[[0-9;]*m/g, "");
        assert.ok(plain.length < cols, "line would wrap");
        rows[y] = plain;
      }
    }
  } };
  const draw = createRenderer(out, relative);
  frames.forEach(draw);
  return rows.filter((r) => r !== undefined);
}

// S1: frame geometry follows terminal width and centers the title from its own length.
const stripAnsi = (line) => line.replace(/\x1b\[[0-9;]*m/g, "");
assert.deepEqual([21, 40, 60, 72, 80, 100].map(frameWidth), [18, 37, 57, 69, 70, 70]);
assert.equal(frameWidth(), 70);
assert.equal(frameWidth(Number.NaN), 70);
for (const cols of [40, 60, 72, 80, 100]) {
  const [top, middle, bottom] = view(initState(modules), modules, cols).slice(0, 3).map(stripAnsi);
  assert.ok([top, middle, bottom].every((line) => line.length <= cols - 1));
  assert.equal(top.length, middle.length);
  assert.equal(middle.length, bottom.length);
  assert.ok([top, middle, bottom].every((line) => /^[+|].*[+|]$/.test(line)));
  const inner = frameWidth(cols);
  const title = "AI Dev Suite setup";
  assert.equal(middle.indexOf(title) - 1, Math.floor((inner - title.length) / 2));
}

// S2: every non-custom preset displays the size of its confirmed selection.
for (const [index, label] of [[0, "Core"], [1, "Everything"], [3, "Minimal"], [4, "Gentle AI"]]) {
  let confirmed = initState(modules);
  for (let i = 0; i < index; i++) confirmed = reduce(confirmed, DOWN, modules);
  confirmed = reduce(confirmed, ENTER, modules);
  const count = chosenNames(confirmed, modules).length;
  const presetRow = view({ ...initState(modules), cursor: index }, modules)
    .find((line) => stripAnsi(line).includes(label));
  assert.ok(new RegExp(`(^| )${count} modules`).test(stripAnsi(presetRow ?? "")));
}

// Presets
assert.deepEqual(chosenNames(run([DOWN, ENTER]).s, modules), modules.map((m) => m.name)); // Everything
assert.deepEqual(chosenNames(run([ENTER]).s, modules), ["base", "node", "pi"]); // Core
assert.deepEqual(chosenNames(run([DOWN, DOWN, DOWN, ENTER]).s, modules), ["base", "node", "pi"]); // Minimal
const gentleModules = [
  ...modules,
  { name: "pi-workflows", category: "Skills & workflows", core: false, desc: "d" },
  { name: "gentle-ai", category: "Memory & review", core: false, desc: "d" },
];
let gentleState = initState(gentleModules);
for (const key of [DOWN, DOWN, DOWN, DOWN, ENTER]) gentleState = reduce(gentleState, key, gentleModules);
assert.deepEqual(chosenNames(gentleState, gentleModules), ["base", "node", "pi", "pi-workflows", "gentle-ai"]); // Gentle AI
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
// Legacy consoles ignore cursor-up: the absolute fallback must not emit it and
// must still leave exactly one banner.
const frames = [];
const probe = createRenderer({ columns: 80, write: (d) => frames.push(d) }, false);
long.forEach(probe);
assert.ok(frames.every((f) => f.startsWith("\x1b[2J\x1b[H") && !/\x1b\[\d*A/.test(f)));
assert.equal(screenAfter(long, 80, false).filter((x) => x.includes("AI Dev Suite")).length, 1);
// Capability detection
assert.equal(supportsCursorUp({}, "linux"), true);
assert.equal(supportsCursorUp({ TERM: "dumb" }, "linux"), false);
assert.equal(supportsCursorUp({}, "win32"), false);
assert.equal(supportsCursorUp({ WT_SESSION: "x" }, "win32"), true);
assert.equal(supportsCursorUp({ ConEmuANSI: "ON" }, "win32"), true);
assert.equal(supportsCursorUp({ ConEmuANSI: "OFF" }, "win32"), false);
assert.equal(supportsCursorUp({ TERM_PROGRAM: "vscode" }, "win32"), true);
assert.equal(supportsCursorUp({ TERM: "xterm-256color" }, "win32"), true);

// Extras submenu tests
const modulesWithExtras = [
  ...modules,
  { name: "taste", category: "Extras", kind: "skill", core: false, desc: "Taste skill" },
  { name: "humanizer", category: "Extras", kind: "skill", core: false, desc: "Humanizer skill" },
  { name: "heroui", category: "Extras", kind: "skill", core: false, desc: "HeroUI skill" },
  { name: "cockpit", category: "Extras", kind: "software", core: false, desc: "Cockpit GUI" },
  { name: "extras", category: "Extras", kind: "software", core: false, desc: "Full bundle" },
];

// S3: action rows remain ASCII on module and extras screens.
for (const frame of [
  view({ screen: "modules", cursor: 0, category: "System", selected: new Set() }, modules),
  view({ screen: "extras", cursor: 0, category: "Extras", selected: new Set() }, modulesWithExtras),
]) {
  assert.ok(frame.every((line) => [...stripAnsi(line)].every((char) => char.codePointAt(0) <= 0x7f)));
}

function runWithExtras(keys) {
  let s = initState(modulesWithExtras);
  const frames = [view(s, modulesWithExtras)];
  for (const k of keys) { s = reduce(s, k, modulesWithExtras); if (s.done) break; frames.push(view(s, modulesWithExtras)); }
  return { s, frames };
}

// 1. Navigate to Custom -> Extras category -> opens extras screen
// Categories: System(0), Agents(1), Extras(2), Gateway(3), Summary(4)
let exRun = runWithExtras([DOWN, DOWN, ENTER, DOWN, DOWN, ENTER]);
assert.equal(exRun.s.screen, "extras");
assert.equal(exRun.s.cursor, 0);

// 2. Multi-select in Extras with Space: select taste and humanizer, return to categories
// In extras: taste(0) [space], down, humanizer(1) [space], down*4 to Return row(5), enter
exRun = runWithExtras([
  DOWN, DOWN, ENTER, // Custom
  DOWN, DOWN, ENTER, // Open Extras submenu
  SPACE,             // Select taste
  DOWN, SPACE,       // Select humanizer
  DOWN, DOWN, DOWN, DOWN, ENTER // Return to category menu
]);
assert.equal(exRun.s.screen, "categories");
assert.deepEqual(chosenNames(exRun.s, modulesWithExtras), ["base", "node", "pi", "taste", "humanizer"]);

// 3. Multi-select in Extras and proceed directly to summary from Extras
exRun = runWithExtras([
  DOWN, DOWN, ENTER, // Custom
  DOWN, DOWN, ENTER, // Open Extras submenu
  SPACE,             // Select taste
  DOWN, SPACE,       // Select humanizer
  DOWN, DOWN, DOWN, DOWN, DOWN, ENTER, // Proceed directly to installation summary
  ENTER              // Confirm
]);
assert.equal(exRun.s.done, "confirm");
assert.deepEqual(chosenNames(exRun.s, modulesWithExtras), ["base", "node", "pi", "taste", "humanizer"]);

// 4. Toggle all/none in extras with 'a' and back with Esc
exRun = runWithExtras([
  DOWN, DOWN, ENTER, // Custom
  DOWN, DOWN, ENTER, // Open Extras submenu
  "a",               // Toggle all extras on
  ESC                // Back to categories
]);
assert.equal(exRun.s.screen, "categories");
assert.ok(exRun.s.selected.has("taste"));
assert.ok(exRun.s.selected.has("cockpit"));

// 5. Verify Extras view output formatting
const extrasView = view({ screen: "extras", cursor: 0, category: "Extras", selected: new Set(["taste"]) }, modulesWithExtras);
assert.ok(extrasView.some((l) => l.includes("Extras: Optional Skills & Software")));
assert.ok(extrasView.some((l) => l.includes("[skill]")));
assert.ok(extrasView.some((l) => l.includes("[software]")));
assert.ok(extrasView.some((l) => l.includes("Return to category menu")));
assert.ok(extrasView.some((l) => l.includes("Proceed directly to installation summary")));

// 6. Verify category modules screen action rows & summary view formatting
// In modules (System): base(0), node(1), Return(2), Summary(3)
let modRun = run([
  DOWN, DOWN, ENTER, // Custom
  ENTER,             // Open System category
  DOWN, DOWN, ENTER  // Select Return to category menu row (2)
]);
assert.equal(modRun.s.screen, "categories");

modRun = run([
  DOWN, DOWN, ENTER, // Custom
  ENTER,             // Open System category
  DOWN, DOWN, DOWN, ENTER // Select Proceed to summary row (3)
]);
assert.equal(modRun.s.screen, "summary");

const summaryView = view({ screen: "summary", cursor: 0, custom: true, selected: new Set(["base", "pi"]) }, modules);
assert.ok(summaryView.some((l) => l.includes("System") && l.includes("(1): base")));
assert.ok(summaryView.some((l) => l.includes("Agents") && l.includes("(1): pi")));

console.log("menu tests passed");
