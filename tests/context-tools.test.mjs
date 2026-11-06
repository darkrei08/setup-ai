import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";

const root = new URL("../", import.meta.url);

const bash = readFileSync(new URL("setup-ai.sh", root), "utf8");
const powershell = readFileSync(new URL("setup-ai.ps1", root), "utf8");
const launcher = readFileSync(new URL("bin/setup-ai.mjs", root), "utf8");
for (const tool of ["toon", "sqz"]) {
  assert.match(bash, new RegExp(`mod_${tool}`));
  assert.match(powershell, new RegExp(`Mod-${tool[0].toUpperCase()}${tool.slice(1)}`));
  assert.match(launcher, new RegExp(`name: "${tool}"`));
}
// LEA and LLMLingua were removed as redundant; no inventory may declare them again.
for (const removed of ["lea", "llmlingua"]) {
  const pascal = `Mod-${removed[0].toUpperCase()}${removed.slice(1)}`;
  assert.doesNotMatch(bash, new RegExp(`mod_${removed}\\(\\)`));
  assert.doesNotMatch(powershell, new RegExp(`${pascal} \\{`));
  assert.doesNotMatch(launcher, new RegExp(`name: "${removed}"`));
}
// A launcher category missing from the menu order is silently unreachable.
const menu = await import(new URL("bin/menu.mjs", root));
const launcherCategories = [
  ...new Set([...launcher.matchAll(/category: "([^"]+)"/g)].map((m) => m[1])),
];
for (const category of launcherCategories) {
  assert.ok(
    menu.CATEGORY_ORDER.includes(category),
    `bin/menu.mjs CATEGORY_ORDER is missing launcher category "${category}"`,
  );
}

for (const source of [bash, powershell]) {
  assert.match(source, /toon --version/);
  assert.doesNotMatch(source, /toon --help/);
}
const toonCli = spawnSync("toon", ["--version"], { encoding: "utf8" });
assert.equal(toonCli.status, 0, `${toonCli.stderr || toonCli.stdout}`);
assert.equal(`${toonCli.stdout}${toonCli.stderr}`.trim(), "2.3.0");
const sqz = spawnSync("sqz", ["--version"], { encoding: "utf8" });
assert.equal(sqz.status, 0, `${sqz.stderr || sqz.stdout}`);
assert.equal(`${sqz.stdout}${sqz.stderr}`.trim(), "sqz 1.9.0");

console.log("Context tool declarations, TOON/sqz runtime verification passed");
