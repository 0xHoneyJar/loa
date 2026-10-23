# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md (Task 1.1: the change in `pr/head.diff`)
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= `pr/PR.md`, per the brief)
**Change under audit:** `pr/head.diff` — cycle-127 sprint-251 operator decisions: FR-1 agy route opt-in (default off), FR-2 Opus 5.5 catalog effort default, FR-3 headless ceiling probe with the I2 clamp, FR-3.4 Opus 5.5 ceiling recalibration 180K→936K. 45 files.
**Review gate:** `engineer-feedback.md` says "All good" (APPROVED, 0 critical / 0 high / 7 medium / 8 low, `excluded: 0`); `adversarial-review.json` carries `metadata.model: gpt-5.5-pro`, two voices.
**Security dissent:** `grimoires/loa/a2a/sprint-1/adversarial-audit.json` — status `clean`, primary `gpt-5.5-pro` (answered by `codex-headless`), companion `claude-headless` (`counted_as: independent_voice`), `verdict_quality.status: APPROVED` 2/2, `hallucination_filter.downgraded: 0`, `degraded: false`, `locality: null` (no DEGRADED_SECURITY_REVIEW).

---

## Verdict: APPROVED - LET'S FUCKING GO

No critical or high finding. Seven mediums and thirteen lows are reported below for follow-up; none is an exploitable path, a data-loss path, or a wrong result on the default configuration. Per the one-way rule the counts do not force CHANGES_REQUIRED, and I am not forcing it on medium/low accumulation: the security-relevant behaviours the PR ships (the agy refusal before any spawn, the boolean-only opt-in in all six readers with no environment override, the fail-closed yq readers, the clean-only catalog write) are each pinned by tests I read, and the mediums are telemetry, contract wording, coverage, planner consistency, one governance gap and one probe/adapter environment divergence.

---

## Executive Summary

The PR's security goal is to put the argv-prompt exposure of the `agy -p` route (CWE-214) behind an explicit operator opt-in, and it does so coherently: the adapter raises `AgyOptInRequiredError` before discovery, workspace or the one-time WARN (`head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:124-125`, pinned by `test_off_refuses_before_any_discovery_or_spawn` and `test_off_never_warns_of_the_argv_prompt`); every bash reader compares a `tag == "!!bool" and . == true` yq result to the literal `true`; the TS reader uses `execFileSync` with an argv array and a fail-closed catch; and the string `"true"` is rejected by a negative test in Python, bash and TS. I re-verified mechanically that the catalog checksum equals the SHA-256 of the head catalog (`17f75f07…`) and that the Bridgebuilder `.build-manifest.json` hashes for `config.ts`, `multi-model-pipeline.ts` and `truncation.generated.ts` equal the head sources. The Bridgebuilder merge-block logic stays safe with a shrunken cohort: an all-not-planned configuration throws at `multi-model-pipeline.ts:212` and an empty cohort makes `computeVerdictBand` return `null`, which is not `APPROVED`, so `mergeBlocked` is set.

What is weaker than the PR text claims: the machine-readable `failure_class: opt_in_required` seam is documented but never emitted on the wire (MED-001); the new `effort_effective` telemetry is resolved against the primary and misreports a fallback CLI hop (MED-002); the one test that validated the writer's `ceiling_calibration` output against the schema now skips forever (MED-003); the 936K Opus 5.5 bound is a hand-written `operator_set` value from a `partial` probe on a different transport with no decision record in this workspace (MED-004); the dissent gates agy by hop name only while flatline and Bridgebuilder also gate by headless mode (MED-005); a non-terminal opted-out agy hop aborts a chain walk (MED-006); and my own new finding, the headless probe spawns `claude` with the full inherited environment including credential variables, contrary to the adapter's env-strip contract, so it may measure and bill a different auth route than the adapter dispatches (MED-007).

**Security Issues Found:**

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 7 |
| Low | 13 |

**Category Scores (per `resources/RUBRICS.md`):** Security 4.0/5 (IV:4 AZ:4 CI:4 IN:4 AV:4) · Architecture 3.8/5 · Code Quality 3.8/5 (TS:3 for the permanent skip) · DevOps 3.8/5 · Blockchain n/a · **Overall 3.9/5 → MODERATE**. Machine-parseable findings: `grimoires/loa/a2a/audits/2026-10-22/findings.jsonl`; sources/sinks working file: `grimoires/loa/a2a/audits/2026-10-22/SECURITY_ANALYSIS_TODO.md`.

