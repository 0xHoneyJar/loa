# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md (Task 1.1: the change in `pr/head.diff`)
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description)
**Review:** grimoires/loa/a2a/sprint-1/engineer-feedback.md (CHANGES REQUIRED; 3 HIGH, 1 MEDIUM, 4 LOW, excluded 0)
**Change under review:** sprint-262 — `ablation-row.sh` 1.2 (defects_missed, regressions_final_green) and `ablation-report.py` 1.2.0 (suite_version partition, H1/A4 read states, degenerate pairs, sensitivity lines, batch record, precision, budget-matched baseline), with `ablation-report.bats`, `ablation-row.bats` and `gen-fixtures.py`

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

The change has no secret, no network call, no shell interpolation and no write outside `--out` / `--json`; the row writer's two new fields are type-checked in jq and reach jq as data, never as program text. The security posture of the row-writer half is sound.

The report half introduces three HIGH defects, all in new code of `ablation-report.py` and all confirmed independently here by reading the code and, for two of them, by executing the functions in isolation: an uncaught `TypeError` in the informational batch record that aborts the whole decision report; a suite-version partition that neither canonicalises string versions nor ranks them below numeric ones, so one stray row rewrites the headline H1/A4 lines; and a primary-version choice that reads rows the report itself never decides. Below them sit one MEDIUM (complexity) and six LOW findings, three of them new here: an uncaught `ValueError` on Unicode digit strings, a non-integer float `suite_version` silently pooled as "absent", and the PR description listing commits outside the diff. The adversarial dissent (two voices, both succeeded, zero rejected payloads) found nothing above LOW and its three LOW findings map onto findings below.

**Pre-flight note (deviation recorded):** the skill's Phase 0 requires the review to say "All good"; the review verdict is CHANGES REQUIRED. The audit was run anyway on the explicit instruction of this task (autonomous, no questions) so the review's three HIGH findings are confirmed or refuted by a second reader before the resubmission. Nothing in this file approves the sprint.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 3 |
| Medium | 1 |
| Low | 6 |

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] The batch record's grader-version sort raises an uncaught TypeError that aborts the report

**Severity:** HIGH (confidence: high)
**File:** `head/evals/harness/ablation-report.py:1081-1082`
**Issue:** The sort key is
```python
e["grader_versions"] = dict(sorted(gv.items(), key=lambda kv: (
    kv[0] == "n/a", [int(p) if p.isdigit() else p for p in re.split(r"[.]", kv[0])])))
```
The list mixes `int` and `str` elements, so two grader versions whose dotted components differ in numeric-ness compare `int` against `str`. Reproduced here in isolation:
```
sorted({"1.2.0-dev": 1, "1.2.5": 2}.items(), key=...)
TypeError: '<' not supported between instances of 'int' and 'str'
```
`main()` catches only `Fail` (`head/evals/harness/ablation-report.py:1678`), so the exception escapes: exit 1 with a traceback, no report.md, no report.json. The header promises "a missing directory is counted, never fatal" (`head/evals/harness/ablation-report.py:139`) and the docstring "a missing file or directory is reported, never fatal" (`head/evals/harness/ablation-report.py:994`). The `"n/a"` sentinel is protected by the leading boolean; real versions are not. The dissent's primary voice and the review found the same defect (DISS-001/DISS-C-001 of the review envelope).
**Impact:** One unusual `grader_version` tag in any `grade.json` under any batch directory (`"1.2.0-dev"`, `"dev"`, `"2-rc1"`) takes down the report the harness gates promotion on, from a section that is documented as informational. Availability of the decision artifact depends on grader output the report does not control.
**Fix:** Make every component self-comparable, e.g. `[(0, int(p)) if p.isdigit() else (1, p) for p in kv[0].split(".")]` (with the ASCII-only predicate of LOW-001), and add a planted test with `"1.2.0-dev"` beside `"1.2.5"` in the `present` fixture's two run directories.
**Reference:** CWE-248 Uncaught Exception https://cwe.mitre.org/data/definitions/248.html; CWE-755 Improper Handling of Exceptional Conditions https://cwe.mitre.org/data/definitions/755.html

