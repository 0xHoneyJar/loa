# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md (Task 1.1: the change in `pr/head.diff`)
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)

---

## Overall Assessment

The change is well-tested at the unit level and the three operator decisions are implemented coherently in most seams: the loader predicate reads the `hounfour` subtree correctly (`"return full.get(\"hounfour\", {})"`, base loader.py:L109, so `merged.get("headless")` is the right key path), the catalog checksum matches the new catalog bytes, the dist bundles are rebuilt in step with the TypeScript sources, every helper the new code calls (`_raw_model_entry`, `_effort_for_model`, `_adv_hop_canon`, `CONFIG_FILE`, `YQ_FLAVOUR`) exists, and the I2 clamp in the probe writer is covered end to end.

The blocking defect is in the one place FR-1 was meant to protect and does not: cheval's own chain walk. The PR makes the agy refusal a `ConfigError`, and cheval's walk hard-aborts the whole invocation on any `ConfigError` (`"STATIC misconfig (ConfigError/INVALID_CONFIG) still falls through to the hard-abort arm below"`, head/.claude/adapters/cheval.py:L2527). Nothing in the PR teaches cheval to skip a gated hop: `cheval.py` has zero references to agy or the opt-in. So every chain that contains the `gemini-headless` hop, which the PR itself describes as `"the terminal of every stock Google chain"` (head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:L36), now dies at that hop with `INVALID_CONFIG` and never reaches the hops after it. Only the dissent's *companion* chain is pre-filtered; the primary `model` + `fallback_chain` walk is not. The PR's docs promise the opposite (`"record the hop as *not planned* (reason: opt_in_required) rather than failed"`, head/docs/migration/v2.0-model-generation-floor.md:L286).

Cross-model dissent (Phase 2.5) ran on `pr/head.diff` with the companion voice as sole voice; its one BLOCKING finding is refuted by the schema in the same diff and is recorded as a LOW below. No payloads were rejected.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Functionality / FR-1 contract: a gated agy hop aborts the entire cheval chain walk

- **HIGH** (confidence: high) `head/.claude/adapters/loa_cheval/types.py:503` — `AgyOptInRequiredError` subclasses `ConfigError`; cheval's chain walk has no handler that walks past a `ConfigError`, so with the default `agy_opt_in: false` any chain whose walk reaches the `gemini-headless` hop returns `INVALID_CONFIG` at that hop and never tries the hops after it.
**File:** `head/.claude/adapters/loa_cheval/types.py:503-517`, `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:124-125`, `head/.claude/adapters/cheval.py:2544-2553` (the `except ChevalError` arm: `"Non-retryable typed cheval error — surface immediately"` … `return EXIT_CODES.get(_e.code, 1)`), `head/.claude/scripts/adversarial-review.sh:4080-4087` (only the companion chain is filtered).
**Issue:** The refusal is raised inside `complete()` of a hop that the resolver has already placed in the chain. The walk's typed-error arm returns immediately (cheval.py:L2552-2553), records the hop as `error_class: "UNKNOWN"` in `models_failed` (L2546-2551), and nothing in the PR adds an `opt_in_required` skip to `chain_resolver`, to the walk, or to the primary-chain loop in `adversarial-review.sh` (the `_adv_agy_filter_chain` helper at L2356 is only applied to `companion_chain_str` at L4083). Concrete failing configuration, taken from this repository's own `.loa.config.yaml`: `hounfour.headless.mode: cli-only` and `flatline_protocol.code_review.fallback_chain: [gpt-5.5, gemini-3.1-pro, claude-headless]`. Under `cli-only` the Google hop is agy; when the codex hop fails (quota, auth), the walk reaches agy, raises `AgyOptInRequiredError`, and `claude-headless` is never attempted. The shell-level planner then classifies that cheval exit as `api_failure` (head/.claude/scripts/adversarial-review.sh:1302, 2212), i.e. a *failed* voice, which is exactly what FR-1 set out to stop (`"A host without agy therefore plans no Google CLI voice instead of failing one"`, agy_headless_adapter.py:L41-42). On a host where agy *is* installed this is a straight regression: before the change the hop answered; after it, with the default off, the whole invoke aborts.
**Why This Matters:** This is the FR-1 acceptance criterion itself, stated in the PR title (`"the agy route is opt-in, default off"` with voices recorded as not planned). As shipped, the default-off setting turns every stock Google-terminated chain into a hard abort inside cheval, and the Bridgebuilder/#1274 "DEGRADED 2/3" symptom the PR cites as motivation is reproduced rather than removed for every path that goes through cheval's walk (the dissent primary chain, Flatline primary/secondary chains that include a Google hop, any direct `cheval invoke`).
**Required Fix:** Make the gate a planning decision inside cheval, not a dispatch-time exception: in the chain resolution (or at the top of the per-hop loop) skip hops whose adapter class is `gemini-headless` when `agy_opt_in_enabled()` is false, record them in the MODELINV envelope as not planned with `reason: opt_in_required` (not in `models_failed`), and keep the adapter's `AgyOptInRequiredError` only as the belt-and-braces refusal for a direct single-hop dispatch. If you prefer the exception, add an `except AgyOptInRequiredError` arm before the `ChevalError` arm that `continue`s with a dedicated `error_class` (e.g. `OPT_IN_REQUIRED`) and is excluded from dropped-voice accounting, and apply `_adv_agy_filter_chain` to the primary `model`/`fallback_chain` in `adversarial-review.sh` as it is applied to the companion chain. Add a test that walks `[codex-headless, gemini-headless, claude-headless]` with the opt-in off and asserts the third hop is dispatched.
**Reference:** CWE-754 (improper check for unusual or exceptional conditions); SDD FR-1 as restated in head/docs/migration/v2.0-model-generation-floor.md:L279-L290.