[ASSUMPTION] Files the PR does not touch (`providers/base.py`, `routing/ceiling.py`, `headless_cli.py`, `anthropic_adapter.py`, `providers/__init__.py`) are read from this workspace's copy where present and assumed unchanged; where a finding depends on them I say so.

---

## Critical Security Issues (Must Fix)

None.

## High Priority Security Issues (Fix Before Deployment)

None.

---

## Medium Priority Issues

### [MED-001] Documented machine-readable refusal seam never reaches cheval's error output

- **Severity:** MEDIUM | **Confidence:** high | **Criterion:** ARCH contracts
- **File:** `head/.claude/adapters/cheval.py:2552` (also `head/.claude/adapters/loa_cheval/types.py:516`, `head/docs/migration/v2.0-model-generation-floor.md:284`)
- **Code:** `print(_error_json(_e.code, str(_e), retryable=_e.retryable), file=sys.stderr)`
- **Issue:** `AgyOptInRequiredError` sets `self.context = {"failure_class": "opt_in_required"}` and its docstring calls this "the machine-readable seam planners read as 'not planned', never as a failed voice"; the migration doc repeats it. The chain walk's `except ChevalError` branch prints `_error_json` without `**_e.context` and records `error_class: "UNKNOWN"` (`:2549`). `_error_json` accepts `**extra` (`:142`) but only the PROVIDER_DISCONNECT path uses it. The in-process test checks `err.context` only, never the emitted JSON.
- **Scenario:** A planner that relies on the documented field (the dissent's `failure_class` classifier, say) cannot tell "not planned" from "failed" without string-matching the message. Nothing in this PR consumes it, so no consumer is broken today.
- **Fix:** Pass `**_e.context` into `_error_json` in that branch and set `error_class` from `context.failure_class` when present; or reword the docstring and migration doc to say the class is in-process only.
- **Reference:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html

### [MED-002] `effort`/`effort_effective` resolved against the primary entry misreport a fallback CLI hop

- **Severity:** MEDIUM | **Confidence:** medium | **Criterion:** ARCH observability (audit-record accuracy)
- **File:** `head/.claude/adapters/cheval.py:933` (emit at `:2838`)
- **Code:** `if effort is None:\n        return None`
- **Issue:** `resolve_effort` runs once against the primary resolved entry (`:1519`). Primary `claude-opus-5` has no `default_effort` → `(None, "none")`; the chain falls to `anthropic:claude-headless` whose `extra.effort: low` is set; the headless adapter's own `_resolve_effort` still puts `--effort low` on argv (pinned by `test_cli_adapter_extra_effort_stays_below_the_chokepoint_value`), but the MODELINV envelope omits `effort` and `effort_effective` and says `effort_source: none`.
- **Scenario:** Cost and behaviour attribution in the audit trail is wrong for exactly the hops the new field was added to describe ("the wire value on the hop that answered").
- **Fix:** When `final_model_id` names a CLI entry and `_effort` is `None`, re-run `resolve_effort` against that hop's entry for `effort_effective`, or read the request the adapter actually built. (The review's DISS-001/DISS-C-002 and its Observation 2 say the same; the "over-apply" half of DISS-C-002 is the documented D-2.2 design.)
- **Reference:** CWE-778 Insufficient Logging — https://cwe.mitre.org/data/definitions/778.html

### [MED-003] The only writer-output-vs-schema check now self-skips permanently

- **Severity:** MEDIUM | **Confidence:** high | **Criterion:** CQ test coverage
- **File:** `head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py:459` (schema assertion at `:500`)
- **Code:** `pytest.skip("the catalog is already calibrated (the lead's probe write landed)")`
- **Issue:** The skip requires the `# loa:shortcut: Opus 5's measured bound` comment in the live catalog; the head catalog no longer carries it (`head/.claude/defaults/model-config.yaml:494-510`), so the test skips on every run from now on. It is the only place the writer's `ceiling_calibration` block is validated with `jsonschema` against `$defs.ceilingCalibration` and run through `routing.ceiling.input_bound`. The remaining writer tests use the `SYNTH` fixture without schema validation; the bats `V3-add (c127)` test validates a hand-written example. `head/.claude/adapters/tests/test_anthropic_catalog_floor.py:146` and `:299` derive the expected value for a measured entry from the entry itself, so the calibrated Opus 5.5 entry is checked only for the I2 invariant.
- **Scenario:** A hand-edit of the calibrated block (missing `method`, a `transport` outside the enum) passes the suite.
- **Fix:** Run the schema and `input_bound` assertions on the `SYNTH` write with no skip, and add one assertion that the live calibrated entry's block validates against the schema.
- **Reference:** CWE-1164 Irrelevant Code (dead test) — https://cwe.mitre.org/data/definitions/1164.html

