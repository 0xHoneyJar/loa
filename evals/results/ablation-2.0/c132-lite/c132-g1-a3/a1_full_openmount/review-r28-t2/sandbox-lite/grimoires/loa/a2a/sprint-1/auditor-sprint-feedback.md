# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)
**Change under audit:** `pr/head.diff` — sprint-264 (cycle-131): four review-catch arms, the `eval_only` batch-context refusal, validate-suite check 8, the report's `eval_only` exclusion. 11 files under `evals/`, +323/−24.

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

The shell side of this change is sound and defensively written. The `eval_only` refusal sits before any side effect (`head/evals/harness/pipeline-run.sh:258-262` precedes the run-directory `mkdir -p` at `:356`), opens only on the literal value `1`, and `run-ablation.sh` sets the marker on the trial command alone (`head/evals/harness/run-ablation.sh:1300-1301`). Validate-suite check 8 is type-exact (`0` is not `false`, `head/evals/harness/validate-suite.sh:168`), reads rule ids from the script that defines them with a character-restricted sed pattern (`:87`) and hands them to `python3 -I` as a single argv, and both `--help` ranges still end on the delimiter line they ended on before (`pipeline-run.sh:156`, `validate-suite.sh:57`). No secret, no injection vector, no new dependency, no privilege change.

The report side is not ready, and that is what blocks the sprint. Adding three review-catch-only arms as **components** and one `eval_only` arm that is declared but rendered nowhere changes what `ablation-report.py` emits in two ways no test asserts: (1) the pre-registered decision procedure can never return `remove` or `simplify` for the three new components, because the pass-rate primary they are assigned pairs over build tasks they never run; (2) the open-mount arm's rows are consumed by the analysis but appear in no table, no per-arm section and not in `report.json`. Both were independently restated by the review gate's cross-model dissent. The security dissent (two voices, not degraded) added a defence-in-depth gap — the refusal keys on the declarative `eval_only` flag rather than on the toggle that actually opens the oracle — which I confirm and tally as MEDIUM. A fourth MEDIUM is mine: the suite's `priority` list was not extended, so a batch launched without `--arms` never schedules any of the four new arms.

**Pre-flight deviation (recorded, not hidden):** the review gate's `engineer-feedback.md` reads `CHANGES REQUIRED`, not "All good"; Phase 0 of this skill would normally stop here. The task definition for this sprint directs the audit to run and write its feedback regardless, so it ran. The audit verdict is derived from this audit's own tally and does not depend on that deviation.

**Verification limits:** the workspace holds only the eleven touched files. `lib/sandbox-mount.sh`, `took-effect.sh`, `freeze.sh`, the bats fixtures and the suite root under `grimoires/loa/evals/` are absent, so **no test was executed** and every parity claim against those siblings is read from code. `br` is not installed (beads steps skipped). `grimoires/loa/known-failures.md` is absent (known-failures surface degraded). `[ASSUMPTION]` statements are marked inline.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 4 |
| Low | 6 |

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] Review-catch-only components can never reach `remove` or `simplify`