### [HIGH-002] String suite_versions are not canonicalised and outrank every numeric version

**Severity:** HIGH (confidence: high for the mechanism; the review rated the likelihood medium)
**File:** `head/evals/harness/ablation-report.py:835`, `head/evals/harness/ablation-report.py:840`
**Issue:** `version_key` folds only `\d+` strings:
```python
return str(int(s)) if re.fullmatch(r"\d+", s) else s
```
so `version_key("1.0")` returns `"1.0"` while the float `1.0` returns `"1"` (verified by executing the function), contrary to the docstring "1, 1.0 and "1" are one version" (`head/evals/harness/ablation-report.py:826`). `version_order` then returns `(1, 0, k)` for any non-digit key, above every numeric `(0, n, "")`, and `partition()` picks `max(groups, key=version_order)` as the default primary (`head/evals/harness/ablation-report.py:861`). The row writer admits strings — `need("suite_version"; ["number","string","null"])` at `head/evals/harness/ablation-row.sh:147` — and takes the value from the manifest, pipeline.json or the task YAML, so one quoted version anywhere upstream produces such a row. `--suite-version 2.0` goes through the same `version_key` (`head/evals/harness/ablation-report.py:857-859`) and is refused when the rows hold 2.
**Impact:** One row with `suite_version: "1.0"` or `"v2"` becomes the primary version: every component reads "no rows", H1 reads "not yet decidable (no pair)", the real rows are demoted to the "reported separately" section, and any row without `suite_version` becomes an exit-2 failure. The report does not say why the primary is a version no batch was planned under. A decision artifact that silently changes its headline on one stray row is an integrity failure.
**Fix:** Canonicalise every numeric representation through one path (`"1.0"` → `"1"`, `"2.0"` → `"2"`), apply it to `--suite-version`, and either rank non-numeric strings below numeric ones or refuse them with exit 2 naming the row. Add a test with a `"1.0"` row beside integer-1 rows.
**Reference:** CWE-20 Improper Input Validation https://cwe.mitre.org/data/definitions/20.html; CWE-1288 Improper Validation of Consistency within Input https://cwe.mitre.org/data/definitions/1288.html

### [HIGH-003] Rows that never enter a decision choose the primary suite_version

**Severity:** HIGH (confidence: medium)
**File:** `head/evals/harness/ablation-report.py:845`, `head/evals/harness/ablation-report.py:861`
**Issue:** `partition()` builds the version keys over every deduplicated row and takes the maximum as the primary, before `Analysis._classify` (`head/evals/harness/ablation-report.py:494-510`) sets aside the rows of smoke batches, of batches without a manifest, of arms the suite does not run and of non-applicable task types. The header documents the default as "the highest present" (`head/evals/harness/ablation-report.py:53-54`), but "present" includes rows that DEC-0393 says are "listed, never decided". `--manifests DIR` walks the whole tree (`head/evals/harness/ablation-report.py:375`), so a smoke run of the next suite version beside the decided batches is the normal layout. The review reproduced it on the `main` fixture (smoke batch tagged `suite_version: 3` → primary 3, six components "no rows", H1 "not yet decidable", `--partial` exits 1, while `by_suite_version["1"].h1` reads established); the mechanism is confirmed here by reading. The dissent rated it advisory because `--suite-version` overrides it; the override is not what the unattended harness runs.
**Impact:** The headline H1/A4 lines and the `--partial` exit code are driven by rows that contribute nothing to them.
**Fix:** Choose the default primary among rows that will enter a decision (reuse the smoke / no-manifest / applicability predicates in a cheap pre-pass) and fall back to the current rule only when no such rows exist; keep `--suite-version` as the explicit override; add a test with a smoke batch at a higher suite_version.
**Reference:** CWE-1288 Improper Validation of Consistency within Input https://cwe.mitre.org/data/definitions/1288.html

---

## Medium/Low Priority Issues

