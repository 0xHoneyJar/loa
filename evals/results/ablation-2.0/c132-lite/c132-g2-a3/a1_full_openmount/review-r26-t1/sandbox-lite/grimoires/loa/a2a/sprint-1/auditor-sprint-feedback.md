# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (pr/PR.md)
**Change under audit:** pr/head.diff (5 files: `ablation-report.py` 1.0.0 → 1.2.0, `ablation-row.sh` row writer 1.1 → 1.2, `ablation-report.bats`, `ablation-row.bats`, `gen-fixtures.py`)

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

The change is an offline report generator and a row writer: it reads `runs.jsonl` rows, `MANIFEST.json`, `STATUS.json`, `grade.json` and a suite file, and writes two files. There are no secrets, no network, no shell built from input, and the two output paths refuse symlinks. The row-writer half (`defects_missed`, `regressions_final_green`, their `--validate` rules) is type-guarded at every jq boundary and I confirmed all eleven generated fixture sets validate (the `present` set included, 90 rows). Scope limits: the real suite file `evals/suites/ablation-2.0.yaml` and the row-writer fixture tree `evals/tests/fixtures/ablation-runs/` are outside the PR, so the report bats ran against a synthesized suite with the same arm ids and rules keys (30 of 35 pass; AR-11, AR-12 and AR-17 fail only on the synthesized rule text; AR-33/34 fail on this host's jq 1.6, LOW-009) and `ablation-row.bats` could not be executed (reviewed by reading plus `--validate`).

Two HIGH defects block the merge, both in new report code, both raised by the review's dissent, confirmed by the senior reviewer, and re-confirmed here with concrete inputs. `version_key()` is not total: a non-integral numeric `suite_version` keys to `None`, which the partition reads as "absent", so rows of different suite versions are **silently pooled** (exit 0), defeating the invariant this sprint exists to enforce. The grader-version tally in `batch_record()` sorts mixed `int`/`str` lists and raises an uncaught `TypeError` when two `grade.json` files in one batch carry differently shaped version strings, aborting the entire decision report (exit 1, nothing written) from a section the header promises is "never fatal". One MEDIUM security finding: the row's `arm` string is used verbatim as a path component, so an absolute or `../` arm makes the report list and read `grade.json` outside the batch directory (CWE-22, read-only, reproduced).

Prerequisite note: the review verdict (`engineer-feedback.md`) is CHANGES_REQUIRED, not "All good". Phase 0 of this skill would stop here; the task instruction directed the audit to run regardless, so this report is written as an independent audit of the same change and does **not** create a COMPLETED marker. The audit dissent ran with two voices (`gpt-5.5-pro` via codex-headless, `claude-headless`), `status: clean`, `degraded: false`, companion `independent_voice`; no DEGRADED_SECURITY_REVIEW marker applies.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 3 |
| Low | 9 |

---

## Category Scores (Rubric-Based Assessment)

| Category | Score | Dimensions |
|----------|-------|------------|
| Security | 3.8/5 | IV:3 AZ:5 (n/a, offline CLI) CI:4 IN:5 AV:2 |
| Architecture | 3.6/5 | MO:4 SC:5 RE:2 CX:3 ST:4 |
| Code Quality | 3.4/5 | RD:4 TC:4 EH:2 TS:3 DC:4 |
| DevOps | 4.0/5 | AU:4 OB:4 RC:4 AC:4 DS:4 |
| Blockchain | n/a | — |
| **Overall** | **3.7/5** | *Security weighted ×2* |

**Machine-Parseable Output:** `grimoires/loa/a2a/audits/2026-10-22/findings.jsonl`; working file `grimoires/loa/a2a/audits/2026-10-22/SECURITY_ANALYSIS_TODO.md`.

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] `version_key()` is not total — rows of different suite versions are silently pooled

