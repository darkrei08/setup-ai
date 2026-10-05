# Repo-specific directives

## Always

- Speak to the user in Italian; keep code, comments, technical artifacts, and commit messages in English.
- Use Pi Workflow and the Engineering Excellence skill for non-trivial implementation, review, and verification work.
- Preserve the intentionally dirty primary worktree; use isolated worktrees for candidate changes.
- Run focused tests, syntax/parse checks, `git diff --check`, the applicable container matrix, GGA, and native review before delivery.
- Record exact host, image, command, exit code, and proving output for cross-platform checks.

## Never

- Never bypass `gga`, use `git commit --no-verify`, or treat a provider wrapper exit 0 with no provider output as a pass.
- Never switch branches or mutate a candidate while a native review lineage is active.
- Never run real package installs/configuration in review or agent workflows; use fake tools and side-effect guards.
- Never claim Windows/macOS verification when the required native host or VM is unavailable.
- Never write credentials, tokens, or opaque review bindings into repository memory.

## Preferences

- Keep each reviewable work unit at or below 400 changed lines unless explicitly authorized.
- Prefer fail-closed ownership checks and exact-path package verification.
- Keep Linux systemd behavior in issue #104 U2 within its approved read-only dependency-guard scope.

## Language

User-facing replies are Italian. Technical artifacts remain English.
