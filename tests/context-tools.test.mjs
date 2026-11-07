import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const root = new URL("../", import.meta.url);
const require = createRequire(import.meta.url);
const formats = require(fileURLToPath(new URL("vendor/wz-ai-context-formats.cjs", root)));
const lea = formats.encodeLEA({
  sources: { S1: "fixture.md" },
  evidence: [{ id: "E1", source: "S1", content: "fixture" }],
});
assert.match(lea, /### SOURCE DICTIONARY/);
assert.match(lea, /\| E1 \| \[S1\] \| fixture \|/);
const toon = formats.toTOON("items", [{ id: 1, name: "Alice" }]);
assert.match(toon, /items:\n\[1\]\{id,name\}:/);
assert.deepEqual(formats.fromTOON(toon), { label: "items", items: [{ id: 1, name: "Alice" }] });

const bash = readFileSync(new URL("setup-ai.sh", root), "utf8");
const powershell = readFileSync(new URL("setup-ai.ps1", root), "utf8");
const launcher = readFileSync(new URL("bin/setup-ai.mjs", root), "utf8");
for (const tool of ["toon", "lea", "llmlingua"]) {
  assert.match(bash, new RegExp(`mod_${tool}`));
  assert.match(powershell, new RegExp(`Mod-${tool[0].toUpperCase()}${tool.slice(1)}`));
  assert.match(launcher, new RegExp(`name: "${tool}"`));
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

console.log("Context tool declarations, TOON/LEA runtime verification passed");
