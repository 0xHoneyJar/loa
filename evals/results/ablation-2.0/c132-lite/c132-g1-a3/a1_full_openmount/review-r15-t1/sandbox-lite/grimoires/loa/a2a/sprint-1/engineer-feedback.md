# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)

---

## Overall Assessment

The change under review is the sprint-251 "operator decisions" PR (45 files): (FR-1) the agy/Antigravity
headless route becomes opt-in behind `hounfour.headless.agy_opt_in`; (FR-2) `claude-opus-5-5` gains a catalog
`params.default_effort: high` resolved once in cheval with `effort_source` / `effort_effective` telemetry; (FR-3)
`tools/ceiling-probe-live.py --transport claude-headless` measures the input bound through the CLI and the Opus 5.5
catalog entry is rewritten from 180,000 to 936,000 as a calibrated `operator_set` bound.

The work is careful in many places — the Python gate fails closed, the dist bundle is rebuilt from the exact head
sources (manifest hashes verified), the catalog checksum matches, and the new test files are extensive. Two defects
block the merge:

1. The opt-in is enforced only inside the agy adapter, and cheval's chain walk surfaces that refusal immediately.
   Under `hounfour.headless.mode: prefer-cli` the agy hop is the FIRST hop of every Google chain, so a Google voice
   with a valid key now fails with INVALID_CONFIG while every planner (Bridgebuilder, Flatline) still counts it as
   planned. The PR's own contract — "not planned, never a failed voice" — does not hold at the one place that
   actually dispatches.
2. The 936,000 bound was measured through the Bedrock CLI route on a probe whose own outcome was `partial`, yet it
   is written to the Anthropic HTTP entry as a *calibrated* bound — the state in which, by the PR's own policy,
   observed provider limits never lower it — while the PR's own comment records that the token estimator
   under-counts ~1.8× on this tokenizer. cheval will now pre-flight-accept inputs the API rejects, and nothing
   corrects the bound.

`pr/PR.md` carries no `## AC Verification` section and no evidence that the Python, bats or node suites (or
`tsc` / `prettier`) ran; the PR files are the entire input here, so that is recorded as an observation rather than
re-derived. The PR's test suites could not be executed in this sandbox: the workspace tree is a later revision of
the repository and the sandbox hook forbids staging a `.claude/` overlay.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Functionality — cheval dispatches the gated agy hop and the refusal kills the chain

- **HIGH** (confidence: high) `head/.claude/adapters/cheval.py:2544` — the chain walk's `except ChevalError` branch surfaces `AgyOptInRequiredError` (a `ConfigError`, raised at `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:124`) as a terminal INVALID_CONFIG and returns; the walk never skips an agy hop whose opt-in is off, so under `prefer-cli` — where `_apply_mode_transform` orders CLI hops first — a Google chain dies at hop 1 before its HTTP hop is tried.
**File:** `head/.claude/adapters/cheval.py:2544-2552`, `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:122-124`
**Issue:** The gate exists in three planners and one adapter, but not in the dispatcher. `isAgyRouted` (`head/.claude/skills/bridgebuilder-review/resources/config.ts:182`) and `_tertiary_routes_to_agy` (`head/.claude/scripts/flatline-orchestrator.sh:534`) treat a Google model as agy-routed only under `cli-only`; under `prefer-cli` they plan the voice. cheval then resolves the chain as `[gemini-headless, gemini-3.1-pro, …]`, the agy adapter raises before discovery, and the walk returns exit 2 (INVALID_CONFIG) without reaching the HTTP hop that holds the operator's `GOOGLE_API_KEY`.
**Failure scenario:** `.loa.config.yaml` with `hounfour.headless.mode: prefer-cli`, `flatline_protocol.models.tertiary: gemini-3.1-pro`, `agy` on PATH, `agy_opt_in` absent (the shipped default). FTA-2 in `head/tests/unit/flatline-tertiary-agy-opt-in.bats` pins that this tertiary IS planned; Flatline dispatches it; cheval refuses at hop 1; the run is a dropped voice / DEGRADED. Before this PR the same host dispatched agy successfully. The same path affects every Bridgebuilder Google voice and any dissent primary whose chain holds the hop.
**Why This Matters:** The PR's stated invariant (docs/migration line 286: "record the hop as *not planned* … rather than failed") is contradicted at the only component that sends the prompt. Operators who upgrade with agy installed lose their Google voice silently-as-a-failure on the default setting.
**Required Fix:** Plan around the hop in cheval before the walk: when `agy_opt_in_enabled()` is false, drop agy-routed entries from `chain.entries` (recording them as `models_not_planned` / `reason: opt_in_required` in the MODELINV envelope, one WARN per process) and leave a chain that is agy alone untouched so the adapter's refusal remains the answer for an explicit `--model gemini-headless`. Make the planners' "routes to agy" predicate the same rule cheval applies (see Observation 5).
**Reference:** SDD D-1.3 (opt-in default off; planners read `failure_class: opt_in_required` as not planned).

