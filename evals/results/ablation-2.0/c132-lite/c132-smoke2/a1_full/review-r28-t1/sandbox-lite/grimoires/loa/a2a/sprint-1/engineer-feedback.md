# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)

---

## Overall Assessment

The change under review is `pr/head.diff`: sprint-264 of cycle-131 — four review-catch arms added to `evals/suites/ablation-2.0.yaml`, an `eval_only` refusal in `pipeline-run.sh` gated on `LOA_ABLATION_BATCH_CONTEXT=1` (exported per trial by `run-ablation.sh`), a new arm-schema check (toggles vocabulary, took-effect rule ids, `eval_only`) in `validate-suite.sh`, the `eval_only` exclusion from report components in `ablation-report.py`, and tests for each.

The harness plumbing is sound. I verified in the head files that: the `eval_only` refusal sits after arm resolution and before `mkdir -p "$RUN_DIR"` (`pipeline-run.sh:256-262` vs `:356`), so the "no pipeline.json" claim holds; `run_trial` is the only launch site in `run-ablation.sh` (`:1652`) so batch and smoke both carry the variable; the `--help` range `2,156p` and the validate-suite usage range `2,55p` both stop one line before the header's closing rule; the dry-run `config_edits` jq matches the sandbox-config assertions the existing a1_no_dissent run test makes (`pipeline-run.bats:1100-1101`); the `.2f` change in the expected-false-positive line is required for `9 × 0.10 / 2 = 0.45`.

The defects are in the analysis layer, where the new arms meet unchanged report code. The three review-catch-only arms are admitted as components but the report still demands a `hidden_test_pass_rate` pair from them, which they can never have: their decisions are permanently "inconclusive" and never decidable. The `eval_only` arm's valid rows are neither decided, listed nor rendered, so the open-mount A/B the arm exists for is never surfaced. Both are introduced by this PR (the suite had no review-catch-only arm before; the PR's own tests pin the new arms as components) and both were independently flagged by both dissent voices.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Functionality — review-catch-only components can never reach a null decision

- **HIGH** (confidence: high) `head/evals/suites/ablation-2.0.yaml:98-103` — a0_bare_fable, a1_review_only and a1_no_dissent are `task_types: [review-catch]` and are counted as components (`head/evals/harness/ablation-report.py:1913`), but `primaries()` (`head/evals/harness/ablation-report.py:653-658`) returns `[hidden_test_pass_rate, defect_catch_rate]` for any arm whose task_types contains `review-catch`. `compare(arm, a1_full, hidden_test_pass_rate)` collects the control's build tasks (`:733`), finds no arm cell for any of them, and emits only `unpaired` entries ("no row in <arm>"); `n` stays 0 so `usable(p)` (`:577-579`) is false and `decide()` (`:846-877`) sets `nopair`. Unless `defect_catch_rate` alone fires `investigate` or `keep`, the arm reads `inconclusive: no valid pair (hidden_test_pass_rate)`; `remove` and `simplify` (`:878-887`) are unreachable and `out["decidable"]` (`:922`) is always False.
**File:** `head/evals/suites/ablation-2.0.yaml:98-103`, `head/evals/harness/ablation-report.py:653-658`, `head/evals/harness/ablation-report.py:1913`
**Issue:** The purpose of a1_no_dissent and a1_review_only is to decide whether the review gate's dissent (and the AUDIT gate) can be dropped on review-catch work. A null result ("dissent does not matter" → remove/simplify) is exactly the outcome these arms exist to detect, and the report can never produce it for them. The expected-false-positive line (`:1927-1931`) also counts them in `k = 9` as if they were decidable tests. The PR's tests pin the broken behaviour (`head/evals/tests/ablation-report.bats:189` asserts 9 components; `:342` asserts 9 decisions) without any assertion on the predicate state of a review-catch-only arm.
**Why This Matters:** Every batch spends review-catch trials on three arms whose Decisions rows are structurally fixed at "Inconclusive". Pre-registered rules (`rules.predicates`, `head/evals/suites/ablation-2.0.yaml:119-124`) are evaluated on a primary the arm cannot have; the report misreads "no data on an inapplicable metric" as "insufficient evidence".
**Required Fix:** Derive primaries from applicability: an arm whose task_types is review-catch-only gets `[defect_catch_rate]`; `all` keeps both; build-only keeps `[hidden_test_pass_rate]`. Add a `review_only` key beside `build_only`/`all_types` in `rules.primaries_by_arm` so the pre-registration names it. Add a bats case that feeds valid review-catch rows for a1_no_dissent equal to a1_full and asserts the decision is `simplify`/`remove` with `decidable: true`, and that `primaries` for the arm is `[defect_catch_rate]`.
**Reference:** `head/evals/harness/ablation-report.py:1201-1218` already has a `not_testable` notion for H1/A4 — component decisions need the equivalent.

