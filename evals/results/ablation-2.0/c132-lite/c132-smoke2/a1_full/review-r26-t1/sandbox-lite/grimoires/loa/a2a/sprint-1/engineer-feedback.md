# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md (Task 1.1: the change in `pr/head.diff`)
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)

---

## Overall Assessment

The change under review is sprint-262: row writer `ablation-row.sh` 1.2 (new optional fields `defects_missed`,
`regressions_final_green`, with `--validate` clauses) and `ablation-report.py` 1.2.0 (suite_version partition,
the not-testable / not-yet-decidable H1 and A4 states, the degradation guard on the H1/A4 lines, the degenerate
single-task pair, plus the presentation items: sensitivity H1/A4 lines, batch record, precision and cost per true
defect, budget-matched baseline), with eleven fixture scenarios and tests AR-23 … AR-35 and five new row tests.

The core statistics and read logic hold up. I could not run the bats suites in this workspace (no `evals/` tree,
no `evals/suites/ablation-2.0.yaml`, no `ablation-runs` fixtures), so I verified the work directly instead:
`gen-fixtures.py` generates all eleven scenarios; every scenario's rows pass the head
`ablation-row.sh --validate --allow-ungraded` (including `present`); the head report ran on all eleven scenarios
against a synthetic suite with the same arms and rules shape and reproduced every planted figure the new tests
assert (H1 d = 0.444444 on v2, A4 not testable, excluded shares 0.750 / 0.333, the degenerate flag and rule
text, precision 0.647059 / USD 0.545455, budget-matched 0.75 / 0.9375 with the exact note, the batch-record
tallies and "no STATUS.json" row). The new `--validate` clauses were exercised with every shape the tests use
plus nested arrays and numbers; all behave as documented. The row emission itself
(`head/evals/harness/ablation-row.sh:410-414`) was verified by reading the jq only, since the run-dir fixtures are
not present here.

One defect blocks the merge: the new batch record's grader-version sort raises an uncaught `TypeError` when two
grader_version strings have differently typed tokens at the same position (for example `2.0.0` beside
`2.0.0-rc.5`), and the whole report aborts with a traceback, no report.md, no report.json. The PR's own header
promises the batch record is "never fatal". Reproduced locally; both dissent voices flagged it BLOCKING
independently. It is a one-line fix plus a fixture.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Functionality — the batch record can abort the whole report

- **HIGH** (confidence: high) `head/evals/harness/ablation-report.py:1081-1082` — the grader_versions sort key
  `[int(p) if p.isdigit() else p for p in re.split(r"[.]", kv[0])]` mixes `int` and `str` tokens; two
  grader_version strings whose tokens differ in type at the first unequal position raise
  `TypeError: '<' not supported between instances of 'str' and 'int'` inside `sorted()`, and the uncaught
  exception aborts `build()` before anything is written.
**File:** `head/evals/harness/ablation-report.py:1081-1082` (called from `build()` at
`head/evals/harness/ablation-report.py:1552` with no guard)
**Issue:** `grader_version` is read from external `grade.json` files
(`head/evals/harness/ablation-report.py:1072-1077`). A batch whose run directories hold `"2.0.0"` beside
`"2.0.0-rc.5"` (tokens `[2,0,0]` vs `[2,0,"0-rc",5]`), or `"1.2.11"` beside `"1.2.11a"`, crashes the report with
a Python traceback (exit 1, not the documented exit 2) and writes neither `--out` nor `--json`. Reproduced on the
`present` fixture with two added grade.json files. The header states the batch record is "never fatal"
(`head/evals/harness/ablation-report.py:139`, `:994`). This repository's own version strings use the
`2.0.0-rc.N` shape, so a grader that adopts it at a bump triggers this on the first mixed batch.
**Why This Matters:** The report is the cycle's decision artifact; an informational section must never prevent
the decisions, H1 and A4 from being written. Recovery would require editing grade.json files inside run
directories, which are evidence.
**Required Fix:** Use a type-stable total order and add coverage.
**Reference:** Python data-model comparison rules (heterogeneous sequence ordering raises); the PR header's own
"never fatal" contract.

