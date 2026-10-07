// Progressive install menu: pure state transitions (reduce), pure view (view)
// and an in-place renderer. No dependencies; used by setup-ai.mjs.

export const PRESETS = [
  { id: "core", label: "Core", desc: "Default set" },
  { id: "all", label: "Everything", desc: "Every module, including optional ones" },
  { id: "custom", label: "Custom", desc: "Pick modules by category" },
  { id: "minimal", label: "Minimal", desc: "base, node, pi" },
];
const MINIMAL = ["base", "node", "pi"];
const CATEGORY_ORDER = ["System", "Agents", "Skills & workflows", "Memory & review", "Editors", "Extras", "Gateway"];

export const categoriesOf = (modules) =>
  CATEGORY_ORDER.filter((c) => modules.some((m) => m.category === c));
const inCategory = (modules, c) => modules.filter((m) => m.category === c);

export function initState(modules) {
  return { screen: "preset", cursor: 0, category: null, custom: false, done: null,
    selected: new Set(modules.filter((m) => m.core).map((m) => m.name)) };
}

export function normalizeKey(raw) {
  if (raw === "\x1b[A" || raw === "k") return "up";
  if (raw === "\x1b[B" || raw === "j") return "down";
  if (raw === " ") return "space";
  if (raw === "\r" || raw === "\n") return "enter";
  if (raw === "\x1b" || raw === "\x7f" || raw === "\b") return "back";
  if (raw === "a") return "all";
  if (raw === "q" || raw === "\x03") return "quit";
  return null;
}

const rowCount = (s, modules) =>
  s.screen === "preset" ? PRESETS.length
    : s.screen === "categories" ? categoriesOf(modules).length + 1
      : s.screen === "modules" ? inCategory(modules, s.category).length : 0;

// Returns a new state; state.done becomes "confirm" or "quit" when finished.
export function reduce(state, rawKey, modules) {
  const key = normalizeKey(rawKey);
  if (!key) return state;
  const s = { ...state, selected: new Set(state.selected) };
  if (key === "quit") return { ...s, done: "quit" };
  const go = (screen) => Object.assign(s, { screen, cursor: 0 });
  if (key === "up" || key === "down") {
    const n = rowCount(s, modules);
    if (n) s.cursor = (s.cursor + (key === "up" ? -1 : 1) + n) % n;
    return s;
  }
  if (s.screen === "preset") {
    if (key === "back") return { ...s, done: "quit" };
    if (key !== "enter") return s;
    const id = PRESETS[s.cursor].id;
    s.custom = id === "custom";
    if (s.custom) return go("categories");
    s.selected = new Set(id === "all" ? modules.map((m) => m.name)
      : id === "minimal" ? modules.filter((m) => MINIMAL.includes(m.name)).map((m) => m.name)
        : modules.filter((m) => m.core).map((m) => m.name));
    return go("summary");
  }
  if (s.screen === "categories") {
    const cats = categoriesOf(modules);
    if (key === "back") return go("preset");
    if (key !== "enter") return s;
    if (s.cursor === cats.length) return go("summary");
    s.category = cats[s.cursor];
    return go("modules");
  }
  if (s.screen === "modules") {
    const mods = inCategory(modules, s.category);
    if (key === "back") { go("categories"); s.cursor = categoriesOf(modules).indexOf(s.category); return s; }
    if (key === "space") {
      const name = mods[s.cursor].name;
      s.selected.has(name) ? s.selected.delete(name) : s.selected.add(name);
    } else if (key === "all") {
      const allOn = mods.every((m) => s.selected.has(m.name));
      mods.forEach((m) => (allOn ? s.selected.delete(m.name) : s.selected.add(m.name)));
    }
    return s;
  }
  // summary
  if (key === "back") return go(s.custom ? "categories" : "preset");
  if (key === "enter") return { ...s, done: "confirm" };
  return s;
}

export const chosenNames = (state, modules) =>
  modules.filter((m) => state.selected.has(m.name)).map((m) => m.name);

const B = (t) => `\x1b[1m${t}\x1b[0m`;
const C = (t) => `\x1b[36m${t}\x1b[0m`;
const pointer = (on) => (on ? C(">") : " ");

export function view(state, modules) {
  const rule = "\x1b[1;36m+" + "-".repeat(70) + "+\x1b[0m";
  const lines = [rule, "\x1b[1;36m|\x1b[0m" + " ".repeat(26) + B("AI Dev Suite setup") + " ".repeat(26) + "\x1b[1;36m|\x1b[0m", rule];
  const count = `${state.selected.size}/${modules.length} selected`;
  if (state.screen === "preset") {
    lines.push("  Step 1/3: choose a preset", "  Arrows/j-k move   Enter select   q quit", "");
    PRESETS.forEach((p, i) => lines.push(`${pointer(i === state.cursor)} ${p.label.padEnd(12)} ${p.desc}`));
  } else if (state.screen === "categories") {
    lines.push(`  Step 2/3: pick a category (${B(count)})`, "  Arrows/j-k move   Enter open   Esc back   q quit", "");
    categoriesOf(modules).forEach((c, i) => {
      const mods = inCategory(modules, c);
      const n = mods.filter((m) => state.selected.has(m.name)).length;
      lines.push(`${pointer(i === state.cursor)} ${c.padEnd(20)} ${n}/${mods.length}`);
    });
    lines.push(`${pointer(state.cursor === categoriesOf(modules).length)} Continue to summary`);
  } else if (state.screen === "modules") {
    lines.push(`  ${B(state.category)} (${B(count)})`, "  Arrows/j-k move   Space toggle   a all/none   Esc back   q quit", "");
    inCategory(modules, state.category).forEach((m, i) => {
      const box = state.selected.has(m.name) ? "\x1b[32m[x]\x1b[0m" : "[ ]";
      const tag = m.core ? "" : " \x1b[33m(optional)\x1b[0m";
      lines.push(`${pointer(i === state.cursor)} ${box} ${m.name.padEnd(13)}${tag} ${m.desc}`);
    });
  } else {
    const names = chosenNames(state, modules);
    lines.push(`  Step 3/3: summary (${B(count)})`, "  Enter install   Esc back   q quit", "");
    if (!names.length) lines.push("  (nothing selected)");
    for (let i = 0; i < names.length; i += 6) lines.push("  " + names.slice(i, i + 6).join(", "));
  }
  return lines;
}

// Truncate to `max` visible characters, skipping ANSI colour sequences.
export function fit(line, max) {
  let visible = 0;
  let out = "";
  for (let i = 0; i < line.length; i++) {
    const esc = /^\x1b\[[0-9;]*m/.exec(line.slice(i));
    if (esc) { out += esc[0]; i += esc[0].length - 1; continue; }
    if (visible === max) return out + "\x1b[0m";
    out += line[i];
    visible++;
  }
  return out;
}

// Redraws in place: moves up over the previous frame, clears to the end of the
// screen and prints once. Lines are truncated so none wraps and the line count
// stays exact.
export function createRenderer(out) {
  let prev = 0;
  return (lines) => {
    const cols = out.columns || 80;
    const fitted = lines.map((l) => fit(l, cols - 1));
    out.write((prev ? `\x1b[${prev}A\r` : "") + "\x1b[J" + fitted.join("\n") + "\n");
    prev = fitted.length;
  };
}
