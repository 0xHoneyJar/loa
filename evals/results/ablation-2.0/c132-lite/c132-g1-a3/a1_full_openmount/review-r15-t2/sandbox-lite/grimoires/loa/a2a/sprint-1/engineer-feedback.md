All good

Sprint 1 has been reviewed and approved. Observations documented and non-blocking. See Observations below.

# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md (Task 1.1: the change in `pr/head.diff`)
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= `pr/PR.md`, per the brief)
**Change under review:** `pr/head.diff` — cycle-127 sprint-251 operator decisions (FR-1 agy opt-in gate, FR-2 Opus 5.5 catalog effort default, FR-3 headless ceiling probe + I2 clamp, FR-3.4 Opus 5.5 recalibration), 45 files

---

## Overall Assessment

The change does what the PR says and the pieces are consistent with each other. I verified mechanically, not from the report:

- `head/.claude/defaults/model-config.yaml.checksum:1` equals the SHA-256 of the head catalog (`17f75f07…`); the base pair also matched.
- The Bridgebuilder `dist/.build-manifest.json` hashes for `config.ts`, `multi-model-pipeline.ts` and `truncation.generated.ts` equal the SHA-256 of the head sources, and `dist/config.js` / `dist/core/multi-model-pipeline.js` carry the same logic as the `.ts`.
- The head catalog's `claude-opus-5-5.ceiling_calibration` block validates against `$defs.ceilingCalibration` of the v3 schema (`additionalProperties: false`), and `effective_input_ceiling == probed_ceiling == 936000 == context_window − default_max_tokens(128000→64000)`.
- `test_no_literal_opus55_ceiling_pins.py` runs green against `pr/head/` (10 passed).
- The catalog writer (`write_catalog_operator_set`) re-run against the head catalog with the adapter import stubbed produces a parseable entry with the same numbers (see Observation 10 for the comment drift it reveals).
- The `type` variable the new `adversarial-review.sh` hunk reads is in `main()` scope (`head/.claude/scripts/adversarial-review.sh:3756`); `_adv_hop_canon`, `_indent`, `_raw_model_entry`, `CONFIG_FILE` (loa-status) and `YQ_FLAVOUR`/`have_yq` (run-preflight) all exist; `loader.py` imports nothing from `loa_cheval.providers`, so the new `agy_headless_adapter → config.loader` import is not circular.

No critical or high finding. The mediums below are telemetry accuracy, a documented contract that does not reach the wire, a coverage regression by self-skip, planner-consistency gaps and the operator decision behind the 180K→936K recalibration. None breaks the primary paths (the opt-in refusal, the effort default, the probe, the planners), each has a small fix, and I am treating them as follow-ups rather than blockers. Rationale: the one-way rule does not force a verdict here; the sprint's success criterion is a merge verdict on the defects introduced, and none of these makes the shipped behaviour wrong for the default configuration.

Process note: the brief designates `pr/PR.md` as the implementation report, so the `## AC Verification` walkthrough the skill normally requires is absent by construction; I am not applying the automatic trigger for it (recorded as Observation 15).

[ASSUMPTION] Files not touched by the PR (`anthropic_adapter._effort_for_model`, `routing/ceiling.input_bound`, `headless_cli`, `providers/__init__`) are not in this workspace; where a finding depends on their behaviour I say so.

Karpathy check — `SIMPLICITY`: no over-engineering found; the four-rung resolver, the one argv builder shared by adapter and probe, and the yq one-liners are the minimum. `net: 0 lines possible. Lean already. Ship.` `SURGICAL`: the dist rebuild and the test sweeps are required by the catalog change. `GOAL-DRIVEN`: every new behaviour has a runnable check except the one noted in Observation 3.

**Verdict:** APPROVED

---

## Observations

### 1. Telemetry — the documented machine-readable refusal seam never reaches cheval's error output

