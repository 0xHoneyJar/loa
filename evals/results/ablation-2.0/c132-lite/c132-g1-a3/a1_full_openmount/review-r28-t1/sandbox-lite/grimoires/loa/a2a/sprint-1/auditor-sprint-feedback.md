# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md (eval task review-r28)
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)
**Change under audit:** `pr/head.diff` — "feat(cycle-131): sprint-264 — four review-catch arms, eval_only batch-context refusal, validate-suite arm schema, the cycle-131 suite root (bounds 50/40) with its image self-check" (11 files)
**Review gate input:** grimoires/loa/a2a/sprint-1/engineer-feedback.md (CHANGES_REQUIRED, 0 critical / 2 high / 5 medium / 4 low, excluded 0)

---

## Verdict: CHANGES_REQUIRED

---

## Pre-flight and scope

- **Phase 0 deviation (recorded, not hidden).** The skill's prerequisite is an `engineer-feedback.md` that says "All good". The review gate on this sprint says CHANGES REQUIRED. The task brief instructs this audit to run autonomously, so it ran; the two review highs are re-derived below from the head files rather than taken on trust. `adversarial-review.json` carries `metadata.model: gpt-5.5-pro`, so the review's Phase 2.5 marker is intact.
- **Guardrails:** `guardrails-orchestrator.sh --skill auditing-security` returned `action: PROCEED` (pii_filter PASS; injection_detection ERROR, fail-open per the include).
- **Known failures surface:** `grimoires/loa/known-failures.md` is absent (SessionStart hook warning). Triage ran without it.
- **Input:** the 11 touched files under `pr/head/` and `pr/base/` plus `pr/head.diff`. `pr/head/.run/audit.jsonl` and `pr/head/evals/harness/__pycache__/` are untracked artifacts of the earlier review session (the audit log of that session's Bash calls and a `py_compile` cache); they are not in `head.diff` and were not audited as change content.
- **Scope limits:** `lib/sandbox-mount.sh` (`apply_arm_toggles`), `took-effect.sh`, `ablation-grade.sh`, `evals/tests/fixtures/ablation-report/gen-fixtures.py` and the suite root `grimoires/loa/evals/ablation-2.0/` are outside the diff and absent from this workspace. Claims about them below are marked `[ASSUMPTION]`. The bats suites were not executed (they need those files); `bash -n` on the four shell files and `python3 -I -m py_compile` on the report were verified by the review and are not re-run here. The dry-run plan reproduced by the review was accepted as evidence.
- **Security-audit-scope.sh** (Phase 0.5) ran against the workspace: 7 sources, 278 sinks (156 command_exec, 106 file_operations). Of these only the four shell scripts and one Python report in `pr/head/evals/` are in the change; the recon list is in `grimoires/loa/a2a/audits/2026-10-21/SECURITY_ANALYSIS_TODO.md`.

## Executive Summary

The change adds four review-catch arms to the ablation suite, an `eval_only` refusal in `pipeline-run.sh` keyed on `LOA_ABLATION_BATCH_CONTEXT=1`, a toggle/took-effect/eval_only schema in `validate-suite.sh`, a sandbox plan in the dry run, and tests. **No exploitable security vulnerability was found**: no new trust boundary is crossed, no user-controlled string reaches a shell or path sink unvalidated, the Python validator runs with `-I`, arm ids are regex-gated before use, and the refusal fires before any filesystem write. The security posture of the diff is sound.

The audit nonetheless returns CHANGES_REQUIRED on two high-severity correctness defects, both confirmed independently against the head files: the four new arms are declared but never reach a default `run-ablation.sh` batch because `priority` was not updated, and the three review-catch-only arms the report now treats as components are given a pass-rate primary that can never form a pair, so their decision can never read `remove` or `simplify`. Six medium and four low findings follow; one medium and one low originate from the cross-model dissent and are confirmed here.

**Security Issues Found:**

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 6 |
| Low | 4 |

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] The four cycle-131 arms are absent from `priority`, so a default batch never runs them

