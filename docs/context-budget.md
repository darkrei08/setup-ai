# Pi context budget and compaction

This policy supports setup-ai issues [#100](https://github.com/darkrei08/setup-ai/issues/100) and [#102](https://github.com/darkrei08/setup-ai/issues/102). It applies to Pi sessions launched through a direct provider or a gateway such as CLIProxyAPI.

## Exact trigger

Pi does not compact at a fixed 90% threshold. Automatic compaction starts when:

```text
contextTokens > contextWindow - reserveTokens
```

The defaults are `reserveTokens: 16384` and `keepRecentTokens: 20000`. `reserveTokens` protects the next model response. `keepRecentTokens` controls how much recent history remains unsummarized after compaction; it does not delay the trigger.

Examples using the default reserve:

| Verified context window | Trigger | Approx. percentage |
|---:|---:|---:|
| 131,072 | 114,688 | 87.50% |
| 200,000 | 183,616 | 91.81% |
| 1,000,000 | 983,616 | 98.36% |

These are arithmetic examples, not claims about every model. A gateway may advertise a smaller effective context than its upstream provider.

## Measure before changing settings

1. Verify the exact provider/model with `pi --list-models "term"`.
2. Inspect the live session with `/session`.
3. For RPC clients, read `get_session_stats.contextUsage.tokens`, `.percent`, and `.contextWindow`.
4. Record the exact `provider/model` and gateway catalog response. Do not infer a context limit from a model family name.

The effective model limit includes the system prompt, tools, conversation history, tool results, and the requested output. OpenAI and Anthropic expose model-specific limits; Anthropic also provides `messages/count_tokens` for complete request input counting.

## Safe tuning

For a verified context window `C` and a desired trigger percentage `p`, the reserve is:

```text
reserveTokens = C - floor(p * C)
```

Use at least the larger of the model's verified output budget and 16,384 tokens. For long tool-heavy coding sessions, start around 80-85% rather than disabling compaction. Example for a 200,000-token window:

- 90% trigger: reserve about 20,000 tokens;
- 85% trigger: reserve about 30,000 tokens;
- 80% trigger: reserve about 40,000 tokens.

Use exact, case-sensitive model overrides only after measuring the gateway's effective limit:

```json
{
  "compaction": {
    "enabled": true,
    "reserveTokens": 16384,
    "keepRecentTokens": 20000,
    "modelOverrides": {
      "provider/exact-model-id": {
        "reserveTokens": 30000,
        "keepRecentTokens": 20000
      }
    }
  }
}
```

Do not disable automatic compaction as a general fix. It removes the safety mechanism and moves failure to provider overflow or request rejection.

## Reduce avoidable growth

- Keep one session focused on one work unit; use `/fork`, `/clone`, or a new session for unrelated work.
- Read bounded file ranges instead of dumping complete logs or generated files.
- Keep workflow prompts, reviewer inputs, and tool results scoped to the current target.
- Before compaction, preserve the goal, constraints, decisions, changed paths, tests, and next steps.
- Treat a gateway model catalog as authoritative for that gateway; Windows and Linux use the same token arithmetic, even though their configuration paths differ.

## Verification record

A configuration change is complete only when the exact model, effective context window, reserve, trigger calculation, and post-change `/session` or RPC reading are recorded. A provider or gateway change requires repeating the measurement; a larger upstream limit does not prove that the gateway exposes it.
