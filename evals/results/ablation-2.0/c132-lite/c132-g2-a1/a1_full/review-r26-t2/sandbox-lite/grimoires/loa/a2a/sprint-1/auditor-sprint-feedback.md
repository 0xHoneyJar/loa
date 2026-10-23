# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md (the pull request in `pr/`: sprint-262 — ablation-row.sh 1.2 carries defects_missed and regressions_final_green; ablation-report.py 1.2.0)
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Review gate:** grimoires/loa/a2a/sprint-1/engineer-feedback.md — CHANGES_REQUIRED (0 critical / 1 high / 3 medium / 6 low, excluded 0). Phase 0 asks for an approved review before the audit; the task runs the audit on this sprint regardless, so the prerequisite is recorded as not met and the audit proceeds on the PR as the sprint's definition.

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

The change is a local, read-only analysis tool (`ablation-report.py` 1.2.0) plus two additive row fields in the jq row writer (`ablation-row.sh` 1.2), with bats coverage and a fixture generator. The decision-bearing logic (suite_version partition, the H1/A4 read states, the degenerate-pair rule, the row writer fields) is sound and well tested: I ran every planted scenario against a stand-in suite file and the AR-23 … AR-35 figures came out as asserted. The row writer additions are typed defensively in jq and validated under `--validate`; the report refuses symlinked STATUS.json, run directories and grade.json.

What blocks is robustness at the trust boundary the sprint added. The new batch record reads `grader_version` strings from every run directory's `grade.json`, a file that sits beside the agent-under-test's workspace, and sorts them with a key that mixes `int` and `str`. One non-numeric version segment beside a numeric one raises an uncaught `TypeError`; the report dies with a traceback, writes neither `report.md` nor the JSON twin, and exits 1 — the code the header reserves for "--partial and no decidable comparison (the report is still written)". I reproduced it in situ (fixture `present` plus one `grade.json` reading `1.2.11-rc1`) and through a second path (a row arm pointing outside the batch tree). The same class recurs on a row's `suite_version`: an unvalidated string is interpolated raw into markdown headings and bold lines (a planted value forges `**H1: established**` eleven times in `report.md` while the JSON twin reads the truth) and a Unicode digit crashes `version_order()`. Three medium findings from the review are confirmed by execution (guard-before-no_pair makes `--partial` exit 0 with zero pairs; the string `"2.0"` becomes its own primary version; rerun directories double-count in the grader tally). Eight low findings follow, two of them new: an arm path escapes the batch directory on the read-only walk, and the new AR-33/AR-34 assertions fail under jq 1.6 because they compare integral floats as `1.0`.

The review's trailer excludes no finding, so there is nothing to confirm or re-tally (`excluded_confirmed` 0). Both dissent voices completed; the envelope is not degraded; no payload was rejected.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 4 |
| Low | 8 |

**Verification record.** Stand-in suite (`/tmp/audit/suite.json`: the nine arm ids the tests name, `rules.exclusion.inconclusive_above_share 0.25`, threshold 0.03, cost 15 %, 1000 resamples) because `evals/suites/ablation-2.0.yaml` is outside `pr/`. All eleven fixture scenarios exit 0. `bats evals/tests/ablation-report.bats` on a copy of `pr/head/evals`: 27 pass, 8 fail — AR-1, AR-2, AR-6, AR-12, AR-16, AR-18 fail on stand-in-suite content (arm task_types, rules text, suite name) and are not attributed to the PR; AR-33 and AR-34 fail on the jq float rendering described in LOW-007. `ablation-row.bats` needs `fixtures/ablation-runs/`, which is outside `pr/`: not executable here; its new cases were read against the jq at `head/evals/harness/ablation-row.sh:410-414`. No CI, formatter or type-check record was supplied. Documentation-coherence reports (`grimoires/loa/a2a/subagent-reports/`) do not exist in this workspace; the header documentation in both scripts is updated in-file; CHANGELOG and README entries named in the commit list are outside the five files in scope.

**Trust model (assumption, stated):** `runs.jsonl`, `MANIFEST.json` and `STATUS.json` are written by the harness (operator trust); `grade.json` is written by the grader into the per-run directory beside the agent-under-test's tree (semi-trusted: an agent that writes there before grading, or a hand-edited file, reaches the report); the suite file and CLI arguments are operator-owned.

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] The batch record's grader-version sort aborts the whole report on a non-numeric version segment (uncaught exception, exit code collides with the documented exit 1)

