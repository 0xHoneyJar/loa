# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)

---

## Overall Assessment

The change under review is sprint-262: `ablation-row.sh` 1.2 adds `defects_missed` and `regressions_final_green` to the row, and `ablation-report.py` 1.2.0 adds the suite_version partition, the H1/A4 read states and degradation guard, the degenerate single-task pair, the sensitivity H1/A4 lines, the batch record, per-arm precision and the budget-matched baseline. Five files are in scope (two programs, two bats files, one fixture generator).

What holds up. The row writer's two new fields and their `--validate` clauses behave exactly as the header documents: I ran the writer's jq fragment and the validator against every documented edge (string instead of list, empty-string id, mixed types, number instead of boolean, legacy rows without the keys) and each probe returned the documented result (`head/evals/harness/ablation-row.sh:165-170`, `:410-414`). All eleven fixture scenarios from the new `gen-fixtures.py` (including `present`, which AR-20 skips) pass the head validator. With a stand-in suite JSON (no `evals/suites/ablation-2.0.yaml` is in the PR) the head report builds every scenario, and 40 of 42 replayed assertions from AR-23 … AR-35 pass; the base and head reports agree on the `main` scenario's decisions and H1 intervals, so the presentation items do leave existing numbers alone (AR-35's claim). The refactor of `build()` into `render_*` helpers is a net readability gain.

What blocks. Two defects introduced by the report, both confirmed by running the head file: (1) the batch record's grader-version sort key mixes `int` and `str` list elements, so two grade.json files with differently shaped versions in one batch raise an uncaught `TypeError` and no report.md or report.json is written, in a section the header calls "never fatal"; (2) `version_key` does not normalise a string `"1.0"` and `version_order` ranks every non-digit key above every integer key, so a quoted suite_version becomes the primary over a higher integer version and splits from its own integer twin, contradicting the documented "highest present" default. The two adversarial voices (gpt-5.5-pro via codex-headless, claude-headless) raised the same two as BLOCKING; I reproduced both.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Robustness — the batch record aborts the whole report

- **HIGH** (confidence: high) `head/evals/harness/ablation-report.py:1081-1082` — the `grader_versions` sort key `[int(p) if p.isdigit() else p for p in re.split(r"[.]", kv[0])]` produces lists that mix `int` and `str` at the same position; comparing them raises `TypeError`, which is not a `Fail`, so `main()` (`:1673-1680`) does not catch it and neither `--out` nor `--json` is written.
**File:** `head/evals/harness/ablation-report.py:1081-1082`
**Issue:** Reproduced on the `present` fixture by adding one grade.json with `"grader_version": "1.2.0-rc1"` beside the planted `1.2.5` and `1.2.11`: `TypeError: '<' not supported between instances of 'str' and 'int'`, traceback, exit 1, no files written. The same happens with `"unknown"` beside `"1.2.5"`. Only two shapes that sort cleanly today are all-numeric dotted versions and the single `"n/a"` sentinel (its boolean prefix keeps it from reaching the list comparison).
**Why This Matters:** The header (`:135-141`) promises the batch record is informational and "a missing directory is counted, never fatal"; here a pre-release or free-form grader version string in any run directory kills the whole report, including the decisions and H1/A4 lines nothing in this section feeds. A real suite with a grader bumped to an `-rc` tag mid-batch is exactly the input this hits.
**Required Fix:** Use a type-stable key, e.g. `tuple((0, int(p)) if p.isdigit() else (1, p) for p in re.split(r"[.]", kv[0]))` with the `== "n/a"` prefix kept, and wrap the per-batch body of `batch_record()` so any exception becomes `status_note` rather than a crash. Add a fixture grade.json with a non-numeric segment to the `present` scenario and assert the report still writes.
**Reference:** CWE-754 (improper check for unusual or exceptional conditions); header contract at `:135-141`.

### 2. Correctness — a string suite_version wins the primary and splits its own version

- **HIGH** (confidence: medium) `head/evals/harness/ablation-report.py:825-840` — `version_key()` returns the string `"1.0"` verbatim (only `\d+` strings are normalised, `:833-834`) while the float `1.0` becomes `"1"`, and `version_order()` (`:839-840`) ranks every non-digit key `(1, 0, k)` above every integer key `(0, n, "")`, so `partition()`'s `max(groups, key=version_order)` (`:861`) picks a string version as the primary over a higher integer one.
**File:** `head/evals/harness/ablation-report.py:825-861`
**Issue:** Reproduced on the `versions` fixture. With the v1 rows' `suite_version` set to the string `"1.0"`: `primary_suite_version` is `"1.0"`, the main sections report the 132 older rows and version 2 is relegated to the "reported separately" section; the header line reads "suite_version 1.0 (primary: the main sections)". With a single row at `"1.0"` beside rows at integer `1`: three versions `["1","1.0","2"]`, primary `"1.0"` (one row), and any row then lacking `suite_version` exits 2 as "two versions present". `--suite-version 2.0` is refused with "no row has that suite_version (present: 1, 2)" while the row float `2.0` is accepted as version 2. The row validator admits `suite_version` as number or string (`head/evals/harness/ablation-row.sh:147`), and the row writer copies whatever type the manifest, pipeline.json or task yaml carries (`:376`), so a quoted value is an in-contract input. The docstring at `:826` claims the three spellings are one version.
**Why This Matters:** The whole point of the partition is that the main sections read the highest suite version and never pool; here a type difference in one provenance field silently inverts which version the Decisions, H1/A4, Exclusions and Cuts sections describe, and can split one version in two. Readers of report.json's top-level keys would act on the wrong version's H1.
**Required Fix:** In `version_key`, normalise numeric strings through `float(s)` and return `str(int(f))` when `f.is_integer()`; in `version_order`, rank non-numeric keys below numeric ones (or parse dotted versions to an int tuple) so a string key can never win the default; apply `version_key` to `--suite-version` the same way (it already is, so the first fix covers `2.0`). Add a fixture row with `"2.0"` beside `2` and assert one version and primary 2.
**Reference:** header contract `:56-65`; docstring `:826`.