---

## Observations

### 1. Configuration: the shell/TS opt-in predicates are go-yq only

- **MEDIUM** (confidence: medium) `head/.claude/scripts/adversarial-review.sh:2353` — `yq eval '… | (tag == "!!bool" and . == true)'` is mikefarah-yq syntax; on a python-yq host the command fails, `v=""`, and the operator's explicit `agy_opt_in: true` reads as off, so the companion hop is silently dropped while cheval (Python) would dispatch it.
**File:** `head/.claude/scripts/adversarial-review.sh:2350-2354`, `head/.claude/scripts/flatline-orchestrator.sh:522-527`, `head/.claude/scripts/loa-status.sh:798-803`, `head/.claude/skills/bridgebuilder-review/resources/config.ts:159-177`
**Suggestion:** The repo already supports both flavours: `run-preflight.sh` branches on `YQ_FLAVOUR` (head/.claude/scripts/run-preflight.sh:154-160) and `flatline-orchestrator.sh`'s `read_config` uses the flavour-neutral `yq -r "$path // \"\""` form (L458-469). Route all four predicates through one flavour-aware helper, or fall back to `python3 -c 'import yaml'` as the loader does, so a planner and cheval never disagree about the opt-in.
**Benefit:** Removes a silent "opted in but never planned" state that no log line explains.

### 2. Routing: `prefer-cli` is not treated as agy-routed

- **MEDIUM** (confidence: low) `head/.claude/scripts/flatline-orchestrator.sh:529-537` — `_tertiary_routes_to_agy` gates a Google model only under `cli-only`; under `prefer-cli` the CLI hop is first in cheval's chain, so with the opt-in off the tertiary is planned, reaches agy first, and (given finding CR-1) aborts instead of falling to its API hop.
**File:** `head/.claude/scripts/flatline-orchestrator.sh:529-537`, `head/.claude/skills/bridgebuilder-review/resources/config.ts:180-183`, pinned by `head/.claude/skills/bridgebuilder-review/resources/__tests__/multi-model-agy-opt-in.test.ts:61`
**Suggestion:** Once cheval skips gated hops (fix for CR-1) this becomes correct: the walk falls through to the API hop. Until then, either gate `prefer-cli` too or document why a `prefer-cli` Google tertiary is considered planned.
**Benefit:** Keeps the planner's "would cheval dispatch through agy" predicate truthful across all four documented modes.

