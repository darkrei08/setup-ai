// Progressive install menu: pure state transitions (reduce), pure view (view)
// and an in-place renderer. No dependencies; used by setup-ai.mjs.

export const PRESETS = [
  { id: "core", label: "Core", desc: "Default set" },
  { id: "all", label: "Everything", desc: "Every module, including optional ones" },
  { id: "custom", label: "Custom", desc: "Pick modules by category" },
  { id: "minimal", label: "Minimal", desc: "base, node, pi" },
  { id: "gentle-ai", label: "Gentle AI", desc: "Foundation + Gentle AI workflows" },
];
const MINIMAL = ["base", "node", "pi"];
const GENTLE_AI = ["base", "node", "pi", "pi-workflows", "gentle-ai"];
const CATEGORY_ORDER = ["System", "Agents", "Skills & workflows", "Memory & review", "Editors", "Extras", "Gateway"];

// 18 = title width: the narrowest frame that still renders the banner.
export const frameWidth = (cols) => Math.max(18, Math.min(70, (Number.isFinite(cols) ? cols : 80) - 3));

const presetSelection = (id, modules) =>
  id === "all" ? modules.map((m) => m.name)
    : id === "minimal" ? modules.filter((m) => MINIMAL.includes(m.name)).map((m) => m.name)
      : id === "gentle-ai" ? modules.filter((m) => GENTLE_AI.includes(m.name)).map((m) => m.name)
        : modules.filter((m) => m.core).map((m) => m.name);

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
      : s.screen === "modules" ? inCategory(modules, s.category).length + 2
        : s.screen === "extras" ? inCategory(modules, "Extras").length + 2
          : 0;

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
    s.selected = new Set(presetSelection(id, modules));
    return go("summary");
  }
  if (s.screen === "categories") {
    const cats = categoriesOf(modules);
    if (key === "back") return go("preset");
    if (key !== "enter") return s;
    if (s.cursor === cats.length) return go("summary");
    s.category = cats[s.cursor];
    if (s.category === "Extras") return go("extras");
    return go("modules");
  }
  if (s.screen === "extras") {
    const extras = inCategory(modules, "Extras");
    const returnIdx = extras.length;
    const summaryIdx = extras.length + 1;
    if (key === "back") {
      go("categories");
      s.cursor = categoriesOf(modules).indexOf("Extras");
      return s;
    }
    if (key === "space") {
      if (s.cursor < extras.length) {
        const name = extras[s.cursor].name;
        s.selected.has(name) ? s.selected.delete(name) : s.selected.add(name);
      } else if (s.cursor === returnIdx) {
        go("categories");
        s.cursor = categoriesOf(modules).indexOf("Extras");
      } else if (s.cursor === summaryIdx) {
        go("summary");
      }
      return s;
    }
    if (key === "all") {
      const allOn = extras.every((m) => s.selected.has(m.name));
      extras.forEach((m) => (allOn ? s.selected.delete(m.name) : s.selected.add(m.name)));
      return s;
    }
    if (key === "enter") {
      if (s.cursor < extras.length) {
        const name = extras[s.cursor].name;
        s.selected.has(name) ? s.selected.delete(name) : s.selected.add(name);
      } else if (s.cursor === returnIdx) {
        go("categories");
        s.cursor = categoriesOf(modules).indexOf("Extras");
      } else if (s.cursor === summaryIdx) {
        go("summary");
      }
      return s;
    }
    return s;
  }
  if (s.screen === "modules") {
    const mods = inCategory(modules, s.category);
    const returnIdx = mods.length;
    const summaryIdx = mods.length + 1;
    if (key === "back") {
      go("categories");
      s.cursor = categoriesOf(modules).indexOf(s.category);
      return s;
    }
    if (key === "space") {
      if (s.cursor < mods.length) {
        const name = mods[s.cursor].name;
        s.selected.has(name) ? s.selected.delete(name) : s.selected.add(name);
      } else if (s.cursor === returnIdx) {
        go("categories");
        s.cursor = categoriesOf(modules).indexOf(s.category);
      } else if (s.cursor === summaryIdx) {
        go("summary");
      }
      return s;
    }
    if (key === "all") {
      const allOn = mods.every((m) => s.selected.has(m.name));
      mods.forEach((m) => (allOn ? s.selected.delete(m.name) : s.selected.add(m.name)));
      return s;
    }
    if (key === "enter") {
      if (s.cursor < mods.length) {
        const name = mods[s.cursor].name;
        s.selected.has(name) ? s.selected.delete(name) : s.selected.add(name);
      } else if (s.cursor === returnIdx) {
        go("categories");
        s.cursor = categoriesOf(modules).indexOf(s.category);
      } else if (s.cursor === summaryIdx) {
        go("summary");
      }
      return s;
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

export function view(state, modules, cols) {
  const inner = frameWidth(cols);
  const title = "AI Dev Suite setup";
  const left = Math.floor((inner - title.length) / 2);
  const rule = "\x1b[1;36m+" + "-".repeat(inner) + "+\x1b[0m";
  const header = "\x1b[1;36m|\x1b[0m" + " ".repeat(left) + B(title) + " ".repeat(inner - title.length - left) + "\x1b[1;36m|\x1b[0m";
  const lines = [rule, header, rule];
  const count = `${state.selected.size}/${modules.length} selected`;
  if (state.screen === "preset") {
    lines.push("  Step 1/3: choose a preset", "  Arrows/j-k move   Enter select   q quit", "");
    PRESETS.forEach((p, i) => {
      const count = p.id === "custom" ? "" : `${presetSelection(p.id, modules).length} modules`;
      lines.push(`${pointer(i === state.cursor)} ${p.label.padEnd(12)} ${count.padEnd(11)} ${p.desc}`);
    });
  } else if (state.screen === "categories") {
    lines.push(`  Step 2/3: pick a category (${B(count)})`, "  Arrows/j-k move   Enter open   Esc back   q quit", "");
    categoriesOf(modules).forEach((c, i) => {
      const mods = inCategory(modules, c);
      const n = mods.filter((m) => state.selected.has(m.name)).length;
      const subtitle = c === "Extras" ? " [submenu]" : "";
      lines.push(`${pointer(i === state.cursor)} ${(c + subtitle).padEnd(25)} ${n}/${mods.length}`);
    });
    lines.push(`${pointer(state.cursor === categoriesOf(modules).length)} Continue to summary`);
  } else if (state.screen === "extras") {
    const extras = inCategory(modules, "Extras");
    const countSelected = extras.filter((m) => state.selected.has(m.name)).length;
    lines.push(
      `  ${B("Extras: Optional Skills & Software")} (${B(`${countSelected}/${extras.length} selected`)})`,
      "  Arrows/j-k move   Space toggle   a all/none   Enter choose   Esc back",
      ""
    );
    extras.forEach((m, i) => {
      const box = state.selected.has(m.name) ? "\x1b[32m[x]\x1b[0m" : "[ ]";
      const isSkill = m.extra || m.kind === "skill";
      const badge = isSkill ? "\x1b[35m[skill]   \x1b[0m" : "\x1b[34m[software]\x1b[0m";
      lines.push(`${pointer(i === state.cursor)} ${box} ${m.name.padEnd(12)} ${badge} ${m.desc}`);
    });
    lines.push("");
    lines.push(`${pointer(state.cursor === extras.length)} ${B("<")} Return to category menu`);
    lines.push(`${pointer(state.cursor === extras.length + 1)} ${B(">")} Proceed directly to installation summary`);
    lines.push("");
    lines.push(`  \x1b[90m${countSelected} extras selected. Use Space to multi-select, then return or proceed.\x1b[0m`);
  } else if (state.screen === "modules") {
    const mods = inCategory(modules, state.category);
    const countSelected = mods.filter((m) => state.selected.has(m.name)).length;
    lines.push(
      `  ${B(state.category)} (${B(`${countSelected}/${mods.length} selected`)})`,
      "  Arrows/j-k move   Space toggle   a all/none   Enter choose   Esc back",
      ""
    );
    mods.forEach((m, i) => {
      const box = state.selected.has(m.name) ? "\x1b[32m[x]\x1b[0m" : "[ ]";
      const tag = m.core ? " \x1b[36m[core]    \x1b[0m" : " \x1b[33m[optional]\x1b[0m";
      lines.push(`${pointer(i === state.cursor)} ${box} ${m.name.padEnd(14)} ${tag} ${m.desc}`);
    });
    lines.push("");
    lines.push(`${pointer(state.cursor === mods.length)} ${B("<")} Return to category menu`);
    lines.push(`${pointer(state.cursor === mods.length + 1)} ${B(">")} Proceed directly to installation summary`);
    lines.push("");
    lines.push(`  \x1b[90m${countSelected} in ${state.category} selected. Use Space to multi-select, then return or proceed.\x1b[0m`);
  } else {
    const names = chosenNames(state, modules);
    lines.push(`  Step 3/3: summary (${B(`${names.length} selected`)})`, "  Enter install   Esc back   q quit", "");
    if (!names.length) {
      lines.push("  (nothing selected)");
    } else {
      categoriesOf(modules).forEach((c) => {
        const inCat = inCategory(modules, c).filter((m) => state.selected.has(m.name));
        if (inCat.length) {
          lines.push(`  ${B(c)} (${inCat.length}): ` + inCat.map((m) => m.name).join(", "));
        }
      });
    }
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

// True when the terminal honours relative cursor-up. Legacy Windows consoles
// ignore it, so win32 needs a sign of a VT-capable host; TERM=dumb never does.
export function supportsCursorUp(env = process.env, platform = process.platform) {
  if (env.TERM === "dumb") return false;
  if (platform !== "win32") return true;
  return Boolean(env.WT_SESSION || env.ANSICON || env.ConEmuANSI === "ON" || env.TERM_PROGRAM || env.TERM);
}

// Redraws in place: moves up over the previous frame, clears to the end of the
// screen and prints once. Lines are truncated so none wraps and the line count
// stays exact. Without cursor-up support it clears the screen and homes the
// cursor instead, so only one frame is ever visible.
export function createRenderer(out, relative = supportsCursorUp()) {
  let prev = 0;
  return (lines) => {
    const cols = out.columns || 80;
    const fitted = lines.map((l) => fit(l, cols - 1));
    const head = relative ? (prev ? `\x1b[${prev}A\r` : "") + "\x1b[J" : "\x1b[2J\x1b[H";
    out.write(head + fitted.join("\n") + "\n");
    prev = fitted.length;
  };
}
