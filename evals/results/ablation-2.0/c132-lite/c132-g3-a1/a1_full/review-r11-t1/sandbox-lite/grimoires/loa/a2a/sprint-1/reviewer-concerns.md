# Reviewer concerns — sprint-1 (cycle-126 PR: full-size adapters / ceiling policy)

Scope: pr/head.diff (65 files). Cite as head/<path>:<line>.

Phase-2 concerns to probe:
1. cheval.py walk gate: pre-flight may replace the heuristic with the provider count (D-1.4), but the per-hop
   `_input_threshold` compare re-runs `estimate_tokens(messages)` — a count that is LOWER than the heuristic
   is accepted at pre-flight and then refused (ROUTING_MISS) at the walk gate.
2. Bridgebuilder default model "opus" (alias): does getTokenBudget / provider inference / validateApiKeys
   resolve aliases on the TS side? If not, the default falls to TOKEN_BUDGETS["default"] (100K/4096) or an
   unknown provider — defeating "every size decision derives from the resolved catalog entry".
3. Bridgebuilder DEFAULTS.maxInputTokens 200_000 > the 5-family probed bound (180K) and the generated
   maxInput (160K): a full-size review payload preempts at cheval's gate under the default policy.
4. Flatline: every voice now passes --max-tokens 64000 (was 16000 bounded so the 600 s per-call timeout never
   meets a 64K generation, cycle-124). Score calls (small JSON) on opus-5 with adaptive thinking get 64K.
5. retry.py: the one-shot shrink `continue` consumes a retry slot; with max_retries=0 the typed error is lost.
6. is_context_limit_message markers ("context window", "input length", "context length") are broad: a 400 of a
   different class containing those words is typed non-walkable and lowers the observed bound.
7. default_max_tokens for non-Anthropic 4096 → 16K: golden request-body fixtures for gpt-*/gemini-* and the
   non-streaming read timeout for OpenAI/Google (no per-provider lengthening).
8. CompletionRequest.temperature now Optional[None]: untouched adapters (xai, cursor, CLI) that still put
   request.temperature on the wire send null.
9. estimate_input labels method "tiktoken" when the module imports, but estimate_tokens may be chars/3.5 only.
10. pricing.calculate_total_cost: long-context threshold compared against input_tokens only — cache-read /
    cache-write tokens excluded from the threshold test.
11. tools/ceiling-probe-live.py write_catalog: test has a dead `if False else` expression; main() record keys.
12. dist/.build-manifest.json sha256 entries vs the head resources files (stale dist?).
13. tests/unit/cycle-124-dispatch-budgets.bats header still says 64K is reserved for open-ended calls.
