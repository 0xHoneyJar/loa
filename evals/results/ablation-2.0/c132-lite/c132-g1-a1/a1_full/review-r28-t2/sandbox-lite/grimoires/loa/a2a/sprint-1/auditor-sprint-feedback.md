# Security & Quality Audit Report — sprint-1 (review-r28)

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Scope:** the pull request in `pr/` (sprint-264: four review-catch arms, `eval_only` batch-context refusal, validate-suite arm schema) — `pr/head.diff`, 11 files under `evals/`, 323 insertions / 24 deletions. Citations are `head/<path>:<line>` from `pr/head/`.
**Methodology:** Systematic 5-category review (Security, Architecture, Code Quality, DevOps; Blockchain not applicable), source→sink trace of every new input, cross-model security dissent on `pr/head.diff`.

---

## Pre-flight

- `grimoires/loa/a2a/sprint-1/engineer-feedback.md` exists but its verdict is **CHANGES REQUIRED** (1 HIGH, 5 MEDIUM, 4 LOW), not "All good". The skill's Phase 0 would stop here; the task brief directs the audit to run on the PR as frozen, so this audit proceeds and records the deviation. The review's HIGH is re-derived independently below (HIGH-001), not inherited.
- `grimoires/loa/a2a/sprint-1/adversarial-review.json` carries `metadata.model: gpt-5.5-pro` (review-gate dissent present).
- `grimoires/loa/known-failures.md` is absent (the session-start `[KF-SURFACE]` warning); triaged without it.
- No beads (`br` not installed); no `grimoires/loa/a2a/subagent-reports/` directory, so the documentation audit was done manually (§Documentation Audit).
- Input guardrails (`guardrails-orchestrator.sh --skill auditing-security`): `PROCEED`.
- `security-audit-scope.sh` over `pr/head`: sources 0, sinks 2 (command_exec 1, file_operations 1), auth files 1, LLM files 1. Working file: `grimoires/loa/a2a/audits/2026-10-21/SECURITY_ANALYSIS_TODO.md`; machine findings: `grimoires/loa/a2a/audits/2026-10-21/findings.jsonl`.

**Scope limits.** `pr/` holds only the touched files. `lib/sandbox-mount.sh`, `took-effect.sh`, `gen-fixtures.py` and the committed suite root `grimoires/loa/evals/ablation-2.0/` are referenced by the change but not in it. Where a claim depends on them it is marked `[ASSUMPTION]` or "Unable to assess".

---

## Executive Summary

The harness side of this change is built the way a guard should be: the `eval_only` refusal sits at `head/evals/harness/pipeline-run.sh:258-262`, before any directory or file is created (`mkdir -p "$RUN_DIR"` is at `:356`; no `mkdir`/`mktemp`/redirect precedes `:258`), only the exact value `1` opens it, and `run-ablation.sh` sets the variable as a command prefix on the trial only (`head/evals/harness/run-ablation.sh:1300-1301`), never in its own environment. The validator's new per-arm schema is type-exact (`gates: 0` is rejected), rule ids reach `python3 -I` as a single argv, and the `oracle_open ⇒ eval_only` coupling is enforced at `head/evals/harness/validate-suite.sh:179`. No secrets, no new network surface, no shell interpolation of untrusted data.

Two things keep this from approval. First, the sprint's primary deliverable does not work: the three review-catch-only arms that become decision components at `head/evals/harness/ablation-report.py:1913` are classified by `primaries()` (`:653-658`) as needing the pass-rate primary, which can never pair for an arm that runs no build task, so `decide()` returns `inconclusive … no valid pair (hidden_test_pass_rate)` on every run and `decidable` is permanently false. This is the one HIGH; it was found independently by the review, by both dissent voices, and by this audit's trace. Second, a defense-in-depth gap: the runtime refusal keys on the declared `eval_only` flag rather than on the toggle that actually opens the oracle (`toggles.oracle_open`), and the coupling between them is enforced only by a validator the runtime never calls (MED-001).

