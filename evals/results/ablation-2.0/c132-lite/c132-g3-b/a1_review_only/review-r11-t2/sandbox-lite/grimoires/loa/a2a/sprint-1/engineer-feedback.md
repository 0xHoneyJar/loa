# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-23
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (mirrors `pr/PR.md`)

---

## Overall Assessment

The change under review is `pr/head.diff` (65 files): cycle-126 "full-size adapters" — a new input-bound policy module (`loa_cheval/routing/ceiling.py`), a typed non-walkable `ProviderContextLimitError` with a one-shot output-budget shrink in the retry layer, catalog-driven output defaults for every provider, an unset-by-default temperature, allowlisted `anthropic-beta` headers, a `count_tokens` pre-flight, a long-context pricing tier, Flatline per-voice budgets from the generated maps, and a Bridgebuilder default model/budget retarget.

The policy module itself is well built: every basis is named, the observed store is append-only and atomic, the legacy kill switch is honoured end to end, and the unit tests (`test_ceiling_policy.py`, `test_ceiling_e2e.py`) assert the decision table concretely. The catalog edits are uniform and the `--write-catalog` tool is byte-preserving.

Three defects block merge, each at the seam between the new module and an existing consumer:

1. The retry layer's shrink-and-`continue` spends a loop attempt, so on the final attempt the typed provider verdict is replaced by a generic `RetriesExhaustedError` and cheval walks the chain — the exact behaviour D-1.1b forbids.
2. The long-context premium is keyed on `input_tokens` alone, which for Anthropic excludes cache-read and cache-creation tokens, so cached long prompts are billed at base rates in the ledger.
3. Bridgebuilder's new default model is the alias `opus`, but the generated truncation table in this PR is keyed on canonical ids and carries no alias map, so the default configuration resolves to the 100K/4096 fallback row.

Several medium findings concern the head-only `_ceiling_unverified` flag being applied to every fallback hop, the undifferentiated 429 short-circuit under the opt-in, and a 4× Flatline output budget with unchanged per-call timeouts.

**Process note.** `reviewer.md` carries only the PR title — there is no `## AC Verification` walkthrough, which the skill treats as an automatic CHANGES_REQUIRED on its own. The PR's Python test suite could not be executed in this workspace: the repository's untouched modules are newer than the PR's base (e.g. `headless_cli.py` imports `headless_connect_floor`, which the PR's `types.py` predates), so collection fails on import. Test assertions were verified by reading; no runtime result is claimed below.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Error handling — the retry layer loses the provider's size verdict on the last attempt

- **HIGH** (confidence: high) `head/.claude/adapters/loa_cheval/providers/retry.py:495` — the one-shot output-budget shrink does `request = replace(...)` then `continue`; when the `ProviderContextLimitError` arrives on the final iteration of `for attempt in range(max_retries + 1)` (line 354) — `max_retries: 0` in `retry` config, or after earlier 429/5xx retries consumed the budget — the loop exits without re-sending, `last_typed_error` is never set in this branch (lines 472–496), and the post-loop `raise RetriesExhaustedError(...)` (line 530) replaces the typed, non-walkable verdict.
**File:** `head/.claude/adapters/loa_cheval/providers/retry.py:472-496`
**Issue:** cheval's walk catches `ProviderContextLimitError` (`head/.claude/adapters/cheval.py:2247`) to end the call, record the observed bound and print the calibration command. A `RetriesExhaustedError` instead reaches the generic handler (`cheval.py:2338`) and the chain walks to the next voice with the same oversized payload. `last_error` is also stale in that case (it is only assigned in the other branches), so the exhausted message names a previous error or `None`.
**Why This Matters:** This is the invariant the sprint names ("the provider's own size verdict ends the call — it is never walked"). Under `max_retries: 0` the shrink retry also never happens at all, so the `input + max_tokens > limit` shape is never retried at the smaller budget; the fallback voice is billed for a payload known to be refused, and no `.run/ceiling-observed.json` row is written.
**Required Fix:** Do not spend a retry slot on the shrink. Either re-dispatch immediately inside the handler, or loop over `range(max_retries + 2)` guarded by `_context_shrink_done`; in every path set `last_typed_error = e` and re-raise the `ProviderContextLimitError` (never `RetriesExhaustedError`) when the loop ends after a context-limit error. Add a test with `max_retries: 0` and one where the context error follows a 429 on the last attempt (`test_ceiling_retry.py` currently uses `max_retries: 3` only, line 31).

