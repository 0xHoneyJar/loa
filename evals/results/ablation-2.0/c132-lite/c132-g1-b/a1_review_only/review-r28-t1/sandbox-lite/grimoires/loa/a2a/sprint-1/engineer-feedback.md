# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)
**Change under review:** pr/head.diff — "feat(cycle-131): sprint-264 — four review-catch arms, eval_only batch-context refusal, validate-suite arm schema, the cycle-131 suite root (bounds 50/40) with its image self-check" (11 files)

---

## Overall Assessment

The mechanical parts of this change are sound: the `eval_only` refusal in `pipeline-run.sh` sits before any run-directory creation and is covered by tests for the dry run, the real run, and the exact-value rule; `run-ablation.sh` has exactly one pipeline launch site and it carries `LOA_ABLATION_BATCH_CONTEXT=1`; the `--help` and `usage()` line ranges were re-counted correctly (pipeline-run.sh header ends at line 157, validate-suite.sh header at 57); the validate-suite arm-schema rules are type-exact and tested for each defined value; and the pipeline-run.bats fixture now loads the real arm definitions instead of a hand-shaped copy.

The problem is the report side. The PR adds three review-catch-only arms as *components* of `ablation-report.py` without touching `Analysis.primaries()`, which gives every arm whose `task_types` mentions review-catch the build primary as well. Those three arms will carry a permanent `no valid pair (hidden_test_pass_rate)` clause and can never reach `remove` or `simplify`, which is precisely the question a1_review_only and a1_no_dissent exist to answer. The eval_only arm is excluded from components and detail but its rows are never classified as listed either, so a batch that pays for a1_full_openmount trials produces a report with no trace of them. The suite's `priority` list was not extended, so a default batch never schedules any of the four arms. Both cross-model dissent voices independently reproduced the first three of these.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Functionality — review-catch-only components can never be decided

- **HIGH** (confidence: high) `head/evals/harness/ablation-report.py:1913` — a0_bare_fable, a1_review_only and a1_no_dissent become `components`, but `Analysis.primaries()` (`head/evals/harness/ablation-report.py:654-658`) returns `[hidden_test_pass_rate, defect_catch_rate]` whenever `"all" in types or REVIEW in types`; `compare(arm, CONTROL, PASS)` pairs over `BUILD_TYPES` tasks only, where these arms have no cells, so `usable()` is false, `nopair` is true, and `decide()` (`:871-874`) returns `inconclusive: … no valid pair (hidden_test_pass_rate)` for every batch unless the catch primary alone triggers `investigate` or `keep`.
**File:** `head/evals/harness/ablation-report.py:1913`, root at `:654-658`; the arms at `head/evals/suites/ablation-2.0.yaml:98-103`
**Issue:** `rules.primaries_by_arm` (`head/evals/suites/ablation-2.0.yaml:113`) has only `build_only` and `all_types` keys; there is no review-only branch, and the PR introduces the first review-catch-only decision arms. The `remove` and `simplify` states — the outcomes that would justify dropping the AUDIT gate or the review dissent — are structurally unreachable. The expected-false-positive sentence (`:1929`) then advertises nine live tests while three can never produce one.
**Why This Matters:** The three control arms spend review-catch budget on comparisons whose decision is pre-determined; the suite would report "inconclusive" indefinitely and the operator would read it as a power problem.
**Required Fix:** Add a `review_only: [defect_catch_rate]` entry to `rules.primaries_by_arm` and a matching branch in `primaries()` (`REVIEW in types and not ("all" in types or any build type in types)` → `review_only`). Add a bats case whose fixture rows give a review-catch-only arm catch pairs equal to control and assert the decision is `simplify`/`remove`, not `inconclusive`. Update the per-arm table so the pass column reads `n/a (review-only)` symmetrical to `n/a (build-only)` (`:1634`, `:1649`, `:1699`).

### 2. Data loss — the eval_only arm's rows vanish from the report