**Overall Risk Level:** MODERATE (functional defect in the deliverable; no exploitable security path)

**Key Statistics:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 6 |
| Low | 5 |

---

## Category Scores (Rubric-Based Assessment)

**Scoring Method:** Each dimension scored 1-5 per `resources/RUBRICS.md`

| Category | Score | Dimensions |
|----------|-------|------------|
| Security | 3.8/5 | IV:4 AZ:3 CI:4 IN:4 AV:4 |
| Architecture | 3.4/5 | MO:3 SC:4 RE:3 CX:4 ST:3 |
| Code Quality | 3.4/5 | RD:4 TC:3 EH:4 TS:3 DC:3 |
| DevOps | 3.8/5 | AU:4 OB:3 RC:4 AC:4 DS:4 |
| Blockchain | n/a | *(not applicable)* |
| **Overall** | **3.6/5** | *Weighted average (Security ×2)* |

**Risk Level Mapping:** 4.5-5.0: LOW | 3.5-4.4: MODERATE | 2.5-3.4: HIGH | 1.0-2.4: CRITICAL

**Machine-Parseable Output:** `grimoires/loa/a2a/audits/2026-10-21/findings.jsonl`

---

## Critical Issues (Fix Immediately)

None.

---

## High Priority Issues (Fix Before Production)

### [HIGH-001] Review-catch-only decision arms can never be decided

**Severity:** HIGH | **Score:** 2/5 | **Confidence:** high
**Component:** `head/evals/harness/ablation-report.py:1913` (root cause `:653-658`)
**Criterion:** CQ-TC / Karpathy 4 (goal-driven: non-trivial logic with no check that fails when it breaks)

**Reasoning Trace:**
> The change makes `a0_bare_fable`, `a1_review_only`, `a1_no_dissent` components: `"components = [a["id"] for a in arms if a["id"] not in (CONTROL, BARE) and not a.get("absent") and a.get("eval_only") is not True]"` (`:1913`). Their `task_types` are `[review-catch]` (`head/evals/suites/ablation-2.0.yaml:98-103`). `primaries()` reads `"if "all" in types or REVIEW in types: return list(pba.get("all_types") or [PASS, CATCH])"` (`:656-657`), so each gets both primaries. `compare()` restricts the pass-rate metric to build tasks: `"types = (REVIEW,) if metric in CATCH_METRICS else BUILD_TYPES"` (`:732`); a review-catch-only arm has no cell on any build task, so the comparison has `n == 0`, `usable()` (`:577-579`) is false, `decide()` sets `nopair` (`:849-850`) and, unless `investigate`/`keep` fired on the catch rate first, returns `"inconclusive", "inconclusive: " + …` with the clause `no valid pair (hidden_test_pass_rate)` (`:873-877`). `out["decidable"] = bool(seen) and all(usable(p) for p in comps)` (`:922`) is therefore always false. The suite's `primaries_by_arm` (`head/evals/suites/ablation-2.0.yaml:113`) has only `build_only` and `all_types`; there is no review-only rule.