**Severity:** HIGH | **Confidence:** high | **Criterion:** SEC-IV Input Validation
**File:** `head/evals/harness/ablation-report.py:836` (the trailing `return None`); `:852` (the single-key join); `:840` (`version_order` ranks any non-digit string above every integer)
**Issue:** The vulnerable code:
```python
    if isinstance(v, float) and v.is_integer():
        return str(int(v))
    if isinstance(v, str) and v.strip():
        s = v.strip()
        return str(int(s)) if re.fullmatch(r"\d+", s) else s
    return None
```
`partition()` (`:843-861`) treats `None` as "suite_version absent". The row schema allows `suite_version` as `number|string|null` (`head/evals/harness/ablation-row.sh:150`), and a YAML `suite_version: 2.1` arrives as a float. Reproduced on the `versions` fixture:

| Input | Result (all exit 0) |
|---|---|
| ver-v1 rows 2.1, ver-v2 rows 2.2 | `primary_suite_version: null`; one `by_suite_version["n/a"]` of 156 rows across both batches; `a1_full.rows` 60 (12 + 48 pooled); `H1: established` computed on the pool; header reads `- row suite_version: 1, 2, 2.1, 2.2` directly above `suite_version n/a (primary …): 156 rows; batches ver-v1, ver-v2` |
| ver-v1 rows 2, ver-v2 rows 2.1 | one group `"2"` with 60 a1 rows: the 2.1 rows fold into version 2 |
| ver-v1 rows `"2-rc"`, ver-v2 rows 2 | two groups; `"2-rc"` is the primary |
| ver-v1 rows the string `"2.0"`, ver-v2 rows the number 2 | two groups `"2"` and `"2.0"`; the string one is primary |

**Impact:** Pooling rows across suite versions is exactly what the Sprint 262 partition was introduced to make impossible. A silent pool produces an H1/A4 line and component decisions on mixed-suite evidence with nothing in the report or the exit code to show it. Confirmed by cross-model review (review dissent DISS-C-001).
**Fix:** Make `version_key` total over numbers and fail loudly otherwise: after the `is_integer()` branch return a canonical string for non-integral floats (`repr(v)` or fixed precision), normalise numeric strings the same way (`"2.0"` → `"2"`), and `raise Fail(f"{row['_where']}: row {rid} has an unreadable suite_version {v!r}")` for any remaining type instead of `return None`. Restrict `max(groups, key=version_order)` to numeric keys or `Fail` when a non-numeric key is present. Add AR cases for 2.1/2.2 (two sections) and 2/2.1 (two sections, never a pool).
**Reference:** CWE-20 Improper Input Validation — https://cwe.mitre.org/data/definitions/20.html; CWE-1286 Improper Validation of Syntactic Correctness of Input — https://cwe.mitre.org/data/definitions/1286.html

### [HIGH-002] grader-version tally sort raises an uncaught `TypeError` and aborts the whole report

**Severity:** HIGH | **Confidence:** high | **Criterion:** SEC-AV Availability
**File:** `head/evals/harness/ablation-report.py:1081-1082`
**Issue:** The vulnerable code:
```python
        e["grader_versions"] = dict(sorted(gv.items(), key=lambda kv: (
            kv[0] == "n/a", [int(p) if p.isdigit() else p for p in re.split(r"[.]", kv[0])])))
```
`grader_version` is read verbatim from any `grade.json` under `<batch>/<arm>/<task>-t<n>[-r<k>]/` (`:1066-1074`). Two keys that differ in type at the same list position make Python compare `int` with `str`. Reproduced on the `present` fixture by adding `a0_bare/rc-01-t3/grade.json` with `grader_version` `1.2.0-rc1` (beside `1.2.5` and `1.2.11`), and again with `v1.2.12`:
```
  File ".../ablation-report.py", line 1081, in batch_record
    e["grader_versions"] = dict(sorted(gv.items(), key=lambda kv: (
TypeError: '<' not supported between instances of 'str' and 'int'
```
exit 1, no `report.md`, no `report.json`. `batch_record()` runs unconditionally from `build()` (`:1552`); `main()` catches only `Fail` (`:1663-1668`); the header (`:140-142`) promises a missing file or directory is "counted, never fatal".
**Impact:** One pre-release or `v`-prefixed grader build landing in one run directory kills every section of the report, decisions included. The grader shipped 1.2.11 → 1.2.13 inside this cycle, so heterogeneous version strings are a realistic input. Confirmed by cross-model review (review dissent DISS-001 and DISS-C-002; audit dissent DISS-C-002).
**Fix:** Use a type-stable key, e.g. `[(0, int(p)) if p.isdigit() else (1, p) for p in parts]` with `"n/a"` last, or sort plain strings; wrap the tally build so any exception degrades to `"n/a"` with a status note rather than propagating; add an AR case with `1.2.0` and `1.2.0-rc1` in one batch.
**Reference:** CWE-248 Uncaught Exception — https://cwe.mitre.org/data/definitions/248.html; CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html

