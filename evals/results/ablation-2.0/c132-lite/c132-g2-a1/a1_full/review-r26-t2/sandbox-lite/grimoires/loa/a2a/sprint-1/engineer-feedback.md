# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)

---

## Overall Assessment

The change under review is `pr/head.diff`: row writer 1.2 (`defects_missed`, `regressions_final_green`) in `ablation-row.sh`, and `ablation-report.py` 1.2.0 (the suite_version partition, the not-testable / not-yet-decidable / degenerate reads, the degradation guard on the H1 and A4 lines, and four presentation items: sensitivity H1/A4 lines, batch record, precision, budget-matched baseline), with the bats tests and the fixture generator.

The decision-bearing logic is sound and well tested. The row writer additions are correct and defensively typed in jq (`defects_missed` only on review-catch rows with an object `recall`, `regressions_final_green` only a boolean, both optional under `--validate`); the fixture generator's planted numbers agree with every assertion in AR-23 … AR-35 that I recomputed by hand (catch d = 8/18 = +0.444444, precision 11/17, a0 union 1.000 vs 0.875, note "3 a0_bare trials cost USD 3.00 vs one a1_full trial USD 10.00"). `usable()` threads the degenerate flag through `decide()`, `arm_report().decidable` and the H1/A4 reads consistently; the "Rows per cell" section and the exit code still read the primary version only, as the header says. `f3`/`u3` handle None (head L214-219), so the budget table's one-arm rows render "n/a" rather than crashing.

One defect blocks: the new batch-record section — documented as "a missing file or directory is reported, never fatal" — crashes the whole report (no report.md, no JSON) on a plain `grader_version` string such as `1.2.11-rc1` or `dev` beside a numeric one, because the markdown sort key compares `int` and `str` list elements. I reproduced the TypeError with the exact key expression; both dissent voices found it independently. It is a one-line fix. Three medium findings (a double-counted rerun directory, the `"1.0"` / `1` partition split with `"2.0"` becoming the primary, and the degradation guard firing on a zero-pair primary) and six low ones follow.

Not verifiable here: the bats suites could not be executed (the real suite `evals/suites/ablation-2.0.yaml` and the `fixtures/ablation-runs/` tree are outside `pr/`), so test results rest on reading the assertions against the generator; no CI / formatter / type-check record was supplied, so fast-gate parity is unverified (FAST-GATE: no evidence either way); CHANGELOG and README entries named in the commit list are outside the five files in scope. `reviewer.md` is the PR description and carries no `## AC Verification` walkthrough; the task brief defines the sprint as the PR itself and the eval instructions say to skip pre-flight steps that need the missing artifacts, so I note the gap without counting it.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Functionality — the batch record can abort the whole report

- **HIGH** (confidence: high) `head/evals/harness/ablation-report.py:1082` — `batch_record()` sorts `grader_versions` with the key `(kv[0] == "n/a", [int(p) if p.isdigit() else p for p in re.split(r"[.]", kv[0])])`; when two `grade.json` files in one batch carry versions whose parts differ in kind at the same position (`"1.2.11"` beside `"1.2.11-rc1"` → `[1, 2, 11]` vs `[1, 2, "11-rc1"]`; `"1.3"` beside `"dev"`), `sorted()` raises `TypeError: '<' not supported between instances of 'str' and 'int'`.
**File:** `head/evals/harness/ablation-report.py:1081-1082`
**Issue:** `grader_version` is a free-form string read from disk and validated nowhere in this script. The exception is not a `Fail`, so `main()` (L1673-1680) does not catch it: the run dies with a traceback and neither `report.md` nor the `--json` twin is written. The header (L136-139) promises the batch record is "reported, never fatal", and the section is presentation-only — it must not be able to take the decision report down. Reproduced with the key expression copied from L1081-1082:
```
import re
gv = {"1.2.13": 2, "1.2.13-rc1": 1, "n/a": 1}
sorted(gv.items(), key=lambda kv: (kv[0] == "n/a", [int(p) if p.isdigit() else p for p in re.split(r"[.]", kv[0])]))
# TypeError: '<' not supported between instances of 'str' and 'int'
```
**Why This Matters:** A single pre-release or hand-labelled grader on one run directory blocks the pre-registered decision report for the whole batch set; the "never fatal" contract of the section is broken.
**Required Fix:** Use a type-homogeneous key, e.g. `[(0, int(p)) if p.isdigit() else (1, p) for p in …]`, and add a fixture directory with a non-numeric `grader_version` to AR-32 so the tally renders (`1.2.11 ×1, 1.2.11-rc1 ×1`) rather than aborting. Optionally guard the whole `batch_record()` call so any exception degrades to a `status_note` instead of propagating.
**Reference:** CWE-754 (improper check for unusual or exceptional conditions); dissent DISS-001 (gpt-5.5-pro) and DISS-C-001 (claude-headless), both BLOCKING.

---

## Observations