### [MED-004] 180K→936K Opus 5.5 bound written as calibrated from a `partial` probe on another transport, with no decision record

- **Severity:** MEDIUM | **Confidence:** medium | **Criterion:** DEVOPS configuration governance / cost control
- **File:** `head/.claude/defaults/model-config.yaml:494` (`:496-502` comment, `:504` source; `head/.claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts:34`)
- **Code:** `effective_input_ceiling: 936000   # cycle-124 FR-3 (SDD §2.1): see claude-fable-5-1`
- **Issue:** The entry's own comment says the probe outcome was `partial` (the $20 cap stopped the bisection; bracket 972,887 accepted / ~1,065,182 rejected, far wider than the 16K tolerance), measured through Bedrock via the CLI (`cli_model: global.anthropic.claude-opus-5-5`) and applied to the `anthropic` HTTP entry whose `account_limits.itpm` is `null`. The tool itself refuses to write anything but `clean` (`head/tools/ceiling-probe-live.py:811`). Per the LSP-5 policy comment in `head/tests/unit/loa-status-providers.bats:66-68`, a calibrated entry's bound is never lowered by observed 429/context verdicts. Bridgebuilder's budget for the model becomes 916,000 input tokens. `grimoires/loa/NOTES.md` has no Decision Log row and the referenced record `grimoires/loa/reports/2026-10-07-opus-5-5-ceiling-probe-cli.json` is not in the PR.
- **Scenario:** If the direct-API account's input limit is below 936K, every large `opus` call 429s and walks the chain (the next two hops still carry 180K and preempt, so the request ends on the CLI route that was actually measured); the observed-ceiling store cannot correct the catalog. Per-call input cost ceiling for the dissent and Bridgebuilder rises 5.7×.
- **Fix:** Add the DEC row (what was measured, why 936K, the API-transport re-probe trigger); consider letting a `PROVIDER_CONTEXT_LIMIT`/`RATE_LIMIT` observation lower a calibrated bound until the API-transport probe lands.
- **Reference:** CWE-400 Uncontrolled Resource Consumption — https://cwe.mitre.org/data/definitions/400.html

### [MED-005] The dissent's agy filter ignores headless mode; flatline and Bridgebuilder do not

- **Severity:** MEDIUM | **Confidence:** medium | **Criterion:** ARCH consistency
- **File:** `head/.claude/scripts/adversarial-review.sh:2360` (compare `head/.claude/scripts/flatline-orchestrator.sh:533-537`, `head/.claude/skills/bridgebuilder-review/resources/config.ts:182`)
- **Code:** `if [[ "$(_adv_hop_canon "$h" 2>/dev/null || printf '%s' "$h")" == "gemini-headless" ]]; then`
- **Issue:** `_adv_agy_filter_chain` drops only hops whose canonical name is `gemini-headless`; the other two planners also treat any Google model under `hounfour.headless.mode: cli-only` as agy-routed. This repository runs `cli-only` (`.loa.config.yaml:114`). I confirmed the default companion route can only contain the agy hop through an operator `companion_chain` list (`_companion_chain` has anthropic/openai families only and adds a CLI hop only when `_adv_cli_present`), so the WARN's wording is accurate; the gap is for a Google API id in such a list.
- **Scenario:** An operator `companion_chain` naming `gemini-3.1-pro` under `cli-only` is planned, dispatched, refused by cheval with INVALID_CONFIG and recorded as a failed companion (a dropped voice for an audit), while the same model as a flatline tertiary is "not planned". [ASSUMPTION] cheval routes a Google API id to the agy hop under `cli-only`, as the flatline FTA-2 and TS tests assert.
- **Fix:** Give `_adv_agy_filter_chain` the same mode rule (`_adv_family_of` = google and mode `cli-only` ⇒ drop), or document that the dissent gates by hop name only.
- **Reference:** CWE-1068 Inconsistency Between Implementation and Documented Design — https://cwe.mitre.org/data/definitions/1068.html

