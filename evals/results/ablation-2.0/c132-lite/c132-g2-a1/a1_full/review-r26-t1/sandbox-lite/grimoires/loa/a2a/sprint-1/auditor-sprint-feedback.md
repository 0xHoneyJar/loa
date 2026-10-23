# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)
**Change under audit:** `pr/head.diff` — sprint-262: ablation-row.sh 1.2 (`defects_missed`, `regressions_final_green`) and ablation-report.py 1.2.0 (suite_version partition, H1/A4 read states, degenerate pairs, sensitivity H1/A4 lines, batch record, precision, budget-matched baseline), with the bats tests and the fixture generator.

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

The row writer half of the change is sound: the two new fields are derived in jq with fail-soft `null` on every unexpected shape (`head/evals/harness/ablation-row.sh:410-414`), the validator keeps them optional and type-checks them (`:165-170`), the `--help` range tracks the header, and five bats cases cover the shapes. No security defect was found in it.

The report half adds ~590 lines, and I executed the head script against the PR's own generated fixtures (sandbox with a reconstructed suite file; the real `evals/suites/ablation-2.0.yaml` is not part of the PR) to confirm every finding below. Two HIGH issues block the merge, both integrity failures in the artifact the H1 "halt before promotion" gate reads:

1. **The primary suite version is chosen from every loaded row, including rows the analysis only lists** (smoke batches, manifest-less rows). A smoke or orphan batch at a newer `suite_version` silently takes over the main sections, the top-level JSON `h1`/`a4`/`decisions`, and the `--partial` exit code, while the real rows are demoted to a secondary section. Reproduced three ways.
2. **Untrusted strings read from `grade.json` and `runs.jsonl` reach `int()`/`sorted()` on paths that raise `TypeError`/`ValueError`, which `main()` does not catch**, so the whole report aborts with a traceback and writes nothing, in a section the header calls "never fatal". Reproduced with four distinct inputs (CWE-248).

The pre-flight condition "engineer-feedback.md says All good" is NOT met: the review verdict is CHANGES_REQUIRED (2 HIGH). The task instruction for this run is to audit autonomously regardless; the deviation is recorded here and nothing in this audit relaxes the review's findings. Both HIGH findings of the review are independently confirmed below.

Security dissent (Phase 1C): both voices succeeded and are independent (primary gpt-5.5-pro via codex-headless returned `clean` with zero findings; companion claude-headless returned 1 MEDIUM, 4 LOW). Not degraded. No rejected payloads.

**Security Issues Found:**

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 3 |
| Low | 7 |

Scope limits: the real suite YAML, the `ablation-runs` fixtures the row bats need, and the CI jq version are not in the PR; the row bats could not be executed (assertions checked by reading them against the jq program), and the report bats ran against a reconstructed suite (AR-11/12/18 fail only on my suite's rule text; every other pre-existing and new AR test passes except AR-33/34, see MED-003). No `grimoires/loa/a2a/subagent-reports/documentation-coherence-*.md` exist in this workspace; documentation was checked manually (header, version line, test docstrings coherent with the code; CHANGELOG is outside the PR files).

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] Listed rows select the primary suite version — the main sections and top-level JSON can describe an empty version

**Severity:** HIGH (confidence: high — reproduced three ways on the head script)
**File:** `head/evals/harness/ablation-report.py:845` (key set from every row), `:861` (primary = max), `:1403` (`partition()` called on the raw `rows`), `:849` (the exit-2 path)
**Issue:** `partition()` builds the version set over *all* loaded rows:

```python
keys = sorted({k for k in (version_key(r.get("suite_version")) for r in rows) if k is not None}, key=version_order)
...
return groups, max(groups, key=version_order)
```

`Analysis._classify` lists — never decides — rows of a smoke batch, rows with no manifest, rows of an unknown arm or task type. Those rows still vote for the primary version. The header promises "the main sections report … the highest present" (`:53-54`) and "rows of a smoke batch … not decided, listed" (`:68`); combined, the normal way to validate a new suite (a smoke batch at the next version beside the real batch) inverts the report.

