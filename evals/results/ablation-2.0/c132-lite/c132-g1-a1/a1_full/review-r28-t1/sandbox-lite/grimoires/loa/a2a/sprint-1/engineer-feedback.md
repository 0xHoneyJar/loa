# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)
**Change under review:** pr/head.diff — "feat(cycle-131): sprint-264 — four review-catch arms, eval_only batch-context refusal, validate-suite arm schema, the cycle-131 suite root (bounds 50/40) with its image self-check" (11 files)

Paths below are cited as `head/<path>:<line>` with line numbers from `pr/head/`.

---

## Overall Assessment

The eval_only refusal, its batch-context plumbing and the validate-suite arm schema are implemented carefully and are well tested: the refusal sits before any run-directory write (`head/evals/harness/pipeline-run.sh:256-262`, run dir created from line 352), only the exact value `1` opens it, run-ablation.sh sets the variable on the single pipeline launch site only (`head/evals/harness/run-ablation.sh:1300-1301`), the `--help` and usage sed ranges were re-anchored correctly (header ends at `pipeline-run.sh:157`, `validate-suite.sh:57`), the type-exact toggle check rejects `0` for `false`, and the bats coverage (pipeline-run, run-ablation, validate-suite, arm-toggles) exercises both the pass and fail sides of each new rule.

The sprint's goal, however, is the four arms as decision/evaluation arms, and the three new *component* arms cannot reach a decision in the report. `primaries()` hands every arm whose task_types include review-catch both primaries, so the pass-rate contrast for a review-catch-only arm never pairs and the decision collapses to "inconclusive: no valid pair" whenever `investigate`/`keep` do not fire. Both dissent voices (gpt-5.5-pro DISS-001, claude-headless DISS-C-001) reached the same conclusion independently. That is one HIGH finding; the medium/low items are design and hygiene observations.

Not run: the workspace holds only the eleven touched files (no `lib/sandbox-mount.sh`, `took-effect.sh`, fixtures or suite root), so the bats suites could not be executed here and claims about those libraries are read from the touched files' references only.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Functionality — review-catch-only component arms can never be decided

- **HIGH** (confidence: high) `head/evals/harness/ablation-report.py:656-658` — for an arm whose `task_types` is `[review-catch]` (a0_bare_fable, a1_review_only, a1_no_dissent) `primaries()` returns `all_types` = `[hidden_test_pass_rate, defect_catch_rate]`; the pass-rate comparison has no build rows to pair, so `remove`/`simplify` are unreachable and `decidable` stays False forever.
**File:** `head/evals/harness/ablation-report.py:656-658` (the arms: `head/evals/suites/ablation-2.0.yaml:98-103`; the component list: `head/evals/harness/ablation-report.py:1913`)
**Issue:** `primaries()` reads `"all" in types or REVIEW in types` → `all_types`. `arm_report()` (`:889-891`) then builds `compare(arm, a1_full, hidden_test_pass_rate)`. In `compare()` (`:731-760`) the build tasks come from a1_full's cells, the arm has no build cell, every task lands in `unpaired` and `n == 0`, so `usable()` (`:577-579`) is False. In `decide()` (`:849-877`) that makes `nopair` True; after the `investigate` and `keep` tests it always appends "no valid pair (hidden_test_pass_rate: …)" and returns `inconclusive`, so the `remove` (`:878-886`) and `simplify` (`:887`) branches are dead for these arms, and `out["decidable"]` (`:922`) is False. The H1/A4 path has a `not_testable` read for exactly this situation (`assess()`, `:1200-1204`); the component path has none. The suite's `primaries_by_arm` (`head/evals/suites/ablation-2.0.yaml:113`) only knows `build_only` and `all_types`.
**Concrete failing input:** a complete cycle-131 batch of a1_review_only on the four review-catch tasks with defect_catch_rate within −0.03 of a1_full and cost 30 % lower — the ablation's intended "the AUDIT gate can be removed" outcome. The report prints "inconclusive: no valid pair (hidden_test_pass_rate: …)" and `decidable: false`.
**Why This Matters:** the three arms are the deliverable of FR-5; the report they feed cannot produce the decision states they exist to reach, and the expected-false-positive line counts them as nine real comparisons (`:1927-1932`). No test exercises a review-catch-only component with rows: AR-12 and the `by_suite_version` case (`head/evals/tests/ablation-report.bats:189,342`) only assert the count 9 on arms with no rows (`no_rows` state).
**Required Fix:** give review-catch-only arms a review-only primary set — e.g. add `review_only: [defect_catch_rate]` to `rules.primaries_by_arm` in the suite and branch on it in `primaries()` (types contain neither `all` nor a build type → review-only); keep `all_types` for `all`. Add an ablation-report.bats case that plants review-catch rows for a review-catch-only component and asserts `decidable: true` and a reachable `remove`/`simplify`/`keep`. Re-check the `k` in AR-12 after deciding item 1 of the Observations.
**Reference:** GOAL-DRIVEN (Karpathy 4): non-trivial logic without a runnable check that fails when it breaks.

