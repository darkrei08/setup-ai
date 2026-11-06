# setup-ai.ps1 parity fixes from the role-based GGA review

Status: spec ready, implementation pending. Windows runtime verification is NOT RUN on
this host (no Windows machine reachable yet; see `port-forwarding-test-hosts.md`).

## Origin

`agents/gga-pi/run-gga.sh run --ci --no-cache` (provider `kilo:reviewer-model`) returned
STATUS: FAILED on the 4.0.4 release commit with three findings. Triaged against the
source; two are real, one is a documented divergence.

## Specs

S1. `Mod-PiWorkflows` must mirror the Bash dotenv path: when
  `${DotenvDir}/pi/agent/extensions/pi-ext-workflows` exists, install
  `pi-extensible-workflows@<resolved version>` inside that directory, require
  `ignore-scripts=false` and the npm 12 remote-source opt-in in its `.npmrc`, and verify
  the installed package by reading
  `<dir>/node_modules/pi-extensible-workflows/package.json` and comparing its version
  with the resolved one. A missing artifact or a version mismatch fails the module.
  Evidence: `setup-ai.sh` lines ~2236-2268 (`mod_pi_workflows` dotenv branch).
  Status: **CONFIRMED defect** - `setup-ai.ps1` links the extensions but never installs
  or verifies the dotenv-side package.

S2. The transient-rename retry probe must cover the dotenv install root as Bash does:
  Bash iterates `PI_EXTENSIONS_DIR`, `DOTENV_EXT_DIR`, `PI_NPM_DIR`; PowerShell iterates
  only `PiExtDir` and `PiNpmDir`.
  Status: **CONFIRMED defect** (same family as S1, separate loop).

S3. `Link-DotenvWorkflowExtensions` must repair a symlink that points somewhere else,
  for both the extension directory and the barrel file, exactly as Bash does
  (`ln -sfn` when the target is a link). PowerShell only creates the link when the path
  does not exist (`Test-Path`), so a link pointing at a stale location is left in place.
  Evidence: `setup-ai.sh` `link_dotenv_workflow_extensions`; `setup-ai.ps1` lines
  ~1513-1545.
  Status: **CONFIRMED defect**.

S4. Finding 1 from the review (Windows refuses `-DryRun`) is **not** a defect: it is a
  documented divergence (`setup-ai.ps1` top-level guard, `docs/modules.md`). Behaviour
  must not change without a separate decision.

S5. The change is PowerShell-only and must not alter Bash or Node behaviour. The parity
  test (`tests/agent-install-parity.sh`), the version parity test, and the existing
  PowerShell lifecycle/inventory fakes must keep passing, and a focused pwsh test must
  cover S1-S3 through the existing fake-tool pattern.

## Acceptance criteria for the implementing slice

- `pwsh -NoProfile -Command "$null=[ScriptBlock]::Create((Get-Content -Raw setup-ai.ps1))"` exits 0.
- A new `tests/powershell-dotenv-workflows.ps1` (fake npm/pi) proves: dotenv install +
  version verify (S1), the three roots in the retry loop (S2), and a stale symlink is
  repointed (S3). Fails before the change.
- `bash tests/version-parity.sh`, `bash tests/agent-install-parity.sh`,
  `pwsh -NoProfile -File tests/powershell-lifecycle.ps1`,
  `pwsh -NoProfile -File tests/powershell-uninstall-inventory.ps1` exit 0.
- `git diff --check` clean; `gga` with the role-based provider passes the changed files.
- The PR body states: Windows runtime verification **NOT RUN** (no reachable host), and
  what a real Windows run must show.

## Risks

- The dotenv install path uses npm inside a directory outside `~/.pi`; a wrong target
  directory would write into a user checkout. The fake-tool test must assert the exact
  directory, and the real path must be resolved from `$DotenvDir`, never guessed.
- Without a Windows host the change is verified only through pwsh-on-Linux fakes; that
  limitation must be stated, not papered over.
