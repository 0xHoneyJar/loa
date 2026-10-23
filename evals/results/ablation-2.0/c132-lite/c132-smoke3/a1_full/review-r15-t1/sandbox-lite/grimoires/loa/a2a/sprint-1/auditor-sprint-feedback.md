# Sprint 1 Security & Quality Audit

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Scope:** The pull request in `pr/` (`pr/head.diff`, 45 files; sprint-251 operator decisions: FR-1 agy opt-in gate, FR-2 Opus 5.5 catalog effort default, FR-3 headless-CLI ceiling probe with the fr23b I2 clamp). Citations are `head/<path>:<line>` with line numbers from `pr/head/`.
**Methodology:** Systematic 5-category review (Security, Architecture, Code Quality, DevOps; Blockchain not applicable), every touched non-generated file read in full, dist bundles spot-checked against their sources.
**Sprint Reference:** grimoires/loa/sprint.md (Task 1.1: the change in `pr/head.diff`)
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Senior Review:** grimoires/loa/a2a/sprint-1/engineer-feedback.md — verdict CHANGES_REQUIRED (1 HIGH, 4 MEDIUM, 11 LOW, excluded 0)

---

## Prerequisite and scope notes

- **Prerequisite deviation (recorded, not hidden).** The skill's Phase 0 requires `engineer-feedback.md` to read "All good". It reads CHANGES_REQUIRED. The task brief orders this audit to run regardless, so it ran; the audit confirms the review's blocking finding independently rather than relying on it. No `COMPLETED` marker is written.
- **Tests could not be executed against head.** The workspace tree is neither the PR's base nor its head (20 of 45 touched files differ from head; the untouched `anthropic_adapter.py` imports a symbol the head `types.py` does not export), so an overlay run of the touched pytest suites failed at import. The PR description names no test, type-check or build output. Test coverage below is judged by reading the suites, not by running them.
- **Known-failures surface degraded.** `grimoires/loa/known-failures.md` is unreadable on this host (startup hook warning); triage proceeded without it.
- **Documentation coherence reports:** none exist under `grimoires/loa/a2a/subagent-reports/`. Documentation was verified manually: `.loa.config.yaml.example`, the migration note and the catalog comments were updated; the dissent skill doc's reason list was not (LOW-010).
- **Beads:** `br` is not installed; no audit comment or label was recorded.

---

## Executive Summary