### 2. Catalog — a foreign-transport, partial-probe bound shipped as a calibrated HTTP ceiling

- **HIGH** (confidence: medium) `head/.claude/defaults/model-config.yaml:494` — `effective_input_ceiling: 936000` (and `probed_ceiling: 936000` at :502) with `ceiling_calibration.source: operator_set` / `calibrated_at` set (:504-505) turns the Anthropic HTTP entry for `claude-opus-5-5` into a *calibrated* entry from a measurement taken through `claude-headless` on Bedrock whose tool outcome was `partial` (:496-497); calibrated bounds are never lowered by observed provider limits, so an API account that 429s or 400s at these sizes repeats the failure on every large call.
**File:** `head/.claude/defaults/model-config.yaml:494-513`, `head/tests/unit/loa-status-providers.bats:69`, `head/docs/migration/v2.0-model-generation-floor.md:303-311`
**Issue:** Three facts in the PR's own text combine into a regression: (a) the bound was measured on another transport and account (Bedrock CLI, `global.anthropic.claude-opus-5-5`) and written to the `anthropic` HTTP entry whose `account_limits.tier` is `unverified`; (b) the PR's policy is "calibrated: the measured bound, observations never lower it" (bats:69), removing the self-correction that previously capped an uncalibrated bound at `observed − 1`; (c) the catalog comment itself says the filler "under-counts ~1.8x under the Opus 4.7+ tokenizer" — cheval's pre-flight at `head/.claude/adapters/cheval.py:2219` / `:2267` uses `estimate_tokens` (tiktoken or `len/3.5`), so an input estimated at 900,000 can be ~1.6M provider tokens. The tool added by this very PR refuses to write a `partial` outcome; the hand-written entry bypasses that guard and also records `sample_size: null` (:506) for a five-sample run.
**Failure scenario:** `cheval --model opus` with a 700,000-estimated-token review diff (previously pre-empted at 180,000 and chunked by the caller). cheval dispatches to the Anthropic API; the provider answers 400 `prompt is too long` (measured > 1,000,000) or, on a tier-1/2 key, 429 `input tokens per minute`. `ProviderContextLimitError` writes the observation, but `input_bound` ignores it for a calibrated entry, so the next call of the same size fails identically; the chain falls to `claude-opus-5` (180K cap) which also rejects it, then to `claude-sonnet-5`, then to the CLI. Downstream mounts inherit the value with the catalog.
**Why This Matters:** This is the default `opus` alias for every review/audit dispatch. The 180K cap was conservative; the new value is only correct for the one route and tokenizer-corrected estimate it was measured with.
**Required Fix:** Either keep the HTTP entry uncalibrated (restore `conservative_default` / 180,000 and put the 936,000 measurement in a `claude-headless`/Bedrock-scoped field or report), or make the calibration transport-aware: record `probe_outcome: partial` and `sample_size: 5` structurally, let a verified observed provider limit tighten a bound whose `ceiling_calibration.transport` differs from the HTTP route, and count exactly (or scale by the measured 1.8 ratio) when the estimate is above half of a calibrated bound. Re-run `--transport api` from a keyed host before shipping a calibrated HTTP bound.
**Reference:** cheval I2 invariant (SDD §2.1); FR-3.4 (the probe writes only on `clean`).

