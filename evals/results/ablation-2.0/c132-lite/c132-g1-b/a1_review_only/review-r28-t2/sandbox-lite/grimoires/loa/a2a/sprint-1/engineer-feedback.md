# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)

Scope: the pull request in `pr/` (`pr/head.diff`, 11 files under `evals/`): four review-catch arms in
`evals/suites/ablation-2.0.yaml`, the `eval_only` batch-context refusal in `pipeline-run.sh` /
`run-ablation.sh`, the arm-schema rule in `validate-suite.sh`, the `eval_only` component filter in
`ablation-report.py`, and their bats cases. Citations are `head/<path>:<line>` with line numbers from
`pr/head/`. The bats suites could not be executed in this workspace (the `evals/` tree, its fixtures,
`lib/sandbox-mount.sh` and `took-effect.sh` are not present), so every claim below is from reading
the head files and tracing the untouched code they call into.

---

## Overall Assessment

The harness side of the change is sound: the `eval_only` refusal in `pipeline-run.sh` runs before any
run directory exists ("EVAL_ONLY=false; …" head/evals/harness/pipeline-run.sh:258-262, mkdir at :356),
honours exactly the value `1`, is exported per trial command only in `run_trial` (head/evals/harness/
run-ablation.sh:1300-1301, the single launch path), and the help/usage `sed` ranges were re-counted
correctly (header ends at :157; usage block 2,55p matches the eight added header lines). The
`validate-suite.sh` rule 8 is type-exact and tested (VS-14..VS-17). The dry-run `sandbox:` line and
its four cases are a useful preview.

The defect is on the report side. The suite now declares three review-catch-only decision arms
(`a0_bare_fable`, `a1_review_only`, `a1_no_dissent`) and `build()` admits them as components
(head/evals/harness/ablation-report.py:1913), but the untouched decision path they flow into has no
review-only branch: `primaries()` hands every non-build-only arm both primaries
("if "all" in types or REVIEW in types: return … all_types" :656-657), the pass-rate comparison for
an arm that never runs build tasks has `n == 0`, `usable()` (:577-579) is false, `nopair` (:850) is
true, and `decide()` returns `inconclusive` for every outcome other than investigate/keep on
`defect_catch_rate` (:873-876). Three of the four arms this sprint ships can therefore never reach
`remove` or `simplify`, and the AR-12/AR fixture assertions lock in nine components without checking
that they can resolve. Both dissent voices reached the same conclusion independently (DISS-001,
DISS-C-001).

`reviewer.md` carries no `## AC Verification` section (it is the PR title plus a file count), which
is an automatic CHANGES_REQUIRED under this skill; the PR title also claims a "cycle-131 suite root
(bounds 50/40) with its image self-check" that is not in the diff.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Functionality — review-catch-only components are structurally undecidable

- **HIGH** (confidence: high) `head/evals/harness/ablation-report.py:1913` — the component filter now admits `a0_bare_fable`, `a1_review_only` and `a1_no_dissent` (task_types `[review-catch]`, head/evals/suites/ablation-2.0.yaml:98-103) as decision components, but `primaries()` at `head/evals/harness/ablation-report.py:653-658` has no review-only branch and gives each of them `hidden_test_pass_rate` as a primary. `compare()` (:731-735) restricts that metric to build-type tasks, the arm has no build cells, so every task is `unpaired`, `n == 0`, `usable()` (:577-579) is false, `nopair` (:850) is true, and `decide()` (:846-887) appends "no valid pair (hidden_test_pass_rate)" and returns `inconclusive` whenever the defect-catch interval does not already force investigate/keep. Concrete failing input: a complete batch where `a1_review_only` equals `a1_full` on `defect_catch_rate` at 20 % lower cost — the pre-registered predicate should read `remove`, the report prints `inconclusive`.
**File:** `head/evals/harness/ablation-report.py:1913` (admits the arms), `:656-658` (no review-only primaries), `:850` + `:873-876` (forces inconclusive)
**Issue:** The report is the instrument FR-5 adds these arms for, and it cannot decide them. The expected-false-positive sentence counts nine components (head/evals/tests/ablation-report.bats:189) although only six can produce a remove/simplify decision, and `.decisions | length == 9` (head/evals/tests/ablation-report.bats:342) asserts the count, not resolvability.
**Why This Matters:** Pre-registered decision rules (`rules.predicates`, head/evals/suites/ablation-2.0.yaml:121-127) are evaluated by this code; a structurally unreachable `remove`/`simplify` silently biases the whole cycle-131 ablation toward "inconclusive" for the review-gate arms and burns their trial budget for no decision.
**Required Fix:** Give `primaries()` a review-only branch: when an arm's `task_types` is exactly `[review-catch]` (no `all`, no build type), return `[defect_catch_rate]` (or `primaries_by_arm.review_only` if you add that rule key beside `build_only`/`all_types`). Add an `ablation-report.bats` case with planted rows for a review-catch-only arm whose `defect_catch_rate` sits within −0.03 of `a1_full` at ≤ −15 % cost and assert `.state == "remove"`; add the mirror case asserting `keep`. Re-derive the expected-false-positive `k` if you decide a review-only arm counts as one comparison.
**Reference:** `rules.primaries_by_arm` (head/evals/suites/ablation-2.0.yaml:113, DEC-0400) already encodes "primaries follow arm applicability" for the build-only case; this is the symmetric gap.

