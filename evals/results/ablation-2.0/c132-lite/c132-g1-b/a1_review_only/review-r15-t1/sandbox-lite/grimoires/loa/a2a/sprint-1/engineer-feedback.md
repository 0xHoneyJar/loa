# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, pr/PR.md)
**Change under review:** pr/head.diff (45 files; cycle-127 sprint-251: agy opt-in, Opus 5.5 effort default, headless ceiling probe + fr23b I2 clamp)

---

## Overall Assessment

The three operator decisions are implemented cleanly at the unit level and are well tested: the agy gate refuses before any discovery or spawn (head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:124), the effort chokepoint is one function with a recorded source (head/.claude/adapters/cheval.py:885), and the headless probe writes the catalog only on a clean outcome with the I2 clamp (head/tools/ceiling-probe-live.py:443). Syntax checks on every touched Python, shell and JSON file pass, the YAML catalog parses, and its checksum file matches the new content. The two-voice adversarial dissent (gpt-5.5-pro primary, claude-headless companion, both succeeded, zero rejected payloads) returned nine advisory findings; four of them confirm concerns raised here and one (DISS-C-004) is refuted below.

What blocks the merge is the catalog change itself. A bound measured once through the Bedrock CLI route, by a probe run whose own outcome was `partial`, is written as the authoritative, observation-proof `effective_input_ceiling` of the Anthropic HTTP entry, which is the one route the probe never touched. The ceiling policy introduced in cycle-126 then stops protecting that route and cannot self-correct. Around it sit several medium defects: the fr23b clamp was added to only one of the two catalog writers, the opt-in predicate exists in six divergent copies that disagree on what "agy-routed" means, cheval's own chain walk still turns the gated hop into a fatal INVALID_CONFIG that masks the real failure, and the probe does not strip the API key the adapter strips.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Ceiling calibration: a foreign-transport measurement frozen as the HTTP route's bound

- **HIGH** (confidence: medium) `head/.claude/defaults/model-config.yaml:494` — the Anthropic HTTP entry for `claude-opus-5-5` now carries `effective_input_ceiling: 936000` with `source: operator_set` and a `calibrated_at` (lines 502-513), so `routing/ceiling.input_bound` reports `basis: calibrated` and, per the PR's own test comment (`head/tests/unit/loa-status-providers.bats:69`, "calibrated: the measured bound, observations never lower it"), a `PROVIDER_CONTEXT_LIMIT` observed on the HTTP route can no longer tighten it. The value was measured through `claude-headless` on Bedrock (`cli_model: global.anthropic.claude-opus-5-5`), a transport that takes no bound from this module at all, and the HTTP route was never measured.
**File:** `head/.claude/defaults/model-config.yaml:494` (also 502, 504, 509, 513)
**Issue:** Failure scenario: an operator with `ANTHROPIC_API_KEY` dispatches `opus` over HTTP with an input between the account's real HTTP limit and 936K. Before this PR cheval preempted at 180K and an observed provider rejection lowered the bound. After it, every such request is sent, the provider rejects it with a context-limit 400, the observation store records it, and `input_bound` ignores the observation because the entry is calibrated. The chain then walks on and the review or audit that needed the context fails on every retry until a human re-probes. The provenance is also wrong on its face: the catalog comment at line 495-500 says the tool's outcome was `partial` and the tool refuses to write on partial, yet the entry is stamped `method: probed_headless` and `measured_input_tokens: 972887`, exactly the shape a clean tool write would produce. `test_anthropic_catalog_floor._measured` (`head/.claude/adapters/tests/test_anthropic_catalog_floor.py:135`) then accepts the entry as authoritative without checking that the measurement transport matches the entry's own transport (dissent DISS-C-006 reaches the same conclusion independently).
**Why This Matters:** This reverses the protective direction of the cycle-126 ceiling policy for the most common route and makes a wrong calibration sticky. The docs (`head/docs/migration/v2.0-model-generation-floor.md:302-306`) advertise "cheval now preempts above 936,000 instead of 180,000 for `opus`", so downstream mounts inherit the exposure with the catalog.
**Required Fix:** Pick one and test it: (a) record the calibration's transport on the entry (the new `ceiling_calibration.transport` field is already there) and have `input_bound` let observations tighten a bound whose calibration transport differs from the dispatching route, keeping the never-lower rule only for same-route calibrations; or (b) leave the HTTP entry at `conservative_default` until `--transport api` measures it, and carry the Bedrock measurement as a route-scoped bound. In both cases do not stamp a hand-written value `method: probed_headless`; keep `operator_set` with the measurement recorded under a field that says it was transcribed from a partial record. Add a test that an observation below a foreign-transport calibration lowers the effective bound.
**Reference:** cycle-126 FR-1.1 observed-bound semantics; CWE-1188 (insecure default) by analogy: a protective default replaced by an unverified one.

