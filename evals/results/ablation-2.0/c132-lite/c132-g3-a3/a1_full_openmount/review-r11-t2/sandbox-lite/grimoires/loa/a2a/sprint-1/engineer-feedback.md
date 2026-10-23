# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-23
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)

---

## Overall Assessment

The change under review is the cycle-126 sprint-247 PR "full-size adapters, Bridgebuilder and Flatline — every size
decision derives from the resolved catalog entry" (65 files; `pr/head.diff`). The core of it is sound: the new
`loa_cheval/routing/ceiling.py` policy module is small, pure and well tested; the provider context-limit class
(`ProviderContextLimitError`, not walked, observed-bound store, calibration command) is wired end to end and its e2e
tests pass; the Flatline per-voice budget and the generated `MODEL_MAX_OUTPUT` map agree with the catalog
(`gen-adapter-maps.sh --check` is clean); the Bridgebuilder generated tables agree with the yaml for every entry.

Three defects block the merge. The first is in the dispatch path the PR is about: the per-hop input gate in
`cmd_invoke` still compares the raw character heuristic, not the estimate the pre-flight just accepted (which may be
the provider's `count_tokens` answer), so the D-1.4 count feature is defeated on the walk and a call the pre-flight
dispatched is skipped at every HTTP hop. The second is in Bridgebuilder: the default model becomes the alias `opus`
(and the personas `tiny` / `opus`) but the truncation budget tables are keyed by concrete ids and nothing in this PR
resolves aliases, so the default review runs with no per-model input clamp (200K, above cheval's 180K probed bound).
The third is in the retry layer: the one-shot output-budget shrink is silently lost when the provider's verdict
arrives on the last attempt, and the error degrades to a walkable `RetriesExhaustedError` — the exact outcome D-1.1b
forbids. Both dissent voices (Phase 2.5) found all three independently.

Process: `reviewer.md` is the PR description only — it carries no `## AC Verification` walkthrough, no test or
fast-gate evidence, which is on its own an automatic CHANGES_REQUIRED under this skill. Verification evidence I could
produce in this sandbox is listed under "Verification performed" (with the caveat that the workspace tree is a later
revision of the repository, not the PR's base).

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Functionality — the walk gate ignores the pre-flight / counted estimate (cheval)

- **HIGH** (confidence: high) `head/.claude/adapters/cheval.py:2119-2120` — the per-hop input gate recomputes `estimate_tokens(messages)` (the chars/3.5 heuristic) and compares it with the hop bound, while the pre-flight at `:1815-1845` may have replaced the estimate with the provider's `count_tokens` answer (`_walk_estimate`, `:1842`). A request the pre-flight dispatched on the count is skipped as ROUTING_MISS at every HTTP hop.
**File:** `head/.claude/adapters/cheval.py:2119-2120` (also `:2090`, where the same loop's I1 fit uses `_walk_estimate`)
**Issue:** Concrete failing input under the default `probed` policy: a 1M-window head entry (`claude-opus-5`, probed 180,000), a prompt whose heuristic is 190,000 tokens and whose `count_tokens` answer is 175,000. Pre-flight: 190,000 ≥ 0.9 × 180,000 so the counter runs (`ceiling.py:409`), `est` becomes 175,000 ≤ 180,000 → `dispatch`, envelope `estimator.method: count_tokens`. Walk, hop 1: `_lookup_max_input_tokens` returns 180,000; `_estimated = estimate_tokens(messages)` = 190,000 > 180,000 → `ROUTING_MISS`, `continue`. Every HTTP fallback (same probed value) is skipped the same way; the call lands on `claude-headless` (6–10 min) or exits CHAIN_EXHAUSTED. The same happens on a 200K entry after the pre-flight I1 shrink: the hop fit (`:2090`) uses the counted 170,000 → `max_tokens` 30,000 → derived bound 170,000, then the gate compares the heuristic 190,000 against it.
**Why This Matters:** D-1.4 ("near the bound the provider's count replaces the estimate") is the reason the count endpoint exists; it only works at the pre-flight, and the two gates inside one loop disagree with each other. The envelope then records `preflight_decision: dispatch` with `method: count_tokens` next to a `ROUTING_MISS` quoting the heuristic — contradictory telemetry an operator cannot act on. No test covers the default-policy case with a count below the heuristic (`test_opt_in_count_endpoint_is_authoritative` runs under the `derived` opt-in where the bound is 936,000, so the heuristic passes anyway). Dissent: DISS-001 (gpt-5.5-pro), DISS-C-001 (claude-headless), both BLOCKING.
**Required Fix:** Use the walk estimate at the hop gate — `_estimated = _walk_estimate if _walk_estimate is not None else estimate_tokens(messages)` — and add an e2e row (default policy, counter → 175,000, heuristic ≈ 190,000, head entry 1M) asserting one dispatch and no ROUTING_MISS.

**Example:**
```python
# Current (problematic) — cheval.py:2118-2120
from loa_cheval.providers.base import estimate_tokens
_estimated = estimate_tokens(messages)
if _estimated > _input_threshold:

# Should be
_estimated = _walk_estimate if _walk_estimate is not None else estimate_tokens(messages)
if _estimated > _input_threshold:
```

### 2. Functionality — Bridgebuilder's alias defaults have no token budget

- **HIGH** (confidence: high) `head/.claude/skills/bridgebuilder-review/resources/config.ts:172` — the built-in default model becomes the alias `opus` (and `personas/quick.md:2` → `tiny`, `personas/security.md:2` → `opus`), but the budget tables the reviewer consults are keyed by concrete ids only (`head/.claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts:19` onward; no alias map is generated by `scripts/gen-bb-registry.ts`), and `core/truncation.ts` is not touched by this PR. `getTokenBudget("opus")` falls through to `TOKEN_BUDGETS["default"]` and `effectiveInputBudget(200_000, "opus")` returns the unclamped 200,000 because the id is unknown.
**File:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:172` and `:176`
**Issue:** Before this PR the default was `claude-opus-4-7` with `maxInputTokens` 128,000: a known id, clamped to min(128,000, 160,000). After it, a default-config review of a large PR prepares up to 200,000 tokens of diff for a model whose cheval input bound is the 180,000 probed value (`model-config.yaml`), so cheval pre-empts it with CONTEXT_TOO_LARGE (exit 7) where it used to dispatch. The PR's own test only asserts the string (`__tests__/config.test.ts:161`: `assert.equal(config.model, "opus")`) and `truncation.test.ts` asserts budgets for concrete ids only; nothing exercises `getTokenBudget("opus")`. The cheval delegate resolves the alias for dispatch, so the model itself is fine — the budget lookup is what breaks. (The workspace copy of `truncation.ts` already carries an alias-resolving `budgetId()` annotated "cycle-126 sprint-250 round 2", i.e. a later fix for exactly this gap; it is not part of this change.)
**Why This Matters:** The default configuration — what every operator who did not pin a model gets — regresses from "truncated and reviewed" to "pre-empted" on exactly the large PRs Bridgebuilder exists for, and `maxInputTokens: 200_000` (`:176`) is above the catalog's dispatchable bound for the alias target even when the id is known.
**Required Fix:** Either keep concrete ids as the default/persona values, or have `gen-bb-registry.ts` emit the yaml `aliases:` block as a generated alias map and resolve it in `getTokenBudget` / `effectiveInputBudget` (and `isReasoningClass`, which keys `GENERATED_REASONING[modelId]` by concrete id too); set the input default at or under the alias target's generated `maxInput` (160,000); add a test that `getTokenBudget("opus")` equals the budget of the `opus` target.

### 3. Error handling — the retry layer's one-shot shrink is lost on the final attempt

- **HIGH** (confidence: medium) `head/.claude/adapters/loa_cheval/providers/retry.py:494-495` — the context-limit arm does `request = replace(request, max_tokens=room)` then `continue` without checking that an iteration remains and without setting `last_typed_error`. When the `ProviderContextLimitError` arrives on the last pass of `for attempt in range(max_retries + 1)` — `retry.max_retries: 0` in config, or three earlier 429/503 backoffs — the loop ends and `:531` raises `RetriesExhaustedError`, so cheval's `except ProviderContextLimitError` (`cheval.py:2247`) never fires.
**File:** `head/.claude/adapters/loa_cheval/providers/retry.py:494-495` (and `:531`)
**Issue:** The shrunk request is never sent; the typed verdict degrades to a generic `RetriesExhaustedError`, which cheval's walk path treats as walkable: the same oversized payload goes to the next voice, no `.run/ceiling-observed.json` row is written, and the operator never sees the calibration command. `last_error` is also stale or `None` in that record because this arm never assigns it. The new `test_ceiling_retry.py` only runs with `max_retries: 3` and a first-attempt error.
**Why This Matters:** Severity is the damage: it is exactly the D-1.1b invariant ("the provider's own size verdict ends the call — it is never walked") being broken; confidence is medium because the default `max_retries: 3` needs three prior transient failures to reach it, but a zero-retry configuration reaches it on the first error. Dissent: DISS-002 (gpt-5.5-pro), DISS-C-002 (claude-headless), both BLOCKING.
**Required Fix:** Perform the shrunk retry outside the attempt budget (one extra `adapter.complete()` after the shrink), or set `last_typed_error = e` and re-raise `e` when `attempt == max_retries`; add tests with `max_retries: 0` and with the context error on the final attempt.

---

## Observations

### 1. `_ceiling_unverified` is the head entry's flag but gates every hop

- **MEDIUM** (confidence: high) `head/.claude/adapters/cheval.py:1843` and `:2297` — the flag is computed once from the pre-flight on the head entry, then consulted on every hop's 429 arm (and `:2256` for the context-limit class). Under the `derived` opt-in, a 429 on a fallback hop (whose own probed bound the request may well be under, or which is calibrated) ends the call as `RATE_LIMIT_UNVERIFIED` and records an observation against that fallback entry, instead of walking as before. The arm also treats every 429 the same, including an ordinary requests-per-minute limit that says nothing about the payload (dissent DISS-003/DISS-004/DISS-C-003).
**Suggestion:** Recompute the unverified zone per hop (`estimate > probed_ceiling` of that entry, and not calibrated) or clear the flag when leaving the head entry; consider distinguishing token-limit 429 bodies from RPM ones before refusing to walk.

### 2. `/loa` prints `ceiling: observed -1` from a zero-token observation row

- **MEDIUM** (confidence: high) `head/.claude/scripts/loa-status.sh:811-819` — the jq reduction takes the `min` of `observed_input_tokens` without a positivity check, while cheval writes `observed_input_tokens: 0` when the gate is disabled and the provider message carries no numbers (`head/.claude/adapters/cheval.py:2005`: `int(_walk_estimate or 0)`). A row `{"observed_input_tokens": 0, "error_class": "PROVIDER_CONTEXT_LIMIT"}` yields `obs=0`, which passes the `^[0-9]+$` check, so the status line reads `ceiling: observed -1`. The Python reducer (`ceiling.py:252`) skips non-positive values, so the two readers disagree (dissent DISS-C-004).
**Suggestion:** Filter `observed_input_tokens > 0` in the jq, and do not append a row (or record `null`) when no positive observation exists.

### 3. Observed-bound store has an unlocked read-modify-write

- **MEDIUM** (confidence: medium) `head/.claude/adapters/loa_cheval/routing/ceiling.py:279-299` — `load_observed` → append → `os.replace`. The replace is atomic but the sequence is not; Flatline runs its voices as parallel cheval processes, so two provider verdicts within the same second drop one row (dissent DISS-C-006). The store is a calibration signal, so the damage is a lost observation, not a wrong bound. (The dissent's symlink point is not a defect: `os.replace` replaces a planted link rather than writing through it.)
**Suggestion:** Take the same per-user flock the ledger writers use (issue #689) around the read-append-replace.

### 4. Flatline: every call kind now gets a 64K budget on 128K entries

- **MEDIUM** (confidence: medium) `head/.claude/scripts/flatline-orchestrator.sh:936-946` and `:1027` — `score` (a small JSON array) and review/skeptic alike pass `--max-tokens 64000` for `claude-opus-5`. The cycle-124 rationale this replaces ("the 600 s per-call timeout never meets a 64K-output generation") is removed without touching the per-call timeout, and on the adaptive-thinking Opus the budget is shared with thinking. A runaway or long-thinking generation now runs to the timeout and drops the voice where 16K bounded it.
**Suggestion:** Keep the cap per voice but let the mode lower it (`score` has no use for 64K), or document the timeout interaction in the SDD.

### 5. Health probe: any non-404 on `/models` is now "unhealthy"

- **MEDIUM** (confidence: medium) `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:672` — `if status != 404: return False`. A gateway or proxy that does not serve `GET /v1/models` and answers 403/405/501 (or an `http_get` transport 503) is reported unhealthy without ever trying the one-token message that the previous probe used, so the breaker/status surfaces a false negative for proxied Anthropic endpoints.
**Suggestion:** Fall back to the message probe on any non-2xx other than an authentication error.

### 6. Long-context threshold ignores cache tokens

- **MEDIUM** (confidence: medium) `head/.claude/adapters/loa_cheval/metering/pricing.py:168` — eligibility tests `input_tokens > threshold` only, although the function then multiplies `cr_cost` / `cw_cost` by the input multiplier (it knows cache traffic is input-side) and the provider's published 1M rule counts the whole prompt. A request of 1,000 uncached + 250,000 cache-read tokens is billed at the base tier, `long_context` is not set on the ledger row, and `cost-report.sh` undercounts exactly the cache-heavy workloads most likely to exceed 200K (dissent DISS-005, DISS-C-005). Confidence medium because the catalog marks the tier `verified: false`.
**Suggestion:** Test `input_tokens + cache_read_tokens + cache_creation_tokens > threshold`, and pin it in `test_long_context_pricing.py`.

### 7. Estimator parity claim does not hold on hosts with tiktoken

- **LOW** (confidence: high) `head/.claude/scripts/lib-multipass.sh:95-98` — the comment says the Anthropic pass uses "the same chars / 3.5 bound cheval applies", but cheval's `estimate_tokens` (`head/.claude/adapters/loa_cheval/providers/base.py:931`) prefers the cl100k encoding for every provider when tiktoken is installed, and `estimate_input` (`base.py:1000`) labels an Anthropic estimate `method: tiktoken`. The two estimators diverge on exactly the hosts the comment describes.
**Suggestion:** Either make `estimate_tokens` provider-aware or correct the comment.

### 8. Dead branch in `fit_max_tokens`

- **LOW** (confidence: high) `head/.claude/adapters/loa_cheval/routing/ceiling.py:144-145` — `room >= requested` is equivalent to `estimate + requested <= context_window`, which the first branch already returned on; this arm is unreachable. SIMPLICITY[delete].

### 9. Long-context tier only on the 5-family

- **LOW** (confidence: low) `head/.claude/defaults/model-config.yaml:541` (claude-opus-4-8, `context_window: 1000000`) and `:744` (claude-sonnet-4-6, also 1M) — these 1M-window entries carry no `pricing.long_context`, and `head/.claude/adapters/tests/test_anthropic_catalog_floor.py:320` locks that in. If the published premium applies to them, >200K requests on these ids are under-billed by 2×.
**Suggestion:** State the applicability in the yaml comment or add the block.

### 10. Raw provider message in the calibration exit

- **LOW** (confidence: medium) `head/.claude/adapters/cheval.py:2021` and `:2029` — `str(_exc)` is interpolated into `models_failed[].message_redacted` and the stderr `_error_json` line without redaction in this closure (dissent DISS-C-007). This matches the existing arms (every other `except` does the same and relies on the modelinv emit-time redaction), and the context-limit body is a fixed-shape message with numbers, so the exposure is the stderr line only.
**Suggestion:** Route the stderr message through the shared redactor like the envelope path.

### 11. Test hygiene

- **LOW** (confidence: high) `head/.claude/adapters/tests/test_ceiling_probe_write_catalog.py:66-69` — a `… if False else …` expression leaves the first `write_catalog` call dead code inside a `pytest.raises`; only the else branch runs.
- **LOW** (confidence: high) `head/.claude/adapters/tests/test_anthropic_catalog_floor.py:295-296` — `assert A == … or derived.basis in ("calibrated", "i1")` is near-tautological for the shipped entries (every uncalibrated 1M row takes the first disjunct trivially; the 200K rows satisfy the second); it does not pin the derived value.

### 12. Complexity

- **LOW** (confidence: high) `head/.claude/adapters/cheval.py:1805-1862` and `:1994-2037` — `cmd_invoke` grows by ~250 lines (a nested closure with `nonlocal`, a 60-line pre-flight branch). The policy module itself is lean (`ceiling.py`: Lean already. Ship.). SIMPLICITY[shrink]: extract the pre-flight gate call into a helper returning `(decision, outcome)`; net: -40 lines possible in `cmd_invoke`.

---

## Cross-Model Observations

Phase 2.5 ran `adversarial-review.sh --type review --sprint-id sprint-1 --diff-file pr/head.diff` with two voices:
primary `gpt-5.5-pro` (status `reviewed`) and companion `claude-headless` (`succeeded`, `counted_as:
independent_voice`). 12 findings (8 BLOCKING, 4 ADVISORY). Disposition:

- DISS-001 / DISS-C-001 (walk gate uses the heuristic) → counted as Change 1.
- DISS-002 / DISS-C-002 (retry shrink lost on the final attempt) → counted as Change 3.
- DISS-003 / DISS-004 / DISS-C-003 (`_ceiling_unverified` head-only; every 429 refused while unverified) → Observation 1 (MEDIUM: opt-in zone, two coincident failures needed).
- DISS-005 / DISS-C-005 (cache tokens excluded from the long-context threshold) → Observation 6.
- DISS-C-004 (zero-token observation row) → Observation 2. DISS-C-006 (unlocked store; symlink) → Observation 3 (symlink part rejected: `os.replace` does not write through a link). DISS-C-007 (unredacted stderr) → Observation 10.
- Neither voice raised the Bridgebuilder alias budget defect (Change 2); it stands on my own reading.

## Rejected dissent payloads

None. `metadata.rejected_summary` is empty and both sidecars (`adversarial-rejected-review.jsonl`, companion: null) hold no rows.

---

## Acceptance Criteria Check

Sprint criterion (sprint.md): "review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict".

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| D-1.1 input bound is a policy over the entry (I1/I2, probed default, derived opt-in, legacy switch) | Pass | `ceiling.py` + `test_ceiling_policy.py` (all pass on the overlay) |
| D-1.1b provider verdict not walked, observed store, calibration command | **Fail** | `test_ceiling_e2e.py` passes, but the final-attempt path walks the payload (Change 3); Obs. 1–3 |
| D-1.4 count endpoint replaces the estimate near the bound | **Fail** | Pre-flight only; the walk gate re-compares the heuristic (Change 1) |
| D-1.3 output defaults per provider, temperature off the wire | Pass | adapters + `test_full_size_adapter_defaults.py`; no other adapter puts `request.temperature` on the wire |
| D-1.2 beta headers allowlisted, one header | Pass | regex anchored; ConfigError on anything else |
| D-1.5 Bridgebuilder budgets/reasoning from the yaml, alias default | **Fail** | generated tables consistent with yaml; alias default has no budget (Change 2) |
| D-1.6 Flatline per-voice budget from the catalog | Pass (Obs. 4) | `flatline-max-tokens.bats` 6/6 pass; `gen-adapter-maps.sh --check` OK |
| D-1.7 health probe without a retired id | Pass (Obs. 5) | |
| D-1.9 long-context pricing + ledger flag + cost-report count | Pass (Obs. 6, 9) | `test_long_context_pricing.py`, `cost-report.bats` CR-8 pass |
| `/loa` surfaces the bound | Pass (Obs. 2) | |
| Implementation report carries `## AC Verification` with file:line evidence | **Fail** | `reviewer.md` is the PR title + "65 file(s) in scope" |

---

## Verification performed

- Workspace caveat: the checked-out tree is neither `pr/base` nor `pr/head` (it is a later revision of the repository), so the head could not be reconstructed exactly. Tests ran on an overlay of the 65 head files over that tree, with the tree's superset `types.py` to satisfy newer untouched modules.
- Python: 163 passed, 1 failed — `test_advisor_tier_points_at_opus_5`, a pre-existing test (present in `pr/base`) that reads the live sandbox `.loa.config.yaml`; not a PR defect.
- bats: `flatline-max-tokens.bats` 6/6, `multipass-estimator.bats` 3/3, `cost-report.bats` CR-8 pass.
- `gen-adapter-maps.sh --check`: generated maps match the head yaml. Generated Bridgebuilder tables (`truncation.generated.ts`, `config.generated.ts`) checked against the yaml for every entry: consistent (maxOutput = min(declared, 32K), reasoning flag = thinking_adaptive ∨ thinking_traces, maxInput = ceiling − 20K). `dist/` artefacts carry the same reasoning flags as the sources.
- FAST-GATE: the report gives no evidence that `tsc --noEmit` / the formatter ran; the rebuilt `dist/.build-manifest.json` implies a build, but it could not be verified here (no node_modules).

---

## Security Checklist

- [x] No hardcoded secrets or credentials (the retired snapshot id is gone from the probe; the store holds counts only)
- [x] Input validation and sanitization present (beta-header allowlist is anchored — prevents header injection, CWE-113; `_long_context_fields` rejects malformed blocks; env knobs parsed defensively)
- [x] Authentication/authorization correct (count_tokens reuses the adapter's own headers/key; no new credential path)
- [x] No SQL/XSS injection vulnerabilities (n/a)
- [x] Dependencies secure (no new dependencies)
- [x] Error messages don't leak sensitive data (provider messages pass through the existing emit-time redaction; see Obs. 10 for the stderr line)

---

## Code Quality Summary

**Strengths:**
- `ceiling.py` is a clean, pure, well-named policy module with every basis labelled and an envelope projection; its unit tests are thorough.
- The provider context-limit class is typed end to end (adapter → retry → cheval → envelope → `/loa`), with the calibration command surfaced in three places.
- Generated artefacts (shell maps, TS tables, dist) are regenerated and consistent with the catalog.

**Areas for Improvement:**
- The two gates inside `cmd_invoke`'s walk loop must read the same estimate (Change 1).
- Alias-valued defaults need alias-aware budget lookups (Change 2).
- The retry layer's shrink must not depend on an iteration remaining (Change 3).
- The implementation report must carry the AC walkthrough and fast-gate evidence.

---

## Next Steps

1. Address the three Changes Required above (and Observations 1–3 while in the same files).
2. Add the missing tests (default-policy count rescue; `getTokenBudget("opus")`; `max_retries: 0` shrink).
3. Update `grimoires/loa/a2a/sprint-1/reviewer.md` with an `## AC Verification` section (every AC, `file:line` evidence, test and fast-gate output).
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":6,"low":7},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-23T03:52:00Z"} -->
