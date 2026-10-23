# Reviewer concerns — sprint-1 (PR: cycle-126 sprint-247, full-size adapters / Bridgebuilder / Flatline)

Scope: `pr/head.diff` (65 files). Citations use `head/<path>:<line>`.

## Confirmed by execution (overlay of head files, package init bypassed)

1. `head/.claude/adapters/loa_cheval/providers/retry.py:472-496` — the one-shot output-budget shrink on
   `ProviderContextLimitError` uses `continue`; when the error lands on the LAST permitted attempt
   (`retry.max_retries: 0`, or three transient failures first), the loop ends without recording
   `last_typed_error`, the shrunk request is never sent, and the function raises
   `RetriesExhaustedError` ("Failed after 1 attempts: unknown"), which cheval WALKS to the next hop
   with the same oversize payload — the exact thing D-1.1b forbids. No observed-bound row is written.
   Reproduced: seen=[64000] only, RetriesExhaustedError raised, for both scenarios.

2. 56 of the PR's adapter-level pytest cases pass (ceiling policy, pricing, estimator, probe
   write-catalog, retry shape tests, count_tokens, adapter defaults). The cheval-importing suites
   (e2e, transport matrix, catalog floor, max_tokens defaults, input-size consumers) could not run in
   this environment (workspace drift in untouched modules), so the end-to-end dispatch path is
   reviewed by reading only.

3. bats: flatline-max-tokens (6/6), multipass-estimator (3/3), cost-report CR-8, cycle-124 B1–B4,
   effort-dispatch ED-8, call-model-schema CM-1..5 pass against head scripts.

## Suspected (reading)

4. `head/.claude/skills/bridgebuilder-review/resources/config.ts:173` — the new default `model: "opus"`
   is not a key of `GENERATED_TOKEN_BUDGETS` (`head/.../core/truncation.generated.ts`) nor of the hand
   table, and the head's generated module exports no alias map, so `getTokenBudget("opus")` falls to
   the `default` row (100K / 4096 / 0.25). The 32K/160K budgets this PR generates for the 5-family are
   unreachable under the default configuration.

5. `head/.claude/skills/bridgebuilder-review/resources/config.ts:176` — `maxInputTokens: 200_000`
   exceeds the 180K probed input bound the `opus` target runs under in cheval (and the 160K
   generated maxInput); a review prepared to the full default is preempted (exit 7).

6. `head/.claude/scripts/flatline-orchestrator.sh:129,1027` — review/skeptic/score default output budget
   moves 16000 → 64000 while the per-call timeout stays 600 s; cycle-124 bounded it precisely so the
   timeout never met a 64K generation.

7. `head/.claude/scripts/loa-status.sh:815-818` — an observed row with `observed_input_tokens: 0`
   (written when the gate is disabled and the provider message states no numbers) yields
   "ceiling: observed -1"; the Python reducer skips non-positive values, the jq does not.

8. `head/.claude/adapters/loa_cheval/providers/base.py:1002-1006` — `estimate_input` reports
   `method: "tiktoken"` whenever the import succeeds, but `estimate_tokens` falls back to the heuristic
   when the encoding cannot load; the envelope then misreports the method.

9. `head/.claude/adapters/loa_cheval/routing/ceiling.py:150-152` — unreachable branch in
   `fit_max_tokens` (a `requested < FLOOR` that fits is already returned by the first branch).

10. Catalog: the 1M-window 4.6–4.8 entries carry no `pricing.long_context` block while the 5-family
    does (`head/.claude/defaults/model-config.yaml`); a 600K request to them is billed at base rate.

11. Only the Anthropic HTTP adapter raises `ProviderContextLimitError`; Bedrock/OpenAI/Google size
    verdicts keep walking.

Please look especially for: other callers broken by `CompletionRequest.temperature` defaulting to
`None`; any place the pre-flight count (`_walk_estimate`) and the per-hop heuristic disagree; the
`write_catalog` text editor's assumptions about catalog indentation.
