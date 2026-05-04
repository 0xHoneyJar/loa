# Flatline Review Failure Postmortem (cycle-099 PRD v1.0, 2026-05-04)

The PRD-level Flatline review of `grimoires/loa/prd.md` v1.0 failed in two attempts. The failures are themselves evidence for cycle-099's scope. This postmortem captures the failure pattern as primary-source data for the cycle.

## Attempt 1 — default routing (legacy adapter)

**Configuration**: `hounfour.flatline_routing: false` (the framework default).

**Failures (2 of 6 Phase 1 calls)**:
- `gpt-review` (gpt-5.5-pro) — exit 2, model-adapter.sh.legacy doesn't know `gpt-5.5-pro`
- `gpt-skeptic` (gpt-5.5-pro) — same root cause

**Successes**:
- Opus review + skeptic
- Gemini-3.1-pro-preview review + skeptic

**Consensus output**: empty. `ERROR: No items to score in either file`. Phase 2 ran with degraded input but consensus calculation refused to score with 2 missing voices.

**Root cause**: `.claude/scripts/model-adapter.sh.legacy` has only `gpt-5.3-codex` for OpenAI. The `.loa.config.yaml::flatline_protocol.models.secondary: gpt-5.5-pro` is not in this dict. This is the **exact registry fragmentation problem `#710` names**: legacy adapter and `generated-model-maps.sh` (hounfour) drift independently.

## Attempt 2 — hounfour routing (cheval)

**Configuration**: `hounfour.flatline_routing: true` (temporary flip for this review).

**Failures (5 of 6 Phase 1 calls)** — three distinct error modes:

### Failure mode A: cheval alias mismatch (GPT + Gemini)
```
INVALID_CONFIG: Unknown alias: 'gpt-5.5-pro'.
Available aliases: ['cheap', 'claude-opus-4-0', ..., 'deep-thinker',
'gemini-3-flash', 'gemini-3.1-pro', 'gpt-5.2-codex', 'gpt-5.3-codex',
'native', 'opus', 'reasoning', 'researcher', 'reviewer', 'tiny']
```

**Root cause**: cheval requires aliases or `provider:model_id` format. The bare model IDs `gpt-5.5-pro` and `gemini-3.1-pro-preview` exist as `providers.openai.models.<id>` and `providers.google.models.<id>` entries in `model-config.yaml`, but they are NOT registered as `aliases.<name>` entries. The `.loa.config.yaml::flatline_protocol.models.{secondary, tertiary}` references the bare model IDs directly.

This is **a second flavor of the registry fragmentation problem**: `model-config.yaml::aliases` and `model-config.yaml::providers.<p>.models` are TWO separate namespaces. The cheval CLI accepts only the alias namespace as input. The hounfour-routed flatline orchestrator passes config-file values through to cheval without translating bare model IDs to aliases.

### Failure mode B: cheval HTTP/2 bug at 45KB (Opus)
```
WARNING: Unexpected error from anthropic (attempt 1/4): Server disconnected without sending a response.
... (4 attempts, all disconnected)
RETRIES_EXHAUSTED: Failed after 4 attempts: Server disconnected without sending a response.
```

**Root cause**: cycle-098's known #675 bug. Previously seen at 137KB+ payloads in cycle-098 SDD reviews. Now reproducing at 45KB. Cycle-098 RESUMPTION marks #675 as "model-adapter large-payload hardening" but the underlying httpx HTTP/2 disconnect is still a live infrastructure bug.

### Failure mode C: degraded mode propagation
With 5 of 6 Phase 1 calls failed, Phase 2 cross-scoring ran on the surviving review. Consensus calculation failed: `ERROR: No items to score in either file`. The orchestrator's degraded-mode handling does not gracefully fall back to single-model output.

## Conclusion: failure modes are PRD evidence

The cycle-099 PRD ([line 1, line 75-78](grimoires/loa/prd.md)) names the problem: **5+ independent registries that drift independently**. The PRD's own Flatline review demonstrates this empirically:

| Attempt | Failure surface | Cycle-099 FR that fixes it |
|---------|------------------|----------------------------|
| 1 (legacy routing) | gpt-5.5-pro absent from `model-adapter.sh.legacy` | FR-1.7 (eliminate legacy dict) + FR-4 (sunset legacy adapter) |
| 2 (cheval routing) | gpt-5.5-pro absent from cheval `aliases` namespace | FR-1.8 (`model-config.yaml` is the only registry) + FR-2 (operator-extensible aliases) |
| 2 (cheval routing) | cheval HTTP/2 bug | Out of scope; tracked as #675 |

The PRD's R-1, R-5, R-7 risks anticipate operator UX issues from registry fragmentation. The Flatline failures are **first-hand evidence** that the fragmentation problem is biting actively in the framework's own quality-gate infrastructure.

## Disposition

**Decision needed at operator review**:

1. **Skip PRD-level Flatline; proceed to /architect** — accept the failed review as evidence; rely on /architect's SDD-level Flatline (cycle-098 pattern: SDD pass back-propagates to PRD via SKP-002).

2. **Retry Flatline with known-good aliases** — temporarily edit `.loa.config.yaml::flatline_protocol.models.{secondary, tertiary}` to use existing aliases (`reviewer`, `deep-thinker`). This works around failure mode A but not failure mode B (HTTP/2 bug on Opus). Likely outcome: 2-of-3 model coverage.

3. **Add gpt-5.5-pro and gemini-3.1-pro-preview as cheval aliases (in this session)** — small `model-config.yaml` edit (System Zone) to add aliases pointing to the existing model entries. Would require explicit cycle-level authorization since System Zone edits are framework-managed. Could be Sprint 1 first task instead.

**Recommended**: Option 1. The PRD is v1.0 draft anyway, and the failure ITSELF is data the cycle will consume. Cycle-098 PRD also did its first Flatline pass at v1.0 → v1.1 incorporating findings; SDD-level reviews back-propagated to PRD v1.2 / v1.3. Same pattern works here: ship v1.0 PRD as-is, /architect produces SDD with full Flatline coverage (using fixed aliases or known-good substitutes), back-propagate any PRD-shaped findings into v1.1.

## References

- `grimoires/loa/prd.md` v1.0 (2026-05-04)
- `/tmp/loa-flatline-review-gpt-5.5-pro-QTsthk.log` (alias mismatch error)
- `/tmp/loa-flatline-skeptic-opus-fnAPO5.log` (HTTP/2 retry exhausted error)
- Issue [#710](https://github.com/0xHoneyJar/loa/issues/710) — registry consolidation
- Issue [#675](https://github.com/0xHoneyJar/loa/issues/675) — cheval HTTP/2 bug
- cycle-098 SDD v1.5 §"Flatline pass #4" — same #675 bug at 137KB+
- cycle-098 PRD v1.3 SKP-002 — SDD-pass back-propagation pattern
