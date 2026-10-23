# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)

---

## Overall Assessment

The change under review is `pr/head.diff`: ablation-row.sh 1.2 (two additive row fields, `defects_missed` and `regressions_final_green`, with `--validate` coverage) and ablation-report.py 1.0.0 → 1.2.0 (the suite_version partition, the not-testable / not-yet-decidable / inconclusive-by-degradation reads on the H1 and A4 lines, the degenerate single-task pair, and the R3 presentation items: sensitivity H1/A4 lines, batch record, precision, budget-matched baseline), with the bats suites and the fixture generator extended.

How it was verified. The real suite file `evals/suites/ablation-2.0.yaml` and the `ablation-runs` fixtures are not part of `pr/`, so I reconstructed a minimal suite from what the tests and code reference (arms a0…a8, `rules.exclusion.inconclusive_above_share 0.25`, `threshold_points 0.03`, `cost_lower_pct 15`, `mde_cut 0.10`, the quoted h1 text) and ran the head `ablation-report.bats` against it under jq 1.6 / Python 3.11: **33 of 35 pass**; AR-33 and AR-34 fail for the reason in Observation 3 (a jq-version dependence in the new assertions, not a code defect). `ablation-row.bats` cannot run without its fixture run directories; I exercised `--validate` directly on every generated runs.jsonl plus hand-made edge rows, and evaluated the two new jq row expressions over eight grade.json shapes — all behave as the header documents. I also probed the new code paths with inputs the fixtures do not cover; one probe crashes the report (Changes Required 1), and two more produce misleading output (Observations 2 and 4).

The row writer change is clean and surgical: the two expressions are null-safe for every grade shape I tried, the validator is additive and legacy rows still validate, the `--help` range tracks the longer header. The report refactor into `analyse()` / `render_*` is well-contained; decision semantics on the pre-existing scenarios are unchanged (AR-1 … AR-22 pass) and the degenerate / degradation-guard / partition logic does what the header says on the planted scenarios.

Blocking: the batch record (an item the header itself calls informational and "never fatal") can abort the entire report with an unhandled `TypeError` on a grader_version string that mixes numeric and non-numeric segments, leaving no report.md and no report.json and bypassing the exit-2 `Fail` contract. Both adversarial dissent voices found the same line independently.

Process note: the implementation report (the PR description) carries no `## AC Verification` walkthrough and the slice holds no CHANGELOG entry; the sprint definition scopes the review to `pr/head.diff`, so I note it here rather than count it.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Functionality — an informational section crashes the whole report

- **HIGH** (confidence: high) `head/evals/harness/ablation-report.py:1081` — the grader_versions tally is sorted with a key that maps digit-only segments to `int` and leaves the rest as `str`; two real versions that differ in kind at the same position make Python compare `int` with `str` and `sorted()` raises `TypeError`, which `main()` does not catch (only `Fail` is, `:1678`): a traceback, exit 1, and neither `--out` nor `--json` is written.
**File:** `head/evals/harness/ablation-report.py:1081-1082`
**Issue:** Reproduced with the `present` fixture by writing `{"grader_version":"1.2.11-rc1"}` (and separately `"dev"`) into `pr-2/a0_bare/rc-01-t3/grade.json` beside the existing `1.2.5` and `1.2.11`:
```
    e["grader_versions"] = dict(sorted(gv.items(), key=lambda kv: (
                                ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
TypeError: '<' not supported between instances of 'str' and 'int'
exit=1   (no report.md, no report.json)
```
The leading `kv[0] == "n/a"` tuple element only separates `n/a` from everything else. grade.json is external data read from run directories with no format restriction on `grader_version`; the header (`:131-137`) promises this section is read-only and that a missing directory is "counted, never fatal", and the exit-code contract (`:158-162`) reserves 1 for `--partial` and 2 for input errors.
**Why This Matters:** The report is the sprint's deliverable (the H1/A4 decision record); a decides-nothing presentation item must not be able to take it down, and an unhandled traceback with exit 1 is indistinguishable from the documented `--partial` exit 1 to a caller that checks status.
**Required Fix:** Use a total ordering for the tally key, e.g. `(kv[0] == "n/a", [(0, int(p)) if p.isdigit() else (1, p) for p in kv[0].split(".")])`, and add a test with a non-numeric segment (e.g. `1.2.11-rc1`) beside numeric versions in the `present` scenario. Consider also wrapping `batch_record()` so any exception there degrades to a `status_note`, honouring the "never fatal" promise.
**Reference:** Dissent envelope DISS-001 (gpt-5.5-pro) and DISS-C-001 (claude-headless companion) — both BLOCKING on this line.

