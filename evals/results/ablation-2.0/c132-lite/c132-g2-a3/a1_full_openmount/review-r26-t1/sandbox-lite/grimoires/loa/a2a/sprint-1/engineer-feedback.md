# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (pr/PR.md)
**Change under review:** pr/head.diff (5 files: ablation-report.py 1.0.0 → 1.2.0, ablation-row.sh row writer 1.2, ablation-report.bats, ablation-row.bats, gen-fixtures.py)

---

## Overall Assessment

The row-writer half of this change (`defects_missed`, `regressions_final_green`, their `--validate` rules, the five new bats cases) is correct and surgical: the jq guards null/absent `recall`, a non-list `missed`, a non-boolean `final_green`, build rows, and legacy rows lacking both keys; the `--help` sed range tracks the 17 added header lines exactly. The report half delivers the suite_version partition, the H1/A4 read states, the degradation guard, the degenerate single-task pair, and the four presentation items, and the twelve new AR tests encode them well. I reproduced the new report behaviour end to end on the generated fixtures against a synthesised suite (the real `evals/suites/ablation-2.0.yaml` is outside this PR): AR-23 … AR-32 and AR-35 pass; AR-33/34 fail here only on jq 1.6 number rendering (see Observations). `evals/tests/ablation-row.bats` could not be executed: its fixture tree `evals/tests/fixtures/ablation-runs/` is not part of the PR; the jq row and validate programs were reviewed by reading and by validating all eleven generated fixture sets (`present` included: 90 rows valid).

Two defects block the merge. Both sit in the new report code and both were raised by the adversarial dissent and confirmed by me with concrete inputs:

1. `version_key()` is not total. A non-integral numeric `suite_version` (2.1) maps to `None`, which `partition()` reads as "absent". Rows of suite_version 2.1 and 2.2 are pooled into one `n/a` version, and a 2.1 row beside version-2 rows is silently folded into version 2. Both exit 0. This defeats the "never pooled" invariant the sprint exists to enforce.
2. The grader-version tally sort in `batch_record()` compares `int` with `str` and raises `TypeError` whenever two `grade.json` files in one batch carry heterogeneously shaped `grader_version` strings (`1.2.0` vs `1.2.0-rc1`, or `1.2.11` vs `v1.2.12`). The report aborts with a traceback for an informational section the header promises is "never fatal".

Process note: `pr/PR.md` (the implementation report) carries no `## AC Verification` section and lists sprint-261 commits, README, CHANGELOG and release-note work that are not in this diff; per the review instructions the PR files are the entire input, so this is recorded rather than counted.

Complexity pass: `build()` shrank by extraction (good); `batch_record` (93 lines) is the one new function over the 50-line bar (Observations §3). net: -30 lines possible.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Correctness — suite_version partition pools non-integral versions

