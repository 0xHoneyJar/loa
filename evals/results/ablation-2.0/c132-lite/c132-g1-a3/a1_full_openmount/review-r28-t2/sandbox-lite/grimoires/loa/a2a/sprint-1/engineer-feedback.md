# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)

---

## Overall Assessment

The change under review is `pr/head.diff`: four cycle-131 review-catch arms added to `evals/suites/ablation-2.0.yaml`, an `eval_only` refusal in `pipeline-run.sh` keyed on `LOA_ABLATION_BATCH_CONTEXT=1` (exported per trial by `run-ablation.sh`), a dry-run `sandbox:` plan line, validate-suite check 8 (toggle vocabulary, took-effect rule ids, `eval_only` boolean, `oracle_open ⇒ eval_only`), and the report's exclusion of `eval_only` arms from `components`, with bats coverage for each.

The shell side is sound: the refusal sits before the run directory is created (`head/evals/harness/pipeline-run.sh:259` precedes `mkdir -p "$RUN_DIR"` at `:356`), only the exact value `1` opens it, `run-ablation.sh` sets the variable on the trial command only (`head/evals/harness/run-ablation.sh:1300-1301`), both `--help`/`usage()` sed ranges still end on the line they ended on before, the validator's type-exact value check correctly rejects `gates: 0`, and every rule id the committed suite names is asserted against `took-effect.sh` by VS-16.

The report side is not ready. Adding three review-catch-only arms as **components** and one `eval_only` arm that is in the suite but excluded from every rendered table changes what `ablation-report.py` produces in two ways that no test catches: (1) the new components can never reach `remove` or `simplify`, because the pass-rate primary they are assigned has no build rows to pair; (2) the open-mount arm's rows are consumed by the analysis but surface nowhere. Both are confirmed independently by the cross-model dissent (its DISS-001 and DISS-002). A reviewer reading the Decisions table would see A1R and A1N stuck on "inconclusive: no valid pair (hidden_test_pass_rate)" after a full, clean batch.

Scope note: the PR title promises "the cycle-131 suite root (bounds 50/40) with its image self-check"; no file under `grimoires/loa/evals/` is in the diff (the new RAB-c131-5 test copies the pre-existing root). Either the title overstates the change or a deliverable is missing; see Incomplete Tasks.

Verification limits: the workspace holds only the eleven touched files. `lib/sandbox-mount.sh`, `took-effect.sh`, `freeze.sh`, the bats fixtures (`fixtures/ablation-runs/suite.yaml`, `fixtures/ablation-report/gen-fixtures.py`, `fixtures/ablation/suite-lib.bash`) and the suite root are absent, so **no test was executed** and parity claims against those siblings are read from the code, not run. `[ASSUMPTION]` statements below are marked.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Functionality — review-catch-only components are structurally undecidable

- **HIGH** (confidence: high) `head/evals/harness/ablation-report.py:1913` — the three new review-catch-only arms (`a0_bare_fable`, `a1_review_only`, `a1_no_dissent`) become `components`, but `Analysis.primaries()` (`head/evals/harness/ablation-report.py:653-657`) gives any arm whose `task_types` contains `review-catch` BOTH primaries, and `decide()` (`:845-887`) requires every primary to be `usable` (`p["n"] > 0`, `:800`) before it can return `remove` or `simplify`; `compare(arm, a1_full, hidden_test_pass_rate)` for an arm that runs no build task yields zero pairs every time, so these components can only ever read `investigate`, `keep` or `inconclusive`.
**File:** `head/evals/harness/ablation-report.py:1913` (components), `:653-657` (primaries), `:845-887` (decide)
**Issue:** `primaries_by_arm` has a `build_only` branch for the mirror case (a2/a4/a5/a6 get `[hidden_test_pass_rate]` only) but no `review_only` branch; the `"all" in types or REVIEW in types` test treats a review-catch-only arm like an all-types arm. For A1R/A1N the whole point of the ablation is to learn whether the AUDIT gate / the dissent can be dropped, and the two outcomes that would say so are unreachable: after a complete, clean batch the decision row reads `inconclusive: no valid pair (hidden_test_pass_rate: …)`.
**Why This Matters:** a pre-registered decision procedure that cannot emit two of its five outcomes for three of nine components silently biases the cycle-131 results toward "inconclusive" and wastes the review-catch budget spent on those arms (up to USD 20 × 4 tasks × 3 trials per arm). `GOAL-DRIVEN:` no test asserts the decision state of any new component (the `c131`/`c131-mixed` scenarios are only checked for exclusions and pins at `head/evals/tests/ablation-report.bats:797-813`); AR-12/AR at `:189` and `:342` only count them.
**Required Fix:** make `primaries()` return `[defect_catch_rate]` for an arm whose `task_types` is exactly `[review-catch]` (add `review_only: [defect_catch_rate]` to `rules.primaries_by_arm` in the suite and read it, mirroring `build_only`), and add a fixture scenario in which a review-catch-only component with equal catch rate and ≥15 % lower cost reads `remove`. Alternatively, if these arms are meant to be evaluation controls rather than decisions (the suite comment at `head/evals/suites/ablation-2.0.yaml:94-97` calls them "review-catch only" controls), exclude them from `components` like `a1_full_openmount` and render them in the per-arm detail instead.

