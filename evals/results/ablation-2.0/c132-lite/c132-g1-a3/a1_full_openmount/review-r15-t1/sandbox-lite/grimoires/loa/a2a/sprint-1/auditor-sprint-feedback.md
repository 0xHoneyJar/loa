# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Review Feedback:** grimoires/loa/a2a/sprint-1/engineer-feedback.md (CHANGES_REQUIRED: 2 high, 8 medium, 8 low, 0 excluded)

---

## Verdict: CHANGES_REQUIRED

---

## Pre-flight and scope

- **Prerequisite deviation (recorded, not hidden).** Phase 0 requires the review to say "All good". The review verdict is
  CHANGES_REQUIRED. The task brief for review-r15 directs the audit to run regardless and write this file, so the audit
  proceeded; the deviation is recorded here and in NOTES.md. No `COMPLETED` marker is written (the verdict forbids it anyway).
- **Input.** `pr/head.diff` (45 files, 3,847 diff lines, sha256 `a7ef6850…48127`), `pr/base/`, `pr/head/`, `pr/PR.md`.
  Every citation below is `head/<path>:<line>` with lines from `pr/head/`. The workspace tree is a later revision of the
  repository (its `cheval.py` already carries a `_plan_around_agy` fix tagged "review r251-1 G1"); it was used only to read
  untouched modules (`routing/ceiling.py`, `routing/chain_resolver.py`) and every finding was re-verified in `pr/head/`.
- **Not run.** The PR's pytest / bats / node suites were not executed: the workspace is not the PR's tree and the sandbox
  forbids staging a `.claude/` overlay. Verification is static (source reading) plus three local checks: the catalog
  checksum (`sha256sum` of `head/.claude/defaults/model-config.yaml` equals the shipped `.checksum`, verified), PyYAML's
  YAML 1.1 boolean set (`yes`/`on` → `True`, verified) against yq v4.40.5 (`yes` → off, verified), and the dist manifest hashes
  (verified by the review; not re-derived).
- **Guardrails.** `guardrails-orchestrator.sh --skill auditing-security` → `PROCEED`. `security-audit-scope.sh` emitted no
  parseable JSON for this tree (its categories were not needed: the surface is the diff).
- **Known-failures surface** `grimoires/loa/known-failures.md` is absent (KF-SURFACE warning at session start); triage was
  done without it.
- **Documentation audit.** No `grimoires/loa/a2a/subagent-reports/documentation-coherence-*.md` exists; the brief states the
  PR files are the entire input. Documentation was verified manually: `docs/migration/v2.0-model-generation-floor.md:286-320`
  and `.loa.config.yaml.example:743-750` describe the security-relevant change (argv exposure, opt-in default) accurately,
  except for the overclaim named in MED-002. No secrets or internal URLs in docs or comments.

## Executive Summary

The PR lands three operator decisions: (FR-1) the agy/Antigravity headless route — whose prompt travels on `agy -p`'s argv,
readable by every local account via `/proc` — becomes opt-in behind `hounfour.headless.agy_opt_in`; (FR-2) `claude-opus-5-5`
gets a catalog `params.default_effort: high` resolved once in cheval with `effort_source` / `effort_effective` telemetry;
(FR-3) a headless-CLI ceiling probe, and the Opus 5.5 HTTP entry rewritten from 180,000 to a *calibrated* 936,000 bound.

Security posture of the opt-in itself is good at the adapter: the gate is checked before any discovery, workspace, WARN or
spawn (`head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:123-124`); every reader accepts only a YAML
boolean `true`; there is no environment override; the TS reader uses `execFileSync` with an argv (no shell); no credential
is added or printed; the probe sends its prompt on stdin in a private cwd and caps captured output at 1 MB. No hardcoded
secret, no injection reachable from review content, no new network surface.

Two defects block the merge. First, the gate exists in three planners and one adapter but not in the dispatcher: cheval's
chain walk treats the opt-in refusal as a terminal `INVALID_CONFIG` and never plans around the hop, so under
`hounfour.headless.mode: prefer-cli` (CLI hops first) every Google chain with a valid HTTP key dies at hop 1 while the
planners still count the voice as planned — the PR's own "not planned, never a failed voice" contract fails at the one
component that sends prompts. Second, the 936,000 bound was measured through the Bedrock CLI on a probe whose own outcome
was `partial`; the tool this PR adds refuses to write a `partial` result, yet the value was hand-written to the Anthropic
HTTP entry as a *calibrated* bound — the state in which, by the PR's own policy, observed provider limits never lower it —
while the PR's own comment records that cheval's token estimator under-counts ~1.8× on this tokenizer. A safeguard added
by this PR was bypassed in this PR, and the self-correction that protected the uncalibrated bound is gone for the default
`opus` alias.