**Severity:** HIGH (confidence: high)
**File:** `head/evals/harness/ablation-report.py:1913` (components); `:653-658` (primaries); `:731-733` (compare pairs the pass-rate metric over build tasks only); `:846-887` (decide)
**Issue:** The three review-catch-only arms (`a0_bare_fable`, `a1_review_only`, `a1_no_dissent`; suite `head/evals/suites/ablation-2.0.yaml:98-103`) now enter `components`:
```python
components = [a["id"] for a in arms if a["id"] not in (CONTROL, BARE) and not a.get("absent") and a.get("eval_only") is not True]
```
`Analysis.primaries()` assigns BOTH primaries to any arm whose `task_types` contains `review-catch`:
```python
if "all" in types or REVIEW in types:
    return list(pba.get("all_types") or [PASS, CATCH])
return list(pba.get("build_only") or [PASS])
```
`compare()` for `hidden_test_pass_rate` restricts the task set to `BUILD_TYPES` (`:732-733`), so for an arm that runs no build task the comparison has zero pairs (`n == 0`) every time. `decide()` requires every primary `usable` (`usable()` at `:577-579`: `p["n"] > 0 …`) before it can return `remove` or `simplify`; `nopair` (`:850`) is always true for these arms and the `"no valid pair (hidden_test_pass_rate)"` clause (`:874-875`) is always appended, so the only reachable outcomes are `investigate`, `keep` and `inconclusive`. `decidable` (`:888`) is permanently false for them, which also feeds the version-level `decidable` at `:1671`.
**Failure scenario:** after a full, clean cycle-131 batch the Decisions table reads `inconclusive: no valid pair (hidden_test_pass_rate)` for A0F, A1R and A1N whatever their catch-rate result; the two outcomes the ablation exists to test for (can the AUDIT gate / the dissent be dropped?) are structurally unreachable, and the review-catch budget spent on those arms (cap USD 20 × 4 tasks × 3 trials per arm) buys no decision. `GOAL-DRIVEN:` no test asserts the decision state of a new component — `head/evals/tests/ablation-report.bats:189` and `:342` only count them.
**Fix:** add a `review_only` branch to `primaries()` (and `review_only: [defect_catch_rate]` to `rules.primaries_by_arm` in the suite, mirroring `build_only`) so an arm whose `task_types` is exactly `[review-catch]` is decided on `defect_catch_rate` alone; add a fixture scenario where a review-catch-only component with equal catch rate and ≥15 % lower cost reads `remove`. Alternatively, if these arms are evaluation controls (the suite comment at `:94-97` calls them "review-catch only" controls), exclude them from `components` as `a1_full_openmount` is and render them in the per-arm detail.
**Reference:** CWE-684 Incorrect Provision of Specified Functionality — https://cwe.mitre.org/data/definitions/684.html

### [HIGH-002] The `eval_only` arm's rows are consumed but reported nowhere

**Severity:** HIGH (confidence: high)
**File:** `head/evals/harness/ablation-report.py:1913` (excluded from components); `:2003` (`detail_arms = [BARE, CONTROL] + components`); `:1108-1123` (`list_reason`); `:1741-1745` (`render_per_arm` iterates `detail_arms` only); `:1865-1868` (`arms_json(metrics)` built from the same metrics); `:1959` (per-version row total)
**Issue:** `a1_full_openmount` is declared, not `absent`, and applies to `review-catch`, so `list_reason()` returns `None` for its rows and they enter `arm_rows` / `cells`. It is then excluded from `components` and therefore from `detail_arms`, so it has no Decisions row, no Per-arm section, no "listed (not decided)" entry and no key in `report.json .arms` (`:2135`, `:2175`). The only trace is the per-arm *count* of oracle-exposed rows in the oracle sensitivity block (`open_reported`, `:613`, `:689`, `:1685`) — never its catch rate, cost or secondaries. Its rows still count in `len(V['rows'])` at `:1959` (the `… 24 rows` line `head/evals/tests/ablation-report.bats:343` asserts), so totals no longer reconcile with the tables beneath them. Before this change every suite arm was a component, a baseline, or listed-with-reason; the new `eval_only` class is none of the three.
**Failure scenario:** a completed batch that ran the open-mount oracle A/B (cycle-131 FR-5: "what does the closed-mount overlay cost?") yields a report with no open-mount figures at all. Rows the report silently swallows are the class of defect the "Row treatment" contract (`:117-127`) was written to prevent.
**Fix:** render `eval_only` arms under a labelled "evaluation controls (never decided)" subsection of Per-arm detail (and include them in `arms_json`) with the catch-rate comparison against `a1_full`; or have `list_reason()` list them (`"eval_only arm <id>: reported, never decided"`) so the row accounting closes. Add a fixture row set for `a1_full_openmount` and assert where it lands.
**Reference:** CWE-1068 Inconsistency Between Implementation and Documented Design — https://cwe.mitre.org/data/definitions/1068.html

