# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)
**Change under review:** `pr/head.diff` — "feat(cycle-131): sprint-264 — four review-catch arms, eval_only batch-context refusal, validate-suite arm schema, the cycle-131 suite root (bounds 50/40) with its image self-check" (11 files)

---

## Overall Assessment

The mechanics that the diff actually ships are sound and well tested: the `eval_only` refusal in `pipeline-run.sh` sits after argument validation and before any run directory is created (`head/evals/harness/pipeline-run.sh:258-262`), it honours exactly the value `1`, `run-ablation.sh` sets the variable on the trial command only (`head/evals/harness/run-ablation.sh:1300-1301`, the single launch site), the dry run prints a sandbox plan that I reproduced against the committed suite for all six arms I tried, and the new `validate-suite.sh` arm-schema checks are type-exact and read the rule set from `took-effect.sh` rather than a second copy. `bash -n` on the four shell files and `py_compile` on the report pass.

Two defects block the merge, both in how the four new arms reach the pipeline downstream of the files that declare them:

1. The suite's `priority` list was not updated, and `run-ablation.sh` derives its default arm set from `priority`. A default batch never schedules the four cycle-131 arms.
2. The report now counts three review-catch-only arms as components, but `primaries()` assigns `hidden_test_pass_rate` to any arm whose `task_types` names review-catch. Those arms have no build rows, so that comparison is never usable and `decide()` can never reach `remove` or `simplify` for them — the exact outcomes the "drop AUDIT" and "drop dissent" arms exist to test.

The PR description also claims a cycle-131 suite root (bounds 50/40) and an image self-check; neither appears in the diff, and the implementation report carries no AC Verification section. Medium and low findings follow under Observations.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Functionality — the four new arms are not in the runner's default plan