**Reproduced** (versions fixture + 3 smoke rows at `suite_version: 3`, manifest `smoke: true`): `primary_suite_version: 3`, `H1: not yet decidable (no pair)`, every decision `no_rows`, `--partial` exit 1, while `by_suite_version["2"].h1.line` is `H1: established`. Two manifest-less rows at v3 give the same inversion with exit 0 (no signal at all). A *listed* smoke row lacking `suite_version` beside two real versions exits 2 at `:849` ("row smoke-x-… has no suite_version while the rows hold suite_version 1, 2"), blocking the report over a row that would never enter a decision.

**Impact:** The top-level `h1`, `a4`, `decisions`, `budget_matched` and the exit code are what the release notes and the regression-check recipe in the PR consume. After this change they can silently describe the wrong version. `--suite-version` is a manual workaround, not a fix. Integrity of a decision record: CWE-20 (Improper Input Validation, https://cwe.mitre.org/data/definitions/20.html) in the sense that the listing predicate is not applied before the row influences the output; also CWE-682 (Incorrect Calculation, https://cwe.mitre.org/data/definitions/682.html).
**Fix:** Apply the listing predicates before `partition()` — e.g. filter rows whose batch has no manifest or whose manifest is `smoke: true` (and arm/task-type refusals) out of the version vote, or pass `mans` into `partition()`. Add bats cases: (a) a smoke batch at a higher `suite_version` beside a real batch keeps the real primary; (b) a listed row without `suite_version` beside two versions does not exit 2.
**Reference:** CWE-20, CWE-682 (URLs above). Confirmed by the review (Changes Required 1).

### [HIGH-002] Untrusted version strings reach `int()`/`sorted()` on uncaught exception paths — the whole report aborts and writes nothing

**Severity:** HIGH (confidence: high — four distinct inputs reproduced; the shipped graders currently emit numeric semver, which bounds likelihood, not impact)
**File:** `head/evals/harness/ablation-report.py:1081-1082` (grader-version sort), `:840` (`version_order`), `:1611` (`primary_suite_version`), `:1678` (`main()` catches `Fail` only)
**Issue:**

```python
e["grader_versions"] = dict(sorted(gv.items(), key=lambda kv: (
    kv[0] == "n/a", [int(p) if p.isdigit() else p for p in re.split(r"[.]", kv[0])])))
```

`grader_version` is free text read verbatim from every `grade.json` under the batch directory (`:1072-1077`), and `suite_version` is free text from `runs.jsonl`. Two defects on the same path:

- Mixed shapes compare `int` with `str`: `"1.2.11"` beside `"1.2.11-rc1"`, or `"v1.2.5"` beside `"1.2.5"`, raise `TypeError: '<' not supported between instances of 'str' and 'int'`.
- `str.isdigit()` accepts characters `int()` rejects (`"²"` is `isdigit() == True`, `re.fullmatch(r"\d+")` is False) and `\d+` accepts strings over Python's 4300-digit limit, so `version_order(k)` at `:840`, the sort key at `:1082` and `int(primary)` at `:1611` raise `ValueError`.

`main()` catches `Fail` only (`:1678`); anything else is a traceback, exit 1, and neither `report.md` nor `report.json` is written — in a section whose docstring says "a missing file or directory is reported, never fatal" (`:993-994`).

**Reproduced** on the `present` fixture: `{"grader_version": "1.2.11-rc1"}` in `pr-2/a0_bare/rc-01-t3/grade.json` → TypeError, exit 1, no output files; `"v1.2.5"` → the same; `"1.2.²"` → ValueError; a row `suite_version: "²"` on the `main` fixture → ValueError from `version_order`.
**Impact:** One malformed or hostile `grade.json` anywhere under `--manifests` (the run directories hold trees the evaluated agent worked in; whether the agent can write `grade.json` depends on the harness — `[ASSUMPTION]` it is at least semi-trusted) or one row takes down the pre-registered decision sections with an unhandled exception instead of the documented exit 2. CWE-248 (Uncaught Exception, https://cwe.mitre.org/data/definitions/248.html); CWE-704 (Incorrect Type Conversion, https://cwe.mitre.org/data/definitions/704.html).
**Fix:** Use a total-order, ASCII-only key — `tuple((0, int(p)) if re.fullmatch(r"[0-9]{1,18}", p) else (1, p) for p in parts)` — in both the grader sort and `version_order`; make `version_key` and `:1611` use the same predicate; wrap the whole `batch_record()` call so any exception degrades to `status_note` rather than aborting; add a bats case with two grader_version strings of different shape in one batch and one with a non-ASCII digit.
**Reference:** CWE-248, CWE-704 (URLs above). Confirmed by the review (Changes Required 2) and by the dissent (DISS-C-001 MEDIUM, DISS-C-003 LOW — merged here because the root cause and blast radius are the same).

---

## Medium/Low Priority Issues

### [MED-001] `version_key` leaves `"2.0"`-style strings as their own version, which then sorts as the primary
- **File:** `head/evals/harness/ablation-report.py:825-838` (`version_key`), `:840` (`version_order` places non-digit keys after digit keys)
- **Issue:** `1`, `1.0` and `"1"` normalise to one key but `"1.0"`/`"2.0"` strings do not; the row schema admits a string `suite_version` (`head/evals/harness/ablation-row.sh:147`) copied from manifest/pipeline/task YAML where `"2.0"` is a plausible spelling. **Reproduced** (degraded fixture, a0_bare rows set to `"2.0"`): `by_suite_version` keys `["2","2.0"]`, `primary_suite_version: "2.0"`, H1 `not yet decidable (no pair)` because a1 and a0 were split across versions. A silent split reads as "no pair" instead of as a data problem. Confidence: medium.
- **Fix:** Parse `^\d+(\.0+)?$` to the integer key; sort unknown strings *before* numeric keys or refuse them with a `Fail` naming the row.

### [MED-002] The sensitivity H1/A4 lines read degradation from the cap-failure exclusions the figure exists to remove
- **File:** `head/evals/harness/ablation-report.py:1191` (sensitivity `Analysis(cap_excluded=True, include_degraded=True)` passed to `h1a4`), `:871` (`assess()` guard counts every excluded cell)
- **Issue:** `excluded_share()` counts `cap_failure (sensitivity figure)` exclusions. **Reproduced** (degenerate-2 fixture, a1 trials 1–2 set to `cap_failure`): main H1 `not established`, sensitivity H1 `inconclusive by degradation (a1_full excluded share 0.667 > 0.25)` — degradation where there is none. The line is labelled "decides nothing", so the damage is a misleading state, not a decision. Confidence: high.
- **Fix:** Exclude the `cap_failure (sensitivity figure)` reason from the share used by the sensitivity read (an `ignore_reason` argument on `excluded_share`), or state in `SENS_H_TREATMENT` that cap failures count toward the guard.

### [MED-003] AR-33 and AR-34 depend on jq ≥ 1.7 float rendering; both fail on jq 1.6
- **File:** `head/evals/tests/ablation-report.bats:487` (`"1.0 2.222222 27 27"`), `:498` (`"1.0 3.0 0.875 10.0 -0.125 defect union"`)
- **Issue:** `jq -r` interpolation of the JSON literal `1.0` prints `1` on jq 1.6 and `1.0` on jq ≥ 1.7. **Reproduced** on this host (jq-1.6): AR-33 prints `1 2.222222 27 27`; AR-34 fails the same way; every other new AR test passes. No pre-existing AR test depended on this. The CI jq version is not visible from the PR files. Confidence: high that the tests are version-dependent; medium that CI is affected.
- **Fix:** Compare numerically (`jq '.precision == 1'`) or format through `tostring`/`@text` with explicit rounding; or pin the jq version the fast gate installs and say so in the test header.

### [LOW-001] `arm` from a row is used as a filesystem path component without re-validating the grammar (read-only path traversal)
- **File:** `head/evals/harness/ablation-report.py:1054` (`ad = os.path.join(d, r["arm"])`); `load_rows` `:355-357` checks only "non-empty string"
- **Issue:** The arm grammar `^[a-z][a-z0-9_]{0,63}$` is enforced by the row writer's optional `--validate`, not by the reader. **Reproduced**: a row with `arm: "../../outside/x"` is listed as "arm … is not run by the suite" yet `batch_record` still lists `…/outside/x`, matches `rc-01-t1`, and reports `"9.9.9-outside": 1` in `grader_versions`. Read-only, JSON-parsed, only `grader_version` surfaces; the reporting user's own permissions bound the reach. CWE-22 (https://cwe.mitre.org/data/definitions/22.html). Confidence: high that it happens; low that it matters beyond a one-string leak.
- **Fix:** Validate `arm` against the grammar in `load_rows` (raise `Fail` naming the row) and/or assert `os.path.realpath(ad)` stays under `os.path.realpath(d)` before listing. Confirmed by cross-model review (DISS-C-002).

### [LOW-002] Row- and STATUS.json-derived strings are interpolated into report.md without `md_cell()` (table/heading injection)
- **File:** `head/evals/harness/ablation-report.py:1156` (`trials_planned` raw in the batch table), `:1106` (`task_id` raw in the budget table), `:1534` (`v` raw in the `## Suite version {v}` heading; `version_key` strips only outer whitespace)
- **Issue:** **Reproduced**: `"trials_planned": "20 | INJECTED | x\n## Fake heading"` in `STATUS.json` splits the batch-record row and inserts a heading into report.md; a `task_id` of `rc-02 | x` breaks the budget-table cell (7 occurrences). `report.json` stays consistent, so a reader of the Markdown alone can be misled. `state`, `cuts`, `extra_models`, `grader_versions` are correctly escaped. CWE-116 (Improper Encoding or Escaping of Output, https://cwe.mitre.org/data/definitions/116.html). Confidence: high; severity low because the inputs are the operator's own pipeline files (`[ASSUMPTION]` semi-trusted).
- **Fix:** Pass `trials_planned`, `task_id` and `v` through `md_cell()`; reject a `suite_version` string with inner whitespace or `|` in `version_key`. Partly confirmed by cross-model review (DISS-C-004).

### [LOW-003] A literal row `suite_version: "n/a"` collides with the "no version" sentinel
- **File:** `head/evals/harness/ablation-report.py:853` (sentinel `"n/a"`), `:1611` (`None if primary == "n/a"`)
- **Issue:** **Reproduced** (main fixture, every row `"n/a"`): `by_suite_version` keys `["n/a"]`, `primary_suite_version: null` for a version that is present. Confidence: high that it happens; low that it occurs in practice.
- **Fix:** Use a non-string sentinel (`None`) for the absent case, or refuse non-numeric strings in `version_key`.

### [LOW-004] H1 with a mix of `inconclusive_by_degradation` and `no_pair`/`degenerate` reads collapses to "not yet decidable (no pair)"
- **File:** `head/evals/harness/ablation-report.py:909-913`
- **Issue:** `live` excludes only `not_testable`; a `no_pair` primary beside a degraded one sends the line to the `else` branch and the degradation signal survives only in the per-comparison `read_text`. The header (`:118-120`) describes the degradation line as applying when "every testable primary" is degraded; a `no_pair` primary is arguably not testable yet. By code reading; not reproduced. Confidence: medium.
- **Fix:** Treat `no_pair` like `not_testable` in the `live` filter, or document the current reading in the header.

### [LOW-005] AR-20 validates every planted scenario except the new `present` one
- **File:** `head/evals/tests/ablation-report.bats:290`
- **Issue:** `present` overrides `false_positives` and plants the most `defects_missed` variants, and is the only scenario not run through `ablation-row.sh --validate`. I ran it: `90 rows valid` — so the gap is coverage, not a hidden shape error. Confidence: high.
- **Fix:** Add `present` to the AR-20 list.

### [LOW-006] "a symlink is not read" is implemented as `islink()` then `open()` (check-then-use race)
- **File:** `head/evals/harness/ablation-report.py:1009-1016` (STATUS.json), `:1072-1075` (grade.json)
- **Issue:** The documented control is advisory: a concurrent writer in the batch directory can swap a path to a symlink between the check and the open. Impact is bounded to the fields the report extracts (`state`, spend, tallies, `grader_version`), all JSON-parsed. CWE-367 (TOCTOU, https://cwe.mitre.org/data/definitions/367.html). Confidence: low (requires a concurrent hostile writer in the operator's own tree); speculative, listed for completeness, not for the verdict. From cross-model review (DISS-C-005).
- **Fix:** Open with `os.open(path, os.O_RDONLY | os.O_NOFOLLOW)` and `fdopen`, or accept and document the control as best-effort.

### [LOW-007] `batch_record()` is ~95 lines at four nesting levels
- **File:** `head/evals/harness/ablation-report.py:992-1085`
- **Issue:** Status parsing (`:1011-1047`) and the grader-version tally (`:1049-1083`) are two concerns in one function; splitting them also gives the "never fatal" wrapper HIGH-002 needs a single seam. `budget_matched()` (`:937-989`) is at the limit but linear; the `render_*` refactor of `build()` is a net improvement. Confidence: high.
- **Fix:** Extract `read_status(d)` and `grader_tally(d, brows)`; wrap each in the degrade-to-note handler.

---

## Cross-Model Security Observations

Envelope `grimoires/loa/a2a/sprint-1/adversarial-audit.json` (type audit, primary gpt-5.5-pro via codex-headless: `clean`, zero findings; companion claude-headless: 5 findings; `companion_voice.status: succeeded`, `counted_as: independent_voice`, `verdict_quality.voices_succeeded_ids: [codex-headless, claude-headless]`, `degraded: false`). No `DEGRADED_SECURITY_REVIEW` marker applies.

- DISS-C-001 (MEDIUM, `batch_record` :1081-1082) — grader-version sort TypeError/ValueError. **Merged into HIGH-002** (I reproduced four triggers; the blast radius is the whole report).
- DISS-C-002 (LOW, :1054) — `arm` path traversal. **Confirmed by cross-model review**; LOW-001.
- DISS-C-003 (LOW, :840) — `isdigit()`/`int()` mismatch in `version_order`. **Merged into HIGH-002** (reproduced with `"²"`).
- DISS-C-004 (LOW, :1534) — unescaped `v`/`task_id` in Markdown. **Confirmed by cross-model review**; LOW-002 (I added `trials_planned` at :1156, reproduced).
- DISS-C-005 (LOW, :1009) — symlink check-then-open. **Confirmed by cross-model review**; LOW-006.

## Rejected dissent payloads

None — `metadata.rejected_summary` is empty, `metadata.rejected_sidecars` is `[]`, and no `adversarial-rejected-audit*.jsonl` sidecar exists beside the envelope.

---

## Review Demotions Confirmed

The review trailer records `excluded: 0`; there is no demoted HIGH to confirm. `excluded_confirmed: 0`.

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added (grep of the diff: none; fixture STATUS.json holds planted spend figures only)
- [ ] Input validation on all new inputs — `arm` reaches a path unvalidated (LOW-001); free-text versions reach `int()`/`sorted()` (HIGH-002); listed rows reach the version vote (HIGH-001)
- [x] Authentication required where needed (n/a — offline CLI)
- [ ] No injection vulnerabilities — Markdown table/heading injection from STATUS.json / rows (LOW-002); no SQL/shell: `yq` runs with a fixed argv, no `shell=True`
- [ ] Error handling doesn't leak info / fails closed — uncaught exceptions print a traceback and leave no output (HIGH-002); `Fail` paths are clean
- [x] Writes confined — only `--out`/`--json`, symlink refused (`write_out`); the report never writes beside the manifests (verified: no files created under the fixture tree)
- [ ] Tests cover security paths — no test for mixed grader versions, a smoke batch at a newer version, or a traversal arm

---

## Rubric Scores

| Dimension | Score | Basis |
|---|---|---|
| SEC-IV Input Validation | 3 | schema/major/type checks on rows and manifests are good; arm grammar and version strings unchecked at the reader (HIGH-002, LOW-001) |
| SEC-IN Injection Prevention | 4 | `md_cell` used almost everywhere; three raw interpolations (LOW-002); no shell/SQL surface |
| SEC-AV Availability/Resilience | 2 | a single malformed file aborts the whole report (HIGH-002) |
| ARCH-MO Modularity | 4 | `render_*`/`analyse`/`h1a4` split is clean; `batch_record` oversized (LOW-007) |
| CQ Correctness | 3 | partition over listed rows (HIGH-001), string-version split (MED-001), sensitivity guard (MED-002) |
| DevOps / Tests | 3 | strong fixture coverage; two tests jq-version-dependent (MED-003), one scenario unvalidated (LOW-005) |

---

## Next Steps

**CHANGES_REQUIRED:**
1. Fix HIGH-001 (partition on decided rows only) and HIGH-002 (total-order ASCII version keys; wrap `batch_record()`; consider a top-level `except Exception` that exits 2 with the cause) with the bats cases named above.
2. Decide MED-001 (string version parsing) and MED-002 (sensitivity guard treatment); neutralise the jq formatting dependency (MED-003).
3. Address the LOW items opportunistically; LOW-001 and LOW-002 are one-line guards each.
4. Re-run `evals/tests/ablation-report.bats` and `evals/tests/ablation-row.bats` against the real suite, then `/review-sprint sprint-1` and `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":3,"low":7},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-22T06:56:32Z"} -->