### 2. Functionality — the eval_only arm's rows are reported nowhere

- **HIGH** (confidence: high) `head/evals/harness/ablation-report.py:1913` — `a1_full_openmount` is declared in the suite and not `absent`, so `list_reason()` (`:1108-1123`) returns `None` for its rows and they enter `arm_rows`/`cells`; yet the arm is excluded from `components` (`:1913`) and therefore from `detail_arms = [BARE, CONTROL] + components` (`:2003`), so it appears in no Decisions row, no Per-arm detail, no "listed (not decided)" entry and not in `report.json .arms`. A completed batch that ran the oracle A/B produces a report with no open-mount figures at all.
**File:** `head/evals/harness/ablation-report.py:1913`, `:2003`
**Issue:** before this change every suite arm was either a component, a baseline, or listed-with-reason; the new `eval_only` class is none of the three. The arm's rows still count in the per-version row total (`rows=vrows`, `:1696`; the `… 24 rows` line asserted at `head/evals/tests/ablation-report.bats:343`), so the totals no longer reconcile with the tables beneath them. The suite header (`head/evals/suites/ablation-2.0.yaml:32-34`) says only that the arm is "never a decision arm", not that it is invisible.
**Why This Matters:** the arm exists to measure what the closed-mount overlay costs (cycle-131 FR-5, "the open-mount oracle A/B"); with this change its results can be bought but not read. Rows the report silently swallows are also the class of defect the "Row treatment" contract (`:117-127`) was written to prevent.
**Required Fix:** either add `eval_only` arms to `detail_arms` (and to `arms_json`) under a clearly labelled "evaluation controls (never decided)" subsection with the catch-rate comparison against `a1_full`, or have `list_reason()` list them (`"eval_only arm <id>: reported, never decided"`) so the row accounting closes; add a fixture row set for `a1_full_openmount` and assert where it lands.

---

## Observations