### 1. Batch record — rerun directories double-count

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-report.py:1065` — the run-directory match keeps only `group(1) == task_id` and `int(group(2)) == trial` and ignores the `-r<k>` suffix, so a row for (task, trial n) matches `<task>-t<n>` **and** every `<task>-t<n>-r<k>`; one row then adds several `grade.json` versions to `grader_versions`, and a superseded run's grader version is tallied as if it were the row's.
**File:** `head/evals/harness/ablation-report.py:1063-1067`
**Suggestion:** Pick one directory per row: the row's `attempts` (or `run_id`) names the attempt, so match `-r<attempts>` when `attempts > 1` and the bare `-t<n>` otherwise; count unmatched rows in `run_dirs_missing` as today.
**Benefit:** The tally the README's regression-check recipe will read (grader versions behind the rows) counts rows, not leftover directories. The dissent (DISS-002) rated this BLOCKING; I keep it at MEDIUM because the figure is informational, the fixture does not show whether an original and a rerun directory coexist for one trial, and no decision reads it.

### 2. Suite-version partition — the key is not normalised the way the docstring says

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-report.py:835` — `version_key()` normalises the float `1.0` and digit-only strings, but the string `"1.0"` stays `"1.0"` (docstring L826: "1, 1.0 and "1" are one version"); a non-integer float such as `1.5` returns `None`, i.e. "absent".
**File:** `head/evals/harness/ablation-report.py:825-840`, `:857`
**Suggestion:** Normalise any numeric-looking string (`re.fullmatch(r"\d+(\.0+)?", s)`) to its integer text; treat a non-integer float as its own key rather than `None`; apply the same normalisation to `--suite-version` at L857.
**Benefit:** Today rows holding `2` and `"2.0"` (the row writer accepts both number and string, `ablation-row.sh` validate L148) split into two "never pooled" versions, and `version_order()` (L839-840) ranks `"2.0"` above every integer, so the string-typed slice silently becomes the primary; `--suite-version 1.0` against integer rows exits 2 with "no row has that suite_version (present: 1)"; a `1.5` row among another version exits 2 with "has no suite_version" although it names one.