Eight medium findings follow, two of them security trust-boundary gaps in the opt-in read (System-Zone defaults merged into
an operator decision; the decision read from the cwd-walked, possibly untrusted, tree), one a fail-open merge quorum in
Bridgebuilder, one a YAML 1.1/1.2 interpretation conflict between the Python reader and the yq readers.

**Security Issues Found:**

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 8 |
| Low | 10 |

Excluded (speculative, low confidence): 0. Review's excluded confirmed: 0 (the review trailer carries `excluded: 0`).

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] cheval dispatches the gated agy hop and the refusal kills the whole chain

**Severity:** HIGH — **Confidence:** high
**File:** `head/.claude/adapters/cheval.py:2544-2552`; raise site `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:123-124`; type `head/.claude/adapters/loa_cheval/types.py:503-518`
**Category:** Architecture / Availability (SEC-AV)
**Issue:** `AgyOptInRequiredError` is a `ConfigError` (`class AgyOptInRequiredError(ConfigError)`, types.py:503). The
chain walk's generic arm reads:

```python
            except ChevalError as _e:
                # Non-retryable typed cheval error — surface immediately.
                ...
                print(_error_json(_e.code, str(_e), retryable=_e.retryable), file=sys.stderr)
                return EXIT_CODES.get(_e.code, 1)
```

(`cheval.py:2544-2552`). Nothing before the walk drops agy-routed entries from `chain.entries` when the opt-in is off
(grep of `head/.claude/adapters/cheval.py` for `opt_in`, `AgyOptIn`, `not_planned`: no hits outside the import of the
error type). `routing/chain_resolver.py` orders `cli + http` under `prefer-cli` (`_apply_mode_transform`, workspace copy,
unchanged by this PR), so for a Google HTTP model the `gemini-headless` hop is hop 1. The adapter raises before discovery,
the walk returns exit 2, and the HTTP hop holding the operator's `GOOGLE_API_KEY` is never tried.
**Failure scenario:** `.loa.config.yaml` with `hounfour.headless.mode: prefer-cli`, `flatline_protocol.models.tertiary:
gemini-3.1-pro`, `agy` on PATH, `agy_opt_in` absent (the shipped default). `head/tests/unit/flatline-tertiary-agy-opt-in.bats:13-22`
(FTA-2) pins that under `prefer-api` this tertiary IS planned and `_tertiary_routes_to_agy`
(`head/.claude/scripts/flatline-orchestrator.sh:534`) gates only `cli-only`; the same rule in Bridgebuilder
(`head/.claude/skills/bridgebuilder-review/resources/config.ts:182`). Flatline/Bridgebuilder dispatch the voice; cheval
refuses at hop 1 → a dropped voice / DEGRADED verdict on every run, on a host that dispatched successfully before this PR.
**Impact:** Availability regression of multi-model verdicts on the default setting; the PR's documented invariant
(`head/docs/migration/v2.0-model-generation-floor.md:286-290`, "record the hop as *not planned* … rather than failed") is false
at the dispatcher. Cross-model: the review round's companion dissent raised this as BLOCKING (DISS-C-001); this round's
dissent did not repeat it. The workspace's later revision carries `_plan_around_agy` for exactly this gap, which corroborates
the defect in head.
**Fix:** Before the walk, when `agy_opt_in_enabled()` is false, remove agy-routed entries from the chain and record them as
`models_not_planned: [{model, provider, reason: opt_in_required}]` in the MODELINV envelope (one WARN per process); leave a
chain that is agy-only untouched so an explicit `--model gemini-headless` still gets the adapter's refusal. Give the planners
the same "routes to agy" predicate cheval applies (see MED-005).
**Reference:** CWE-755 Improper Handling of Exceptional Conditions — https://cwe.mitre.org/data/definitions/755.html ;
OWASP A05:2021 Security Misconfiguration — https://owasp.org/Top10/A05_2021-Security_Misconfiguration/

### [HIGH-002] A partial, foreign-transport probe shipped as a calibrated HTTP ceiling, bypassing the tool's own guard