---

## Observations

### 1. Report surface for the evaluation-only arm

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-report.py:1913` — `a1_full_openmount` is excluded from `components`, hence also from `detail_arms` (`[BARE, CONTROL] + components`, :2003) and the per-arm metrics loop (:1743-1745). Its rows are only mentioned as a count in the oracle-exposed sensitivity line (:1624). The arm exists to A/B the open mount against `a1_full` on `defect_catch_rate`; after a batch that spends its trial budget the report shows no per-arm figures and no comparison for it. If another tool renders this, say so in the suite comment at head/evals/suites/ablation-2.0.yaml:94-97 and add a test that it appears there; otherwise add an "Evaluation controls" section that runs `compare(a1_full_openmount, CONTROL, defect_catch_rate)` labelled as not a decision.
**Suggestion:** Keep two collections in `build()`: `components` (decisions) and `reported_arms` (components + eval_only arms) and drive `detail_arms`/metrics from the latter.
**Benefit:** The FR-5 oracle A/B becomes readable without hand-querying `runs.jsonl`.

### 2. A bare baseline counted as a component

- **MEDIUM** (confidence: high) `head/evals/suites/ablation-2.0.yaml:98-99` — `a0_bare_fable` (`loa_mount: false`, `phases: [BARE]`) is a second bare baseline, not a shipped component, but `build()` excludes only the `CONTROL`/`BARE` constants and `eval_only` arms (head/evals/harness/ablation-report.py:1913), so the report emits a keep/remove/simplify "component decision" for a baseline that cannot be removed, and it inflates `k` in the expected-false-positive arithmetic (head/evals/tests/ablation-report.bats:189 now asserts 9 including it). Combined with Changes Required #1 its decision is always `inconclusive` today.
**Suggestion:** Exclude arms whose toggles set `loa_mount: false` from `components` and surface `a0_bare_fable` beside `a0_bare` in the H1-style baseline section (:1241-1242 pattern), or document why a bare arm is a component.
**Benefit:** The Method section stops reporting decisions on non-components and the false-positive budget reflects real comparisons.

### 3. Default batch never schedules the new arms

- **MEDIUM** (confidence: high) `head/evals/suites/ablation-2.0.yaml:55` — `priority` is unchanged; `run-ablation.sh` derives its default arm set from `priority` minus absent arms (head/evals/harness/run-ablation.sh:570-571), so a batch without `--arms` collects nothing for `a0_bare_fable`, `a1_review_only`, `a1_no_dissent` or `a1_full_openmount`. `cut_ladder` (:46) is likewise silent on them. If this is intentional (budget), record it in the suite comment at :94-97; if not, add the three decision arms to `priority` and decide explicitly whether the eval-only arm belongs in the default set.
**Suggestion:** One-line `priority` update plus a `run-ablation.bats` dry-run assertion on the default plan.
**Benefit:** The arms the sprint ships actually run.

### 4. Implementation report and PR description overstate the scope

- **MEDIUM** (confidence: high) `head/../pr/PR.md:1` — the title claims "the cycle-131 suite root (bounds 50/40) with its image self-check"; no file under `grimoires/loa/evals/` or any self-check is in `pr/head.diff` (the 11 files are the harness, suite, stub and five bats files). `reviewer.md` has no `## AC Verification` section and states no assumptions (Think Before Coding), so no acceptance criterion is traced to `file:line`.
**Suggestion:** Either drop the suite-root clause from the title or land that change; add the AC walkthrough to `reviewer.md`.
**Benefit:** The audit gate and the sprint ledger describe what actually merged.

### 5. Refusal ordering hides the more specific reason

- **LOW** (confidence: high) `head/evals/harness/pipeline-run.sh:259-262` — the `eval_only` exit 2 runs after `REFUSAL` is computed (:244-252) but before it is reported (:318 dry run, :468-472 run), so `pipeline-run.sh --arm a1_full_openmount` on a build task outside the batch context says only "eval_only arm outside an evaluation batch"; the operator sets `LOA_ABLATION_BATCH_CONTEXT=1` and then hits "does not apply to task type". Print the pending `REFUSAL` alongside, or check `eval_only` first and consistently.
**Suggestion:** `[[ -n "$REFUSAL" ]] && echo "pipeline-run.sh: refused: $REFUSAL" >&2` before the eval_only exit.
**Benefit:** One round-trip for manual runs.

### 6. Three copies of the toggle semantics