**Description:** The verdicts `a1_review_only` and `a1_no_dissent` exist to reach (`remove` — drop the AUDIT gate / the review dissent; `simplify`) are unreachable. Each run of these arms lands on `investigate`, `keep` or `inconclusive`, and every `inconclusive` triggers `inconclusive_extension_trials: 2` (`:129`) — paid trials with no possible payoff.
**Impact:** The sprint's primary deliverable (decidable review-catch arms for the cycle-131 AUDIT-gate and dissent questions) is non-functional while the report's tests pass: AR-12 (`head/evals/tests/ablation-report.bats:189`) and the `decisions | length == 9` assertion (`:342`) count rows, not decidability, so the gap is invisible to CI.
**Proof of Concept:**
```
A batch where a1_review_only matches a1_full on defect_catch_rate (d within ±0.03, interval
straddling 0) at 40 % lower cost satisfies the pre-registered `remove` predicate
(ablation-2.0.yaml:126) — the report prints
  **Inconclusive** — inconclusive: no valid pair (hidden_test_pass_rate)
with pass-rate Δ = "no pair" and decidable: false.
```
**Remediation:**
```yaml
# ablation-2.0.yaml rules
primaries_by_arm: {build_only: [hidden_test_pass_rate], review_only: [defect_catch_rate],
                   all_types: [hidden_test_pass_rate, defect_catch_rate]}
```
```python
# ablation-report.py primaries()
if "all" in types or any(t in BUILD_TYPES for t in types) and REVIEW in types:
    return list(pba.get("all_types") or [PASS, CATCH])
if REVIEW in types:
    return list(pba.get("review_only") or [CATCH])
return list(pba.get("build_only") or [PASS])
```
Render `n/a (review-only)` for the pass-rate column at the three `"n/a (build-only)"` sites (`:1634`, `:1649`, `:1699`). Add a `gen-fixtures.py` scenario with planted rows for `a1_review_only` that reaches `remove` and one that reaches `keep`, asserting `.decidable == true` and the `.primaries` list, as AR-6 does for build-only arms.
**References:** CWE-1164 Irrelevant Code / unreachable outcome — https://cwe.mitre.org/data/definitions/1164.html

---

## Medium Priority Issues (Address in Next Sprint)

### [MED-001] The `eval_only` refusal gates the declaration, not the toggle that opens the oracle

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `head/evals/harness/pipeline-run.sh:258-262`
**Criterion:** SEC-AZ (authorization / guard placement)
**Description:** `"EVAL_ONLY=false; [[ "$(jq -r '.eval_only // false' <<<"$ARM_DEF")" == true ]] && EVAL_ONLY=true"` (`:258`). The hazard the refusal exists for is the open mount — `toggles: {oracle_open: true}` hands the evaluated agent the review-catch answer paths (dry run: `overlay=none(oracle_open)`, `:338`). The rule that ties `oracle_open` to `eval_only` lives only in `head/evals/harness/validate-suite.sh:179`, which `pipeline-run.sh` never invokes. A `--suite-file` that sets `oracle_open: true` and omits `eval_only` (an edited copy, a stale pre-FR-5 file) runs the open mount with no refusal, writes a normal `pipeline.json` and arm evidence, and nothing but `oracle_open=true` in `meta/arm-evidence.txt` distinguishes the rows from closed-mount rows. Independently raised by the dissent (DISS-C-001).
**Impact:** Operator-error class, not an attacker path: the suite file is an in-tree artefact and `--suite-file` is operator-controlled. The refusal's stated purpose ("refused … before the run directory exists, so no pipeline.json and no infrastructure_error is ever written", `:141-147`) is met for the committed suite but not for the toggle it protects against.
**Remediation:** Derive `EVAL_ONLY` from either marker so the runtime enforces what the validator declares:
```bash
EVAL_ONLY=false
if [[ "$(jq -r '.eval_only == true or (.toggles.oracle_open == true)' <<<"$ARM_DEF")" == true ]]; then EVAL_ONLY=true; fi
```
or `die_usage` when `oracle_open` is true and `eval_only` is not. Add a bats case: `oracle_open: true` without `eval_only` is refused outside the batch context.
**References:** CWE-807 Reliance on Untrusted Inputs in a Security Decision — https://cwe.mitre.org/data/definitions/807.html ; OWASP A04:2021 Insecure Design — https://owasp.org/Top10/A04_2021-Insecure_Design/