**Severity:** HIGH — **Confidence:** medium
**File:** `head/.claude/defaults/model-config.yaml:494` (`effective_input_ceiling: 936000`), `:502` (`probed_ceiling: 936000`),
`:504-505` (`source: operator_set`, `calibrated_at: "2026-10-07T09:29:07Z"`), `:496-497` (comment: outcome `partial`,
~1.8× under-count); policy `head/tests/unit/loa-status-providers.bats:67-69`; probe guard `head/tools/ceiling-probe-live.py:805-807`
**Category:** Architecture / Availability (SEC-AV), Integrity of a safety bound
**Issue:** The entry's own comment reads: "the tool's own outcome was `partial` — the $20 budget cap stopped the bisection
before the 16K tolerance (the filler under-counts ~1.8x under the Opus 4.7+ tokenizer)" (model-config.yaml:495-497). The tool
added by this PR writes the catalog only on `clean` (`ceiling-probe-live.py:805`: `if outcome == "clean" and
args.write_catalog`), and `test_a_completion_without_the_needle_is_unverified_and_partial` /
`test_budget_cap_stops_with_partial_and_writes_nothing` pin that a partial record never touches the catalog. The value was
written by hand anyway, to the `anthropic` HTTP entry (`account_limits.tier: unverified`, :516) from a measurement through
`claude-headless` on Bedrock (`cli_model: global.anthropic.claude-opus-5-5`, :511). The PR's policy for a calibrated entry is
"the measured bound, observations never lower it" (loa-status-providers.bats:69); `routing/ceiling.input_bound` (workspace
copy, unchanged) returns `basis="calibrated"` for any entry with `calibrated_at` and a `source` in
`operator_set|empirical_probe`, ignoring `observed`. cheval's pre-flight (`head/.claude/adapters/cheval.py:2220`, `:2268`) uses
`estimate_tokens`, the estimator the PR's own comment says under-counts ~1.8× on this tokenizer.
**Failure scenario:** `cheval --model opus` with a review estimated at 700,000 tokens (pre-PR: pre-empted at 180,000 and
chunked by the caller). cheval dispatches to the Anthropic API; the provider rejects (400 `prompt is too long` at ~1.26M real
tokens, or 429 ITPM on a low tier). `ProviderContextLimitError` records the observation, `input_bound` ignores it for a
calibrated entry, and the next call of the same size fails identically — no self-correction. The chain falls to
`claude-opus-5` (180K, pre-flight reject), `claude-sonnet-5`, then the CLI. Every downstream mount inherits the value with the
catalog (`docs/migration/v2.0-model-generation-floor.md:318-319`).
**Impact:** The default `opus` alias for every review/audit dispatch carries a bound that is only correct for one route and
one tokenizer-corrected estimate, with the self-correcting path removed. Process-wise, a safeguard introduced by this PR
(refuse to write `partial`) was circumvented in the same PR, and the circumvention lives in a comment rather than a field
(see LOW-004).
**Fix:** Either keep the HTTP entry uncalibrated (`conservative_default`, 180,000; park the 936,000 measurement in a
Bedrock/claude-headless-scoped field or the report), or make calibration transport-aware: record `probe_outcome: partial`,
`sample_size: 5` and `tokenizer_ratio` structurally (schema too), let a verified observed provider limit tighten a bound whose
`ceiling_calibration.transport` differs from the dispatch route, and count exactly (or scale by the measured ratio) when the
estimate exceeds half a calibrated bound. Re-run `--transport api` from a keyed host before shipping a calibrated HTTP bound.
**Reference:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html ;
OWASP A05:2021 — https://owasp.org/Top10/A05_2021-Security_Misconfiguration/

---

## Medium Priority Issues

### [MED-001] System-Zone defaults are merged into an operator-only security decision
- **Severity:** MEDIUM — **Confidence:** high
- **File:** `head/.claude/adapters/loa_cheval/config/loader.py:122`
- **Issue:** `merged = _deep_merge(load_system_defaults(root), load_project_config(root))` then
  `headless.get("agy_opt_in") is True` (:125-126). `load_system_defaults` reads `.claude/defaults/model-config.yaml`
  (:98) — the System Zone, replaced on every framework update. A shipped top-level `headless: {agy_opt_in: true}` would opt
  every downstream mount into the argv-exposed route without an operator decision. The docstring (:114-117), the example
  config (`.loa.config.yaml.example:743-750`: "Only a YAML boolean true counts") and the four other readers (bash yq, TS)
  all read `.loa.config.yaml` alone. Today no such key exists in the defaults (verified), so this is latent.
- **Fix:** Read the key from `load_project_config(root)` only; add a test that a `headless.agy_opt_in: true` in the system
  defaults does not opt in.
- **Reference:** CWE-15 External Control of System or Configuration Setting — https://cwe.mitre.org/data/definitions/15.html

### [MED-002] The opt-in is read from the cwd-walked tree, which the review flows treat as untrusted
- **Severity:** MEDIUM — **Confidence:** medium
- **File:** `head/.claude/adapters/loa_cheval/config/loader.py:120` (`root = project_root or _find_project_root()`), `:87-93`
  (walk up from `Path.cwd()` to the first `.loa.config.yaml` / `.claude`), call sites with no root
  `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:123`, `:261`, `:295`
