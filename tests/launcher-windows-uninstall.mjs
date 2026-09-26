import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";

// This regression runs in the Linux Node gate; /bin/echo replaces PowerShell.
const launcher = fileURLToPath(new URL("../bin/setup-ai.mjs", import.meta.url));
const code = `
  Object.defineProperty(process, "platform", { value: "win32" });
  process.argv = [process.execPath, ${JSON.stringify(launcher)}, "--uninstall", "--all", "--purge"];
  await import(${JSON.stringify(pathToFileURL(launcher).href)});
`;
const result = spawnSync(process.execPath, ["--input-type=module", "-e", code], {
  encoding: "utf8",
  env: { PATH: process.env.PATH, SETUP_AI_PWSH: "/bin/echo" },
});

assert.equal(result.status, 0, result.stderr || result.stdout);
assert.match(result.stdout, /setup-ai launcher · win32/);
assert.match(result.stdout, /-Uninstall -All -Purge(?:\r?\n|$)/);
console.log("Windows uninstall launcher forwarding regression passed.");
