# Native RDD review: `start` returns `blocked` / `mutation_outcome: unknown`

Troubleshooting note for the native receipt-driven-development review when it cannot
start at all. Written so the next session does not rediscover the same dead end, and so
the maintainer has the exact commands to decide between the two continuations at the end.

**Observation date:** 2026-09-13
**Machine:** Windows 11, Git Bash
**Versions observed:** `gentle-ai 2.7.0` (`C:\Users\Admin\go\bin\gentle-ai.exe`),
`gentle-pi 2.6.0`, native review protocol 1.5 under contract
`gentle-ai.review-integration/v1` (2.5 under `/v2`).

This document distinguishes two kinds of claim:

- **Verified** — a command in this document was run on that machine and its output is
  quoted here.
- **Read** — taken from GitHub issues, from the installed `gentle-pi` source, or from the
  owner's earlier session. Not reproduced by the author of this note.

The native review was **not** attempted while writing this document, and no
`gentle-ai review` subcommand that mutates state was run. Every command below is
read-only.

---

## 1. Symptom

**Read** — recorded by the repository owner in the evidence comment on
[#1](https://github.com/darkrei08/setup-ai/issues/1), and reported again in
[#12](https://github.com/darkrei08/setup-ai/issues/12). One attempt per candidate across
three candidates. The envelope fields were:

```jsonc
{
  "status": "blocked",
  "outcome": "native-mutation-status-reconciled",
  "mutation_outcome": "unknown",
  "next_action": "start"
}
```

What accompanies those fields:

- No error text and no `diagnostics` payload.
- No consent envelope is produced.
- No lineage is created.
- Nothing is written to the native authority store, and the store reads clean afterwards.

The failure stays identical across attempts, so retrying `start` does not converge.

## 2. What those fields mean

**Read** from the installed `gentle-pi 2.6.0` source
(`extensions/gentle-ai.ts`, `runtime/review-integration-v2.mjs`):

| Field | Meaning |
| --- | --- |
| `outcome: native-mutation-status-reconciled` | A mutating native call failed *without* returning an envelope. The provider then called native `review status` to reconcile, and reports that reconciled status here instead of the missing error. |
| `mutation_outcome: unknown` | The fail-closed value. The provider could not prove the failed call did not mutate. The closed enum is `not_started` \| `unknown` \| `committed`. |
| `next_action: start` | The reconciliation itself concluded that a fresh `start` is the correct next step. Nothing is stuck or half-created. |
| `status: blocked` | The provider refuses to continue on an unproven mutation outcome. |

So `blocked` here does **not** mean "the review rejected this candidate". It means "a
native call failed without telling the provider what happened, and the provider will not
guess". That is why the store being clean is consistent with the failure rather than
contradicting it.

> **Read, `gentle-pi` 2.6.0 field defect.** When the provider *can* prove no mutation
> happened (the reconciled authority revision is unchanged), it stamps
> `mutation_outcome: "none"`. That literal is not a member of the `REVIEW_MUTATION_OUTCOME`
> enum (`not_started` \| `unknown` \| `committed`), and the runtime validates
> `failure.mutation_outcome` against that enum. A "proven unchanged" envelope would
> therefore be rejected by the provider's own validator. This does not affect the observed
> failure, which carries `unknown`, but it is worth knowing before reading a future
> envelope of this shape.

## 3. Verified: the native authority store is clean and untouched

Run from the repository root. All three are read-only.

```console
$ gentle-ai review status
{
  "schema": "gentle-ai.review-authority-status/v1",
  "operation": "review/status",
  "repository": "C:\\Users\\Admin\\git\\personale\\.worktrees\\rdd-review-blocked-docs",
  "complete": true,
  "authoritative": true,
  "status": "clean",
  "entries": [],
  "locks": [
    {
      "version": "compact-v2",
      "path": "C:\\Users\\Admin\\git\\personale\\setup-ai\\.git\\gentle-ai\\review-transactions\\v2\\LOCK",
      "status": "released"
    }
  ],
  "diagnostics": []
}
```

```console
$ gentle-ai review inspect-authority
{
  "schema": "gentle-ai.review-authority-inspection/v1",
  "operation": "review/inspect-authority",
  "repository_root": "C:\\Users\\Admin\\git\\personale\\.worktrees\\rdd-review-blocked-docs",
  "complete": true,
  "valid": true,
  "totals": {
    "compact_entries": 0,
    "loaded_entries": 0,
    "edges": 0,
    "valid_edges": 0,
    "invalid_edges": 0,
    "entry_diagnostics": 0
  },
  "edges": [],
  "entry_diagnostics": [],
  "sanctioned_exits": []
}
```

```console
$ gentle-ai review mode status
receipt-driven development: on (decided by global)
  global:      on
  clone-local: unset
```

### The `find` command needs the common dir, not `.git`

In a linked worktree `.git` is a **file**, not a directory, so the check fails outright:

```console
$ find .git/gentle-ai -newermt '-30 minutes'
find: '.git/gentle-ai': Not a directory
```

The store lives in the main clone. Resolve it and search there:

```console
$ git rev-parse --git-common-dir
C:/Users/Admin/git/personale/setup-ai/.git

$ find "$(git rev-parse --git-common-dir)"/gentle-ai -newermt '-30 minutes'
$                       # empty: nothing written in the last 30 minutes
```

**Verified.** Nothing was written under the authority store around the attempts, the lock
is released, and both authority readings are complete, valid, and empty. Whatever fails,
it fails *before* the store is touched.

## 4. Candidate cause A (verified): the provider's pinned reviewer binary is not installed

This is the leading cause and it is fully verified on that machine.

`gentle-pi` does not use the `gentle-ai` on `PATH`. It pins one package-local binary and
refuses to fall back. `gentle-pi 2.6.0` pins **gentle-ai 2.8.0**
(`scripts/gentle-ai-installer.mjs` → `INSTALLER_VERSION`). Resolving it with the
provider's own resolver:

```console
$ cat probe.mjs
const mod = "file:///C:/Users/Admin/.pi/agent/npm/node_modules/gentle-pi/runtime/gentle-ai-binary.mjs";
const { resolveGentleAiBinary, gentleAiBinaryPath, GENTLE_AI_VERSION } = await import(mod);
console.log("GENTLE_AI_VERSION =", GENTLE_AI_VERSION);
console.log("expected path     =", gentleAiBinaryPath());
try { console.log("RESOLVED OK       =", resolveGentleAiBinary()); }
catch (error) { console.log("RESOLVE FAILED    =", error.code); console.log("message           =", error.message); }

$ node probe.mjs
GENTLE_AI_VERSION = 2.8.0
expected path     = C:\Users\Admin\.pi\agent\npm\node_modules\gentle-pi\.gentle-ai\v2.8.0\gentle-ai.exe
RESOLVE FAILED    = package-local-binary-missing
message           = package-local-binary-missing: Gentle AI v2.8.0 is not installed at
                    C:\Users\Admin\.pi\agent\npm\node_modules\gentle-pi\.gentle-ai\v2.8.0\gentle-ai.exe.
                    ... run `node scripts/install-gentle-ai.mjs`.
```

That directory does not exist, and no dev-binary override is registered
(`$GENTLE_PI_GENTLE_AI_DEV_BINARY` unset, `~/.pi/gentle-ai/dev-binary.json` absent). The
`gentle-ai` that answers on `PATH` is **2.7.0** — a *different, older* binary that the
provider never invokes:

```console
$ gentle-ai --version
gentle-ai 2.7.0
```

That binary is installed by the reviewer's own `postinstall`, which npm 12 is still
blocking:

```console
$ npm install-scripts ls --json --prefix ~/.pi/agent/npm
{
  "allowScripts": [
    {
      "name": "gentle-pi",
      "changes": [
        { "key": "gentle-pi@2.6.0", "change": "pending" }
      ]
    }
  ]
}
```

`gentle-pi`'s `postinstall` is `node scripts/install-gentle-ai.mjs`, and that script spells
out this exact consequence when it is skipped:

> `native review operations will fail with package-local-binary-missing until gentle-pi is reinstalled.`

`setup-ai.sh` already handles this case (`approve_npm_install_scripts`, the
`review_binary_missing` check) and reads the binary back from disk rather than trusting an
exit code — **read** in `setup-ai.sh`, and correct as written: a missing binary fails the
run. The current machine state simply predates a successful approval for
`gentle-pi@2.6.0`.

**Why this fits the symptom.** If the reviewer binary cannot be spawned, no native call
ever reaches the authority store — which is exactly what section 3 measures: zero entries,
lock released, nothing written. The review fails before it can mutate anything.

**Continuation.** Approve the install script so the postinstall writes the pinned binary,
then re-run the resolver above to confirm it resolves before attempting any review.
Re-running the `pi` module does this and verifies it. **Read** in `setup-ai.sh`,
`approve_npm_install_scripts` runs the equivalent of these two commands, which were
**not** run while writing this note because they change installed state:

```console
npm install-scripts approve gentle-pi --prefix ~/.pi/agent/npm
npm rebuild gentle-pi --foreground-scripts --prefix ~/.pi/agent/npm
```

> **Honest gap.** The envelope recorded in §1 carries
> `outcome: native-mutation-status-reconciled`, while a missing package-local binary maps
> to `outcome: native-status-package-binary-missing` (**read** in
> `extensions/gentle-ai.ts`). Those are different outcome strings, and the recorded
> envelope came from an earlier session, before the current `gentle-pi 2.6.0` package files
> were written at 16:43 local. So the recorded envelope may predate this cause. The
> commands above settle it in one run: if `resolveGentleAiBinary` still throws, no `start`
> attempt can succeed and the envelope question is moot until it resolves.

## 5. Candidate cause B (excluded): contract / protocol version mismatch

The hypothesis, recorded in [#1](https://github.com/darkrei08/setup-ai/issues/1), was that
the native binary advertises contract `gentle-ai.review-integration/v1` with protocol 1.5
and five operations, while the provider route passes
`--contract=gentle-ai.review-integration/v2`.

The first half is true, but only as the **default** value of `--contract`. Negotiating v2
explicitly succeeds, and returns a strictly *richer* surface:

```console
$ gentle-ai review capabilities
  "schema": "gentle-ai.review-integration.capabilities/v1.5"
  "contract": "gentle-ai.review-integration/v1"
  "protocol": { "major": 1, "minor": 5 }
  "minimum_protocol_major": 1, "maximum_protocol_major": 1

$ gentle-ai review capabilities --contract=gentle-ai.review-integration/v2
  "schema": "gentle-ai.review-integration.capabilities/v2.5"
  "contract": "gentle-ai.review-integration/v2"
  "protocol": { "major": 2, "minor": 5 }
  "minimum_protocol_major": 2, "maximum_protocol_major": 2
```

`diff` between the two outputs shows the v2 negotiation adds exactly what the v2 provider
route needs — `start/v4`, `status/v5`, `status/v6`, `status/v7`, `consent/v3`,
`intended-untracked-selection/v1`, and
`gentle-ai.review-integration.operation/v2` — and removes nothing.

**Verified exclusion.** The `operations` array is *byte-identical* under both contracts
(`review.capabilities`, `review.repair`, `review.start`, `review.status`,
`review.validate`), so the five-operation list does not discriminate v1 from v2 at all; it
is a coarse legacy advertisement. The same binary answers `v2` with a higher protocol
window on request. A version mismatch between the advertised default and the requested
contract is therefore not the cause. The `--contract` flag is documented as *optional*
("optional negotiated review integration contract") in `gentle-ai review start --help`.

## 6. Candidate cause C (open, unconfirmed): Windows write-path failure class

Tracked as [#1](https://github.com/darkrei08/setup-ai/issues/1) itself. On Windows, a
`write(.tmp)` + `rename()` pair with no retry fails with
`EPERM: operation not permitted, rename '…state.json.tmp' -> '…state.json'` when something
transiently holds the target — Defender real-time scanning, the search indexer, or a
concurrent Node worker. The issue records this breaking `pi-extensible-workflows` state
writes, and names the durable fix as retry-with-backoff around `rename`.

**Read**, not confirmed here. Two reasons to keep it as a candidate rather than the cause:

- No `EPERM` text was captured on the review path. The recorded envelope has no error text
  at all, which is what a swallowed write failure would look like, but that is an absence
  of evidence, not evidence.
- It is a plausible *mechanism* once the binary resolves: a `start` whose transaction write
  never lands leaves the store empty, and the provider's reconciliation then cannot prove
  what happened. That is precisely the observed shape.

Relevant to §4: the upstream fix for this class was already applied to the workflow side
(`0443d98`, `renameWithRetry` retrying `EACCES`/`EBUSY`/`EPERM`), so what remains open in
#1 is the native review path.

## 7. Explicitly NOT the cause

| Hypothesis | Why it is excluded | Evidence |
| --- | --- | --- |
| A moving workspace snapshot (#12's mechanism: switching branches mid-review) | The same failure was recorded with a stable target identity: `target_identity` identical between `inspect` and `start`, and no working-tree change between the two calls. The failure also reproduces in a fresh worktree that is clean. | **Read** in [#12's comment](https://github.com/darkrei08/setup-ai/issues/12); **verified** here that this worktree is clean |
| A dirty / locked authority store | Status is `clean`, `complete`, `authoritative`, `entries: []`, lock `released`; authority inspection is `valid: true` with 0 entries and 0 edges; nothing written in 30 minutes. | **Verified**, §3 |
| A missing or unanswered consent answer | The route never gets far enough to emit a consent envelope (§1), and the consent relay is not what blocks: RDD is on globally, and the RDD consent question was already recorded. The blocking envelope is a native-status reconciliation, not a consent state. | **Read** for the envelope; **verified** for mode-on and the recorded question (`review-mode/rar-authority/v1/rdd-mode/asked.json`) |

The fourth hypothesis worth naming: **not** a broken install of `gentle-ai` itself.
`gentle-ai doctor` reports the tool healthy at 2.7.0 on `PATH`. The problem is the
*provider's* pinned package-local binary (§4), which `doctor` does not inspect.

## 8. Continuations

Two, and only two. The first is a fix; the second is a decision to stop reviewing on this
clone. Neither one is a workaround to apply silently, and **neither was run while writing
this note** — the native review was never attempted here.

1. **Align the versions — make the provider's pinned binary exist.** Close §4 and re-run
   `gentle-ai review capabilities` plus one `start`. If the envelope changes shape, the
   contract surface is fine and §6 is next; if it still blocks, capture the new envelope
   verbatim (it will name its own cause).
2. **Turn the review off for this clone — an explicit human decision.**
   `gentle-ai review mode disable --scope clone` stops the native review from running here
   and hands delivery back to ordinary repository policy. This is the documented off-path
   of the consent envelope, it is clone-scoped, and it is *not* the global kill switch.
   Choose it knowingly: it is a decision to deliver unreviewed, not a repair.

Do **not** loop on `start`. Each attempt reconciles to the same `blocked` state without
touching the store; repetition adds no information.

## 9. Environment

| Item | Value |
| --- | --- |
| OS | Windows 11, Git Bash |
| `gentle-ai` on `PATH` | 2.7.0 — `C:\Users\Admin\go\bin\gentle-ai.exe` (executable sha256 `03dcf405809e2eeea6da9930ac894bcbcdef7f60128b37855c4e8821f25ea6a3`, self-reported) |
| `gentle-pi` | 2.6.0 — `C:\Users\Admin\.pi\agent\npm\node_modules\gentle-pi` |
| `gentle-pi` pinned native binary | gentle-ai **2.8.0** — absent |
| Native protocol | 1.5 under `--contract=…/v1`; 2.5 under `--contract=…/v2` |
| RDD mode | on, decided by global; clone-local unset |
| Observation date | 2026-09-13 |

## 10. Related

- [#1 — Windows: EPERM on state.json rename breaks pi workflows and RDD review](https://github.com/darkrei08/setup-ai/issues/1)
- [#12 — docs/guard: prevent branch switching during an active RDD review](https://github.com/darkrei08/setup-ai/issues/12)
- [`docs/pi-extensions.md`](pi-extensions.md) — the npm 12 install-script approval that
  §4 depends on, and the two-root package shadowing