---

## Medium/Low Priority Issues

### [MED-001] A bare baseline counted as a removable component; the pre-registered k is stale
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/harness/ablation-report.py:1913`, `:1927-1931`; `head/evals/suites/ablation-2.0.yaml:94`, `:117`
- **Issue:** `a0_bare_fable` is "A0 on the review model" (suite `:94`), a `loa_mount: false` baseline, yet it is a component: `arm_report()` compares it with `a1_full` and `decide()` can print `keep`/`remove`/`simplify` for "component a0_bare_fable", which has no referent (nothing is removed). It also inflates `k` to 9 in the expected-false-positive sentence (`:1927-1931`), while per primary the comparison count is 6 (pass rate) / 5 (catch rate). The rules block is pre-registered and "mirrored in NOTES" (`:109`), and its own comment still reads `over 6 components` (`:117`) while AR-12 now asserts 9 (`head/evals/tests/ablation-report.bats:189`).
- **Fix:** treat `a0_bare_fable` like `BARE` (exclude from components, include in `detail_arms`) or document in a DEC why a second bare arm is a decision; update the `multiple_comparisons` comment and the NOTES mirror, or print k per primary.
- **Reference:** CWE-1068 — https://cwe.mitre.org/data/definitions/1068.html

### [MED-002] The toggle→config mapping now lives in three places with no parity check
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/harness/pipeline-run.sh:338-343` (dry-run jq re-derives the `.loa.config.yaml` keys `apply_arm_toggles` edits); `head/evals/harness/validate-suite.sh:137-139` (`TOGGLE_VALUES`, the vocabulary a third time)
- **Issue:** Nothing checks either copy against `lib/sandbox-mount.sh`; the dry-run tests at `head/evals/tests/pipeline-run.bats:1197-1215` assert the jq's own output. When the library gains or renames a toggle (as this PR did for `dissent`, `bare_model`, `oracle_open`) the dry run and the validator drift silently. `[ASSUMPTION]` the mapping matches `apply_arm_toggles` today — the library is not in the workspace.
- **Fix:** have `lib/sandbox-mount.sh` export the vocabulary and the key list (a function that prints them) and have both consumers read it; at minimum one test that diffs the three copies.
- **Reference:** CWE-1041 Use of Redundant Code — https://cwe.mitre.org/data/definitions/1041.html