**Example:**
```python
# Current (ablation-report.py:653-658)
if "all" in types or REVIEW in types:
    return list(pba.get("all_types") or [PASS, CATCH])
return list(pba.get("build_only") or [PASS])

# Should be
if "all" in types:
    return list(pba.get("all_types") or [PASS, CATCH])
if REVIEW in types and not any(t in types for t in ("build", *BUILD_TYPES)):
    return list(pba.get("review_only") or [CATCH])
if REVIEW in types:
    return list(pba.get("all_types") or [PASS, CATCH])
return list(pba.get("build_only") or [PASS])
```

### 2. Functionality — the eval_only arm's valid rows vanish from the report

- **HIGH** (confidence: medium) `head/evals/harness/ablation-report.py:1913` — excluding a1_full_openmount from `components` also drops it from `detail_arms = [BARE, CONTROL] + components` (`:2003`) and from `decisions`; it is not CONTROL/BARE and not `absent`, and `list_reason()` (`:1108-1123`) returns None for it (declared arm, applies to review-catch), so its rows enter cells (`:660-690`) and are never surfaced. Only its excluded rows appear, in the Exclusions table (`:1806-1814`). Valid rows are in no section of report.md and no key of report.json.
**File:** `head/evals/harness/ablation-report.py:1913`, `head/evals/harness/ablation-report.py:2003`
**Issue:** The PR's own comment (`:1911-1912`) calls the arm "the open-mount oracle A/B … an evaluation control". After this change the A/B (a1_full_openmount vs a1_full on defect_catch_rate) is computed nowhere, and the report's row-treatment contract (`:116-128`: every row is decided, excluded pairwise, or listed with a reason) is violated silently for an entire arm. Confidence is medium only because a dedicated "evaluation controls" section may be a later sprint's deliverable; the silent drop is a defect regardless.
**Why This Matters:** Operators pay for review-catch trials on the open-mount arm and receive no figure; a reader of the report cannot tell the arm ran. Dropped rows with no listing reason is the failure class the `listed`/`exclusions` design exists to prevent.
**Required Fix:** Give `eval_only` arms an explicit rendering path that is not a decision: either (a) an "Evaluation controls" section and JSON key reporting `defect_catch_rate` of the arm against CONTROL with its interval and a `decision: none (eval_only)` label, excluded from `decisions`, from `k`, and from `decidable`; or (b) at minimum, list its rows under "Rows listed, never decided" with reason `eval_only arm` so nothing disappears. Add a bats case with valid a1_full_openmount rows asserting where they appear.
**Reference:** `head/evals/harness/ablation-report.py:98` ("arm not run, unknown or inapplicable task type … is listed") — the listing contract.

---

## Observations

### 1. Statistics — a bare baseline counted as a component

- **MEDIUM** (confidence: medium) `head/evals/suites/ablation-2.0.yaml:98` — a0_bare_fable is a baseline (no mount, bare model; "A0 on the review model" per `:94-95`), yet `head/evals/harness/ablation-report.py:1913` treats it as a component whose decision vocabulary is keep/remove/simplify relative to a1_full, and it inflates `k` in the expected-false-positive line. "Remove"/"simplify" a baseline is not a meaningful decision; the analogous comparison for a0_bare is H1, not a Decisions row.
**Suggestion:** Mark baseline arms explicitly (e.g. `role: baseline`, or extend the BARE exclusion to any arm with `toggles.loa_mount == false`) and render an H1-style line for it instead of a component row. Then update `head/evals/tests/ablation-report.bats:189,342` from 9 to the real component count.
**Benefit:** Decisions table and error-budget sentence describe only real ablation tests.

### 2. Documentation — stale component count in the pre-registered rules block

- **LOW** (confidence: high) `head/evals/suites/ablation-2.0.yaml:117` — `# expected false positives at 0.90 over 6 components printed` while the report now prints 9 (`head/evals/tests/ablation-report.bats:189`); the Method section quotes this rules block verbatim (AR-12), so the report contradicts itself.
**Suggestion:** Update the comment or drop the hard-coded number from the rules text.
**Benefit:** The pre-registration and the computed sentence agree.

### 3. Maintainability — toggle vocabulary and config-edit mapping are hand copies of the mount library

- **LOW** (confidence: medium) `head/evals/harness/validate-suite.sh:137-139` — `TOGGLE_VALUES` duplicates `lib/sandbox-mount.sh apply_arm_toggles`' vocabulary by hand (the header `:45-49` claims it is "the vocabulary of lib/sandbox-mount.sh"), while `RULE_IDS` (`:87`) is correctly read from `took-effect.sh`. The dry-run `config_edits` jq in `head/evals/harness/pipeline-run.sh:337-341` duplicates the toggle→config-edit mapping the same way. No test pins either copy to the lib; the new bats cases compare against literal strings.
**Suggestion:** Export the vocabulary and edit map from `lib/sandbox-mount.sh` (validate-suite already sources it) and consume them in both places, or add a parity test that diff-checks them.
**Benefit:** A toggle added or renamed in the lib cannot be silently rejected by the validator or omitted from the dry-run plan.