The change implements three operator decisions coherently at the unit level: a single Python predicate for the agy opt-in (`head/.claude/adapters/loa_cheval/config/loader.py:113-126`) with eight parametrised negative cases, a single effort chokepoint in cheval with precedence tests and dry-run output, and a headless-CLI ceiling probe whose catalog write is clamped to the I2 invariant and covered end to end by a fake CLI with a zero-live-spend guard. No secrets, no shell interpolation of untrusted text, no new dependencies; the opt-in cannot be flipped from the environment, and the cheval circuit breaker is not tripped by the refusal (`retry.py` re-raises `ChevalError` without `_record_failure`, so the docs' "never a breaker trip" holds).

The blocking defect is that the FR-1 gate is a planning decision in every shell/TypeScript planner but a dispatch-time exception inside cheval, and cheval's chain walk treats that exception class as a hard abort. With the shipped default (`agy_opt_in: false`) any cheval chain that reaches the `gemini-headless` hop returns `INVALID_CONFIG` there and never tries the hops behind it. The PR's own docs promise the opposite. This is a resilience regression on hosts where agy is installed and reproduces the "degraded multi-model verdict" symptom the PR cites as its motivation.

Secondary concerns: the two "routes to agy" predicates ignore `prefer-cli`; the catalog raises the Opus 5.5 input bound 5.2x on a partial, route-specific probe whose record is not in the repository, with no self-correcting path on other routes; and the probe's `_main_cli` is a 215-line function with six closures. Fifteen LOW items follow, two of them audit-originated (raw CLI text interpolated into a YAML comment in the System-Zone catalog; the probe inheriting the full parent environment where the adapter strips credentials).

**Overall Risk Level:** HIGH (rubric 3.4/5; driven by SEC-AV and ARCH-RE)

**Key Statistics:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 3 |
| Low | 15 |

---

## Category Scores (Rubric-Based Assessment)

**Scoring Method:** Each dimension scored 1-5 per `resources/RUBRICS.md`

| Category | Score | Dimensions |
|----------|-------|------------|
| Security | 3.6/5 | IV:4 AZ:4 CI:4 IN:4 AV:2 |
| Architecture | 3.0/5 | MO:3 SC:4 RE:2 CX:3 ST:3 |
| Code Quality | 3.4/5 | RD:3 TC:4 EH:3 TS:4 DC:3 |
| DevOps | 3.6/5 | AU:4 OB:4 RC:3 AC:4 DS:3 |
| Blockchain | n/a | *(not applicable; weight redistributed)* |
| **Overall** | **3.4/5** | *Weighted: Security 30%, others 23.3% each* |

**Risk Level Mapping:** 4.5-5.0 LOW | 3.5-4.4 MODERATE | 2.5-3.4 HIGH | 1.0-2.4 CRITICAL

**Machine-Parseable Output:** `grimoires/loa/a2a/audits/2026-10-21/findings.jsonl`

---

## Critical Issues (Fix Immediately)

None.

---

## High Priority Issues (Fix Before Production)

### [HIGH-001] A gated agy hop aborts cheval's entire chain walk instead of being skipped

**Severity:** HIGH | **Confidence:** high | **Criterion:** SEC-AV Availability/Resilience, ARCH-RE Resilience
**Component:** `head/.claude/adapters/loa_cheval/types.py:503`, `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:124-125`, `head/.claude/adapters/cheval.py:2544-2553`, `head/.claude/scripts/adversarial-review.sh:4083`

**Reasoning Trace:**
> Traced the refusal from its raise site to every consumer. `AgyOptInRequiredError` is declared as `class AgyOptInRequiredError(ConfigError)` (types.py:503) and raised at the top of `complete()`: `"if not agy_opt_in_enabled(): raise AgyOptInRequiredError()"` (agy_headless_adapter.py:124-125). cheval's per-hop loop has walk-and-continue arms only for retry exhaustion and `AuthRevokedError`; the comment at cheval.py:2527-2529 states the policy: `"STATIC misconfig (ConfigError/INVALID_CONFIG) still falls through to the hard-abort arm below — operator config errors are NEVER silently masked"`. That arm (cheval.py:2544-2553) appends the hop to `models_failed` with `error_class: "UNKNOWN"`, prints the error JSON and `return EXIT_CODES.get(_e.code, 1)` (INVALID_CONFIG = 2, cheval.py:124). A grep of head `cheval.py` for `agy`, `opt_in`, `health_check` or `failure_class == "opt_in_required"` finds nothing: no resolver filter, no loop skip, no dedicated arm. The adapter's `health_check()` now returns False while off (agy_headless_adapter.py:294-298), but cheval's walk never calls `health_check`. In `adversarial-review.sh` only the companion chain is passed through `_adv_agy_filter_chain` (line 4083); the primary `fallback_chain` array built at 3971-4007 and walked at 4134 is not filtered, and a cheval exit 2 on that walk is classified `api_failure` (lines 1295-1302) — a failed voice.

**Description:** The PR states the contract as `"the dissent, Flatline's tertiary, Bridgebuilder, run-preflight.sh and /loa record the hop as *not planned* (reason: opt_in_required) rather than failed"` (`head/docs/migration/v2.0-model-generation-floor.md:286`) and describes the hop as `"the terminal of every stock Google chain"` (agy_headless_adapter.py:36). Inside cheval, the gate is enforced only as an exception that the walk cannot pass. Any chain containing a Google CLI hop (every stock Google chain; under `hounfour.headless.mode: cli-only`, which this repository sets, every Google model) now dies at that hop with the opt-in off.

**Impact:** Hops after the gated one (e.g. `claude-headless`) are never attempted; the invocation returns INVALID_CONFIG. For the dissent's primary chain and any Flatline chain holding a Google hop, this is a dropped voice and a DEGRADED verdict — the exact symptom (Bridgebuilder #1274, "DEGRADED 2/3") the PR cites as motivation. On a host where agy is installed, behaviour regresses from "hop answers" to "whole invoke aborts" by default. Blast radius: every `cheval invoke` whose resolved chain reaches `gemini-headless`.

**Proof of Concept:**
```
# .loa.config.yaml: hounfour.headless.mode: cli-only (this repo), agy_opt_in absent
# chain: [gpt-5.5, gemini-3.1-pro, claude-headless]; codex hop fails (quota)
# -> walk reaches google:gemini-3.1-pro -> cli-only -> gemini-headless adapter
# -> complete() raises AgyOptInRequiredError (ConfigError)
# -> cheval.py:2544 `except ChevalError` -> models_failed[error_class=UNKNOWN] -> return 2
# claude-headless is never dispatched; adversarial-review.sh records api_failure
```

**Remediation:** Make the gate a planning decision inside cheval too. In chain resolution or at the top of the per-hop loop, skip hops whose adapter class is `gemini-headless` when `agy_opt_in_enabled()` is false and record them in the MODELINV envelope as not planned (`reason: opt_in_required`), not in `models_failed`; keep the adapter's exception as the belt-and-braces refusal for a direct single-hop dispatch. Alternatively add an `except AgyOptInRequiredError` arm before the `ChevalError` arm that `continue`s with a dedicated `error_class` (e.g. `OPT_IN_REQUIRED`) excluded from dropped-voice accounting. Apply `_adv_agy_filter_chain` to the primary `fallback_chain` in `adversarial-review.sh` as it is applied to the companion chain. Add a test walking `[codex-headless, gemini-headless, claude-headless]` with the opt-in off that asserts the third hop is dispatched and the envelope shows the second as not planned.

**References:** CWE-754 Improper Check for Unusual or Exceptional Conditions (https://cwe.mitre.org/data/definitions/754.html); CWE-755 Improper Handling of Exceptional Conditions (https://cwe.mitre.org/data/definitions/755.html); OWASP A05:2021 Security Misconfiguration (https://owasp.org/Top10/A05_2021-Security_Misconfiguration/)

---

## Medium Priority Issues (Address in Next Sprint)

### [MED-001] The "routes to agy" predicates gate `cli-only` but not `prefer-cli`

**Severity:** MEDIUM | **Confidence:** medium | **Criterion:** ARCH-ST Standards Compliance
**Component:** `head/.claude/scripts/flatline-orchestrator.sh:529-537` (`"[[ "$mode" == "cli-only" ]] || return 1"`, line 534), `head/.claude/skills/bridgebuilder-review/resources/config.ts:182` (`"return modelId === "gemini-headless" || mode === "cli-only""`), pinned by `head/.claude/skills/bridgebuilder-review/resources/__tests__/multi-model-agy-opt-in.test.ts`
**Description:** Both predicates claim to answer "would cheval dispatch this through agy". Under `prefer-cli` cheval orders the CLI hop first for a Google model, so the tertiary / Bridgebuilder voice is planned, reaches agy first and, while HIGH-001 stands, aborts rather than falling to its API hop. The predicate is truthful for only two of the four documented modes.
**Impact:** A planned voice that cannot answer; a DEGRADED Flatline or Bridgebuilder verdict that the planner said would not happen.
**Remediation:** Once cheval skips gated hops (HIGH-001) the `prefer-cli` case becomes correct by fall-through; until then gate `prefer-cli` as well, or document why a `prefer-cli` Google voice counts as planned.

### [MED-002] Opus 5.5 input bound raised 180000 to 936000 on a partial, route-specific probe with no record and no self-correction

**Severity:** MEDIUM | **Confidence:** medium | **Criterion:** DO-DS Deployment Safety, SEC-AV Availability
**Component:** `head/.claude/defaults/model-config.yaml:494-513`, `head/.claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts:34`, `head/.claude/adapters/tests/test_anthropic_catalog_floor.py:135-141`
**Description:** The entry's own comment says `"the tool's own outcome was `partial` — the $20 budget cap stopped the bisection"` (model-config.yaml:496-497), yet the calibration is written as `method: probed_headless` (line 509), a value the tool itself refuses to write on a partial outcome (`head/tools/ceiling-probe-live.py:796-800`: `"partial (...) — nothing written to the catalog"`). The evidence file named at line 501, `grimoires/loa/reports/2026-10-07-opus-5-5-ceiling-probe-cli.json`, is neither in the change nor in this repository. The bound was measured through claude-headless on Bedrock; the entry is the HTTP `anthropic:claude-opus-5-5` entry, and `test_anthropic_catalog_floor._measured` now makes the floor suite follow whatever a calibrated entry says (only the I2 inequality is still asserted). The /loa bats test states the policy: `"calibrated: the measured bound, observations never lower it"` (`head/tests/unit/loa-status-providers.bats:69`).
**Impact:** On a direct-API route whose real bound is lower, cheval will preempt only above 936000 and Bridgebuilder will budget 916000 input tokens; every oversized call fails with PROVIDER_CONTEXT_LIMIT and nothing lowers the calibrated value, so the failure repeats until an operator edits the catalog. Each such attempt bills up to ~936K input tokens at the catalog price.
**Remediation:** Commit the probe record with the catalog (or link a durable location); either mark the calibration honestly (`method` absent or a new `operator_set_partial`, with the route in `reprobe_trigger` as today) or re-run to a clean outcome; and let an observed `PROVIDER_CONTEXT_LIMIT` below a calibrated bound lower the effective bound at least for `source: operator_set`.

### [MED-003] `_main_cli` is a 215-line function with six closures over shared mutable state

**Severity:** MEDIUM | **Confidence:** high | **Criterion:** ARCH-CX Complexity, CQ-RD Readability
**Component:** `head/tools/ceiling-probe-live.py:632-847` (`_main_cli`), `head/tools/ceiling-probe-live.py:402-485` (`write_catalog_operator_set`, 84 lines)
**Description:** `SIMPLICITY[shrink]`: `_m`, `_size`, `current_ok`, `current_fail`, `step`, `next_target` close over `samples`, `ratio`, `spent_micro` with `nonlocal` writes; the re-anchor rule, the budget rule and the ratio update are each buried in a closure. The `__import__("time").sleep` / `__import__("re")` idioms at lines 136, 144 and 148 replace plain imports. Neither function carries a justification comment for exceeding the 50-line threshold.
**Impact:** The bisection state machine is testable only through the fake CLI; the clamp and re-anchor logic cannot be unit-tested in isolation, and the next change to the budget or ratio rule has no seam.
**Remediation:** Lift the bisection state into a small `Bisection` dataclass with `step()` / `next_target()` methods; keep `_main_cli` to argument handling, the loop and the record; use top-level imports. Net reduction of roughly 40 lines is available.

---

## Low Priority Issues (Technical Debt)

### [LOW-001] Four copies of the yq opt-in predicate, one flavour-aware and three not
**Component:** `head/.claude/scripts/adversarial-review.sh:2353`, `head/.claude/scripts/flatline-orchestrator.sh:525`, `head/.claude/scripts/loa-status.sh:801`, `head/.claude/skills/bridgebuilder-review/resources/config.ts:166`; contrast `head/.claude/scripts/run-preflight.sh:157-158` (branches on `YQ_FLAVOUR`)
**Confidence:** medium. The review rated this MEDIUM; this audit demotes it: the three non-branching scripts already used `yq eval` (go-yq syntax) before the change (base counts 25/3/5), so the new predicate adds no new flavour dependency. What remains is five hand-copied predicates for one security-relevant key, which will drift.
**Remediation:** One flavour-aware shell helper (sourced) for the three scripts; keep the TS reader but share the yq expression text with it via the generated config.

### [LOW-002] Stale `effort_source` comment says three values; there are four
**Component:** `head/.claude/adapters/loa_cheval/audit/modelinv.py:498` and `head/.claude/adapters/cheval.py:2834` (`"caller | catalog | none"`); `resolve_effort` returns `"extra"` (cheval.py:921) and the schema enumerates four (`head/.claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json:755-762`). Comment fix only; the schema and `test_modelinv_schema_declares_effort_source` are correct.

### [LOW-003] `measured_input_tokens` description predates the I2 clamp
**Component:** `head/.claude/data/schemas/model-config-v3.schema.json:306` (`"the value written to probed_ceiling / effective_input_ceiling"`), `head/tools/ceiling-probe-live.py:44-45` (`"raw — the api transport applies no safety margin"`), `head/docs/migration/v2.0-model-generation-floor.md:297` (`"to the measured bound"`). The second commit writes `min(measured, context_window − default_max_tokens)` (`head/tools/ceiling-probe-live.py:377-399`) and the live catalog carries 972887 vs 936000.

### [LOW-004] Effort resolved once against the primary entry and attributed to the answering hop
**Component:** `head/.claude/adapters/cheval.py:1519-1522`; MODELINV `effort_source: catalog` then names the answering hop's catalog even when that entry declares no default. Only Opus 5.5 sets a default today (pinned by `test_no_other_entry_sets_default_effort_this_cycle`), so impact is nil now. **Confidence:** medium.

### [LOW-005] `_find_project_root()` is evaluated outside the fail-closed `try`
**Component:** `head/.claude/adapters/loa_cheval/config/loader.py:120`. A vanished cwd raises a raw `OSError` from `complete()` instead of the documented refusal; cheval's catch-all then reports `API_ERROR retryable=True`. Move the call inside the `try`. **Confidence:** medium.

### [LOW-006] `_effort_on_wire` keys on the literal provider name `anthropic`
**Component:** `head/.claude/adapters/cheval.py:928-940` (`"if provider == "anthropic""`, line 937). Returns `None` for Claude served by the catalog's `bedrock` provider and passes effort through for non-Claude CLI hops whose adapters do not read it; `effort_effective` can be wrong in both directions. **Confidence:** medium.

### [LOW-007] Preflight P3 FAIL text names the wrong cause when the only voice is gated
**Component:** `head/.claude/scripts/run-preflight.sh:204` (`"no credential present and no CLI hop on PATH"`) and the fix hint at line 210, which does not mention `hounfour.headless.agy_opt_in`. The fail-closed outcome itself is correct (pinned by `PF-AGY`).

### [LOW-008] `/loa` Providers row alignment broken by a 52-character hop note
**Component:** `head/.claude/scripts/loa-status.sh:866` (`hop %-7s` fed `"agy: opt-in (disabled; hounfour.headless.agy_opt_in)"`). The bats regex tolerates it; a reader will not.

### [LOW-009] `validate_config()` returns an error for the stock provider on every default install
**Component:** `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:261-262`. No production caller besides `doctor.py` today, but "default configuration validates with an error" is a trap for the first caller that treats the list as fatal. Return a warning, or only when the hop is planned. **Confidence:** medium.

### [LOW-010] New `companion_voice` reason `opt_in_required` is undocumented in the skill docs
**Component:** `head/.claude/scripts/adversarial-review.sh:4085`; `.claude/skills/reviewing-code/resources/ADVERSARIAL-REVIEW.md` and its byte-identical `auditing-security` copy (not in the change) enumerate `no_workdir`, `no_route`, `prompt_copy_failed` only. Update both (CMP-138 pins them identical).

### [LOW-011] A writer test now skips permanently on the calibrated live catalog
**Component:** `head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py:459`. `test_write_operator_set_changes_only_the_entry_and_replaces_the_shortcut` carries the only assertions that neighbouring entries are untouched, exactly one comment is removed, and the written `ceiling_calibration` validates against the v3 schema; they now run nowhere. Port them onto the `SYNTH` fixture.

### [LOW-012] Raw CLI text is interpolated into a YAML comment line in the System-Zone catalog (audit-originated)
**Component:** `head/tools/ceiling-probe-live.py:467-468`
**Description:** `provenance = (f"        # cycle-127 FR-3: bound measured {day} by tools/ceiling-probe-live.py --transport claude-headless ({route}, {cli_model}){clamp_note}; ...")` places `host_route` (`--host-route`, free text) and `cli_model` (`--cli-model` or the `ANTHROPIC_DEFAULT_*_MODEL` environment value, `_resolved_cli_model`) verbatim into a `#` comment line that is then spliced into `.claude/defaults/model-config.yaml` by `_write_text_atomic`. A newline or carriage return in either value ends the comment and injects arbitrary YAML into the catalog cheval loads. The sibling `reprobe_trigger` is correctly `json.dumps`-quoted. Trust context: operator-controlled arguments on an operator tool, so not an exploit path; it is the one place in the change where untrusted-shaped text reaches a System-Zone file without validation.
**Confidence:** high that the injection is possible; severity LOW for the trust context.
**Remediation:** Reject control characters (`\r`, `\n`, `#` is fine) in `host_route` and `cli_model` before the write, or render the comment via `json.dumps` like the trigger.
**References:** CWE-93 Improper Neutralization of CRLF Sequences (https://cwe.mitre.org/data/definitions/93.html); CWE-20 (https://cwe.mitre.org/data/definitions/20.html)

### [LOW-013] The probe inherits the full parent environment where the adapter strips credentials (audit-originated)
**Component:** `head/tools/ceiling-probe-live.py:217` (`env = {**os.environ, "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1"}`)
**Description:** The headless adapter spawns the CLI with `env=build_headless_subprocess_env()` (`headless_cli.py:380`), whose contract is `"never inherit subprocess env"` and which strips `_HEADLESS_STRIPPED_AUTH_VARS` (other providers' API keys and auth-mode selectors). The probe, whose stated goal is `"one builder, so the probe measures the shape the adapter dispatches"` (D-3.9), passes the operator's entire environment, including any `OPENAI_API_KEY` / `GOOGLE_API_KEY`, to the `claude` process. The CLI does not need them.
**Confidence:** medium. **Remediation:** Build the env through `build_headless_subprocess_env()` and add the auto-memory switch on top.
**References:** CWE-526 Cleartext Storage of Sensitive Information in an Environment Variable (https://cwe.mitre.org/data/definitions/526.html)

### [LOW-014] The opt-in is read from the reviewed tree's config by cwd walk; the enabling file is never named (dissent DISS-C-001, triaged)
**Component:** `head/.claude/adapters/loa_cheval/config/loader.py:113-126`, `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:124`
**Description:** The gate resolves `.loa.config.yaml` from `_find_project_root()` at every `complete()`; the adapter's own comment notes `"the caller's cwd is the reviewed tree"` (agy_headless_adapter.py:147). The dissent argues a config landed in a reviewed checkout can opt the reviewer into the argv exposure. This audit does not accept that as new attack surface: the same file already governs every `hounfour` routing decision (providers, endpoints, headless mode), and before this change agy dispatched with no gate at all, so the change strictly narrows exposure. What is missing is attribution: the one-time argv WARN does not say which file enabled the route.
**Confidence:** low (as a risk); high (as a logging gap). **Remediation:** Include the resolved config path in the one-time WARN; consider resolving the root once at cheval start and threading it to the adapter.

### [LOW-015] No test, type-check or build evidence in the implementation report
**Component:** `pr/PR.md` (`FAST-GATE`); `head/.claude/skills/bridgebuilder-review/dist/.build-manifest.json` (timestamp 2026-10-07T09:33:28Z) is the only evidence a build ran. The dist bundles do mirror their sources (`readAgyGate`/`notPlanned` present in `dist/config.js` and `dist/core/multi-model-pipeline.js`; 916000 in `dist/core/truncation.generated.js`). This audit could not execute pytest, bats or `tsc --noEmit` against head (see scope notes). Paste the runs into the report on resubmission.

---

## Observations

None demoted. No HIGH finding in this audit is marked speculative; `excluded` is 0.

---

## Cross-Model Observations

Dissent ran as `adversarial-review.sh --type audit --sprint-id sprint-1 --diff-file pr/head.diff --json`; envelope `grimoires/loa/a2a/sprint-1/adversarial-audit.json` (`metadata.status: reviewed`, `metadata.model: gemini-3.1-pro`, `metadata.type: audit`). The primary chain exhausted on this host (`gpt-5.5-pro`, `gpt-5.5`, `gemini-3.1-pro` all `api_failure`; `claude-headless` skipped as shared with the companion); the companion `claude-headless` answered and is `counted_as: sole_voice` (`verdict_quality.voices_planned: 4`, `voices_succeeded: 1`). `hallucination_filter.applied: true, downgraded: 0`. Two findings, both from the companion voice, triaged:

- **DISS-C-001** (MEDIUM, `agy_opt_in_enabled`, cross-file) — the opt-in read from the reviewed tree's config by cwd walk. Partially accepted: recorded as LOW-014 (not new attack surface; attribution gap is real).
- **DISS-C-002** (LOW, `build_headless_argv`) — claims a hostile `extra.effort` value such as `--dangerously-skip-permissions` is placed verbatim after `--effort`. **Refuted.** Both callers validate before the builder: the adapter's `_resolve_effort` accepts only `_ALLOWED_EFFORTS` and warns otherwise (`head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:344-381`), and the probe passes the literal `"low"` (`head/tools/ceiling-probe-live.py:177`). cheval's `resolve_effort` validates against `_EFFORT_LEVELS` too. Not tallied.

The dissent did not reach HIGH-001; it is confirmed here from the code independently of the review.

**DEGRADED_SECURITY_REVIEW:** the second voice is missing in the sense of the skill's rule (`counted_as: sole_voice`, primary never answered). The marker is set; the audit's own reading of every touched file compensates, and the dissent's advisory value is noted as limited to the two findings above.

## Rejected dissent payloads

None: the envelope's `metadata.rejected_summary` is `[]`, `metadata.rejected_sidecars` is `[]`, and no `adversarial-rejected-audit*.jsonl` sidecar exists beside it.

---

## Security Checklist Status

### Secrets & Credentials
- [x] No hardcoded secrets (the refusal message names a config key only; the probe record stores region/prefix values and the presence, not the value, of the Bedrock switch)
- [x] No new secret-bearing files; `.run/` artifacts in `pr/head/.run/` are untracked runtime output, not part of the diff
- [ ] Probe subprocess env not minimised (LOW-013)

### Authentication & Authorization
- [x] Opt-in is config-only; environment overrides tested inert (`test_no_environment_override`)
- [x] Gate fails closed on unreadable config (`test_an_unparsable_config_reads_as_off`); `_find_project_root` edge is LOW-005
- [x] Opted-in path preserves the one-time argv-exposure WARN

### Input Validation
- [x] yq expressions are fixed strings; `execFileSync` without a shell; prompt on stdin in the probe; needle is `secrets.token_hex`
- [x] Effort values validated at every entry (`resolve_effort`, `_resolve_effort`, argparse choices, schema enum)
- [ ] `host_route` / `cli_model` reach a YAML comment unvalidated (LOW-012)

### Data Privacy
- [x] No PII; redaction of known env keys preserved in cheval's catch-all
- [x] Probe caps captured CLI output at 1 MB and removes its workspace

### Supply Chain
- [x] No new dependencies; dist bundles mirror sources

### API Security / Resilience
- [ ] Chain walk aborts on the gated hop (HIGH-001)
- [x] Breaker not tripped by the refusal (`retry.py:498-500` re-raises `ChevalError` before `_record_failure`)
- [x] Probe retries transient classes with backoff and a cumulative budget; partial outcomes never write

---

## Threat Model Summary

**Trust Boundaries:**
- Operator config (`.loa.config.yaml`, the catalog) → cheval and planners: trusted, operator-owned; the opt-in key is read from it only.
- Reviewed diff → `agy -p` argv: the exposure FR-1 gates; closed by default after this change.
- CLI stdout/stderr → probe classifier: untrusted text, parsed as JSON with fallbacks, capped at 1 MB.

**Attack Vectors:**
- Local user reading `/proc/<pid>/cmdline` during an agy hop: mitigated by default-off; residual when opted in (documented).
- Hostile config in a reviewed checkout flipping the opt-in: same trust as the rest of `hounfour`; residual, LOW-014.
- Control characters in probe CLI arguments landing in the System-Zone catalog: operator self-inflicted; LOW-012.

**Mitigations:** default-off gate with YAML-boolean-only semantics; no env override; fail-closed reads; argv WARN on opt-in; needle-verified probe accepts; I2 clamp on catalog writes; atomic catalog replace.

**Residual Risks:** availability regression on every Google-terminated chain until HIGH-001 is fixed; a 936000 input bound on routes the probe never measured (MED-002).

---

## Positive Findings

- One Python predicate for the opt-in, with the string-`"true"`, integer `1` and non-mapping `headless` cases all pinned negative in Python, four shells and TypeScript.
- The refusal happens before discovery, workspace creation, WARN or spawn, and the test asserts each of those seams is untouched (`test_off_refuses_before_any_discovery_or_spawn`).
- `build_headless_argv` gives the adapter and the probe one argv builder, with a test comparing the two.
- The probe's fake-CLI harness asserts zero live spend via the MODELINV ledger's byte-identity and covers classification, retry, budget, re-anchoring and the clamp, including `python3 -I` from a foreign cwd.
- Bridgebuilder fails closed when every voice is gated (`modelAdapters.length === 0` throws) and subtracts `notPlanned` from the participation check rather than treating gated voices as missing.
- Catalog checksum, truncation table (936000 − 20000 = 916000) and dist bundles are consistent with the sources.

---

## Recommendations

### Immediate Actions (24 Hours)
1. Fix HIGH-001: plan-time skip of gated `gemini-headless` hops inside cheval (or a dedicated `continue` arm), plus primary-chain filtering in `adversarial-review.sh`, with the three-hop walk test.
2. Commit or link the Opus 5.5 probe record and correct the `method` provenance (MED-002).

### Short-Term Actions (1 Week)
1. Gate `prefer-cli` in both "routes to agy" predicates or document the choice (MED-001).
2. Validate `host_route` / `cli_model` and use `build_headless_subprocess_env()` in the probe (LOW-012, LOW-013).
3. Fix the comment, schema and doc wording (LOW-002, LOW-003); port the skipped writer assertions onto `SYNTH` (LOW-011); document `opt_in_required` in both skill docs (LOW-010).
4. Run pytest, bats, `node --test` and `tsc --noEmit` and paste the output into the implementation report (LOW-015).

### Long-Term Actions (1 Month)
1. Refactor the bisection into a dataclass (MED-003).
2. One flavour-aware yq helper for the opt-in predicate (LOW-001).
3. Let observed context-limit verdicts lower an `operator_set` calibrated bound (MED-002).

---

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 3 |
| Low | 15 |

One-way rule: critical + high = 1 > 0 ⇒ CHANGES_REQUIRED.

## Verdict

**CHANGES_REQUIRED**

**Next Steps:**
1. `/implement sprint-1` to address HIGH-001 (and, in the same pass, MED-001 and MED-002's provenance).
2. `/review-sprint sprint-1`, then `/audit-sprint sprint-1`.

---

**Audit Completed:** 2026-10-21T14:05:00Z
**Next Audit Recommended:** on resubmission
**Remediation Tracking:** `grimoires/loa/a2a/audits/2026-10-21/`

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":3,"low":15},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T14:05:00Z"} -->
