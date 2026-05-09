# Flatline PRD Review — Degradation Report (2026-05-09)

> Captured live during cycle-102 kickoff. Documents the silent-degradation
> pattern manifesting on its own kickoff PRD review — empirical evidence for
> cycle-102 thesis (vision-019 Axiom 3).

## Outcome

```
{
  "consensus_summary": { "models": 2, "tertiary_items": 0, "confidence": "degraded" },
  "high_consensus_count": 0, "disputed_count": 0, "blocker_count": 0,
  "degraded": true, "degraded_model": "both",
  "degradation_reason": "no_items_to_score",
  "tertiary_status": "active"
}
```

Exit code: **0** (orchestrator silently swallowed the degradation per axiom-3 violation pattern).

## What actually failed (per `/tmp/loa-flatline-{review,skeptic}-*.log`)

| Call | Provider | Outcome | Typed class | Detail |
|---|---|---|---|---|
| opus-review | anthropic | succeeded? | — | No /tmp log captured; orchestrator counted it among the 3 successes |
| **opus-skeptic** | anthropic | **FAILED** | `PROVIDER_DISCONNECT` (cheval-typed) → `RETRIES_EXHAUSTED` after 4 attempts | "Server disconnected without sending a response" × 4 |
| **gpt-review** | openai | **FAILED** | `PROVIDER_DISCONNECT` → `RETRIES_EXHAUSTED` | First 2 attempts disconnected; circuit breaker tripped (5 failures ≥ threshold 5); attempts 3-4 hit "Circuit open for openai" |
| **gpt-skeptic** | openai | **FAILED** | `PROVIDER_DISCONNECT` → `RETRIES_EXHAUSTED` | All attempts hit the already-open circuit |
| gemini-review | google | succeeded? | — | Aliasing concern: model id `gemini-3.1-pro-preview` not in cheval alias map (only `gemini-3.1-pro` bare alias is). Older log `/tmp/loa-flatline-review-gemini-3.1-pro-preview-EhmzDa.log` shows `INVALID_CONFIG` for that alias. Tertiary status reported active but `tertiary_items: 0`. Suspected alias-resolution divergence. |
| gemini-skeptic | google | succeeded? | — | Same suspected alias divergence. |

## Why this matters (cycle-102 thesis evidence)

This is the silent-degradation pattern in vivo:

1. **Reframe Principle violation candidate**: orchestrator's reported "3 of 6 Phase 1 calls failed" doesn't tell the full story — the other 3 may have succeeded with empty output, or had alias-resolution divergence (gemini), or had output-parsing issues.
2. **Rollback-half-life evidence**: gpt-5.5-pro is the freshly-restored triad model from sprint-bug-143 (PR #790). Its first cycle-kickoff invocation degraded. The "fix-forward in hours" worked for the budget bug; the **transport-resilience** layer is the next surface.
3. **Visible-failure violation**: orchestrator returned exit 0 with `degraded=true`. Operator is expected to *notice* the consensus stats AND read the orchestrator log. Per cycle-102 AC-1.5 (strict) + AC-1.6 (operator-visible header), this would be a typed BLOCKER aborting the gate.

## Cheval circuit-breaker state

OpenAI circuit was OPEN at ~16:23 UTC (failures=5). Default cooldown is presumably 60s-5min. A near-term re-run would fail-fast against the open circuit until cooldown clears.

## Disposition options

1. **Wait + re-run** — circuit cooldown probably clears within 5 min; transport disconnects are commonly transient
2. **Proceed with degraded validation + explicit notation** — accept that adversarial review on PRD is incomplete; document in PRD §0 footnote
3. **Skip to /architect with audit trail** — cycle-102's thesis is *exactly* this pattern; proceeding constructs the fix that prevents future occurrences
4. **Investigate the gemini alias divergence first** — could be a real bug worth filing pre-implementation

## Sources

- `grimoires/loa/cycles/cycle-102-model-stability/flatline-prd.log` — orchestrator transcript
- `/tmp/loa-flatline-skeptic-opus-kcMRC9.log` — opus-skeptic transport failure
- `/tmp/loa-flatline-skeptic-gpt-5.5-pro-oypGoy.log` — gpt-skeptic
- `/tmp/loa-flatline-review-gpt-5.5-pro-6cBCbq.log` — gpt-review + circuit breaker trip
- `/tmp/loa-flatline-review-gemini-3.1-pro-preview-EhmzDa.log` (older mtime) — INVALID_CONFIG alias divergence (suspected ongoing)
- vision-019 Axiom 3 (Visible-Failure Principle)
- PR #781 (cheval typed classification — working correctly here)
- Issue #774 (PROVIDER_DISCONNECT class precedent)
- Issue #759 (degraded-consensus emission path referenced in scoring-engine warning)