---

## Observations

### 1. Security — the batch record follows a row's arm out of the batch directory

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-report.py:1054-1059` — `batch_record()` joins `r["arm"]` from every row of the batch, including listed rows whose arm is not a suite arm, onto the batch directory and lists it; the report never applies the arm grammar that `ablation-row.sh --validate` enforces.
**File:** `head/evals/harness/ablation-report.py:1054-1073`
**Suggestion:** Reproduced: a row with `"arm": "../../outside"` and a planted `outside/rc-01-t1/grade.json` made the batch record tally `{"LEAKED": 1}` from outside the manifest tree (the row itself was listed as "not run by the suite"). Restrict the tally to rows in `main.arm_rows` (or arms matching `^[a-z][a-z0-9_]{0,63}$`) and assert `os.path.realpath(ad)` stays under `os.path.realpath(d)`. Read-only and only `grader_version` is surfaced, hence MEDIUM.
**Benefit:** The batch record reads only what its header says it reads (CWE-22).

### 2. Testing — two new assertions depend on jq ≥ 1.7 number formatting

- **MEDIUM** (confidence: high) `head/evals/tests/ablation-report.bats:487` and `head/evals/tests/ablation-report.bats:498` — AR-33 expects `"1.0 2.222222 27 27"` and AR-34 expects `"1.0 3.0 0.875 10.0 -0.125 defect union"` from `jq -r` string interpolation; jq 1.6 prints `1`, `3`, `10` for those floats (jq 1.7 preserves the literal), so both tests fail on a jq 1.6 host while the report's numbers are right.
**File:** `head/evals/tests/ablation-report.bats:487,498`
**Suggestion:** On this host (jq 1.6) the replay gave `1 2.222222 27 27` and `1 3 0.875 10 -0.125 defect union`; no pre-existing test in the base file has an `x.0` expectation, so this dependence is new. Compare numerically (`.precision == 1`, `.a0_cost_sum == 3`) or format with a fixed precision.
**Benefit:** The suite passes wherever the shipped `ablation-row.sh` tests already pass.

### 3. Complexity — `batch_record()` is ~95 lines

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-report.py:992-1085` — one function reads STATUS.json, tallies five list fields, normalises `extra_models` and `paused_arms`, lists run directories and tallies grader versions, with nested `lst`/`tally` closures and a six-deep nesting at `:1070-1079`.
**Suggestion:** Split into `read_status(sp)` and `grader_tally(d, brows)`; the exception-to-`status_note` wrap from Changes Required #1 falls out naturally. Over-engineering pass otherwise: `budget_json`/`arms_json` could share one float-rounding helper; net: -10 lines possible.

### 4. Testing — AR-20 skips the `present` scenario

- **LOW** (confidence: high) `head/evals/tests/ablation-report.bats:290` — the `--validate` loop lists every new scenario except `present`, the only one that sets `false_positives = 0` and plants STATUS.json. I ran it: 90 rows valid, so it is a coverage gap only.
**Suggestion:** Add `present` to the loop.

### 5. Semantics — cuts apply to every suite version

- **LOW** (confidence: medium) `head/evals/harness/ablation-report.py:1181-1185` — `analyse()` passes the same `cuts` to each version's `arm_report`, so a cut pre-registered against one version's batch plan also marks the other version's section "Not run (cut)" (AR-30 asserts this on v1). The cuts file carries no version field, and the section text says "the same rules, cuts and seed", so it is documented; it just means a per-version cut cannot be expressed.
**Suggestion:** Either accept with a note in the header, or let a cuts row name an optional `suite_version`.

### 6. Semantics — a null `false_positives` yields precision 1.000

