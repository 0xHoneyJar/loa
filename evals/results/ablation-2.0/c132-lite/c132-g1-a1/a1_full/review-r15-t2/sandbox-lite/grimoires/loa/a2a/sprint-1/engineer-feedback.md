# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)

---

## Overall Assessment

The change under review is `pr/head.diff` (45 files): sprint-251's three operator decisions — (FR-1) the agy/`gemini-headless` route becomes opt-in via `hounfour.headless.agy_opt_in`, (FR-2) `claude-opus-5-5` gets a catalog `params.default_effort: high` resolved once in cheval with `effort_source` / `effort_effective` telemetry, (FR-3) `tools/ceiling-probe-live.py --transport claude-headless` plus the fr23b I2 clamp, and the catalog write of the Opus 5.5 bound (180,000 → 936,000).

What is good: the opt-in predicate is one function, fails closed, and is tested through the real config layer (`head/.claude/adapters/tests/test_agy_opt_in_gate.py`); `resolve_effort` is a single chokepoint with a clear rung order and warn-once behaviour; the probe verifies every accept with a needle, measures from CLI usage, bisects in measured tokens, and only a `clean` outcome writes the catalog; the fr23b clamp pins cheval's I2 invariant; the `.build-manifest.json` hashes for the three touched TS sources and the `model-config.yaml.checksum` match the head files (verified with `sha256sum`); the dist JS matches the TS source by reading.

What blocks: the FR-1 guarantee — "the hop is recorded as not planned, never as a failed voice" — is implemented by five planners pre-checking the key, but cheval's own chain walk treats the refusal as a hard-abort `ConfigError`. Under `hounfour.headless.mode: prefer-cli` the resolver puts `gemini-headless` *first* in every Google chain, so with the new default (off) and `agy` installed, every Google invoke aborts with `INVALID_CONFIG` before the HTTP Gemini hops are tried, and the Bridgebuilder/Flatline gates (which treat only `cli-only` as agy-routed) plan, dispatch and then record a *failed* voice — the #1274 DEGRADED pattern the PR set out to remove. Details and a fix are under Changes Required.

The remaining findings are medium/low: telemetry that misreports the wire effort on a CLI fallback hop, the dissent's primary-voice classification, provenance of the hand-written catalog calibration, two tests that no longer check what they read as checking, stale contract comments, and a 218-line function.

Process notes. (1) Tests were **not executed**: the PR's base tree differs from this workspace (`cheval.py`, `flatline-orchestrator.sh`, the catalog all differ; `tools/` is absent), and building an overlay copy was refused by the System Zone fence (`FR-SZ2-COPY`), so every test assertion below was verified by reading, not by running. (2) `reviewer.md` is the PR description and carries no `## AC Verification` walkthrough; per `pr/REVIEW-INSTRUCTIONS.md` the PR files are the entire input, so the ACs were checked directly against the code (table below) and the absence is recorded, not counted. (3) The adversarial dissent ran without a reviewer concerns file (independence preserved); its findings are triaged under Cross-Model Observations.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Functionality — the opt-in refusal hard-aborts cheval's chain walk