---

## Medium/Low Priority Issues

### [MED-001] The batch record walks a directory named by an unvalidated row field (CWE-22, read-only)
- **Severity:** MEDIUM | **Confidence:** high | **Criterion:** SEC-IV Input Validation
- **File:** `head/evals/harness/ablation-report.py:1054` (`ad = os.path.join(d, r["arm"])`); `:1057-1058` (`os.listdir`); `:1066-1070` (`grade.json` open)
- **Issue:** `load_rows()` (`:328-367`) only requires `arm` to be a non-empty string; the arm grammar `^[a-z][a-z0-9_]{0,63}$` is enforced by `ablation-row.sh --validate`, which the report never runs; rows `_classify` has already listed as "arm … is not run by the suite" still reach this loop. Reproduced on the `present` fixture: a row with `"arm": "/tmp/audit-r26/evil"` makes the report `listdir` that absolute path (`os.path.join` discards `d`) and read `/tmp/audit-r26/evil/rc-01-t1/grade.json`, whose `grader_version` `9.9.9-EVIL` is printed in the batch record; `"arm": "../../outside"` does the same (`8.8.8-DOTDOT`). Exit 0 both times. The `islink`-then-`open` guards are check-then-use, which matters little for an operator-run CLI but is noted.
- **Impact:** Limited to enumerating one directory and reading one JSON string field from a row-chosen location; the path is fully row-controlled. Confirmed by cross-model review (audit dissent DISS-C-001, rated LOW there; I keep MEDIUM because the sink is reachable from every row of every batch).
- **Fix:** Apply the arm grammar in `load_rows()` (or skip rows whose arm is not a suite arm) before building paths, and assert `os.path.realpath(ad)` stays under `os.path.realpath(d)`.
- **Reference:** CWE-22 Path Traversal — https://cwe.mitre.org/data/definitions/22.html; OWASP A01:2021 — https://owasp.org/Top10/A01_2021-Broken_Access_Control/

### [MED-002] The single-task zero-variance read applies to the catch rate only
- **Severity:** MEDIUM | **Confidence:** medium | **Criterion:** ARCH-ST Standards Compliance
- **File:** `head/evals/harness/ablation-report.py:634-635`
- **Issue:** `degenerate` requires `metric == CATCH`. A `hidden_test_pass_rate` comparison with exactly one paired build task has one diff, so `bootstrap()` returns `lo == hi == d` — the same zero-variance-by-construction property the PR uses to disqualify the catch-rate case — yet it is read `tested`. Reproduced with a0/a1/a4 rows on `fb-01` only: `H1: established` (n = 1, lo = hi = d = +0.200) and `A4 sensitivity: holds` (n = 1, lo = hi = d = −0.100). The bats comment at `head/evals/tests/ablation-report.bats:429` asserts this is intended ("a build primary is never degenerate").
- **Impact:** H1 or A4 can be decided on one task; a suite with one build task would decide A4 on a single number.
- **Fix:** Extend the degenerate read to any comparison with `n == 1`, or state in the header and Method why a one-task pass-rate interval is admissible when a one-task rate-fallback catch interval is not.