### [MED-002] A bare baseline variant is counted as a decision component

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `head/evals/harness/ablation-report.py:1913`
**Criterion:** CQ-TC / report integrity
**Description:** `a0_bare_fable` is `toggles: {loa_mount: false, bare_model: fable}, phases: [BARE]` (`head/evals/suites/ablation-2.0.yaml:98`) — A0 on the review model — yet only `a0_bare` is excluded from `components` (by id). It inflates `k` to 9 in the expected-false-positive line (`:1928-1932`) and is handed a `keep`/`remove`/`simplify` verdict that is meaningless for a baseline. The PR's own test comment calls the three arms "control arms" (`head/evals/tests/ablation-report.bats:189`).
**Impact:** The pre-registered component count and the decision table misstate what is being decided.
**Remediation:** Exclude `toggles.loa_mount == false` arms (or a declared `decision_arm: false`) from `components`; report A0F beside A0 in the H1 section.

### [MED-003] The `eval_only` arm's results are rendered nowhere

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `head/evals/harness/ablation-report.py:2003`
**Criterion:** DO-OB (observability)
**Description:** `a1_full_openmount` rows pass `_classify` and are kept, but the arm is in neither `components` nor `detail_arms` (`"detail_arms = [BARE, CONTROL] + components"`, `:2003`). Beyond the oracle-exposed sensitivity count (`:1624`, `:1685`) its rows appear in neither `report.md` nor `report.json`. The open-mount A/B the arm exists for (cycle-131 FR-5) has no output.
**Impact:** Spend on the arm produces no readable result.
**Remediation:** Render `eval_only` arms in a dedicated "Evaluation-only arms" table (catch rate vs `a1_full`, cost), labelled as deciding nothing.

### [MED-004] The dry run re-implements the toggle→config mapping

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `head/evals/harness/pipeline-run.sh:341-345`
**Criterion:** ARCH-MO (duplication of a security-relevant mapping)
**Description:** The `config_edits=` line is an inline jq mapping of `companion_voice`, `gates`, `dissent`, `flatline` to `.loa.config.yaml` keys (`"sb_edits="$(jq -r '[ (if .companion_voice == false then …"`, `:341`). `[ASSUMPTION]` the source of truth is `apply_arm_toggles` in `lib/sandbox-mount.sh` (not in the diff). The dry run is the operator's way to confirm which gates a sandbox will have disabled; when the library changes, it misreports, and the dry-run tests (`head/evals/tests/pipeline-run.bats:1195-1221`) pin the copy, not the library. The `dissent == false and gates != false` precedence at `:343` could not be verified against the library.
**Impact:** An operator reads "gates on" from a dry run whose real run has them off, or vice versa.
**Remediation:** Add a `plan_arm_config_edits <toggles-json>` function to the library, called by both `apply_arm_toggles` and the dry run.
**References:** CWE-1041 Use of Redundant Code — https://cwe.mitre.org/data/definitions/1041.html

### [MED-005] A default batch never schedules the four new arms

**Severity:** MEDIUM | **Confidence:** high
**Component:** `head/evals/suites/ablation-2.0.yaml:55`
**Criterion:** DO-AU
**Description:** `"priority: [a0_bare, a1_full, a2_no_sprint_plan, a3_one_voice, a4_no_gates, a7_effort_medium, a5_no_flatline, a6_one_window]"` omits the four arms; `run-ablation.sh` defaults `--arms` to `priority` minus absent arms (`head/evals/harness/run-ablation.sh:570-571`). `cut_ladder` (`:46`) is silent on them too.
**Impact:** The arms run only when named on `--arms`; the operator learns they exist from a missing row.
**Remediation:** Append them to `priority` and say where the cut ladder drops them, or state in the arms comment that they are `--arms`-only.