- **HIGH** (confidence: medium) `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:124-125` — `complete()` raises `AgyOptInRequiredError`, a `ConfigError`; cheval's walker catches it in the `except ChevalError` arm (`head/.claude/adapters/cheval.py:2544-2552`, "surface immediately", `return EXIT_CODES[...]`), so the hop is not skipped — the whole invoke ends with `INVALID_CONFIG` (exit 2) and no later hop runs.
**File:** `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:124-125`; `head/.claude/adapters/loa_cheval/types.py:503-518`; `head/.claude/adapters/cheval.py:2544-2552`
**Issue:** Under `prefer-api` (default) `gemini-headless` is the chain terminal (`head/.claude/defaults/model-config.yaml:216,228,248,262,289,309`), so the abort only changes the error text. Under `prefer-cli` the within-company mode transform orders CLI entries first (`loa_cheval/routing/chain_resolver.py`, `_mode_transform`: `cli + http`), so `gemini-headless` becomes hop 1 of every Google chain. Failure scenario: a host with `agy` installed (yesterday's working configuration), `hounfour.headless.mode: prefer-cli`, a valid `GOOGLE_API_KEY`, and the new default `agy_opt_in` absent → `cheval --model gemini-3.1-pro-preview` aborts at hop 1 with "agy headless route is opt-in" and never reaches `gemini-3.1-pro-preview` / `gemini-2.5-pro` over HTTP. The planners' gates do not cover this mode: `head/.claude/skills/bridgebuilder-review/resources/config.ts:180-183` (`isAgyRouted` → `modelId === "gemini-headless" || mode === "cli-only"`) and `head/.claude/scripts/flatline-orchestrator.sh:529-536` (`_tertiary_routes_to_agy`, `cli-only` only) plan the Google voice, dispatch it through cheval, and record it as **failed** (Bridgebuilder: `mergeBlocked`; Flatline: dropped voice). The migration doc's claim (`head/docs/migration/v2.0-model-generation-floor.md:283-287`) "the dissent, Flatline's tertiary, Bridgebuilder … record the hop as not planned rather than failed" is therefore false for cheval's own routing. The repo's primary host is documented as CLI-routed (KF-040, `head/docs/migration/v2.0-model-generation-floor.md:300-302`), so this configuration is realistic, not hypothetical.
**Why This Matters:** The PR's stated purpose for FR-1 is that a not-opted-in host "plans no Google CLI voice instead of failing one (Bridgebuilder #1274 ran DEGRADED 2/3 on that account)". On `prefer-cli` hosts that have `agy`, the new default re-creates that exact degradation and additionally removes a working HTTP fallback. The default flip is a breaking change the migration doc should name as such.
**Required Fix:** Make the refusal a *skip* in the walk rather than an abort: either (a) have cheval's walker test `agy_opt_in_enabled()` (or `adapter.health_check()`) for `gemini-headless` entries before dispatch and `continue` with a `models_failed` row `error_class: NOT_PLANNED`, `failure_class: opt_in_required`; or (b) raise a walkable class (a `ProviderUnavailableError` subclass carrying `failure_class = "opt_in_required"`) so the chain falls through to the HTTP siblings. In both cases extend `isAgyRouted` and `_tertiary_routes_to_agy` to treat `prefer-cli` as agy-routed for Google voices (the CLI hop runs first there), add a prefer-cli case to `test_agy_opt_in_gate.py` and `flatline-tertiary-agy-opt-in.bats`, and state the behaviour change for `prefer-cli`/`cli-only` hosts in the migration doc.
**Reference:** SDD cycle-104 §1.4.2 "skip-and-walk" contract (the walker's own step-1 comment at `head/.claude/adapters/cheval.py:2174`).

---

## Observations

### 1. Telemetry — effort on fallback hops (cross-model DISS-C-002, confirmed)

- **MEDIUM** (confidence: high) `head/.claude/adapters/cheval.py:2838-2843` — `effort_effective` is computed from the primary's `_effort`; `_effort_on_wire` returns `None` when `_effort is None` (`head/.claude/adapters/cheval.py:934-935`), yet a CLI hop that answered resolves its own legacy `extra.effort` and sends `--effort <x>` (the PR's own test pins this: `head/.claude/adapters/tests/test_effort_catalog_default.py:384-386`). The MODELINV row then omits `effort_effective` for a call that did put an effort on the wire.
**File:** `head/.claude/adapters/cheval.py:2838-2843`, `head/.claude/adapters/cheval.py:1829`
**Suggestion:** Compute `effort_effective` from the answering hop's own resolution (call `resolve_effort` against the final hop's raw entry), not from the primary's value. Separately, `effort=_effort` at line 1829 places the primary's catalog default on every fallback hop's request, so an operator's per-hop `extra.effort` on a CLI fallback is silently overridden — contradicting the docstring's "the headless adapter's own rung" (`head/.claude/adapters/cheval.py:896-897`). Document that precedence or resolve per hop.
**Benefit:** Audit rows describe what was sent; per-hop operator config keeps meaning.

### 2. Dissent — the primary voice path is not covered by the opt-in filter