- **HIGH** (confidence: high) `head/evals/harness/ablation-report.py:825-836` — `version_key()` returns `None` for any float that is not integral and for any non-string, non-int value, and `partition()` (`:843-861`) treats `None` as "suite_version absent". Rows with `suite_version: 2.1` and `2.2` therefore form an empty key set and are pooled into a single `n/a` group; a `2.1` row among version-`2` rows takes the `len(keys) <= 1` branch at `:852` and is joined to version 2. Neither case exits 2.
**File:** `head/evals/harness/ablation-report.py:836` (the trailing `return None`), `:852` (the single-version join), `:839-841` (`version_order` ranks any non-digit string above every integer, so a stray `"2-rc"` becomes the primary over `2`).
**Issue:** Reproduced on the `versions` fixture with my scratch suite: ver-v1 rows set to 2.1 and ver-v2 to 2.2 → exit 0, `primary_suite_version: null`, one `by_suite_version["n/a"]` entry of 156 rows across both batches, `a1_full.rows: 60` (12 + 48 pooled), `H1: established` computed on the pooled rows, header line `- row suite_version: 2.1, 2.2` directly above `suite_version n/a (primary …): 156 rows; batches ver-v1, ver-v2`. With ver-v1 at 2 and ver-v2 at 2.1: exit 0 and the 2.1 rows fold into version 2. The row schema explicitly allows `suite_version` as `number|string|null` (`head/evals/harness/ablation-row.sh:150`), so 2.1 is a legal value, and a YAML `suite_version: 2.1` arrives as a float. Also inconsistent: the string `"2.0"` keys as `"2.0"` while the number `2.0` keys as `"2"`, so the same version written two ways is reported as two versions with the string one primary.
**Why This Matters:** Pooling rows across suite versions is exactly what Sprint 262's partition was introduced to make impossible; a silent pool produces an H1/A4 line and component decisions on mixed-suite evidence with nothing in the report or the exit code to show it.
**Required Fix:** Make `version_key` total over numbers and fail loudly on anything else: after the `is_integer()` branch return a canonical string for non-integral floats (e.g. `repr(v)` or a fixed-precision form), normalise numeric strings the same way (`"2.0"` → `"2"`), and `raise Fail(f"{row['_where']}: row {rid} has an unreadable suite_version {v!r}")` for any remaining type instead of `return None`. Restrict `max(groups, key=version_order)` to numeric keys or `Fail` when a non-numeric key is present. Add an AR case with `suite_version` 2.1 and 2.2 (expect two sections) and one with 2 and 2.1 (expect two sections, never a pool).

### 2. Robustness — grader_version tally sort raises TypeError and aborts the report

- **HIGH** (confidence: high) `head/evals/harness/ablation-report.py:1081-1082` — `sorted(gv.items(), key=lambda kv: (kv[0] == "n/a", [int(p) if p.isdigit() else p for p in re.split(r"[.]", kv[0])]))` builds mixed `int`/`str` lists; Python raises `TypeError: '<' not supported between instances of 'str' and 'int'` as soon as two keys differ in type at the same position.
**File:** `head/evals/harness/ablation-report.py:1081`
**Issue:** Reproduced: a batch whose run directories hold `grade.json` with `grader_version` `1.2.5`, `1.2.11` and `PWNED-9.9` (or `1.2.0` with `1.2.0-rc1`, or `1.2.11` with `v1.2.12`) → traceback from `batch_record` → `build` → `main`, exit 1, no `report.md` or `report.json` written. `batch_record()` runs unconditionally from `build()` (`:1552`) and the header (`:140-142`) says a missing file or directory is "counted, never fatal"; a `TypeError` is neither a `Fail` (exit 2) nor tolerated. The `grader_version` string is read verbatim from any `grade.json` on disk (`:1070-1074`), so one pre-release or prefixed grader build in a batch kills every section of the report, decisions included.
**Why This Matters:** An informational table must never block the decision report. The grader has shipped 1.2.11 → 1.2.13 inside this cycle; a `-dev`/`-rc` or `v`-prefixed build landing in one run directory is a realistic input.
**Required Fix:** Use a type-stable key, e.g. `[(0, int(p)) if p.isdigit() else (1, p) for p in parts]`, with `"n/a"` last; or sort plain strings. Wrap the tally build so any exception degrades to `"n/a"` with a status note rather than propagating. Add an AR case with `1.2.0` and `1.2.0-rc1` in one batch.

---

## Observations