---

## Observations

### 1. Configuration / trust boundary

- **MEDIUM** (confidence: high) `head/.claude/adapters/loa_cheval/config/loader.py:122` — `agy_opt_in_enabled` deep-merges `load_system_defaults(root)` (the System Zone `.claude/defaults/model-config.yaml`) under the project config before reading `headless.agy_opt_in`, so a framework update that ships a top-level `headless: {agy_opt_in: true}` would opt every downstream mount in without an operator decision; the docstring (:114) and `.loa.config.yaml.example:743-750` promise a `.loa.config.yaml` boolean only, and the three shell readers and the TS reader read the project file alone.
**Suggestion:** Read the key from `load_project_config(root)` only.
**Benefit:** The opt-in stays the operator's decision; the five readers agree on the source.

- **MEDIUM** (confidence: high) `head/.claude/adapters/loa_cheval/config/loader.py:126` — the Python reader is PyYAML (YAML 1.1: `yes`, `on`, `Yes` parse to `True`, verified locally) while the bash readers (`head/.claude/scripts/flatline-orchestrator.sh:517-522`, `head/.claude/scripts/adversarial-review.sh:2348-2354`, `head/.claude/scripts/loa-status.sh:800-804`, `head/.claude/scripts/run-preflight.sh:154-160`) and `readAgyGate` (`head/.claude/skills/bridgebuilder-review/resources/config.ts:159-178`) use yq v4 (YAML 1.2, `yes` is `!!str`). `agy_opt_in: yes` opts cheval in and leaves every planner reading "off".
**Suggestion:** Pin the accepted spelling to the literal scalar `true` in all readers (reject or warn on any other spelling), and add the `yes`/`on` rows to `test_the_key_is_a_yaml_boolean_default_false`.
**Benefit:** One predicate, one answer, across Python, bash and TS.

### 2. Telemetry correctness (FR-2)

