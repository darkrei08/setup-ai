# Problems & solutions

## Historical workflow runtime mismatch

- **Symptom:** An agent workflow failed because the interactive process loaded an incompatible runtime.
- **Cause:** The process runtime differed from the installed workflow package requirements.
- **Fix:** Restart under a compatible runtime and verify the runtime loaded by the process, not only the installed command. Keep a shell-only fallback when the interactive runtime cannot be refreshed.

## Historical provider no-output false pass

- **Symptom:** A review wrapper returned success without provider output.
- **Cause:** The wrapper did not fail closed when the provider failed or produced no result.
- **Fix:** Treat missing provider output as a failed review; never use the wrapper exit code alone as evidence.

## Historical review candidate identity

- **Symptom:** A native review became stale after the candidate changed.
- **Cause:** Native review binds to the exact workspace snapshot.
- **Fix:** Do not mutate, switch branches, or commit an active candidate before capture; obtain fresh status and submit only the current candidate.