---

## Observations

### 1. Catalog writers (medium)

- **MEDIUM** (confidence: high) `head/tools/ceiling-probe-live.py:316` — the API-transport writer still sets `effective_input_ceiling` to the raw `int(ceiling)`; the fr23b I2 clamp lives only in `write_catalog_operator_set` (`head/tools/ceiling-probe-live.py:441-443`). Concrete input: `--transport api --write-catalog` on a 1M-window entry that accepts 972,887 tokens writes 972887, and `test_ceiling_is_the_computed_value_per_entry` fails because 972887 + 64000 exceeds the window. Runtime is saved by the I1 clamp in `input_bound`, so the damage is a red catalog test and a misleading entry. The API writer also never updates `probed_ceiling` or writes `method: probed_api`, so the new schema enum value `probed_api` is dead. The probe docstring at `head/tools/ceiling-probe-live.py:45` still says the CLI write is "raw".
**Suggestion:** Route both writers through `i2_clamped`, write `method`/`transport` from both, and correct the docstring.
**Benefit:** One invariant, enforced in one place, for both transports.

- **MEDIUM** (confidence: medium) `head/tools/ceiling-probe-live.py:217` — `_run_capped` passes the whole parent environment to the CLI. The adapter the probe claims to mirror (SDD D-3.9) dispatches through `build_headless_subprocess_env()`, which strips `ANTHROPIC_API_KEY` and the other provider credentials. Claude Code prefers an exported `ANTHROPIC_API_KEY` unless the Bedrock switch is set, and the API transport requires that key, so an operator who has it exported and runs `--transport claude-headless` without the Bedrock wrapper measures and bills the direct API route while the record and the catalog comment say `host_route: claude CLI default auth` or `bedrock`. The test fixture deletes the key (`head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py:131-134`), so the suite never exercises this path (dissent DISS-C-007).
**Suggestion:** Build the env with `build_headless_subprocess_env()` plus the auto-memory switch, and record which auth route the CLI actually used.
**Benefit:** The probe measures the shape the adapter dispatches, which is the whole point of D-3.9.

### 2. The opt-in predicate: six copies, two definitions of "agy-routed" (medium)

- **MEDIUM** (confidence: high) `head/.claude/scripts/adversarial-review.sh:2360` — the dissent's companion filter drops only hops whose canonical id is the literal `gemini-headless`. Flatline (`head/.claude/scripts/flatline-orchestrator.sh:529-538`) and Bridgebuilder (`head/.claude/skills/bridgebuilder-review/resources/config.ts:180-182`) also gate any Google model when `hounfour.headless.mode` is `cli-only`, which is correct: the chain resolver strips HTTP entries under `cli-only`, so a Google model dispatches through `gemini-headless`. `run-preflight.sh` (`head/.claude/scripts/run-preflight.sh:153` and `:190`) and `loa-status.sh` share the dissent's narrower reading. Failure scenario: `hounfour.headless.mode: cli-only`, opt-in off, operator `companion_chain.anthropic: [gemini-3.1-pro]`. The dissent plans the hop, dispatches it, cheval refuses with INVALID_CONFIG, `_companion_failure_class` maps exit 2 to `model_unavailable`, and the voice is recorded as dropped (DEGRADED for an audit) while Flatline and Bridgebuilder treat the identical config as "not planned", contradicting the contract written in `head/.loa.config.yaml.example:742-750`. `SIMPLICITY[shrink]`: the PR title promises "one Python predicate", but the predicate is re-implemented in `head/.claude/adapters/loa_cheval/config/loader.py:113`, `adversarial-review.sh:2350`, `flatline-orchestrator.sh:522`, `loa-status.sh:798`, `run-preflight.sh:154` and `config.ts:159`, with two different yq flavours and one PyYAML reader.
**Suggestion:** Expose the decision once (a `cheval --print-config` field or a `lib/agy-gate.sh` sourced by all four scripts and shelled out to by Bridgebuilder) that returns both "opted in" and "this model is agy-routed under the effective mode", and make the dissent and preflight consume it. net: -60 lines possible.
**Benefit:** One truth for planners; the inconsistency class above cannot recur.