### [MED-003] Implementation report and documentation do not describe this change
- **Severity:** MEDIUM | **Confidence:** medium | **Criterion:** CQ-DC Documentation
- **File:** `head/evals/harness/ablation-report.py:174` (`VERSION = "1.2.0"`); `head/evals/harness/ablation-row.sh:66` (row writer 1.2)
- **Issue:** The change adds `--suite-version`, new `report.json` keys (`primary_suite_version`, `by_suite_version`, `sensitivity.h1/a4`, `budget_matched`, `batches`, `arms.<arm>.precision`) and two row fields, but the diff carries no CHANGELOG entry and no suite README update. `pr/PR.md` (carried as `reviewer.md`) lists CHANGELOG, README, release-note and sprint-261 credential-fix commits that are not in `pr/head.diff`, and has no AC-verification section. No documentation-coherence report exists under `grimoires/loa/a2a/subagent-reports/`; I verified the header against the code manually and found two drifts (LOW-004, LOW-006). No security-relevant change is undocumented, so this is not a blocker on its own.
- **Fix:** Include the CHANGELOG entry for the two row fields and the report 1.1.0/1.2.0 items in the same change (or state where it landed) and make the implementation report describe this diff.

### [LOW-001] `version_order` guards `int()` with `str.isdigit()` — a Unicode digit aborts the report
- **Severity:** LOW | **Confidence:** high | **Criterion:** SEC-AV
- **File:** `head/evals/harness/ablation-report.py:840`
- **Issue:** `str.isdigit()` is true for characters `int()` rejects (superscript `²`), while `version_key` (`:834`) normalises only `\d+` matches, so such a string passes through as a key and `int(k)` raises `ValueError` (uncaught, exit 1, traceback). Reproduced on the `main` fixture with `suite_version: "²"`. Exotic input, same class as HIGH-002; cross-model review raised it too (audit dissent DISS-C-002).
- **Fix:** Use `re.fullmatch(r"[0-9]+", k)` in both sort keys, or catch `ValueError`/`TypeError` at the partition and batch-record boundaries into `Fail`.
- **Reference:** CWE-248 — https://cwe.mitre.org/data/definitions/248.html

### [LOW-002] `--suite-version` is not normalised like row values
- **Severity:** LOW | **Confidence:** high
- **File:** `head/evals/harness/ablation-report.py:857`
- **Issue:** argparse hands a string, so `version_key("2.0")` is `"2.0"` while numeric `2.0` rows key to `"2"`. `--suite-version 2.0` on the `versions` fixture exits 2 with `no row has that suite_version (present: 1, 2)` although the rows hold version 2; `" 2 "` is accepted. The HIGH-001 fix (normalising numeric strings) covers it.

### [LOW-003] Three new table/bullet cells bypass `md_cell`
- **Severity:** LOW | **Confidence:** high | **Criterion:** SEC-IN
- **File:** `head/evals/harness/ablation-report.py:1156` (`trials_planned` from STATUS.json), `:1106` (row `task_id` in the budget-matched table), `:1269` (`degenerate_reason`, which embeds a `task_id`, as a raw bullet)
- **Issue:** Every neighbouring field in `render_batches` is routed through `md_cell`; these three are interpolated raw, so a `|` or newline in them corrupts the table or injects Markdown into `report.md`. Confirmed by reading and by a STATUS.json with `trials_planned: "x"` rendering raw. Raised by cross-model review (audit dissent DISS-C-003, which also notes HTML rendering of the report would carry the injection; the report is consumed as Markdown here, so LOW).
- **Fix:** Route the three values through `md_cell`; coerce `trials_planned` to `int` or `'n/a'`.
- **Reference:** CWE-116 Improper Encoding or Escaping of Output — https://cwe.mitre.org/data/definitions/116.html

### [LOW-004] A suite without `a4_no_gates` prints "fails" for the undocumented state `no_arm`
- **Severity:** LOW | **Confidence:** high
- **File:** `head/evals/harness/ablation-report.py:931`
- **Issue:** JSON `a4.state: "no_arm"` is not in the header's state list (`:120-123`) and the line reads "A4 sensitivity: fails — harden tasks before acting on other arms". "No arm" is not "fails".
- **Fix:** Print "A4 sensitivity: no arm a4_no_gates in the suite" and document the state.

