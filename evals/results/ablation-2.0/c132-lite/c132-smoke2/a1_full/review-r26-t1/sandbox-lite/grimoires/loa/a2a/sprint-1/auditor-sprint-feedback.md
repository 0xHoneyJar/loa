# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md (Task 1.1: the change in `pr/head.diff`)
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Review:** grimoires/loa/a2a/sprint-1/engineer-feedback.md (CHANGES REQUIRED, 1 high / 2 medium / 8 low, excluded 0)

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

The change is sprint-262: row writer `ablation-row.sh` 1.2 (two additive optional fields, `defects_missed` and
`regressions_final_green`, with `--validate` clauses) and `ablation-report.py` 1.2.0 (the suite_version partition,
the H1/A4 read states, the degenerate single-task pair, and four presentation items: sensitivity H1/A4 lines, the
batch record, precision per arm, the budget-matched baseline), plus eleven fixture scenarios and tests AR-23 … AR-35
and five row tests. Scope: the five files of `pr/head.diff`.

Security posture: the report is an offline, read-only analysis tool (stdlib only; `yq` unchanged; `write_out`
refuses symlinks; `STATUS.json`, `MANIFEST.json` and `grade.json` symlinks are refused). The new attack surface is
the batch record, which for the first time makes the report walk the filesystem beside the manifests and read
`STATUS.json` and per-run `grade.json` files, both of which it treats as data it never validates. Three defects
follow from that surface: an unguarded sort over `grade.json` strings that aborts the whole report (HIGH, the only
blocker), markdown injection through unescaped `STATUS.json` values into the human-read decision artifact (MEDIUM),
and a row `arm` joined into a path without the grammar the row writer enforces (LOW, read-only, bounded). Two
further correctness defects sit in the new suite_version partition and the grader-version tally (MEDIUM each). The
row writer's jq is sound: every validate shape I tried behaves as documented, all eleven fixture scenarios validate
under the head writer, and `bash -n` passes.

Every finding below was reproduced in this workspace against the head files with the generated fixtures and a
synthetic suite of the same arm and rules shape (the repository's `evals/suites/ablation-2.0.yaml` and the bats
run-dir fixtures are not present here, so the two bats suites could not be executed; the planted figures the
tests assert were reproduced directly).

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 3 |
| Low | 9 |

Phase 0 note: `engineer-feedback.md` reads CHANGES REQUIRED, not "All good". The task instructions for this
evaluation direct the audit to run regardless and waive the a2a prerequisites, so the audit proceeded; the review's
blocker is confirmed below as HIGH-001 rather than assumed fixed.

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] A single grade.json grader_version string aborts the entire report (uncaught TypeError in the batch record)

**Severity:** HIGH
**Confidence:** high (reproduced)
**File:** `head/evals/harness/ablation-report.py:1081-1082` (called from `build()` with no guard; the header's
"never fatal" promise at `head/evals/harness/ablation-report.py:139` and `:994`)
**Issue:** The grader_versions tally is sorted with

```python
e["grader_versions"] = dict(sorted(gv.items(), key=lambda kv: (
    kv[0] == "n/a", [int(p) if p.isdigit() else p for p in re.split(r"[.]", kv[0])])))
```