- **Issue:** The adapter's own module docstring treats the caller's cwd as the reviewed, untrusted tree (private workspace,
  refusal of any `GEMINI.md`), yet the privacy gate reads its answer from the `.loa.config.yaml` found by walking up from that
  cwd. In a CI review of an untrusted branch the branch can add `hounfour.headless.agy_opt_in: true` and re-enable the
  argv-exposed route; `test_the_project_root_defaults_to_the_cwd_walk` pins the walk as intended. The migration note promises
  the exposure happens "only ever … by an operator's deliberate choice" (`docs/migration/v2.0-model-generation-floor.md:296-297`,
  adapter docstring :45). Caveat that keeps this at medium: a branch that controls `.loa.config.yaml` in CI also controls the
  framework scripts, so the gate is not weaker than the surrounding trust model — but the PR's text claims a stronger
  guarantee than the code gives. Raised by this round's companion dissent (DISS-C-001, MEDIUM); verified against head.
- **Fix:** Pass the orchestrator's resolved project root (the config cheval already loaded for the invocation) into the gate
  instead of re-walking the cwd; document that the decision is as trusted as the checkout it is read from, or read it from an
  operator-owned location for CI reviews of foreign branches.
- **Reference:** CWE-807 Reliance on Untrusted Inputs in a Security Decision — https://cwe.mitre.org/data/definitions/807.html

### [MED-003] YAML 1.1 vs 1.2: the Python gate and the yq gates disagree on `yes` / `on`
- **Severity:** MEDIUM — **Confidence:** high (verified locally)
- **File:** `head/.claude/adapters/loa_cheval/config/loader.py:126` (PyYAML `safe_load`, YAML 1.1); yq v4 readers
  `head/.claude/scripts/flatline-orchestrator.sh:525`, `head/.claude/scripts/adversarial-review.sh:2353`,
  `head/.claude/scripts/loa-status.sh:801`, `head/.claude/scripts/run-preflight.sh:157`,
  `head/.claude/skills/bridgebuilder-review/resources/config.ts:163-166`; python-yq flavour `run-preflight.sh:158`
- **Issue:** `yaml.safe_load('a: yes')['a']` is `True` (verified); `yq eval '… | (tag == "!!bool" and . == true)'` on the same
  text prints `false` (yq v4.40.5, verified). With `agy_opt_in: yes` cheval dispatches agy (and exposes the prompt on argv)
  while every planner records the voice as not planned; `run-preflight.sh:158`'s python-yq branch is YAML 1.1 again, so
  three readers hold two answers. `test_the_key_is_a_yaml_boolean_default_false` has no `yes`/`on` row.
- **Fix:** Accept only the literal scalar `true` in every reader (Python: compare the raw token, or load with a YAML 1.2
  loader; or reject/warn on any other spelling); add the `yes`/`on`/`Yes` rows to the gate test.
- **Reference:** CWE-436 Interpretation Conflict — https://cwe.mitre.org/data/definitions/436.html

### [MED-004] Bridgebuilder's merge quorum shrinks on a config read error (fails open)
- **Severity:** MEDIUM — **Confidence:** medium
- **File:** `head/.claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts:422`
  (`modelResults.length !== multiConfig.models.length - keyStatus.notPlanned.length`); `config.ts:173-176` (bare `catch {}`,
  then `optIn=false`); strict mode `multi-model-pipeline.ts:176` (only `missing` is checked)