**Severity:** HIGH | **Confidence:** high
**File:** `head/evals/harness/ablation-report.py:1081-1082` (sort key); `:1069-1080` (the per-directory read whose `except` does not cover the sort); `:1673-1680` (`main()` catches `Fail` only)
**Criterion:** SEC-AV Availability/Resilience; CQ-EH Error Handling

**Issue:**
```python
e["grader_versions"] = dict(sorted(gv.items(), key=lambda kv: (
    kv[0] == "n/a", [int(p) if p.isdigit() else p for p in re.split(r"[.]", kv[0])])))
```
`grader_version` is `str(g["grader_version"])` from disk (`:1077`), validated nowhere. Two versions whose dotted segments differ in kind at one position (`1.2.11` beside `1.2.11-rc1`, `1.3` beside `dev`, or any version beside a value read from a directory the arm walk reaches) compare `int` to `str` inside `sorted()`:
```
TypeError: '<' not supported between instances of 'str' and 'int'
```
A segment such as `²` passes `str.isdigit()` and fails `int()` with `ValueError`. Neither is a `Fail`, so `main()` does not map it to exit 2: the interpreter prints a traceback and exits 1, and `write_out` never runs.

**Reproduced:** fixture `present` with `manifests/pr-2/a0_bare/rc-01-t3/grade.json` set to `{"grader_version": "1.2.11-rc1"}` → traceback, `exit=1`, `report.md` not written. Also reached through LOW-001's path (a row arm of `../../../outside` whose `grade.json` read `OUTSIDE`).

**Impact:** The header promises the batch record is "reported, never fatal" (`:136-139`). A single pre-release, hand-labelled or planted grader version in one run directory takes down the pre-registered decision report for the whole batch set — no `report.md`, no `--json` twin. Exit 1 is documented as "--partial and no decidable comparison (the report is still written)" (`:157-159`), so a batch driver keying on the exit code reads a crash as a written-but-undecided report. An agent under test with write access to its run directory before grading can trigger it deliberately (CWE-754 at a semi-trusted boundary).

**Fix:**
```python
def _ver_key(s):
    return [(0, int(p)) if re.fullmatch(r"[0-9]+", p) else (1, p) for p in s.split(".")]
e["grader_versions"] = dict(sorted(gv.items(), key=lambda kv: (kv[0] == "n/a", _ver_key(kv[0]))))
```
Wrap the whole `batch_record()` call in `build()` so any exception degrades to a `status_note` on the record (the section is presentation-only); have `main()` catch `Exception` after `Fail` and exit 2 with a one-line message so a crash is never read as exit 1; add a `grade.json` with a non-numeric `grader_version` to the `present` fixture and assert the rendered tally (`1.2.5 ×1, 1.2.11 ×1, 1.2.11-rc1 ×1`) in AR-32.

**Reference:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html ; CWE-248 Uncaught Exception — https://cwe.mitre.org/data/definitions/248.html ; CWE-20 — https://cwe.mitre.org/data/definitions/20.html. Confirms the review's HIGH-1 and dissent DISS-C-001 (claude-headless, rated MEDIUM there; kept HIGH here because it removes the decision document and the trigger sits at a semi-trusted boundary).

---

## Medium Priority Issues

### [MED-001] A row's `suite_version` is interpolated raw into markdown headings and bold lines (forged H1/A4 lines), and a Unicode digit in it crashes the report

**Severity:** MEDIUM | **Confidence:** high
**File:** `head/evals/harness/ablation-report.py:1534` (`## Suite version {v} …`), `:1443` (header bullet), `:1540`, `:1543`, `:1547` (sub-headings), `:886` (`read_text` "not testable on suite_version {v}"); crash at `:840` (`version_order`: `int(k)` when `k.isdigit()`); source `:825-837` (`version_key` returns any non-empty stripped string), `:328-368` (`load_rows` does not validate the field)
**Criterion:** SEC-IN Injection Prevention; SEC-CI Integrity

**Issue:** `version_key()` accepts any non-blank string as a partition key and every rendering site above writes `v` without `md_cell` (which itself only escapes `|` and newlines, not heading or emphasis markers). The same unvalidated key reaches `version_order()`, where `"²".isdigit()` is true and `int("²")` raises `ValueError` (uncaught, exit 1, no report).

