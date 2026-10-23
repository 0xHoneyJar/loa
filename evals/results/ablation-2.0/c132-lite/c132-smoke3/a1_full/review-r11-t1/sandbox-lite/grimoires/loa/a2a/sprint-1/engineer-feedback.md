# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md (task brief: grimoires/loa/context/task-brief.md)
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)
**Change under review:** pr/head.diff — "feat(cycle-126): full-size adapters, Bridgebuilder and Flatline — every size decision derives from the resolved catalog entry (sprint-247)", 65 files

---

## Overall Assessment

The design is sound and well-tested at the unit level: the input bound becomes a policy over the catalog entry (`loa_cheval/routing/ceiling.py`), the output default follows `max_output_tokens` for every provider, temperature leaves the wire unless set, beta headers are allowlisted, the health probe drops the retired snapshot id, and the Bridgebuilder / Flatline tables are regenerated from the same catalog (verified: the generated `MODEL_MAX_OUTPUT` map matches the yaml exactly, and the dist `.build-manifest.json` sha256 values match the head sources). The 18 policy unit tests in `test_ceiling_policy.py` pass when run against the head `ceiling.py` (one path-shape assertion fails only because of the stub layout, not the code).

Three defects block the merge, all in the D-1.1b "a provider size verdict is never walked" seam, which the e2e tests do not reach because they patch `invoke_with_retry` wholesale and use a `MagicMock` adapter whose `count_tokens` never returns an int:

1. The retry layer's single output-budget shrink spends a retry attempt; on the last attempt it falls out of the loop as a generic `RetriesExhaustedError`, which cheval walks — the same oversized payload goes to the next voice and nothing is recorded.
2. The per-hop walk gate re-estimates with the heuristic and compares it against a bound derived from a budget that was fitted to the provider's count; whenever the count is lower than the heuristic (English prose) every HTTP hop is skipped as `ROUTING_MISS` for a request the pre-flight already approved.
3. `_ceiling_unverified` is computed for the head entry but consulted on every hop, so a plain 429 on a fallback hop becomes a terminal exit recorded against the wrong model.

The implementation report (`pr/PR.md`) is a two-line title with no `## AC Verification` walkthrough and no CHANGELOG entry is among the touched files; per this skill that is an automatic CHANGES_REQUIRED on its own.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Retry layer: the context-limit shrink can fall through to a walkable RetriesExhaustedError

- **HIGH** (confidence: high) `head/.claude/adapters/loa_cheval/providers/retry.py:495` — the shrink `continue` consumes an iteration of `for attempt in range(max_retries + 1)`; on the final iteration (or with `retry.max_retries: 0`) the loop ends and the post-loop `RetriesExhaustedError` is raised with `last_error` still `None` and no typed cause, so cheval's `RetriesExhaustedError` arm (`head/.claude/adapters/cheval.py:2338`) walks the identical payload to the next voice — exactly what D-1.1b forbids — and `_calibration_needed_exit` never runs.
**File:** `head/.claude/adapters/loa_cheval/providers/retry.py:472-496`
**Issue:** `except ProviderContextLimitError` sets `_context_shrink_done`, replaces the request and `continue`s without assigning `last_typed_error`/`last_error`. With `max_retries: 0` (`range(1)`) the retry never happens; with the default 3, three prior 429/5xx attempts followed by the provider's prompt-too-long 400 produce the same fall-through.
**Why This Matters:** The whole point of D-1.1b is that the provider's verdict ends the call and lands in `.run/ceiling-observed.json`. Here it becomes `FALLBACK_EXHAUSTED` → chain walk → the fallback fails identically → `CHAIN_EXHAUSTED`, with no observed-bound row and no `calibration_needed` envelope. `test_ceiling_e2e.py` cannot see this because it patches `invoke_with_retry`; `test_ceiling_retry.py` uses `max_retries: 3` and never exhausts.
**Required Fix:** Do not charge the shrink to the attempt budget (e.g. a `while` with an explicit extra iteration, or `if attempt == max_retries: raise` before the `continue`), and in every path set `last_typed_error = e` so a fall-through carries the typed cause. Add a `test_ceiling_retry.py` case with `max_retries: 0` asserting `ProviderContextLimitError` propagates (and one with the shrink retry after prior 429s).