### 3. Catalog: a 5.2× ceiling raise from a partial, route-specific probe

- **MEDIUM** (confidence: medium) `head/.claude/defaults/model-config.yaml:496-513` — `probed_ceiling`/`effective_input_ceiling` go from 180000 to 936000 for the HTTP `claude-opus-5-5` entry on the strength of a `partial` CLI probe over Bedrock (`"the tool's own outcome was `partial` — the $20 budget cap stopped the bisection"`, L496-497), written as `method: probed_headless`, a value the tool itself refuses to write on a partial outcome (head/tools/ceiling-probe-live.py:796-800).
**File:** `head/.claude/defaults/model-config.yaml:496-513`, `head/.claude/adapters/tests/test_anthropic_catalog_floor.py:135-141` (`_measured` makes the suite follow whatever the catalog says), `head/tests/unit/loa-status-providers.bats:66-69` (`"calibrated: the measured bound, observations never lower it"`)
**Suggestion:** This is an acknowledged operator decision and the `reprobe_trigger` is honest about the route, so it is not blocking. Two things would make it safer: commit the referenced record (`grimoires/loa/reports/2026-10-07-opus-5-5-ceiling-probe-cli.json` is not in this change) so the evidence travels with the catalog, and reconsider that a *calibrated* entry is never lowered by observed `PROVIDER_CONTEXT_LIMIT` verdicts: on a direct-API route whose real bound is lower, cheval will now send up to 936K on every call and fail every time with no self-correction. A `source: operator_set` entry derived from a partial probe is the case where observation-driven lowering is most needed.
**Benefit:** Prevents a permanent hard-fail loop on routes the probe never measured.

### 4. Complexity: `_main_cli` is a 215-line function with five nested closures

- **MEDIUM** (confidence: high) `head/tools/ceiling-probe-live.py:632-847` — `SIMPLICITY[shrink]`: `_main_cli` runs from L632 to L847 with `_m`, `_size`, `current_ok`, `current_fail`, `step`, `next_target` as closures over `samples`, `ratio`, `spent_micro`; `write_catalog_operator_set` (L402-485) is 84 lines. Both exceed the 50-line threshold without a justification comment.
**File:** `head/tools/ceiling-probe-live.py:632-847`, `402-485`
**Suggestion:** Lift the bisection state into a small `Bisection` dataclass with `step()` / `next_target()` methods and keep `_main_cli` to argument handling, the loop, and the record. The `__import__("time").sleep` / `__import__("re")` idioms at L136, L144, L148 should be plain top-level imports. net: -40 lines possible.
**Benefit:** The tests already exercise the pieces through `_outcome_reasons`; making the state explicit lets the clamp and re-anchor logic be unit-tested without the fake CLI.

### 5. Documentation and contract consistency (low)