- **Issue:** `readAgyGate` swallows every error — yq missing, unreadable or malformed config, timeout — as "opt-in off". Under
  `mode: cli-only` (this repository's own setting, `.loa.config.yaml:114`) a configured Google voice then becomes `notPlanned`
  and is subtracted from the expected cohort, so a 2/2 result clears a 3-voice merge gate (the new test asserts exactly
  "✓ APPROVED — 2/2 voices" with `mergeBlocked` false, `multi-model-agy-opt-in.test.ts:150-152`). In `api_key_mode: strict`
  the dropped voice is not even warned. Failing closed on the *opt-in* is right; failing open on the *quorum* is not.
- **Fix:** Carry `readError` on the gate; a voice removed because the gate could not be read stays in the expected set
  (merge blocked, reason named) and strict mode throws; log the real reason instead of "agy opt-in off".
- **Reference:** CWE-636 Not Failing Securely ('Failing Open') — https://cwe.mitre.org/data/definitions/636.html

### [MED-005] Five readers, three definitions of "routes to agy"
- **Severity:** MEDIUM — **Confidence:** medium
- **File:** `head/.claude/scripts/adversarial-review.sh:2360` and `head/.claude/scripts/run-preflight.sh:190` (name
  `gemini-headless` only); `head/.claude/scripts/loa-status.sh:808-811` (every `google` provider); 
  `head/.claude/scripts/flatline-orchestrator.sh:529-538` and `head/.claude/skills/bridgebuilder-review/resources/config.ts:180-183`
  (name, or any Google model under `cli-only`)
- **Issue:** With this repository's `hounfour.headless.mode: cli-only`, run-preflight P3 counts `gemini-3.1-pro` as a usable
  voice (credential present) while cheval would route it to agy and refuse; the dissent companion filter plans the same hop
  and records a `failed` voice; `/loa` marks every Google provider gated regardless of mode. The planners cannot be trusted
  to agree with the dispatcher (HIGH-001) while each carries its own rule.
- **Fix:** One shared predicate `routes_to_agy <model> <mode>` (a sourced `lib/agy-gate-lib.sh`, mirrored in `config.ts`
  and `loader.py`), alias-resolved, used by all five readers and by cheval.
- **Reference:** CWE-1041 Use of Redundant Code — https://cwe.mitre.org/data/definitions/1041.html

### [MED-006] `effort_effective` telemetry misreports on codex/grok CLI hops and on fallback hops
- **Severity:** MEDIUM — **Confidence:** high
- **File:** `head/.claude/adapters/cheval.py:935-936` (`if _is_cli_entry(...): return effort`); fallback threading
  `head/.claude/adapters/cheval.py:1829` (`effort=_effort` on `base_request`), MODELINV `:2833-2843`
- **Issue:** Only the claude-headless adapter reads `CompletionRequest.effort`; codex-headless and grok build their
  reasoning flag from `extra.reasoning_effort`. `_effort_on_wire` returns the resolved effort for every CLI entry, so a
  `--effort high` dispatch answered by codex-headless records `effort_effective: high` although nothing of the kind went on
  the wire. The primary entry's catalog default also rides `base_request.effort` into every fallback hop, which then reports
  `effort_source: catalog` for an entry that declares no default. The audit ledger (MODELINV) is the record D-2.6's
  effort-vs-outcome analysis is meant to read; it is now wrong for those rows.
- **Fix:** Let each adapter class answer `wire_effort(request, model_config)`; cheval records that. Resolve the catalog rung
  per hop entry, not once for the primary.
- **Reference:** CWE-778 Insufficient Logging (inaccurate audit record) — https://cwe.mitre.org/data/definitions/778.html ;
  OWASP A09:2021 — https://owasp.org/Top10/A09_2021-Security_Logging_and_Monitoring_Failures/

### [MED-007] Bridgebuilder's Opus 5.5 budget outruns its own token heuristic
- **Severity:** MEDIUM — **Confidence:** medium
- **File:** `head/.claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts:34` (`maxInput: 916000`), dist
  copy `head/.claude/skills/bridgebuilder-review/dist/core/truncation.generated.js:31`
- **Issue:** 916,000 is the new ceiling minus the generator's fixed 20,000 margin. Bridgebuilder's `estimateTokens` is a
  character heuristic; the catalog comment measures a ~1.8× under-count on this tokenizer, so a review packed to the budget is
  ~1.65M provider tokens and is rejected. The old 160,000 budget absorbed that error inside the 1M window.
- **Fix:** Scale the Opus 5.5 budget by the measured `tokenizer_ratio` (or use an API-measured bound); keep the ratio beside
  `measured_input_tokens` so the generator can read it.
- **Reference:** CWE-682 Incorrect Calculation — https://cwe.mitre.org/data/definitions/682.html

### [MED-008] FAST-GATE: no evidence the ~1,800 new test lines ran
- **Severity:** MEDIUM — **Confidence:** high
- **File:** `pr/PR.md:1-9` (the implementation report)
- **Issue:** The report names no self-checks — no pytest, bats or node run, no `tsc --noEmit` / `prettier --check` — and has
  no `## AC Verification` section. The dist `.build-manifest.json` hashes match the head sources (the build ran); nothing shows
  the new suites pass. Not re-run here (see Pre-flight).
- **Fix:** Record the fast-gate commands and results in the report before re-audit.
- **Reference:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html

---

## Low Priority Issues

### [LOW-001] `validateApiKeys` defaults to a cwd-relative config path
- **File:** `head/.claude/skills/bridgebuilder-review/resources/config.ts:190` (`gate: AgyGate = readAgyGate()` → `".loa.config.yaml"`, :159)
- **Issue:** Only the pipeline passes the repo-root path (`multi-model-pipeline.ts:172`); any other caller answers "off" when
  Bridgebuilder runs from another directory.
- **Fix:** Make `gate` required, or derive the path from `repoRoot` in one helper used by every caller.
- **Reference:** CWE-426 Untrusted Search Path — https://cwe.mitre.org/data/definitions/426.html

### [LOW-002] `validate_config` double-reports one cause; `health_check` sits under the wrong banner
- **File:** `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:261-262` (refusal appended, PATH still probed at :270-275), `:293-297` (`health_check` under the "Internal: command construction" banner at :289-291)
- **Fix:** `return errors` after the opt-in refusal; move `health_check` above the banner.
- **Reference:** CWE-1078 Inappropriate Source Code Style or Formatting — https://cwe.mitre.org/data/definitions/1078.html

### [LOW-003] The gate's root lookup sits outside its fail-closed `try`, and re-walks on every call
- **File:** `head/.claude/adapters/loa_cheval/config/loader.py:120-124`
- **Issue:** `root = project_root or _find_project_root()` (:120) precedes the `try` (:121-124). `Path.cwd()` raises when the
  working directory has vanished (the codebase handles that as `cwd_vanished` for CLI adapters) and `Path.exists()` re-raises
  `PermissionError`, so the gate escapes `complete()` as a raw exception that cheval's catch-all reports as a retryable
  `API_ERROR` instead of the refusal. The gate also re-walks the cwd and re-parses both YAML files on every `complete()`,
  `health_check()` and `validate_config()` call, independent of the config cheval already loaded. Raised by the review
  round's companion dissent (DISS-C-005); verified in head.
- **Fix:** Move the root lookup inside the `try`; resolve once per process (or read the loaded `hounfour` dict).
- **Reference:** CWE-755 — https://cwe.mitre.org/data/definitions/755.html

### [LOW-004] Calibration provenance lives in comments, not fields
- **File:** `head/.claude/defaults/model-config.yaml:506` (`sample_size: null` for a five-sample run), `:495-500` (outcome `partial`, 1.8× ratio, record path — comments only)
- **Issue:** `loa-status`, the v3 schema and every reader see a clean calibrated entry; the facts that would let them
  discount it are invisible to code.
- **Fix:** Add `probe_outcome`, `sample_size: 5` and `tokenizer_ratio` to `ceiling_calibration` and to the schema's
  `ceilingCalibration` definition (`head/.claude/data/schemas/model-config-v3.schema.json:286-307`).
- **Reference:** CWE-1059 — https://cwe.mitre.org/data/definitions/1059.html

### [LOW-005] Stale three-value comments for `effort_source`
- **File:** `head/.claude/adapters/loa_cheval/audit/modelinv.py:498`, `head/.claude/adapters/cheval.py:2834` ("caller | catalog | none")
- **Issue:** The resolver (`cheval.py:921-925`) and both schemas emit `extra` as well.
- **Fix:** Update the comments.
- **Reference:** CWE-1116 Inaccurate Comments — https://cwe.mitre.org/data/definitions/1116.html

### [LOW-006] `extra.effort` shadows a valid `extra.reasoning_effort`; the "both rungs" WARN fires for HTTP entries
- **File:** `head/.claude/adapters/cheval.py:907-911`
- **Issue:** `extra_raw = extra.get("effort") or extra.get("reasoning_effort")` short-circuits, so an invalid `extra.effort`
  hides a valid `reasoning_effort`; the WARN at :908-911 is not gated on `_is_cli_entry(entry)` although HTTP adapters never
  read `extra.effort`.
- **Fix:** Try both keys in order, each validated; gate the WARN on CLI entries.
- **Reference:** CWE-697 Incorrect Comparison — https://cwe.mitre.org/data/definitions/697.html

### [LOW-007] Ceiling tests that no longer test
- **File:** `head/.claude/adapters/tests/test_anthropic_catalog_floor.py:146-148` (for a measured entry
  `cap = entry["effective_input_ceiling"]`, so the "computed, not a constant" assertion reduces to the I2 check on the next
  line), `:168-169` (lookup compared against the catalog's own value — circular);
  `head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py:459` (skips on the shipped calibrated catalog, so the
  live-catalog shortcut-replacement path never runs in CI)
- **Fix:** For measured entries assert `ceiling == min(measured_input_tokens, cw − dmt)` (the writer's own clamp); run the
  shortcut test against a pre-probe fixture copy of the real catalog instead of skipping.
- **Reference:** CWE-1164 Irrelevant Code — https://cwe.mitre.org/data/definitions/1164.html

### [LOW-008] `build_headless_argv` trusts every caller's `effort` and `cli_model`
- **File:** `head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:156-157` (`if effort: cmd.extend(["--effort", effort])`), `:149-150` (`"--model", cli_model`)
- **Issue:** The builder is now shared by the adapter (whose `_resolve_effort` also reads operator `extra.effort`) and the
  probe, but validates neither value; a string starting with `-` would be parsed by the CLI as a flag. Today's callers are
  operator-controlled (cheval validates at the chokepoint), so this is hardening, not an exploit. Raised by this round's
  companion dissent (DISS-C-002, LOW); verified in head.
- **Fix:** Validate `effort` against the shared level tuple and reject a `cli_model` beginning with `-`, raising `ConfigError`.
- **Reference:** CWE-88 Argument Injection — https://cwe.mitre.org/data/definitions/88.html

### [LOW-009] Raw `cli_model` / `host_route` interpolated into a YAML comment line of the catalog
- **File:** `head/tools/ceiling-probe-live.py:467-468` (`provenance = f"        # cycle-127 FR-3: bound measured {day} … ({route}, {cli_model}){clamp_note}; …"`), sources `:438` (`route` = raw `--host-route`), `:186-188` (`cli_model` = raw `ANTHROPIC_DEFAULT_*_MODEL` env)
- **Issue:** `reprobe_trigger`, `cli_model` and `cli_version` scalars are `json.dumps`-quoted (:457-460), but the comment line
  takes `route` and `cli_model` unescaped; a newline in either breaks out of the comment and lands arbitrary text in the
  System-Zone catalog. Both inputs are the operator's own (CLI argument, wrapper env), so the blast radius is self-inflicted.
- **Fix:** Strip control characters (or `json.dumps`) before interpolating into the comment.
- **Reference:** CWE-74 Improper Neutralization of Special Elements in Output Used by a Downstream Component — https://cwe.mitre.org/data/definitions/74.html

### [LOW-010] SIMPLICITY[shrink]: the probe's bisection driver and classifier are oversized and fragilely coupled
- **File:** `head/tools/ceiling-probe-live.py:632` (`_main_cli`, ~215 lines, four nested closures; `step` at :681 nests four deep), `:402` (`write_catalog_operator_set`, ~78 lines with two inner helpers), `:261-262` (`_classify` calls the adapter's instance method `_raise_for_error` with a `SimpleNamespace` standing in for `self`)
- **Fix:** Lift `step` / `next_target`, the record builder and the catalog write to module-level functions (~−40 lines);
  expose the error classification as a static/module function on the adapter instead of faking `self`.
- **Reference:** CWE-1121 Excessive McCabe Cyclomatic Complexity — https://cwe.mitre.org/data/definitions/1121.html

---

## Observations (not tallied)

- `head/.claude/scripts/loa-status.sh:791-797`: the new `LOA_STATUS_CONFIG_FILE` seam is gated on `BATS_TEST_FILENAME`/`BATS_VERSION`
  like the existing `LOA_STATUS_RUN_DIR` / `LOA_STATUS_ENV_DIR` seams (:732, :782) — consistent with the repository's test-mode
  gating invariant; display-only effect. Acceptable.
- `head/.claude/skills/bridgebuilder-review/resources/config.ts:163-168`: `readAgyGate` runs `yq` via `execFileSync` with an argv
  and `stdio: ["ignore","pipe","ignore"]`, 5 s timeout — no shell, no prompt text. Acceptable.
- `head/tools/ceiling-probe-live.py:214-227`: the probe spawns the CLI with the prompt on stdin, in a fresh `mkdtemp` cwd
  removed afterwards, output capped at 1 MB each stream, and passes the full `os.environ` (the CLI needs its auth env).
  Acceptable for an operator tool.
- `head/tests/unit/loa-status-providers.bats:60` and `multi-model-agy-opt-in.test.ts:80`: the only credential-shaped strings
  in the change are test fixtures (`sk-test-value-must-never-print`, asserted never printed; `fixture-not-a-key`).
- The dist bundle (`dist/config.js`, `dist/core/multi-model-pipeline.js`, `dist/core/truncation.generated.js`) matches the TS
  sources read here; manifest hashes were verified by the review.

---

## Cross-Model Security Observations

Security dissent (Phase 1C) ran on `pr/head.diff` with two voices: primary `gpt-5.5-pro` chain answered by `codex-headless`
(`status: clean` — "no findings met the BLOCKING/ADVISORY bar — not an approval of unreviewed surface"), companion
`claude-headless` (`status: succeeded`, `counted_as: independent_voice`). `verdict_quality`: 2/2 voices, `chain_health: ok`,
`status: APPROVED`; `degraded: false`; no `degraded_security_review` marker. Envelope:
`grimoires/loa/a2a/sprint-1/adversarial-audit.json` (`metadata.model: gpt-5.5-pro`, `metadata.type: audit`).

| Dissent id | Voice | Severity | Triage |
|------------|-------|----------|--------|
| DISS-C-001 | claude-headless | MEDIUM | Real: the opt-in read from the cwd-walked (untrusted in CI) tree → **MED-002** |
| DISS-C-002 | claude-headless | LOW | Real (hardening): `build_headless_argv` validates neither `effort` nor `cli_model` → **LOW-008** |

Neither voice repeated the review round's BLOCKING finding (the chain walk, HIGH-001); that finding is carried on the auditor's
own verification above. Advisory voices: none (`advisory_voices` absent).

## Rejected dissent payloads

None — `metadata.rejected_summary` is empty, `metadata.rejected_sidecars` is `[]`, and no `adversarial-rejected-audit*.jsonl`
exists beside the envelope (the `adversarial-rejected-review.jsonl` in the directory belongs to the review gate and holds no rows).

---

## Rubric Scores

| Dimension | Score | Basis |
|-----------|-------|-------|
| SEC-IV Input Validation | 4 | Boolean-only gate in every reader; YAML 1.1/1.2 gap (MED-003); unvalidated argv builder (LOW-008); comment interpolation (LOW-009) |
| SEC-AZ Authorization | 3 | The opt-in is a privacy control enforced at the adapter but bypassable at the dispatcher's expense (HIGH-001) and read from a System-merged, cwd-walked source (MED-001, MED-002) |
| SEC-CI Confidentiality/Integrity | 4 | No secrets; argv exposure now off by default; catalog checksum matches; provenance in comments (LOW-004) |
| SEC-IN Injection Prevention | 5 | `execFileSync` argv, stdin prompts, no shell interpolation of untrusted text |
| SEC-AV Availability/Resilience | 2 | Default-setting voice loss under prefer-cli (HIGH-001); uncorrectable pre-flight bound (HIGH-002); fail-open quorum (MED-004) |
| ARCH-MO Modularity | 3 | One predicate reimplemented five ways (MED-005); dispatcher lacks the gate; shared argv builder is good |
| Code Quality | 3 | Extensive tests, but two reduced to tautology / skip (LOW-007); 215-line closure-heavy driver (LOW-010); telemetry wrong on two hop classes (MED-006) |
| DevOps | 3 | Build artefacts honest (manifest, checksum); no evidence suites ran (MED-008) |

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added (fixtures only; asserted never printed)
- [x] Input validation at trust boundaries — boolean-only opt-in, no env override, argv-based yq call
- [ ] Trust boundary of the opt-in source — System defaults merged (MED-001); cwd-walked tree (MED-002); YAML 1.1 spelling (MED-003)
- [x] Authentication/authorization — argv-exposure route off by default, refused before spawn, OAuth-authed CLI documented
- [x] No injection reachable from review content (stdin prompts, argv exec); operator-only comment interpolation noted (LOW-009)
- [ ] Error handling — the refusal is terminal in the chain walk (HIGH-001); root lookup outside fail-closed try (LOW-003); read errors shrink the quorum (MED-004)
- [x] Error messages don't leak sensitive data (`AgyOptInRequiredError.MESSAGE` names the key only; probe caps output)
- [ ] Tests cover security paths — gate matrix good; `yes`/`on` rows missing; two ceiling tests inert (LOW-007); suites not shown to run (MED-008)
- [x] Dependencies — none added
- [x] CHANGELOG/migration documents the security change (argv exposure, opt-in) — with the overclaim in MED-002

---

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 8 |
| Low | 10 |

critical + high = 2 > 0 ⇒ CHANGES_REQUIRED (one-way rule).

---

## Next Steps

1. Plan around gated agy hops in cheval's chain walk and record them as `models_not_planned` (HIGH-001); unify the
   "routes to agy" predicate across cheval and the five readers (MED-005).
2. Decide the Opus 5.5 HTTP bound: restore the uncalibrated 180,000 until an API-transport probe, or make calibration
   transport-aware with structured provenance and a tokenizer-corrected pre-flight (HIGH-002, LOW-004, MED-007).
3. Read the opt-in from the project config only, from the orchestrator's resolved root, accepting the literal `true` alone
   (MED-001, MED-002, MED-003, LOW-003); keep read errors out of Bridgebuilder's quorum (MED-004).
4. Fix `effort_effective` per adapter and per hop (MED-006, LOW-005, LOW-006).
5. Run the fast gate and the three suites; add `## AC Verification` to the implementation report (MED-008).
6. `/implement sprint-1` for the fixes, then `/review-sprint sprint-1` and `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":8,"low":10},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-22T00:05:00Z"} -->
