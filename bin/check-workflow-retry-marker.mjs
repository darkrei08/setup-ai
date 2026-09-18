// Guard for the pi-workflows install path: the transient-rename retry must stay
// verified against the installed artifact, in both scripts. Fails when the marker
// string, the assertion function, or the module's call to that assertion is dropped.
// Run: node bin/check-workflow-retry-marker.mjs
import { readFileSync } from "node:fs";

const targets = [
  {
    file: "setup-ai.sh",
    marker: 'PI_WORKFLOWS_RETRY_MARKER="renameWithRetry"',
    assertDecl: "assert_transient_rename_retry() {",
    moduleDecl: "mod_pi_workflows() {",
    assertCall: "assert_transient_rename_retry ",
  },
  {
    file: "setup-ai.ps1",
    marker: "$PiWorkflowsRetryMarker = 'renameWithRetry'",
    assertDecl: "function Assert-TransientRenameRetry {",
    moduleDecl: "function Mod-PiWorkflows {",
    assertCall: "Assert-TransientRenameRetry -IoJs",
  },
];

const problems = [];
for (const target of targets) {
  const source = readFileSync(new URL(`../${target.file}`, import.meta.url), "utf8");
  // Bash and PowerShell both declare at column 0 and indent their bodies, so the
  // module body runs to the next column-0 line: this checks the call inside the
  // module, not just anywhere in the file.
  const from = source.indexOf(target.moduleDecl);
  const tail = from < 0 ? "" : source.slice(from);
  const end = tail.search(/\n\S/);
  const body = end < 0 ? "" : tail.slice(0, end);
  if (!source.includes(target.marker)) problems.push(`${target.file}: marker ${target.marker}`);
  if (!source.includes(target.assertDecl)) problems.push(`${target.file}: ${target.assertDecl}`);
  if (from < 0) problems.push(`${target.file}: ${target.moduleDecl}`);
  else if (!body.includes(target.assertCall)) problems.push(`${target.file}: ${target.moduleDecl} does not call ${target.assertCall.trim()}`);
}

if (problems.length > 0) {
  console.error("pi-workflows retry verification is missing:");
  for (const problem of problems) console.error(`  - ${problem}`);
  process.exit(1);
}
console.log("pi-workflows retry verification present in setup-ai.sh and setup-ai.ps1");