**Severity:** HIGH — **Confidence:** high — **Category:** Architecture / correctness
**File:** `head/evals/suites/ablation-2.0.yaml:55`
**Code:**
```yaml
priority: [a0_bare, a1_full, a2_no_sprint_plan, a3_one_voice, a4_no_gates, a7_effort_medium, a5_no_flatline, a6_one_window]
```
**Issue:** The arms are declared at `head/evals/suites/ablation-2.0.yaml:98-105` and the file's own header (line 12) names `priority` as a `run-ablation.sh` input. `run-ablation.sh` documents the default arm set as "the suite's priority minus every arm declared absent: true" (`head/evals/harness/run-ablation.sh:24-25`) and implements exactly that at `head/evals/harness/run-ablation.sh:570-571`:
```bash
[[ -n "$ARMS_CSV" ]] || ARMS_CSV="$(jq -r '(.arms // [] | map(select(.absent == true) | .id)) as $absent
                                            | [.priority // [] | .[] | select(IN($absent[]) | not)] | join(",")' <<<"$SUITE_JSON")"
```
`a0_bare_fable`, `a1_review_only`, `a1_no_dissent` and `a1_full_openmount` are not in that list.
**Failure scenario:** An operator starts the cycle-131 batch without `--arms`. The runner plans arms × tasks from `priority`, the four new arms are never scheduled, and the report's nine-component decision table and expected-false-positive sentence (`head/evals/harness/ablation-report.py:1926-1932`) describe arms with zero rows. The whole FR-5 batch-context mechanism (`LOA_ABLATION_BATCH_CONTEXT=1` set only on trial commands, `head/evals/harness/run-ablation.sh:1300-1301`) is built on the assumption that these arms run inside such batches. `AT-13` (`head/evals/tests/arm-toggles.bats:255-258`) checks the arm list and never `priority`, so no test fails.
**Fix:** Append the four ids to `priority` (position = cut order; `a1_full_openmount` last), and extend `AT-13` to assert every non-absent arm id is in `priority`. If the intent is an always-explicit `--arms` for cycle-131 batches, say so in the suite header and the runner's usage text, and pin that with a test.
**Reference:** CWE-684 Incorrect Provision of Specified Functionality — https://cwe.mitre.org/data/definitions/684.html

### [HIGH-002] Review-catch-only components are given a pass-rate primary that can never pair, so `remove`/`simplify` are unreachable

**Severity:** HIGH — **Confidence:** high — **Category:** Architecture / correctness
**File:** `head/evals/harness/ablation-report.py:653-658`
**Code:**
```python
    def primaries(self, arm):
        types = self.arms[arm].get("task_types") or []
        pba = self.rules.get("primaries_by_arm") or {}
        if "all" in types or REVIEW in types:
            return list(pba.get("all_types") or [PASS, CATCH])
        return list(pba.get("build_only") or [PASS])
```
**Issue:** The `components` filter at `head/evals/harness/ablation-report.py:1913` now admits `a0_bare_fable`, `a1_review_only` and `a1_no_dissent`, whose `task_types` is `[review-catch]`. `primaries()` keys on `REVIEW in types` and returns `[hidden_test_pass_rate, defect_catch_rate]`. `compare()` restricts the pass-rate metric to `BUILD_TYPES` tasks (`head/evals/harness/ablation-report.py:732`); these arms have no build rows, so the comparison has `n == 0`, `usable()` (`:577`) is false, `nopair` is true in `decide()` (`:846-887`), and every run that does not already hit `investigate` or `keep` on catch rate returns `inconclusive: no valid pair (hidden_test_pass_rate)`. `out["decidable"]` (`:926`) is always false for them. The suite's `primaries_by_arm` (`head/evals/suites/ablation-2.0.yaml:113`) has no entry for review-catch-only arms either.
**Failure scenario:** `a1_review_only` exists to ask whether the AUDIT gate adds anything, `a1_no_dissent` whether review dissent adds anything. The informative answer is `remove`/`simplify`. Under this code those states are structurally impossible; the report prints Inconclusive forever and the operator reads a harness defect as insufficient data. The fixtures do not catch it: `head/evals/tests/ablation-report.bats:189` and `:342` only count components (9) in the `main` scenario, where the three arms have no rows.
**Fix:** Add a third primary shape (e.g. `primaries_by_arm.review_only: [defect_catch_rate]` in the suite rules, matched by a branch in `primaries()` for arms whose types contain no build type), and add a report test with rows for one review-catch-only arm asserting `remove`/`simplify` is reachable and that the comparison list has no pass-rate entry.
**Reference:** CWE-1023 Incomplete Comparison with Missing Factors — https://cwe.mitre.org/data/definitions/1023.html