### [MED-001] batch_record() and build() are too large to test the failure above in isolation
- **Severity:** MEDIUM (confidence: high) — code quality
- **File:** `head/evals/harness/ablation-report.py:992-1084`, `head/evals/harness/ablation-report.py:1379-1637`
- **Issue:** `batch_record()` is 93 lines mixing STATUS.json parsing, tallying and a filesystem walk; `build()` stays at about 260 lines after the `render_*` extraction. HIGH-001 sits in the untested tail of the first.
- **Fix:** Split `batch_record` into a STATUS.json reader and a grader-version walker; move the header/provenance block and the JSON assembly of `build()` into helpers like the renderers already extracted.
- **Reference:** CWE-1120 Excessive Code Complexity https://cwe.mitre.org/data/definitions/1120.html

### [LOW-001] str.isdigit() and int() disagree: a Unicode digit string crashes the report with a traceback
- **Severity:** LOW (confidence: high)
- **File:** `head/evals/harness/ablation-report.py:840`; also `head/evals/harness/ablation-report.py:1082` and `head/evals/harness/ablation-report.py:1611`
- **Issue:** `version_order` calls `int(k)` whenever `k.isdigit()`; `str.isdigit()` is true for `"²"` while `int("²")` raises `ValueError` and `version_key`'s `\d+` did not fold it. Verified: `version_order("²")` raises. The same predicate pair sits in the grader sort (`"1.²"`) and in the `primary_suite_version` expression. Only `Fail` is caught, so the report dies with a traceback (local paths included) instead of the documented exit 2 naming the row. Dissent DISS-C-001 (companion voice) reports the same.
- **Fix:** One ASCII-only predicate (`re.fullmatch(r"[0-9]+", k)`) in all four places and convert `ValueError` into `Fail`.
- **Reference:** CWE-248 https://cwe.mitre.org/data/definitions/248.html

### [LOW-002] A row's arm is a filesystem path component with no grammar check (read-only traversal)
- **Severity:** LOW (confidence: high)
- **File:** `head/evals/harness/ablation-report.py:1054` (listing `:1057`, read `:1070-1075`)
- **Issue:** `ad = os.path.join(d, r["arm"])`. `load_rows` requires only a non-empty string (`head/evals/harness/ablation-report.py:354-357`); an arm absent from the suite is listed, not dropped; the arm grammar `^[a-z][a-z0-9_]{0,63}$` lives only in the row writer (`head/evals/harness/ablation-row.sh:162`). `"../.."` lists a parent directory and an absolute arm discards `d` entirely (verified: `os.path.join("/data/batch", "/etc") == "/etc"`); any `<task_id>-t<n>/grade.json` beneath is `json.load`ed and its `grader_version` printed in report.md and report.json. Symlinks are skipped and only one string per file is surfaced, so the exposure is enumeration plus one field — but the header says the report "reads, never writes, each batch's STATUS.json and its run directories' grade.json", and this reads outside them. The islink/isfile-then-open sequence at `:1009-1016` and `:1072-1075` is a check-then-use pair; negligible for an offline tool, noted. Dissent DISS-C-002 reports the same.
- **Fix:** Skip (with a note in the batch record) rows whose arm or task_id fails the grammar or contains `os.sep` / `..`; confirm `realpath(ad)` stays under `realpath(d)` before listing.
- **Reference:** CWE-22 Path Traversal https://cwe.mitre.org/data/definitions/22.html; OWASP A01:2021 https://owasp.org/Top10/A01_2021-Broken_Access_Control/

### [LOW-003] trials_planned from STATUS.json is rendered raw into the batch-record table
- **Severity:** LOW (confidence: high)
- **File:** `head/evals/harness/ablation-report.py:1156`
- **Issue:** `{e['trials_planned'] if e['trials_planned'] is not None else 'n/a'}` while every neighbouring cell of the row goes through `md_cell()` (`:1147-1160`). A value holding `|` or a newline shifts the columns so the table shows a different state or spend than the data holds. The JSON twin is unaffected. Dissent DISS-C-003 reports the same; its second half (`task_id` raw in the budget table, `:1106`) follows the file's pre-existing treatment of `task_id` in every other table (`:1259`, `:1514`) and is not counted as introduced here.
- **Fix:** `md_cell(e['trials_planned'])`, or coerce to `int` else `'n/a'`.
- **Reference:** CWE-116 Improper Encoding or Escaping of Output https://cwe.mitre.org/data/definitions/116.html