- **MEDIUM** (confidence: high) `head/.claude/adapters/cheval.py:2544` — the chain walk's `except ChevalError` arm surfaces any non-walkable typed error immediately, so `AgyOptInRequiredError` raised at a non-first hop aborts the whole invocation with exit 2 INVALID_CONFIG and the opt-in message, and `models_failed` records the hop with `error_class: UNKNOWN`. Concrete input: stock Google chain `gemini-3.1-pro → google:gemini-headless` (`head/.claude/defaults/model-config.yaml:216`), opt-in off, HTTP primary fails walkably (empty content or 429). The caller sees a configuration error about a route that was disabled by default, the primary's real failure class is lost, and the dissent's `_companion_failure_class` reads it as `model_unavailable`. Because the gate is now off by default, this happens on every host, not only agy-less ones, whenever a Google chain reaches its terminal (dissent DISS-001 and DISS-C-003 agree). The "not planned, never a failed voice" seam exists only in the external planners; cheval has no such seam.
**Suggestion:** Drop gated `gemini-headless` hops at chain-resolution time (chain_resolver) and record them in the MODELINV envelope as `not_planned: opt_in_required`, so the walk never reaches them and the last real failure is what surfaces.
**Benefit:** The documented contract holds at the one layer every planner depends on.

- **MEDIUM** (speculative, confidence: low) `head/.claude/adapters/loa_cheval/config/loader.py:120` — the gate reads `.loa.config.yaml` from the project root found by walking up from the process cwd. When `/review-sprint` runs the dissent on a checked-out PR branch, that file is the one in the reviewed tree, so a PR that adds `hounfour.headless.agy_opt_in: true` opts the reviewer's host in and puts the redacted diff on `agy`'s argv (dissent DISS-C-001). This is the same trust boundary every other `.loa.config.yaml` key already crosses, but FR-1's security rationale is specifically that only the operator consents.
**Suggestion:** Document it, or read the opt-in from the operator's checked-in config at the default branch rather than the working tree, if that distinction exists in the dispatch path.

### 3. Complexity and process (medium)

- **MEDIUM** (confidence: high) `head/tools/ceiling-probe-live.py:632` — `_main_cli` is about 215 lines with five nested closures that share `ratio`, `spent_micro` and `samples` through `nonlocal`; `write_catalog_operator_set` (`:402`) is about 80 lines. Both exceed the 50-line threshold without a justification comment. The bisection logic (`step`, `next_target`, re-anchoring) is where the fr23b tokenizer-ratio bugs lived, and it is testable only end to end through the fake CLI. `SIMPLICITY[shrink]`: lift `step` and `next_target` to module functions taking an explicit state object.

- **MEDIUM** (confidence: high) `grimoires/loa/a2a/sprint-1/reviewer.md:1` — the implementation report is the PR description and carries no `## AC Verification` walkthrough, no test-run evidence, and no formatter or type-check evidence. `FAST-GATE:` the new TypeScript (`config.ts`, `multi-model-pipeline.ts`, the node test) and the regenerated `dist/` have no recorded `tsc --noEmit`, `npm test` or `prettier --check` run; the five new pytest and three new bats files have no recorded run. Per the review brief this does not by itself decide the verdict here, but the next report must include it.