```python
# Current (problematic) — retry.py:488-495
_context_shrink_done = True
...
request = replace(request, max_tokens=room)
continue            # on attempt == max_retries this falls through to RetriesExhaustedError

# Should be (shape)
last_typed_error = e
if attempt >= max_retries:
    raise            # the typed verdict must reach cheval
request = replace(request, max_tokens=room)
continue
```

### 2. Metering — the long-context threshold ignores cached prompt tokens

- **HIGH** (confidence: medium) `head/.claude/adapters/loa_cheval/metering/pricing.py:168` — `if threshold is not None and input_tokens > threshold` compares only the uncached `input_tokens`; the Anthropic adapter maps `cache_read_input_tokens` / `cache_creation_input_tokens` into separate fields (`head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:557-562`) and `create_ledger_entry` passes them as `cache_read_tokens` / `cache_creation_tokens` (`head/.claude/adapters/loa_cheval/metering/ledger.py:162-166`), so a 10K fresh + 240K cached prompt is priced at base rates while the provider bills the premium tier.
**File:** `head/.claude/adapters/loa_cheval/metering/pricing.py:163-175`
**Issue:** The provider's published rule for the 1M-window family applies the premium when the request's total prompt exceeds 200K tokens; cached tokens are part of that prompt. The multipliers are correctly applied to `cr_cost` / `cw_cost` once the branch is taken (lines 172–173), which shows the intent — only the trigger is wrong. The catalog itself marks the tier `verified: false` (`head/.claude/defaults/model-config.yaml`, the `long_context` blocks), so this is the point to get the base right.
**Why This Matters:** Cached long-context reviews (the Flatline / Bridgebuilder shape — a stable persona prefix plus a large diff) are the main consumer of the 1M window. The ledger systematically under-reports those rows by up to 2× on input and `long_context_rows` in `cost-report.sh` undercounts, which is the signal the budget enforcer reads.
**Required Fix:** Compare `input_tokens + cache_read_tokens + cache_creation_tokens > threshold` (and say so in the comment above line 163). Extend `test_long_context_pricing.py` with a cached case (`calculate_total_cost(10_000, 1, 0, big, cache_read_tokens=240_000)` expecting `long_context_applied is True`). If the provider's rule turns out to be uncached-only, record that finding next to the threshold instead — either way the choice must be explicit.

### 3. Bridgebuilder — the default model alias has no token-budget row

- **HIGH** (confidence: medium) `head/.claude/skills/bridgebuilder-review/resources/config.ts:172` — the built-in default becomes `model: "opus"`, but `getTokenBudget` / `effectiveInputBudget` (`resources/core/truncation.ts`) look ids up in `GENERATED_TOKEN_BUDGETS` and the hand table, both keyed on canonical ids; the generated table this PR ships (`head/.claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts:19-51`) exports only `GENERATED_TOKEN_BUDGETS`, with no alias map, and the generator (`head/.claude/skills/bridgebuilder-review/scripts/gen-bb-registry.ts`) emits none, so the default configuration resolves to `"default": { maxInput: 100000, maxOutput: 4096 }` (line 51) instead of the 160K/32K row the previous default `claude-opus-4-7` had.
**File:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:172-176`
**Issue:** The PR raises `maxInputTokens` to 200K (line 176) "to match the 200K-class payload" while the budget clamp for the default model silently drops to 100K — or, where no clamp applies, a 200K payload is sent against a 160K dispatchable bound and cheval preempts with CONTEXT_TOO_LARGE. The 30-minute reasoning budget still applies (the `/opus/i` regex in `multi-model-pipeline.ts`), so the regression is in payload sizing only, and it is invisible: `truncation.test.ts` asserts `getTokenBudget("claude-opus-5")` (line 121) but nothing asserts the budget of the configured default. `resolveConfig` and `SKILL.md` document the alias as "resolved by cheval"; cheval resolves it for dispatch, not for BB's local sizing.
**Why This Matters:** This is the default every Bridgebuilder run uses when no `BRIDGEBUILDER_MODEL` is set. The sprint's stated goal is that every size decision derives from the resolved catalog entry; here the default decision derives from the fallback row.
**Required Fix:** Either keep a canonical id as the default (and retarget it where the catalog's `opus` alias moves), or have `gen-bb-registry.ts` emit the catalog `aliases:` block as a `GENERATED_MODEL_ALIASES` map and resolve through it in `getTokenBudget` / `effectiveInputBudget` / `deriveTimeoutMs`. Add a test that `getTokenBudget(DEFAULTS.model).maxInput === 160_000` so the default and the table cannot drift apart again. Apply the same check to the persona hints `# model: opus` / `# model: tiny` (`resources/personas/security.md:2`, `quick.md:2`) if they are ever uncommented.

