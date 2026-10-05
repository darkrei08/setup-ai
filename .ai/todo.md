# TODO & tech debt

## Open

- [ ] Verify installer runtime behavior on native Windows and macOS when suitable hosts are available. Linux, WSL, and containers on this host do not satisfy native verification.

## Current release state

- GitHub `main` contains the v4.0.0 release line.
- `setup-ai` v4.0.0 is released and published.
- The old dirty branch is a preserved candidate, not the release branch. Do not use it as release state or publish from it.
- Gentle/Engram integration is pinned globally for agent workflows, but it is not committed source.

## Deferred

- Revisit native Windows/macOS verification only when the required hosts or full VMs are available.