- **MEDIUM** (confidence: high) `head/.claude/scripts/adversarial-review.sh:4080-4087` — `_adv_agy_filter_chain` is applied to the companion chain only. A primary whose chain reaches `gemini-headless` exits 2 (`INVALID_CONFIG`), which `_companion_failure_class` (`head/.claude/scripts/adversarial-review.sh:2979-2993`) maps to `model_unavailable`: a dropped voice, not `opt_in_required`. The surfaced diagnostic also names the opt-in when the operator's actual gap is a missing `GOOGLE_API_KEY` (HTTP hops exhausted first under `prefer-api`).
**Suggestion:** Classify exit 2 with the `opt_in_required` marker as not-planned (or filter the primary chain the same way), and have the terminal refusal message mention that the HTTP hops were tried first.
**Benefit:** `verdict_quality` counts planned voices only, as the doc claims.

### 3. Catalog — provenance of the 936,000 calibration

- **MEDIUM** (confidence: medium) `head/.claude/defaults/model-config.yaml:494-513` — the entry is written `source: operator_set`, `method: probed_headless`, `calibrated_at: 2026-10-07T09:29:07Z`, but the comment at line 496 says the tool's own outcome was `partial` (budget-capped before the 16K tolerance); the tool refuses to write a partial result (`head/tools/ceiling-probe-live.py:1017-1019`), so this calibration was hand-authored from the record `grimoires/loa/reports/2026-10-07-opus-5-5-ceiling-probe-cli.json`, which is not in the PR and cannot be checked. The bound was measured through the Bedrock CLI route but governs the `anthropic` HTTP entry; and once calibrated, observed provider verdicts no longer lower the bound (`head/tests/unit/loa-status-providers.bats:272-273`), so a direct-API rejection below 936,000 would recur rather than adapt. Bridgebuilder's budget follows it to 916,000 (`head/.claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts:34`).
**Suggestion:** Commit the probe record beside the catalog (or under `grimoires/loa/reports/`), record `method` as what it was (a partial headless probe, operator-accepted) or add an `operator_note` field, and say in `reprobe_trigger` that any direct-API `PROVIDER_CONTEXT_LIMIT` for this model should re-fire the probe. This is an operator decision; the reviewer flags the evidence gap, not the number.
**Benefit:** A reader of the catalog can tell measured from accepted.

### 4. Tests — two calibrated-entry checks no longer check (cross-model DISS-C-006, confirmed)

- **MEDIUM** (confidence: high) `head/.claude/adapters/tests/test_anthropic_catalog_floor.py:146-148` — for a measured entry `cap = entry["effective_input_ceiling"]` and `expected = min(cap, cw − dmt)`, so the assertion holds for any value satisfying I2; the same at `head/.claude/adapters/tests/test_anthropic_catalog_floor.py:168-169`. Nothing asserts `effective_input_ceiling == min(ceiling_calibration.measured_input_tokens, context_window − default_max_tokens)`.
**File:** also `head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py:459-460`
**Suggestion:** Assert against provenance for measured entries. Note that `test_write_operator_set_changes_only_the_entry_and_replaces_the_shortcut` now `pytest.skip`s permanently on this tree (the catalog is calibrated), and it was the only test validating the written `ceiling_calibration` against `$defs.ceilingCalibration` with `jsonschema` (`head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py:499-501`). Move that schema assertion to the SYNTH-based tests so it keeps running.
**Benefit:** The floor suite guards the calibrated state it was swept to cover.

### 5. Complexity — `_main_cli`

- **MEDIUM** (confidence: high) `head/tools/ceiling-probe-live.py:632-849` — `SIMPLICITY[shrink]`: 218 lines, six nested closures (`step` alone is ~55 lines, `next_target` carries the re-anchor rule), the record dict and the catalog write inline. `write_catalog_operator_set` (`head/tools/ceiling-probe-live.py:402-480`) is 79 lines. The API-path `main()` (`head/tools/ceiling-probe-live.py:490-601`, 112 lines) set the precedent, which is why this is not blocking; a split into bisection / record / write would make the probe's rules testable without a fake CLI. net: -40 lines possible.

### 6. Trust model — the opt-in is read from the reviewed tree (cross-model DISS-C-004)