---

## Medium/Low Priority Issues

### [MED-001] The `eval_only` refusal keys on a label, not on the capability it guards, and leaves no provenance in the run — *Confirmed by cross-model review (DISS-C-001)*
- **Severity:** MEDIUM — **Confidence:** medium
- **File:** `head/evals/harness/pipeline-run.sh:258-262`
- **Code:**
```bash
EVAL_ONLY=false; [[ "$(jq -r '.eval_only // false' <<<"$ARM_DEF")" == true ]] && EVAL_ONLY=true
if [[ "$EVAL_ONLY" == true && "${LOA_ABLATION_BATCH_CONTEXT:-}" != 1 ]]; then
```
- **Issue:** The thing being protected is the open mount (`toggles.oracle_open: true`, answer paths visible to the reviewer). The gate reads `eval_only`, a sibling flag in the same operator-editable suite file, and an env var the header itself tells the operator to set by hand (`:145-146`). The `oracle_open ⇒ eval_only` pairing is enforced only by `validate-suite.sh` (`head/evals/harness/validate-suite.sh:179-180`), which `pipeline-run.sh` never runs. Nothing in `meta/arm-evidence.txt` or `pipeline.json` records that a trial was launched in batch context, so an open-mount trial launched by hand is indistinguishable downstream from a batch one. Trust context [ASSUMPTION]: the operator is trusted and this is an operational guard, not an authorization boundary, which is why this is medium and not high.
- **Failure scenario:** A suite copy that sets `oracle_open: true` without `eval_only` (or a hand-exported variable) produces oracle-leaked rows that look like ordinary trials; the only downstream exclusion (`ablation-report.py:1913`) keys on the same editable flag.
- **Fix:** Refuse on `toggles.oracle_open == true` as well as `eval_only` (either suffices), and write `eval_only=<bool>` and `batch_context=<bool>` into `meta/arm-evidence.txt` so `took-effect.sh` and the report can verify provenance per run.
- **Reference:** CWE-807 Reliance on Untrusted Inputs in a Security Decision — https://cwe.mitre.org/data/definitions/807.html ; CWE-778 Insufficient Logging — https://cwe.mitre.org/data/definitions/778.html

### [MED-002] `a0_bare_fable` is counted as an ablatable component
- **Severity:** MEDIUM — **Confidence:** medium
- **File:** `head/evals/harness/ablation-report.py:1913`
- **Issue:** The suite comment calls `a0_bare_fable` "A0 on the review model" (`head/evals/suites/ablation-2.0.yaml:94-95`), i.e. a baseline, and the code comment at `:1911-1912` says components are "every runnable arm but the two baselines". The filter admits it (it is neither `CONTROL`, `BARE`, absent nor `eval_only`), so the decision table carries a "remove a0_bare_fable" style row against `a1_full` and `k` is 9 rather than 8; `head/evals/tests/ablation-report.bats:189` and `:342` lock the 9 in.
- **Fix:** Decide the arm's role explicitly. If it is a baseline, exclude arms with `toggles.loa_mount == false` (or a `baseline: true` flag) from `components`, keep it in per-arm detail, and set the tests to 8.
- **Reference:** CWE-1023 — https://cwe.mitre.org/data/definitions/1023.html

### [MED-003] The `eval_only` arm is invisible in the report
- **Severity:** MEDIUM — **Confidence:** medium
- **File:** `head/evals/harness/ablation-report.py:2003`
- **Code:** `detail_arms = [BARE, CONTROL] + components`
- **Issue:** The per-arm detail inherits the `eval_only` exclusion, so `a1_full_openmount` appears neither in Decisions nor in Per-arm detail; its rows surface only in the oracle-exposed note (`:1624`). The open-mount A/B the arm exists for cannot be read from the artifact meant to show it.
- **Fix:** Keep `eval_only` arms out of `components` but add them to `detail_arms`, or render a labelled `a1_full` vs `a1_full_openmount` comparison that "decides nothing" like the existing sensitivities.
- **Reference:** CWE-684 — https://cwe.mitre.org/data/definitions/684.html

