# Reviewer concerns — sprint-1 (PR: cycle-126 full-size adapters / ceiling policy)

Phase 2 notes handed to the cross-model dissent. Cite `head/<path>:<line>`.

1. Chain-walk gate ignores the provider count. `cheval.py` preflight replaces the heuristic with
   `count_tokens` and stores it in `_walk_estimate`, but the per-hop walk gate (around
   `cheval.py:2118-2120`) recomputes `estimate_tokens(messages)` and compares that heuristic to the
   same bound. Heuristic > bound >= count ⇒ preflight dispatches, walk skips the head hop
   (ROUTING_MISS) and falls to the fallback chain. D-1.4 defeated at the head hop.
2. `_ceiling_unverified` is a head-entry property applied to every fallback hop
   (`cheval.py` RateLimitError and ProviderContextLimitError arms). A 429 on a fallback hop with a
   calibrated / larger bound is not walked and is typed RATE_LIMIT_UNVERIFIED.
3. Bridgebuilder default model is now the alias `opus` (`config.ts`) while `maxInputTokens` default
   rises to 200K; the truncation tables have no alias entry and the generator emits none, so
   `effectiveInputBudget(200_000, "opus")` is unclamped (unknown id ⇒ operator budget). Previously
   `claude-opus-4-7` clamped to 160K.
4. `record_observed` is read-modify-write with no lock; concurrent cheval processes (parallel
   dissent voices) lose rows. Also `observed_input_tokens` of 1 would set the bound to 0 with no
   plausibility check; a row with 0 renders as `observed -1` in loa-status.
5. Long-context premium compares `input_tokens` only; cache read/creation tokens are multiplied
   but not counted toward the 200K threshold. Multiplier applied to already-floored costs.
6. Flatline now passes `--max-tokens 64000` explicitly on every Anthropic voice; the explicit value
   bypasses cheval's transport-aware default (16K non-streaming, 4096 legacy wire) — cycle-124's
   stated reason for the 16K literal.
7. Under `LOA_CHEVAL_LEGACY_WIRE`, thinking-model entries now log "temperature 0.7 dropped" on
   every call (the old `!= 0.7` guard is gone).
8. `write_catalog` in `tools/ceiling-probe-live.py` edits YAML by text indent; does not update
   `probed_ceiling`; no test of the written file re-parsing against the real catalog.
9. `is_context_limit_message` marker "too many tokens" also matches throttle messages; only the
   400/413 status gate protects it.
10. No CHANGELOG entry; dist/ rebuilt (manifest changed) — verify dist matches sources.