### [MED-006] A non-terminal, opted-out agy hop aborts the whole chain walk

- **Severity:** MEDIUM | **Confidence:** medium | **Criterion:** ARCH resilience
- **File:** `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:125` (walk at `head/.claude/adapters/cheval.py:2544`)
- **Code:** `raise AgyOptInRequiredError()`
- **Issue:** `AgyOptInRequiredError` is a `ConfigError`; at `cheval.py:2544` any `ChevalError` from a hop "surfaces immediately" and returns. For stock chains agy is terminal, so the walk would have ended anyway. For an operator chain where the agy hop precedes a keyed HTTP hop, a host with `agy` installed but no opt-in now exits INVALID_CONFIG at the agy hop although the next hop would have answered (before the PR that host dispatched agy). Same class as the pre-PR "agy CLI not found on PATH" ConfigError, so not a new failure mode for stock chains.
- **Scenario:** The HTTP voice behind the hop is lost in a review. [ASSUMPTION] about chain ordering under `prefer-cli`. Raised by the review dissent as DISS-C-006.
- **Fix:** Treat `opt_in_required` as walkable (skip the hop, record `not_planned`), or state in the docstring that the refusal is non-walkable and stock chains keep agy terminal.
- **Reference:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html

### [MED-007] The headless probe spawns `claude` with the full inherited environment, contrary to the adapter's env-strip contract