---

## Observations

### 1. Chain-walk classification (cheval)

- **MEDIUM** (confidence: high) `head/.claude/adapters/cheval.py:1843` — `_ceiling_unverified` is computed once from the head entry's pre-flight `GateOutcome` and then consulted unchanged for every hop at lines 2256 and 2297. Scenario: head runs above its probed bound under `LOA_CHEVAL_UNCALIBRATED_CEILING=derived`, fails with a walkable 503, and the calibrated fallback gets an ordinary 429 → the call ends `RATE_LIMITED` via `_calibration_needed_exit` instead of walking, and a `RATE_LIMIT_UNVERIFIED` row is appended for a hop that never ran unverified. A provider context verdict on the fallback is likewise classed `CEILING_UNVERIFIED_LIMIT`.
**Suggestion:** Recompute the flag per hop from that hop's own bound decision (`_ceiling_input_bound(_hop_entry, max_tokens=_hop_budget, observed=...)` versus `_walk_estimate`), and use the per-hop value in both `except` arms.
**Benefit:** Correct `error_class` in the envelope and the store; fallback semantics preserved for verified hops.

- **MEDIUM** (confidence: medium) `head/.claude/adapters/cheval.py:2297` — any `RateLimitError` while `_ceiling_unverified` ends the call. The comment says "the token-limit class", but `RateLimitError` carries no class (`head/.claude/adapters/loa_cheval/types.py:225-229` — provider and `retry_after` only) and the adapter raises it for every 429 (`anthropic_adapter.py:343`). A transient requests-per-minute 429 on an opt-in request therefore terminates the chain and writes a calibration row. `test_ceiling_e2e.py:352-361` locks this in as intended.
**Suggestion:** Populate a `token_limited` attribute on `RateLimitError` from the 429 body / `anthropic-ratelimit-input-tokens-*` headers and gate the short-circuit on it; let a plain RPM 429 fall through to the existing walk path.
**Benefit:** Opt-in operators keep chain fallback on ordinary rate limiting.

- **MEDIUM** (confidence: low) `head/.claude/adapters/loa_cheval/routing/ceiling.py:163-166` — the markers `"context length"`, `"context window"`, `"input length"` match any 400 whose message merely mentions the window. Such a 400 becomes a non-walkable `ProviderContextLimitError` (`anthropic_adapter.py:361`, `:503`) with no parsed numbers, so `_calibration_needed_exit` records `observed_input_tokens = _walk_estimate` (`cheval.py:2005`) as a `PROVIDER_CONTEXT_LIMIT` row — and `observed_for` then lowers the entry's bound to `estimate − 1` until calibration.
**Suggestion:** Require either a parsed number (`parse_context_limit` non-empty) or one of the specific phrases ("prompt is too long", "exceed context limit", `request_too_large`) before raising the typed error; record the estimate only when the provider stated nothing but the class is unambiguous.
**Benefit:** A validation 400 cannot poison the observed store.

### 2. Flatline per-voice budget versus timeouts

