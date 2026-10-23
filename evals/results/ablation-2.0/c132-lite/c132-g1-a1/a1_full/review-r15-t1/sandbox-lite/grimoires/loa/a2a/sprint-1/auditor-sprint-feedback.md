# Sprint 1 Security & Quality Audit

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Scope:** `pr/head.diff` — cycle-127 sprint-251 operator decisions (45 files; FR-1 agy opt-in, FR-2 Opus 5.5 effort default, FR-3 headless ceiling probe + catalog calibration). Citations are `head/<path>:<line>` with line numbers from `pr/head/`.
**Methodology:** Systematic 5-category review (Security, Architecture, Code Quality, DevOps; Blockchain n/a), two-voice security dissent on the diff.
**Inputs:** `pr/PR.md` (implementation report), `grimoires/loa/sprint.md`, `grimoires/loa/a2a/sprint-1/engineer-feedback.md` (review, CHANGES_REQUIRED), `adversarial-audit.json` (this audit's dissent).

> **Prerequisite deviation.** The skill's Phase 0 expects `engineer-feedback.md` to say "All good"; the review verdict is CHANGES_REQUIRED (2 HIGH). The task directs the audit to run regardless, so it ran; this audit therefore also independently re-examines the review's two HIGH findings rather than inheriting them. `known-failures.md` was unreadable at session start (KF-SURFACE warning) — triage proceeded without it.

---

## Executive Summary

The change is well-shaped where it is security-motivated: the agy (Antigravity) `gemini-headless` route — whose `agy -p` invocation puts the whole review prompt on argv, readable by every local account via `/proc` (CWE-214) — becomes opt-in, default off, keyed on a strict YAML boolean with no environment override, and the five planners (dissent, Flatline tertiary, Bridgebuilder, `/loa`, run preflight) agree on the semantics. `build_headless_argv` is one builder for the adapter and the probe, the catalog checksum and the Bridgebuilder build manifest match the head sources, and the new schema fields are enum-tight.

Two defects block. First, the Bridgebuilder budget regenerated from the calibrated catalog (`maxInput: 916000`) mixes units — a provider-measured ceiling minus headroom, compared against Bridgebuilder's chars×0.25 estimate, which the PR's own catalog comment says under-counts the Opus 4.7+ tokenizer by ~1.8× — so large diffs are admitted and then rejected by the provider above the 1M window, after the spend. Second, the opt-in refusal is a `ConfigError` raised from inside cheval's chain walk, where ConfigError hard-aborts; every stock Google `fallback_chain` ends in `google:gemini-headless`, so an upstream Google HTTP failure that walks to the terminal now exits INVALID_CONFIG naming the opt-in — and because the `failure_class` the PR documents as the "machine-readable seam" lives only in `exception.context`, which `_error_json` never serializes, planners cannot read `opt_in_required` off the wire at all.

The dissent (gpt-5.5-pro primary via codex-headless: clean; claude-headless companion: 2 MEDIUM, 3 LOW) raised no CRITICAL/HIGH; its two MEDIUMs are triaged below (one confirmed and merged, one downgraded with its premise refuted).

**Overall Risk Level:** HIGH (two HIGH functional/contract defects; no exploitable security path confirmed)

**Key Statistics:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 5 |
| Low | 10 |

---

## Category Scores (Rubric-Based Assessment)

| Category | Score | Dimensions |
|----------|-------|------------|
| Security | 3.8/5 | IV:4 AZ:4 CI:3 IN:4 AV:4 |
| Architecture | 3.2/5 | MO:3 SC:4 RE:2 CX:3 ST:4 |
| Code Quality | 3.2/5 | RD:3 TC:3 EH:3 TS:4 DC:3 |
| DevOps | 3.5/5 | AU:4 OB:4 RC:3 AC:4 DS:3 |
| Blockchain | n/a | — |
| **Overall** | **3.5/5** | *Security-weighted average* |

**Machine-Parseable Output:** `grimoires/loa/a2a/audits/2026-10-21/findings.jsonl`

---

## Critical Issues (Fix Immediately)

None.

---

## High Priority Issues (Fix Before Production)

### [HIGH-001] Bridgebuilder `maxInput` for `claude-opus-5-5` is in the wrong units — reviews are admitted above the 1M window

**Severity:** HIGH | **Confidence:** high
**Component:** `head/.claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts:34` (also `head/.claude/skills/bridgebuilder-review/dist/core/truncation.generated.js:31`, `head/docs/migration/v2.0-model-generation-floor.md:309`)
**Criterion:** ARCH-RE Resilience / SEC-AV Availability

**Reasoning Trace:**
> `"claude-opus-5-5": { maxInput: 916000, maxOutput: 32000, coefficient: 0.25 }` (truncation.generated.ts:34) — the generated-file header states the rule: "maxInput = effective_input_ceiling − 20000 when the yaml entry carries the v3 ceiling" (truncation.generated.ts:11); 936,000 − 20,000 = 916,000. The catalog ceiling is provider-measured: `measured_input_tokens: 972887` (model-config.yaml:513) and the provenance comment says "the filler under-counts ~1.8x under the Opus 4.7+ tokenizer" (model-config.yaml:497). Bridgebuilder compares `maxInput` against `Math.ceil(text.length * coefficient)` (`truncation.ts` `estimateTokens`) and truncates to `floor(effectiveInputBudget × 0.9)`. The old 160,000 budget sat ~6× below the window so estimate skew was absorbed; the new one sits at the window edge with none.

**Description:** A diff that Bridgebuilder's truncation engine admits at ~824K–916K estimated tokens measures ~1.3–1.65M on the wire for the Opus 4.7+ tokenizer and is rejected by the provider (or by the CLI pre-flight the probe itself recorded at ~1,065,182 tokens). cheval's own pre-flight (`estimate_tokens`, tiktoken/len÷3.5) is the same class of estimate and will not pre-empt either.
**Impact:** Every multi-model Bridgebuilder review of a large PR on `opus` fails at the provider after the prompt is prepared and billed; the chain then walks to `claude-opus-5`, whose 180K ceiling pre-empts. The migration note advertises the broken number (docs:309). Corroboration: the repository's current copy of `scripts/gen-bb-registry.ts` (post-dating this PR) already carries a `MEASURED_TO_ESTIMATE_SAFETY = 1.8` divisor labelled "r251-1 C8 (the units gap)" — the maintainers have since recognised this exact defect; the PR under audit does not contain it.
**Remediation:** In `gen-bb-registry.ts`, for entries whose `ceiling_calibration.measured_input_tokens` is set, emit `maxInput = floor((effective_input_ceiling − 20000) / 1.8 / 1000) × 1000` (≈ 508,000 here); regenerate `truncation.generated.ts` and `dist/`; add a test asserting `maxInput × 1.8 + default_max_tokens ≤ context_window` for every measured entry; correct docs:309.
**References:** CWE-682 Incorrect Calculation — https://cwe.mitre.org/data/definitions/682.html

### [HIGH-002] Opt-in refusal is a `ConfigError` inside the chain walk: hard-abort, masks the upstream failure, and the `failure_class` seam never reaches the wire

**Severity:** HIGH | **Confidence:** high (code path), medium (live frequency)
**Component:** `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:124-125`; contract at `head/.claude/adapters/loa_cheval/types.py:503-516`; walk arm at `head/.claude/adapters/cheval.py:2544-2553`
**Criterion:** CQ-EH Error Handling / ARCH-RE Resilience

**Reasoning Trace:**
> `if not agy_opt_in_enabled(): raise AgyOptInRequiredError()` (agy_headless_adapter.py:124-125). `class AgyOptInRequiredError(ConfigError)` whose docstring promises "`failure_class` (also in `context`) is the machine-readable seam planners read as 'not planned', never as a failed voice" (types.py:503-516). In the walk, `except ChevalError as _e:` records `"error_class": "UNKNOWN"`, prints `_error_json(_e.code, str(_e), retryable=_e.retryable)` and returns (cheval.py:2544-2553) — `_error_json` builds `{"error","code","message","retryable"}` plus explicit kwargs only (cheval.py:142-146); `_e.context` is never passed, and `ChevalError.to_json()` omits it too. The comment two arms up confirms the design: "STATIC misconfig (ConfigError/INVALID_CONFIG) still falls through to the hard-abort arm" (cheval.py:2526-2528). Every stock Google entry's `fallback_chain` terminates in `google:gemini-headless` (model-config.yaml:216, 228, 248, 262, 289). The dissent script's `_companion_failure_class` has no `opt_in_required` class; exit 2 falls to `model_unavailable` (adversarial-review.sh:2979-2995).

**Description:** Scenario: the Flatline tertiary `gemini-3.1-pro` is planned under `prefer-api` (FTA-2 explicitly asserts this), its HTTP hop takes a 429 or 5xx, cheval walks to `gemini-headless`, the adapter raises INVALID_CONFIG. The operator is told to set `agy_opt_in` for what was a rate limit; the MODELINV `models_failed` entry carries `UNKNOWN`; the voice is counted failed. The planner-side filters (`_adv_agy_filter_chain`, `isAgyRouted`, `_tertiary_routes_to_agy`) gate only explicitly named hops or cli-only mode, never a catalog fallback chain. On hosts that have `agy` installed this is also a silent behaviour change: chains that completed yesterday abort today.
**Impact:** The FR-1 acceptance claim "never a failed voice" is false on the one path every stock Google chain takes; the real upstream failure class — which drives retries, breakers and alerting — is replaced by a config refusal. The `failure_class` field the PR documents as machine-readable is unreachable by any consumer of cheval's stderr JSON.
**Remediation:** (a) In the walk, catch `AgyOptInRequiredError` (or any `ChevalError` whose `context.failure_class == "opt_in_required"`) before the generic `ChevalError` arm: append `{"error_class": "OPT_IN_REQUIRED", ...}` to `models_failed`, keep the previous hop's exception as `_last_walk_exception`, and `continue`; or (b) drop `gemini-headless` from the resolved chain at plan time when `agy_opt_in_enabled()` is false. In both cases serialise `failure_class` into `_error_json(...)` for the single-hop refusal, and teach `_companion_failure_class` the class. Add a two-hop test (HTTP 429 → gemini-headless) asserting the exit code and MODELINV class are the upstream's.
**References:** CWE-755 Improper Handling of Exceptional Conditions — https://cwe.mitre.org/data/definitions/755.html; CWE-392 Missing Report of Error Condition — https://cwe.mitre.org/data/definitions/392.html

---

## Medium Priority Issues (Address in Next Sprint)

### [MED-001] The opt-in predicate's authority surface is wider than documented: System-Zone catalog layer, cwd walk, and a root resolution outside the fail-closed guard

**Severity:** MEDIUM | **Confidence:** high
**Component:** `head/.claude/adapters/loa_cheval/config/loader.py:120-126`
**Criterion:** SEC-AZ Authorization / SEC-CI Integrity
**Description:** `merged = _deep_merge(load_system_defaults(root), load_project_config(root))` (loader.py:122) reads one boolean through the whole catalog merge, so a `headless: {agy_opt_in: true}` key in `.claude/defaults/model-config.yaml` — a System-Zone file the operator never edits — opts every project in without touching `.loa.config.yaml`, contradicting the docs ("Set it `true` only where…", the example at `.loa.config.yaml.example:743-750`) and the docstring's "an operator's deliberate choice". `root = project_root or _find_project_root()` (loader.py:120) runs outside the `try`, so a vanished cwd (`Path.cwd()` raising — the codebase has `cwd_vanished` for exactly this) propagates as a raw `FileNotFoundError` rather than the promised fail-closed `False`; in the walk that becomes an `API_ERROR` exit instead of a refusal. The predicate also re-parses both YAML files on every `complete()`, `health_check()` and `validate_config()`. Confirmed by cross-model review (DISS-C-002) and by the review (Observation §2).
**Impact:** The control whose purpose is to keep the review diff off a world-readable argv (CWE-214) can be flipped from a layer the operator does not own; a tampered or mis-shipped catalog is a plausible vector because the catalog is the one System-Zone file this PR also hand-edits.
**Remediation:** Read `load_project_config(root)` alone; move `_find_project_root()` inside the `try`; memoise per `project_root`.
**References:** CWE-15 External Control of System or Configuration Setting — https://cwe.mitre.org/data/definitions/15.html; CWE-214 — https://cwe.mitre.org/data/definitions/214.html

### [MED-002] The probe spawns the CLI with the full parent environment, not the adapter's stripped one

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `head/tools/ceiling-probe-live.py:214-227` (`env = {**os.environ, "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1"}` at :217)
**Criterion:** SEC-CI Confidentiality / DO-DS Deployment Safety
**Description:** The adapter's contract is "never inherit subprocess env" — `build_headless_subprocess_env()` strips `ANTHROPIC_API_KEY` and the auth-mode selectors (`providers/base.py:794-819`). `_run_capped` hands the CLI everything in the shell. With a key present, `claude` may authenticate to the direct API while the record stamps `host_route` / `cli_model` as Bedrock from the wrapper's env vars (`_default_host_route`, `_route_env`), so the written `reprobe_trigger` ("measured through claude-headless on Bedrock") describes a transport the measurement never used. The docstring claims the probe "runs the headless adapter's own argv"; the environment is half of what the adapter dispatches (D-3.9).
**Impact:** A credential is forwarded to a subprocess that should be OAuth/Bedrock-authed, and the catalog provenance — which decides when the bound is re-probed — can be wrong.
**Remediation:** `env = build_headless_subprocess_env(); env["CLAUDE_CODE_DISABLE_AUTO_MEMORY"] = "1"`; refuse (or at least record) `--transport claude-headless` when `ANTHROPIC_API_KEY` is set.
**References:** CWE-526 Cleartext Storage of Sensitive Information in an Environment Variable — https://cwe.mitre.org/data/definitions/526.html; CWE-668 Exposure of Resource to Wrong Sphere — https://cwe.mitre.org/data/definitions/668.html

### [MED-003] A CLI/Bedrock measurement is written to the HTTP `anthropic:claude-opus-5-5` entry

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `head/.claude/defaults/model-config.yaml:494`, `:502-513`
**Criterion:** ARCH-RE Resilience / SEC-AV Availability
**Description:** `effective_input_ceiling: 936000` on the HTTP entry comes from `transport: claude-headless`, `cli_model: "global.anthropic.claude-opus-5-5"` (model-config.yaml:510-512). `_lookup_max_input_tokens("anthropic", …)` reads this field for direct-API callers (cheval.py:828-), and policy says a calibrated bound is never lowered by observation (LSP-5). Direct-API accounts with low ITPM lose the 180K pre-emption and 429 on the wire; `account_limits.tier: unverified, itpm: null` remains. The entry's own `reprobe_trigger` admits the gap.
**Impact:** Availability regression for the route the entry actually describes; a 5× larger prompt per call (~$3.74 input at the catalog price) is now admitted on the HTTP path with no account check.
**Remediation:** Keep the HTTP entry at the policy cap until an `--transport api` probe runs, or carry a per-transport ceiling; gate on `account_limits.itpm` when known.
**References:** CWE-770 Allocation of Resources Without Limits or Throttling — https://cwe.mitre.org/data/definitions/770.html

### [MED-004] Catalog tests now read the value under test; the live-catalog writer test skips permanently

**Severity:** MEDIUM | **Confidence:** high
**Component:** `head/.claude/adapters/tests/test_anthropic_catalog_floor.py:146-148`; `head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py:459`
**Criterion:** CQ-TC Test Coverage
**Description:** `cap = entry["effective_input_ceiling"] if _measured(entry) else CEILING_CAP; expected = min(cap, cw − dmt)` (floor.py:146-147) — for measured entries the equality collapses to `eic ≤ cw − dmt`, which line 148 already asserts; a wrong hand-edited ceiling passes. `pytest.skip("the catalog is already calibrated (the lead's probe write landed)")` (transport.py:459) fires on every run from now on, so `write_catalog_operator_set` against the live catalog layout is never exercised — only the SYNTH copy.
**Impact:** The FR-3.4 sweep guards the invariant, not the measured value; the one layout the writer will actually meet in the field has no coverage.
**Remediation:** For measured entries assert `eic == min(measured_input_tokens, cw − dmt)` and `probed_ceiling == eic`; replace the skip with a fixture that resets the live entry to its pre-probe shape.
**References:** CWE-1164 Irrelevant Code — https://cwe.mitre.org/data/definitions/1164.html

### [MED-005] SIMPLICITY[shrink] — `_main_cli` (216 lines, six closures over `nonlocal` state) and `write_catalog_operator_set` (~80 lines of line-level YAML surgery)

**Severity:** MEDIUM | **Confidence:** high
**Component:** `head/tools/ceiling-probe-live.py:632-847`; `:402-480`
**Criterion:** ARCH-CX Complexity / CQ-RD Readability
**Description:** `_m`, `_size`, `current_ok`, `current_fail`, `step`, `next_target` share `samples`, `ratio`, `spent_micro` through closures; the tolerance/re-anchor logic is only readable with the whole graph in view. `write_catalog_operator_set` splices YAML text by indent arithmetic with three nested finders. Both exceed the 50-line threshold without a justification marker.
**Impact:** The bisection cannot be unit-tested below the whole-run level; the YAML surgery is the code path that writes the System-Zone catalog.
**Remediation:** Lift bisection state into a small dataclass with `step`/`next_target` as methods; split the writer into "replace scalars", "replace calibration block", "replace provenance comment".
**References:** CWE-1120 Excessive Code Complexity — https://cwe.mitre.org/data/definitions/1120.html

---

## Low Priority Issues (Technical Debt)

### [LOW-001] Schema description contradicts the fr23b clamp
**Component:** `head/.claude/data/schemas/model-config-v3.schema.json:306`
**Description:** `measured_input_tokens` is "the value written to probed_ceiling / effective_input_ceiling"; the shipped entry has 972,887 vs 936,000 (model-config.yaml:502, :513) and `i2_clamped` exists precisely to differ. Confidence: high.
**Remediation:** "the raw accepted size; probed/effective = min(this, context_window − default_max_tokens)".
**References:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html

### [LOW-002] Stale comments on calibrated/derived values
**Component:** `head/.claude/defaults/model-config.yaml:494` (`# cycle-124 FR-3 (SDD §2.1): see claude-fable-5-1` on a calibrated value — `_set_scalar` preserves trailing comments, so the writer would keep it too); `head/.claude/adapters/cheval.py:2834` and `head/.claude/adapters/loa_cheval/audit/modelinv.py:498` document `effort_source` as `caller | catalog | none` while `resolve_effort` and the schema emit a fourth value `extra`. Confidence: high.
**References:** CWE-1059 — https://cwe.mitre.org/data/definitions/1059.html

### [LOW-003] `method: probed_headless` on a value the tool refused to write
**Component:** `head/.claude/defaults/model-config.yaml:509` (outcome `partial` per :496)
**Description:** The record is honest about `operator_set` but `method` claims the tool's method; the tool writes `probed_headless` only on a `clean` outcome. Confidence: high.
**Remediation:** Omit `method`, or add the `partial` outcome to `reprobe_trigger`.
**References:** CWE-1059 — https://cwe.mitre.org/data/definitions/1059.html

### [LOW-004] Effort rungs are validated unevenly at the "one chokepoint"
**Component:** `head/.claude/adapters/cheval.py:909-913`, `:922`
**Description:** `if explicit: return explicit, "caller"` returns the caller value unvalidated (argparse is trusted; any programmatic `Namespace` bypasses `_EFFORT_LEVELS`, and the value reaches `--effort <value>` on the CLI argv and the MODELINV envelope); `extra.effort` is `strip().lower()`-normalised (:922) but `params.default_effort` is not, so `"High"` is accepted in one rung and rejected in the other; the "sets both" WARN (:909) fires for HTTP entries whose `extra.effort` no adapter reads. Confirmed by cross-model review (DISS-C-003). Confidence: medium.
**Remediation:** Run every rung through `_valid_effort`; normalise both; warn only for CLI entries without a caller value.
**References:** CWE-20 Improper Input Validation — https://cwe.mitre.org/data/definitions/20.html

### [LOW-005] Effort is resolved once against the primary and rides every fallback hop
**Component:** `head/.claude/adapters/cheval.py:1519-1522`, `:2838-2845`
**Description:** A fallback entry's own `params.default_effort` is never applied; `effort_effective` is recomputed for `final_model_id` with the primary's value. Low impact today (every live Anthropic hop accepts the five levels; other providers map to None). Confidence: medium.
**References:** CWE-684 Incorrect Provision of Specified Functionality — https://cwe.mitre.org/data/definitions/684.html

### [LOW-006] `build_headless_argv` re-exposes the argv-prompt surface as a one-argument choice
**Component:** `head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:127-161` (`*([] if prompt is None else [prompt])` at :145)
**Description:** The cycle-126 fix moved the prompt to stdin to close `/proc/<pid>/cmdline` exposure; the new public module-level builder accepts `prompt=` and puts it after `-p`. Both current callers pass `None`, but the only thing keeping the diff off argv is a default argument. Confirmed by cross-model review (DISS-C-004). Confidence: medium.
**Remediation:** Drop the `prompt` parameter (stdin is the only transport), or assert `prompt is None` with a comment naming the exposure.
**References:** CWE-214 — https://cwe.mitre.org/data/definitions/214.html

### [LOW-007] The provenance comment splices unquoted operator strings into the catalog
**Component:** `head/tools/ceiling-probe-live.py:467-469`
**Description:** `provenance = f"        # cycle-127 FR-3: bound measured {day} … ({route}, {cli_model}) …"` — `route` derives from `--host-route` and `cli_model` from `--cli-model` or `ANTHROPIC_DEFAULT_*_MODEL`; a newline in either breaks out of the comment into a YAML line in the System-Zone catalog. The scalar fields are safe: `reprobe_trigger`, `cli_version`, `cli_model` go through `json.dumps` (valid double-quoted YAML) and `cli_version` is first-line-only, 120 chars. Operator-controlled input into the operator's own file, hence LOW; the dissent's broader claim (DISS-C-005) is otherwise refuted. Confidence: medium.
**Remediation:** Strip `\r\n` from `route` and `cli_model` before formatting the comment.
**References:** CWE-74 Injection — https://cwe.mitre.org/data/definitions/74.html

### [LOW-008] Opt-in enforced per method rather than at one construction seam
**Component:** `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:124`, `:261`, `:295`
**Description:** The gate is repeated in `complete`, `validate_config` and `health_check`. The base `HeadlessCLIAdapter` has exactly those three public entry points (`headless_cli.py:359, 460, 479`), so there is no unguarded path today — the dissent's MEDIUM premise (DISS-C-001) is refuted on that point — but a future base-class method would be unguarded by default, and three test modules monkeypatch the predicate to keep the opted-in path alive. Confidence: high (design note, not a present defect).
**Remediation:** Gate once in `__init__`/`get_adapter` (raise or return a refusing stub), or in `HeadlessCLIAdapter._dispatch`.
**References:** CWE-657 Violation of Secure Design Principles — https://cwe.mitre.org/data/definitions/657.html

### [LOW-009] `_classify` calls an instance method with a fake `self`
**Component:** `head/tools/ceiling-probe-live.py:261-262`
**Description:** `cha.ClaudeHeadlessAdapter._raise_for_error(SimpleNamespace(provider="claude-headless"), returncode=…, stderr=…, parsed=…)` couples the probe to the private method's exact use of `self`; any attribute the adapter adds breaks the classifier silently (an `AttributeError` lands in the `except Exception` arm as `kind: other`). Also `__import__("time")` / `__import__("re")` at module level (:135, :144, :148) instead of imports. Confidence: high.
**Remediation:** Make `_raise_for_error` a `@staticmethod` taking `provider`, or instantiate the adapter.
**References:** CWE-1061 Insufficient Encapsulation — https://cwe.mitre.org/data/definitions/1061.html

### [LOW-010] `LOA_HEADLESS_MODE` lowers the Bridgebuilder merge quorum
**Component:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:176`, `:180-183`; `head/.claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts:422`
**Description:** `mode: process.env.LOA_HEADLESS_MODE || mode || "prefer-api"` and `isAgyRouted` treat every Google voice as agy-routed under `cli-only`; `mergeBlocked` then compares against `models.length − notPlanned.length`. So an environment variable — not the config — removes configured voices from the count that may clear a merge. The direction is fail-closed for the opt-in itself (nothing in env opts in), and the same env precedence exists in cheval, but the docs say "verdict quality counts planned voices only" without naming this env input. Confidence: low (requires CI env control, which already implies broader control).
**Remediation:** Read `mode` from the config file only in Bridgebuilder, or log the env override with the not-planned line.
**References:** CWE-807 Reliance on Untrusted Inputs in a Security Decision — https://cwe.mitre.org/data/definitions/807.html

---

## Observations

No HIGH or CRITICAL findings were demoted here (`excluded: 0`). The review trailer's `excluded` is 0; `excluded_confirmed: 0`.

- **Process:** `pr/PR.md` (the implementation report) carries no `## AC Verification` section and states no formatter / type-check / pytest / bats results. The dist and build manifest hashes match the head sources, so the TS build ran; nothing else is evidenced.
- **Security property that holds:** the opt-in itself is strict in every reader — Python `is True` (loader.py:126), Go-yq `tag == "!!bool" and . == true` in four scripts (adversarial-review.sh:2353, flatline-orchestrator.sh:525, loa-status.sh:801, run-preflight.sh:157), python-yq `== true` (run-preflight.sh:158), TS `parsed.opt === true` (config.ts:170); the `"true"` string case is tested in each. `AgyOptInRequiredError.MESSAGE` names the key only — no secret in the message.
- **Integrity:** `model-config.yaml.checksum` (`17f75f07…`) matches `sha256sum` of the head catalog; the Bridgebuilder `.build-manifest.json` records the head sources.
- **Bats seam:** `_providers_config_file` (loa-status.sh:791) is gated on `BATS_TEST_FILENAME`/`BATS_VERSION` like the two pre-existing seams beside it (:732, :782) — consistent with the file's convention, display-only.

---

## Cross-Model Security Observations

Dissent: `adversarial-audit.json` — primary `gpt-5.5-pro` (answered by `codex-headless`, status `clean`, no findings), companion `claude-headless` (`succeeded`, `counted_as: independent_voice`), `voices_planned: 2`, `voices_succeeded: 2`, `degraded: false`, `rejected_count: 0`. Not DEGRADED_SECURITY_REVIEW.

| Dissent | Severity | Triage |
|---------|----------|--------|
| DISS-C-001 — opt-in enforced per method, not at the registry seam | MEDIUM | Premise partly refuted (the base class has exactly the three guarded entry points); kept as design note → LOW-008 |
| DISS-C-002 — cwd walk + System-defaults layer flip the gate; `_find_project_root()` outside the fail-closed `try` | MEDIUM | Confirmed → MED-001 (merged with review Observation §2) |
| DISS-C-003 — caller rung returns `explicit` unvalidated | LOW | Confirmed → LOW-004 |
| DISS-C-004 — `build_headless_argv(prompt=…)` re-opens the argv-prompt surface | LOW | Confirmed → LOW-006 |
| DISS-C-005 — operator strings spliced into the catalog unescaped | LOW | Partly refuted (scalars are `json.dumps`-quoted); the provenance comment line is the one unquoted sink → LOW-007 |

Review HIGHs re-examined independently: both confirmed (HIGH-001, HIGH-002), the second with an additional defect (the `failure_class` seam is never serialised).

## Rejected dissent payloads

None. `metadata.rejected_summary` is empty, `metadata.rejected_sidecars` is empty, and no `adversarial-rejected-audit*.jsonl` sidecar exists beside the envelope.

---

## Security Checklist Status

### Secrets & Credentials
- [x] No hardcoded secrets (dissent secret scan and inspection of head sources)
- [ ] Probe subprocess inherits `ANTHROPIC_API_KEY` from the shell (MED-002)

### Authentication & Authorization
- [x] agy route defaults off; opt-in is a strict YAML boolean, no env override, fail-closed on unreadable config
- [ ] Opt-in readable from the System-Zone catalog layer (MED-001)

### Input Validation
- [x] yq reads are tag-checked; probe refuses non-positive ceilings and entries without `context_window`; schema enums for `default_effort`, `method`, `transport`, `measured_input_tokens`
- [ ] Caller effort rung unvalidated at the chokepoint (LOW-004); provenance comment unquoted (LOW-007)

### Data Privacy
- [x] Prompt travels on stdin for `claude -p`; argv exposure for `agy -p` is now opt-in and documented (CWE-214)
- [x] Error messages name the config key only; env-var secrets redacted in the walk's catch-all

### Supply Chain
- [x] No new dependencies; dist regenerated and manifest matches; catalog checksum matches

### API Security
- [x] Budget caps unchanged (per-voice `budget_cents`); transient-class retry with backoff in the probe
- [ ] Bridgebuilder budget admits payloads above the provider window (HIGH-001); HTTP ceiling raised 5× without an account check (MED-003)

---

## Threat Model Summary

**Trust Boundaries:** operator config (`.loa.config.yaml`) → cheval/planners; System-Zone catalog → cheval ceilings and Bridgebuilder budgets; local process table (`/proc`) ↔ `agy -p` argv; the probe's shell env → `claude` subprocess.

**Attack Vectors:** a tampered catalog opting the agy route in (MED-001: medium); credential forwarded to a CLI subprocess (MED-002: medium); oversized prompts billed then rejected (HIGH-001: availability/cost); operator strings into the catalog comment (LOW-007: low).

**Mitigations present:** strict boolean opt-in across six readers; stdin prompt transport for claude; `json.dumps`-quoted catalog scalars; atomic catalog write; budget caps.

**Residual Risks:** masked upstream failures behind the opt-in refusal (HIGH-002); wrong pre-emption bound on the direct-API route (MED-003).

---

## Documentation Audit

No `documentation-coherence-*.md` reports exist in this frozen workspace; verified manually. `.loa.config.yaml.example:743-750` documents the opt-in and its argv exposure; `docs/migration/v2.0-model-generation-floor.md:276-311` documents all three decisions — but advertises the wrong Bridgebuilder budget (HIGH-001) and the HTTP-entry bound as if route-independent (MED-003). Schema description contradicts the clamp (LOW-001). No CHANGELOG in the repository; the migration doc's "(unreleased)" addendum is the release note.

---

## Positive Findings

- One predicate, one argv builder, one effort chokepoint — the stated D-2.2 / D-3.9 shapes exist and are pinned by tests (`build_headless_argv` byte-for-byte; `test_no_literal_opus55_ceiling_pins.py`).
- Fail-closed everywhere the opt-in is read, with the `"true"`-string case covered in every reader (Python, four shell scripts, TS, bats, pytest).
- The probe's `clean`/`partial` discipline: the catalog is written only on a verified, bracketed, needle-echoed measurement, clamped to I2, atomically.
- Verdict-quality accounting treats a not-planned voice as neither valid nor missing in Bridgebuilder, the dissent and Flatline.

---

## Recommendations

### Immediate (24 Hours)
1. HIGH-001: units-correct `maxInput` for measured entries in `gen-bb-registry.ts`; regenerate `truncation.generated.ts` + `dist/`; fix docs:309; add the `maxInput × ratio + default_max_tokens ≤ context_window` test.
2. HIGH-002: handle `opt_in_required` in the chain walk (skip-and-continue, upstream error preserved) or filter the hop at plan time; serialise `failure_class`; add the two-hop test; teach `_companion_failure_class` the class.

### Short-Term (1 Week)
1. MED-001: read the project layer only, move root resolution inside the guard, memoise.
2. MED-002: `build_headless_subprocess_env()` in the probe; refuse the CLI transport with a key present.
3. MED-003: per-transport ceiling or keep the HTTP entry at the policy cap until an API probe.
4. MED-004: assert the measured value; un-skip the live-catalog writer test with a reset fixture.

### Long-Term (1 Month)
1. MED-005: dataclass the bisection; split the catalog writer.
2. LOW-004..010 as listed; add `## AC Verification` and fast-gate results to the implementation report.

---

## Verdict

**CHANGES_REQUIRED**

**Next Steps:**
1. Fix HIGH-001 and HIGH-002 via `/implement sprint-1`; regenerate the Bridgebuilder twin and dist.
2. Run pytest, bats, `tsc --noEmit`, `prettier --check`; state the results and an `## AC Verification` walkthrough in the implementation report.
3. `/review-sprint sprint-1` then `/audit-sprint sprint-1`.

---

**Audit Completed:** 2026-10-21T17:30:09Z
**Next Audit Recommended:** on the next sprint-1 submission
**Remediation Tracking:** `grimoires/loa/a2a/audits/2026-10-21/`

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":5,"low":10},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T17:30:09Z"} -->
