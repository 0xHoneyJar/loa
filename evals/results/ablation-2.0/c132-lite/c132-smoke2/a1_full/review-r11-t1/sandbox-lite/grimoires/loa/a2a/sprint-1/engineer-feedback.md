# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (carries only the PR title; `pr/PR.md` is the report per sprint.md)

---

## Overall Assessment

The change under review is `pr/head.diff` (cycle-126 sprint-247, 65 files): a ceiling *policy* module (`routing/ceiling.py`) replacing the single `effective_input_ceiling` literal, a non-walkable provider size verdict (`ProviderContextLimitError`) with an observed-bound store and probe-tool catalog writer, catalog-driven output defaults and wire temperature for every provider, Anthropic `beta_headers` / `count_tokens` / models-endpoint health probe, a long-context pricing tier, Flatline per-voice budgets from the generated maps, and Bridgebuilder generated reasoning flags and 32K output budgets.

The design is coherent and most of it is well tested. I rebuilt the head tree as an overlay and ran what the environment allows: 56 adapter-level pytest cases (ceiling policy, pricing, estimator, probe write-catalog, retry shape tests, count_tokens, adapter defaults) pass; the PR's bats suites for Flatline budgets (6/6), the multipass estimator (3/3), cost-report CR-8, dispatch-budgets B1–B4, effort-dispatch ED-8 and call-model-schema CM-1..5 pass. The cheval-importing suites (`test_ceiling_e2e`, `test_transport_matrix`, `test_anthropic_catalog_floor`, `test_max_tokens_defaults`, `test_input_size_consumers`) could not be collected here because untouched workspace modules have drifted past the PR's base, so the end-to-end dispatch path was reviewed by reading. Unrelated bats failures (cycle-124 B5/B6/B8, ED-4..7: `model-adapter.sh` exec denied in the overlay; cost-report CR-7 fails identically against the unchanged script) are environment artifacts, not defects of this change.

Three defects block the merge. One is reproduced by execution: the retry layer's single output-budget shrink on a provider context-limit error is silently dropped when that error lands on the last permitted attempt, and the typed, non-walkable error degrades into a walkable `RetriesExhaustedError` — the exact failure D-1.1b was written to prevent. The second is a gate inconsistency: after the pre-flight accepts the provider's authoritative token count, the per-hop walk gate re-derives the heuristic estimate and compares it against a bound that, once I1 has shrunk the budget, equals the count — so a heuristic that overestimates knocks the head entry out. The third is in Bridgebuilder: the new default `model: "opus"` is an alias that no budget table in the head tree knows, so the 32K/160K budgets this PR generates for the 5-family are unreachable under the default configuration.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Retry layer: the one-shot shrink is lost on the final attempt and the typed verdict becomes walkable

- **HIGH** (confidence: high) `head/.claude/adapters/loa_cheval/providers/retry.py:495` — when the `input + max_tokens > limit` verdict arrives on the last permitted attempt, `continue` ends the `for attempt in range(max_retries + 1)` loop without sending the shrunk request, `last_typed_error` is never set, and the function raises `RetriesExhaustedError("Failed after 1 attempts: unknown")`, which cheval walks to the next hop with the same oversize payload.
**File:** `head/.claude/adapters/loa_cheval/providers/retry.py:472-496`
**Issue:** The `except ProviderContextLimitError` arm (472) shrinks `request.max_tokens` and `continue`s (495) to use the next loop iteration as the retry. There is no next iteration when `attempt == max_retries`. Reproduced against the head module with the `_Adapter` shape of `test_ceiling_retry.py`:
  - `retry.max_retries: 0` + one `input length and max_tokens exceed context limit: 190000 + 64000 > 200000` error → `seen=[64000]` only, `RetriesExhaustedError` raised, `last_error='... Failed after 1 attempts: unknown'`.
  - `max_retries: 3`, three `ProviderUnavailableError` then the limit on attempt 4 → same: no shrunk attempt, `RetriesExhaustedError` whose `last_error` names the 503.
**Why This Matters:** `cheval.cmd_invoke` catches `ProviderContextLimitError` (head/.claude/adapters/cheval.py:2247) to end the call typed, record `.run/ceiling-observed.json` and print the calibration command. A `RetriesExhaustedError` instead reaches the walk arm (cheval.py:2338): the same payload is sent to every fallback hop (repeated provider 400s, wasted latency and cost), no observed-bound row is written, the exit is `CHAIN_EXHAUSTED` with an "unknown" cause, and the invariant the PR documents in `multi-model-reference.md` ("never walked to the next voice") is violated in the configuration operators use to turn retries off. `test_ceiling_retry.py` only runs with `max_retries: 3` and a first-attempt limit, and `test_ceiling_e2e.py:116` patches `invoke_with_retry` away, so neither suite reaches this path.
**Required Fix:** Perform the shrunk attempt outside the attempt budget, or re-raise the typed error when no attempt remains. Minimal shape:

```python
            request = replace(request, max_tokens=room)
            last_typed_error = e
            if attempt < max_retries:
                continue
            # no attempt left: send the shrunk request once, typed
            return adapter.complete(request)  # or raise e, so cheval stays on the typed, non-walkable path
```

  and set `last_typed_error = e` on the `raise` branch too, so a shrink that then fails is reported by class. Add a `max_retries: 0` case and a "limit on the last attempt" case to `test_ceiling_retry.py`, and one e2e case that does not patch `invoke_with_retry`.
**Reference:** CWE-754 (improper check for unusual or exceptional conditions); SDD D-1.1b as quoted in `head/.claude/loa/reference/multi-model-reference.md` ("A provider's own size verdict … is **never walked** to the next voice").

### 2. Per-hop walk gate discards the authoritative count the pre-flight accepted

- **HIGH** (confidence: medium) `head/.claude/adapters/cheval.py:2119` — the per-hop walk gate calls `estimate_tokens(messages)` (heuristic) and compares it with a bound computed from `_hop_budget`, which the I1 fit at cheval.py:2090 derived from `_walk_estimate` — the provider's `count_tokens` value when the pre-flight counted (cheval.py:1842). Whenever the heuristic exceeds the count and I1 shrank, the bound equals the count by construction, the head hop is recorded `ROUTING_MISS` and skipped although the provider said the request fits.
**File:** `head/.claude/adapters/cheval.py:2090-2120`
**Issue:** Two estimates of the same prompt flow through the walk: `_walk_estimate` (count-corrected, used by the I1 fit and therefore by `_lookup_max_input_tokens(..., max_tokens=_hop_budget)`), and a fresh `estimate_tokens(messages)` at 2119 used for the comparison. Under `LOA_CHEVAL_UNCALIBRATED_CEILING=derived` with a prompt near the window, `input_bound` returns `derived = cw − (cw − count) = count` (basis `i1`), so `heuristic > count` is the whole test. Under the default policy the same inconsistency fires for any prompt the heuristic places above 180K while the count places it below (code-heavy prompts, where cl100k counts differ from Claude's tokenizer). The fallback hops share the same probed bound and the same heuristic, so they miss too and the request lands on the CLI hop or exits `CHAIN_EXHAUSTED`.
**Why This Matters:** D-1.4 makes the provider count authoritative near the bound precisely so the heuristic's error does not decide the call; this gate re-introduces the heuristic as the decider one step later. `test_ceiling_e2e.py::test_opt_in_count_endpoint_is_authoritative` uses a count (611K) *above* the heuristic (600K), so the overestimating direction is untested.
**Required Fix:** Reuse `_walk_estimate` at 2119 (`_estimated = _walk_estimate if _walk_estimate is not None else estimate_tokens(messages)`), and add an e2e case where the counter returns a value below the heuristic near the bound and asserts the head hop dispatches.
**Reference:** SDD D-1.4 (count endpoint replaces the estimate near the bound), `routing/ceiling.py` docstring ("the provider's count is authoritative").

### 3. Bridgebuilder's new default model is an alias no budget table resolves

- **HIGH** (confidence: medium) `head/.claude/skills/bridgebuilder-review/resources/config.ts:172` — `model: "opus"` is not a key of `GENERATED_TOKEN_BUDGETS` (`head/.claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts:19-52`) nor of the hand `TOKEN_BUDGETS` table, and neither `truncation.generated.ts` nor `config.generated.ts` exports an alias map in the head tree, so `getTokenBudget("opus")` resolves to the `default` row (`truncation.generated.ts:51`: maxInput 100000, maxOutput 4096) instead of the 5-family row (`:27`: 160000 / 32000) this PR generates.
**File:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:172-178`
**Issue:** The comment says the alias "is resolved by cheval's alias path", and it is — for dispatch (`cheval-delegate.ts` passes `--model opus`). But every budget decision inside Bridgebuilder (`reviewer.ts` calls `getTokenBudget(this.config.model)` for the truncation coefficient and input budget) is keyed by the configured string, and the PR adds no alias resolution on that side. `truncation.test.ts` and `truncation-registry.test.ts` only exercise concrete ids; `config.test.ts:161` asserts the literal `"opus"` and nothing downstream of it. `isReasoningClass("anthropic","opus")` happens to survive via the `/opus/i` regex, which hides the gap.
**Why This Matters:** The headline of this sprint for Bridgebuilder — 32K output and 160K input budgets for the 5-family from the catalog — never applies when nobody sets `BRIDGEBUILDER_MODEL`. Combined with the raised `maxInputTokens: 200_000` default (config.ts:176, see Observations) the default configuration either under-budgets (100K) or over-sends (200K against cheval's 180K probed bound), depending on which path `reviewer.ts` takes.
**Required Fix:** Either keep a concrete default (`claude-opus-5`, i.e. the alias target) or emit a `GENERATED_MODEL_ALIASES` map from `gen-bb-registry.ts` (the yaml `aliases:` block) and resolve it in `getTokenBudget` before falling back to `default`; add a test that `getTokenBudget("opus").maxOutput === 32_000`.
**Reference:** SDD D-1.5 (Bridgebuilder budgets follow the resolved catalog entry).

---

## Observations

### 1. Defaults and budgets

- **MEDIUM** (confidence: medium) `head/.claude/skills/bridgebuilder-review/resources/config.ts:176` — `maxInputTokens: 200_000` exceeds both the 160K `maxInput` the generated table gives the 5-family and the 180K probed input bound cheval enforces for the `opus` target; a review prepared to the full default is preempted by cheval's pre-flight (exit 7, `CONTEXT_TOO_LARGE`) unless something downstream clamps it.
**File:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:176`
**Suggestion:** Default to the generated row's `maxInput` (160K) or clamp the operator budget to `getTokenBudget(model).maxInput` before preparing the payload.
**Benefit:** No default-configuration preempts.

- **MEDIUM** (confidence: medium) `head/.claude/scripts/flatline-orchestrator.sh:129` — the review/skeptic/score default output budget moves 16000 → 64000 (`flatline_voice_max_tokens`, applied at :1027) while the per-call timeout stays 600 s; cycle-124 introduced the 16K bound precisely so "the 600 s per-call timeout never meets a 64K-output generation", and the non-streaming read timeout `_nonstreaming_read_timeout(120, 64000)` saturates at its 600 s cap.
**File:** `head/.claude/scripts/flatline-orchestrator.sh:129,1027`
**Suggestion:** If the SDD wants one rule per voice, cap at a value the timeout can absorb (e.g. 32000, the Bridgebuilder cap) or raise the per-call timeout alongside, and say so in the KF-037/KF-038 comment in `.loa.config.yaml`.
**Benefit:** Keeps the cycle-124 timeout invariant explicit instead of silently reversed.

- **MEDIUM** (confidence: low) `head/.claude/defaults/model-config.yaml:527` — the 1M-window `claude-opus-4-8` (and `claude-opus-4-7` :574, `claude-opus-4-6` :637, `claude-sonnet-4-6` :737) carry no `pricing.long_context` block while the 5-family does; a 600K request to them is ledgered at base rate, and `test_entries_outside_the_five_family_carry_no_long_context_tier` locks that in.
**Suggestion:** Either add the tier (with `verified: false`) to every 1M-window entry or document why the 4.x family is excluded.
**Benefit:** Consistent cost reporting across the entries the catalog says have a 1M window.

### 2. Gate semantics

- **MEDIUM** (confidence: medium) `head/.claude/adapters/cheval.py:2297` — `_ceiling_unverified` is computed once from the head entry's pre-flight (cheval.py:1843) and consulted on every hop: a plain requests-per-minute 429 on a *fallback* hop ends the call as `RATE_LIMIT_UNVERIFIED` (exit 1) instead of walking, and a `ProviderContextLimitError` on a calibrated fallback is classed `CEILING_UNVERIFIED_LIMIT` (:2256) although that hop's bound was verified. (Raised by the dissent as DISS-C-002; its claim that the diff's own tests assert otherwise is false — the named tests do not exist.)
**Suggestion:** Recompute the unverified flag per hop from that hop's `input_bound` decision (`not calibrated and estimate > probed`), or only apply the 429 rule on the head hop.
**Benefit:** A transient rate limit on a healthy fallback keeps walking; calibration rows name the right class.

- **MEDIUM** (confidence: medium) `head/.claude/adapters/loa_cheval/metering/pricing.py:168` — the premium triggers on `input_tokens > threshold` only; Anthropic's `usage.input_tokens` excludes `cache_read_input_tokens` / `cache_creation_input_tokens` (anthropic_adapter.py:557-562), and the provider applies the tier to the request's total input. A 150K uncached + 100K cached prompt is billed premium by the provider and base rate here, so `long_context` and `long_context_rows` under-count exactly the cached long prompts Flatline/Bridgebuilder send. (DISS-C-006, confirmed.)
**Suggestion:** Compare `input_tokens + cache_read_tokens + cache_creation_tokens` against the threshold.
**Benefit:** Ledger matches the invoice.

### 3. Small correctness and hygiene items

- **LOW** (confidence: high) `head/.claude/scripts/loa-status.sh:813` — the jq reducer takes `min` over `observed_input_tokens` without filtering non-positive values (:814 only guards the final shape), so a row with `observed_input_tokens: 0` renders `ceiling: observed -1`; the Python reducer (`observed_for`) skips such rows. (DISS-C-005.)
- **LOW** (confidence: medium) `head/.claude/adapters/cheval.py:2005` — with `LOA_CHEVAL_DISABLE_INPUT_GATE=1` (`_walk_estimate` is None) and a provider message that states no numbers, `_obs` becomes 0 and a zero observation row is still appended to the store; skip the record when there is no positive observation.
- **LOW** (confidence: medium) `head/.claude/adapters/loa_cheval/providers/base.py:1000` — `estimate_input` reports `method: "tiktoken"` whenever the import succeeds, but `estimate_tokens` falls back to the heuristic when `get_encoding("cl100k_base")` fails (offline hosts); the envelope then misreports the method.
- **LOW** (confidence: high) `head/.claude/adapters/loa_cheval/routing/ceiling.py:144` — unreachable branch in `fit_max_tokens`: a `requested < FLOOR_MAX_TOKENS` that fits is already returned by the first `if`. `SIMPLICITY[delete]`.
- **LOW** (confidence: low) `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:672` — `health_check` returns False for any `/models` status other than 200/404; a gateway that fronts `/messages` but answers 401/403/405 on `/models` is reported down. (DISS-C-008; the previous probe was already broken by its retired model id, so this is net better.)
- **LOW** (confidence: medium) `head/.claude/adapters/loa_cheval/providers/bedrock_adapter.py:227` — only the Anthropic HTTP adapter raises `ProviderContextLimitError`; Bedrock (`ValidationException: input is too long`), OpenAI (`context_length_exceeded`) and Google size verdicts still walk the chain with the same payload. Scope note against the PR title, not a regression.
- **LOW** (confidence: high) `head/.claude/adapters/tests/test_anthropic_catalog_floor.py:296` — `assert derived.value == min(...) or derived.basis in ("calibrated", "i1")` is close to tautological (the second disjunct absorbs most real failures); split into two assertions keyed on the calibration state.
- **LOW** (confidence: high) `head/.claude/adapters/tests/test_ceiling_probe_write_catalog.py:68` — the `… if False else tool.write_catalog(...)` expression is dead code wrapped around the real assertion; keep the one `pytest.raises` on the synthetic two-line catalog.
- **LOW** (confidence: medium) `head/.claude/adapters/tests/test_ceiling_e2e.py:116` — patching `invoke_with_retry` means the retry layer never runs in the e2e suite, which is why Change 1 was not caught; one unpatched case with a stub adapter would close that seam.
- **LOW** (confidence: low) `tools/ceiling-probe-live.py:173` — `_write_catalog_file` leaves the `.model-config.*.tmp` file behind if the write fails (unlike `record_observed`, which unlinks it).

### 4. Dissent triage (DISS-C-003, DISS-C-007 — not defects)

- DISS-C-003 (redaction of `str(_exc)` in `models_failed[].message_redacted`): not a regression — every existing walk arm uses `str(_e)` the same way (cheval.py:2155, 2243, 2268, …) and the MODELINV emitter redacts at write time (`audit/modelinv.py:877`, `assert_no_secret_shapes_remain` :881). The test it cites does not exist.
- DISS-C-007 (`CompletionRequest.temperature` defaulting to None breaking other consumers): checked — within `loa_cheval` only the four updated adapters and `cursor_headless_adapter` (which ignores it) read `request.temperature`; cheval's dry-run prints it as JSON `null`. No further consumer found.

### 5. Complexity

`cmd_invoke` (already the largest function in cheval.py) grows by ~150 lines: the pre-flight gate block (1804-1862), the nested `_calibration_needed_exit` (1994-2037) and the per-hop I1 block (2070-2109). `SIMPLICITY[shrink]`: lift the pre-flight gate into a `_preflight_gate(head, cfg, request, …) -> (PreflightDecision | None, GateOutcome | None)` helper and the per-hop fit into `_fit_hop_budget(...)`; with the dead branch above, net: -45 lines possible.

---

## Cross-Model Observations

Adversarial dissent (`adversarial-review.json`, status `reviewed`): the configured primary chain (gpt-5.5-pro → gpt-5.5 → gemini-3.1-pro) failed for want of credentials; the companion voice `claude-headless` answered (`counted_as: sole_voice`). Eight findings, all `voice: claude-headless`:

| Id | Severity | Triage |
|----|----------|--------|
| DISS-C-001 retry shrink lost on the last attempt | BLOCKING | Confirmed by execution → Change 1 |
| DISS-C-002 `_ceiling_unverified` head-only flag applied per hop | BLOCKING | Behaviour confirmed; cited tests do not exist → Observation 2 (MEDIUM) |
| DISS-C-003 unredacted `str(_exc)` in the envelope | BLOCKING | Not a defect: emit-time redaction, same pattern as every existing arm |
| DISS-C-004 per-hop gate compares the heuristic against a count-derived bound | BLOCKING | Confirmed by reading → Change 2 |
| DISS-C-005 zero observation row / `observed -1` | ADVISORY | Confirmed → Observation 3 (LOW ×2) |
| DISS-C-006 long-context threshold ignores cache tokens | ADVISORY | Confirmed → Observation 2 (MEDIUM) |
| DISS-C-007 `temperature: None` reaching untouched consumers | ADVISORY | Checked, none found → not a defect |
| DISS-C-008 health probe false on 401/403/405 from `/models` | ADVISORY | Observation 3 (LOW) |

## Rejected dissent payloads

None — `metadata.rejected_summary` is empty and no `adversarial-rejected-review*.jsonl` sidecar was produced.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Reviewed — changes required | Changes 1–3 above |

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| "review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict" (sprint.md) | Pass | This file; every finding carries `head/<path>:<line>` |
| `reviewer.md` `## AC Verification` walkthrough | Not applicable | `pr/REVIEW-INSTRUCTIONS.md`: "There is no sprint plan, beads database, implementation report … skip any pre-flight step that needs them" |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (the retired `claude-3-haiku-20240307` probe id is gone; `tools/ceiling-probe-live.py` reads `ANTHROPIC_API_KEY` from the environment only)
- [x] Input validation at trust boundaries — `params.beta_headers` is allowlisted (`^[a-z0-9]+(-[a-z0-9]+)*-\d{4}-\d{2}-\d{2}$`, rejects header-injection shapes), `_long_context_fields` and `_pos_int` reject malformed catalog values, `load_observed` fails open on a malformed state file by design
- [x] Authentication/authorization unchanged (`_headers()` factors the existing `x-api-key` path)
- [x] No injection — `loa-status.sh` passes catalog values to jq via `--arg`; `write_catalog` edits lines by exact match
- [x] Dependencies — no new ones (`tiktoken`/`httpx` remain optional)
- [ ] Error messages — the stderr `_error_json` lines at cheval.py:2031 print the provider's message unredacted; this follows the pre-existing pattern (:2157, :2245) and the MODELINV envelope is redacted at emit, so noted, not counted

---

## Code Quality Summary

**Strengths:**
- `routing/ceiling.py` is a clean, pure policy module: every basis is named, decisions are frozen dataclasses, and the unit suite covers each rung (probed / derived / calibrated / observed / i1 / guard / legacy).
- The observed-bound store is append-only with atomic replace and a reducer, and the probe tool's `--write-catalog` edits the live yaml text without disturbing comments (verified on the real catalog).
- Flatline's per-voice budget derives from `generated-model-maps.sh` with the alias hop (`MODEL_IDS`) handled; the bats suite pins every mode.
- `wire_temperature` centralises the legacy-wire kill switch; the four adapters agree.

**Areas for Improvement:**
- Two estimates of the same prompt live in `cmd_invoke`; make `_walk_estimate` the only one (Change 2).
- Retry-layer control flow that depends on "there is a next iteration" needs an explicit guard (Change 1).
- Bridgebuilder has no alias knowledge of its own; either generate it or keep concrete ids in defaults (Change 3).
- Documentation: `multi-model-reference.md` and the Bridgebuilder `SKILL.md` table are updated; no CHANGELOG entry is part of the frozen diff (cannot verify whether the repository keeps one — noted, not counted).

---

## Next Steps

1. Fix Changes 1–3 (retry last-attempt path, per-hop estimate reuse, Bridgebuilder alias budget) and add the named regression tests.
2. Decide on Observations 1–2 (200K default, 64K Flatline cap vs 600 s, per-hop unverified flag, cache tokens in the premium threshold) — each is a one-line policy decision worth recording in the SDD.
3. Re-run `tests/test_ceiling_e2e.py` with at least one case that does not patch `invoke_with_retry`.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":5,"low":10},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T13:05:00Z"} -->