- **MEDIUM** (confidence: medium) `head/.claude/scripts/flatline-orchestrator.sh:129` — `FLATLINE_VOICE_MAX_TOKENS_CAP=64000` raises every Anthropic voice's `--max-tokens` from 16,000 to 64,000 (all 128K entries in `generated-model-maps.sh:511-526`), while `DEFAULT_MODEL_TIMEOUT=120` (line 115) and the config's 600 s per-call timeout are unchanged. The cycle-124 rationale was that "the 600 s per-call timeout never meets a 64K-output generation"; the bats header at `head/tests/unit/cycle-124-dispatch-budgets.bats:8` still states that rationale while its assertions now expect 64000. A review or skeptic voice that actually uses its budget (≈50 tok/s → >20 min) is killed by the timeout where it previously completed.
**Suggestion:** Either cap the voice budget nearer the old envelope (32K matches Bridgebuilder's `BB_OUTPUT_CAP`) or scale the per-call timeout with the budget, as `_nonstreaming_read_timeout` does; update the bats header either way.
**Benefit:** No regression in Flatline completion rate on long findings documents.

### 3. Status surface

- **MEDIUM** (confidence: high) `head/.claude/scripts/loa-status.sh:813` — the jq reduction `[.observed_input_tokens, (if .provider_limit then .provider_limit + 1 else empty end)] | min` does not filter non-positive values, whereas `observed_for` does (`ceiling.py` `_pos_int`). cheval writes `observed_input_tokens: 0` when the gate is disabled and the message states no numbers (`cheval.py:2005`, `int(_walk_estimate or 0)`), so `/loa` would print `ceiling: observed -1` for the opus target while cheval's own bound is unchanged; a row with `observed_input_tokens: 0` and a stated `provider_limit` yields 0 in the shell and `limit + 1` in Python.
**Suggestion:** `select(. > 0)` on both candidates in the jq, or skip the store write in `_calibration_needed_exit` when `_obs <= 0` and `provider_limit is None`.
**Benefit:** The two readers of the store agree.

### 4. Lower-severity items

- **LOW** (confidence: medium) `head/.claude/adapters/cheval.py:2247-2258` — `LOA_CHEVAL_LEGACY_CEILING=1` is documented as "today's literal + preempt", but the adapter raises `ProviderContextLimitError` and this handler ends the call and writes the observed store regardless of policy, so the kill switch does not restore pre-cycle walk semantics, and state written while "legacy" changes behaviour the moment the switch is cleared.
**Suggestion:** Document the policy-independence next to the switch, or under `legacy` fall back to the pre-cycle handling and skip the store write.

- **LOW** (confidence: high) `head/.claude/adapters/loa_cheval/routing/ceiling.py:144` — `if 0 < requested < FLOOR_MAX_TOKENS and room >= requested` is unreachable: `room >= requested` is exactly `estimate + requested <= context_window`, which already returned at line 138. SIMPLICITY[delete]: `net: -2 lines possible`.

- **LOW** (confidence: high) `head/.claude/adapters/tests/test_ceiling_probe_write_catalog.py:68` — the third `pytest.raises` block is `X if False else Y`; the first operand is never evaluated and the intent (a block missing `effective_input_ceiling` raises) is obscured. SIMPLICITY[shrink]: call `tool.write_catalog("      claude-opus-5:\n        context_window: 1\n", ...)` directly.

- **LOW** (confidence: high) `head/tests/unit/flatline-call-model-schema.bats:48` — still greps `FLATLINE_(REVIEW|SCORE)_MAX_TOKENS` from the orchestrator, which the PR removes; the `eval` is a no-op for those names and the line misleads the next reader.

---

## Rejected dissent payloads

- None. `metadata.rejected_summary` is empty and `grimoires/loa/a2a/sprint-1/adversarial-rejected-review.jsonl` holds zero rows (0 bytes); both voices (`codex-headless` for the `gpt-5.5-pro` primary, `claude-headless` companion) returned schema-valid payloads (`metadata.rejected_count: 0`, `companion_voice.status: succeeded`).

## Cross-Model Observations

Adversarial dissent ran on `pr/head.diff` (`adversarial-review.json`, two voices, consensus). Every payload was checked against the head files before use:

- DISS-004 / DISS-C-003 (retry fallthrough) — confirmed independently; adopted as Changes Required §1.
- DISS-003 / DISS-C-006 (long-context threshold base) — confirmed via the adapter's usage mapping; adopted as §2.
- DISS-002 / DISS-C-001 (head-only `_ceiling_unverified`) — confirmed; recorded as MEDIUM (Observations §1).
- DISS-001 / DISS-C-002 (undifferentiated 429) — confirmed; recorded as MEDIUM. The dissent cites a test `test_request_rate_429_while_unverified_walks_to_the_next_hop` that does not exist in the diff; the PR's own test asserts the opposite behaviour.
- DISS-C-004 (unredacted `message_redacted`) — not adopted: every other `models_failed` append in `cmd_invoke` stores `str(_e)` the same way (`cheval.py:2155-2399`) and the envelope emitter redacts payload strings at emission; no new exposure.
- DISS-C-005 (zero observation poisons the store) — not adopted for cheval (`observed_for` drops non-positive values) but the shell reader does not filter; recorded as MEDIUM (Observations §3).
- DISS-C-007 (temperature default `None` breaks adapters outside the diff) — not adopted: no other adapter reads `request.temperature` (`cursor_headless_adapter.py:34` documents that it ignores it).
- DISS-C-008 (kill switch does not restore walk semantics) — recorded as LOW.

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| "review the pull request, report each defect it introduces with the file and line it sits on" (sprint.md Success Criteria) | Pass | Findings above cite `head/<path>:<line>`; also written as `review.md` at the repository root in the brief's one-line shape |
| "give a merge verdict" | Pass | CHANGES_REQUIRED |
| `reviewer.md` carries a `## AC Verification` walkthrough | Fail | `reviewer.md` / `pr/PR.md` is the PR title only — automatic CHANGES_REQUIRED per the skill, independent of the findings |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (the health probe drops the retired snapshot id; `count_tokens` reuses the adapter's own headers)
- [x] Input validation and sanitization present — `params.beta_headers` is allowlisted by regex and a non-list / out-of-allowlist value is a `ConfigError` (`anthropic_adapter.py:163-182`); env knobs are parsed defensively (`ceiling.py:_guard_from_env`)
- [x] Authentication/authorization correct — no change to credential handling; `http_get` reuses the provider headers
- [x] No SQL/XSS injection vulnerabilities — n/a; the observed store is written atomically via temp + `os.replace`
- [x] Dependencies secure — no new dependencies (`tiktoken` remains optional)
- [x] Error messages don't leak sensitive data — provider messages flow through the existing redaction at envelope emission; the new `calibration_needed` stderr line carries only counts and a command template

---

## Code Quality Summary

**Strengths:**
- `ceiling.py` names every basis (`calibrated | probed | derived | observed | i1 | guard | legacy`) and the envelope records it, so a refusal is explainable from the log alone.
- The observed store is append-only, atomic, fail-open on a malformed file, and reduced by class — a 429 row is recorded but can never lower the bound.
- `--write-catalog` edits the live catalog at line level and the test proves every other entry and every comment survive byte-for-byte.
- The legacy kill switches (`LOA_CHEVAL_LEGACY_CEILING`, `LOA_CHEVAL_LEGACY_WIRE`) are threaded through policy, I1, the count, the temperature and the default budgets consistently.
- The transport matrix test ties cheval, the Bridgebuilder generated table and the Flatline maps to the same catalog rows.

**Areas for Improvement:**
- The seams between the new module and its consumers (retry loop accounting, ledger token fields, Bridgebuilder id resolution, status-script reduction) are where every blocking and most medium findings sit; each needs a test at the seam, not only inside the module.
- `_ceiling_unverified` is a per-request flag doing per-hop work.
- Comments and test headers that encode the cycle-124 rationale (16K budgets, 600 s timeouts) were left in place while the numbers moved.

Complexity: `cmd_invoke` grows by ~200 lines in an already very long function; the new `_calibration_needed_exit` closure is a reasonable extraction. No new nesting beyond three levels outside the pre-existing walk loop; no duplicate blocks beyond the two `ProviderContextLimitError` raises in the adapter (streaming / non-streaming twins, matching the file's existing pattern). Over-engineering pass: `net: -2 lines possible` (ceiling.py:144).

---

## Next Steps

1. Fix the retry fallthrough (§1), the threshold base (§2) and the Bridgebuilder default budget (§3), each with a seam test.
2. Address the per-hop `_ceiling_unverified` and the 429 class, or document the opt-in trade-off in `multi-model-reference.md`.
3. Decide the Flatline cap/timeout pairing and update the bats header.
4. Add an `## AC Verification` walkthrough to `grimoires/loa/a2a/sprint-1/reviewer.md`.
5. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":5,"low":4},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-23T07:29:00Z"} -->