- **Severity:** MEDIUM | **Confidence:** medium | **Criterion:** SEC information exposure / route fidelity (new finding, not in the review or the dissent)
- **File:** `head/tools/ceiling-probe-live.py:217` (in `_run_capped`, `:214-226`)
- **Code:** `env = {**os.environ, "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1"}`
- **Issue:** The adapter whose argv the probe reproduces spawns with `build_headless_subprocess_env()` (`.claude/adapters/loa_cheval/providers/base.py:794-822`, not in the PR), which strips `_HEADLESS_STRIPPED_AUTH_VARS` under the documented contract "never inherit subprocess env" (#879/#880). The probe passes the whole environment, so `ANTHROPIC_API_KEY` and the Bedrock/Vertex mode selectors reach the `claude` CLI. The tool's docstring says it measures "the shape the adapter dispatches"; the test fixture deletes `ANTHROPIC_API_KEY` from the test environment, but the tool does not.
- **Scenario:** An operator with `ANTHROPIC_API_KEY` exported runs the CLI-transport probe expecting the subscription or Bedrock route; the CLI picks up the key, the probe measures the direct-API account's bound and bills that account, and the catalog is written with a bound measured on a route the adapter never uses. [ASSUMPTION] that the claude CLI prefers an exported `ANTHROPIC_API_KEY` over its OAuth login when `CLAUDE_CODE_USE_BEDROCK` is unset, as it has historically.
- **Fix:** Build the env with `build_headless_subprocess_env()` (importable through `_adapters()`) and then set `CLAUDE_CODE_DISABLE_AUTO_MEMORY`; record in the probe JSON whether a credential variable was present and stripped.
- **Reference:** CWE-526 Cleartext Storage of Sensitive Information in an Environment Variable — https://cwe.mitre.org/data/definitions/526.html ; CWE-214 — https://cwe.mitre.org/data/definitions/214.html

---

## Low Priority Issues

### [LOW-001] The opt-in is read from the project-layer config via cwd walk; the docstring implies an operator-only surface
- **Confidence:** medium · **File:** `head/.claude/adapters/loa_cheval/config/loader.py:120-122`
- **Issue:** The gate's docstring excludes environment override so "a planner is never talked into the agy voice by ambient env", but the decision comes from `.loa.config.yaml` found by walking up from cwd — the tree under review in a self-hosted review flow. The project layer already owns endpoints, auth and chains, so a writer of that file can already redirect prompts; the PR adds no new boundary and narrows exposure. Security dissent DISS-C-001, downgraded to LOW for that reason.
- **Fix:** Document that the project layer is trusted, and have the one-time argv WARN name the file that enabled the route.
- **Reference:** CWE-15 External Control of System or Configuration Setting — https://cwe.mitre.org/data/definitions/15.html

### [LOW-002] The fail-closed predicate evaluates the project-root walk outside its `try` and re-parses two YAML files per call
- **Confidence:** medium · **File:** `head/.claude/adapters/loa_cheval/config/loader.py:120` (`try` at `:121`)
- **Issue:** `_find_project_root()` calls `Path.cwd()`, which raises `FileNotFoundError` when the cwd has been removed (handled elsewhere via `cwd_vanished`); the exception escapes `complete()`/`health_check()`/`validate_config()` into the chain walk's catch-all as `API_ERROR, retryable: true`. The dispatch is still prevented, so the gate is closed, with the wrong error class. Both layers are parsed and the whole System catalog deep-merged on every call (`:122`), and the adapter calls the predicate in three methods. The review rated this MEDIUM (Observation 6); I rate it LOW because the refusal still holds.
- **Fix:** Move the root resolution inside the `try`; read `.loa.config.yaml` alone or memoise per (root, mtime).
- **Reference:** CWE-755 — https://cwe.mitre.org/data/definitions/755.html

### [LOW-003] Six readers of the opt-in disagree on the layer they read
- **Confidence:** high · **File:** `head/.claude/adapters/loa_cheval/config/loader.py:122`
- **Issue:** The Python reader merges the System catalog under the project config; the four bash readers and the TS reader read only `.loa.config.yaml`. A `headless.agy_opt_in: true` placed in `.claude/defaults/model-config.yaml` (System Zone, integrity-checked) would opt cheval in while every planner reads off. Raised in `reviewer-concerns.md` item 2 and not carried into the review's observations.
- **Fix:** Read only `load_project_config(root)` in `agy_opt_in_enabled`.
- **Reference:** CWE-1068 — https://cwe.mitre.org/data/definitions/1068.html

### [LOW-004] The caller rung of the effort chokepoint is not validated inside the chokepoint
- **Confidence:** high · **File:** `head/.claude/adapters/cheval.py:912`
- **Issue:** `resolve_effort` allow-lists the catalog and extra rungs but returns `args.effort` as-is; a programmatic caller bypasses the allow-list and the value reaches the HTTP body, the CLI argv and the MODELINV payload. argparse validates the CLI path. Security dissent DISS-C-002.
- **Fix:** Apply `_valid_effort(explicit)` and warn-once/ignore on mismatch.
- **Reference:** CWE-20 — https://cwe.mitre.org/data/definitions/20.html

### [LOW-005] `build_headless_argv` keeps an argv-prompt parameter no caller uses
- **Confidence:** high · **File:** `head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:131` (`:145`)
- **Issue:** cycle-126 moved the claude-headless prompt to stdin to close the `/proc/<pid>/cmdline` exposure; the shared builder's optional `prompt` puts it back on argv when passed. The adapter passes `None` (`:280`) and the probe builds without it. Security dissent DISS-C-003.
- **Fix:** Drop the parameter, or rename it to make the exposure explicit and add a test that the adapter never passes it.
- **Reference:** CWE-214 — https://cwe.mitre.org/data/definitions/214.html

### [LOW-006] `LOA_HEADLESS_MODE` can remove Google voices from the planned cohort
- **Confidence:** medium · **File:** `head/.claude/scripts/flatline-orchestrator.sh:533` (also `head/.claude/skills/bridgebuilder-review/resources/config.ts:176`)
- **Issue:** The opt-in has no env override, but the mode that decides whether a Google voice is agy-routed does. With `LOA_HEADLESS_MODE=cli-only` in the environment every Google voice becomes "not planned" in flatline and Bridgebuilder; the verdict is computed over the remaining voices as a full cohort (Bridgebuilder prints "2/2 voices" for a three-voice config). The removal is logged and carried in `notPlanned` / `tertiary_status`, and cheval honours the same variable, so this is a design note rather than an exploit.
- **Fix:** Read the mode for the gate from the config only, or document that `LOA_HEADLESS_MODE` participates in the gate.
- **Reference:** CWE-15 — https://cwe.mitre.org/data/definitions/15.html

### [LOW-007] Two comments say `effort_source` has three values
- **Confidence:** high · **File:** `head/.claude/adapters/loa_cheval/audit/modelinv.py:498` and `head/.claude/adapters/cheval.py:2834`
- **Issue:** The resolver (`:921-926`) and both schemas (`model-invoke-complete.payload.schema.json:755-762`) have four values including `extra`. The dissent's DISS-C-001 (review round) claimed the schema was three-valued; it is not — only the comments are stale.
- **Fix:** Fix both comments.
- **Reference:** CWE-1116 — https://cwe.mitre.org/data/definitions/1116.html

### [LOW-008] `default_effort: null` warns, and the two rungs normalise differently
- **Confidence:** high · **File:** `head/.claude/adapters/cheval.py:914`
- **Issue:** `"default_effort" in params` is true for an explicit `null`, so `_valid_effort(None)` logs once per process; the extra rung lower-cases and strips (`:924`) while the catalog rung is verbatim.
- **Fix:** Treat `None` as absent; keep the strict casing on the catalog rung (matches the schema enum).
- **Reference:** CWE-20 — https://cwe.mitre.org/data/definitions/20.html

### [LOW-009] Catalog provenance comment drifts from what the writer produces
- **Confidence:** high · **File:** `head/.claude/defaults/model-config.yaml:495` (writer at `head/tools/ceiling-probe-live.py:465`)
- **Issue:** The writer emits a clamp note when `written < measured`; the hand-written line lacks it, so re-running the writer rewrites line 495.
- **Fix:** Run the writer once more or accept the drift knowingly.
- **Reference:** CWE-1059 — https://cwe.mitre.org/data/definitions/1059.html

### [LOW-010] Status note shown on hosts without `agy`
- **Confidence:** high · **File:** `head/.claude/scripts/loa-status.sh:805`
- **Issue:** `_provider_hop_note google` prints `agy: opt-in (disabled; …)` whenever the opt-in is off, regardless of `command -v agy`; after opting in such a host shows `hop -`.
- **Fix:** Check `command -v agy` before printing the note, or append "not installed".
- **Reference:** CWE-1053 — https://cwe.mitre.org/data/definitions/1053.html

### [LOW-011] Preflight FAIL text is wrong when the only voice is gated
- **Confidence:** high · **File:** `head/.claude/scripts/run-preflight.sh:204` (`:208`)
- **Issue:** The detail says "no credential present and no CLI hop on PATH" while the real cause is appended as "not planned: …". Pinned as written by PF-AGY.
- **Fix:** Branch the detail text when `p3_optin` is non-empty.
- **Reference:** CWE-1053 — https://cwe.mitre.org/data/definitions/1053.html

### [LOW-012] Re-anchoring the top after a parsed size rejection spends a second top-size attempt
- **Confidence:** medium · **File:** `head/tools/ceiling-probe-live.py:740`
- **Issue:** When the blind first step is a size rejection whose parsed count is more than `tol` from `hi`, `next_target` returns `hi` again (now scaled), almost always rejected again; the worst-case step is charged twice.
- **Fix:** Skip the re-anchor when the first sample is a rejection.
- **Reference:** CWE-400 — https://cwe.mitre.org/data/definitions/400.html

### [LOW-013] Emit-time lazy import of a private symbol inside the audit emit
- **Confidence:** medium · **File:** `head/.claude/adapters/cheval.py:938` (evaluated at `:2838`)
- **Issue:** `_effort_on_wire` imports `anthropic_adapter._effort_for_model` lazily inside the `_emit_modelinv(...)` argument list after spend; the emit is fail-soft (`:2814`/`:2873`), so a mapping failure loses the MODELINV record, not the invoke.
- **Fix:** Compute `effort_effective` before the emit and default to `None` on error.
- **Reference:** CWE-755 — https://cwe.mitre.org/data/definitions/755.html

---

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 7 |
| Low | 13 |

Review trailer `excluded: 0` → nothing to confirm; `excluded_confirmed: 0`. No audit finding is marked speculative; `excluded: 0`.

---

## Security Dissent Triage (`adversarial-audit.json`)

Three findings, all from the companion `claude-headless`; the primary (`gpt-5.5-pro` → `codex-headless`) returned none.

- **DISS-C-001 (MEDIUM, config)** — opt-in read from the cwd-walked project config → **LOW-001**. Downgraded: the project layer already owns the provider endpoints and auth; the PR narrows exposure and adds no new boundary.
- **DISS-C-002 (LOW, input-validation)** — caller rung unvalidated → **LOW-004**, agreed.
- **DISS-C-003 (LOW, info-disclosure)** — `prompt` parameter on the shared argv builder → **LOW-005**, agreed.

`advisory_voices`: none. `metadata.locality`: null; `degraded: false` — not a DEGRADED_SECURITY_REVIEW.

## Rejected dissent payloads

- None — `metadata.rejected_summary` is `[]`, `rejected_count` is 0, and no `adversarial-rejected-audit.jsonl` sidecar exists beside the envelope.

---

## Review Cross-Check (`engineer-feedback.md`)

The review's seven mediums map to MED-001…MED-006 and LOW-002 (its Observation 6, downgraded here: the refusal still holds). Its eight lows map to LOW-007…LOW-013; its Observation 15 (no AC walkthrough in the implementation report) is a process note, recorded under Observations below and not tallied. New in this audit: MED-007 (probe environment), LOW-001, LOW-003, LOW-004, LOW-005, LOW-006.

---

## Observations (not tallied)

- **yq flavour.** `adversarial-review.sh`, `loa-status.sh`, `flatline-orchestrator.sh` and the TS reader use go-yq `tag == "!!bool"` syntax; only `run-preflight.sh` branches on `YQ_FLAVOUR`. Each of those scripts already uses `yq eval` throughout (26, 6 and 4 existing sites), so a python-yq host was never supported by them; on such a host the new readers fail closed ("not planned"). Not introduced by the PR.
- **Process.** The implementation report is the PR description by the brief's construction: no `## AC Verification` walkthrough, no self-check or test-run output. The pytest, bats and node suites that import the untouched package tree could not be executed in this frozen copy; I ran only mechanical checks (hashes, grep for the shortcut comment, reading the merge-block path).
- **Documentation coherence.** No `grimoires/loa/a2a/subagent-reports/documentation-coherence-*.md` exists in this workspace; I verified manually that `.loa.config.yaml.example:743-751`, `docs/migration/v2.0-model-generation-floor.md:276-311`, the v3 schema descriptions and the agy adapter docstring describe the shipped behaviour (with the MED-001 caveat). No CHANGELOG is in the PR and none is present in `pr/head/`; whether the repository keeps one could not be assessed here.
- **Known-failures surface** (`grimoires/loa/known-failures.md`) is absent in this workspace; triage was done without it.
- **Checked and found safe:** `execFileSync("yq", [...])` argv array with timeout and fail-closed catch (`config.ts:162-170`); `_write_text_atomic` mkstemp + `os.replace` in the catalog directory; probe output caps (1 MiB per stream, diagnostics cut at 300 chars); the probe's needle verification and zero-live-spend fixture; the bats-gated `LOA_STATUS_CONFIG_FILE` seam; `_adv_agy_filter_chain` word handling; Bridgebuilder `repoRoot` resolves CLI > env > git (the Loa root, not the reviewed repository).

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added (probe fake uses placeholder keys; `_dry` strips `ANTHROPIC_API_KEY`; the TS tests use `fixture-not-a-key`)
- [x] Input validation at trust boundaries: `agy_opt_in` boolean-only in six readers; `default_effort` enum-validated in the schema and allow-listed at runtime; the writer rejects non-positive/boolean ceilings and unknown models
- [x] The argv-prompt exposure (CWE-214) is behind an explicit opt-in whose risk is named in `.loa.config.yaml.example` and the migration doc
- [x] No environment override for the opt-in (tested in Python, bash and TS) — the headless *mode* still has one (LOW-006)
- [x] Error messages do not leak secrets (the refusal names the key, not a value)
- [x] Subprocess spawns use argv arrays, no shell (`execFileSync`, `subprocess.run(cmd)`)
- [ ] Probe subprocess environment is not stripped as the adapter's is (MED-007)
- [ ] Not verifiable here: that cheval honours `AGY_HEADLESS_BIN` only from trusted env (pre-existing)

---

## Next Steps

1. Sprint is cleared: APPROVED - LET'S FUCKING GO.
2. File follow-ups for MED-001…MED-007 (one-line fixes for MED-001, MED-007 and LOW-002/LOW-003; a DEC row for MED-004).
3. Move to the next sprint or `/deploy-production`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":7,"low":13},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-22T00:58:00Z"} -->