- **HIGH** (confidence: high) `head/evals/harness/ablation-report.py:1121-1123` — `list_reason()` has no `eval_only` branch, so a1_full_openmount rows return `None`, enter `self.cells`/`self.arm_rows`, and are then rendered nowhere: not in `components` (`:1913`), not in `detail_arms` (`:2003`), hence not in `render_per_arm`/`arms_json`, and not in "Rows listed, never decided".
**File:** `head/evals/harness/ablation-report.py:1121-1123`, `:1913`, `:2003`
**Issue:** The suite comment calls this arm "the open-mount oracle A/B … an evaluation control" (`head/evals/suites/ablation-2.0.yaml:96-97`), yet nothing compares a1_full_openmount against a1_full, and the row-accounting line (`:1984-1986`) counts its rows in the total while attributing them to no bucket. An operator cannot tell from the report that the arm ran.
**Why This Matters:** The one purpose of running an eval_only arm is the A/B; after this change the batch spends the money and the result is silently discarded.
**Required Fix:** Either (a) list the rows — add an `eval_only` check to `list_reason()` returning `f"eval_only arm {arm}: evaluation control, never decided"` — and render a small "Evaluation controls" section with the a1_full_openmount vs a1_full `defect_catch_rate` interval (deciding nothing, like the existing sensitivities), or at minimum (a) alone so the rows are accounted for. Add an assertion to ablation-report.bats with a fixture row on a1_full_openmount.

---

## Observations

### 1. Suite wiring

- **MEDIUM** (confidence: medium) `head/evals/suites/ablation-2.0.yaml:55` — `priority` still lists only the original eight runnable arms. `run-ablation.sh` derives the default `--arms` from `.priority` (`head/evals/harness/run-ablation.sh:570-571`), so a default batch never launches a0_bare_fable, a1_review_only, a1_no_dissent or a1_full_openmount; the RAB-c131-5 case passes only because it names `--arms a1_full`. If leaving them out of the default batch is intentional, say so on the arm comment at `:94-97`; otherwise append them to `priority` (and decide where they sit in the cut ladder).
**Suggestion:** State the intent in the suite file either way; the eval_only machinery is documented as "run-ablation.sh exports it to every trial it launches", which reads as if the batch runs the arm.
**Benefit:** Removes a silent no-op for the operator who runs the documented default batch.

- **LOW** (confidence: high) `head/evals/suites/ablation-2.0.yaml:117` — the `multiple_comparisons: none` comment still says "over 6 components"; the PR moved k to 9 (`head/evals/tests/ablation-report.bats:189`).

### 2. SIMPLICITY — three copies of the toggle semantics

- **MEDIUM** (confidence: medium) `head/evals/harness/pipeline-run.sh:341-345` — `SIMPLICITY[shrink]`: the dry-run `config_edits` field is a hand-written jq over four toggles (companion_voice, gates, dissent, flatline) that mirrors what `lib/sandbox-mount.sh apply_arm_toggles` does to the sandbox `.loa.config.yaml`. The other nine toggles in the vocabulary always render `-`, and any future change to the library silently makes the dry run wrong with no test tying the two together (the library is not in this PR, so the mirror could not be verified here).
**Suggestion:** Have the library expose the edit list (e.g. `apply_arm_toggles --plan` printing `key=value` lines) and let the dry run call it, or at least add a bats case that runs a real `apply_arm_toggles` on a temp config and diffs its keys against the dry-run line for every arm in the suite.
**Benefit:** One source of truth; `net: -8 lines possible` in pipeline-run.sh.

- **LOW** (confidence: medium) `head/evals/harness/validate-suite.sh:137-139` — `TOGGLE_VALUES` is a hand-maintained table, while the rule ids on the same check are derived from `took-effect.sh` at run time (`:85-88`). The asymmetry invites drift: a toggle added to `apply_arm_toggles` without a matching table entry makes the validator reject a correct suite. Consider reading the vocabulary from the library the same way, or document that the table is the authority.

### 3. Report, tests and process

- **MEDIUM** (confidence: high) `head/evals/tests/ablation-report.bats:342` — `GOAL-DRIVEN:` the only assertions touching the new components are the count (9 decisions) and the EFP sentence (`:189`). The fixture has no rows for any cycle-131 arm, so every new component lands in `no_rows` and the decision path for a review-catch-only arm is never executed — which is how Changes Required §1 passed the suite. Add a fixture scenario with catch-only rows for one of the new arms and assert its decision state.

