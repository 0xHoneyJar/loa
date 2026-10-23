# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)

---

## Overall Assessment

The PR (cycle-127 sprint-251 operator decisions, 45 files) lands three operator decisions: (FR-1) the agy/`gemini-headless`
route becomes opt-in via `hounfour.headless.agy_opt_in`, read by one Python predicate plus parallel yq readers in four shell
planners and the Bridgebuilder TS pipeline; (FR-2) `claude-opus-5-5` gets `params.default_effort: high`, resolved once at
the cheval chokepoint with `effort_source` / `effort_effective` recorded in MODELINV; (FR-3) `tools/ceiling-probe-live.py`
gains a `--transport claude-headless` bisection and the catalog's Opus 5.5 ceiling is hand-written to 936,000 from a
Bedrock/CLI measurement, with the fr23b I2 clamp.

What is good: the opt-in predicate is strict (YAML boolean only, no env override, fail-closed) and the shell, TS and Python
readers agree; `build_headless_argv` is extracted without changing the adapter's argv (pinned by test); the catalog checksum
and the Bridgebuilder build manifest both match the head sources; the schema additions are enum-tight and tested; the
new test suites are thorough on the paths they cover.

What blocks: the regenerated Bridgebuilder budget for `claude-opus-5-5` (916,000) mixes units — a provider-measured
ceiling minus headroom, compared against a 4-chars-per-token estimate — which the PR's own catalog comment says
under-counts by ~1.8x, so Bridgebuilder now admits reviews that exceed the 1M window. And the opt-in refusal is a
`ConfigError` raised from inside cheval's chain walk, where ConfigError hard-aborts, so the "not planned, never a failed
voice" contract the PR documents does not hold for the one place every stock Google chain reaches the hop.

Process: the implementation report (`pr/PR.md`) carries no `## AC Verification` section, which the skill treats as an
automatic CHANGES_REQUIRED on its own. The verdict below rests on the two HIGH findings regardless.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Functionality — Bridgebuilder budget units

