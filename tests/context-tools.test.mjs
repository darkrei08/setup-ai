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
for (const tool of ["toon", "lea", "sqz", "llmlingua"]) {
  assert.match(bash, new RegExp(`mod_${tool}`));
  assert.match(powershell, new RegExp(`Mod-${tool[0].toUpperCase()}${tool.slice(1)}`));
  assert.match(launcher, new RegExp(`name: "${tool}"`));
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

console.log("Context tool declarations, TOON/LEA runtime verification passed");