- **MEDIUM** (confidence: high) `pr/PR.md:1` — the title promises "the cycle-131 suite root (bounds 50/40) with its image self-check", but no file under a suite root (`grimoires/loa/evals/ablation-2.0/…`) or any self-check script is in the diff; the 11 files are harness, suite yaml, tests and a fixture. The implementation report carries no `## AC Verification` walkthrough and no statement of which bats files were run (FAST-GATE: unverified). Either drop the claim from the description or include the files; add the AC walkthrough and the test run evidence.

- **LOW** (confidence: medium) `head/evals/harness/pipeline-run.sh:258` — `[[ "$(jq -r '.eval_only // false' <<<"$ARM_DEF")" == true ]]` treats `eval_only: 1` or `eval_only: "yes"` as *not* eval_only and runs the arm unrestricted. `validate-suite.sh` rejects those spellings (`:177-178`), but `pipeline-run.sh` does not run the validator and accepts an arbitrary `--suite-file`. A `die_usage` on any non-boolean value would close the gap in two lines.

### 4. Cross-Model Observations (advisory, not counted)

- Dissent DISS-C-006 (claude-headless) worried that run-ablation.sh invokes pipeline-run.sh on other paths (retry, preflight, took-effect re-run) without the batch variable. Checked: `run_trial` at `head/evals/harness/run-ablation.sh:1295-1301` is the only `$PIPELINE_BIN` invocation in the script; not a defect.
- DISS-C-004 and DISS-C-005 correspond to the `eval_only` parsing and dry-run `config_edits` observations above.

## Rejected dissent payloads

- none (`metadata.rejected_summary` is empty and `adversarial-rejected-review.jsonl` has zero rows; two voices, gpt-5.5-pro via codex-headless and claude-headless, both completed, `consensus`).

---

## Previous Feedback Status

Not applicable — first review of this sprint.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Reviewed, not approved | Changes Required §1–§2 |

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| "review the pull request" | Done | Every touched head file read; surrounding code (`primaries`, `compare`, `decide`, `list_reason`, `run_trial`, dry-run block, header line counts) verified against the diff's claims |
| "report each defect it introduces with the file and line it sits on" | Done | 2 high, 4 medium, 3 low above, each with `head/<path>:<line>` |
| "give a merge verdict" | Done | CHANGES_REQUIRED |

**Could not verify in this snapshot** (not in the PR, not on disk): `lib/sandbox-mount.sh apply_arm_toggles` (toggle vocabulary the validator and the dry run assume), `took-effect.sh` (the nine rule ids the new arms name — VS-16 asserts them but was not run here), the `fixtures/ablation-runs/suite.yaml` BARE caps (inferred 170/4200 from the existing test at `head/evals/tests/pipeline-run.bats:155`), and the smoke-task count behind RAB-c131-5's `-eq 2` (consistent with RAB-4's 2 smoke tasks). No bats suite was executed; the `evals/` tree is not present in the workspace.

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [x] Input validation at trust boundaries — validate-suite arm schema is type-exact; pipeline-run.sh `eval_only` parse is lenient (Observation 3, low)
- [x] Authentication/authorization — n/a
- [x] No injection — jq/yq receive values via `--arg`; `RULE_IDS` is built from a fixed regex over an in-tree script and passed as a single argv
- [x] Dependencies — none added
- [x] Error messages — the refusal names the arm id only

---

## Code Quality Summary

**Strengths:**
- The refusal is placed before the run directory exists and is proven so by the test (`[ ! -e "$T/run" ]`), with the exact-value rule covered for `0`, `yes`, `true`, and empty.
- `c131_arms` now loads the committed arm definitions, so the pipeline tests cannot drift from the suite.
- `RULE_IDS` derived from `took-effect.sh` is the right pattern for the schema check.

**Areas for Improvement:**
- The report never learned that a review-catch-only component exists; the suite, the primaries rule and `primaries()` must move together.
- Toggle→config semantics now live in three places.

---

## Next Steps

1. Fix Changes Required §1 and §2 in `ablation-report.py` and the suite rules, with fixture rows that exercise a review-catch-only decision and an eval_only arm.
2. Decide and document the `priority` question; fix the stale comment.
3. Add the AC Verification walkthrough and the bats run evidence to `reviewer.md`; reconcile the PR description with the diff.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":4,"low":3},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T04:20:00Z"} -->