**Example:**
```python
# Current (problematic) — ablation-report.py:1081-1082
e["grader_versions"] = dict(sorted(gv.items(), key=lambda kv: (
    kv[0] == "n/a", [int(p) if p.isdigit() else p for p in re.split(r"[.]", kv[0])])))

# Should be — every token compares as a (tag, value) pair
e["grader_versions"] = dict(sorted(gv.items(), key=lambda kv: (
    kv[0] == "n/a", [(0, int(p), "") if p.isdigit() else (1, 0, p) for p in kv[0].split(".")])))
```
Add to `present_scenario()` in `gen-fixtures.py` a run dir with `grader_version: "1.2.11-rc.1"` beside the existing
`1.2.11`, and assert the tally in AR-32.

---

## Observations

### 1. Correctness — suite_version keys that are the same number but a different JSON type

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-report.py:825-836` — `version_key` unifies `1`,
  `1.0` and `"1"` (its docstring) but keeps the string `"2.0"` as its own key and maps a non-integer float such as
  `2.5` to `None` (read as "no suite_version").
**File:** `head/evals/harness/ablation-report.py:825-836`, `:839-840`, `:861`
**Suggestion:** Reproduced: one row with `"suite_version": "2.0"` among integer-2 rows produced
`primary_suite_version: "2.0"` with versions 2 and 1 pushed into "reported separately" sections, because
`version_order` (`:839-840`) ranks every non-digit key above every integer key and `partition` takes the max
(`:861`). A float `2.5` among two versions exits 2 with "has no suite_version" although it has one, and
`--suite-version 2.0` is refused while `--suite-version 02` works. Normalise numeric-looking strings (try
`float()`, `is_integer()` → `str(int)`, else keep the numeric text) and let `--suite-version` follow.
**Benefit:** A quoted version in a manifest or task YAML cannot silently take over the main sections.

### 2. Correctness — grader-version tally counts rerun directories twice per row

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-report.py:1063-1080` — every directory matching
  `<task>-t<n>` or `<task>-t<n>-r<k>` is tallied for one row, so a rerun cell with both `rc-01-t1` and
  `rc-01-t1-r2` contributes two grader_version counts.
**File:** `head/evals/harness/ablation-report.py:1063-1080`
**Suggestion:** Reproduced on `present`: 18 rows gave 4 tallied versions plus 15 "no run dir" (19 > 18), and the
stale pre-rerun `grade.json` was counted as if it fed a row. Prefer the highest `-r<k>` directory per row and
count it once.
**Benefit:** The batch record's grader_versions sum stays equal to `trials_rowed` and names the grader that
actually produced each row.

### 3. Input handling — the row's arm is joined into a filesystem path unchecked

- **LOW** (confidence: medium) `head/evals/harness/ablation-report.py:1054` — `os.path.join(d, r["arm"])` trusts the
  row's `arm`; the report never applies the arm grammar `ablation-row.sh --validate` enforces
  (`head/evals/harness/ablation-row.sh:162`), so a crafted runs.jsonl with arm `../../x` lists and reads
  `grade.json` files outside the batch directory (symlinks are refused at `:1057-1059`, `:1072`; plain traversal is
  not).
**File:** `head/evals/harness/ablation-report.py:1054`
**Suggestion:** Skip (or `Fail`) rows whose arm does not match `^[a-z][a-z0-9_]{0,63}$` before building the path.
Impact is small (only a `grader_version` string is read and rendered through `md_cell`), which is why this is LOW.
**Benefit:** Trust boundary consistency between the row writer and the reader (CWE-22 class, read-only).
**Reference:** CWE-22.

### 4. Documentation vs code — the budget-matched rate fallback

- **LOW** (confidence: high) `head/evals/harness/ablation-report.py:959-964` — the header (`:145-147`) says the
  rate fallback applies to "a task whose a0 rows carry none" of the ids, but `all(... how in ("ids", "cap"))`
  falls back for the whole task when any single a0 row lacks ids.
**File:** `head/evals/harness/ablation-report.py:959-964`
**Suggestion:** One pre-1.2 row among 1.2 rows on the same task discards the per-defect union for every trial and
reports the best trial's rate, labelled only "rate fallback". Either compute the union over the id-bearing rows
and fall back only when none carry ids, or document the stricter rule and add the id-less row count to `reason`.
**Benefit:** The informational figure means what the Method text says it means during the v1→v2 transition.

### 5. Tests — AR-20 leaves the `present` scenario out of the row-shape validation

- **LOW** (confidence: high) `head/evals/tests/ablation-report.bats:290` — the `--validate` loop covers every new
  scenario except `present`, although its rows validate (90 rows valid when I ran the head row writer on them).