### 4. Low

- **LOW** (confidence: high) `head/.claude/data/schemas/model-config-v3.schema.json:306` — `measured_input_tokens` is described as "the value written to probed_ceiling / effective_input_ceiling"; after the clamp the live catalog has 972887 there and 936000 in both ceilings. `head/docs/migration/v2.0-model-generation-floor.md:297` ("to the measured bound") and the probe docstring at `:45` have the same staleness. `head/.claude/adapters/cheval.py:2834` and `head/.claude/adapters/loa_cheval/audit/modelinv.py:498` list `effort_source` as "caller | catalog | none" while the resolver and schema emit four values including `extra` (the schema itself is correct, so dissent DISS-C-005's validation concern is refuted). The retained inline comment at `head/.claude/defaults/model-config.yaml:494`, "see claude-fable-5-1", now points at an entry that has nothing to do with this value.
- **LOW** (confidence: high) `head/.claude/adapters/cheval.py:908` — the "sets both params.default_effort and extra.effort" WARN fires even when an explicit `--effort` makes both rungs moot; move it under the `explicit` check.
- **LOW** (confidence: medium) `head/.claude/adapters/loa_cheval/config/loader.py:120` — `_find_project_root()` sits outside the fail-closed `try`, so a `Path.cwd()` failure (deleted cwd) or a `PermissionError` during the upward walk escapes `complete()` as a raw exception rather than reading as off (dissent DISS-C-002).
- **LOW** (confidence: high) `head/.claude/adapters/loa_cheval/config/loader.py:126` — the Python gate reads through PyYAML (YAML 1.1), so `agy_opt_in: yes` or `on` is boolean `True` and opts the adapter in, while every yq-based planner (YAML 1.2) reads those as strings and plans no voice. Fail-safe direction only, but the test matrix in `head/.claude/adapters/tests/test_agy_opt_in_gate.py:48-56` never covers `yes`/`on` (dissent DISS-C-008).
- **LOW** (confidence: high) `head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py:459` — the only writer test against the live catalog is now permanently skipped on this tree because the catalog is already calibrated; the writer is covered by the synthetic block only. Replace the skip with a copy of the pre-probe block as a fixture.
- **LOW** (confidence: high) `head/.claude/scripts/loa-status.sh:865` — the 50-character opt-in note is printed through a `%-7s` hop column, breaking the Providers table alignment; `head/.claude/scripts/run-preflight.sh:190` skips the gated voice but the FAIL detail at `:204` still reads "no credential present and no CLI hop on PATH" when the only cause is the opt-in.
- **LOW** (confidence: high) `head/.claude/scripts/adversarial-review.sh:4085` — introduces the companion `reason: opt_in_required`, but the companion-voice contract text in `.claude/skills/reviewing-code/resources/ADVERSARIAL-REVIEW.md` and its byte-identical twin under `auditing-security` (kept in lockstep by CMP-138) still enumerate only `no_workdir`, `no_route`, `prompt_copy_failed`.

---

## Cross-Model Observations

Dissent envelope: `grimoires/loa/a2a/sprint-1/adversarial-review.json`, status `reviewed`, primary gpt-5.5-pro, companion claude-headless (`counted_as: independent_voice`), nine advisory findings, none blocking. Triage:

| Finding | Voice | Triage |
|---------|-------|--------|
| DISS-001 chain walk turns the gated hop into fatal INVALID_CONFIG | gpt-5.5-pro | Confirmed; folded into Observations §2 (cheval.py:2544) |
| DISS-C-001 reviewed PR's `.loa.config.yaml` can flip the gate on the reviewer host | claude-headless | Plausible, unverified; recorded as speculative medium in §2 |
| DISS-C-002 `_find_project_root()` outside the fail-closed try | claude-headless | Confirmed; low |
| DISS-C-003 opt-in refusal masks the primary's failure class on every host | claude-headless | Confirmed; folded into Observations §2 |
| DISS-C-004 `_is_cli_entry` keys absent from model entries, `extra` rung dead | claude-headless | Refuted: the `claude-headless` model entry carries `auth_type: headless` and `kind: cli` at model level (`head/.claude/defaults/model-config.yaml:914-916`), and the in-process test pins the rung |
| DISS-C-005 schema may enumerate three `effort_source` values | claude-headless | Refuted for the schema (it lists four); the stale comments are recorded as low |
| DISS-C-006 `_measured` accepts a foreign-transport calibration as the HTTP bound | claude-headless | Confirmed; supports Changes Required §1 |
| DISS-C-007 probe inherits `ANTHROPIC_API_KEY`, measures and bills a different route than recorded | claude-headless | Confirmed against `build_headless_subprocess_env`; raised to medium in §1 |
| DISS-C-008 PyYAML 1.1 `yes`/`on` accepted by cheval, strings for yq planners | claude-headless | Confirmed; low |

## Rejected dissent payloads

No payloads were rejected: the envelope's `rejected_summary` is empty and the listed sidecar `adversarial-rejected-review.jsonl` has zero rows.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | The catalog calibration in Changes Required §1 must be re-scoped or made observation-correctable before merge |

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| FR-1 agy route opt-in, default off, YAML boolean, no env override, one Python predicate | Partial | Adapter gate and tests are correct; "one predicate" is not met (six copies, two definitions); cheval's chain walk still fails the hop rather than not planning it |
| FR-2 Opus 5.5 catalog effort default resolved once, recorded in MODELINV, dry-run reports it | Pass | `resolve_effort`, schema, dry-run and in-process tests all line up |
| FR-3 headless probe transport, clean-only catalog write with provenance | Partial | CLI writer correct; API writer unclamped; probe env diverges from the adapter |
| fr23b clamp: written = min(measured, context_window − default_max_tokens) | Pass (CLI writer) | Correct and tested for `write_catalog_operator_set`; not applied to the API writer |
| Catalog: `claude-opus-5-5` bound 180,000 → 936,000 | Fail | Foreign-transport, partial-outcome measurement written as an observation-proof HTTP calibration (Changes Required §1) |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (the dissent's secret scan applied one redaction on the diff text; no key material in the change)
- [x] Input validation at trust boundaries: the YAML gate accepts only a boolean `true`; `write_catalog_operator_set` refuses bad ceilings and missing fields
- [ ] Authentication/authorization correct: the probe forwards provider credentials the adapter deliberately strips (Observations §1)
- [x] No injection: the probe prompt travels on stdin, argv values are fixed; yq expressions take no user input
- [x] Dependencies: none added
- [x] Error messages: the refusal names the key and the exposure, no secrets

---

## Code Quality Summary

**Strengths:**
- The agy gate is checked before discovery, workspace or spawn, and the tests prove it with mocks that fail on any spawn.
- `resolve_effort` is a genuine single chokepoint with the source recorded end to end, including the alias-resolution case.
- The headless probe refuses to write on anything but a clean, needle-verified, bracketed measurement, and the clamp tests cover the live 972,887 case.
- The generated Bridgebuilder budgets and `dist/` were rebuilt in the same change, with the manifest hashes updated.

**Areas for Improvement:**
- One predicate, not six; one invariant (I2) in one place, not in one of two writers.
- The catalog should never carry a calibration the tool itself refused to write under the tool's own provenance label.
- `_main_cli` needs to be decomposed before the next tokenizer-ratio fix lands in it.

---

## Next Steps

1. Resolve Changes Required §1 (re-scope or make the Bedrock-measured bound observation-correctable; fix the provenance label) and add the regression test.
2. Apply the I2 clamp and `method`/`transport` writes to the API-transport writer; strip credentials in the probe's CLI env.
3. Collapse the opt-in predicate into one shared decision and make the dissent and preflight use the same "agy-routed" definition as Flatline and Bridgebuilder; drop gated hops at chain resolution in cheval.
4. Re-run pytest (adapters), bats (tests/unit) and the Bridgebuilder node tests plus `tsc --noEmit`, and record them in `grimoires/loa/a2a/sprint-1/reviewer.md` with an `## AC Verification` section.
5. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":7,"low":7},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T04:20:00Z"} -->