- **HIGH** (confidence: high) `head/evals/suites/ablation-2.0.yaml:55` — `priority` still lists only `a0_bare … a6_one_window`; `run-ablation.sh` builds its default arm set from `.priority` minus absent arms (`head/evals/harness/run-ablation.sh:570-571`), so a batch started without `--arms` never schedules `a0_bare_fable`, `a1_review_only`, `a1_no_dissent` or `a1_full_openmount`.
**File:** `head/evals/suites/ablation-2.0.yaml:55`
**Issue:** The diff adds four arms at `head/evals/suites/ablation-2.0.yaml:98-105` and documents them as the cycle-131 review-catch arms, but `priority` (the file's own header at line 12 names it as a `run-ablation.sh` input) is untouched. `run-ablation.sh:24` documents the default as "the suite's priority minus absent", and `run-ablation.sh:570-571` implements exactly that.
**Why This Matters:** The whole FR-5 batch-context design (the env var exported "to every trial it launches") assumes the arms run inside `run-ablation.sh` batches. With the default plan omitting them, a cycle-131 batch produces no rows for three of the nine components the report now expects, and the report's new 9-component false-positive line and decision table describe arms that were never run. `AT-13` checks the arm list; nothing checks `priority`.
**Required Fix:** Append the four ids to `priority` (position decides cut order; `a1_full_openmount` presumably last), and extend `AT-13` (or a new case) to assert every non-absent arm id appears in `priority`. If the intent is instead that cycle-131 batches are always launched with an explicit `--arms`, say so in the suite header and in `run-ablation.sh`'s usage text, and add the test that pins it.

### 2. Functionality — review-catch-only components can never be decided "remove" or "simplify"

- **HIGH** (confidence: high) `head/evals/harness/ablation-report.py:653-658` — `primaries()` returns `primaries_by_arm.all_types` (`[hidden_test_pass_rate, defect_catch_rate]`) for any arm whose `task_types` contains `review-catch`; for `a0_bare_fable`, `a1_review_only` and `a1_no_dissent` (now components via line 1913) the pass-rate comparison has no build tasks (`compare`, lines 731-733, selects `BUILD_TYPES` tasks of which the arm has none), so `n == 0`, `usable()` (line 577) is false, `nopair` is true in `decide()` (lines 846-887) and every run that does not already hit `investigate` or `keep` on catch rate is read `inconclusive: no valid pair (hidden_test_pass_rate …)`. `remove` and `simplify` are unreachable.
**File:** `head/evals/harness/ablation-report.py:653-658`
**Issue:** The `components` filter at line 1913 was widened to admit the first review-catch-only arms, but the primaries logic still has only two shapes — "build only" and "all types" — and keys the second on `REVIEW in types`. The `rules.primaries_by_arm` block in the suite (`head/evals/suites/ablation-2.0.yaml:113`) has no entry for review-catch-only arms either.
**Why This Matters:** `a1_review_only` asks "does the AUDIT gate add anything?" and `a1_no_dissent` asks "does review dissent add anything?". The informative answer is `remove`/`simplify` (no loss, cheaper). Under this code those states are structurally impossible for those arms; the report will always print `Inconclusive` for them, and the operator may read that as insufficient data rather than a harness defect. The test fixtures do not catch it because the three arms have no rows in the `main` scenario (`head/evals/tests/ablation-report.bats:189, 342` only count rows and the k in the sentence).
**Required Fix:** Give review-catch-only arms their own primary set (e.g. `primaries_by_arm.review_only: [defect_catch_rate]` in the suite rules with a matching branch in `primaries()` — `types == [REVIEW]` or "no build type in types" → catch rate only), and add a report test with rows for one of these arms asserting a `remove`/`simplify` decision is reachable and that the comparison list has no pass-rate entry.

---

## Observations

### 1. Report semantics — `a0_bare_fable` counted as a component

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-report.py:1913` — `a0_bare_fable` passes the new filter (it is neither `CONTROL`, `BARE`, absent nor `eval_only`) and so gets a keep/remove decision row against `a1_full`, although the suite comment at `head/evals/suites/ablation-2.0.yaml:94-95` calls it "A0 on the review model", i.e. a baseline, and the comment on line 1911-1912 says components are "every runnable arm but the two baselines". The decision table then carries a meaningless "remove a0_bare_fable" style row and `k` in the expected-false-positive sentence is 9 rather than 8; `head/evals/tests/ablation-report.bats:189` and `:342` lock the 9 in. The companion dissent voice raised the same point (DISS-C-001).
**Suggestion:** Decide explicitly whether a bare-model arm is a component. If not, exclude arms with `toggles.loa_mount == false` (or a `baseline: true` flag analogous to `eval_only`) from `components`, keep the arm in the per-arm detail, and set the tests to 8.
**Benefit:** The decision table and the false-positive budget describe only ablatable components.

### 2. Report coverage — the eval_only arm is invisible in the report

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-report.py:2003` — `detail_arms = [BARE, CONTROL] + components` inherits the `eval_only` exclusion, so `a1_full_openmount` appears neither in Decisions nor in Per-arm detail. Its rows are still loaded, but the only place they surface is the oracle-exposed exclusion note (line 1624). The open-mount oracle A/B that FR-5 introduces the arm for cannot be read from the report.
**Suggestion:** Keep `eval_only` arms out of `components` but add them to `detail_arms` (or render a labelled `a1_full` vs `a1_full_openmount` comparison that "decides nothing", as the two report-1.3 sensitivities do).
**Benefit:** The arm's purpose is served by the artifact that is supposed to show it.

### 3. Duplication — the dry-run config_edits mapping is a hand copy of `apply_arm_toggles`

- **MEDIUM** (confidence: medium) `head/evals/harness/pipeline-run.sh:338-346` — the jq expression that prints `config_edits=` re-implements which `.loa.config.yaml` keys each toggle sets (companion_voice, gates, dissent, flatline). The authoritative mapping lives in `lib/sandbox-mount.sh apply_arm_toggles` (not in this diff). A toggle added or re-mapped in the library leaves the dry run printing a plan the sandbox does not get, and the new dry-run tests (`head/evals/tests/pipeline-run.bats:1175-1221`) pin the copy, not the library.
**Suggestion:** Have the library expose its mapping (a function that prints `key=value` lines for a toggles JSON) and call it from the dry run, so one source serves both. `SIMPLICITY[shrink]`: net: -12 lines possible in `pipeline-run.sh`.
**Benefit:** No silent divergence between "what the dry run says" and "what the sandbox does".

### 4. Duplication — `TOGGLE_VALUES` is a second copy of the toggle vocabulary

- **MEDIUM** (confidence: medium) `head/evals/harness/validate-suite.sh:137-139` — the validator hard-codes the toggle names and accepted values although the same script sources `lib/sandbox-mount.sh` a few lines above and already derives `RULE_IDS` from `took-effect.sh` (line 87) rather than listing them. A toggle the library accepts but this table lacks is rejected as "unknown toggle"; the reverse validates an arm the sandbox ignores. The companion dissent voice raised the same point (DISS-C-002).
**Suggestion:** Export the vocabulary from the library (or parse its `case` labels the way `RULE_IDS` parses `rule_<id>()`) and pass it to the Python block as a seventh argument beside `RULE_IDS`; or add a test asserting `TOGGLE_VALUES` equals the keys `apply_arm_toggles` dispatches on.
**Benefit:** The validator and the runtime agree by construction.

### 5. Report vs code — the PR description claims work the diff does not contain

- **MEDIUM** (confidence: high) `pr/PR.md:1` — the title promises "the cycle-131 suite root (bounds 50/40) with its image self-check". No file under `grimoires/loa/evals/` and nothing touching an image or a self-check is in `head.diff`; the only suite-root reference is the pre-existing fixture copy in `head/evals/tests/run-ablation.bats:1196`. The report also has no `## AC Verification` section, so none of the sprint's deliverables is traced to `file:line` evidence.
**Suggestion:** Either add the missing files to the change or retitle the PR to what it ships; add an AC walkthrough so the reviewer can check each claim.
**Benefit:** Reviewers and the audit trail judge the change that exists.

### 6. Documentation drift in the suite header

- **LOW** (confidence: high) `head/evals/suites/ablation-2.0.yaml:29-31` — "Every mounted review-catch arm runs the closed mount" is no longer true once `a1_full_openmount` (open mount, `oracle_open: true`) is declared five lines later.
**Suggestion:** Qualify the sentence ("every mounted review-catch arm except an `oracle_open` eval_only arm").

- **LOW** (confidence: high) `head/evals/suites/ablation-2.0.yaml:117` — `multiple_comparisons: none  # expected false positives at 0.90 over 6 components printed` — the report and `AR-12` now say 9 (or 8, see Observation 1).
**Suggestion:** Update the comment, or drop the number from it.

### 7. Untested downstream of a one-phase review-catch run

- **LOW** (confidence: low) `head/evals/tests/pipeline-run.bats:1256-1263` — the `a1_review_only` test asserts the phases and `completed`, but nothing in the diff exercises grading or `took-effect.sh` (`review_only_phases`) for a run with a single gate output; `ablation-grade.sh` and `took-effect.sh` are outside the diff, so I could not verify they accept a review-catch run without an AUDIT envelope.
**Suggestion:** Add a run-ablation or grade-level test with the stub producing one envelope.

### 8. Changelog

- **LOW** (confidence: low) `head/evals/suites/ablation-2.0.yaml:98` — the change adds four arms, a new suite key (`eval_only`), a new env contract (`LOA_ABLATION_BATCH_CONTEXT`) and new validator rules, but the diff carries no CHANGELOG entry. I cannot see whether this repository keeps one for `evals/`; if it does, this needs a line.

---

## Cross-Model Observations

Adversarial dissent ran on `pr/head.diff` (`--type review --sprint-id sprint-1 --diff-file pr/head.diff`), two voices, status `clean`, consensus, 2/2 voices succeeded. Two ADVISORY findings, both already covered above:

- DISS-C-001 (`ablation-report.py:1913`) — `a0_bare_fable` treated as a component. → Observation 1.
- DISS-C-002 (`validate-suite.sh:137-139`) — `TOGGLE_VALUES` duplicates the library's toggle vocabulary. → Observation 4.

## Rejected dissent payloads

- none — `metadata.rejected_summary` is `[]`, `rejected_count` 0, no `adversarial-rejected-review*.jsonl` sidecar beside `adversarial-review.json`.

---

## Acceptance Criteria Check

Sprint success criterion (grimoires/loa/sprint.md): "review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict" — this document.

### Task 1.1: the change in `pr/head.diff` (deliverables per the PR title)

| Criterion | Status | Notes |
|-----------|--------|-------|
| Four review-catch arms declared and validated | Partial | Declared (`ablation-2.0.yaml:98-105`), validated (`validate-suite.sh:157-180`), but absent from `priority` (Change 1) and undecidable in the report (Change 2) |
| eval_only batch-context refusal | Pass | `pipeline-run.sh:258-262`; `run-ablation.sh:1300-1301`; dry run reproduced here: refusal exit 2 without the variable, plan with it |
| validate-suite arm schema (toggles, took_effect, eval_only) | Pass | `validate-suite.sh:137-139, 157-180`; tests VS-14…VS-17 |
| cycle-131 suite root (bounds 50/40) | Fail | Not in the diff |
| image self-check | Fail | Not in the diff |
| `## AC Verification` in the implementation report | Fail | Report is the PR title only |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [x] Input validation at trust boundaries — `eval_only` and toggle values are type-exact; the batch-context check accepts only the literal `1`
- [x] No new code paths touch user-controlled paths; the Python validator runs with `-I`
- [x] Error messages name the arm id and the reason, nothing sensitive
- [ ] n/a — no auth, SQL or web surface in this change

## Fast-Gate Parity

`bash -n` on `pipeline-run.sh`, `run-ablation.sh`, `validate-suite.sh`, `ablation-pipeline-stub.sh` and `python3 -I -m py_compile ablation-report.py` pass. The bats suites could not be executed here: the workspace holds only the touched files, and the tests need `took-effect.sh`, `lib/sandbox-mount.sh`, `evals/tests/fixtures/ablation-runs/` and `grimoires/loa/evals/ablation-2.0`. Treat the test assertions as unverified by this review; the report's AR-12 arithmetic (0.45 / 0.90 at `.2f`) was checked by hand.

## Complexity Review

No function over 50 lines added; nesting stays within 3. Over-engineering: the two duplicated vocabularies (Observations 3 and 4) are the only shrink candidates — net: -12 lines possible. Otherwise lean.

## Code Quality Summary

**Strengths:**
- The refusal is positioned exactly where its comment says (after validation, before the run dir), and the test covers dry run, real run, the four non-`1` values and a non-eval_only arm.
- `RULE_IDS` is derived from `took-effect.sh`, not listed; the validator's type-exact comparison rejects `0` for `false`.
- The pipeline-run tests now load the four arms from the committed suite, so fixture and suite cannot drift.

**Areas for Improvement:**
- Downstream consumers of a new arm (`priority`, report primaries, detail rendering) were not walked when the arms were added.
- Two hand-maintained copies of library knowledge.

## Next Steps

1. Add the four arms to `priority` (or pin the explicit-`--arms` contract) with a test.
2. Give review-catch-only components a catch-rate-only primary set and a test that reaches `remove`/`simplify`.
3. Decide `a0_bare_fable`'s role (baseline vs component) and render the `eval_only` arm's detail.
4. Reconcile the PR title with the diff and add an AC Verification walkthrough.
5. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":5,"low":4},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T23:40:00Z"} -->