---

## Observations

### 1. Correctness — the version partition runs before the smoke / no-manifest listing

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-report.py:843-862` — `partition()` keys every row by suite_version before `Analysis._classify` (`:494-507`) lists smoke-batch and no-manifest rows, so a smoke batch on a newer suite_version becomes the primary: the main Decisions / H1 / A4 sections then describe a version whose rows are all listed and never decided, and the real data is pushed into the "reported separately" section.
**File:** `head/evals/harness/ablation-report.py:1403`
**Suggestion:** Reproduced: giving the `main` fixture's `smoke-260` rows `suite_version: 3` yields `primary_suite_version 3`, `H1: not yet decidable (no pair)` at the top, and `## Suite version 1 (batches: priority-1) — reported separately` below, exit 0 with no warning. A smoke batch is exactly what runs first on a new suite version. Partition only rows that will enter a decision (not smoke, with a manifest), or exclude such rows from the primary choice and say so in the header.
**Benefit:** The headline sections always describe the data that was actually scored; `--suite-version` stays an override, not a workaround.

### 2. Testing — the new bats assertions depend on jq ≥ 1.7 number formatting

- **MEDIUM** (confidence: high) `head/evals/tests/ablation-report.bats:487` — AR-33 expects `"1.0 2.222222 27 27"` and AR-34 (`:498`, `:503`) expects `"1.0 3.0 0.875 10.0 …"` from `jq -r` string interpolation; jq 1.6 prints `1.0` as `1` and `3.0` as `3`, so both tests fail on jq 1.6 (Debian 12 / Ubuntu 22.04 default) while the report output is correct. No pre-PR assertion in this file depends on this, so the dependence is new.
**File:** `head/evals/tests/ablation-report.bats:487-503`
**Suggestion:** Compare numerically (`.precision == 1`), or format with `tostring`/`@json` after `tonumber`, or pin jq ≥ 1.7 in the test preamble and skip otherwise. `FAST-GATE:` the report's self-check in the PR description does not state the jq version the suite was run under.
**Benefit:** AR-33/AR-34 pass or skip deterministically across the fleet rather than depending on the host's jq.