- **MEDIUM** (confidence: medium) `head/.claude/adapters/loa_cheval/config/loader.py:121-127` — the key is read from `.loa.config.yaml` found by the cwd walk; the agy adapter's own comment notes "the caller's cwd is the reviewed tree" (`head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:147`). A PR branch can set `agy_opt_in: true` and opt the reviewing host into the argv-exposed route. This is within the existing trust model for `.loa.config.yaml` (a branch can also edit `.claude/`), so it is not counted, but the docstring's "never talked into the agy voice by ambient env" states a stronger guarantee than the design provides.
**Suggestion:** Say so in the docstring and the `.loa.config.yaml.example` note, or read the opt-in from an operator-owned layer.

### 7. Documentation and comments

- **LOW** (confidence: high) `head/.claude/adapters/loa_cheval/audit/modelinv.py:498` and `head/.claude/adapters/cheval.py:2834` — comments say `caller | catalog | none`; the resolver returns a fourth value `extra` (`head/.claude/adapters/cheval.py:923-925`) and the payload schema enumerates it (`head/.claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json:755-762`). Comment drift only (see Cross-Model DISS-C-001).
- **LOW** (confidence: high) `head/tools/ceiling-probe-live.py:45-46` — the module docstring still says the bound is written "raw — the api transport applies no safety margin either"; the fr23b commit clamps it (`head/tools/ceiling-probe-live.py:377-399`). Same drift in `head/.claude/data/schemas/model-config-v3.schema.json:306`: `measured_input_tokens` is described as "the value written to probed_ceiling / effective_input_ceiling", which is false whenever the clamp applies (the live entry has 972887 vs 936000).
- **LOW** (confidence: high) `head/.claude/defaults/model-config.yaml:495-501` — a future re-probe replaces only the single `# cycle-127 FR-3: bound measured` line (`head/tools/ceiling-probe-live.py:469-479`, `old_prov`), leaving the six-line hand-written `operator_set (lead, …)` comment stale beside a new value.
- **LOW** (confidence: high) `head/docs/migration/v2.0-model-generation-floor.md:265-274` — the cycle-126 addendum bullet was rewritten in place to describe cycle-127 behaviour, and the cycle-127 section then refers back to it (`:290-291`); migration notes should append, not rewrite history.

### 8. Probe tool — robustness and SIMPLICITY

- **LOW** (confidence: high) `head/tools/ceiling-probe-live.py:261` — `ClaudeHeadlessAdapter._raise_for_error` is called unbound with a `SimpleNamespace(provider=…)` stand-in for `self`. It works today because the method reads only `self.provider` (`head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:519-600`), but any future `self.` use raises `AttributeError`, which the blanket `except Exception` (`:273`) silently classifies as `other`. Prefer a module-level classifier shared by adapter and probe.
- **LOW** (confidence: high) `head/tools/ceiling-probe-live.py:135,144,147,261` — `SIMPLICITY[stdlib]`: `__import__("time")`, `__import__("re")` ×2, `__import__("types")` inline instead of `import` statements.
- **LOW** (confidence: high) `head/tools/ceiling-probe-live.py:503` — `--allow-partial` is accepted on the CLI transport but `_main_cli` never reads it; the api path's message (`:581`) tells operators to pass it. Reject it for `--transport claude-headless` or honour it.
- **LOW** (confidence: high) `head/.claude/adapters/cheval.py:908-911` — the "sets both rungs" WARN fires for HTTP entries carrying `extra.effort`, although the `extra` rung applies only to CLI entries (`:915`); harmless noise.

### 9. Shell planners and status surfaces