### [LOW-004] Header and rendered note describe a rate fallback the code does not implement
- **Severity:** LOW (confidence: high)
- **File:** `head/evals/harness/ablation-report.py:147`, `head/evals/harness/ablation-report.py:959`, `head/evals/harness/ablation-report.py:1094-1095`
- **Issue:** The header says rate fallback applies to "a task whose a0 rows carry none" of the per-defect ids and the rendered note says "where the rows carry no per-defect ids", but `budget_matched()` falls back when ANY valid a0 trial lacks ids: `all(vv is not None and how in ("ids", "cap") for vv, how in vecs)`. The `method` column therefore does not mean what the text says.
- **Fix:** Align the text to the code, or compute the union over the id/cap trials and name the dropped trials in `reason`.
- **Reference:** CWE-1059 Insufficient Technical Documentation https://cwe.mitre.org/data/definitions/1059.html

### [LOW-005] A non-integer float suite_version is read as absent and silently pooled
- **Severity:** LOW (confidence: medium — depends on whether non-integer suite versions ever occur; the mechanism is verified)
- **File:** `head/evals/harness/ablation-report.py:831-836`, `head/evals/harness/ablation-report.py:852-853`
- **Issue:** `version_key(1.5)` returns `None` (the float branch requires `is_integer()` and the function falls through), while `version_key("1.5")` returns `"1.5"`. A row with the number 1.5 is treated as having no suite_version: with one other version present it joins that group (`groups = {keys[0]: list(rows)}`), contrary to "never pooled"; with two it fails as "has no suite_version", which is not what the row says. The same value partitions differently by JSON type.
- **Fix:** Fold every finite number through one canonical string, or refuse non-integer versions with exit 2 naming the row.
- **Reference:** CWE-20 https://cwe.mitre.org/data/definitions/20.html

### [LOW-006] The implementation report is a commit list that does not match the diff
- **Severity:** LOW (confidence: high) — process
- **File:** `grimoires/loa/a2a/sprint-1/reviewer.md:1` (= `pr/PR.md`)
- **Issue:** The report lists 24 commits, including CHANGELOG, suite README, release-notes, codex pre-flight and grader 1.2.12/1.2.13 changes that are not among the five files in `pr/head.diff`; it carries no AC verification walkthrough and no stated assumptions, so claims cannot be checked against the change. The documentation that is in scope (both script headers, the bats and fixture headers) is updated and accurate apart from LOW-004.
- **Fix:** On resubmission, an AC table (field or state, test, `file:line`) scoped to the files in the diff.
- **Reference:** OWASP Proactive Controls C1 https://owasp.org/www-project-proactive-controls/

---

## Observations (not tallied)

- **Pre-existing, made live by this change:** `defect_vector` (`head/evals/harness/ablation-report.py:549-551`, identical in base) reads a `defects_missed` id as missed only when it is exactly `d1 … dN`; an id of any other shape (`"D2"`, `"defect-2"`, `"d7"` when N = 5) is silently read as caught, so a grader that names ids differently inflates the per-defect catch rate to 1.0 while the row's own `defect_catch_rate` may be 0. Verified: `["D1","d7","defect-2"]` with N = 3 → `[1.0, 1.0, 1.0], "ids"`. The row writer now emits the field (`head/evals/harness/ablation-row.sh:410-413`) and `--validate` (`:165-168`) checks only "non-empty strings". A consistency check (ids ⊆ d1…dN, and |missed| against `defects_seeded` and the rate) would close it. Recorded as an observation because the reader is unchanged by the PR.
- **Scope:** `pr/head/evals/.run/audit.jsonl` (2 lines, untracked) is a tool-audit hook artifact of the review session whose cwd was `pr/head/evals`; it is not part of the PR and was excluded.
- **Environment:** AR-33/AR-34 of `ablation-report.bats` depend on jq ≥ 1.7 number-literal preservation; the repository already requires it (the pre-existing keyword-shorthand key at `head/evals/harness/ablation-row.sh:383` does not compile under 1.6). Not a finding.
- **Documentation coherence:** no `grimoires/loa/a2a/subagent-reports/documentation-coherence-*.md` exists for this sprint; the two script headers, the bats headers and the fixture header were verified manually against the code (LOW-004 is the one divergence). No secrets, internal URLs or credentials appear in the diff. No CHANGELOG is in the diff to check.
- **Review demotions:** the review trailer counts `excluded: 0`; there is nothing to confirm, `excluded_confirmed` is 0.