### [MED-006] The implementation report overstates the change and leaves new tests dependent on unverifiable state

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `pr/PR.md:1` (= `grimoires/loa/a2a/sprint-1/reviewer.md:3`)
**Criterion:** CQ-DC (documentation) / process
**Description:** The title claims "the cycle-131 suite root (bounds 50/40) with its image self-check"; no file under `grimoires/loa/evals/` is in `pr/head.diff`. The report carries no `## AC Verification` walkthrough. VS-14 and VS-16 (`head/evals/tests/validate-suite.bats:244-299`) require `rule_<id>() {` functions `bare_model_fable`, `review_only_phases`, `no_review_dissent_envelope`, `oracle_closed`, `oracle_open_recorded` in `took-effect.sh`, which is not in the diff — if any is missing, the committed suite itself fails `validate-suite.sh` (`:87`, `:173-174`). RAB-c131-5's `cp -r "$REPO_ROOT/grimoires/loa/evals/ablation-2.0"` (`head/evals/tests/run-ablation.bats:1196`) reuses a pre-existing pattern (`:144`, `:184`), so that dependence is not new. **Unable to assess** the five rule functions.
**Impact:** The gates reviewed less than the title describes; a missing rule function would make the committed suite invalid at validation time.
**Remediation:** Trim the title to the diff or add the suite-root files; add the AC walkthrough with `file:line` evidence; confirm the five `rule_<id>()` functions exist on the base.

---

## Low Priority Issues (Technical Debt)

### [LOW-001] Stale "over 6 components" comment
**Severity:** LOW | **Confidence:** high
**Component:** `head/evals/suites/ablation-2.0.yaml:117`
**Description:** `"multiple_comparisons: none # expected false positives at 0.90 over 6 components printed"`; the report now prints 9 (AR-12, `head/evals/tests/ablation-report.bats:189`).
**Remediation:** Update the comment or drop the number.

### [LOW-002] Rule-id scrape is formatting-sensitive
**Severity:** LOW | **Confidence:** medium
**Component:** `head/evals/harness/validate-suite.sh:87`
**Description:** `"RULE_IDS="$(sed -n 's/^rule_\([a-z_][a-z0-9_]*\)() *{.*$/\1/p' "$TOOK_EFFECT" …"`. A rule written `rule_x () {` or with the brace on the next line vanishes silently; the committed suite then fails with a misleading "unknown rule id". Only the all-missing case is caught (`:88`). VS-16 pins the same literal shape (`head/evals/tests/validate-suite.bats:286`).
**Remediation:** Accept optional whitespace and either brace style, or have `took-effect.sh` print `--list-rules`.

### [LOW-003] Duplicate arm ids pass validation
**Severity:** LOW | **Confidence:** high
**Component:** `head/evals/harness/validate-suite.sh:157`
**Description:** The new per-arm loop does not reject two arms sharing an `id`; `arm_ids` (`:146`) is a set. The duplicate check at `:239` is for task ids. At runtime the first definition wins (`head/evals/harness/pipeline-run.sh:242`, `head/evals/harness/run-ablation.sh:576`) and the second is silently dead.
**Remediation:** Count ids before the loop and emit `arm <id> is declared twice`.

### [LOW-004] `eval_only` typing differs across its three consumers
**Severity:** LOW | **Confidence:** medium
**Component:** `head/evals/harness/ablation-report.py:1913` vs `head/evals/harness/pipeline-run.sh:258`
**Description:** `jq -r '.eval_only // false'` prints `true` for the string `"true"`, so the pipeline refuses such an arm, while the report's `a.get("eval_only") is not True` keeps it as a component. Only the optional validator (`validate-suite.sh:177`) rejects the string.
**Remediation:** Use `.eval_only == true` in jq so both runtime consumers agree with the validator.

### [LOW-005] The batch-context variable is a soft guard and should be documented as such in the suite
**Severity:** LOW | **Confidence:** high
**Component:** `head/evals/harness/pipeline-run.sh:259`; `head/evals/suites/ablation-2.0.yaml:32-34`
**Description:** `LOA_ABLATION_BATCH_CONTEXT` is an unauthenticated, fixed-value env variable; the header instructs operators to set it by hand for dry runs (`:145-146`), and once exported in a shell it applies to every subsequent manual run, real runs included. The header frames it correctly as a guard against accidental invocation; the suite comment does not. Dissent DISS-C-002, confirmed.
**Remediation:** Add "not a security boundary" to the suite comment; consider a per-invocation `--batch-context` flag (set by `run-ablation.sh`) over an inheritable variable.
**References:** CWE-807 — https://cwe.mitre.org/data/definitions/807.html