### [LOW-005] "remaining pairs no pair (n = 0 …)"
- **Severity:** LOW | **Confidence:** high
- **File:** `head/evals/harness/ablation-report.py:888`
- **Issue:** `interval(p)` returns `no pair` when `n == 0`, so `read_text` for `inconclusive_by_degradation` renders `remaining pairs no pair (n = 0 tasks)` when every pair dropped.
- **Fix:** Branch on `p["n"] == 0`.

### [LOW-006] `budget_matched` JSON keys undocumented and conditional
- **Severity:** LOW | **Confidence:** high
- **File:** `head/evals/harness/ablation-report.py:986`
- **Issue:** `a0_cost_sum_mean` and the overwritten `a1_cost_mean` appear only when the section is available, `label` always; none is in the documented shape (`:63-65`, `:146-148`).
- **Fix:** Emit both keys as `null` in the unavailable case and document them.

### [LOW-007] `batch_record` is 93 lines mixing I/O and tallies
- **Severity:** LOW | **Confidence:** high | **Criterion:** CQ-RD
- **File:** `head/evals/harness/ablation-report.py:992-1084`
- **Issue:** One function reads STATUS.json, tallies rerowed/rerun, lists run directories and reads grade.json; this is why the exceptions in HIGH-002 and LOW-001 escape unnoticed.
- **Fix:** Split into `read_status(path)` and `grader_tally(dir, rows)` so the "never fatal" promise is checkable per helper.

### [LOW-008] AR-20 omits the `present` scenario
- **Severity:** LOW | **Confidence:** high
- **File:** `head/evals/tests/ablation-report.bats:290`
- **Issue:** The validate loop lists every planted scenario except `present`, which `setup_file` builds (`:25`). It validates (90 rows).
- **Fix:** Add `present` to the loop.

### [LOW-009] AR-33 and AR-34 depend on jq ≥ 1.7 number rendering
- **Severity:** LOW | **Confidence:** high
- **File:** `head/evals/tests/ablation-report.bats:487`, `:498`
- **Issue:** The expected strings `1.0 2.222222 27 27` and `1.0 3.0 0.875 10.0 …` rely on jq preserving the `1.0`/`3.0`/`10.0` literals through `"\(.x)"`; on jq 1.6 (this host) they render `1`, `3`, `10` and both tests fail while the JSON is correct. Observed in this audit's bats run.
- **Fix:** Compare with `jq -e '.x == 1.0'` or numeric tests independent of the jq version.

---

## Observations

None demoted: no HIGH finding in this audit is speculative.

---

## Cross-Model Security Observations

Envelope `grimoires/loa/a2a/sprint-1/adversarial-audit.json`: type audit, primary `gpt-5.5-pro` (answered by codex-headless, no findings), companion `claude-headless` (`status: succeeded`, `independent: true`, `counted_as: independent_voice`), `status: clean`, `degraded: false`, `budget_scale: diff`, `cost_usd` 0 as recorded. The dissent received `pr/head.diff` only (no `--context-file`).

| Dissent | Severity (theirs) | Where it landed |
|---|---|---|
| DISS-C-001 `batch_record` arm → path (`:1054-1080`) | LOW | Confirmed by reproduction; MED-001 (I rate it MEDIUM) |
| DISS-C-002 `isdigit` vs `int()` in `version_order` (`:840`); mixed int/str grader key (`:1081-1082`) | LOW | Confirmed by reproduction; the grader half is HIGH-002, the Unicode half LOW-001 |
| DISS-C-003 Markdown injection via `trials_planned` (`:1156`), `task_id` (`:1106`), `degenerate_reason` (`:1269`) | LOW | Confirmed by reading; LOW-003 |

Review-round dissent (`adversarial-review.json`): DISS-001 and DISS-C-002 → HIGH-002; DISS-C-001 → HIGH-001; DISS-C-003 (`budget_matched` None-safety) independently re-checked and not adopted: `mean([])` cannot occur because the union branch runs only when every vector is `ids`/`cap`, whose length is `task_defects ≥ 1` (`:559-569`, `:968-970`); `catch_task_score` never returns `None` on a valid row (`_classify` requires a numeric catch rate or `cap_failure`, `:522-527`); `f3`/`u3`/`usd` render `None` as `n/a` (`:214-219`, `:1099`).