- **LOW** (confidence: medium) `head/evals/harness/pipeline-run.sh:341-345` and `head/evals/harness/validate-suite.sh:137-139` — the dry-run `config_edits` jq re-implements `apply_arm_toggles`' key mapping, and `TOGGLE_VALUES` is a hand-maintained copy of the `lib/sandbox-mount.sh` vocabulary, while rule ids are derived from `took-effect.sh` at :87. A toggle added to the library is rejected by the validator and misreported by `--dry-run` until two more edits land. `SIMPLICITY[shrink]`: expose a plan function in `lib/sandbox-mount.sh` (toggles JSON → key=value list) and call it from both; or add a bats case diffing `config_edits` against the keys actually written to the sandbox config for every committed arm. net: −12 lines possible.
**Suggestion:** As above.
**Benefit:** `--dry-run` stays a faithful preview; the validator stops drifting.

### 7. Stale pre-registration comment

- **LOW** (confidence: high) `head/evals/suites/ablation-2.0.yaml:117` — `multiple_comparisons: none  # expected false positives at 0.90 over 6 components printed` is now wrong (nine), and AR-12 asserts the Method section quotes the rules block verbatim (head/evals/tests/ablation-report.bats:190-191), so the report would carry "over 6" beside its own "over 9 components" sentence.
**Suggestion:** Update the comment with the count you settle on after Changes Required #1 / Observation 2.
**Benefit:** Self-consistent Method section.

### 8. Test assumptions I could not execute

- **LOW** (confidence: low) `head/evals/tests/run-ablation.bats:1194-1203` — RAB-c131-5 asserts exactly two trials for `a1_full` in both the batch (`review-01,review-02`) and the smoke run, so it depends on the committed smoke root holding exactly two tasks `a1_full` applies to; and `c131_arms` (head/evals/tests/pipeline-run.bats:1017-1020) now loads the real arms, which changed `a0_bare_fable` from `task_types: [all]` to `[review-catch]` for every test that uses it (all pass `$REVIEWC`, so no break found). Neither suite nor fixtures are present here, so the bats runs were not executed; the engineer's report should state the `bats evals/tests` result.
**Suggestion:** Paste the bats summary into `reviewer.md`.
**Benefit:** Fast-gate parity is verifiable.

---

## Rejected dissent payloads

- none — `metadata.rejected_summary` is empty and `adversarial-rejected-review.jsonl` is zero bytes (two voices, 2/2 succeeded, consensus).

## Cross-Model Observations

Advisory input, not counted: DISS-001 / DISS-C-001 (BLOCKING, both voices) match Changes Required #1; DISS-002 (BLOCKING, primary) and DISS-C-003 match Observation 1; DISS-C-002 matches Observation 2; DISS-C-004 matches Observations 3 and 7; DISS-C-005 matches Observation 5; DISS-C-006 matches Observation 6.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | The report cannot decide the three review-catch-only arms it introduces (Changes Required #1); the title's suite-root / image self-check is not in the diff (Observation 4) |

---

## Acceptance Criteria Check

### Task 1.1: review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict

| Criterion | Status | Notes |
|-----------|--------|-------|
| Four review-catch arms declared and validated | Pass | head/evals/suites/ablation-2.0.yaml:98-105; VS-14..17, AT-13 |
| eval_only refusal before any run artefact, batch context exported per trial | Pass | head/evals/harness/pipeline-run.sh:258-262; head/evals/harness/run-ablation.sh:1300-1301; RAB-c131-5 |
| validate-suite arm schema (toggles, took_effect, eval_only, oracle_open ⇒ eval_only) | Pass | head/evals/harness/validate-suite.sh:157-180 |
| Report treats the new arms correctly | Fail | Changes Required #1; Observations 1-2 |
| Suite root (bounds 50/40) with image self-check | Fail | Not in the diff (Observation 4) |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [x] Input validation and sanitization present — `eval_only` is type-checked by validate-suite, the env gate matches exactly `1`
- [x] Authentication/authorization correct — n/a; `LOA_ABLATION_BATCH_CONTEXT` is an operator guard, not a security boundary, and is not in the sandbox env allowlist (pipeline-run.sh header :57-63)
- [x] No SQL/XSS injection vulnerabilities — arm ids reach jq via `--arg`, not string splicing
- [x] Dependencies secure (no known CVEs) — no new dependencies
- [x] Error messages don't leak sensitive data

---

## Code Quality Summary

**Strengths:**
- Refusal placed before `mkdir`, so no `pipeline.json`/`infrastructure_error` row can be minted for a refused eval-only arm.
- Rule ids are derived from `took-effect.sh` rather than copied; the validator's type-exact value check (`0` ≠ `false`) is tested.
- `c131_arms` now loads the committed arms, so the pipeline tests exercise the real declarations.

**Areas for Improvement:**
- The report's decision path was not traced when the arm shapes changed; a review-catch-only component is a new shape and needs a primaries rule.
- Toggle semantics are now spelled out in three places.

---

## Next Steps

1. Add the review-only branch to `primaries()` and the two report tests (remove / keep) for a review-catch-only arm.
2. Decide and document the report surface for `a1_full_openmount` and whether `a0_bare_fable` is a component or a baseline; update `priority` and the rules comment.
3. Correct the PR title or land the suite-root change; add `## AC Verification` and the bats summary to `reviewer.md`.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":4,"low":4},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T06:12:11Z"} -->