### 3. H1/A4 reads — the degradation guard fires on a primary with no pair

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-report.py:875` — `assess()` checks the excluded share before `no_pair`; a primary whose comparison has zero pairs (a1_full's only review cells so far all degraded → share 1.000; a0_bare not yet rowed) reads `inconclusive_by_degradation`. With no other live primary (`h1a4()` L908-913), the H1 line reads "inconclusive by degradation — not established", `analyse()` counts it as decided (L1192, `H1_DECIDED`), and `--partial` exits 0.
**File:** `head/evals/harness/ablation-report.py:866-881`, `:1192`
**Suggestion:** Return `no_pair` when `p["n"] == 0` before applying the share guard (or require at least one pair for the guard to classify the comparison), so an early partial report keeps reading "not yet decidable (no pair)" and exit 1.
**Benefit:** A batch driver keying on `--partial`'s exit code, or an operator reading the H1 line, is not told a degradation verdict about a comparison that has not been made.

### 4. Lower-severity items

- **LOW** (confidence: high) `head/evals/harness/ablation-report.py:1054` — `r["arm"]` from the row is joined onto the batch directory with no grammar check (the report never re-checks the `^[a-z][a-z0-9_]{0,63}$` grammar the row writer enforces only under `--validate`); an arm like `../../x` makes the read-only listdir / `grade.json` walk leave the batch tree. Exposure is a `grader_version` string, but the read is outside the documented scope. Reject arms failing the grammar, or `os.path.realpath` and check containment. (CWE-22.)
- **LOW** (confidence: high) `head/evals/harness/ablation-report.py:959` — `budget_matched()` uses the per-defect union only when **every** valid a0_bare trial of the task carries an `ids`/`cap` vector; the header (L146-147) and the rendered legend (L1095) say the rate fallback applies to "a task whose a0 rows carry none". A task mixing row-writer 1.1 and 1.2 rows discards the union of the trials that do carry ids. Either union the ids-bearing trials and fall back only for the rest, or state the all-or-nothing rule in both texts.
- **LOW** (confidence: high) `head/evals/harness/ablation-report.py:1191` — the sensitivity H1/A4 `Analysis` excludes cap failures as cells (L522), and `assess()` counts those exclusions in the excluded share, so the sensitivity line can read "inconclusive by degradation (a1_full excluded share …)" when the share comes from the figure's own cap-failure treatment. Label the share source in `read_text` for the sensitivity read, or compute the guard on the main Analysis's cells.
- **LOW** (confidence: high) `head/evals/harness/ablation-report.py:776` — a null `false_positives` counts as 0 flagged regions, so an arm whose rows never recorded the field reports `precision` 1.0 and a `usd_per_true_defect` as if every flagged region were a true defect. Documented (L142), but the JSON carries no "rows with a numeric false_positives" count to tell measured 1.0 from unmeasured. Add that count (or null the precision when no row carries the field).
- **LOW** (confidence: high) `head/evals/tests/ablation-report.bats:290` — AR-20 runs `ablation-row.sh --validate` over every planted scenario except the new `present` one (the only scenario that sets `false_positives` on review rows and ships the extras tree). Add `present` to the list.
- **LOW** (confidence: high) `head/evals/harness/ablation-report.py:992` — SIMPLICITY[shrink]: `batch_record()` runs ~90 lines with four levels of nesting (for row → for dir → if → try). Split the STATUS.json read and the grader-version walk into two helpers. `budget_matched()` (L937) is at the 50-line threshold but reads linearly. Over-engineering pass otherwise: net: -0 lines possible beyond the split; the four presentation items are each the minimum that renders their table.

### 5. Cross-model observations (advisory, not counted)

- DISS-C-002, C-003, C-004, C-005 (claude-headless) restate items 4.1, 2, 4.4 and 4.2 above and are absorbed there.
- DISS-C-006 (claude-headless, null-safety: `f3(e['diff'])` on None) — **rejected on evidence**: `f3` returns `"n/a"` for None (`head/evals/harness/ablation-report.py:214-215`); the one-arm budget rows render "n/a".

## Rejected dissent payloads

- None: `metadata.rejected_summary` is empty and the sidecar `grimoires/loa/a2a/sprint-1/adversarial-rejected-review.jsonl` holds 0 rows (both voices completed: gpt-5.5-pro primary, claude-headless companion; `hallucination_filter.downgraded` 0).

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | The HIGH fix above (batch-record sort key) and the AR-32 fixture covering a non-numeric grader_version |

---

## Acceptance Criteria Check

### Task 1.1: review the pull request (sprint.md Success Criteria: "review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict")

| Criterion | Status | Notes |
|-----------|--------|-------|
| Row writer 1.2 carries `defects_missed` (bd-yz1rd) | Pass | `head/evals/harness/ablation-row.sh:410-413`; null on build rows, with no `recall`, or when `missed` is not a list of non-empty strings; `--validate` L165-168; bats L407-427, L465-479 |
| Row writer 1.2 carries `regressions_final_green` (bd-m0hw7) | Pass | `head/evals/harness/ablation-row.sh:414`; boolean or null; bats L429-446 |
| Suite versions never pooled; `--suite-version`; exit 2 on a version-less row among two versions | Pass with observation | `partition()` L843-861; AR-23/AR-24; Observation 2 (string `"1.0"` key) |
| Not-testable / not-yet-decidable / degenerate reads; degradation guard on H1 and A4 | Pass with observation | `assess()`/`h1a4()` L864-935, `compare()` L631-638; AR-25 … AR-29; Observation 3 (guard before no_pair) |
| Presentation items change no decision, H1/A4 state or existing number | Pass | `usable()`/`decide()`/`arm_report()` unchanged for non-degenerate pairs; AR-35 |
| Batch record "reported, never fatal" | Fail | HIGH above: TypeError in the grader-version sort aborts the report |
| Each defect reported with file and line; merge verdict given | Pass | This file and `review.md` |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [ ] Input validation and sanitization present — the report joins the row's `arm` into a filesystem path without the arm grammar (Observation 4.1); STATUS.json / grade.json are read with symlink refusal and type checks (good)
- [x] Authentication/authorization correct (n/a: local read-only tool)
- [x] No SQL/XSS injection vulnerabilities (markdown cells pass through `md_cell`)
- [x] Dependencies secure (stdlib only; jq in the row writer)
- [x] Error messages don't leak sensitive data

---

## Code Quality Summary

**Strengths:**
- The read states are a small explicit state machine (`assess()` → `h1a4()`) with the order documented in the header and in `## Method`, and each state has a planted fixture.
- The degenerate-pair rule closes a real statistical hole (a zero-variance interval that read as evidence) and is threaded through every consumer via one predicate (`usable()`).
- The row writer additions are typed defensively in jq and stay additive under `schema_version` 1.
- `batch_record()` refuses symlinks for STATUS.json, run directories and grade.json, and tolerates every missing file as a note.

**Areas for Improvement:**
- A presentation-only section must not be able to abort the decision report (HIGH).
- Normalise version keys once, in one place, and document the actual rule.
- `batch_record()` is long enough to split.

---

## Next Steps

1. Fix the grader-version sort key (and consider wrapping `batch_record()` so any exception degrades to a `status_note`); add a non-numeric `grader_version` directory to the `present` fixture and assert the rendered tally in AR-32.
2. Address Observations 1–3 or record the accepted behaviour in the header.
3. Run `bats evals/tests/ablation-report.bats evals/tests/ablation-row.bats` and record the result (and the CI fast gate) in the report in `grimoires/loa/a2a/sprint-1/reviewer.md`.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":3,"low":6},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T08:14:00Z"} -->