**File:** `head/evals/tests/ablation-report.bats:290`
**Suggestion:** Add `present` to the loop.
**Benefit:** The scenario that drives AR-32 … AR-34 is held to the same row-shape contract as the others.

### 6. Tests — stale file header

- **LOW** (confidence: high) `head/evals/tests/ablation-report.bats:6-7` — the header still says gen-fixtures
  "writes four scenarios (main, boundary, exclusions, partial …)"; the PR brings it to eleven.
**File:** `head/evals/tests/ablation-report.bats:6-7`
**Suggestion:** Update the count and point at the gen-fixtures header for the list.
**Benefit:** The next reader does not go looking for four directories.

### 7. Fixtures — the planted rows are the pre-1.2 row shape

- **LOW** (confidence: high) `head/evals/tests/fixtures/ablation-report/gen-fixtures.py:87-116` — `row()` emits
  `defects_missed` only when `with_missed` and `missed is not None`, and never emits `regressions_final_green`;
  AR-20's "the planted rows hold the real row shape" therefore covers the legacy (pre-1.2) shape only.
**File:** `head/evals/tests/fixtures/ablation-report/gen-fixtures.py:114-116`
**Suggestion:** Emit `"defects_missed": None` on build rows and on id-less review rows, and
`"regressions_final_green": True/False/None`, so the fixtures match what row writer 1.2 writes and the report's
reader of a null `defects_missed` (`ablation-report.py:546-552`) is exercised by the planted rows.
**Benefit:** The report is tested on the rows the writer actually produces.

### 8. Diagnostics — element-level validate failures do not name the element

- **LOW** (confidence: medium) `head/evals/harness/ablation-row.sh:165-168` — for `["d2", 3]`, `[""]` or
  `[["d2"]]` the message reads "field defects_missed has type array, want a list of non-empty strings|null" and
  never says which element failed or why.
**File:** `head/evals/harness/ablation-row.sh:168`
**Suggestion:** Branch the message: type mismatch vs "element N is not a non-empty string".
**Benefit:** A failed `--validate` on a 300-row file points at the cause.

### 9. Text — the degenerate reason misdescribes an all-cap single-task pair

- **LOW** (confidence: medium) `head/evals/harness/ablation-report.py:634-639` — when every row of a single-task
  catch pair is `cap_failure`, `defect_identity` is empty after `- {"cap"}` so the pair is flagged degenerate with
  the reason "with no per-defect ids: every defect takes the row's defect_catch_rate", which is not what happened
  (every vector is zeros from `:544-545`).
**File:** `head/evals/harness/ablation-report.py:637-639`
**Suggestion:** The read (no valid pair) is right; make the reason name the cap-only case.
**Benefit:** Accurate narrative in a line a lead reads before ruling.

### 10. SIMPLICITY[shrink] — `batch_record` is 93 lines

- **LOW** (confidence: high) `head/evals/harness/ablation-report.py:992-1084` — one function reads STATUS.json,
  tallies four lists, maps extra_models and paused_arms, and walks run directories for grader versions.
**File:** `head/evals/harness/ablation-report.py:992-1084`
**Suggestion:** Split the STATUS.json read (`:1007-1049`) and the grader-version walk (`:1050-1082`) into two
helpers; the fix for Changes Required §1 lands in the second. `build()` (`:1379-1637`) also grew but is the
pre-existing render driver; I am not asking for a rewrite of it in this sprint. Over-engineering pass otherwise:
Lean already. net: -10 lines possible.
**Benefit:** Each helper fits on a screen and the "never fatal" guarantee can be checked per helper.

### Process notes (not counted)

- `reviewer.md` is the PR description and carries no `## AC Verification` section. The sprint definition for this
  review designates `pr/PR.md` as the implementation report and the review instructions waive the a2a
  prerequisites, so this is recorded rather than applied as the automatic trigger.
- The PR's commit list names a CHANGELOG Sprint 262 entry and README/suite-README updates; those files are
  outside the five-file scope of `pr/head.diff`, so they were not verified here.
- Fast-gate parity could not be checked (no CI configuration or formatter run is in scope); `bash -n` passes on
  the row writer and the report imports and runs under `python3 -I`.

---

## Cross-Model Observations

Adversarial review (`adversarial-review.json`, two voices, both completed, companion counted as an independent
voice): primary gpt-5.5-pro (answered by codex-headless), companion claude-headless.

- DISS-001 / DISS-C-001 (BLOCKING, both voices) — the grader_versions sort TypeError. Counted above as Changes
  Required §1; matches my reproduction.