### [MED-004] The dry-run `config_edits` mapping is a hand copy of `apply_arm_toggles`
- **Severity:** MEDIUM — **Confidence:** medium
- **File:** `head/evals/harness/pipeline-run.sh:341-345`
- **Issue:** The jq expression re-implements which `.loa.config.yaml` keys each toggle sets (companion_voice, gates, dissent, flatline). [ASSUMPTION] The authoritative mapping lives in `lib/sandbox-mount.sh apply_arm_toggles`, outside the diff. A toggle added or re-mapped there leaves the dry run printing a plan the sandbox does not get, and the new tests (`head/evals/tests/pipeline-run.bats:1192-1221`) pin the copy, not the library.
- **Fix:** Have the library expose its mapping (a function printing `key=value` lines for a toggles JSON) and call it from the dry run.
- **Reference:** CWE-1041 Use of Redundant Code — https://cwe.mitre.org/data/definitions/1041.html

### [MED-005] `TOGGLE_VALUES` is a second copy of the toggle vocabulary
- **Severity:** MEDIUM — **Confidence:** medium
- **File:** `head/evals/harness/validate-suite.sh:137-139`
- **Issue:** The validator hard-codes toggle names and accepted values although the same script derives `RULE_IDS` from `took-effect.sh` (`:87`) instead of listing them, and sources `lib/sandbox-mount.sh` a few lines later. A toggle the library accepts but this table lacks is rejected as unknown; the reverse validates an arm the sandbox ignores. The type-exact comparison at `:166` is correct (rejects `0` for `false`); the finding is the duplication, not the check.
- **Fix:** Export the vocabulary from the library (or parse its `case` labels as `RULE_IDS` parses `rule_<id>()`) and pass it as an eighth argv beside `RULE_IDS`; or add a test asserting `TOGGLE_VALUES` equals the keys `apply_arm_toggles` dispatches on.
- **Reference:** CWE-1041 — https://cwe.mitre.org/data/definitions/1041.html

### [MED-006] The PR description claims work the diff does not contain, and no AC walkthrough exists
- **Severity:** MEDIUM — **Confidence:** high
- **File:** `pr/PR.md:1`
- **Issue:** The title promises "the cycle-131 suite root (bounds 50/40) with its image self-check". Nothing in `head.diff` touches `grimoires/loa/evals/`, an image, or a self-check; the only suite-root reference is the pre-existing fixture copy in `head/evals/tests/run-ablation.bats:1196`. The implementation report is the title plus "11 file(s) in scope"; there is no `## AC Verification`, so none of the sprint's deliverables is traced to `file:line` evidence. The audit trail then judges a change that does not match its own description.
- **Fix:** Add the missing files or retitle the PR to what it ships; add an AC walkthrough.
- **Reference:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html

### [LOW-001] Stale suite header: "Every mounted review-catch arm runs the closed mount"
- **Severity:** LOW — **Confidence:** high
- **File:** `head/evals/suites/ablation-2.0.yaml:29-31`
- **Issue:** `a1_full_openmount` (declared at `:104`, `oracle_open: true`) is a mounted review-catch arm that runs the open mount.
- **Fix:** Qualify the sentence ("every mounted review-catch arm except an `oracle_open` eval_only arm").
- **Reference:** CWE-1116 Inaccurate Comments — https://cwe.mitre.org/data/definitions/1116.html

### [LOW-002] Stale rules comment: "over 6 components"
- **Severity:** LOW — **Confidence:** high
- **File:** `head/evals/suites/ablation-2.0.yaml:117`
- **Issue:** The report and `AR-12` now print 9 (or 8, per MED-002).
- **Fix:** Update or drop the number.
- **Reference:** CWE-1116 — https://cwe.mitre.org/data/definitions/1116.html