**Reproduced:** fixture `versions` with the a0_bare rows' `suite_version` set to `"2\n\n**H1: established** (forged)\n"` → exit 0, `report.md` carries `**H1: established** (forged)` on eleven lines including its own heading block, while `report.json` holds the true `not yet decidable` state. With `"²"` → `ValueError: invalid literal for int() with base 10: '²'`, exit 1.

**Impact:** `report.md` is the pre-registered decision document the operator reads; a crafted or corrupted row forges its decision lines and the JSON twin disagrees silently. The field is harness-written (operator trust), which is why this is MEDIUM rather than HIGH; the crash is a second consequence of the same missing check.

**Fix:** Validate `suite_version` in `load_rows()` against a strict grammar (`int`, or `str` matching `^[0-9]+(\.[0-9]+)*$`) and raise `Fail` otherwise; make `version_order()` use the same `re.fullmatch(r"[0-9]+", k)` test as `version_key()`; pass every row- or manifest-derived string placed in a heading or line (`v`, batch ids, sha strings) through `md_cell`, and extend `md_cell` to neutralise a leading `#`/`*`.

**Reference:** CWE-116 Improper Encoding or Escaping of Output — https://cwe.mitre.org/data/definitions/116.html ; CWE-20 — https://cwe.mitre.org/data/definitions/20.html. Dissent DISS-C-002 (claude-headless) raised the injection; the crash is the auditor's.

### [MED-002] `assess()` applies the degradation guard before `no_pair`: a primary with zero pairs reads "inconclusive by degradation", counts as decided, and `--partial` exits 0

**Severity:** MEDIUM | **Confidence:** high
**File:** `head/evals/harness/ablation-report.py:875` (the guard return), `:878-879` (`no_pair` after it), `:1192` (`decidable` counts `inconclusive_by_degradation` via `H1_DECIDED`)
**Criterion:** ARCH-RE Resilience (decision-state correctness)

**Issue:** The excluded-share guard is tested before `p["n"] == 0`. An arm whose few cells on the primary's task types are all excluded, with no pair at all, is read as a degradation verdict about a comparison that was never made.

**Reproduced:** fixture `degraded` restricted to its a1_full rows (all 12 marked degraded, no a0_bare rows) with `--partial` → exit 0; JSON `h1.state = inconclusive_by_degradation`, `h1.comparisons[].n = [0, 0]`, reads `["not_testable", "inconclusive_by_degradation"]`.

**Impact:** A batch driver keying on `--partial`'s exit code, or an operator reading the H1 line, is told a degradation outcome for a comparison with no pair; the early-batch "not yet decidable (no pair)" state the sprint introduced (bd-wqbz3) is bypassed.

**Fix:** In `assess()`, return `no_pair` when `p["n"] == 0` before the share guard (or require at least one pair for the guard to classify), and add a fixture asserting `--partial` exits 1 on an all-excluded single arm.

**Reference:** CWE-670 Always-Incorrect Control Flow Implementation — https://cwe.mitre.org/data/definitions/670.html. Confirms the review's MEDIUM 3.

### [MED-003] `version_key()` does not normalise the string `"2.0"`: it becomes its own never-pooled version and, ranking above every integer, the primary

**Severity:** MEDIUM | **Confidence:** high
**File:** `head/evals/harness/ablation-report.py:825-837` (`version_key`: only digit-only strings and integral floats normalise), `:840` (`version_order` ranks non-digit keys first), `:857` (`--suite-version` gets the same partial normalisation)
**Criterion:** CQ-TC/SEC-IV (input normalisation at the partition boundary)

**Issue:** The docstring says `1, 1.0 and "1" are one version`, but the string `"1.0"` stays `"1.0"`; the row writer accepts suite_version as number or string (`head/evals/harness/ablation-row.sh:148` validate), so a batch rowed with the string form splits from the integer form. `version_order()` puts non-numeric keys after numeric ones in ascending order, and `partition()` picks the primary with `max(...)`, so the string slice becomes the main sections.