### 1. Security — the batch record walks a directory named by an unvalidated row field

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-report.py:1054` — `ad = os.path.join(d, r["arm"])` uses the row's `arm` string as a path component. `load_rows()` (`:328-367`) only requires `arm` to be a non-empty string; the arm grammar `^[a-z][a-z0-9_]{0,63}$` is enforced by `ablation-row.sh --validate`, which the report never runs. `batch_record()` iterates every row of the batch, including rows `_classify` has already listed as "arm … is not run by the suite".
**File:** `head/evals/harness/ablation-report.py:1054`, `:1057-1058` (`os.listdir`), `:1066-1074` (`grade.json` open)
**Suggestion:** Reproduced: a row with `"arm": "/tmp/r26evil"` makes the report `listdir` that absolute path (`os.path.join` discards `d`) and read `/tmp/r26evil/rc-01-t1/grade.json`; its `grader_version` (`9.9.9`) is printed in the batch record. A `../`-relative arm does the same. Impact is limited to reading one JSON string field from an operator-chosen location (CWE-22, read-only), but the report should apply the arm grammar in `load_rows()` (or skip rows whose arm is not in the suite) before building paths.
**Benefit:** Closes the only place the report turns row content into a filesystem path.

### 2. Methodology — the single-task zero-variance pair is flagged for the catch rate only

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-report.py:634-635` — `degenerate` requires `metric == CATCH`; a `hidden_test_pass_rate` comparison with exactly one paired build task has exactly one diff, so `bootstrap()` returns `lo == hi == d` (zero variance by construction, the same property the PR uses to disqualify the catch-rate case), yet it is read as `tested`: H1 is established on `lo > 0` and A4 `holds` on `hi < 0` from a single task. The bats comment at `head/evals/tests/ablation-report.bats:429` asserts this is intended ("a build primary is never degenerate").
**Suggestion:** Either extend the degenerate read to any comparison with `n_tasks == 1` and `n == 1` (one diff), or state in the header and Method section why a one-task pass-rate interval is admissible when a one-task rate-fallback catch interval is not. A suite v3 with one build task would otherwise decide A4 on one number.
**Benefit:** Consistent inferential rule; avoids a one-task "A4 holds".

### 3. Complexity — `batch_record` is 93 lines

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-report.py:992-1084` — one function reads STATUS.json, tallies rerowed/rerun, lists run directories and reads grade.json. `SIMPLICITY[shrink]`: split into `read_status(path)` and `grader_tally(dir, rows)`; the TypeError in Changes Required §2 is easier to contain in a 20-line helper. `render_per_arm` (`:1243-1302`, 60 lines) is moved code and is not counted here. `build()` (`:1379-1637`) is pre-existing and shrank in this PR.
**Benefit:** Keeps the "never fatal" promise checkable per helper.

### 4. Documentation — no CHANGELOG or README change in the diff

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-report.py:173` — `VERSION = "1.2.0"` and the row writer bumps to 1.2, with `--suite-version` as a new CLI flag and `report.json` gaining `primary_suite_version`, `by_suite_version`, `sensitivity.h1/a4`, `budget_matched`, `batches`, `arms.<arm>.precision`, but the change contains no CHANGELOG entry and no suite README update. The PR description lists CHANGELOG and README commits that are not in `pr/head.diff`.
**Suggestion:** Include the CHANGELOG entry for the two row fields and the report 1.1.0/1.2.0 items in the same change, or state where it landed.

### 5. Small items