- **MEDIUM** (confidence: high) `head/.claude/adapters/cheval.py:2552` — the chain walk's `except ChevalError` branch prints `_error_json(_e.code, str(_e), retryable=_e.retryable)` and records `error_class: "UNKNOWN"` (`head/.claude/adapters/cheval.py:2549`); the exception's `context` is never passed, so `failure_class: opt_in_required` set at `head/.claude/adapters/loa_cheval/types.py:516` is dropped on the floor.
**File:** `head/.claude/adapters/loa_cheval/types.py:507`
**Issue:** The docstring says `failure_class` "(also in `context`) is the machine-readable seam planners read as 'not planned', never as a failed voice", and `head/docs/migration/v2.0-model-generation-floor.md:289` repeats it. Nothing in cheval's CLI output carries it: `_error_json` accepts `**extra` (`head/.claude/adapters/cheval.py:142`) but only the `PROVIDER_DISCONNECT` path uses that (`_last_walk_extra`, line 2507). The in-process test `head/.claude/adapters/tests/test_agy_opt_in_gate.py:93` checks `err.context` only, never the emitted JSON. Every planner in this PR gates before dispatch by reading YAML, so no consumer is broken today, but the contract as written does not exist.
**Suggestion:** Pass `**_e.context` into `_error_json` in the `ChevalError` branch (and record `error_class` from it when present), or reword the docstring and migration doc to say the message names the key and the class is in-process only.
**Benefit:** A planner that does rely on the documented field (e.g. the dissent's `failure_class: auth|model_unavailable|…` classifier) could tell "not planned" from "failed" without string-matching.

### 2. Telemetry — `effort`/`effort_effective` are resolved against the primary entry and misreport a fallback CLI hop

- **MEDIUM** (confidence: medium) `head/.claude/adapters/cheval.py:933` — `_effort_on_wire` returns `None` as soon as `effort is None`. Scenario: primary `claude-opus-5` (no `default_effort`) → `resolve_effort` yields `(None, "none")`; the chain falls to `anthropic:claude-headless` whose `extra.effort: low` is set; the headless adapter's own `_resolve_effort` still puts `--effort low` on argv (pinned by `test_cli_adapter_extra_effort_stays_below_the_chokepoint_value`), but the MODELINV envelope at `head/.claude/adapters/cheval.py:2838` omits `effort` and `effort_effective` and says `effort_source: none`.
**Suggestion:** When the answering hop is a CLI entry and `_effort` is `None`, re-run `resolve_effort` against that hop's entry for the `effort_effective` value (or read the request the adapter actually built).
**Benefit:** The new field's stated purpose, "the wire value on the hop that answered", holds across fallbacks. (The dissent's DISS-001 and DISS-C-002 raise the same point; DISS-C-002's second half, that a fallback CLI hop inherits the primary's catalog default, is the documented D-2.2 design and not a defect.)

### 3. Testing — the only writer-output-vs-schema check now self-skips permanently

- **MEDIUM** (confidence: high) `head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py:459` — `test_write_operator_set_changes_only_the_entry_and_replaces_the_shortcut` calls `pytest.skip` unless the live catalog still carries the `# loa:shortcut: Opus 5's measured bound` comment; the head catalog no longer does (verified by grep), so the test skips on every run from now on.
**File:** `head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py:500`
**Issue:** That test is the only place the writer's `ceiling_calibration` output is validated with `jsonschema` against `$defs.ceilingCalibration` and fed through `routing.ceiling.input_bound`. The remaining writer tests run on the `SYNTH` fixture and never validate against the schema; the bats `V3-add (c127)` test validates a hand-written example, not the writer's output. Combined with `head/.claude/adapters/tests/test_anthropic_catalog_floor.py:146` and `:299`, where a measured entry's expected value is derived from the entry itself, the calibrated Opus 5.5 entry is now checked only for the I2 invariant (the dissent's DISS-C-007 says the same).
**Suggestion:** Run the schema/`input_bound` assertions on the `SYNTH` write (no skip), and keep one assertion that the live calibrated entry's block validates against the schema.
**Benefit:** A future hand-edit of the calibrated block (missing `method`, wrong `transport`) fails a test instead of passing silently.

### 4. Operator decision — the 180K→936K Opus 5.5 bound is written as calibrated from a `partial` probe on a different transport

