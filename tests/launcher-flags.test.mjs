import assert from "node:assert/strict";
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";

const launcher = new URL("../bin/setup-ai.mjs", import.meta.url).href;

function runAsWindows(args, pwsh = null) {
  const code = `
    Object.defineProperty(process, "platform", { value: "win32" });
    process.argv = ["node", "setup-ai.mjs", ...${JSON.stringify(args)}];
    await import(${JSON.stringify(launcher)});
  `;
  const env = { ...process.env };
  if (pwsh) env.SETUP_AI_PWSH = pwsh;
  return spawnSync(process.execPath, ["--input-type=module", "-e", code], { encoding: "utf8", env });
}

const stubDir = mkdtempSync(join(tmpdir(), "setup-ai-launcher-"));
const stubIsWindows = process.platform === "win32";
const pwshStub = join(stubDir, stubIsWindows ? "pwsh-stub.cmd" : "pwsh-stub");
const stubSource = stubIsWindows
  ? "@echo off\r\nfor %%A in (%*) do if \"%%~A\"==\"-DryRun\" exit /b 0\r\nexit /b 91\r\n"
  : "#!/bin/sh\nfor arg in \"$@\"; do [ \"$arg\" = \"-DryRun\" ] && exit 0; done\nprintf '%s\\n' 'missing -DryRun' >&2\nexit 91\n";
writeFileSync(pwshStub, stubSource);
if (!stubIsWindows) chmodSync(pwshStub, 0o755);
try {
  const dryRun = runAsWindows(["--dry-run"], pwshStub);
  assert.equal(dryRun.status, 0, dryRun.stderr);
  assert.match(dryRun.stdout, /setup-ai launcher · win32/);
  assert.doesNotMatch(dryRun.stderr, /not implemented/);

  const purge = runAsWindows(["--uninstall", "--purge"]);
  assert.equal(purge.status, 2, purge.stderr);
  assert.match(purge.stdout, /setup-ai launcher · win32/);
  assert.match(purge.stderr, /--purge is not implemented on Windows/);
} finally {
  rmSync(stubDir, { recursive: true, force: true });
}

console.log("Windows launcher forwards dry-run and rejects unsupported purge");
