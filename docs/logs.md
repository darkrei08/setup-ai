# Logs

Each run writes `logs/setup_<runid>.log` (human), `.jsonl` (structured), and an
`engineering-report_<runid>.md`.

The JSONL ends with one `run_summary` record per run, and every step that goes
through the installer's command helpers adds a `step_result` record. Both are
additive: existing event names and payloads are unchanged, and `setup-ai.sh` and
`setup-ai.ps1` emit the same fields in the same order. The engineering report
ends with the same summary.

```json
{
  "event": "run_summary",
  "run_id": "20260913T150742Z",
  "return_code": 0,
  "summary": {
    "run_id": "20260913T150742Z",
    "outcome": "success",
    "started_at": "2026-09-13T15:07:42Z",
    "ended_at": "2026-09-13T15:07:48Z",
    "duration_seconds": 6,
    "modules": [{ "name": "rotator", "status": "success" }],
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
  approval) is listed with its phase name.

## Reading a run without paging the log

```bash
node -e 'const s=require("fs").readFileSync(process.argv[1],"utf8").trim().split("\n").map(JSON.parse).filter(r=>r.event==="run_summary").pop().summary;console.log(s.outcome, JSON.stringify(s.modules), JSON.stringify(s.steps))' logs/setup_<runid>.jsonl
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

Back to the [README](../README.md).