```python
# Current (head/evals/harness/ablation-report.py:653-658)
def primaries(self, arm):
    types = self.arms[arm].get("task_types") or []
    pba = self.rules.get("primaries_by_arm") or {}
    if "all" in types or REVIEW in types:
        return list(pba.get("all_types") or [PASS, CATCH])
    return list(pba.get("build_only") or [PASS])

# Should distinguish the review-catch-only arm
def primaries(self, arm):
    types = self.arms[arm].get("task_types") or []
    pba = self.rules.get("primaries_by_arm") or {}
    builds = "all" in types or "build" in types or any(t in BUILD_TYPES for t in types)
    if "all" in types or (REVIEW in types and builds):
        return list(pba.get("all_types") or [PASS, CATCH])
    if REVIEW in types:
        return list(pba.get("review_only") or [CATCH])
    return list(pba.get("build_only") or [PASS])
```

---

## Observations

### 1. Report semantics

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-report.py:1913` — a0_bare_fable is counted as a *component* and gets a keep/remove/simplify decision row against a1_full, although the suite describes it as "A0 on the review model" (`head/evals/suites/ablation-2.0.yaml:94-95`), i.e. a baseline like `a0_bare`; a "remove: a0_bare_fable" row is meaningless and it inflates `k` (and the AR-12 expectation of 9) by one.
**Suggestion:** either exclude it from `components` the way BARE is (a `baseline: true` arm key, or treat `loa_mount: false` arms as baselines) and render it beside H1 as the Fable-side bare contrast, or state in the suite comment why a bare-model arm is a component decision.
**Benefit:** the decisions table and the false-positive budget describe real component ablations only.

- **MEDIUM** (confidence: medium) `head/evals/suites/ablation-2.0.yaml:55` — `priority` was not extended, so a batch without `--arms` (`head/evals/harness/run-ablation.sh:570-571`) never runs the three new decision arms, while the report counts them in `k` and prints a `no_rows` row for each.
**Suggestion:** add a0_bare_fable, a1_review_only, a1_no_dissent to `priority` (not a1_full_openmount), or document that cycle-131 arms are opt-in and make the report count only arms the batch planned.

- **LOW** (confidence: medium) `head/evals/harness/ablation-report.py:2003` — a1_full_openmount rows pass `list_reason` (`:1108-1123`) and enter cells, but the arm is neither a component nor in `detail_arms`, so the open-mount A/B the arm is run and paid for is never rendered (only its oracle-exposed rows surface in the sensitivity count, `:1624`). (Dissent DISS-C-004, triaged: real gap, not in this sprint's stated scope.)

- **LOW** (confidence: high) `head/evals/suites/ablation-2.0.yaml:117` — comment "expected false positives at 0.90 over 6 components printed" is stale (now 9); AR-12 quotes this block verbatim, so keep it accurate.

### 2. Refusal keyed on the flag, not the toggle

- **MEDIUM** (confidence: medium) `head/evals/harness/pipeline-run.sh:258-259` — the refusal reads `eval_only`, not `oracle_open`. The invariant "oracle_open ⇒ eval_only" lives only in validate-suite.sh (`head/evals/harness/validate-suite.sh:179-180`), which pipeline-run.sh never runs, and `--suite-file` accepts any file. Concrete input: the committed suite with `eval_only` deleted from a1_full_openmount (exactly the shape VS-17 rejects) runs the open mount with no batch-context check. (Dissent DISS-C-002, confirmed.)
**Suggestion:** also refuse when `SUITE_TOGGLES.oracle_open == true` outside the batch context, so the fence is on the behaviour that leaks the oracle.

### 3. Hand-duplicated vocabularies (SIMPLICITY / drift)

- **LOW** (confidence: medium) `head/evals/harness/pipeline-run.sh:341-345` — the dry-run `config_edits` line re-implements apply_arm_toggles' toggle→config mapping by hand and reads the raw `SUITE_TOGGLES`, whereas the run uses the library-resolved `TOGGLES` (`:510-515`); a mapping change in lib/sandbox-mount.sh, or toggles the line does not list (karpathy_block, rule_files, audit_delta_instruction), makes the dry run misreport the sandbox.
**Suggestion:** have the library expose the planned edits (a `describe_arm_toggles` call) and print that, or state in the header that the dry-run line is a summary of four toggles only.

- **LOW** (confidence: medium) `head/evals/harness/validate-suite.sh:137-139` — `TOGGLE_VALUES` is a copied vocabulary of lib/sandbox-mount.sh while `RULE_IDS` (`:85-88`) is derived from took-effect.sh; a toggle added to the library without this edit is rejected by the validator with an "unknown toggle" message that points at the suite, not at the copy.

### 4. Report and process

- **MEDIUM** (confidence: high) `pr/PR.md:1` — the title claims "the cycle-131 suite root (bounds 50/40) with its image self-check"; nothing in `pr/head.diff` touches a suite root, bounds or an image self-check (the only files are the five harness/suite files and six tests). Either the diff is incomplete or the title overstates the change; the merge description must match the merged content.

- **MEDIUM** (confidence: low) `pr/PR.md:3` — FAST-GATE / Think-before-coding: the implementation report is a title and a file count; it carries no `## AC Verification`, no record that the bats suites, shellcheck or the formatter ran, and no stated assumptions. The skill's automatic CHANGES_REQUIRED for a missing AC Verification is noted; the verdict here rests on the blocking defect in Changes Required §1 and would stand without this item. Please add the self-check evidence and an AC walkthrough to the report when resubmitting.