- **LOW** (confidence: high) `head/evals/harness/ablation-report.py:931` — a suite without `a4_no_gates` yields JSON `a4.state: "no_arm"` (undocumented in the header's state list at `:120-123`) while the line still reads "A4 sensitivity: fails — harden tasks before acting on other arms". "No arm" is not "fails"; print "A4 sensitivity: no arm a4_no_gates in the suite" and document the state.
- **LOW** (confidence: high) `head/evals/harness/ablation-report.py:888` — `read_text` for `inconclusive_by_degradation` renders `remaining pairs no pair (n = 0 tasks)` when every pair dropped; branch on `p["n"] == 0`.
- **LOW** (confidence: high) `head/evals/harness/ablation-report.py:986` — `a0_cost_sum_mean` and the overwritten `a1_cost_mean` are added to the `budget_matched` JSON only when the section is available, and `label` is always present; neither appears in the header's documented shape (`:63-65`, `:146-148`). Emit both keys as `null` in the unavailable case and document them.
- **LOW** (confidence: high) `head/evals/tests/ablation-report.bats:290` — AR-20 validates every planted scenario except `present`; the set at `:25` builds it. Add `present` to the loop (it validates: 90 rows).
- **LOW** (confidence: medium) `head/evals/tests/ablation-report.bats:487`, `:498` — the expected strings `1.0 2.222222 27 27` and `1.0 3.0 0.875 10.0 …` depend on jq ≥ 1.7 preserving the `1.0`/`3.0`/`10.0` literals through `"\(.x)"`; on jq 1.6 (this host) they render `1`, `3`, `10` and AR-33/34 fail while the JSON is correct. Compare with `jq -e '.x == 1.0'` or `tojson`-free numeric tests so the suite is jq-version independent.

---

## Adversarial review triage

Envelope `grimoires/loa/a2a/sprint-1/adversarial-review.json`: two voices (gpt-5.5-pro via codex-headless, claude-headless), status reviewed, degraded false, consensus, `rejected_count: 0`.

| Dissent | Verdict | Where it landed |
|---|---|---|
| DISS-001 (BLOCKING) grader_versions sort TypeError | Confirmed by reproduction | Changes Required §2 |
| DISS-C-002 (ADVISORY) same defect, line anchor | Confirmed (merged with DISS-001) | Changes Required §2 |
| DISS-C-001 (BLOCKING) `version_key` not total; non-numeric strings become primary | Confirmed by reproduction; the 2-with-2.1 case is a silent pool, not the mis-blaming error the voice predicted | Changes Required §1 |
| DISS-C-003 (ADVISORY) `budget_matched` None-safety | Not adopted: `mean([])` cannot occur (the union branch runs only when every vector is `ids`/`cap`, whose length is `task_defects ≥ 1`); `catch_task_score` never returns `None` on a valid row (`_classify` requires a numeric catch rate or `cap_failure`); `f3`/`u3`/`usd` all render `None` as `n/a` (`:214-219`, `:1098`). | — |

## Rejected dissent payloads

None: `metadata.rejected_summary` is empty and `adversarial-rejected-review.jsonl` holds 0 rows.

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| review the pull request, report each defect it introduces with the file and line it sits on | Pass | Findings above cite `head/<path>:<line>` |
| give a merge verdict | Pass | CHANGES_REQUIRED (two HIGH) |
| Row writer 1.2 carries `defects_missed` (bd-yz1rd) | Pass | `head/evals/harness/ablation-row.sh:410-413`; `--validate` `:165-168`; bats `:407-431`, `:468-479` |
| Row writer 1.2 carries `regressions_final_green` (bd-m0hw7) | Pass | `head/evals/harness/ablation-row.sh:414`; `--validate` `:169-170`; bats `:433-451` |
| Rows of different suite_version never pooled | Fail | Changes Required §1 (non-integral and mixed-type versions pool silently) |
| Batch record "never fatal" | Fail | Changes Required §2 |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [ ] Input validation at the trust boundary — row `arm` reaches `os.path.join` unvalidated (Observations §1)
- [x] Symlinked STATUS.json / grade.json / run dirs are refused (`:1013`, `:1057`, `:1068`)
- [x] Read-only: the report never writes beside the manifests (AR-32 asserts it)
- [x] Error messages leak nothing beyond operator paths already on the command line

---

## Code Quality Summary

**Strengths:**
- The partition is applied once and every per-version figure flows from one `analyse()`; the main sections and the per-version sections share renderers, so they cannot drift.
- The degenerate flag is computed where the interval is computed and consumed by `usable()` in both the decision and the H1 read.
- Fixture scenarios document every planted number in the header; the bats cases assert both the JSON and the Markdown.
- Row-writer jq is defensive at every null/shape boundary and the validate rules are additive (legacy rows pass).

**Areas for Improvement:**
- `version_key` and the grader-version sort both fall into Python's "a lambda that works for the fixture values" trap; both need total, type-stable keys.
- Apply the row grammar in the report's loader so the report does not rely on rows having been validated upstream.

---

## Next Steps

1. Fix Changes Required §1 and §2 with the regression cases named there.
2. Re-run `bats evals/tests/ablation-report.bats` and `bats evals/tests/ablation-row.bats` against the real suite and fixture runs; paste the results into `reviewer.md` with an `## AC Verification` section.
3. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":4,"low":5},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T12:50:00Z"} -->
