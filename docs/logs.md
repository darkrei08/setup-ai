# Logs

Each run writes `logs/setup_<runid>.log` (human), `.jsonl` (structured), and an
`engineering-report_<runid>.md`. For terminal output, add `--verbose` (or `-v`)
to render spaced event blocks and live child-command output; log files keep
their stable machine-readable and plain-text formats.

The JSONL ends with one `run_summary` record per run, and every step that goes
through the installer's command helpers adds a `step_result` record. Both
writers emit the same keys in the same order. The engineering report ends with
the same summary.

Every record starts with these keys:

```json
{
  "ts": "2026-09-13T15:07:48Z",
  "lvl": "INFO",
  "ph": "bootstrap",
  "ev": "run_summary",
  "msg": "Run summary: outcome=success;duration_seconds=6",
  "rc": 0,
  "rid": "20260913T150742Z",
  "pid": 4242
}
```

`meta`, `summary`, and `err` are optional and are appended in that order. `meta`
remains a string, and `summary` keeps its existing object shape. A record with a
non-zero `rc` always carries `err.rc`. The `optional` and `behavior` keys are
included only when the caller supplied those classifications; the writers never
infer them from the log level or a default value. `step_result` records
intentionally carry only `err.rc`, because that summary outcome does not receive
the command helper's classification. Bash has no expected-exit path; PowerShell
logs an expected exit at INFO with `rc: 0`, so it has no `err` object.

```json
{
  "ts": "2026-09-13T15:07:44Z",
  "lvl": "WARN",
  "ph": "node",
  "ev": "optional_command_failed",
  "msg": "Optional command failed; continuing",
  "rc": 7,
  "rid": "20260913T150742Z",
  "pid": 4242,
  "meta": "npm cache verify ",
  "err": { "rc": 7, "optional": true, "behavior": "continue" }
}
```

The terminal `run_summary` record keeps `summary.modules` and `summary.steps`:

```json
{
  "ts": "2026-09-13T15:07:48Z",
  "lvl": "INFO",
  "ph": "bootstrap",
  "ev": "run_summary",
  "msg": "Run summary: outcome=success;duration_seconds=6",
  "rc": 0,
  "rid": "20260913T150742Z",
  "pid": 4242,
  "summary": {
    "run_id": "20260913T150742Z",
    "outcome": "success",
    "started_at": "2026-09-13T15:07:42Z",
    "ended_at": "2026-09-13T15:07:48Z",
    "duration_seconds": 6,
    "modules": [{ "name": "cliproxyapi", "status": "success" }],
    "steps": { "installed": 1, "verified": 3, "skipped": 0, "failed": 0 }
  }
}
```

- `summary.modules[].status` is `success`, `failed`, or `skipped` (never
  reached). A failed entry also carries `failed_step` (the command that failed)
  and `return_code`.
- `summary.steps` counts the step records: `installed` (a state-changing step
  ran), `verified` (a readback step ran), `skipped` (an optional step failed, or
  the step never ran) and `failed` (a mandatory step returned a failure). Both
  flags a caller can use stay in the log: `--optional` (`-Optional`) marks a
  failure the run recovers from, so it is counted as skipped, and `--verify`
  (`-Verify`) marks a read-back, so a successful one is counted as verified
  instead of installed. A recovered attempt therefore never inflates the failed
  count.
- `summary.outcome` is `success` only when the whole run exited 0, so a failed
  run still says which module and step failed and with which return code. A
  failure outside the selected modules (a quality gate, the npm install-script
  approval) is listed with its phase name. A run killed by a signal (`HUP`,
  `INT`, `TERM`) is `interrupted`: the in-flight module is reported `failed`
  with `failed_step: run_interrupted: ...`, and the summary carries
  `interrupted=true;signal=<name>` with a non-zero exit code.

## Reading a run without paging the log

Run this from the repository root after an installer run. It selects the newest
JSONL artifact, so it works against a fresh log without replacing a placeholder:

```bash
node --input-type=module <<'NODE'
import fs from "node:fs";

const name = fs.readdirSync("logs")
  .filter((entry) => /^setup_.*\.jsonl$/.test(entry))
  .sort()
  .at(-1);
if (!name) throw new Error("No setup JSONL log found in logs/");
const records = fs.readFileSync(`logs/${name}`, "utf8")
  .trim().split("\n").map(JSON.parse);
const summary = records.filter((record) => record.ev === "run_summary").at(-1).summary;
console.log(summary.outcome, JSON.stringify(summary.modules), JSON.stringify(summary.steps));
NODE
```

## Reading the event stream

Normal, in order:

```text
command_start   → the command is about to run
command_success → it exited 0
step_result     → the step is recorded (status=installed|verified|skipped)
```

A successful step is immediately followed by the **next** step's `command_start`;
that is not an error. Failures are explicit: `command_failed` /
`step_failed_optional` carry the return code. See
[troubleshooting](./troubleshooting.md) for the errors seen in the field.

### Expected INFO: `skill_shared_root_only` for codex

`skills` and `ee` verify each skill for every targeted agent by looking for
`<root>/<skill>/SKILL.md`, checking the agent's own config dir first and the shared
`~/.agents/skills` root second. The upstream `skills` CLI treats Codex as a
universal agent: under `--global --copy` its install target is `~/.agents/skills`,
because Codex reads that path as a user-scope skills directory
([Codex skills](https://developers.openai.com/codex/skills)), and it does not write
a per-agent copy under `~/.codex/skills`. The check therefore reports one INFO per
skill that landed only in the shared root:

```text
[INFO] skills skill_shared_root_only: Skill is installed under the shared skills root, which is this agent's own install target
```

For every other agent the same situation stays a WARN
(`skill_not_copied_to_agent_root`), because there the shared root means the CLI
skipped the copy into that agent's own config dir. The `skills_verified` INFO
emitted after the loop is the success signal, and a skill missing from every
candidate root is an ERROR (`skill_missing`) that fails the module.

Back to the [README](../README.md).