### 3. Correctness of presentation — precision is fabricated when false positives were never graded

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-report.py:776-779` — a `null` `false_positives` counts as 0, so an arm whose review rows carry no false-positive grading at all reads `precision 1.000 = true defects N / flagged regions N`, and `:1288-1292` prints that line whenever the arm has any review task (the per-task dict is non-empty even when every value is `None`).
**File:** `head/evals/harness/ablation-report.py:1288-1292`
**Suggestion:** Reproduced by nulling `false_positives` on every `present` row: a0_bare reports precision 1 over 6 rows. The header documents "a null false_positives counts 0" (`:139-141`), but null here means ungraded, not zero; emit `null` (and "n/a") unless at least one counted row carries a numeric `false_positives`, or report the count of FP-graded rows beside the figure.
**Benefit:** An informational number labelled "decides nothing" still gets quoted; a perfect precision that nobody measured is the kind of number that gets quoted most.

### 4. Robustness — suite_version keys that are neither int nor digit-string

- **LOW** (confidence: high) `head/evals/harness/ablation-report.py:825-835` — `version_key` folds `1`, `1.0` and `"1"` together but keeps `"2.0"` (a string) distinct from `2`, and returns `None` for a non-integral float such as `2.5`; the `None` case then raises at `:849` with "row … has no suite_version" although the row names one, and `--suite-version 2.0` is rejected with "no row has that suite_version (present: 1, 2)".
**File:** `head/evals/harness/ablation-row.sh:410` copies `suite_version` from the manifest, pipeline or task YAML without normalisation, so a string form can reach the report.
**Suggestion:** Normalise digit strings with a trailing `.0` to the integer key, and name the actual value in the error ("suite_version 2.5 is not a version key").
**Benefit:** Clear errors; no accidental third partition from a formatting difference. (Dissent DISS-C-005 raised the same point.)

### 5. Security hygiene — a row's arm name is joined into a filesystem path

- **LOW** (confidence: medium) `head/evals/harness/ablation-report.py:1054` — `os.path.join(d, r["arm"])` uses the row's `arm` string unchecked; `load_rows` (`:296-300`) only requires a non-empty string and the report never requires `--validate`d rows, so an arm of `../../..` makes `batch_record` list an arbitrary directory. Impact is small (only directory names are compared against `task_id` and only `grader_version` of a `grade.json` is read), but it is the one place the report walks the filesystem from row data.
**File:** `head/evals/harness/ablation-report.py:1054`
**Suggestion:** Skip rows whose arm is not one of the suite's arm ids (they are listed as "not run by the suite" anyway) or apply the arm grammar `^[a-z][a-z0-9_]{0,63}$` that `ablation-row.sh --validate` enforces (`:164`).
**Reference:** CWE-22 (path traversal), defence in depth.

### 6. Testing — AR-20 does not validate the `present` scenario

- **LOW** (confidence: high) `head/evals/tests/ablation-report.bats:290` — the `--validate` loop lists every new scenario except `present`, the only one that sets `false_positives = 0` and carries the STATUS.json / grade.json extras. It does validate (90 rows valid when I ran it), so this is coverage, not a failure.
**Suggestion:** Add `present` to the loop.
**Benefit:** Every planted runs.jsonl stays in the real row shape as the row writer evolves.

### 7. Documentation — the A4 `no_arm` state is undocumented and wears the "fails" line

- **LOW** (confidence: medium) `head/evals/harness/ablation-report.py:931` — a suite without `a4_no_gates` yields `a4.state "no_arm"` but the line reads "A4 sensitivity: fails — harden tasks before acting on other arms", and `no_arm` is absent from the header's A4 state list (`:120-124`) and from `A4_DECIDED`. The wording is pre-existing; the new state machine makes it an undocumented state that reads as a decision.
**Suggestion:** Either document `no_arm` in the header or give it its own line ("A4 sensitivity: no arm a4_no_gates in the suite").
**Benefit:** JSON consumers switching on `a4.state` see every state the code emits.

### Complexity

`analyse()` / `render_*` extraction is a net simplification of `build()`; `batch_record()` (~75 lines) and `render_batches()` (~40 lines) are long but linear. `budget_matched()` and the precision block are each the one required check behind their figure. Lean enough. Ship once Changes Required 1 is fixed.

---

## Rejected dissent payloads

None. The envelope's `metadata.rejected_summary` is empty and `adversarial-rejected-review.jsonl` beside it holds no rows (0 bytes).

---

## Cross-Model Observations

Adversarial review envelope `grimoires/loa/a2a/sprint-1/adversarial-review.json`: primary gpt-5.5-pro (answered via codex-headless), companion claude-headless (independent voice, succeeded); 6 findings, 2 BLOCKING, 4 ADVISORY. Triage:

- **DISS-001 / DISS-C-001 (BLOCKING, both voices)** — grader_versions sort `TypeError` at `:1081`. **Accepted**, reproduced; it is Changes Required 1.
- **DISS-C-002 (ADVISORY)** — claims `assess()` reads "not testable" when every cell of a type is excluded. **Refuted**: `compare()` builds `tasks` from `self.cells`, which holds excluded rows too, and lists such tasks under `unpaired` ("every cell of X excluded"); reproduced by degrading every a1_full row of the `degraded` fixture: catch rate reads `inconclusive_by_degradation` with 4 unpaired tasks, H1 `inconclusive_by_degradation`.
- **DISS-C-003 (ADVISORY)** — `f3(None)` in `render_budget`. **Refuted**: `f3` returns `"n/a"` for `None` (`:214-215`).
- **DISS-C-004 (ADVISORY)** — vector-length mismatch / `None` scores in `budget_matched`. **Refuted**: every vector for a task has length `task_defects[task]` (`:535-546`), and valid review rows always carry a numeric catch rate or are cap failures (`:517-518`), so `catch_task_score` never returns `None`.
- **DISS-C-005 (ADVISORY)** — `version_key` returns `None` for 1.5 and the error says "has no suite_version". **Accepted** as Observation 4.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | Changes Required 1 (report aborts on a mixed-form grader_version) |

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff` (claims from `pr/PR.md` and the file headers)