### [LOW-003] Component exclusion trusts the suite flag and never cross-checks row evidence — *Confirmed by cross-model review (DISS-C-002)*
- **Severity:** LOW — **Confidence:** low
- **File:** `head/evals/harness/ablation-report.py:1913`
- **Issue:** Rows record `oracle_open` and `mount_overlay` per run (the new bats assertions at `head/evals/tests/pipeline-run.bats:1251-1252` show both), but `components` consults only the suite's `eval_only`. A suite revision that relabels the open-mount arm without `eval_only`, or rows produced under a differently flagged suite, would be counted as a decision component with oracle-leaked results. The existing `oracle_reason` path (`:584-588`) already reads `row["oracle_open"]`, so the data is available.
- **Fix:** When building `components`, exclude or fail hard on any arm whose review-catch rows carry `oracle_open=true` / `mount_overlay=none`, and print a provenance line when the suite flag and the recorded evidence disagree.
- **Reference:** CWE-345 Insufficient Verification of Data Authenticity — https://cwe.mitre.org/data/definitions/345.html

### [LOW-004] The `eval_only` refusal pre-empts the applicability refusal
- **Severity:** LOW — **Confidence:** medium
- **File:** `head/evals/harness/pipeline-run.sh:259`
- **Issue:** The `eval_only` check runs after `REFUSAL` is computed (`:244-252`) but before it is acted on (`:318` dry run, `:468-472` real run, which writes a refused `pipeline.json` for `applicability_refused`). Outside the batch context an `eval_only` arm on a non-applicable task is reported as "eval_only arm outside an evaluation batch" rather than "does not apply to task type", and no refusal record is written. Inside a batch the runner never schedules such a pair, so the effect is limited to hand runs and the message they get.
- **Fix:** Evaluate `REFUSAL` first (or fold the `eval_only` clause into the `REFUSAL` chain after the task_types test) so the more specific reason wins; document which refusal writes a record and which does not.
- **Reference:** CWE-684 — https://cwe.mitre.org/data/definitions/684.html

---

## Observations (not tallied)

- **Test coverage gap, unverifiable here.** `head/evals/tests/pipeline-run.bats:1256-1263` asserts the phases and `completed` status of an `a1_review_only` run; nothing in the diff exercises grading or `took-effect.sh`'s `review_only_phases` for a run with one gate envelope. Both scripts are outside the diff, so this is a scope limit, not a finding.
- **Changelog.** The change adds four arms, a new suite key, a new env contract and new validator rules with no CHANGELOG line. Whether this repository keeps one for `evals/` is not visible from the touched files.
- **Help bounds.** `sed -n '2,156p'` (`head/evals/harness/pipeline-run.sh:193`) and the usage `sed -n '2,55p'` (`head/evals/harness/validate-suite.sh:68`) were checked against the head headers: both end on the last comment line before the rule, so the help text is complete. No finding.
- **Env-var hygiene in the runner.** `LOA_ABLATION_BATCH_CONTEXT=1` is prefixed on the trial command only (`head/evals/harness/run-ablation.sh:1300-1301`), never exported into the runner's shell, and the stub's `${VAR-<unset>}` probe plus `RAB-c131-5` prove the assertion is not vacuous. Correct.

---

## Cross-Model Security Observations

`adversarial-review.sh --type audit --sprint-id sprint-1 --diff-file pr/head.diff --json` ran once (started 2026-10-21T23:43:46Z), status `clean`, `degraded: false`, 2/2 voices succeeded (`codex-headless` via the gpt-5.5-pro chain, `claude-headless` companion, `independent: true`, `counted_as: independent_voice`), `hallucination_filter.downgraded 0`, `metadata.locality` absent, `diff_sha256 ab963f46…`. Not a DEGRADED_SECURITY_REVIEW. Two advisory findings, both from the companion voice, both triaged above:

- DISS-C-001 (MEDIUM, authz, `pipeline-run.sh:258-262`) — refusal keyed on `eval_only` + env var, not on `oracle_open`; no batch-context provenance in the run. → MED-001 (confirmed; tallied as my own medium).
- DISS-C-002 (LOW, input-validation, `ablation-report.py:1913`) — components exclusion keyed on the suite flag only, never on row evidence. → LOW-003 (confirmed; tallied as my own low).