---

## Cross-Model Observations

Two voices ran (primary gpt-5.5-pro, companion claude-headless, `counted_as: independent_voice`; envelope `grimoires/loa/a2a/sprint-1/adversarial-review.json`, status `reviewed`).

- DISS-001 (BLOCKING, gpt-5.5-pro) and DISS-C-001 (BLOCKING, claude-headless): the review-catch-only component arms' pass-rate primary never pairs → counted as Changes Required §1.
- DISS-C-002 (ADVISORY): refusal keyed on `eval_only`, not `oracle_open` → Observations §2 (MEDIUM).
- DISS-C-003 (ADVISORY): "the eval_only refusal is placed after the applicability branch, so an eval_only arm on a build task records an applicability refusal" → **not a defect**: the applicability branch only assigns `REFUSAL` (`head/evals/harness/pipeline-run.sh:249-252`); it is acted on at `:318` (dry run) and `:468-472` (run), both after the eval_only `exit 2` at `:259-262`, so the eval_only refusal still fires first and writes nothing.
- DISS-C-004 (ADVISORY): the open-mount A/B is never rendered → Observations §1 (LOW).

## Rejected dissent payloads

None — `metadata.rejected_summary` is empty and the listed sidecar `adversarial-rejected-review.jsonl` has zero rows.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | the three component arms cannot reach a decision in the report (Changes Required §1); the PR title names work absent from the diff |

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| "review the pull request, report each defect it introduces with the file and line it sits on" | Pass | every finding above carries a `head/<path>:<line>` citation |
| "give a merge verdict" | Pass | CHANGES_REQUIRED (1 high) |
| eval_only arm refused outside a batch before anything is created (`pipeline-run.sh:138-144`) | Pass | refusal at `:259-262`, run dir from `:352`; tests `pipeline-run.bats:1223-1244` |
| run-ablation.sh marks every trial with the batch context (`run-ablation.sh:163-166`) | Pass | single launch site `:1300-1301`; test RAB-c131-5 (`run-ablation.bats:1189-1209`) incl. the non-vacuous `<unset>` check |
| validate-suite rule 8: toggles vocabulary, took_effect ids, eval_only boolean, oracle_open ⇒ eval_only | Pass | `validate-suite.sh:157-180`; VS-14..VS-17 |
| the four arms declared and read by the report as intended | Fail | `primaries()` gap above; a0_bare_fable semantics; `priority` unchanged |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [x] Input validation at the trust boundary (suite values type-checked; env value compared exactly to `1`; `took-effect.sh` rule ids read by a fixed regex from a sibling path)
- [x] No shell injection: arm ids and values flow through `jq --arg`/argv, never into eval'd strings
- [x] Error messages do not leak secrets
- [ ] n/a: authentication, SQL/XSS, dependency CVEs (no such surfaces in the change)
- Note: `LOA_ABLATION_BATCH_CONTEXT` is an operator misuse guard, not a security boundary — anyone can export it; the open-mount leak is bounded by run-ablation's rows being labelled oracle_open (see Observations §2 for the gap).

---

## Code Quality Summary

**Strengths:**
- Refusal placed before any side effect, with dry run honouring the same gate; tests assert "no run dir, no argv log" and the exact-value rule.
- Tests derive the four arms from the committed suite instead of a drifting copy (`pipeline-run.bats:1017-1020`), and VS-16 cross-checks every suite rule id against took-effect.sh.
- The stub's `<unset>` marker makes the env assertion non-vacuous.

**Areas for Improvement:**
- Three hand-copied vocabularies (toggle values, toggle→config edits, component semantics) where one source of truth exists in a sibling library.
- The report side of FR-5 (how the new arms are read) has no test with data; the count-only assertions passed while the decision path is dead.

Complexity: no function over 50 lines added; nesting ≤ 3; the duplicated mappings are the only over-engineering — net: −12 lines possible by sourcing the library's vocabulary instead of copying it.

---

## Next Steps

1. Fix `primaries()` and add the review-only primary set to the suite rules; add a data-bearing report test for a review-catch-only component.
2. Decide a0_bare_fable's role (baseline vs component) and whether the new arms join `priority`; update the AR-12 constant and the suite comment at `:117` accordingly.
3. Reconcile the PR title with the diff, add the self-check evidence and an AC walkthrough to the report.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":5,"low":4},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T17:06:12Z"} -->