- **MEDIUM** (confidence: high) `head/.claude/adapters/cheval.py:935-936` — `_effort_on_wire` returns the resolved effort for every CLI entry, but only the claude-headless adapter reads `CompletionRequest.effort`; codex-headless (and grok) build `model_reasoning_effort` from `extra.reasoning_effort` alone. With `--effort high` and a codex-headless hop answering, the MODELINV row records `effort_effective: high` although nothing of the kind was sent (or `medium` from the entry's extra was). Relatedly, the primary entry's catalog default rides `base_request.effort` into every fallback hop (`head/.claude/adapters/cheval.py:2319`), so a hop whose own entry declares no default still reports `effort_source: catalog`.
**Suggestion:** Ask the adapter class what it puts on the wire (a `wire_effort(request, model_config)` hook) instead of a provider/kind switch in cheval; codex/grok return their extra value, HTTP non-Anthropic return None.
**Benefit:** `effort_effective` is trustworthy for the effort-vs-outcome analysis D-2.6 motivates.

- **LOW** (confidence: high) `head/.claude/adapters/cheval.py:907-908` — `extra_raw` short-circuits on `extra.effort`, so an invalid `extra.effort` shadows a valid `extra.reasoning_effort`; and the "sets both rungs" WARN fires for HTTP entries whose adapters never read `extra.effort`.
**Suggestion:** Try both keys in order, each validated; gate the WARN on `_is_cli_entry(entry)`.

- **LOW** (confidence: high) `head/.claude/adapters/loa_cheval/audit/modelinv.py:498` and `head/.claude/adapters/cheval.py:2834` — comments say `caller | catalog | none`; the schema and resolver also emit `extra`.
**Suggestion:** Update the comments.

### 3. Bridgebuilder pipeline

- **MEDIUM** (confidence: high) `head/.claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts:422` — the quorum is `models.length − notPlanned.length` whatever produced `notPlanned`. `readAgyGate` (`config.ts:173-174`) swallows every error (yq missing, unreadable or malformed config) as "opt-in off", so a host fault removes a configured `gemini-headless` voice from the expected set and a 2/2 cohort clears a 3-voice merge. In `api_key_mode: strict` (:176) the dropped voice is not even warned — strict promised every configured voice.
**Suggestion:** Carry a `readError` on the gate; a voice removed by a read error stays expected (merge blocked, reason named); warn in strict mode; log the actual reason instead of "agy opt-in off".
**Benefit:** A missing tool can never shrink the quorum.

- **LOW** (confidence: medium) `head/.claude/skills/bridgebuilder-review/resources/config.ts:190` — `validateApiKeys(config, gate = readAgyGate())` defaults to a cwd-relative `.loa.config.yaml`; only the pipeline passes the repo-root path (`multi-model-pipeline.ts:172`), so any other caller (the CLI's key validation) answers "off" when Bridgebuilder runs from another directory.
**Suggestion:** One `loaConfigPathFor(repoRoot)` helper used by every caller; make `gate` required.

### 4. Planner consistency

- **MEDIUM** (confidence: medium) `head/.claude/scripts/adversarial-review.sh:2360`, `head/.claude/scripts/run-preflight.sh:153`, `head/.claude/scripts/loa-status.sh:806` — five readers, three different rules for "routes to agy": the dissent companion filter and preflight recognise the hop only by the name `gemini-headless`; `/loa` marks every `google` provider as gated; Flatline and Bridgebuilder add "any Google model under `cli-only`". With this repository's own `hounfour.headless.mode: cli-only`, run-preflight P3 counts `gemini-3.1-pro` as a usable voice (credential present) while cheval would route it to agy and refuse; the dissent would plan the same companion hop and record a `failed` voice.
**Suggestion:** One shared `routes_to_agy <model> <mode>` predicate (a `lib/agy-gate-lib.sh` sourced by the four scripts, mirrored in `config.ts` and `loader.py`), alias-resolved.

- **MEDIUM** (confidence: medium) `head/.claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts:34` — `maxInput: 916000` is derived from the new ceiling by the generator's fixed `− 20000` margin, but Bridgebuilder's `estimateTokens` is a character heuristic; the PR's own catalog comment measures ~1.8× under-count on this tokenizer, so a review packed to 916,000 estimated tokens is ~1.65M provider tokens and is rejected. The old 160,000 budget absorbed that error inside the 1M window; the new one does not.
**Suggestion:** Scale the Opus 5.5 budget by the measured `tokenizer_ratio` (or use the API-measured bound), and record the ratio beside `measured_input_tokens`.

### 5. Adapter details

- **LOW** (confidence: high) `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:261-270` — `validate_config` appends the opt-in refusal and then still probes PATH, so every default install reports two errors for one cause ("opt-in" and "`agy` CLI not found"); `health_check` (:293) sits under the "Internal: command construction" banner (:290).
**Suggestion:** `return errors` after the opt-in refusal; move `health_check` above the banner.

- **LOW** (confidence: medium) `head/.claude/adapters/loa_cheval/config/loader.py:120` — the gate re-walks the cwd and re-parses both YAML files on every `complete()`, `health_check()` and `validate_config()` call, independently of the configuration cheval already loaded for the invocation (a different `project_root` argument would silently diverge).
**Suggestion:** Resolve once per process (cache per root) or read from the loaded `hounfour` dict the adapter already receives through its `ProviderConfig`.

- **LOW** (confidence: medium) `head/.claude/adapters/loa_cheval/config/loader.py:120` — `root = project_root or _find_project_root()` sits outside the `try` that the docstring (:117-118) describes as "fails closed"; `Path.cwd()` raises `FileNotFoundError` when the working directory has been removed (the code base already handles that case as `cwd_vanished` for the CLI adapters) and `Path.exists()` re-raises `PermissionError`, so the gate escapes `complete()` as a raw exception that cheval's catch-all reports as a retryable API_ERROR instead of the opt-in refusal. (Raised by the companion dissent voice, DISS-C-005; verified against the head source.)
**Suggestion:** Move the root lookup inside the `try`.

### 6. Catalog provenance

- **LOW** (confidence: high) `head/.claude/defaults/model-config.yaml:506` — `sample_size: null` for a run the comment describes as five samples; the `partial` outcome and the 1.8× ratio live only in a comment (:496-497), invisible to `loa-status`, the schema and any reader.
**Suggestion:** Add `probe_outcome: partial`, `sample_size: 5` and `tokenizer_ratio` to `ceiling_calibration` (and to the v3 schema), as the tool's record already carries them.

### 7. Tests

- **LOW** (confidence: high) `head/.claude/adapters/tests/test_anthropic_catalog_floor.py:146` — for a measured entry `cap = entry["effective_input_ceiling"]`, so `expected = min(ceiling, cw − dmt)` and the assertion `ceiling == expected` reduces to the I2 check already made on the next line; the "computed, not a constant" intent is lost for calibrated entries, and `test_legacy_wall_applies_only_to_anthropic_under_the_kill_switch` (:168-169) now compares the lookup against the catalog's own value, which is circular. `head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py:459` skips on the shipped (already calibrated) catalog, so the live-catalog shortcut-replacement path is never exercised in CI.
**Suggestion:** Assert `ceiling == min(measured_input_tokens, cw − dmt)` (the writer's own clamp rule) for measured entries; run the shortcut test against a pre-probe fixture copy of the real catalog instead of skipping.

- **MEDIUM** (confidence: medium) `FAST-GATE:` `pr/PR.md` (the implementation report) names no self-checks — no pytest/bats/node run, no `tsc --noEmit` / `prettier --check`. The dist `.build-manifest.json` hashes match the head sources (verified), which proves the build ran; nothing proves the 1,800 lines of new tests pass. Not re-run here (see Overall Assessment).
**Suggestion:** Record the fast-gate commands and results in the report.

### 8. Complexity

- **MEDIUM** (confidence: high) `SIMPLICITY[shrink]:` `head/tools/ceiling-probe-live.py:632` — `_main_cli` is 215 lines with four nested closures (`step` at :681 nests `for`/`if`/`try` four deep); `write_catalog_operator_set` (:402) is 78 lines with two inner helpers. Function too long: split the bisection driver (`step`, `next_target`), the record builder and the catalog write into module-level functions. Everything else in the PR is lean. net: ~-40 lines possible by lifting the closures and sharing the `_find`/`_set_scalar` helpers with the existing `_write_catalog_file`.

---

## Cross-Model Observations

Adversarial dissent (Phase 2.5) ran on `pr/head.diff` with two voices — primary `gpt-5.5-pro` chain, answered by
`codex-headless`; companion `claude-headless` — `verdict_quality.status: APPROVED`, 2/2 voices, `chain_health: ok`,
envelope `grimoires/loa/a2a/sprint-1/adversarial-review.json`. Eight findings, triaged against the head source:

| Dissent id | Severity | Triage |
|------------|----------|--------|
| DISS-C-001 (companion) / DISS-001 (primary, demoted `out_of_scope`: trigger anchor outside the diff) | BLOCKING / ADVISORY | Real defect — the same chain-walk gap as **Changes Required 1**; counted there, not twice |
| DISS-C-007 | ADVISORY | Real defect — the calibrated 936K HTTP bound; counted as **Changes Required 2** |
| DISS-C-004 | ADVISORY | Real defect — System defaults merged into the opt-in read; Observation 1 (medium) |
| DISS-C-005 | ADVISORY | Real defects — root lookup outside the fail-closed `try` (new LOW under Observation 5, verified) and the YAML 1.1/1.2 spelling divergence (already Observation 1, medium) |
| DISS-C-003 | ADVISORY | Real defect — `effort_effective` on codex/grok hops and the primary default riding fallback hops; Observation 2 (medium, text extended) |
| DISS-C-006 | ADVISORY | Real defect — tautological / skipped / circular ceiling tests; Observation 7 (low, text extended) |
| DISS-C-002 | ADVISORY | Partly not a defect: the voice feared `effort_source: extra` fails the trajectory schema, but `head/.claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json:755-762` already enumerates `extra`; the stale three-value comments stand as Observation 2 (low) |

Advisory voices are input, never counted; every item above that is counted appears once under its own heading.

## Rejected dissent payloads

None — `metadata.rejected_summary` is empty and the named sidecar `adversarial-rejected-review.jsonl` holds no rows.

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| "review the pull request, report each defect it introduces with the file and line it sits on" (sprint.md § Success Criteria) | Pass | 2 high, 8 medium, 8 low findings above, each cited `head/<path>:<line>` |
| "give a merge verdict" | Pass | CHANGES_REQUIRED (two high findings) |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (the TS test uses `fixture-not-a-key`; the bats fixture's `sk-test…` is asserted never printed)
- [x] Input validation at trust boundaries — the opt-in is a strict YAML-boolean read with no env override in every reader; `readAgyGate` uses `execFileSync` with an argv (no shell); yq expressions take the path as an argument
- [x] Authorization — the argv-exposure route (prompt readable via `/proc` by local users) is now off by default and refused before spawn; the one-time WARN only fires when opted in
- [x] No injection — the probe passes the prompt on stdin and runs the CLI in a private temp cwd
- [x] Dependencies — none added
- [x] Error messages don't leak sensitive data — `AgyOptInRequiredError.MESSAGE` names the key only; the probe caps captured output at 1 MB
- [ ] Trust boundary of the opt-in source: System Zone defaults are merged into the decision (Observation 1) — fix before relying on the gate as a security control

---

## Code Quality Summary

**Strengths:**
- The agy gate fails closed in every reader and is enforced before discovery, workspace, WARN or spawn; the test file for it covers the boolean/string/int/unparsable matrix.
- `resolve_effort` is a single chokepoint with one WARN per (model, reason); dry-run and MODELINV expose source and wire value.
- The probe's `clean` contract (needle-verified accept, bracketed rejection, no `other`/budget stop) and the I2 clamp are well specified and well tested on a fake CLI; the record is always written.
- Build artefacts are honest: dist manifest hashes equal the head sources; the catalog checksum equals the file.

**Areas for Improvement:**
- The gate's "routes to agy" rule and its YAML reader are reimplemented five times with three different semantics; the dispatcher implements none of it.
- An operator decision overrode the tool's own `partial` guard and landed as a calibrated HTTP bound; the provenance of that decision is in comments rather than fields.
- Long closure-heavy functions in the probe tool.

---

## Next Steps

1. Plan around gated agy hops in cheval's chain walk (High 1) and unify the "routes to agy" predicate across the planners.
2. Decide the Opus 5.5 HTTP bound: keep it uncalibrated until an API-transport probe, or make calibration transport-aware with structured provenance and a tokenizer-corrected pre-flight (High 2).
3. Address the medium observations (System-defaults merge, YAML 1.1/1.2 spelling, `effort_effective` for codex/grok, read-error quorum, Bridgebuilder budget ratio).
4. Run the fast gate and the three suites; record the commands and results in `grimoires/loa/a2a/sprint-1/reviewer.md` with an `## AC Verification` section.
5. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":8,"low":8},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T23:58:00Z"} -->
