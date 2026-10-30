# SkillOpt-Sleep evidence (project-scoped, mock backend, no adoption)

- Run at: 2026-10-30T16:14Z (UTC)
- Project: `/root/git/personale/pi.dev/setup-ai/.worktrees/ui-shell-autonomous`
- Engine checkout: `/root/git/agent-skills/skillopt` (the configured `SKILLOPT_SLEEP_REPO=/root/git/personale/upstream` path does not exist)
- Interpreter: `/usr/bin/python3.13` with `PYTHONPATH=/root/git/agent-skills/skillopt`
  and `PYTHONPYCACHEPREFIX=/tmp/pycache-so2`

## Environment findings

- The bundled `plugins/run-sleep.sh` fails on this host: `ValueError: bad marshal data
  (unknown type code)` while loading `skillopt_sleep/cycle.py` from stale bytecode.
- The ambient `python3` on `PATH` is the setup-ai mineru venv interpreter
  (`/root/.local/share/setup-ai/mineru/venv/bin/python3`), which has no
  `skillopt_sleep` module.
- Running the engine module directly with the system interpreter and a fresh bytecode
  cache prefix works (`--help` exits 0), so that route was used instead of editing the
  engine checkout.

## Commands and results

1. Syntax/interpreter probe

```
PYTHONPATH=/root/git/agent-skills/skillopt PYTHONPYCACHEPREFIX=/tmp/pycache-so2 \
  /usr/bin/python3.13 -m skillopt_sleep --help
```

Exit 0; subcommands `run, dry-run, self-improve, status, adopt, harvest, schedule,
unschedule, evalkit`; `--source` accepts `pi`.

2. Status (read-only)

```
/usr/bin/python3.13 -m skillopt_sleep status --project "$PWD" --json --source pi
```

Exit 0. `night: 4`, `state_path: /root/.skillopt-sleep/state.json`,
`latest_staging: null` (no staged proposal is pending).
stdout sha256: `593eee708601dc0d34c8bc457cba9c62155332bb087db333ff1a3bf040c6a0a1`

3. Dry run (mock backend, no auto-adopt, explicit target skill)

```
timeout 420 /usr/bin/python3.13 -m skillopt_sleep dry-run --project "$PWD" \
  --source pi --scope invoked --backend mock --lookback-hours 6 \
  --max-sessions 1 --max-tasks 1 \
  --target-skill-path /root/.pi/agent/skills/tigerstyle/SKILL.md --json
```

Exit 0. Result: `night 5`, `gate_action: reject`, `baseline 0.0`, `candidate 0.0`,
`n_sessions: 1`, `n_tasks: 1`, `n_accepted_edits: 0`, `n_rejected_edits: 0`,
`staging_dir: ""`, `staged_skills: []`, `adopted: false`.
Engine warning: the model key changed since the last night (`codex::` -> `mock::`), so
learned skill text may not transfer; the mock backend produced no scorable gain.
stdout sha256: `6c906af403067d0a5ad97125b489101c2a4c7cc2c5b9a4f9329c1c868ce84c89`

## Artifacts

- Engine-side evidence (outside the repository, contains harvested task text and is
  therefore not committed): `/root/.skillopt-sleep/evidence/dryrun-20261030-161430.jsonl`,
  sha256 `727f99fecc1d8461068b1b0d90d02017048acdf09d1ce3060f59d3cb044e5abf`.
- No proposal was staged, nothing was adopted, and no live skill or configuration file
  was modified by this step.

## Boundary

- Only `--scope invoked` with `--lookback-hours 6 --max-sessions 1` was harvested, and
  the harvested text stayed in the engine's own evidence file (outside the repository).
- `--auto-adopt` was not passed. Adoption is out of scope for this effort.