The key mixes `int` and `str` list elements. Whenever two `grader_version` strings differ in token type at the
first unequal position (`"1.2.11"` beside `"1.2.11-rc.1"`, `"1.2.5"` beside `"git-abc1234"`, `"2.0.0"` beside
`"2.0.0-rc.5"`, the repository's own release-tag shape), Python raises
`TypeError: '<' not supported between instances of 'str' and 'int'` inside `sorted()`. Nothing catches it: the
`try/except (OSError, ValueError)` at `:1073-1079` wraps only the file read. `build()` dies with a traceback,
exit 1 (not the documented exit 2), and neither `--out` nor `--json` is written.
**PoC:**
```
cp -R fx/present a; mkdir -p a/manifests/pr-2/a0_bare/rc-01-t3
echo '{"grader_version":"1.2.11-rc.1"}' > a/manifests/pr-2/a0_bare/rc-01-t3/grade.json
python3 -I ablation-report.py --runs a/runs.jsonl --manifests a/manifests --suite suite.json --out a.md --json a.json
#   File "ablation-report.py", line 1081, in batch_record
#   TypeError: '<' not supported between instances of 'str' and 'int'   (exit 1; a.md and a.json absent)
```
**Impact:** `grade.json` lives inside per-run directories (the agent-under-test's working area) and is read with
no validation. One file, benign or planted, denies the cycle its decision artifact: no Decisions, no H1/A4, no
JSON twin, for every suite version. Recovery means editing evidence files inside run directories. An
informational section the header itself labels "never fatal" must not be able to do this. CWE-248 (Uncaught
Exception, https://cwe.mitre.org/data/definitions/248.html); CWE-754 (Improper Check for Unusual or Exceptional
Conditions, https://cwe.mitre.org/data/definitions/754.html).
**Fix:** A type-stable total order, and a guard around the whole walk so no `grade.json` content can be fatal:
```python
def _ver_key(s):
    return [(0, int(p), "") if p.isdigit() else (1, 0, p) for p in s.split(".")]

e["grader_versions"] = dict(sorted(gv.items(), key=lambda kv: (kv[0] == "n/a", _ver_key(kv[0]))))
```
Add a run directory with `grader_version: "1.2.11-rc.1"` to `present_scenario()` in `gen-fixtures.py` and assert
the tally order in AR-32. Both dissent voices of the review and the companion voice of this audit flagged the same
line independently.
**Reference:** CWE-248, CWE-754; the header contract at `:139`.

---

## Medium Priority Issues

### [MED-001] Unescaped STATUS.json values and version strings reach the markdown decision artifact

- **Severity:** MEDIUM — **Confidence:** medium (reproduced; trust context of STATUS.json stated below)
- **File:** `head/evals/harness/ablation-report.py:1156` (`trials_planned` interpolated raw), `:1142` (batch name
  in backticks, unescaped), `:1136` and `:1534` (a suite_version key in a heading, unescaped)
- **Issue:** `render_batches` passes `state`, `extra_models`, `cuts`, `paused_arms` and the grader tally through
  `md_cell`, but `trials_planned` goes straight into the table row as whatever JSON value `STATUS.json` holds:

  ```python
  L(f"| {name} | {md_cell(e['state'] or 'n/a')} | {e['trials_planned'] if e['trials_planned'] is not None else 'n/a'}"
  ```

  A `STATUS.json` of `{"trials_planned": "20 | **INJECTED** |\n## fake heading"}` produced, in my run, a table
  row with an extra bolded cell and a new `## fake heading` line in report.md (`c.md:438-439`), while `state`
  on the same row was correctly escaped (`x\|y`). Likewise a row or manifest `suite_version` string (which
  `ablation-row.sh --validate` accepts, `head/evals/harness/ablation-row.sh:147`) is written into `###
  suite_version {v}` and `## Suite version {v}` headings unescaped. report.md is the artifact a lead reads before
  ruling; a forged row or heading in it is a tampering channel even though the JSON twin carries the raw value.
  [ASSUMPTION] `STATUS.json` is harness-written beside `MANIFEST.json` and the run directories are
  container-executed, so the writer is semi-trusted; the finding stays MEDIUM because the PR itself treats sibling
  values on the same row as untrusted and escapes them, and because the artifact is the decision record.
- **Fix:** Route `trials_planned`, the batch name and the version keys through `md_cell` (and strip backticks from
  the batch name or render it without them); consider an allowlist shape for `trials_planned` (`int` or `n/a`).
- **Reference:** CWE-116 (Improper Encoding or Escaping of Output, https://cwe.mitre.org/data/definitions/116.html);
  CWE-74 (https://cwe.mitre.org/data/definitions/74.html).

### [MED-002] version_key keeps the string "2.0" as its own version and ranks it primary; a non-integer float reads as "no suite_version"

- **Severity:** MEDIUM — **Confidence:** high (reproduced)
- **File:** `head/evals/harness/ablation-report.py:825-836` (`version_key`), `:839-840` (`version_order` ranks every
  non-digit key above every integer), `:861` (`partition` takes the max)
- **Issue:** The docstring says 1, 1.0 and "1" are one version, but `"2.0"` (a string the validator accepts,
  `ablation-row.sh:147`) is not normalised: with one such row among integer-2 rows the report wrote
  `primary_suite_version: "2.0"`, `by_suite_version` keys `["1","2","2.0"]`, and the main sections read one row
  (`H1: not yet decidable (no pair)`, `a0_bare.rows = 1`) while the real version 2 was pushed into a "reported
  separately" section. A float `2.5` maps to `None`, so the report exits 2 with "row … has no suite_version"
  although it has one; `--suite-version 2.0` is refused while `--suite-version 02` works. One quoted version in a
  manifest or task YAML silently takes over the main sections, defeating the "never pooled, primary = highest"
  contract this sprint introduces.
- **Fix:** Normalise once: `try: f = float(s)` → `str(int(f))` when `f.is_integer()`, else the canonical numeric
  text; keep non-numeric strings as they are but never rank them above numeric versions (or refuse them with exit
  2). Apply the same function to `--suite-version`. Add a fixture row with `"suite_version": "2.0"` to AR-23/24.
- **Reference:** CWE-20 (Improper Input Validation, https://cwe.mitre.org/data/definitions/20.html).

### [MED-003] The grader-version tally counts every rerun directory for one row and walks rows the suite does not run

- **Severity:** MEDIUM — **Confidence:** high (reproduced)
- **File:** `head/evals/harness/ablation-report.py:1063-1070` (every directory matching `<task>-t<n>` or
  `<task>-t<n>-r<k>` is appended for the row), `:1000` (`brows` is every row of the batch, listed rows included)
- **Issue:** With both `rc-01-t2/grade.json` (1.2.5) and `rc-01-t2-r2/grade.json` (1.2.11) present, the present
  batch reported `{"1.2.11":1,"1.2.5":2,"n/a":1}` plus `run_dirs_missing: 15` against `trials_rowed: 18` — 19
  tallies for 18 rows, and the stale pre-rerun `grade.json` counted as if it had fed a row. Rows the suite does
  not run (arm not in the suite, "listed, never decided") are still walked and tallied. The batch record is meant
  to name the grader that produced each row; a tally that exceeds the row count is a self-inconsistent record in
  the decision artifact.
- **Fix:** Pick one directory per row (the highest `-r<k>`, else the bare `-t<n>`) and count it once; walk only
  rows that entered a cell.
- **Reference:** Code quality (CQ-EH, RUBRICS.md); the "never fatal / counted" contract at `:139`.

---

## Low Priority Issues

### [LOW-001] A row's arm is joined into a filesystem path without the arm grammar

- **Confidence:** high (reproduced, relative and absolute)
- **File:** `head/evals/harness/ablation-report.py:1054` (`ad = os.path.join(d, r["arm"])`); `:1057-1059` and
  `:1072` refuse symlinks but not the segment itself
- **Issue:** The row writer enforces `^[a-z][a-z0-9_]{0,63}$` on emission (`head/evals/harness/ablation-row.sh:247`)
  and in `--validate` (`:162`); the report never does. A `runs.jsonl` row with arm `../../../outside` or
  `/tmp/audit/outside` made the report list that directory and read `outside/rc-01-t1/grade.json`, whose
  `grader_version` ("9.9.9") then appeared in the batch record — even though the same row was listed as "arm …
  is not run by the suite". Bounded: only directories named `<task_id>-t<trial>[-r<k>]` are considered, only one
  JSON string is read, and `runs.jsonl` is operator-provided; hence LOW.
- **Fix:** Skip (or `Fail`) rows whose arm fails the grammar before building the path, and refuse absolute arms.
- **Reference:** CWE-22 (Path Traversal, https://cwe.mitre.org/data/definitions/22.html), read-only.

### [LOW-002] defects_missed ids are copied verbatim with no id grammar; unknown ids silently count as caught

- **Confidence:** medium
- **File:** `head/evals/harness/ablation-row.sh:410-413` (emission), `:165-168` (validate), consumed at
  `head/evals/harness/ablation-report.py:544-550` (`defect_vector` tests membership of `d1 … dN`)
- **Issue:** Any list of non-empty strings passes (`["a|b\nc"]` validated), and the report's union and per-defect
  vectors only test `f"d{k}" in ms`. A grader that emits `"D2"`, `"d02"` or a defect name instead of `d<k>`
  therefore produces a vector of all-caught (1.0) for that row — an inflated catch rate with "ids" identity —
  rather than a rejected row. The budget-matched union (`:959-960`) inherits the same read.
- **Fix:** Validate each id against `^d[1-9][0-9]*$` on emission and in `--validate`; in the report, fall back to
  "rate" (or exclude) when an id is outside `d1 … dN`.
- **Reference:** CWE-20.

### [LOW-003] The budget-matched rate fallback is stricter than the header says

- **Confidence:** high
- **File:** `head/evals/harness/ablation-report.py:959-964`; header `:145-147`
- **Issue:** `all(... how in ("ids", "cap"))` falls back to the best trial's rate for the whole task when any single
  a0 row lacks ids, while the header says the fallback is for "a task whose a0 rows carry none". During the
  v1→v2 transition one pre-1.2 row discards the defect union for every trial of that task, labelled only "rate
  fallback".
- **Fix:** Compute the union over the id-bearing rows and fall back only when none carry ids, or document the
  stricter rule and add the id-less row count to `reason`.

### [LOW-004] Element-level --validate failures do not name the element

- **Confidence:** high (observed for `["d2", 3]`, `[""]`, `[["d2"]]`)
- **File:** `head/evals/harness/ablation-row.sh:165-168`
- **Issue:** The message reads "field defects_missed has type array, want a list of non-empty strings|null" for
  every element-level failure; on a 300-row file it does not say which element or why.
- **Fix:** Branch the message: type mismatch vs "element N is not a non-empty string".

### [LOW-005] AR-20 leaves the `present` scenario out of the row-shape validation

- **Confidence:** high (its 90 rows validate under the head writer)
- **File:** `head/evals/tests/ablation-report.bats:290`
- **Fix:** Add `present` to the loop so the scenario driving AR-32 … AR-34 is held to the row contract.

### [LOW-006] Stale test-file header

- **Confidence:** high
- **File:** `head/evals/tests/ablation-report.bats:6-7`
- **Issue:** "writes four scenarios (main, boundary, exclusions, partial …)"; the PR brings it to eleven.
- **Fix:** Update the count and point at the gen-fixtures header for the list.

### [LOW-007] The planted rows are the pre-1.2 row shape

- **Confidence:** high
- **File:** `head/evals/tests/fixtures/ablation-report/gen-fixtures.py:114-115`
- **Issue:** `row()` emits `defects_missed` only when `with_missed and missed is not None` and never emits
  `regressions_final_green`, so AR-20's "real row shape" claim covers the legacy shape; the report's null
  `defects_missed` path is not exercised by the fixtures.
- **Fix:** Emit `"defects_missed": None` on build rows and id-less review rows, and
  `"regressions_final_green": True/False/None`.

### [LOW-008] The degenerate reason misdescribes an all-cap single-task pair

- **Confidence:** medium
- **File:** `head/evals/harness/ablation-report.py:634-639`
- **Issue:** When every row of a single-task catch pair is `cap_failure`, `defect_identity` holds only "cap", so
  the pair is flagged degenerate with "with no per-defect ids: every defect takes the row's defect_catch_rate",
  which is not what happened (all-zero vectors from `:544-545`). The read (no valid pair) is right; the text is not.
- **Fix:** Name the cap-only case in the reason.

### [LOW-009] SIMPLICITY[shrink] — `batch_record` is 93 lines holding two concerns

- **Confidence:** high
- **File:** `head/evals/harness/ablation-report.py:992-1084`
- **Issue:** One function reads STATUS.json (`:1007-1049`) and walks run directories for grader versions
  (`:1050-1082`); the "never fatal" promise cannot be checked per concern, which is how HIGH-001 slipped through.
- **Fix:** Two helpers, each wrapped so any exception becomes a `status_note` / `"n/a"` tally rather than an abort.

---

## Observations

None demoted. The review's trailer carries `excluded: 0`, so there is no speculative high to confirm;
`excluded_confirmed` is 0.

Verified and not defects (the companion voice's and the review's dissent claims I tested): `assess()` reads
"inconclusive by degradation" only when an arm's excluded share on the primary's task types exceeds the guard, and
the ungraded/all-excluded case reaches the guard as the review found; the precision line renders when every
`false_positives` is null; jq's `or` short-circuits, so the `--validate` clause never iterates a non-array
`defects_missed`; the `-h` range `2,101p` ends on the same header paragraph the base `2,84p` did.

---

## Cross-Model Observations

Adversarial audit (`adversarial-audit.json`, type audit, `--diff-file pr/head.diff`): primary gpt-5.5-pro
(answered by codex-headless) returned no findings (status `clean`); companion claude-headless (independent voice,
counted) returned four. `verdict_quality`: consensus, 2/2 voices, chain health ok, no degradation marker, so no
DEGRADED_SECURITY_REVIEW.

- DISS-C-001 (MEDIUM, companion) — the grader_versions sort TypeError. Confirmed; tallied as HIGH-001 (I rate the
  damage higher than the voice did: the whole decision artifact is lost to one file).
- DISS-C-002 (LOW, companion) — the arm joined into the path, absolute arms discard the batch dir. Confirmed; LOW-001.
- DISS-C-003 (LOW, companion) — `trials_planned` and the batch name unescaped in the batch table. Confirmed and
  reproduced; tallied as MED-001 because the artifact is the human-read decision record and the PR escapes the
  sibling cells.
- DISS-C-004 (LOW, companion) — `defects_missed` ids not checked against the `d1 … dN` grammar. Confirmed; LOW-002,
  with the consequence (unknown ids read as caught) added.

## Rejected dissent payloads

None. `metadata.rejected_summary` is empty, `metadata.rejected_sidecars` is `[]`, and no
`adversarial-rejected-audit*.jsonl` sidecar exists beside the envelope.

---

## Documentation Audit

- No `documentation-coherence-*` reports exist in this workspace; verified manually. Both headers (`ablation-report.py`
  `:1-160`, `ablation-row.sh` `:49-68`) document the new fields, options, states, exit codes and the "never fatal"
  batch record (the last of which the code does not yet honour — HIGH-001). The `-h` range was advanced with the header.
- The PR's commit list names a CHANGELOG Sprint 262 entry and suite README updates; those files are outside the
  five-file `pr/head.diff` scope and were not verified here. No secrets, internal URLs or credentials appear in the
  diff; no auth or crypto surface is touched.

## Security Checklist for This Sprint

- [x] No hardcoded secrets added (stdlib only; no credentials, tokens or URLs in the diff)
- [ ] Input validation on all new inputs — STATUS.json and grade.json are read without validation (HIGH-001,
  MED-001); the row `arm` is not grammar-checked by the reader (LOW-001); `defects_missed` ids have no grammar (LOW-002)
- [x] Authentication required where needed (n/a — offline report)
- [ ] No injection vulnerabilities — markdown injection into report.md via `trials_planned` and version headings (MED-001)
- [x] Error handling doesn't leak info (Fail messages name paths the operator passed; the HIGH-001 traceback leaks
  nothing beyond the script's own path, but it is still an uncaught exception)
- [ ] Tests cover security paths — no test exercises a mixed grader_version, an unescaped STATUS.json value, or an
  out-of-grammar arm or defect id

## Rubric Scores

| Dimension | Score | Basis |
|-----------|-------|-------|
| Security — input validation (SEC-IV) | 3 | Symlink refusals and tolerant JSON reads, but three new unvalidated reads (HIGH-001, MED-001, LOW-001) |
| Security — injection (SEC-IN) | 3 | `md_cell` applied to most cells; two sites missed (MED-001) |
| Security — availability (SEC-AV) | 2 | One file aborts the whole report (HIGH-001) |
| Architecture | 4 | Per-version `analyse()` and the render split are clean; `batch_record` holds two concerns (LOW-009) |
| Code quality | 3 | Sound jq and statistics; the tally and version-key defects (MED-002, MED-003) and the doc/code mismatches |
| DevOps | 4 | Additive schema, tests for every new behaviour, fixtures regenerate deterministically |

---

## Next Steps

1. Fix HIGH-001 (type-stable sort key, wrap the grader walk so nothing in grade.json is fatal) and add the
   mixed-version fixture to `present_scenario()` / AR-32.
2. Fix MED-001 (escape `trials_planned`, the batch name and the version headings), MED-002 (normalise
   `version_key` and `--suite-version`), MED-003 (one directory per row; rows in cells only) in the same pass; they
   are all inside the new code.
3. Run `bats evals/tests/ablation-report.bats evals/tests/ablation-row.bats` in the real tree.
4. Run `/implement sprint-1` to apply, then `/review-sprint sprint-1` and `/audit-sprint sprint-1` again.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":3,"low":9},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T10:48:00Z"} -->