## Rejected dissent payloads

- none — `metadata.rejected_summary` is `[]`, `rejected_count` 0, `rejected_sidecars` `[]`, and no `adversarial-rejected-audit*.jsonl` exists beside `adversarial-audit.json`.

---

## Review-trailer reconciliation

The review trailer counts `excluded: 0` (no high demoted to Observations). Nothing to confirm; `excluded_confirmed` is 0. Both review highs are re-derived above (HIGH-001, HIGH-002) with independent evidence; all five review mediums are confirmed (MED-002…MED-006) and one medium is added from the dissent (MED-001). Of the review's four lows, two are confirmed (LOW-001, LOW-002), two are recorded as scope-limited observations, and two lows are added (LOW-003 from the dissent, LOW-004 from this audit).

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added — none; the only literal credentials-shaped value is the model id in tests
- [x] Input validation on all new entry points — arm ids regex-gated before use (`run-ablation.sh:574`); `eval_only` and toggle values type-exact (`validate-suite.sh:166, 177`); the batch-context test accepts only the literal `1`
- [x] No command/path injection — suite and task content reach jq/yq/python only as data; the Python validator runs with `-I`; no `eval`, no unquoted expansion of suite-derived strings in the new shell
- [x] Refusal fires before any filesystem write (`pipeline-run.sh:258-262` precedes run-dir creation); no partial `pipeline.json`
- [x] Error messages name the arm id and the reason only
- [ ] Authorization — n/a; the `eval_only` gate is an operator guard, not an auth boundary (see MED-001 for its limits)
- [ ] Tests cover security paths — the refusal is covered on dry run, real run, four non-`1` values and a non-eval_only arm (`pipeline-run.bats:1223-1244`); not executed in this workspace (see Scope limits)

## Rubric Scores (resources/RUBRICS.md)

| Dimension | Score | Justification |
|-----------|-------|---------------|
| SEC-IV Input Validation | 4 | Type-exact toggle/eval_only checks, regex-gated arm ids, `-I` Python; gap: `oracle_open` not checked at runtime (MED-001) |
| SEC-AZ Authorization | 4 | n/a surface; operator guard keyed on label (MED-001) |
| SEC-CI Confidentiality/Integrity | 4 | Evaluation integrity depends on an editable suite flag with no per-run provenance (MED-001, LOW-003) |
| SEC-IN Injection Prevention | 5 | No new sink takes untrusted strings |
| SEC-AV Availability | 5 | No new long-running or unbounded path |
| Architecture | 2 | New arms not wired to the runner's default plan (HIGH-001) or to a usable primary set (HIGH-002); two duplicated vocabularies |
| Code Quality | 3 | Lean, well-commented; stale comments (LOW-001/002); description/diff mismatch (MED-006) |
| DevOps | 3 | Tests load arms from the committed suite (good); no test guards `priority`; bats not runnable here |

## Documentation Audit

No `grimoires/loa/a2a/subagent-reports/documentation-coherence-*.md` exists for this sprint (the workspace has no implement phase). Manually verified: the headers of `pipeline-run.sh` (`:46-51, :141-150`), `validate-suite.sh` (`:46-53`), the suite (`:32-34`) and the stub (`:10-11`) were updated with the new env contract and rules. Red flags found: two stale comments (LOW-001, LOW-002) and a PR description that names undelivered deliverables (MED-006). No secrets or internal URLs in comments; no auth/crypto change.

---

## Next Steps

**CHANGES_REQUIRED:**
1. Fix HIGH-001 and HIGH-002 (both are small: a `priority` edit plus a test; a third primary shape plus a test).
2. Resolve MED-001 (refuse on `oracle_open` too; record `eval_only`/`batch_context` in arm evidence) and decide MED-002/MED-003 (role of `a0_bare_fable`; render the `eval_only` arm).
3. Reconcile the PR title with the diff and add an AC Verification walkthrough (MED-006); fix the two stale comments.
4. Re-run `/review-sprint sprint-1`, then `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":6,"low":4},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T23:50:00Z"} -->
