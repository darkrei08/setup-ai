# Conventions

## Code style
Bash starts with `set -euo pipefail`, quotes expansions, and routes fallible commands through existing helpers. PowerShell keeps strict mode/error handling and uses `Write-Log`/`Invoke-Step`. Node remains ESM-only and dependency-free at runtime.

## Architecture patterns
Bash, PowerShell, and Node are parallel implementations. Changes to module names, order, descriptions, install logic, or verification must be mirrored and covered by the parity test. Ownership markers/receipts are fresh-install evidence only; existing packages are verified and preserved without being claimed.

## Testing
Use focused fake-tool tests for ownership and lifecycle behavior, then run `bash -n`, PowerShell parsing, parity, lifecycle, `git diff --check`, and the configured container matrix. Functional checks remain required in addition to code review. Native Windows tests must run on a real Windows host or full Windows VM, never WSL or a Linux-hosted Windows container.

## Git & delivery
Use isolated worktrees for issue candidates. Keep work units within 400 changed lines. Every commit goes through `gga run`; never bypass the hook. Native review is candidate-bound and must be approved and acknowledged before commit or handoff. Do not merge or publish without explicit authorization.

## Documentation
Update the relevant module documentation and changelog with behavior changes, especially ownership, uninstall scope, and unavailable platform verification.