**Reproduced:** fixture `versions` with the a0_bare rows' `suite_version` set to `"2.0"` → exit 0, `by_suite_version` keys `["1", "2", "2.0"]`, `primary_suite_version = "2.0"`, main H1 line `not yet decidable (no pair)` (the a1_full rows are in `"2"`). `--suite-version 2.0` against integer rows exits 2 ("no row has that suite_version"); a non-integer float such as `1.5` returns `None` and is read as an absent version.

**Impact:** The main sections and the exit code silently describe the wrong slice of rows; the "never pooled" guarantee is honoured, but the primary is wrong.

**Fix:** Normalise any `^\d+(\.0+)?$` string to its integer text, treat a non-integer float as its own key, and apply the same function to `--suite-version`; a string that normalises to nothing should `Fail` (ties to MED-001's grammar).

**Reference:** CWE-20 — https://cwe.mitre.org/data/definitions/20.html. Confirms the review's MEDIUM 2.

### [MED-004] Rerun directories double-count in the grader-version tally

**Severity:** MEDIUM | **Confidence:** high
**File:** `head/evals/harness/ablation-report.py:1063-1066` (match on task and trial only; the `-r<k>` group is ignored)
**Criterion:** CQ-TC (figure correctness)

**Issue:** `GRADE_DIR` captures the rerun suffix but the match keeps every directory with the row's task and trial, so one row contributes the `grade.json` of `<task>-t<n>` and of every `<task>-t<n>-r<k>`.

**Reproduced:** fixture `present` plus `manifests/pr-2/a0_bare/rc-01-t1-r2/grade.json` (`1.2.11`) beside the existing `rc-01-t1` (`1.2.5`) → `grader_versions {"1.2.11": 2, "1.2.5": 1, "n/a": 1}` for 18 rows with 15 "no run dir": four directories tallied for three rows.

**Impact:** The tally the README's regression-check recipe reads (which grader graded the rows) counts leftover directories, not rows; a superseded run's grader version is reported as the row's. Informational section, no decision reads it — MEDIUM on the lower end.

**Fix:** Select one directory per row — `-r<attempts>` when the row's `attempts > 1`, else the bare `-t<n>`; count rows without a match in `run_dirs_missing` as today; add the rerun directory to the `present` fixture and assert one version per row.

**Reference:** CWE-682 Incorrect Calculation — https://cwe.mitre.org/data/definitions/682.html. Confirms the review's MEDIUM 1.

---

## Low Priority Issues

### [LOW-001] The row's `arm` is joined onto the batch directory with no grammar check; listed rows are walked too, so the read-only tally leaves the batch tree
- **File:** `head/evals/harness/ablation-report.py:1054` (`os.path.join(d, r["arm"])`), `:1057-1059` (listdir), `:1070-1077` (open grade.json); `load_rows` `:355-357` checks only non-empty `str`; `batch_record` takes every row of the batch (`:997`), including rows `_classify` listed as "arm … is not run by the suite" (`:509-510`)
- **Issue:** The arm grammar `^[a-z][a-z0-9_]{0,63}$` is enforced only by `ablation-row.sh --validate`. **Reproduced:** one `present` row with `arm = "../../../outside"` and `/tmp/audit/outside/rc-01-t1/grade.json` reading `9.9.9` → `grader_versions {"1.2.11": 1, "9.9.9": 1, "n/a": 1}`, the row listed as "not run by the suite" yet walked.
- **Impact:** Read-only; only a `grader_version` string from an arbitrary readable directory lands in the report (and, with a non-numeric value, triggers HIGH-001). Symlink checks are check-then-open and do not cover parent components.
- **Fix:** Reject arms failing the grammar in `load_rows()` (or skip them in `batch_record()`), restrict the walk to rows `_classify` accepted, and check `os.path.realpath(ad)` is under `d`.
- **Reference:** CWE-22 Path Traversal — https://cwe.mitre.org/data/definitions/22.html ; CWE-367 TOCTOU — https://cwe.mitre.org/data/definitions/367.html. Review LOW 4.1; dissent DISS-C-004.

### [LOW-002] STATUS.json `trials_planned` is rendered raw into the batch table cell
- **File:** `head/evals/harness/ablation-report.py:1156` (`{e['trials_planned'] if … else 'n/a'}` with no `md_cell` or type check); source `:1030` (`trials_planned=st.get("trials_planned")`)
- **Issue:** The neighbouring cells (`state`, `extra_models`, `cuts`, `paused_arms`, `grader versions`) pass through `md_cell`; this one does not. **Reproduced:** `trials_planned = "20 | forged | x"` → the `pr-2` row gains two columns and every cell after it shifts.
- **Fix:** Render only when `isinstance(x, int) and not isinstance(x, bool)`, else `n/a`.
- **Reference:** CWE-116 — https://cwe.mitre.org/data/definitions/116.html. Dissent DISS-C-003.

### [LOW-003] `budget_matched()` falls back to the rate for a task when any a0_bare trial lacks per-defect ids; the header and legend say "a task whose a0 rows carry none"
- **File:** `head/evals/harness/ablation-report.py:959` (`all(vv is not None and how in ("ids", "cap") …)`); documented at `:146-147` and the legend `:1095-1096`
- **Issue:** A task mixing row-writer 1.1 and 1.2 rows discards the union of the trials that do carry ids.
- **Fix:** Union the ids-bearing trials and fall back only for the rest, or state the all-or-nothing rule in both texts. Review LOW 4.2; dissent DISS-C-005's IndexError on this line is **not reachable** (every vector of one task has length `task_defects[task]`, `:541-553`).

### [LOW-004] The sensitivity H1/A4 guard counts cap-failure exclusions as degradation
- **File:** `head/evals/harness/ablation-report.py:1191` (the third Analysis is built `cap_excluded=True`), `:522` (cap failures excluded as cells), `:871-873` (`assess()` counts every excluded cell in the share)
- **Issue:** The sensitivity line can read "inconclusive by degradation (… excluded share …)" when the share comes from the figure's own cap-failure treatment.
- **Fix:** Compute the guard on the main Analysis's cells for the sensitivity read, or label the share's source in `read_text`. Review LOW 4.3.

### [LOW-005] A null `false_positives` counts as 0 flagged regions: precision 1.0 for an arm that never recorded the field, with no signal in the JSON
- **File:** `head/evals/harness/ablation-report.py:776` (`f = … else 0`); documented at `:142`
- **Fix:** Add a `false_positive_rows` count beside `precision_rows`, or null the precision when no row carries a numeric `false_positives`. Review LOW 4.4.

### [LOW-006] AR-20 validates every planted scenario against `ablation-row.sh --validate` except the new `present` one
- **File:** `head/evals/tests/ablation-report.bats:290`
- **Issue:** `present` is the only scenario that sets `false_positives` on review rows and ships the STATUS.json / run-directory extras; it is built in `setup_file` (`:25`) but not validated.
- **Fix:** Add `present` to the AR-20 list. Review LOW 4.5.

### [LOW-007] AR-33 and AR-34 compare integral floats as `1.0` / `3.0` / `10.0` through `jq -r`; they fail under jq 1.6
- **File:** `head/evals/tests/ablation-report.bats:487` (`"1.0 2.222222 27 27"`), `:498` (`"1.0 3.0 0.875 10.0 -0.125 defect union"`)
- **Issue:** Python writes `1.0`; jq 1.6 prints it as `1`, jq 1.7+ preserves the literal. **Reproduced:** both tests fail here (jq-1.6: `1 2.222222 27 27`, `1 3 0.875 10 -0.125 defect union`) while the JSON itself is correct. The older assertions in the file avoid integral floats, so this is new fragility; whether CI pins jq ≥ 1.7 is not visible from `pr/`.
- **Fix:** Compare with `jq` arithmetic (`.precision == 1`) or `tostring`-normalise on both sides; or pin and document the jq version the suite needs.
- **Reference:** CWE-1357 Reliance on Insufficiently Trustworthy Component (environment-dependent test) — https://cwe.mitre.org/data/definitions/1357.html.

### [LOW-008] `batch_record()` is ~90 lines at four levels of nesting
- **File:** `head/evals/harness/ablation-report.py:992-1084`
- **Fix:** Split the STATUS.json read and the grader-version walk into two helpers; wrapping each in its own `try` also delivers the "never fatal" promise of HIGH-001. Review LOW 4.6.

---

## Observations (not tallied)

- `--help` prints `sed -n '2,101p'` (`head/evals/harness/ablation-row.sh:123`), which stops one line before the "Tested by" paragraph; the base did the same at `2,84p`, so the truncation is not introduced here.
- Rows whose batch has no manifest are listed and absent from the batch record (`trials_rowed` counts manifest batches only) — consistent with the header; noted for the reader of the record.
- `status_file` in the JSON (`:1024`) carries the filesystem path of STATUS.json; `provenance.batches[].manifest` already does the same, so no new disclosure.
- The dissent's DISS-C-005 IndexError is dismissed on evidence (see LOW-003); its `int()` digit-length remark is an exotic sub-case of MED-001's missing grammar.

## Rejected dissent payloads

- None: `metadata.rejected_summary` is empty, `rejected_count` 0, `rejected_sidecars` empty and no `adversarial-rejected-audit*.jsonl` exists beside `grimoires/loa/a2a/sprint-1/adversarial-audit.json`. Both voices completed (`model_attempts ["gpt-5.5-pro:clean"]`, companion `claude-headless` succeeded, `hallucination_filter.downgraded` 0, `metadata.degraded` false — not a DEGRADED_SECURITY_REVIEW). All five envelope findings are the companion's; the primary returned none. Mapping: DISS-C-001 → HIGH-001, DISS-C-002 → MED-001, DISS-C-003 → LOW-002, DISS-C-004 → LOW-001, DISS-C-005 → LOW-003 (IndexError rejected on evidence, remainder absorbed in MED-001).

## Review demotions

The review trailer counts `excluded: 0`; nothing to confirm. `excluded_confirmed: 0`.

---

## Rubric Scores

| Category | Score | Dimensions |
|----------|-------|------------|
| Security | 3.2/5 | IV:3 AZ:5 (n/a, local tool) CI:3 IN:3 AV:2 |
| Architecture | 4.0/5 | MO:4 SC:4 RE:3 CX:4 ST:5 |
| Code Quality | 3.6/5 | RD:4 TC:4 EH:2 TS:4 DC:4 |
| DevOps | 3.0/5 | AU:3 OB:4 RC:3 AC:n/a DS:2 |
| Blockchain | n/a | — |

## Security Checklist for This Sprint

- [x] No hardcoded secrets added (fixture values are planted placeholders)
- [ ] Input validation at the new boundaries — `grader_version`, `suite_version`, `arm`, `trials_planned` reach sorts, headings, paths and table cells unvalidated (HIGH-001, MED-001, LOW-001, LOW-002)
- [x] Authentication/authorization — n/a, local read-only tool
- [ ] No injection — markdown heading/emphasis injection via `suite_version` (MED-001); table-cell injection via `trials_planned` (LOW-002)
- [ ] Error handling doesn't crash or mislead — uncaught `TypeError`/`ValueError` exit 1 and collide with the documented partial exit (HIGH-001, MED-001)
- [x] Symlink refusal on STATUS.json, run directories and grade.json; manifests walk with `followlinks=False`
- [ ] Tests cover security paths — no fixture for a non-numeric grader version, a hostile `suite_version`, or an out-of-grammar arm; two new assertions are jq-version dependent (LOW-007)

## Positive Findings

- The read states form one explicit state machine (`assess()` → `h1a4()`), documented in the header and `## Method`, each with a planted fixture; the degenerate-pair rule is threaded through one predicate (`usable()`).
- The row writer fields are additive, typed in jq, null on every non-applicable shape, and validated under `--validate` with a legacy-row test.
- The fixture generator's planted numbers agree with every AR-23 … AR-35 assertion I recomputed and with the stand-in run.
- The report never writes beside the manifests (AR-32 asserts it; the walk is listdir/open only).

## Next Steps

1. Fix HIGH-001 (type-homogeneous sort key; wrap `batch_record()`; `main()` catches `Exception` → exit 2) and add the non-numeric grader fixture to AR-32.
2. Add a `suite_version` grammar in `load_rows()` and route every heading/line string through `md_cell` (MED-001, MED-003); return `no_pair` before the guard (MED-002); one run directory per row (MED-004).
3. Address the low items or record the accepted behaviour in the header; make AR-33/AR-34 jq-version independent.
4. Run `bats evals/tests/ablation-report.bats evals/tests/ablation-row.bats` against the real suite and record the result (and the CI fast gate) in `grimoires/loa/a2a/sprint-1/reviewer.md`.
5. Re-run `/review-sprint sprint-1`, then `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":4,"low":8},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-22T08:27:00Z"} -->