### [MED-003] The refusal keys on the declarative `eval_only` flag, not on the toggle that opens the oracle — Confirmed by cross-model review (DISS-C-001)
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/harness/pipeline-run.sh:258-262` (refusal reads `.eval_only` only); `:336-338` (the dry run — and, per the library, the run — opens the overlay on `toggles.oracle_open == true` with no `eval_only` check); `head/evals/harness/validate-suite.sh:176-177` (the `oracle_open ⇒ eval_only` invariant lives only in the validator, which `pipeline-run.sh` never invokes)
- **Issue:** `pipeline-run.sh` reads `--suite-file` directly. A suite that sets `oracle_open: true` without `eval_only: true` — an edited copy, or any suite that never passed `freeze.sh`/`validate-suite.sh` — runs the open mount with the answer paths exposed and is never refused; the invariant is enforced one process away. The marker itself is a plain environment variable any caller can set (the header at `:146-147` documents doing so), so it is a mistake-guard, not a trust boundary, and should not be relied on to keep oracle-exposed rows out of result sets. Mitigation already present: the row carries `oracle_open` evidence (`took_effect: oracle_open_recorded`) and the report keeps such rows "reported, never excluded" (`ablation-report.py:1136-1142`), so an exposed run is identifiable after the fact, but only by inspecting evidence.
- **Fix:** refuse when `toggles.oracle_open == true` and the marker is not exactly `1`, in addition to the `eval_only` check; exit 2 when `oracle_open: true` appears without `eval_only: true`, mirroring the validator, so the invariant holds for unvalidated suite files too.
- **Reference:** CWE-693 Protection Mechanism Failure — https://cwe.mitre.org/data/definitions/693.html

### [MED-004] The four new arms are not in the suite's `priority`, so the default batch plan never schedules them
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/suites/ablation-2.0.yaml:55` (`priority` unchanged by the diff); `head/evals/harness/run-ablation.sh:570-573` (default `--arms` = the suite's `priority` minus absent arms)
- **Issue:** `priority: [a0_bare, a1_full, a2_no_sprint_plan, a3_one_voice, a4_no_gates, a7_effort_medium, a5_no_flatline, a6_one_window]` was not extended with `a0_bare_fable`, `a1_review_only`, `a1_no_dissent`, `a1_full_openmount`. A cycle-131 batch launched without an explicit `--arms` runs the cycle-130 plan and none of the arms this sprint delivers; the report then prints the three new components as `no_rows`. The `cut_ladder` (`:46`) likewise names no new arm. `[ASSUMPTION]` the cycle-131 batch may be launched with explicit `--arms`; the PR description does not say, and the suite header (`:12`) names `priority` as what `run-ablation.sh` reads.
- **Fix:** append the four arms to `priority` (and decide their place in `cut_ladder`), or state in the suite header and the PR that the cycle-131 arms are run only by explicit `--arms`.
- **Reference:** CWE-1068 — https://cwe.mitre.org/data/definitions/1068.html

### [LOW-001] A pre-existing test now appends a duplicate arm id
- **Severity:** LOW (confidence: high)
- **File:** `head/evals/tests/run-ablation.bats:1173-1175`
- **Issue:** RAB-c131-4 copies the committed suite and appends `a0_bare_fable`; the committed suite now declares that id (`head/evals/suites/ablation-2.0.yaml:98`), so the copy holds two arms with the same id. `run-ablation.sh` resolves `[.arms[] | select(.id == $a)][0]` (`head/evals/harness/run-ablation.sh:576`), so the appended definition (two rules, `took_effect: [no_dot_claude, bare_model_fable]`) is dead and the test exercises a duplicate-id suite that validate-suite check 8 has no rule for. RAB-c131-5 sits directly below it (`:1189`) and did not update it.
- **Fix:** drop the `yq -i '.arms += …'` and run RAB-c131-4 against the committed suite.
- **Reference:** CWE-561 Dead Code — https://cwe.mitre.org/data/definitions/561.html

### [LOW-002] The pre-registered rules comment is stale
- **Severity:** LOW (confidence: high)
- **File:** `head/evals/suites/ablation-2.0.yaml:117`
- **Issue:** `multiple_comparisons: none  # expected false positives at 0.90 over 6 components printed` — the report now prints 9 (`head/evals/tests/ablation-report.bats:189`). The comment is the pre-registration record (`:109`). Resolved by MED-001's fix; cited separately because the record must agree with what is printed.
- **Reference:** CWE-1116 Inaccurate Comments — https://cwe.mitre.org/data/definitions/1116.html

### [LOW-003] `took_effect` is now mandatory on every non-absent arm, undocumented as such
- **Severity:** LOW (confidence: medium)
- **File:** `head/evals/harness/validate-suite.sh:171-172`; header `:50-51`
- **Issue:** Before this change the validator did not read `took_effect`; now a missing key is `took_effect must be a list of rule ids`. Every committed arm carries it and DEC-0418 implies it should, but the check-8 header says "is a list", not "is required", and a `--suite-file` copy that drops the key fails freeze/validation with no hint that the key is required. Say so in the header; if `took_effect: []` is legal, say that too.
- **Reference:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html

### [LOW-004] Refusal ordering for callers that iterate every arm
- **Severity:** LOW (confidence: low)
- **File:** `head/evals/harness/pipeline-run.sh:258-262` (before the applicability `REFUSAL` is reported at `:326` and before `--dry-run`)
- **Issue:** An `eval_only` arm asked for an inapplicable task type outside a batch reports the eval_only reason rather than the task-type reason, and any future tool that dry-runs "every runnable arm" (a cost pre-flight, an image self-check) exits 2 on `a1_full_openmount` with no `pipeline.json`. Nothing in this diff does so (`run-ablation.sh --dry-run` never calls `pipeline-run.sh`), so this is a design note: consider letting `--dry-run` through unconditionally and refusing only a real run.
- **Reference:** CWE-696 Incorrect Behavior Order — https://cwe.mitre.org/data/definitions/696.html

### [LOW-005] `jq -r` string comparisons accept what the validator rejects — Confirmed by cross-model review (DISS-C-002)
- **Severity:** LOW (confidence: high)
- **File:** `head/evals/harness/pipeline-run.sh:260` (`jq -r '.eval_only // false'` == `true`), `:334`, `:338` (`.loa_mount`, `.oracle_open` likewise)
- **Issue:** `jq -r` renders the JSON string `"true"` and the boolean `true` identically, so `eval_only: "true"` or `oracle_open: "true"` are honoured here while validate-suite check 8 (`type(v) is type(x)`, `:168`; `isinstance(…, bool)`, `:174`) rejects them. The two components disagree on what a valid value is, and `pipeline-run.sh` is the one that acts. Low impact alone; it widens MED-003's gap for an unvalidated suite.
- **Fix:** test type-strictly, e.g. `jq -e '.eval_only == true'`, for `eval_only`, `oracle_open` and `loa_mount`.
- **Reference:** CWE-1287 Improper Validation of Specified Type of Input — https://cwe.mitre.org/data/definitions/1287.html

### [LOW-006] RAB-c131-5's title claims more than it asserts
- **Severity:** LOW (confidence: high)
- **File:** `head/evals/tests/run-ablation.bats:1189-1191`
- **Issue:** The title says "the runner's own environment is unchanged", but the only related assertion is the precondition `[ -z "${LOA_ABLATION_BATCH_CONTEXT+x}" ]` before the run; `ra` executes in a child process, so the test cannot observe the runner's shell and asserts nothing after it. Either drop the clause or assert it (e.g. have the runner print its own `${LOA_ABLATION_BATCH_CONTEXT-<unset>}` at exit in a test hook).
- **Reference:** CWE-1116 Inaccurate Comments — https://cwe.mitre.org/data/definitions/1116.html

---

## Rejected dissent payloads

None. The envelope `grimoires/loa/a2a/sprint-1/adversarial-audit.json` carries `metadata.rejected_summary: []`, `rejected_count: 0` and `rejected_sidecars: []`; the companion voice's `rejected_sidecar` is `null`, and no `adversarial-rejected-audit*.jsonl` exists beside the envelope.

## Cross-Model Security Observations

Security Dissenter ran once, two voices, `status: clean` on the primary (`gpt-5.5-pro`, `status_note`: no finding met the bar — not an approval of unreviewed surface) and two findings from the companion (`claude-headless`, `counted_as: independent_voice`, `independent: true`). `degraded: false`; companion `status: succeeded`; hallucination filter applied, 0 downgraded; `verdict_quality.consensus_outcome: consensus`, `chain_health: ok`. Not a DEGRADED_SECURITY_REVIEW.

- DISS-C-001 (companion, authz, `pipeline-run.sh:258-262`): the refusal keys on `eval_only` rather than `toggles.oracle_open`, and the invariant lives only in the validator; the marker is an env var any caller sets. Verified against the code and tallied as MED-003.
- DISS-C-002 (companion, input-validation, `pipeline-run.sh:334-341`): `jq -r` string compares are not type-exact where the validator is. Verified and tallied as LOW-005.

Review gate's dissent (`adversarial-review.json`, `gpt-5.5-pro` + `claude-headless`, four ADVISORY findings) independently restated HIGH-001, HIGH-002, the per-primary k of MED-001 and the ordering note of LOW-004; cross-referenced, not re-tallied.

## Confirmation of review demotions

The review trailer carries `excluded: 0` — no HIGH was demoted to Observations — so there is nothing to confirm; `excluded_confirmed: 0`.

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added
- [x] Input validation at the trust boundary — suite schema check 8 is type-exact; rule ids come from `took-effect.sh` through a `[a-z_][a-z0-9_]*` sed pattern and reach Python as one argv; `LOA_ABLATION_BATCH_CONTEXT` is compared to the literal `1`; `python3 -I`
- [x] Authentication/authorization — n/a (operator-run harness); the env-var guard is a mistake-guard, not a trust boundary (MED-003)
- [x] No injection vectors introduced — `$ARM` reaches `echo`/`printf` quoted; `yq load(strenv(…))` in tests only; no `eval`
- [x] Error handling doesn't leak info — refusal names arm and remedy only
- [ ] Tests cover security paths — the refusal and the marker are tested on both launch paths; the report's handling of the new arm classes has **no decision-state test** (HIGH-001/002); no bats suite could be executed here

## Documentation Audit

No `grimoires/loa/a2a/subagent-reports/documentation-coherence-*.md` exists in this workspace; manually verified instead. The header comments of `pipeline-run.sh` (`:46-51`, `:141-147`), `run-ablation.sh` (`:163-166`), `validate-suite.sh` (`:46-53`) and the suite (`:32-34`, `:94-97`) describe the code as shipped; the two `--help` sed ranges were widened by exactly the lines added. Gaps: LOW-002 (stale pre-registration comment), LOW-003 (requirement not stated), and the PR title promises "the cycle-131 suite root (bounds 50/40) with its image self-check" while no file under `grimoires/loa/evals/` is in the diff (`head/evals/tests/run-ablation.bats:1196` copies the pre-existing root) — either the title overstates the change or a deliverable is missing. `pr/PR.md` carries no `## AC Verification` and no test-run record.

## Rubric Scores

| Category | Dimension | Score | Basis |
|---|---|---|---|
| Security | Input validation | 4 | type-exact validator; jq -r mismatch (LOW-005) |
| Security | Injection prevention | 5 | no new sinks reachable from untrusted data |
| Security | Confidentiality/Integrity | 4 | oracle-exposure guard is one-process-deep (MED-003) |
| Architecture | Modularity | 3 | toggle vocabulary in three places (MED-002) |
| Architecture | Standards | 3 | pre-registration and implementation disagree (MED-001, HIGH-001) |
| Code quality | Test coverage | 3 | shell paths well covered; report decision states untested; nothing executed here |
| Code quality | Documentation | 3 | headers current; stale comment, undocumented requirement, PR title overclaim |
| DevOps | Automation | 3 | fast gate (shellcheck, bats) not evidenced in the PR |

Overall: MODERATE risk from a security standpoint; the verdict is driven by the two HIGH correctness findings in the report, per the one-way rule.

---

## Next Steps

**CHANGES_REQUIRED:**
1. Fix HIGH-001 and HIGH-002 in `ablation-report.py` (and `rules.primaries_by_arm` in the suite if the `review_only` route is taken), with fixture scenarios that assert the decision state of a review-catch-only component and where `a1_full_openmount` rows land.
2. Decide and document `a0_bare_fable`'s role and the new k (MED-001, LOW-002); extend `priority` or document the explicit-`--arms` convention (MED-004).
3. Harden the refusal on `toggles.oracle_open` and make the jq tests type-strict (MED-003, LOW-005); add one parity test for the toggle vocabulary (MED-002).
4. Run the five bats suites and record the results in the implementation report; then `/implement sprint-1` → `/review-sprint sprint-1` → `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":4,"low":6},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-22T00:59:00Z"} -->