### 1. Statistics — a bare baseline counted as a removable component; the pre-registered k

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-report.py:1913` — `a0_bare_fable` is "A0 on the review model" (`head/evals/suites/ablation-2.0.yaml:94`), a baseline variant with `loa_mount: false`, yet it is now a component: `arm_report()` compares it with `a1_full` and `decide()` can print `keep`/`remove`/`simplify` for "component a0_bare_fable", which has no meaning (there is nothing to remove), and it inflates `k` in the expected-false-positive sentence to 9 (`:1927-1931`). The dissent's companion voice adds that no component is now tested on the same primary set: per primary the comparison count is 6 (pass rate) and 5 (catch rate), so "9 components" overstates exposure on either metric. The rules block is pre-registered and "mirrored in NOTES" (`head/evals/suites/ablation-2.0.yaml:109`), and its own comment still says "over 6 components" (`:117`).
**File:** `head/evals/harness/ablation-report.py:1913`, `:1927-1931`; `head/evals/suites/ablation-2.0.yaml:117`
**Suggestion:** treat `a0_bare_fable` like `BARE` (exclude from components, include in `detail_arms`), or document in a DEC why a second bare arm is a decision; update the `multiple_comparisons` comment and the NOTES mirror to the new k, or print k per primary.
**Benefit:** the Decisions table and the pre-registration agree, and no reader acts on a "remove" verdict for a baseline.

### 2. Simplicity — the toggle→config mapping now lives in three places

- **MEDIUM** (confidence: medium) `head/evals/harness/pipeline-run.sh:341-345` — the dry-run re-derives in jq which `.loa.config.yaml` keys `apply_arm_toggles` edits for `companion_voice`, `gates`, `dissent`, `flatline`; `validate-suite.sh` carries the toggle vocabulary a third time (`head/evals/harness/validate-suite.sh:137-139`). Nothing checks either copy against `lib/sandbox-mount.sh`: the dry-run tests at `head/evals/tests/pipeline-run.bats:1197-1215` assert the jq's own output. When the library gains or renames a toggle (as this very PR did for `dissent`/`bare_model`/`oracle_open`), the dry run and the validator drift silently. `[ASSUMPTION]` the mapping matches `apply_arm_toggles` today; the library is not in the workspace.
**File:** `head/evals/harness/pipeline-run.sh:341-345`; `head/evals/harness/validate-suite.sh:137-139`
**Suggestion:** `SIMPLICITY[shrink]:` have `lib/sandbox-mount.sh` export the vocabulary and the key list (a function that prints them), and have both `pipeline-run.sh --dry-run` and `validate-suite.sh` read it; or at minimum add one test that diffs the three copies. `net: -12 lines possible`.
**Benefit:** one source of truth for what an arm toggles.

### 3. Tests — a pre-existing test now appends a duplicate arm id

- **LOW** (confidence: high) `head/evals/tests/run-ablation.bats:1173-1175` — RAB-c131-4 copies the committed suite and appends `a0_bare_fable`; the committed suite now declares that id (`head/evals/suites/ablation-2.0.yaml:98`), so the copy holds two arms with the same id. `run-ablation.sh` resolves `[.arms[] | select(.id == $a)][0]` (`head/evals/harness/run-ablation.sh:576`) and `took-effect.sh` reads its own definition, so the appended definition (two rules, `task_types [review-catch]`) is dead and the test exercises a suite `validate-suite.sh` never sees in production (check 8 has no duplicate-id rule). The PR's own RAB-c131-5 sits directly below and did not update it.
**File:** `head/evals/tests/run-ablation.bats:1173-1175`
**Suggestion:** drop the `yq -i '.arms += …'` and run RAB-c131-4 against the committed suite, which is what the test's title now describes.
**Benefit:** the test asserts the shipped arm, not a shadow of it.

### 4. Documentation — the pre-registered rules comment is stale

- **LOW** (confidence: high) `head/evals/suites/ablation-2.0.yaml:117` — `multiple_comparisons: none  # expected false positives at 0.90 over 6 components printed` — the report now prints 9 (AR-12 asserts it, `head/evals/tests/ablation-report.bats:189`). Covered by Observation 1's fix; cited separately because the comment is the pre-registration record.

### 5. Validation — `took_effect` is now mandatory on every non-absent arm

- **LOW** (confidence: medium) `head/evals/harness/validate-suite.sh:171-172` — before this change the validator did not read `took_effect` at all; now a missing key is a violation ("must be a list of rule ids"). Every committed arm carries it, and DEC-0418 implies it should, but the header text for check 8 (`:46-53`) says "is a list" rather than "is required", and any operator or fixture suite without it (a `--suite-file` copy that drops the key) now fails freeze/validation with no hint that the key is required. Confirm the requirement is intended and say so in the header; if a `took_effect: []` arm is legal, say that too.

### 6. Robustness — refusal ordering for callers that iterate every arm