### 2. Walk gate compares the heuristic against a bound fitted to the provider's count

- **HIGH** (confidence: high) `head/.claude/adapters/cheval.py:2119-2120` — the per-hop gate calls `estimate_tokens(messages)` afresh and compares it to `_input_threshold`, but that threshold now comes from `_lookup_max_input_tokens(..., max_tokens=_hop_budget)` where `_hop_budget` was I1-fitted (line 2090) to `_walk_estimate`, which the pre-flight replaced with the provider's count. After a shrink the bound equals the counted size, so whenever the heuristic exceeds the count the hop is skipped as `ROUTING_MISS`.
**File:** `head/.claude/adapters/cheval.py:2090-2120`
**Issue:** Concrete path under the default policy: a 200K entry (`claude-sonnet-4-5-20250929`), `--max-tokens 128000`, a prompt the count endpoint measures at 100K and the `chars/3.5` heuristic at ~114K. Pre-flight: fit shrinks to 86K, bound 114K, count runs (≥ 90 %), estimate becomes 100K → dispatch. Walk loop: `_hop_budget` = 128K → fit with 100K → 100K; `_lookup_max_input_tokens(max_tokens=100K)` → min(180K, 200K − 100K) = 100K; heuristic 114K > 100K → `ROUTING_MISS` on every Anthropic hop → `CHAIN_EXHAUSTED`. The same happens under the opt-in for any input the count certifies near the window.
**Why This Matters:** The request the pre-flight and the provider's own count approved is refused by cheval, and the operator sees a routing miss, not a size message. `test_170k_on_a_200k_entry_shrinks_the_output_budget_instead_of_failing` does not catch it because `MagicMock().count_tokens(...)` returns a `MagicMock`, which `_pos_int` rejects, so the heuristic is kept and the two estimates coincide.
**Required Fix:** Compare `_walk_estimate` (the authoritative post-pre-flight estimate) in the walk gate instead of re-running `estimate_tokens(messages)`, or fit the walk-gate bound from the unfitted budget. Add an e2e case whose adapter `count_tokens` returns less than the heuristic and asserts dispatch.

### 3. The unverified flag is head-only but applied to every hop