- **MEDIUM** (confidence: medium) `head/.claude/defaults/model-config.yaml:494` — `effective_input_ceiling: 936000` and `source: operator_set` (`:504`) were hand-written from a probe whose own outcome was `partial` (`:496`, the $20 cap stopped the bisection; bracket 972,887 accepted / ~1,065,182 rejected, far wider than the 16K tolerance), measured through Bedrock via the CLI (`cli_model: global.anthropic.claude-opus-5-5`) and applied to the `anthropic` HTTP entry whose `account_limits.itpm` is `null`. The tool itself refuses to write anything but a `clean` outcome (`head/tools/ceiling-probe-live.py:361`).
**Issue:** Per the PR's own LSP-5 comment (`head/tests/unit/loa-status-providers.bats:66-68`), a calibrated entry's bound is never lowered by observed 429/context verdicts. If the direct-API account's input limit is below 936K, every large `opus` call now 429s and walks the chain (the first two fallbacks, `claude-opus-5` and `claude-sonnet-5`, still carry 180K), and the observed-ceiling store cannot correct it. The per-call input cost ceiling for the dissent and Bridgebuilder rises from 160K to 916K tokens (`head/.claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts:34`). The comment is honest about all of this and names a maintainer delegation, but `grimoires/loa/NOTES.md` in this workspace has no Decision Log row and the referenced record `grimoires/loa/reports/2026-10-07-opus-5-5-ceiling-probe-cli.json` is not in the PR. Under the skill's task-kind rule, an operator decision without a DEC row is a MEDIUM.
**Suggestion:** Add the DEC row (what was measured, why 936K, the API-transport re-probe trigger) and consider keeping `ceiling_calibration.source: operator_set` but allowing a `PROVIDER_CONTEXT_LIMIT`/`RATE_LIMIT` observation to lower a calibrated bound until the API-transport probe lands.
**Benefit:** The decision is auditable, and a wrong bound self-corrects instead of failing every large call.

### 5. Planner consistency — the dissent's agy filter ignores headless mode; flatline and Bridgebuilder do not

- **MEDIUM** (confidence: medium) `head/.claude/scripts/adversarial-review.sh:2360` — `_adv_agy_filter_chain` drops only hops whose canonical name is `gemini-headless`. `head/.claude/scripts/flatline-orchestrator.sh:529` and `head/.claude/skills/bridgebuilder-review/resources/config.ts:182` also treat any Google model under `hounfour.headless.mode: cli-only` as agy-routed. This repository's own config is `cli-only` (`.loa.config.yaml:114`) and the default dissent chain walked in my run was `gpt-5.5-pro gpt-5.5 gemini-3.1-pro claude-headless`: an operator `companion_chain` naming `gemini-3.1-pro` under `cli-only` is planned, dispatched, refused by cheval with INVALID_CONFIG and recorded as a failed companion (a dropped voice for an audit), while the same model as a flatline tertiary is "not planned".
**Suggestion:** Give `_adv_agy_filter_chain` the same mode rule (`_adv_family_of` = google and mode `cli-only` ⇒ drop), or document that the dissent gates by hop name only. [ASSUMPTION] that cheval routes a Google API id to the agy hop under `cli-only`, as the flatline FTA-2 and TS tests assert.
**Benefit:** "Not planned" means the same thing in every planner.

### 6. Robustness — the fail-closed predicate evaluates the project-root walk outside its `try`

- **MEDIUM** (confidence: medium) `head/.claude/adapters/loa_cheval/config/loader.py:120` — `root = project_root or _find_project_root()` runs before the `try` at `:121`; `_find_project_root` calls `Path.cwd()`, which raises `FileNotFoundError` when the cwd has been removed, a case this codebase already handles elsewhere (`cwd_vanished` imported at `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:65`). The exception escapes `complete()`/`health_check()`/`validate_config()` and lands in the chain walk's catch-all as `API_ERROR, retryable: true` instead of the documented refusal or `False`.
**Issue:** Also, `:122` parses both YAML layers and deep-merges the whole System catalog on every call, and the adapter calls it in `complete()` (`:124`), `validate_config()` (`:261`) and `health_check()` (`:295`); a second, smaller point from the dissent (DISS-C-003).
**Suggestion:** Move the root resolution inside the `try`; memoise per (root, mtime) or read `.loa.config.yaml` alone (the System catalog has no `headless:` key, verified by grep, and the bash/TS readers only read the project file).
**Benefit:** The gate fails closed as documented in every path, and an agy dispatch does not re-read the 500-line catalog.

### 7. Chain behaviour — a non-terminal, opted-out agy hop aborts the whole walk