### 4. Verification gap — took-effect rule ids are validated against a file this PR does not touch

- **LOW** (confidence: low) `head/evals/harness/validate-suite.sh:87` — the committed suite now names five rule ids (`oracle_closed`, `oracle_open_recorded`, `bare_model_fable`, `review_only_phases`, `no_review_dissent_envelope`) that must exist as single-line `rule_<id>() {` definitions in `took-effect.sh`, which is not in `pr/base` or `pr/head`. [ASSUMPTION] Sprint 263 defined them in that shape; I could not verify (VS-14/VS-16 would fail otherwise). The sed shape also silently drops `function rule_x` or brace-on-next-line definitions.
**Suggestion:** Confirm the five functions exist in the merge target; consider a `--list-rules` mode in `took-effect.sh` instead of parsing its source.
**Benefit:** Validator correctness does not depend on function-definition style.

### 5. Validator — arm-level `effort` and `phases` remain unchecked

- **LOW** (confidence: medium) `head/evals/harness/validate-suite.sh:157-180` — check 8 validates `toggles.effort` but not the arm-level `effort:` key that a0_bare_fable uses (`head/evals/suites/ablation-2.0.yaml:98`), nor `phases`. A typo there passes the validator and makes every trial of the arm exit 2 at `head/evals/harness/pipeline-run.sh:313` before a run dir exists, which `run-ablation.sh` synthesises as interrupted rows. Pre-existing gap, but the PR adds the arm schema and leaves it.
**Suggestion:** Validate `effort` against the same enum and `phases` against the suite's phase names in the same block.
**Benefit:** Suite typos are caught at validation, not as a batch of interrupted trials.

### 6. Process — PR description claims deliverables the diff does not contain; no AC verification

- **MEDIUM** (confidence: high) `grimoires/loa/a2a/sprint-1/reviewer.md:3` — the title promises "the cycle-131 suite root (bounds 50/40) with its image self-check"; the diff holds no suite root, bounds or self-check artefact (11 files, all under `evals/`). The report has no `## AC Verification` section and does not state that `bats evals/tests/*.bats` or `shellcheck` ran (FAST-GATE: unverifiable here — the `evals/` tree outside the PR files is not present in this workspace, so I could not execute the suites). Per the review instructions for this frozen PR, the missing sections are noted, not counted.
**Suggestion:** Either add the suite-root files to the PR or trim the title; add the AC walkthrough and the test-run evidence to the report.
**Benefit:** Reviewers and the audit gate can trace what shipped.

---

## Cross-Model Observations

Adversarial review ran with two voices (`grimoires/loa/a2a/sprint-1/adversarial-review.json`: primary gpt-5.5-pro answered by codex-headless, companion claude-headless; `counted_as: independent_voice`, consensus). Both voices independently raised Changes Required 1 and 2 as BLOCKING (DISS-001/DISS-C-001 and DISS-002/DISS-C-002); the companion's advisory findings DISS-C-003..006 correspond to Observations 1–4 above. No finding was dropped.

## Rejected dissent payloads

- none — `metadata.rejected_summary` is empty and `adversarial-rejected-review.jsonl` has zero rows.

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| "review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict" | Done | Two HIGH defects introduced (Changes Required 1–2); six non-blocking observations; verdict below |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [x] Input validation at trust boundaries present — `validate-suite.sh` check 8 is type-exact (`0` is not `false`); `eval_only` JSON parse is literal-true
- [x] `LOA_ABLATION_BATCH_CONTEXT` is an operator guard against accidental runs, not a security boundary — correctly documented as such
- [x] No injection surface: arm ids are interpolated into messages only; jq uses `--arg`
- [x] Error messages name the arm and reason, leak nothing sensitive

---

## Complexity Review

No function added or grown past 50 lines; nesting ≤ 3; the validator block is one loop. Lean already. Ship.

## Code Quality Summary

**Strengths:**
- The refusal is placed before any side effect and the header documents the exit contract; tests cover exact-value semantics (`0`, `yes`, `true`, `""` all refused) and the no-run-dir claim.
- `RULE_IDS` is read from the defining script rather than copied.
- Test fixtures now load the committed arms (`c131_arms`) instead of a hand-written shadow.

**Areas for Improvement:**
- The analysis layer was not re-checked against the new arm shape (review-catch-only); the tests pin counts rather than predicate states.
- Hand-copied vocabularies in two scripts.

---

## Next Steps

1. Fix `primaries()` for review-catch-only arms and give `eval_only` arms a reporting path (Changes Required 1–2), with bats cases asserting predicate state and row placement.
2. Decide the a0_bare_fable role (Observation 1) and correct the component count in the tests and the rules comment.
3. Update the report in `grimoires/loa/a2a/sprint-1/reviewer.md` with an AC walkthrough and test-run evidence.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":2,"low":4},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T12:12:00Z"} -->