- **LOW** (confidence: high) `head/.claude/adapters/loa_cheval/audit/modelinv.py:498` — comment says `effort_source` is `caller | catalog | none`; `resolve_effort` returns a fourth value `extra` (head/.claude/adapters/cheval.py:885-926) and the schema enumerates four (head/.claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json:755-762). Same stale comment at `head/.claude/adapters/cheval.py:2834`. (Dissent DISS-C-001 raised this as BLOCKING on the premise that the schema has three values; the schema has four and the test at `head/.claude/adapters/tests/test_effort_catalog_default.py:388-393` pins it, so it is a comment fix only.)
- **LOW** (confidence: high) `head/.claude/data/schemas/model-config-v3.schema.json:303-306` — `measured_input_tokens` is described as `"the value written to probed_ceiling / effective_input_ceiling"`, but the second commit's I2 clamp writes `min(measured, context_window − default_max_tokens)` (head/tools/ceiling-probe-live.py:377-399), and the live catalog carries 972887 vs 936000. The tool's module docstring (head/tools/ceiling-probe-live.py:44-45, `"the measured accepted size (raw …)"`) and the migration note (head/docs/migration/v2.0-model-generation-floor.md:297, `"to the measured bound"`) carry the same pre-clamp wording. (Dissent DISS-C-005 concurs.)
- **LOW** (confidence: medium) `head/.claude/adapters/cheval.py:1519-1522` — effort is resolved once against the *primary* resolved entry and forwarded unchanged to every fallback hop; the MODELINV `effort_source: catalog` then attributes the value to the answering hop's catalog even when that entry declares no default or a different one. Only Opus 5.5 sets a default today (pinned by `test_no_other_entry_sets_default_effort_this_cycle`), so the impact is nil now, but the design will surprise the first second entry. (Dissent DISS-C-002.)
- **LOW** (confidence: medium) `head/.claude/adapters/loa_cheval/config/loader.py:120` — `_find_project_root()` is evaluated outside the `try`, so a cwd that vanished or an unreadable parent raises a raw `OSError` from `complete()` instead of the documented fail-closed `AgyOptInRequiredError`; cheval's catch-all then reports `API_ERROR retryable=True`. Move the call inside the `try`. (Dissent DISS-C-003.)
- **LOW** (confidence: medium) `head/.claude/adapters/cheval.py:928-940` — `_effort_on_wire` returns `None` for Claude models served by a provider not literally named `anthropic` (the catalog has a `bedrock` provider: base loader.py:L796 `hounfour.providers.bedrock`) and returns the effort unchanged for every CLI hop including non-Claude ones whose adapters do not read it, so `effort_effective` can be wrong in both directions. (Dissent DISS-C-004.)
- **LOW** (confidence: high) `head/.claude/scripts/run-preflight.sh:204` — when the only configured voice is a gated agy hop, P3 FAILs with `"no credential present and no CLI hop on PATH"` even though agy is on PATH and the cause is the opt-in; the fix hint at L210 (`"install a CLI hop (claude, codex, agy)"`) does not mention `hounfour.headless.agy_opt_in`.
- **LOW** (confidence: high) `head/.claude/scripts/loa-status.sh:866` — `hop %-7s` is now fed the 52-character note `agy: opt-in (disabled; hounfour.headless.agy_opt_in)`, breaking the column alignment the format string exists for; the bats regex tolerates it, a reader will not.
- **LOW** (confidence: medium) `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:261-262` — `validate_config()` now returns an *error* for the stock `gemini-headless` provider on every default install (opt-in off). I found no production caller besides `doctor.py`, so this is cosmetic today, but "default configuration validates with an error" is a trap for the first caller that treats the list as fatal. Consider returning it as a warning or only when the hop is actually planned.
- **LOW** (confidence: high) `.claude/skills/reviewing-code/resources/ADVERSARIAL-REVIEW.md` (not in the change) — the skill doc enumerates `companion_voice.planned: false` reasons as `no_workdir`, `no_route`, `prompt_copy_failed`; the new `opt_in_required` (head/.claude/scripts/adversarial-review.sh:4085) is not documented there or in its byte-identical auditing-security copy (CMP-138 pins them identical, so update both).
- **LOW** (confidence: high) `head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py:459` — `test_write_operator_set_changes_only_the_entry_and_replaces_the_shortcut` now `pytest.skip`s permanently because the live catalog is calibrated; its unique assertions (neighbouring entries untouched, exactly one comment removed, jsonschema validation of the written `ceiling_calibration`, `input_bound` basis) run nowhere else. Port them onto the `SYNTH` fixture.
- **LOW** (confidence: medium) `pr/PR.md` — `FAST-GATE:` the PR description names no test run, formatter, or type-check output (pytest, bats, `tsc --noEmit`, `node --test`); the rebuilt `dist/.build-manifest.json` timestamp is the only evidence a build ran. I could not execute the suites against the frozen `pr/` tree, so this is recorded, not weighted.

---

## Cross-Model Observations

Dissent ran as `adversarial-review.sh --type review --sprint-id sprint-1 --diff-file pr/head.diff`; envelope `grimoires/loa/a2a/sprint-1/adversarial-review.json` (`status: reviewed`, primary chain exhausted, companion `claude-headless` succeeded as `sole_voice`, `verdict_quality.status: FAILED` 1/4 voices). Five findings, all from the companion voice, triaged:

- DISS-C-001 (BLOCKING, `cheval.py:resolve_effort`) — claims `effort_source: extra` may fail schema validation. Refuted: the schema in this diff enumerates `caller, catalog, extra, none` and a test pins it. Kept as the stale-comment LOW above.
- DISS-C-002 (ADVISORY) — fallback hops inherit the primary's effort. Agreed; LOW above.
- DISS-C-003 (ADVISORY) — `_find_project_root()` outside the `try`. Agreed; LOW above.
- DISS-C-004 (ADVISORY) — `_effort_on_wire` keyed on the literal provider name. Agreed; LOW above.
- DISS-C-005 (ADVISORY) — schema description vs clamped catalog value. Agreed; LOW above.

The dissent did not reach the chain-walk abort (CR-1); it is a reviewer-originated finding.

## Rejected dissent payloads

None: the envelope's `metadata.rejected_summary` is `[]`, `metadata.rejected_sidecars` is `[]`, and no `adversarial-rejected-review*.jsonl` sidecar exists beside it.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | FR-1 "not planned, never failed" does not hold for cheval's own chain walk (CR-1) |

---

## Acceptance Criteria Check

### Task 1.1: review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict

| Criterion | Status | Notes |
|-----------|--------|-------|
| FR-1 agy route opt-in, default off, read by one Python predicate, no env override | Partial | Predicate correct (loader.py:113-126, 8 parametrised cases). Planners filter companion chain, Flatline tertiary, Bridgebuilder, preflight, /loa. cheval's chain walk aborts at the gated hop instead of skipping it (CR-1). |
| FR-2 Opus 5.5 catalog effort default resolved once at cheval chokepoint | Pass | `resolve_effort` precedence, dry-run output, MODELINV fields, both adapters covered (test_effort_catalog_default.py, cycle-124-effort-flag.bats c127-2-1..3). Comment drift only. |
| FR-3 headless-CLI ceiling probe, clean-only catalog write, I2 clamp (fr23b) | Pass | Clamp implemented and tested at 972887→936000; raw measurement kept; partial outcomes never write. Docstring/schema wording pre-dates the clamp (LOW). |
| Catalog checksum / generated tables / dist bundles consistent | Pass | sha256 of head catalog equals `model-config.yaml.checksum`; truncation table 936000−20000=916000; dist mirrors sources. |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [x] Input validation and sanitization present (yq expressions fixed, `execFileSync` without a shell, prompt on stdin in the probe)
- [x] Authentication/authorization correct (opt-in is config-only; env overrides tested as inert)
- [x] No SQL/XSS injection vulnerabilities
- [x] Dependencies secure (no new dependencies)
- [x] Error messages don't leak sensitive data (refusal names the key only)

---

## Code Quality Summary

**Strengths:**
- The opt-in predicate's YAML-boolean-only semantics are enforced identically in Python, four shells and TypeScript, with string-`"true"` negative cases everywhere.
- The probe's fake-CLI test harness asserts zero live spend and covers classification, retry, budget, re-anchoring and the clamp.
- The `build_headless_argv` extraction gives the probe and the adapter one argv builder, pinned by a test that compares them.

**Areas for Improvement:**
- The gate is enforced at dispatch time inside cheval but as a planning decision everywhere else; cheval needs the planning form too.
- Four copies of the yq predicate, one of them flavour-aware and three not.
- Documentation written before the fr23b clamp was not revised with it.

---

## Next Steps

1. Fix CR-1 (the Changes Required finding): make cheval's chain walk skip (not abort on) a gated `gemini-headless` hop and record it as not planned; filter the primary chain in `adversarial-review.sh` as the companion chain is.
2. Address the MEDIUM observations or record the decision in NOTES.md.
3. Run and paste the pytest, bats and `node --test` / `tsc --noEmit` results into the report.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":4,"low":11},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T13:52:00Z"} -->