- **HIGH** (confidence: medium) `head/.claude/adapters/cheval.py:2297` — `_ceiling_unverified` is set once from the head entry's `GateOutcome` (line 1843) and consulted in the `RateLimitError` arm for every hop; after a walkable head failure, a 429 on a fallback hop (possibly a calibrated one, or a different provider) ends the invocation as `RATE_LIMIT_UNVERIFIED` and appends a row for the fallback model instead of walking as the cycle-104 chain contract requires.
**File:** `head/.claude/adapters/cheval.py:2297-2307` and `head/.claude/adapters/cheval.py:2256`
**Issue:** The `ProviderContextLimitError` arm has the same inheritance: a provider verdict on a calibrated fallback is labelled `CEILING_UNVERIFIED_LIMIT` (line 2256) although that hop was never in the unverified zone. The adapter raises a bare `RateLimitError(self.provider)` for any 429, so the arm cannot distinguish the token-limit class from a request-rate limit either.
**Why This Matters:** A fallback chain exists to absorb a 429; under the opt-in it now terminates the call on the first fallback 429, and the store records an observation for a model that never ran above its probed bound. `test_429_while_unverified_is_recorded_not_walked_and_never_lowers_the_bound` covers only the head hop.
**Required Fix:** Compute the unverified flag per hop (true only for `_idx == 0`, or by comparing `_walk_estimate` against the hop entry's own probed/calibrated value via `input_bound`), and use that per-hop flag for both the `RateLimitError` short-circuit and the `CEILING_UNVERIFIED_LIMIT` / `PROVIDER_CONTEXT_LIMIT` classification. Add an e2e case: head 503 → fallback 429 → walk continues (no calibration row).

---

## Observations

### 1. Observed-bound store can be lowered by a non-token verdict

- **MEDIUM** (confidence: medium) `head/.claude/adapters/cheval.py:2005` — when the provider message states no numbers, `_obs` falls back to the heuristic walk estimate and the row is written with a bound-lowering class (`PROVIDER_CONTEXT_LIMIT`). A 413 from a proxy's body-size limit, or any 400 matched by the broad markers `"context window"` / `"input length"` (`head/.claude/adapters/loa_cheval/routing/ceiling.py:164,166`), then caps the entry's bound at estimate − 1 until the operator reprobes.
**Suggestion:** Only lower the bound when the provider stated `input_tokens` or `limit`; record the rest with a non-lowering class. Treat 413 separately from the prompt-too-long 400 class.
**Benefit:** A single misclassified error cannot pin a model below its real bound.

### 2. Long-context premium ignores cache traffic in the threshold test

- **MEDIUM** (confidence: medium) `head/.claude/adapters/loa_cheval/metering/pricing.py:168` — `input_tokens > threshold` uses uncached input only, while the multipliers are then applied to cache read/write costs as well. The provider's published rule keys on the total prompt (uncached + cache read + cache creation), so a prompt-caching-heavy request above 200K total is billed base rate here and `long_context_rows` undercounts.
**Suggestion:** Compare `input_tokens + cache_read_tokens + cache_write_tokens > threshold`, and say so in the `PricingEntry` comment.
**Benefit:** Ledger and invoice agree; budget enforcement sees the real spend.

### 3. Bridgebuilder default model is an alias the generated tables do not key

- **MEDIUM** (confidence: low) `head/.claude/skills/bridgebuilder-review/resources/config.ts:172` — `model: "opus"` while `GENERATED_TOKEN_BUDGETS`, `GENERATED_MODEL_REGISTRY` and `GENERATED_REASONING` are keyed by concrete ids; a `getTokenBudget("opus")` or registry lookup on the configured model falls to the `default` row (100K / 4096), defeating the FR-1.5 32K output. `truncation.ts` and the adapter factory are outside the diff, so this could not be confirmed. Relatedly, `maxInputTokens: 200_000` (line 176) exceeds the generated `maxInput: 160000` for every Anthropic row.
**Suggestion:** Resolve the alias through the generated aliases before table lookups (or add alias keys to the generated tables), and add a test that `getTokenBudget(DEFAULTS.model)` is not the default row.
**Benefit:** The default configuration gets the budget the sprint promised.

### 4. Flatline per-voice budget: stage routing and the timeout rationale

- **MEDIUM** (confidence: medium) `head/.claude/scripts/flatline-orchestrator.sh:1027` — under score stage routing (line 1004 omits `--model` and passes `--role`), `--max-tokens` is still sized from `model_override`, so the budget belongs to a model cheval may not pick. Separately, the Anthropic voices now receive 64000 while the per-call timeout stays 600 s; the cycle-124 header in `head/tests/unit/cycle-124-dispatch-budgets.bats:5-8` still asserts the opposite rationale ("the 600 s Flatline ... timeouts never meet a 64K generation").
**Suggestion:** Skip `--max-tokens` under stage routing (let cheval's per-model default apply), and either lower `FLATLINE_VOICE_MAX_TOKENS_CAP` or raise the per-call timeout and update the bats header.
**Benefit:** Budget and routing decide from the same entry; a runaway generation cannot outlive its timeout.

### 5. Temperature default change reaches adapters outside the diff

- **MEDIUM** (confidence: low) `head/.claude/adapters/loa_cheval/types.py:22` — `temperature` is now `Optional[float] = None` and cheval passes `binding.temperature` (often `None`). The four adapters in the diff route through `wire_temperature`; any provider or CLI adapter not in the diff (xai, cursor, headless argv builders) that reads `request.temperature` directly now emits `null`. Not verifiable from the PR files.
**Suggestion:** grep `request.temperature` across `loa_cheval/providers` and the CLI adapters; add a transport-matrix assertion that no body carries `temperature: null`.
**Benefit:** No silent 400s on the untouched providers.

### 6. Process: no AC Verification walkthrough, no CHANGELOG entry

- **MEDIUM** (confidence: high) `head/.claude/loa/reference/multi-model-reference.md:63` — the reference doc is updated, but none of the 65 touched files is a CHANGELOG, and `pr/PR.md` (the implementation report) carries no `## AC Verification` section mapping FR-1.1 … FR-1.9 to `file:line` evidence. Per this skill the missing walkthrough is an automatic CHANGES_REQUIRED.
**Suggestion:** Add the CHANGELOG entry and an AC table (one row per FR with the test that pins it).
**Benefit:** Reviewers and the audit gate can trace each requirement.

### 7. Minor code observations

- **LOW** (confidence: high) `head/.claude/adapters/loa_cheval/routing/ceiling.py:144` — the branch `0 < requested < FLOOR_MAX_TOKENS and room >= requested` is unreachable: `room >= requested` is exactly the first branch's condition. SIMPLICITY[delete]: −2 lines.
- **LOW** (confidence: medium) `head/.claude/adapters/loa_cheval/routing/ceiling.py:410-414` — after the count replaces the estimate, the I1 fit is not re-evaluated, so `counted + max_tokens` may exceed `context_window` by the heuristic's error; the provider then 400s and the retry shrink pays for it.
- **LOW** (confidence: medium) `head/.claude/scripts/loa-status.sh:813` — `[.observed_input_tokens, …] | min` yields `null` for a row whose `observed_input_tokens` is null, and the outer `min` then returns null and discards every observation for the model.
- **LOW** (confidence: high) `head/.claude/scripts/lib-multipass.sh:106` — `ceil(chars / 3.5)` while cheval's `estimate_tokens` is `int(len / 3.5)` (floor); the comment claims "the same bound cheval applies".
- **LOW** (confidence: medium) `head/tools/ceiling-probe-live.py:173` and `head/.claude/adapters/loa_cheval/routing/ceiling.py:294` — `mkstemp` creates the temp at 0600 and `os.replace` gives the catalog / store that mode (the shipped catalog is group-readable); the probe's temp file is not unlinked when `write` fails.

---

## Rejected dissent payloads

None — the dissent envelope's `metadata.rejected_summary` is empty, `rejected_sidecars` is empty and no `adversarial-rejected-review*.jsonl` sidecar exists beside it.

---

## Cross-Model Observations

Adversarial dissent (`adversarial-review.json`, companion voice `claude-headless`, primary chain exhausted: `gpt-5.5-pro`, `gpt-5.5`, `gemini-3.1-pro` all `api_failure`; `counted_as: sole_voice`, `confidence_floor: low`). Triage of its seven findings against the head files:

| Dissent id | Claim | Triage |
|---|---|---|
| DISS-C-001 | retry shrink `continue` falls through to RetriesExhaustedError | Confirmed in code → counted as Changes Required #1 |
| DISS-C-002 | `_ceiling_unverified` inherited by every hop | Confirmed → Changes Required #3. Its cited tests `test_request_rate_429_while_unverified_walks_to_the_next_hop` and `test_unverified_status_is_per_hop_not_inherited_from_the_head` do not exist in `test_ceiling_e2e.py` (grep: 0 matches); the diff's own test asserts the head-hop 429 is NOT walked by design, so only the cross-hop part is a defect |
| DISS-C-003 | `message_redacted: str(_exc)` leaks secrets | Not a defect: same pattern as every pre-existing `models_failed` arm (e.g. `cheval.py:2349`), the MODELINV layer redacts at emit (`redact_payload_strings`, which the e2e test patches to identity), and the cited test `test_calibration_exit_redacts_secret_shapes_in_the_recorded_message` does not exist |
| DISS-C-004 | walk gate heuristic vs count-fitted bound | Confirmed with a concrete arithmetic path → Changes Required #2 |
| DISS-C-005 | long-context threshold excludes cache tokens | Plausible, provider rule keys on total prompt → Observation #2 (medium) |
| DISS-C-006 | `_obs` fallback poisons the store on a 413 / misclassified 400 | Partly confirmed (a 0 observation does not lower; the heuristic one does) → Observation #1 (medium) |
| DISS-C-007 | adapters outside the diff read `request.temperature` | Unverifiable from PR files → Observation #5 (medium, low confidence) |

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | The three D-1.1b defects above; AC Verification walkthrough; CHANGELOG entry |

---

## Acceptance Criteria Check

### Task 1.1: review the pull request, report each defect with file and line, give a merge verdict

| Criterion | Status | Notes |
|-----------|--------|-------|
| FR-1.1 input bound is a policy over the entry (I1/I2, probed default, opt-in derived, observed cap, guard, legacy) | Pass (unit) / Fail (walk) | `ceiling.py` policy correct and unit-tested; walk gate defeats it (Changes Required #2) |
| D-1.1b provider verdict never walked, observed store written | Fail | Changes Required #1 and #3 |
| FR-1.2 beta headers allowlisted, one header | Pass | `anthropic_adapter.py:163-182`, regex pinned by test |
| FR-1.3 output default per provider; temperature off the wire | Pass (in-diff adapters) | Observation #5 for adapters outside the diff |
| FR-1.4 estimator uncertainty + count endpoint | Pass | `base.py:947-1003`, `anthropic_adapter.py:591-619` |
| FR-1.5 Bridgebuilder tables from the yaml | Pass with caveat | Generated tables and manifest verified; alias default unverified (Observation #3) |
| FR-1.6 Flatline per-voice budget | Pass with caveat | `MODEL_MAX_OUTPUT` matches the catalog exactly; Observation #4 |
| FR-1.7 health probe without retired id | Pass | `anthropic_adapter.py:660-690` |
| FR-1.8 transport matrix | Pass | `test_transport_matrix.py` |
| FR-1.9 long-context pricing | Pass with caveat | Observation #2 |
| Implementation report carries AC Verification | Fail | `pr/PR.md` is title-only |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [x] Input validation and sanitization present (beta-header allowlist `^[a-z0-9]+(-[a-z0-9]+)*-\d{4}-\d{2}-\d{2}$` prevents header injection, CWE-113; `_pos_int` guards on every catalog/store integer)
- [x] Authentication/authorization correct (count_tokens and health probe reuse `_headers()`; the key value is never logged)
- [x] No SQL/XSS injection vulnerabilities (n/a; lib-multipass still pipes text via stdin)
- [x] Dependencies secure (no new dependencies; `tiktoken` remains optional)
- [x] Error messages don't leak sensitive data (the `_error_json` text follows the pre-existing pattern; MODELINV redaction applies at emit)
- [ ] State-file hardening: `.run/ceiling-observed.json` is a new trust input to the gate; a malformed file fails open (documented), but a writable store lets a local writer lower any model's bound (Observation #1 broadens this). Acceptable for a per-repo state dir; noted.

---

## Code Quality Summary

**Strengths:**
- Every policy decision is named in the envelope (`basis`, `ceiling_policy`, `max_tokens_shrunk`, `calibration_needed`) and tested per basis.
- Generated artefacts (shell map, TS tables, dist, manifest) are byte-consistent with the catalog.
- Kill switches (`LOA_CHEVAL_LEGACY_CEILING`, `LOA_CHEVAL_LEGACY_WIRE`) preserve the pre-cycle request body and are pinned by tests.
- `write_catalog` is a line-level edit that keeps comments; idempotency is tested.

**Areas for Improvement:**
- The e2e tests mock the retry layer and the adapter, so the three seams where the new typed error meets the chain walk are untested end to end.
- Per-hop state (`_ceiling_unverified`, `_walk_estimate`) is computed for the head and reused for every hop.

Complexity: `cmd_invoke` grows by ~170 lines in an already very long function; the new logic would read better as `_preflight_gate(...)` and `_fit_hop_budget(...)` helpers. SIMPLICITY[delete] ceiling.py:144 (−2). Net: −2 lines possible; the rest is required logic.

---

## Next Steps

1. Fix the three Changes Required (retry fall-through, walk-gate estimate, per-hop unverified flag) and add the e2e cases named above.
2. Address or explicitly defer the medium observations; add the CHANGELOG entry and an AC Verification table to the report.
3. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":6,"low":5},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T13:58:00Z"} -->