---

## Security Checklist Status

### Secrets & Credentials
- [x] No hardcoded secrets (none introduced; `LOA_EVAL_CREDS_HOME` handling unchanged)
- [x] No credentials in logs or test fixtures

### Authentication & Authorization
- [x] The refusal is placed before any artefact exists (`pipeline-run.sh:258-262` vs `:356`)
- [ ] The guard keys on the protected condition (MED-001 — keys on the declaration)
- [x] Env guard documented as not a security boundary in the harness header (LOW-005 for the suite)

### Input Validation
- [x] Toggle values type-exact (`validate-suite.sh:167`); `eval_only` boolean (`:177`); `took_effect` list of non-empty strings (`:170-171`)
- [x] Rule ids reach `python3 -I` as one argv (`:122`); no shell interpolation of YAML values
- [x] Only the exact value `1` opens the batch context (`pipeline-run.sh:259`)
- [ ] Duplicate arm ids rejected (LOW-003)

### Data Privacy
- [x] No PII; no new logging of user data

### Supply Chain
- [x] No new dependencies (yq, jq, python3 already required)

### API / Process Security
- [x] Error messages name the arm and the reason only; no path or secret leakage
- [x] `set -euo pipefail` retained in all three scripts

---

## Threat Model Summary

**Trust Boundaries:**
- Suite file (`--suite-file`, in-tree default) → `pipeline-run.sh` / `run-ablation.sh` / `ablation-report.py`: trusted in-tree artefact, operator-overridable.
- Operator shell environment (`LOA_ABLATION_BATCH_CONTEXT`) → `pipeline-run.sh`: trusted operator, accidental-misuse guard only.
- `took-effect.sh` source text → `validate-suite.sh` rule-id set: in-tree script.

**Attack Vectors:**
- Open-mount run outside a batch via a suite file lacking `eval_only` (MED-001): operator error, LOW-MODERATE risk, contaminates evaluation rows rather than exposing data.
- Inherited `LOA_ABLATION_BATCH_CONTEXT=1` (LOW-005): operator error, LOW risk.

**Mitigations:**
- Refusal before artefact creation; exact-value check; command-prefix assignment in the runner; validator coupling `oracle_open ⇒ eval_only`.

**Residual Risks:**
- The validator is not on the runtime path (MED-001); the dry run's config mapping can drift from the library (MED-004).

---

## Documentation Audit

No `grimoires/loa/a2a/subagent-reports/documentation-coherence-*.md` exist in this workspace; manually verified:
- `pipeline-run.sh` header (`:46-51`, `:141-147`, `:150`) documents the dry-run lines, the refusal and the new env var; `--help` range `2,156p` matches the header (closing rule at `:157`).
- `run-ablation.sh` header (`:163-166`) documents the per-trial variable.
- `validate-suite.sh` header rule 8 (`:46-53`) documents the schema; `usage()` range `2,55p` matches (closing rule at `:57`).
- `ablation-2.0.yaml` documents `eval_only` (`:32-34`) and the four arms (`:94-97`).
- Red flags: the `rules` comment at `:117` is stale (LOW-001); the PR title overstates the diff (MED-006). No security-critical code is uncommented.

---

## Positive Findings

- The refusal exits before `mkdir -p "$RUN_DIR"`; the tests prove it for the dry run, the real run and four non-`1` values (`head/evals/tests/pipeline-run.bats:1223-1244`).
- `c131_arms` now loads the committed arm definitions from the real suite instead of a hand-written copy (`head/evals/tests/pipeline-run.bats:1017-1021`), so pipeline tests exercise the shipped shape.
- The stub proves the `<unset>` branch so the batch-context assertion is not vacuous (`head/evals/tests/run-ablation.bats:1204-1208`).
- Type-exact toggle validation (`gates: 0` rejected) and the `oracle_open ⇒ eval_only` rule close the obvious misuse at validation time.