- **MEDIUM** (confidence: medium) `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:125` — `AgyOptInRequiredError` is a `ConfigError`; at `head/.claude/adapters/cheval.py:2544` any `ChevalError` from a hop "surfaces immediately" and returns. For the stock chains agy is terminal, so this is harmless. For a chain where the agy hop is not last (an operator `prefer-cli` Google chain with a keyed `gemini-api` hop behind it), a host with `agy` installed but no opt-in now exits INVALID_CONFIG at the agy hop although the next hop would have answered (before the PR that host dispatched agy). [ASSUMPTION] about chain ordering under `prefer-cli`. Raised by the dissent as DISS-C-006.
**Suggestion:** Either treat `opt_in_required` as walkable (skip the hop, record `not_planned`) in the chain walk, or state in the docstring that the refusal is non-walkable and stock chains keep agy terminal.
**Benefit:** Operators can keep agy in a chain without opting in and still get the HTTP voice.

### 8. Comments — three sources still say `effort_source` has three values

- **LOW** (confidence: high) `head/.claude/adapters/loa_cheval/audit/modelinv.py:498` and `head/.claude/adapters/cheval.py:2834` say `caller | catalog | none`; the resolver (`head/.claude/adapters/cheval.py:921`) and both schemas (`head/.claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json:755-762`) have four, including `extra`. Fix the two comments.

### 9. Validation asymmetry — `default_effort: null` warns, and the two rungs normalise differently

- **LOW** (confidence: high) `head/.claude/adapters/cheval.py:914-915` — `"default_effort" in params` is true for an explicit `null`, so `_valid_effort(None)` logs "`None` is not one of low, medium, …" once per process; the natural spelling for "no default" is a warning. The `extra` rung lower-cases and strips (`:924`) while the catalog rung is verbatim (an upper-cased `high` warns). Treat `None` as absent; the strict casing is consistent with the schema enum and can stay. (Dissent DISS-C-005.)

### 10. Catalog provenance comment drifts from what the writer produces

- **LOW** (confidence: high) `head/.claude/defaults/model-config.yaml:495` — the hand-written provenance line lacks the clamp note the second commit's writer emits (`head/tools/ceiling-probe-live.py:465`: "; written clamped to 936000 (I2: …) from the measured 972887"). Re-running the writer on the head catalog rewrites line 495 (verified by running `write_catalog_operator_set` on the head text). Either run the writer once more or accept the drift knowingly.

### 11. Status surface — the opt-in note is shown on hosts without `agy`

- **LOW** (confidence: high) `head/.claude/scripts/loa-status.sh:805` — `_provider_hop_note google` prints `agy: opt-in (disabled; …)` whenever the opt-in is off, regardless of whether `agy` is on PATH; after opting in, such a host shows `hop -`. Readers may infer that opting in would yield a hop. Check `command -v agy` before printing the note, or word it "agy: opt-in (disabled; …; not installed)".

### 12. Preflight — a stage whose only voice is a gated agy hop fails with the wrong reason text

- **LOW** (confidence: high) `head/.claude/scripts/run-preflight.sh:204` — the FAIL detail says "no credential present and no CLI hop on PATH" while the real cause (appended at `:208`) is the opt-in. Pinned by PF-AGY as written; the wording should branch when `p3_optin` is non-empty.

### 13. Probe cost — re-anchoring the top after a parsed size rejection spends a second top-size attempt

- **LOW** (confidence: medium) `head/tools/ceiling-probe-live.py:740` — when the blind first step is a size rejection whose parsed count is more than `tol` from `hi`, `next_target` returns `hi` again (now scaled), which is almost always rejected again; the worst-case step at the catalog price is charged twice before the bisection starts. Skip the re-anchor when the first sample is a rejection.

### 14. Emit-time lazy import inside the audit emit

- **LOW** (confidence: medium) `head/.claude/adapters/cheval.py:938` — `_effort_on_wire` imports the private `anthropic_adapter._effort_for_model` lazily and is evaluated inside the `_emit_modelinv(...)` argument list at `:2838`, after spend. The emit is wrapped fail-soft (`try` at `:2814`, `except Exception` at `:2873`), so a mapping failure loses the MODELINV record rather than the invoke. Compute `effort_effective` before the emit and default to `None` on error. (Dissent DISS-C-004, downgraded for the fail-soft wrapper.)

### 15. Process — no `## AC Verification` walkthrough in the implementation report