---

## Rejected dissent payloads

- none — `metadata.rejected_count` is 0, `metadata.rejected_summary` is empty and `metadata.rejected_sidecars` is empty in `grimoires/loa/a2a/sprint-1/adversarial-audit.json` (both voices succeeded; companion `counted_as: independent_voice`).

---

## Cross-Model Observations

Envelope: `grimoires/loa/a2a/sprint-1/adversarial-audit.json` — type audit, run with `--diff-file pr/head.diff` (sha256 3043bf32…), model `gpt-5.5-pro`, status `clean` ("no findings met the BLOCKING/ADVISORY bar — not an approval of unreviewed surface"), companion voice `claude-headless` succeeded, 2/2 voices, consensus, `degraded: false`, not a degraded security review. Companion findings: DISS-C-001 (LOW, `version_order` isdigit/int mismatch) → LOW-001; DISS-C-002 (LOW, `batch_record` path from row arm) → LOW-002; DISS-C-003 (LOW, raw `trials_planned` / `task_id`) → LOW-003 (the `task_id` half is pre-existing treatment). No advisory voice. The three HIGH findings come from this audit's own reading and execution, agreeing with the review's envelope (`adversarial-review.json`, DISS-001/DISS-C-001/DISS-C-002/DISS-C-003).

---

## Rubric Scores

| Dimension | Score (1–5) | Basis |
|-----------|-------------|-------|
| SEC-IV Input validation | 3 | row fields type-checked; version strings, arm path and STATUS.json shape not (HIGH-002, LOW-001/002/003/005) |
| SEC-AZ Authorization | n/a | offline CLI, no principals |
| SEC-CI Confidentiality/Integrity | 4 | no secrets; read-only traversal surfaces one string (LOW-002) |
| SEC-IN Injection | 5 | jq receives data via --slurpfile/--argjson; yq via argv list; no eval/shell interpolation |
| SEC-AV Availability | 2 | two uncaught exception paths abort the decision report (HIGH-001, LOW-001) |
| Architecture / data integrity | 2 | the partition key and primary choice let one stray row rewrite the headline (HIGH-002, HIGH-003) |
| Code quality | 3 | tests cover every new state; batch_record/build size (MED-001); doc/code divergence (LOW-004) |

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added
- [ ] Input validation on all new inputs — suite_version canonicalisation, arm grammar before path use, STATUS.json cell encoding (HIGH-002, LOW-001, LOW-002, LOW-003, LOW-005)
- [x] Authentication required where needed — n/a (offline CLI)
- [x] No SQL/XSS/shell injection — jq data passed as files/args, no shell interpolation
- [ ] Error handling doesn't leak info — two uncaught exceptions print tracebacks with local paths (HIGH-001, LOW-001)
- [x] Tests cover the new states (AR-23…AR-35, five new row-writer tests) — but none plants a non-numeric grader_version, a string suite_version or a smoke batch at a higher version

---

## Next Steps

1. Fix HIGH-001, HIGH-002 and HIGH-003 with the three named planted-row tests; fold LOW-001 into the same predicate change.
2. Address LOW-002, LOW-003, LOW-005 (small, local); align the text for LOW-004.
3. Re-run `evals/tests/ablation-report.bats` and `evals/tests/ablation-row.bats` with jq ≥ 1.7 and yq v4.
4. Resubmit with an AC walkthrough scoped to the diff (LOW-006), then `/review-sprint sprint-1` and `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":1,"low":6},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-22T14:26:37Z"} -->