- **LOW** (confidence: high) `head/.claude/scripts/run-preflight.sh:204` — when a stage's only voice was gated off, the FAIL detail reads "no credential present and no CLI hop on PATH", which is false in the PF-AGY scenario (agy is on PATH; the cause is the opt-in). The `; not planned:` suffix (`:207`) carries the truth; put it in the primary message.
- **LOW** (confidence: high) `head/.claude/scripts/loa-status.sh:805-806,865` — the google row always reads `agy: opt-in (disabled; …)` regardless of whether `agy` is installed, so the hop column no longer tells an operator whether the binary is present, and the 46-character note overruns the `%-7s` hop column.
- **LOW** (confidence: medium) `head/.claude/skills/bridgebuilder-review/resources/config.ts:190` — `validateApiKeys`'s default `gate = readAgyGate()` reads `.loa.config.yaml` relative to the process cwd, while the pipeline passes `repoRoot` (`head/.claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts:172`); any other caller (e.g. a preflight in `main.ts`, not in this diff) gets a cwd-dependent answer. Make `gate` required.
- **LOW** (confidence: medium) `head/.claude/scripts/flatline-orchestrator.sh:529-536` — `_tertiary_routes_to_agy` matches by name; an operator alias that resolves to `google:gemini-headless` through the catalog bypasses the gate and surfaces as `INVALID_CONFIG` (a failed voice). Resolve through the catalog alias table as `adversarial-review.sh`'s `_adv_hop_canon` does.
- **LOW** (confidence: medium) `head/.claude/adapters/cheval.py:2838-2843` — `_effort_on_wire` (with its lazy import of the private `_effort_for_model`) is evaluated inside the `emit_model_invoke_complete(...)` argument list after a paid call; an exception there loses the MODELINV row (cross-model DISS-C-005). Compute it beforehand under a guard.

---

## Cross-Model Observations

Adversarial dissent: `grimoires/loa/a2a/sprint-1/adversarial-review.json` — two voices (primary `codex-headless` for the configured `gpt-5.5-pro`, companion `claude-headless`), `voices_planned: 2`, `voices_succeeded: 2`, `rejected_count: 0`. Advisory input, triaged:

| Dissent | Claim | Triage |
|---------|-------|--------|
| DISS-C-001 (BLOCKING) | `effort_source: "extra"` would fail payload-schema validation | **Not a defect as stated**: the payload schema in this diff enumerates `extra` (`head/.claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json:755-762`) and `test_modelinv_schema_declares_effort_source` pins it. Only the two comments are stale → Observations §7, LOW. |
| DISS-C-002 | Primary-resolved effort rides every hop; `effort_effective` misreports a CLI fallback | **Confirmed** → Observations §1, MEDIUM. |
| DISS-C-003 | `AgyOptInRequiredError` is a hard-abort in the walk | **Confirmed in mechanics**; the stock `gemini-headless → gemini-api` fallthrough it describes does not exist (`gemini-headless` is a declared chain terminal, `head/.claude/defaults/model-config.yaml:318-321`), but the `prefer-cli` ordering produces the same loss → Changes Required §1, HIGH. |
| DISS-C-004 | Opt-in readable from the reviewed tree's config | **Confirmed, within the existing trust model** → Observations §6, MEDIUM. |
| DISS-C-005 | `_effort_on_wire` inline in the emit call | Plausible, low likelihood → Observations §9, LOW. |
| DISS-C-006 | Calibrated-entry floor tests are tautological | **Confirmed** → Observations §4, MEDIUM. |

## Rejected dissent payloads

- none — the envelope's `rejected_summary` is `[]`, `rejected_sidecars` is `[]`, and no `adversarial-rejected-review*.jsonl` sidecar exists beside it.

---

## Previous Feedback Status

No prior `engineer-feedback.md` existed for this sprint.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Reviewed — changes required | Changes Required §1 (walker skip for the opt-in refusal; `prefer-cli` coverage in the TS and Flatline gates; migration note) |

---

## Acceptance Criteria Check

The sprint's success criterion is "review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict". The PR's own stated requirements (title, `pr/PR.md`, migration doc) were checked as the ACs:

### Task 1.1: sprint-251 operator decisions