- **HIGH** (confidence: high) `head/.claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts:34` — `maxInput: 916000` is the measured ceiling 936,000 − 20,000 headroom, but `maxInput` is compared against Bridgebuilder's chars × 0.25 estimate; a diff admitted at ~900K estimate tokens measures ~1.4–1.6M on the wire and is rejected by the provider above the 1M window.
**File:** `head/.claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts:34` (also `head/.claude/skills/bridgebuilder-review/dist/core/truncation.generated.js:31`, `head/docs/migration/v2.0-model-generation-floor.md:309`)
**Issue:** The catalog ceiling is in provider-measured tokens (`measured_input_tokens: 972887`, `head/.claude/defaults/model-config.yaml:513`). The PR's own provenance comment states "the filler under-counts ~1.8x under the Opus 4.7+ tokenizer" (`head/.claude/defaults/model-config.yaml:497`). Bridgebuilder's truncation engine estimates at coefficient 0.25 tokens/char, the same class of estimate. The previous 160,000 budget sat ~5x below the 1M window, so estimate skew was absorbed; the new budget sits at the window edge with no margin. cheval's own pre-flight (`estimate_tokens`, tiktoken/len÷3.5) is also an estimate and will not pre-empt either, so the failure surfaces as a provider 400 on exactly the large diffs the budget exists to serve, after the spend.
**Why This Matters:** Every multi-model Bridgebuilder review of a large PR on `opus` fails or degrades (the chain walks to `claude-opus-5` whose 180K ceiling then pre-empts), and the docs now advertise the broken number.
**Required Fix:** Derive `maxInput` for calibrated entries in estimate units: e.g. `floor((effective_input_ceiling − 20000) / 1.8 / 1000) × 1000` using the probe's `tokenizer_ratio` (or a conservative constant), in `scripts/gen-bb-registry.ts`; regenerate `truncation.generated.ts` and `dist/`; add a test asserting `maxInput × worst_case_ratio + default_max_tokens ≤ context_window`; correct the migration note.
**Reference:** cycle-124 FR-3 / SDD §2.1 (BB truncates below cheval's gate); cycle-126 D-1.1b (provider verdict is not walked).

### 2. Error handling — opt-in refusal inside the chain walk

- **HIGH** (confidence: medium) `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:124-125` — `complete()` raises `AgyOptInRequiredError` (a `ConfigError`, INVALID_CONFIG, exit 2); cheval's chain walk surfaces ConfigError immediately ("STATIC misconfig … hard-abort"), so a stock Google chain that walks to its `gemini-headless` terminal after an upstream HTTP failure exits INVALID_CONFIG naming the opt-in, masking the real upstream error and counting as a failed voice.
**File:** `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:124-125`; contract text at `head/.claude/adapters/loa_cheval/types.py:503-510`
**Issue:** The docstring says `failure_class: opt_in_required` is "the machine-readable seam planners read as 'not planned', never as a failed voice". The planner-side filters (`_adv_agy_filter_chain` at `head/.claude/scripts/adversarial-review.sh:2356`, `isAgyRouted`, `_tertiary_routes_to_agy`) gate only explicitly configured hops or cli-only mode. Nothing teaches cheval's walk — where every catalog `fallback_chain` ending in `gemini-headless` is traversed — to skip the hop. Scenario: Flatline tertiary `gemini-3.1-pro` under `prefer-api` is planned (FTA-2), its HTTP hop gets a 429, cheval walks to `gemini-headless`, the adapter raises INVALID_CONFIG; `_companion_failure_class` maps exit 2 to `model_unavailable` (no `opt_in_required` class exists there). The operator is told to set `agy_opt_in` for a rate limit. On hosts with agy installed this is also a silent behaviour change: hops that completed yesterday abort today.
**Why This Matters:** The FR-1 acceptance claim ("never a failed voice") is false on the chain-walk path; upstream failure classes that drive retries, breakers and alerting are hidden behind a config refusal.
**Required Fix:** Either (a) in `cmd_invoke`'s walk, catch `AgyOptInRequiredError` (or any error with `failure_class == "opt_in_required"`), record the hop as skipped in `models_failed` with that class, keep the previous hop's exception as the reported failure, and `continue`; or (b) filter `gemini-headless` out of the resolved chain at plan time when `agy_opt_in_enabled()` is false. Add a test with a two-hop chain (HTTP failure → gemini-headless) asserting the exit code and MODELINV class are the upstream's.
**Reference:** #1095 safety constraint (operator config errors never masked) — cuts both ways here: the upstream error is the one being masked.

---

## Observations

### 1. Routing — CLI/Bedrock measurement written to the HTTP entry

- **MEDIUM** (confidence: medium) `head/.claude/defaults/model-config.yaml:494` — `effective_input_ceiling: 936000` on the `anthropic:claude-opus-5-5` HTTP entry comes from a claude-headless/Bedrock measurement; `_lookup_max_input_tokens("anthropic", …)` now returns 936,000 for direct-API callers, and a calibrated bound is by policy never lowered by observation (LSP-5), so accounts with low ITPM lose the 180K pre-emption and 429 on the wire.
**Suggestion:** Keep the HTTP entry at the policy cap until an `--transport api` probe runs, or carry a per-transport ceiling; at minimum gate on `account_limits.itpm` when known. The `reprobe_trigger` text already admits the gap.
**Benefit:** Pre-emption stays correct for the route the entry actually describes.

### 2. Configuration — opt-in predicate reads the System Zone catalog and re-parses per call

- **MEDIUM** (confidence: high) `head/.claude/adapters/loa_cheval/config/loader.py:122` — `agy_opt_in_enabled` deep-merges `load_system_defaults(root)` (the whole model-config.yaml) under the project config to read one key; a `headless.agy_opt_in: true` in a shipped or tampered System-Zone catalog would opt every project in without touching `.loa.config.yaml`, contradicting "an operator's deliberate choice". It also re-parses both YAML files on every `complete()`, `health_check()` and `validate_config()`.
**Suggestion:** Read `load_project_config(root)` alone (fail closed as now) and memoize per `project_root`.
**Benefit:** The opt-in lives only where the docs say it does; no repeated 1,400-line YAML parse per dispatch.

### 3. Tooling — probe subprocess environment is not the adapter's

- **MEDIUM** (confidence: medium) `head/tools/ceiling-probe-live.py:217` — `_run_capped` spawns the CLI with `{**os.environ, CLAUDE_CODE_DISABLE_AUTO_MEMORY: "1"}`, while the adapter uses `build_headless_subprocess_env()` which strips `ANTHROPIC_API_KEY` (`providers/base.py:779`). With a key in the shell the CLI may authenticate to the direct API while the record stamps `host_route`/`cli_model` as Bedrock from wrapper env vars, so the written `reprobe_trigger` and provenance describe a transport the measurement never used.
**Suggestion:** Build the env with `build_headless_subprocess_env()` plus the probe's additions; warn or refuse when `ANTHROPIC_API_KEY` is set with `--transport claude-headless`.
**Benefit:** "The probe measures the shape the adapter dispatches" (D-3.9) holds for the environment too.

### 4. Testing — assertions that now read the value under test

- **MEDIUM** (confidence: high) `head/.claude/adapters/tests/test_anthropic_catalog_floor.py:146-147` — for measured entries `expected = min(entry["effective_input_ceiling"], cw − dmt)`, so the equality reduces to `eic ≤ cw − dmt`, which line 148 already asserts; a wrong hand-edited ceiling passes. `head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py:459` skips permanently now that the live catalog is calibrated, so the live-catalog writer layout has no coverage (only the SYNTH copy).
**Suggestion:** For measured entries assert `eic == min(measured_input_tokens, cw − dmt)` and `probed_ceiling == eic`; replace the skip with a fixture that resets the live entry to its pre-probe shape.
**Benefit:** The FR-3.4 sweep keeps guarding the measured value, not just the invariant.

### 5. Complexity — SIMPLICITY[shrink]

- **MEDIUM** (confidence: high) `head/tools/ceiling-probe-live.py:632-848` — `_main_cli` is 216 lines with five nested closures (`_m`, `_size`, `current_ok`, `current_fail`, `step`, `next_target`) sharing `nonlocal` state; `write_catalog_operator_set` (`:402-480`) is ~80 lines of line-level YAML surgery. Both exceed the 50-line threshold without a justification marker.
**Suggestion:** Lift the bisection state into a small class or dataclass (`samples`, `ratio`, `spent_micro`) with `step`/`next_target` as methods; split `write_catalog_operator_set` into "replace scalars", "replace calibration block", "replace provenance comment".
**Benefit:** Testable units; the tolerance/re-anchor logic becomes readable without the closure graph. net: −40 lines possible.

### 6. Documentation / consistency

- **LOW** (confidence: high) `head/.claude/data/schemas/model-config-v3.schema.json:306` — `measured_input_tokens` is described as "the value written to probed_ceiling / effective_input_ceiling", which the fr23b clamp contradicts (shipped entry: 972,887 vs 936,000). Update the description to "the raw accepted size; probed/effective = min(this, context_window − default_max_tokens)".
- **LOW** (confidence: high) `head/.claude/defaults/model-config.yaml:494` — trailing comment `# cycle-124 FR-3 (SDD §2.1): see claude-fable-5-1` is stale on a calibrated value (the writer's `_set_scalar` preserves it); `head/.claude/adapters/cheval.py:2834` and `head/.claude/adapters/loa_cheval/audit/modelinv.py:498` still document `effort_source` as `caller | catalog | none` while the schema and `resolve_effort` emit a fourth value, `extra`.
- **LOW** (confidence: high) `head/.claude/defaults/model-config.yaml:509` — `method: probed_headless` on an entry the tool refused to write (its outcome was `partial`, per the comment at :496); the record is honest about `operator_set` but the method field claims the tool's method. Consider `method` absent or a note in `reprobe_trigger`.

### 7. Effort resolution edges

- **LOW** (confidence: medium) `head/.claude/adapters/cheval.py:909` — the "sets both" WARN fires for HTTP entries whose `extra.effort` no adapter reads, and when an explicit `--effort` makes both rungs moot; `:921` normalises (`strip().lower()`) the extra rung but not `params.default_effort`, so `"High"` is rejected in one and accepted in the other. Warn only for CLI entries without a caller value; normalise both.
- **LOW** (confidence: medium) `head/.claude/adapters/cheval.py:1519` — effort is resolved once against the primary entry and rides the single `CompletionRequest` through every fallback hop; a fallback's own `default_effort` is never applied, and `effort_effective` (`:2838-2845`) is recomputed for `final_model_id` with the primary's value. Low impact today (every live Anthropic hop accepts the five levels; other providers map to None), but worth a per-hop resolve or a comment in D-2.2.

---

## Cross-Model Observations

Two voices answered (`gpt-5.5-pro` primary via codex-headless, `claude-headless` companion; `voices_planned: 2`,
`voices_succeeded: 2`, `counted_as: independent_voice`). Twelve findings, two BLOCKING (companion). Triage:

| Dissent | Severity | Triage |
|---------|----------|--------|
| DISS-C-001 / DISS-002 — BB `maxInput` units | BLOCKING / ADVISORY | Confirmed; counted as Changes Required §1 |
| DISS-C-002 / DISS-001 — opt-in ConfigError in chain walk | BLOCKING / ADVISORY | Confirmed; counted as Changes Required §2 |
| DISS-C-005 — CLI measurement on HTTP entry | ADVISORY | Confirmed; Observation §1 |
| DISS-C-006 — predicate merges System defaults, re-parses | ADVISORY | Confirmed; Observation §2 |
| DISS-C-009 — probe env not the adapter's | ADVISORY | Confirmed (`build_headless_subprocess_env` strips the key); Observation §3 |
| DISS-C-007 — tautological floor test, permanent skip | ADVISORY | Confirmed; Observation §4 |
| DISS-C-010 — schema description vs clamp | ADVISORY | Confirmed; Observation §6 |
| DISS-C-008 — "both" WARN / normalisation | ADVISORY | Confirmed; Observation §7 |
| DISS-C-004 — primary effort rides every hop | ADVISORY | Partly confirmed; Observation §7 (LOW) |
| DISS-C-003 — `extra` undocumented / schema-invalid | ADVISORY | Premise refuted: the schema enum includes `extra` (`model-invoke-complete.payload.schema.json:915-922`); only the two code comments are stale — folded into Observation §6 |

## Rejected dissent payloads

None. `metadata.rejected_summary` is empty and the listed sidecar `adversarial-rejected-review.jsonl` holds zero rows.

---

## Previous Feedback Status

Not applicable — no prior `engineer-feedback.md` for sprint-1.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | The two HIGH defects above; `## AC Verification` section absent from the implementation report |

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

Sprint success criterion (sprint.md): "review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict".

| Criterion | Status | Notes |
|-----------|--------|-------|
| FR-1 agy route opt-in, default off, YAML boolean, no env override | Pass (with caveat) | Predicate strict and fail-closed (`loader.py:113-126`); all planner readers agree. Caveat: refusal inside cheval's chain walk is a hard abort, not "not planned" (Changes Required §2) |
| FR-2 `claude-opus-5-5` effort default `high`, resolved once, recorded in MODELINV | Pass | `resolve_effort` (`cheval.py:885-926`), schema enums, dry-run and in-process tests verified |
| FR-3 headless-transport probe, clean-only catalog write, I2 clamp | Pass | Writer and clamp tested on SYNTH; live-catalog path untested (Observation §4) |
| FR-3 catalog/budget propagation (BB `maxInput`, docs) | Fail | Unit mismatch (Changes Required §1) |
| `## AC Verification` walkthrough in the implementation report | Fail | Section absent from `pr/PR.md` |

Fast-Gate parity: the report names no formatter / type-check run; the dist and build manifest hashes match the head
sources, so the TS build ran, but `prettier --check` / `tsc --noEmit` / pytest / bats results are not stated. `FAST-GATE:`
state the self-check commands and results in the report.

---

## Security Checklist

- [x] No hardcoded secrets or credentials (adversarial secret scan applied 1 redaction to the diff; none in head sources on inspection)
- [x] Input validation at trust boundaries — opt-in is a strict boolean; `yq` reads are tag-checked; probe refuses non-positive ceilings and missing `context_window`
- [x] Authentication/authorization — opt-in documents the argv exposure (CWE-214) and defaults off; see Observation §2 for the System-Zone read
- [x] No SQL/XSS injection vectors (none applicable); probe prompt travels on stdin, cwd is a private temp dir
- [x] Dependencies secure — no new dependencies
- [x] Error messages don't leak sensitive data — `AgyOptInRequiredError.MESSAGE` names the key only

---

## Code Quality Summary

**Strengths:**
- One predicate, one argv builder, one chokepoint — the stated D-2.2 / D-3.9 shapes are real and tested.
- Fail-closed everywhere the opt-in is read; the string `"true"` case is covered in every reader.
- Catalog checksum and build manifest regenerated and matching.

**Areas for Improvement:**
- Unit discipline across catalog (measured tokens) and consumers (estimate tokens).
- Make "not planned" a property cheval's walk honours, not only the planners.
- Keep tests asserting the value, not the invariant alone, after a sweep.

---

## Next Steps

1. Fix the two Changes Required items; regenerate `truncation.generated.ts` and `dist/`.
2. Add the chain-walk test and the `maxInput × ratio` guard test; run pytest, bats, `tsc --noEmit`.
3. Add `## AC Verification` (every AC verbatim, `file:line` evidence) and the fast-gate results to the report.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":5,"low":5},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T17:17:27Z"} -->