- DISS-C-002 (advisory) — `version_key` string/float handling. Corroborates Observations §1.
- DISS-C-004 (advisory) — rerun directories tallied twice, and the unchecked arm path. Corroborates Observations
  §2 and §3.
- DISS-C-005 (advisory) — the budget-matched fallback wording. Corroborates Observations §4.
- DISS-C-003 (advisory) — claimed `assess()` reads "not testable" when both H1 arms are fully excluded. Tested and
  not reproduced: `compare()` records every such task under `unpaired` ("every cell of X excluded",
  `ablation-report.py:581-593`), so `assess()` proceeds to the degradation guard; with every a0 and a1 review row
  degraded the report read "H1: inconclusive by degradation — not established" (state
  `inconclusive_by_degradation`, 4 unpaired tasks), and the same with every row ungraded. Not a defect.
- DISS-C-006 (advisory) — claimed the precision line is skipped when every `false_positives` is null. Tested and
  not reproduced: `false_positives_per_task` (`:794`) is keyed by task, so it is non-empty whenever valid
  review-catch rows exist; with all a3_one_voice false_positives null the line still rendered
  ("n/a = true defects 0 / flagged regions 0 … over 6 valid review-catch rows"). Not a defect.

## Rejected dissent payloads

None. `metadata.rejected_summary` is empty and the named sidecar `adversarial-rejected-review.jsonl` holds zero
rows; the companion produced no sidecar.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | Changes Required §1 (batch record sort crash) |

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff` (goals as the PR states them)

| Criterion | Status | Notes |
|-----------|--------|-------|
| Row writer 1.2 carries `defects_missed` (review-catch rows; null otherwise) | Pass | `ablation-row.sh:410-413`; verified by reading; the five new row tests cover the shapes |
| Row writer 1.2 carries `regressions_final_green` (boolean or null) | Pass | `ablation-row.sh:414`, `boolish` at `:319` |
| `--validate` accepts both fields optionally with the documented types | Pass | `ablation-row.sh:165-170`; exercised with 9 crafted rows, all as documented |
| Rows of different suite_version are never pooled; primary = highest or `--suite-version` | Pass (with Observations §1) | `partition` `:843-861`; reproduced AR-23/24/30 figures |
| H1/A4 states not_testable / inconclusive_by_degradation / degenerate / no_pair / tested | Pass | `assess` `:864-880`, `h1a4` `:898-934`; AR-25 … AR-29 figures reproduced |
| Presentation items change no decision, state or existing number | Pass | AR-35 logic reproduced; sensitivity lines, batch record, precision, budget-matched present in both outputs |
| Batch record "never fatal" | Fail | Changes Required §1 |
| Fixtures + tests for every new behaviour | Pass (not executed here) | Could not run bats in this workspace; planted figures reproduced against a synthetic suite |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [x] Input validation and sanitization present (STATUS.json / grade.json read tolerantly; symlinks refused; `md_cell` on rendered strings; see Observations §3 for the arm path)
- [x] Authentication/authorization correct (n/a — offline report)
- [x] No SQL/XSS injection vulnerabilities (markdown cells escaped)
- [x] Dependencies secure (stdlib only; `yq` unchanged)
- [x] Error messages don't leak sensitive data

---

## Code Quality Summary

**Strengths:**
- The read order for H1/A4 is explicit, documented in the header and mirrored in the Method section.
- The degenerate flag is computed once in `compare()` and consumed uniformly by `usable()`, `decide()`, `assess()`.
- Fixture scenarios plant every number the tests assert and the header lists them.
- The row writer keeps the new fields additive under schema_version 1 and optional for legacy rows.

**Areas for Improvement:**
- Keep informational sections (batch record, budget-matched) behind their "never fatal" promise with type-stable
  code paths; see Changes Required §1 and Observations §2.
- Normalise versions once (`version_key`) for every JSON type the writer can emit.

---

## Next Steps

1. Fix the grader_versions sort key (Changes Required §1) and add the mixed-version fixture to `present_scenario()`.
2. Consider Observations §1 and §2 in the same pass (both are small and in the same new code).
3. Run `bats evals/tests/ablation-report.bats evals/tests/ablation-row.bats` in the real tree.
4. Update the report in `grimoires/loa/a2a/sprint-1/reviewer.md` and request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":2,"low":8},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T10:36:00Z"} -->