| Criterion | Status | Notes |
|-----------|--------|-------|
| ablation-row.sh 1.2 carries `defects_missed` (bd-yz1rd) per the header rules | Pass | `:410-413`; eight grade shapes evaluated: list copied, `[]` kept, null for build rows / null recall / non-list / empty-string ids |
| ablation-row.sh 1.2 carries `regressions_final_green` (bd-m0hw7) | Pass | `:414`; boolean copied, null for array/absent/non-boolean |
| `--validate` accepts legacy rows and rejects bad new-field types | Pass | `:165-170`; 9 edge rows checked, messages as the tests expect |
| suite_version partition, never pooled; `--suite-version`; exit 2 on a missing version | Pass with caveat | AR-23/24 pass; Observation 1 (smoke batch can become primary), Observation 4 (key normalisation) |
| not-testable / not-yet-decidable / inconclusive-by-degradation reads on H1 and A4 | Pass | AR-25 … AR-27 pass; mixed-read case (pass tested lo ≤ 0, catch degraded) reads "not established" as the header says |
| degenerate single-task rate-fallback pair flagged and read as no valid pair | Pass | AR-28/29 pass |
| sensitivity H1/A4 lines, batch record, precision, budget-matched baseline change no decision | Pass with caveat | AR-31/32/35 pass; batch record can abort the report (Changes Required 1); precision misleading when FP ungraded (Observation 3) |
| Tests pass | Fail on jq 1.6 | AR-33, AR-34 fail under jq 1.6 (Observation 2); 33/35 pass with the reconstructed suite |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [x] Input validation and sanitization present — row/manifest schema checks, symlink refusals on STATUS.json, grade.json and MANIFEST.json; one unchecked path component (Observation 5)
- [x] Authentication/authorization correct — n/a (offline report generator)
- [x] No SQL/XSS injection vulnerabilities — markdown cells escaped via `md_cell`
- [x] Dependencies secure (no known CVEs) — stdlib only; `yq` invoked with a fixed argv
- [x] Error messages don't leak sensitive data — paths only

---

## Code Quality Summary

**Strengths:**
- The row-writer change is additive, null-safe and documented in the header; `--validate` stays backward compatible.
- Decision semantics are preserved: every pre-existing AR test passes unchanged except AR-14's intentional wording change.
- The partition / read-state design is explicit about what is decided versus listed, and the JSON mirrors every markdown figure.
- Read-only discipline in `batch_record` (symlinks refused, missing files tolerated) is the right posture.

**Areas for Improvement:**
- "Never fatal" presentation code should be wrapped so a malformed external file degrades to a note (Changes Required 1).
- The primary-version choice should consider only rows that can enter a decision (Observation 1).
- New test assertions should not depend on the host jq's number formatting (Observation 2).

---

## Next Steps

1. Fix the grader_versions sort key and add the mixed-form regression test (Changes Required 1).
2. Decide on Observations 1–3; they are not blocking but each changes what an operator reads.
3. Re-run both bats suites, stating the jq version, and update `grimoires/loa/a2a/sprint-1/reviewer.md` with an `## AC Verification` walkthrough.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":3,"low":4},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T15:45:00Z"} -->