---

## Cross-Model Observations

Phase 1C dissent on `pr/head.diff`: `adversarial-review.sh --type audit --sprint-id sprint-1 --diff-file pr/head.diff --json`. Envelope: `grimoires/loa/a2a/sprint-1/adversarial-audit.json`. `verdict_quality`: `voices_planned 2`, `voices_succeeded 2` (`codex-headless`, `claude-headless`), `consensus_outcome: consensus`, `chain_health: ok`, `companion_voice.status: succeeded`, `counted_as: independent_voice`, `hallucination_filter.downgraded: 0`. Not degraded. Advisory input, never tallied:

- **DISS-C-001 (MEDIUM, authz)** — the refusal keys on `eval_only`, not `toggles.oracle_open`; a suite file omitting `eval_only` runs the open mount unrefused. Confirmed by trace; it is MED-001. Its sub-claim that the string `"true"` bypasses the refusal is wrong in that direction — `jq -r` prints `true` for the string, so such an arm is refused — but the typing inconsistency is real and recorded as LOW-004.
- **DISS-C-002 (LOW, config)** — the batch context is an inheritable fixed-value env variable. Confirmed; LOW-005.

## Rejected dissent payloads

None. `metadata.rejected_summary` is `[]`, `metadata.rejected_count` is 0, `companion_voice.rejected_sidecar` is `null`, and no `adversarial-rejected-audit*.jsonl` exists beside the envelope.

---

## Review demotion cross-check

The review trailer (`grimoires/loa/a2a/sprint-1/engineer-feedback.md`) carries `excluded: 0` — no demoted HIGH to confirm. `excluded_confirmed: 0`.

---

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 6 |
| Low | 5 |

---

## Recommendations

### Immediate Actions (24 Hours)
1. HIGH-001: add `review_only: [defect_catch_rate]` to `primaries_by_arm`, teach `primaries()` the review-only shape, render `n/a (review-only)`, and add a fixture scenario proving `a1_review_only` can reach `remove` and `keep` with `.decidable == true`.
2. MED-001: make the runtime refusal fire on `toggles.oracle_open == true` as well as `eval_only == true`, with a bats case.

### Short-Term Actions (1 Week)
1. MED-002/MED-003: decide whether `a0_bare_fable` is a baseline or a component; render the `eval_only` arm in its own table.
2. MED-005: add the four arms to `priority` and the cut ladder, or document them as `--arms`-only.
3. MED-006: reconcile the PR title with the diff; add `## AC Verification`; confirm the five `rule_<id>()` functions exist in `took-effect.sh`.

### Long-Term Actions (1 Month)
1. MED-004: single shared toggle→config mapping in `lib/sandbox-mount.sh` used by both `apply_arm_toggles` and the dry run.
2. LOW-001…LOW-005 as technical debt.

---

## Verdict

**CHANGES_REQUIRED**

The one-way rule applies: critical + high = 1 > 0. The HIGH is a functional defect in the sprint's primary deliverable, not a security exposure; the security posture of the harness change is sound apart from the defense-in-depth gap in MED-001.

**Next Steps:**
1. `/implement sprint-1` to address HIGH-001 and MED-001 (and the MEDIUMs the engineer chooses to take now).
2. `/review-sprint sprint-1`, then `/audit-sprint sprint-1`.

---

**Audit Completed:** 2026-10-21T18:16:41Z
**Next Audit Recommended:** after the fix round
**Remediation Tracking:** `grimoires/loa/a2a/audits/2026-10-21/`

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":6,"low":5},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T18:16:41Z"} -->
