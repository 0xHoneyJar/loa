# Reviewer concerns — sprint-1 (PR: cycle-126 full-size adapters / ceiling policy)

Phase 2 concern notes for the adversarial dissent. Diff: pr/head.diff. Cite head/<path>:<line>.

1. retry.py ProviderContextLimitError arm: the shrink `continue` consumes a retry
   attempt; on the last attempt (or with retry.max_retries: 0) the loop falls
   through to RetriesExhaustedError with last_error None and no typed error.
   cheval's RetriesExhaustedError arm WALKS to the next hop — the same payload
   reaches the next voice, which D-1.1b forbids, and nothing is recorded in
   .run/ceiling-observed.json.
2. cheval.py: `_ceiling_unverified` is computed from the HEAD entry's pre-flight
   but consulted on every hop in the walk — a 429 on a fallback hop becomes a
   terminal RATE_LIMIT_UNVERIFIED exit recorded against the fallback model.
3. cheval.py `_calibration_needed_exit`: records observed_input_tokens from the
   walk estimate (Anthropic count) for any provider's entry.
4. ceiling.py fit_max_tokens: the third branch (requested < floor and room >=
   requested) is unreachable (implies the first branch).
5. ceiling.py gate: after the count endpoint replaces the estimate, the I1 fit
   is not re-evaluated with the counted size.
6. flatline-orchestrator.sh: under score stage routing (--role, no --model) the
   --max-tokens is still sized from model_override, not the routed tier.
   64000 budget vs the 600 s per-call timeout (cycle-124 rationale reversed).
7. Bridgebuilder default model "opus" (alias) vs tables keyed by concrete ids
   (GENERATED_TOKEN_BUDGETS / GENERATED_MODEL_REGISTRY) — alias lookups miss.
8. loa-status.sh jq: a row with null observed_input_tokens makes the outer min
   null and discards every observation.
9. estimate_input labels method "tiktoken" when the module imports, mirroring
   estimate_tokens; _messages_text_and_tools counts only text blocks.
10. anthropic_adapter is_context_limit_message markers ("context window",
    "input length") may classify a non-size 400 as a provider size verdict,
    which is terminal (not walked).
11. No CHANGELOG entry in the touched files.