- **LOW** (confidence: high) `head/evals/harness/ablation-report.py:772-779` — `false_positives` null counts as 0 (documented at `:150`), so an arm whose review rows were never graded for false positives reports `precision 1.000` in both report.md and report.json (reproduced on `present` with a0_bare's `false_positives` nulled: precision 1, flagged regions 11).
**Suggestion:** Report `null` when no counted row carries a numeric `false_positives`, and say "n/a (no false-positive grading)" in the line.

### 7. JSON shape — `budget_matched` keys vary with availability

- **LOW** (confidence: high) `head/evals/harness/ablation-report.py:1013` — `a0_cost_sum_mean` is added only on the available path; the unavailable record lacks the key.
**Suggestion:** Initialise it to `None` in `out` at `:940-941`.

### 8. Wording — A4 without the arm still reads "fails"

- **LOW** (confidence: high) `head/evals/harness/ablation-report.py:928-929` — when `a4_no_gates` is not in the suite the JSON state is `"no_arm"` but the line keeps the base wording "fails — harden tasks before acting on other arms". Pre-existing text, new state field; the two now disagree.
**Suggestion:** "A4 sensitivity: no arm a4_no_gates in the suite — not decided".

---

## Cross-Model Observations

Two-voice dissent (`adversarial-review.json`: primary gpt-5.5-pro answered by codex-headless, companion claude-headless, both succeeded, `counted_as: independent_voice`). DISS-001 and DISS-C-002 (grader-version sort `TypeError`) and DISS-C-001 (`version_key`/`version_order`) are the two Changes Required above; DISS-C-004 (arm path traversal) is Observation 1. Two advisories did not reproduce and are not counted: DISS-C-003 (precision line omitted when `false_positives_per_task` is empty) — the dict has a key per review task even when every value is `None`, so the line prints whenever precision is computed; DISS-C-005 (`catch_task_score` returning `None` in `budget_matched`) — `_classify` (`:522-523`) marks a review row with a non-numeric `defect_catch_rate` "ungraded" unless it is a `cap_failure` (scored 0), so no valid cell reaches that code without a score.

## Rejected dissent payloads

None. The envelope's `metadata.rejected_summary` is empty and the listed sidecar `adversarial-rejected-review.jsonl` has zero rows.

---

## Previous Feedback Status

No previous `engineer-feedback.md` existed for sprint-1.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | Changes Required #1 and #2 above |

---

## Acceptance Criteria Check

### Task 1.1: review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict

| Criterion | Status | Notes |
|-----------|--------|-------|
| ablation-row.sh 1.2 carries `defects_missed` (bd-yz1rd) per the header contract | Pass | Writer fragment and validator probed on every documented edge (`head/evals/harness/ablation-row.sh:410-413`, `:165-168`); fixture rows of all eleven scenarios validate |
| ablation-row.sh 1.2 carries `regressions_final_green` (bd-m0hw7) per the header contract | Pass | `:414`, `:169-170`; boolean/null only, legacy rows without the key validate |
| Rows of different suite_version are never pooled; main sections read the highest present | Fail | Holds for integer/float values (AR-23 replayed); fails for a string `"1.0"` (Changes Required #2) |
| H1/A4 read states, degradation guard, degenerate pair | Pass | AR-25 … AR-30 replayed against the head report with a stand-in suite; `main` decisions and H1 intervals identical to the base report |
| Presentation items (sensitivity H1/A4, batch record, precision, budget-matched) change no decision and are never fatal | Fail | Numbers match AR-31 … AR-34; the batch record aborts the report on mixed grader-version shapes (Changes Required #1) |
| `reviewer.md` carries an `## AC Verification` walkthrough | Not met | The report is the PR description (commit list only); per `REVIEW-INSTRUCTIONS.md` the PR files are the entire input, so this is noted, not counted |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [ ] Input validation and sanitization present — the report trusts `arm` from runs.jsonl when building filesystem paths (Observation 1)
- [x] Authentication/authorization correct — n/a (local CLI)
- [x] No SQL/XSS injection vulnerabilities — markdown cells go through `md_cell`
- [x] Dependencies secure — stdlib only; `yq` for YAML suites, unchanged
- [x] Error messages don't leak sensitive data — a traceback on Changes Required #1 prints local paths only

---

## Code Quality Summary

**Strengths:**
- The row writer change is minimal, additive (schema_version stays 1), and the `--validate` clauses are exact to the header; the bats cases cover every documented shape.
- `build()` split into `analyse`/`render_*`/`*_json` helpers; per-version reporting reuses them without duplication.
- Fixture scenarios are self-describing (the gen-fixtures header lists each planted number) and AR-35 pins that the presentation items leave decisions untouched.

**Areas for Improvement:**
- Informational sections must not be able to abort the report (Changes Required #1; wrap or make type-stable).
- Normalise provenance values once at load time rather than at each use (Changes Required #2).
- Keep filesystem reads keyed by suite-validated arms, not raw row fields (Observation 1).
- Fast gate: no formatter or type-check run is recorded in the report; `py_compile` and `bash -n` pass on the head files, shellcheck was not available here.

---

## Next Steps

1. Fix Changes Required #1 and #2 with the fixture additions named there.
2. Re-run `evals/tests/ablation-report.bats` and `evals/tests/ablation-row.bats` (consider Observation 2 so they pass on jq 1.6 too).
3. Update the report in `grimoires/loa/a2a/sprint-1/reviewer.md` with an `## AC Verification` walkthrough.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":3,"low":5},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T17:25:11Z"} -->