## Rejected dissent payloads

None: `metadata.rejected_summary` is empty, `metadata.rejected_sidecars` is empty, and no `adversarial-rejected-audit*.jsonl` exists beside the envelope.

---

## Confirmation of the review's demotions

The review trailer carries `excluded: 0`; there is nothing to confirm. `excluded_confirmed: 0`.

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added (grep of the five head files: none)
- [ ] Input validation at the trust boundary — row `arm` reaches `os.path.join` unvalidated (MED-001); `suite_version` and `grader_version` keys are not total (HIGH-001, HIGH-002, LOW-001)
- [x] No shell, SQL or eval built from input (`yq` runs as an argv list on the operator's path, `:308`)
- [x] Symlinked `MANIFEST.json` / `STATUS.json` / `grade.json` / run dirs are refused (`:377`, `:1013`, `:1057`, `:1068`)
- [x] Read-only beside the manifests; only `--out` and `--json` are written, symlinks refused (`:1641-1647`; AR-19/AR-32 assert it)
- [ ] Error handling does not leak or abort — two uncaught exception paths (HIGH-002, LOW-001) print tracebacks instead of the documented exit 2
- [x] Error messages carry only operator paths already on the command line
- [ ] Tests cover the failure paths — no AR case for a non-integral `suite_version`, a mixed grader string, or a non-grammar arm
- [x] Row writer: jq guards null/absent `recall`, non-list `missed`, non-boolean `final_green`; `--validate` rules are additive and legacy rows pass (`head/evals/harness/ablation-row.sh:165-170`, `:410-414`; checked on hand-made bad rows and all eleven fixture sets)

---

## Acceptance Criteria Check

| Criterion | Status | Notes |
|-----------|--------|-------|
| report each defect the PR introduces with file and line | Pass | 14 findings above, each with `head/<path>:<line>` |
| give a merge verdict | Pass | CHANGES_REQUIRED (two HIGH) |
| Row writer 1.2 carries `defects_missed` (bd-yz1rd) and `regressions_final_green` (bd-m0hw7) | Pass | `head/evals/harness/ablation-row.sh:410-414`, `:165-170` |
| Rows of different suite_version never pooled | Fail | HIGH-001 |
| Batch record "never fatal" | Fail | HIGH-002, LOW-001 |

---

## Positive Findings

- The partition is applied once and every per-version figure flows from one `analyse()`; main and per-version sections share renderers, so they cannot drift.
- The degenerate flag is computed where the interval is computed and consumed by `usable()` in both the decision and the H1 read.
- The row-writer jq is defensive at every null/shape boundary; `--validate` rejects `[""]` and a numeric `regressions_final_green` with precise messages.
- STATUS.json of arbitrary shape (list `state`, string `trials_planned`, non-dict `cuts`/`extra_models`/`paused_arms`) is tolerated without a crash (probed).

---

## Next Steps

**CHANGES_REQUIRED:**
1. Fix HIGH-001 and HIGH-002 with the regression cases named there; the same change should close LOW-001 and LOW-002 (total, type-stable keys; `ValueError`/`TypeError` → `Fail`).
2. Apply the arm grammar in `load_rows()` (MED-001) and route the three raw cells through `md_cell` (LOW-003).
3. Decide MED-002 (extend the degenerate read or document the asymmetry) and land the CHANGELOG/README entries with an implementation report that describes this diff (MED-003).
4. Re-run `bats evals/tests/ablation-report.bats` and `bats evals/tests/ablation-row.bats` against the real suite and fixture runs; then `/review-sprint sprint-1` and `/audit-sprint sprint-1`.

Beads: `br` is not installed on this host, so no `SECURITY AUDIT:` comment or `security-blocked` label was recorded.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":3,"low":9},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-22T12:58:00Z"} -->