- **LOW** (confidence: high) `grimoires/loa/a2a/sprint-1/reviewer.md:1` — the report is the PR description by the brief's construction and carries no AC walkthrough, no self-check evidence (formatter/type-checker, `FAST-GATE:` unverifiable here), and no test-run output. I ran what the workspace allows (see Overall Assessment); the pytest/bats/node suites that import the untouched package tree could not be executed in this frozen copy.

---

## Cross-Model Observations

Dissent: `grimoires/loa/a2a/sprint-1/adversarial-review.json` — status `reviewed`, two voices (`codex-headless` answered for the primary `gpt-5.5-pro` chain; companion `claude-headless`, `counted_as: independent_voice`), `verdict_quality.status: APPROVED`, 8 findings, `hallucination_filter.downgraded: 0`. Triage:

- **DISS-C-001 (BLOCKING, companion)** — "if the trajectory payload schema encodes a three-value `effort_source` enum, every `extra` event is out-of-enum". Not a defect: `head/.claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json:755-762` enumerates `caller, catalog, extra, none`, and `test_modelinv_schema_declares_effort_source` pins exactly that. Only the two comments are stale → Observation 8 (LOW). Not counted.
- **DISS-001 / DISS-C-002 (ADVISORY)** — `effort_effective` under-report on a fallback CLI hop → Observation 2 (MEDIUM). The "over-apply" half of DISS-C-002 is the documented D-2.2 design.
- **DISS-C-003 (ADVISORY)** — root walk outside the `try`, per-call catalog parse → Observation 6 (MEDIUM).
- **DISS-C-004 (ADVISORY)** — emit-time lazy import → Observation 14 (LOW; the emit is fail-soft).
- **DISS-C-005 (ADVISORY)** — rung validation asymmetry → Observation 9 (LOW).
- **DISS-C-006 (ADVISORY)** — non-terminal agy hop aborts the walk → Observation 7 (MEDIUM).
- **DISS-C-007 (ADVISORY)** — tautological calibrated-entry checks and the permanent skip → Observation 3 (MEDIUM).

## Rejected dissent payloads

- None — `metadata.rejected_summary` is `[]` and the sidecar `adversarial-rejected-review.jsonl` is empty (0 bytes); no payload was dropped by the schema filter.

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| Review the pull request | Pass | Every hunk of the 3,847-line diff read; sourcemap hunks skipped; mechanical checks listed in Overall Assessment |
| Report each defect with file and line | Pass | 15 observations above, each cited `head/<path>:<line>` |
| Give a merge verdict | Pass | APPROVED (0 critical, 0 high; mediums are non-blocking follow-ups) |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (probe fake uses placeholder keys; `_dry` strips `ANTHROPIC_API_KEY`)
- [x] Input validation at trust boundaries: `agy_opt_in` requires a YAML boolean in all five readers; `default_effort` is enum-validated in the schema and tolerated at runtime; `write_catalog_operator_set` rejects non-positive/boolean ceilings and unknown models
- [x] The argv-prompt exposure (CWE-214, information exposure through process environment/command line) is now behind an explicit operator opt-in with the risk named in `.loa.config.yaml.example` and the migration doc — the PR's security goal
- [x] No env override for the opt-in (tested in Python, bash and TS)
- [x] Error messages do not leak secrets (the refusal names the key, not a value)
- [ ] Not verifiable here: that cheval honours `AGY_HEADLESS_BIN` only from trusted env (pre-existing)

---

## Code Quality Summary

**Strengths:**
- One argv builder shared by the adapter and the probe (D-3.9), so the probe measures the shape that is dispatched.
- Five independent readers of the opt-in agree on "YAML boolean true only" and each has a negative test for the string `"true"`.
- The probe's needle verification, measured-token bisection and I2 clamp are each covered by a fake-CLI test with a zero-live-spend guard.
- Honest provenance in the catalog for an operator-set value.

**Areas for Improvement:**
- Telemetry fields should be computed from the hop that answered, not the primary (Obs. 2).
- A documented machine-readable field should be emitted where documented (Obs. 1).
- Avoid tests that skip forever once the fixture they depend on changes (Obs. 3).

---

## Next Steps

1. File follow-ups for Observations 1–7 (one-line fixes for 1, 6, 8; a DEC row for 4).
2. `/audit-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":7,"low":8},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T00:40:00Z"} -->
