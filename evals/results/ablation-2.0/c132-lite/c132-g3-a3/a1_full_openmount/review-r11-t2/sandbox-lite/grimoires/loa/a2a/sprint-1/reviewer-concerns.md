# Reviewer concerns — sprint-1 (cycle-126 full-size adapters PR)

Phase 2 notes for the cross-model dissent. Cite head/<path>:<line>.

1. cheval.py walk-loop input gate (head/.claude/adapters/cheval.py:2118-2120) re-estimates with the raw
   heuristic `estimate_tokens(messages)` while the pre-flight (1815-1845) may have replaced the estimate with the
   provider's count_tokens value (`_walk_estimate`). Under the default `probed` policy, a prompt whose heuristic is
   above 180K but whose count is under it is dispatched by the pre-flight and then skipped per hop as ROUTING_MISS.
2. retry.py (head/.claude/adapters/loa_cheval/providers/retry.py:472-497): the one-shot output-budget shrink does
   `continue`; on the final loop iteration this falls through to RetriesExhaustedError, so the typed
   ProviderContextLimitError is lost (walked by cheval as RetriesExhausted, no observed-bound record).
3. cheval.py `_ceiling_unverified` is computed from the head entry only (1842) but consulted on every hop's 429 arm
   (2297), so a fallback hop's 429 under the derived opt-in ends the chain instead of walking.
4. loa-status.sh `_anthropic_ceiling_json` (head/.claude/scripts/loa-status.sh:811-815) treats an
   `observed_input_tokens: 0` row (cheval writes 0 when the gate is disabled and the message carries no numbers)
   as a bound and prints `ceiling: observed -1`; the Python reducer skips non-positive values.
5. ceiling.py record_observed (head/.claude/adapters/loa_cheval/routing/ceiling.py:278-299): read-modify-write of
   the store with no lock; parallel Flatline voices can drop each other's rows.
6. flatline-orchestrator.sh: every call kind (including `score`) now gets 64000 max_tokens for a 128K entry; the
   cycle-124 rationale (600 s per-call timeout never meets a 64K generation) is reverted without a timeout change.
7. Bridgebuilder default `model: "opus"` (config.ts) and persona `# model: tiny|opus`: check getTokenBudget/
   effectiveInputBudget resolve the alias; otherwise the default budget (100K maxInput) applies instead of 160K.
8. fit_max_tokens lines 144-145 are unreachable (the condition is implied by the first branch).