| Criterion | Status | Notes |
|-----------|--------|-------|
| FR-1: `hounfour.headless.agy_opt_in` is a YAML boolean, default off, no env override, read by one predicate | Pass | `head/.claude/adapters/loa_cheval/config/loader.py:113-127`; parametrised test over absent/false/"true"/1/true at `test_agy_opt_in_gate.py:62-73`; env override test `:80-83`. |
| FR-1: cheval refuses before discovery/spawn; `health_check` False without a spawn; `validate_config` names the key | Pass | `agy_headless_adapter.py:124-125,261-262,293-298`; tests `:96-110,124-136`. |
| FR-1: planners record the hop as not planned, never failed | **Fail** | Holds for the companion chain, Flatline tertiary, Bridgebuilder, preflight, `/loa` under `prefer-api`/`cli-only`; fails for cheval's own walk and for `prefer-cli` (Changes Required §1) and for the dissent's primary voice (Observations §2). |
| FR-2: `claude-opus-5-5` carries `params.default_effort: high`; schema accepts the five levels | Pass | `model-config.yaml:518-522`; `model-config-v3.schema.json:163-167`; bats V3-add. |
| FR-2: resolved once, caller > catalog > extra > none; `effort_source`/`effort_effective` in MODELINV and dry-run | Pass with defect | `cheval.py:885-925,1519-1523,2833-2843`; `effort_effective` wrong on a CLI fallback (Observations §1). |
| FR-3.1/3.2: `--transport claude-headless` uses the adapter's argv builder plus `--effort low --max-turns 1`, prompt on stdin, needle-verified, measured from usage, clean-only write | Pass | `claude_headless_adapter.py:127-161` (`build_headless_argv`), `tools/ceiling-probe-live.py:167-170,681-734,998-1028`; tests `test_ceiling_probe_cli_transport.py:191-217,248-277`. |
| FR-3.4: floor/status suites read the catalog instead of pinning 180K | Pass with defect | `test_no_literal_opus55_ceiling_pins.py` guards it; two swept assertions became tautological (Observations §4). |
| fr23b: the clean write clamps to `min(measured, context_window − default_max_tokens)`, raw accept kept in `measured_input_tokens` | Pass | `tools/ceiling-probe-live.py:377-399,460-468`; tests `:547-608`. |
| Generated artefacts consistent: catalog checksum, bridgebuilder manifest hashes, dist mirrors TS | Pass | `sha256sum` of `head/.claude/defaults/model-config.yaml` equals the `.checksum`; manifest sha256 for `config.ts`, `multi-model-pipeline.ts`, `truncation.generated.ts` match; `dist/*.js` read against the TS. |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (the TS test's `fixture-not-a-key`, the probe's needle, and the fake CLI are fixtures)
- [x] Input validation at trust boundaries — opt-in accepts only a YAML boolean in Python, yq (`tag == "!!bool"`) and TS; `default_effort` enum-validated in schema and `_valid_effort`; the probe caps captured CLI output at 1 MB and runs the CLI in an empty private cwd with the prompt on stdin
- [x] Authorization — the opt-in defaults off; see Observations §6 for the trust-model caveat on where it is read
- [x] No injection — the yq expressions take the file as an argument, not interpolated text; `execFileSync` (no shell) in TS
- [x] Dependencies — no new dependencies
- [x] Error messages do not leak sensitive data — the refusal names the key, not a value; `_cli_version` truncates to 120 chars

CWE references: none of the findings above is a vulnerability class; the argv exposure that motivates FR-1 is CWE-214 (invocation of process using visible sensitive information), and the PR narrows it.

---

## Code Quality Summary

**Strengths:**
- One predicate for the opt-in, fail-closed, tested at the config layer and at the adapter with discovery/spawn mocks asserted never called.
- `resolve_effort` is a clear chokepoint; the warn-once set avoids per-call log noise.
- The probe records every attempt with cost, verifies accepts with a needle, measures in provider tokens, re-anchors after a tokenizer overshoot, and never writes a partial result.
- Generated artefacts (checksum, manifest, dist) are consistent with their sources.

**Areas for Improvement:**
- The refusal class chosen for FR-1 (`ConfigError`) is a hard-abort in the one place the planners cannot pre-empt — cheval's own walk.
- Several comments and a schema description were not updated with the second (fr23b) commit.
- `_main_cli` should be split; the inline `__import__` idiom and the unbound private-method call are avoidable.

---

## Next Steps

1. Address Changes Required §1 (walker skip or walkable refusal; `prefer-cli` coverage in `isAgyRouted` and `_tertiary_routes_to_agy`; migration note on the default flip).
2. Fix Observations §1 (`effort_effective` from the answering hop) and §7 (stale comments/schema text) in the same round — they are small.
3. Run the Python, bats and node test suites on the PR's base tree and record the fast-gate results (formatter, `tsc --noEmit` for the bridgebuilder rebuild) in `reviewer.md`, with an `## AC Verification` section.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":6,"low":13},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T17:59:00Z"} -->
