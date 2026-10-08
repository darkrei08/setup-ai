import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";

const launcher = new URL("../bin/setup-ai.mjs", import.meta.url).href;

function runAsWindows(args) {
  const code = `
    Object.defineProperty(process, "platform", { value: "win32" });
    process.argv = ["node", "setup-ai.mjs", ...${JSON.stringify(args)}];
    await import(${JSON.stringify(launcher)});
  `;
  return spawnSync(process.execPath, ["--input-type=module", "-e", code], { encoding: "utf8" });
}

for (const [args, message] of [
  [["--dry-run"], /--dry-run is not implemented on Windows/],
  [["--uninstall", "--purge"], /--purge is not implemented on Windows/],
]) {
  const result = runAsWindows(args);
  assert.equal(result.status, 2, result.stderr);
  assert.match(result.stdout, /setup-ai launcher · win32/);
  assert.match(result.stderr, message);
}

console.log("Windows launcher rejects unsupported lifecycle flags explicitly");