- **LOW** (confidence: low) `head/evals/harness/pipeline-run.sh:258-262` — the `eval_only` refusal runs before the applicability `REFUSAL` is reported and before `--dry-run`; the only launcher that sets the marker is `run_trial` (`head/evals/harness/run-ablation.sh:1300-1301`). An `eval_only` arm asked for an inapplicable task type outside a batch reports the eval_only reason rather than the task-type reason, and (per the dissent's companion voice) any future tool that dry-runs "every runnable arm" — a cost pre-flight, an image self-check — exits 2 on `a1_full_openmount` with no `pipeline.json`. Nothing in this diff does so (`run-ablation.sh --dry-run` never calls `pipeline-run.sh`; verified by grep), so this is a design note: consider letting `--dry-run` through unconditionally and refusing only a real run.

---

## Rejected dissent payloads

None. The envelope's `metadata.rejected_summary` is empty and the listed sidecar `adversarial-rejected-review.jsonl` holds zero rows; the companion voice (`claude-headless`, counted as an independent voice) rejected none either.

## Cross-Model Observations

The dissent (`gpt-5.5-pro` primary, `claude-headless` companion) returned four ADVISORY findings, none counted:

- DISS-001 and DISS-002 (gpt-5.5-pro) restate Changes Required 1 and 2 independently: review-catch-only components cannot reach `remove`/`simplify`; the open-mount control is reported nowhere.
- DISS-C-001 (claude-headless): the per-primary comparison counts are 6 / 5, not 9; folded into Observation 1.
- DISS-C-002 (claude-headless): callers that iterate every arm through `pipeline-run.sh` hit the eval_only refusal; folded into Observation 6 (speculative — no such caller exists in the diff).

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| PR title: "the cycle-131 suite root (bounds 50/40) with its image self-check" | Not in the diff | No file under `grimoires/loa/evals/` is touched; `head/evals/tests/run-ablation.bats:1196` copies the pre-existing `ablation-2.0` root. Either trim the title or add the deliverable. |

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| eval_only arm refused outside a batch, before any run-dir write (FR-5) | Pass | `head/evals/harness/pipeline-run.sh:258-262` precedes `:356`; exact-value `1` test; dry run included; bats at `pipeline-run.bats:1217-1250` |
| run-ablation exports the marker to every trial, batch and smoke, without exporting to its own shell | Pass | `head/evals/harness/run-ablation.sh:1300-1301`; RAB-c131-5 asserts both paths and the stub's `<unset>` control |
| validate-suite check 8: toggle vocabulary and values, took-effect rule ids from `took-effect.sh`, `eval_only` boolean, `oracle_open ⇒ eval_only` | Pass | `head/evals/harness/validate-suite.sh:85-88`, `:137-139`, `:157-180`; VS-14..17. `[ASSUMPTION]` `rule_<id>() {` is the only definition style in `took-effect.sh` |
| dry-run prints the sandbox plan | Pass (with Observation 2) | `head/evals/harness/pipeline-run.sh:332-348` |
| the four arms declared with the right toggles/phases/took_effect, absent arm last | Pass | `head/evals/suites/ablation-2.0.yaml:98-105`; AT-13 |
| the report treats the new arms correctly | **Fail** | Changes Required 1 and 2; Observation 1 |
| self-checks / fast gate (shellcheck, bats) | Not evidenced | `pr/PR.md` carries no `## AC Verification`, no test run; the workspace cannot run bats (siblings absent). `FAST-GATE:` unrun |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [x] Input validation at the trust boundary present (suite schema check 8 is type-exact; `python3 -I`; `LOA_ABLATION_BATCH_CONTEXT` compared to the literal `1`)
- [x] Authentication/authorization — n/a
- [x] No injection vectors introduced (`RULE_IDS` passed as a single argv to Python; arm ids reach `printf` quoted; `load(strenv(…))` in tests only)
- [x] Dependencies — none added
- [x] Error messages don't leak sensitive data

---

## Code Quality Summary

**Strengths:**
- The refusal is placed exactly where its comment says (before any side effect), tested for the exact-value rule and for both launch paths, and the stub proves the assertion is not vacuous.
- `c131_arms()` now loads the committed arms instead of a hand-copied shape, so the pipeline tests cannot drift from the suite.
- Check 8 is type-exact (`0` is not `false`) and reads rule ids from the script that defines them rather than a hard-coded list.

**Areas for Improvement:**
- The report was not adapted to the new arm classes (Changes Required 1–2) and no test asserts a decision outcome for them.
- Three copies of the toggle vocabulary (Observation 2).
- A pre-existing test left stale by the suite change (Observation 3).

**Complexity:** no function over the thresholds was added; the dry-run jq block is 5 lines. `net: -12 lines possible` (Observation 2).

---

## Next Steps

1. Fix Changes Required 1 and 2 in `ablation-report.py` (and the suite's `primaries_by_arm` if the `review_only` route is taken), with fixture scenarios that assert the decision state of a review-catch-only component and where `a1_full_openmount` rows land.
2. Decide and document `a0_bare_fable`'s role (component vs baseline); update the `multiple_comparisons` comment and the NOTES mirror.
3. Run the bats suites (`pipeline-run`, `run-ablation`, `validate-suite`, `ablation-report`, `arm-toggles`) and record the results in the implementation report.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":2,"low":4},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T00:55:00Z"} -->
