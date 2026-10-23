# Reviewer concerns — sprint-1 (PR: cycle-126 sprint-247, full-size adapters / ceiling policy)

Scope: `pr/head.diff` (65 files). Verified by running the PR's tests in an overlay tree and by
direct reproduction against the head code. Cite as `head/<path>:<line>`.

## Confirmed defects (reproduced)

1. `head/.claude/adapters/cheval.py:2297` — ANY `RateLimitError` while `_ceiling_unverified` ends the
   invocation (RATE_LIMIT_UNVERIFIED, exit RATE_LIMITED) and writes a store row. The design (D-1.1b, the
   PR's own comment) scopes this to the token-limit class; `RateLimitError` carries no class in this PR, so a
   requests-per-minute 429 under `LOA_CHEVAL_UNCALIBRATED_CEILING=derived` never walks the chain.
2. `head/.claude/adapters/cheval.py:1843,2256,2297` — `_ceiling_unverified` is computed once from the HEAD
   entry's pre-flight and inherited by every fallback hop. A calibrated fallback (payload verified there)
   that answers 429 is classed RATE_LIMIT_UNVERIFIED (not walked, store row against the fallback model);
   its provider verdict is classed CEILING_UNVERIFIED_LIMIT instead of PROVIDER_CONTEXT_LIMIT.
3. `head/.claude/adapters/loa_cheval/routing/ceiling.py:264-299` — `record_observed` is read→append→
   `os.replace` with no inter-process lock; 4 concurrent writers × 25 rows retained 26–30 of 100 rows in
   three trials. Flatline / adversarial review dispatch voices concurrently against the same provider.
4. `head/.claude/adapters/loa_cheval/metering/pricing.py:165-176` — long-context multipliers applied to the
   already-floored per-category micro costs; remainders not recomputed. 3 tok × 1.25 × 1.5 bills 4 (exact
   floor 5).
5. `head/.claude/adapters/loa_cheval/metering/pricing.py:290-295` — `_mult` accepts `inf` (`.inf`, `1e309`);
   `int(inp_cost * inf)` raises OverflowError inside `calculate_total_cost` on the post-call cost path.
6. `head/.claude/skills/bridgebuilder-review/resources/config.ts:172` — DEFAULTS.model becomes the alias
   `opus`, but neither `GENERATED_TOKEN_BUDGETS` (head `truncation.generated.ts`) nor the hand table has an
   `opus` row; `getTokenBudget("opus")` falls to the `default` row (100K/4096) and the effective input
   budget is the raw operator budget (now 200_000, above the 180K probed bound). Same for `tiny` in
   `personas/quick.md`.

## Suspected / lower-severity

7. `head/.claude/adapters/cheval.py:2022` — `message_redacted: str(_exc)` not passed through the redaction
   helper at this new exit (defence in depth; the adapter sanitises).
8. `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:82,174` — `\d` + `re.match` + `$`:
   Unicode digits and a trailing `\n` pass the allowlist; the header then fails at the transport instead of
   as ConfigError.
9. `head/.claude/scripts/flatline-orchestrator.sh:129,936` — 64000 cap applies regardless of
   `LOA_CHEVAL_DISABLE_STREAMING`; the adapter's own non-streaming default is 16K and its read timeout caps
   at 600 s.
10. `head/.claude/scripts/loa-status.sh:806-813` — model id spliced into the yq expression; the jq `min`
    returns null when a row lacks `observed_input_tokens`, and a 0 row renders `observed -1`.
11. `head/.claude/adapters/loa_cheval/routing/ceiling.py:159` — marker `too many tokens` also matches a
    throttle message ("Too many tokens, please wait before trying again").
12. `head/.claude/adapters/loa_cheval/providers/base.py:1000` — `method="tiktoken"` is reported whenever the
    module imports, even when `estimate_tokens` fell back to the heuristic.

Please look especially for: other callers that assumed `CompletionRequest.temperature == 0.7`; places the
I1 shrink changes an explicit operator `--max-tokens` silently; interactions between the walk-loop I1 fit and
the adapter's own `enforce_context_window`; the `write_catalog` line-level YAML editor.
