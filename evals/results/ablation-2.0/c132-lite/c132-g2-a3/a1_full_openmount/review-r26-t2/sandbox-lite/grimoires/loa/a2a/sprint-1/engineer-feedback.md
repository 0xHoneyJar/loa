# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description)
**Change under review:** `pr/head.diff` — sprint-262: ablation-row.sh 1.2 (defects_missed, regressions_final_green) and ablation-report.py 1.2.0 (suite_version partition, H1/A4 read states, degenerate pairs, sensitivity lines, batch record, precision, budget-matched baseline), with the bats and fixture generator

---

## Overall Assessment

The row-writer half of the change is sound: the two new fields are derived defensively, `--validate` accepts legacy rows without them, and the five new tests pass (see Verification below). The report half is well structured — `build()` is partly decomposed into `render_*` helpers, every new state is covered by a planted-row test, and the degenerate-pair and degradation-guard logic reads correctly on inspection and under test.

Three defects block the merge, all in the new code of `ablation-report.py`:

1. The batch record's grader-version sort compares `int` against `str` and raises an uncaught `TypeError` that aborts the whole report (no report.md, no report.json) — in a section documented as "never fatal".
2. The suite-version partition does not normalise string versions as its docstring claims, and ranks every non-numeric string above every number, so one row with `suite_version: "1.0"` or `"v2"` silently becomes the primary version and empties the main sections.
3. The primary version is chosen over rows the report itself never decides (smoke batches, batches without a manifest), so a smoke batch tagged with a newer suite_version turns the headline into "H1: not yet decidable" while the decided rows establish it in a secondary section.

The adversarial dissent (two independent voices, `gpt-5.5-pro` answered by `codex-headless` and `claude-headless`) found defect 1 and independently confirmed defects 2 and 3 plus the three low observations below.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Functionality — the batch record can abort the whole report

- **HIGH** (confidence: high) `head/evals/harness/ablation-report.py:1081-1082` — the grader_versions sort key is `[int(p) if p.isdigit() else p for p in re.split(r"[.]", kv[0])]`; two grader_version strings whose components differ in numeric-ness make Python compare `int` with `str` and `sorted()` raises `TypeError`.
**File:** `head/evals/harness/ablation-report.py:1081-1082`
**Issue:** Reproduced: with `grade.json` files carrying `"1.2.0-dev"` and `"1.2.5"` under one batch's run directories the report dies with
```
    e["grader_versions"] = dict(sorted(gv.items(), key=lambda kv: (
TypeError: '<' not supported between instances of 'int' and 'str'
```
exit 1, no report.md or report.json written. `"1.2.11"` beside `"dev"` or `"2"` beside `"2-rc1"` fail the same way. The `"n/a"` sentinel is protected by the leading boolean in the tuple; real versions are not. The exception is not a `Fail`, so `main()` does not catch it, and the header (`head/evals/harness/ablation-report.py:139`) and the docstring (`head/evals/harness/ablation-report.py:994`) promise the batch record is "never fatal".
**Why This Matters:** The batch record is informational, yet one unusual grader tag anywhere in the batch tree takes down the decision report, including the H1 line the harness gates promotion on.
**Required Fix:** Make every component self-comparable, e.g. `[(0, int(p)) if p.isdigit() else (1, p) for p in kv[0].split(".")]`, and add a planted test with a non-numeric grader_version component beside a numeric one (the `present` fixture already has two run dirs with grade.json — give one `"1.2.0-dev"`).

### 2. Functionality — string suite_versions split from their numeric twin and win the primary slot

- **HIGH** (confidence: medium) `head/evals/harness/ablation-report.py:835` — `version_key` folds only `\d+` strings, so `"1.0"` stays `"1.0"` while the float `1.0` becomes `"1"`, contradicting the docstring at line 826 ("1, 1.0 and "1" are one version"); and `head/evals/harness/ablation-report.py:840` — `version_order` returns `(1, 0, k)` for any non-digit key, above every numeric `(0, n, "")`, so `partition()` (line 861) makes the string version the default primary.
**File:** `head/evals/harness/ablation-report.py:835`, `head/evals/harness/ablation-report.py:840`
**Issue:** Reproduced on the `main` fixture: changing one row's `suite_version` to `"1.0"` yields `primary_suite_version: "1.0"`, every component "no rows", `H1: not yet decidable (no pair)`, and the 155 real rows demoted to the "reported separately" section; `"v2"` behaves the same. Because two keys now exist, any row lacking `suite_version` turns into an exit-2 failure, and `--suite-version 2.0` is refused with "no row has that suite_version (present: 1, 2)". The row writer admits strings (`need("suite_version"; ["number","string","null"])`, `head/evals/harness/ablation-row.sh:147`), and takes the value from the manifest, pipeline.json or task YAML, so a quoted version in any of those produces such rows.
**Why This Matters:** A single stray row silently rewrites the headline decisions; nothing in the report says why the primary is a version no batch was planned under.
**Required Fix:** Normalise numeric strings via `float()` (`"1.0"` → `"1"`, `"2.0"` → `"2"`), apply the same normalisation to `--suite-version`, and rank non-numeric strings below numeric versions (or refuse them with exit 2, naming the row). Add a test with a `"1.0"`-typed row beside integer-1 rows.

### 3. Functionality — rows that are never decided choose the primary version

- **HIGH** (confidence: medium) `head/evals/harness/ablation-report.py:845` — `partition()` computes the version keys over every deduplicated row, including rows `Analysis` only lists (smoke batches, batches without a manifest, non-applicable arms), and line 861 picks the maximum as the primary.
**File:** `head/evals/harness/ablation-report.py:845`, `head/evals/harness/ablation-report.py:861`
**Issue:** Reproduced twice on the `main` fixture: (a) tagging the existing `smoke-260` smoke batch `suite_version: 3` makes 3 the primary — all six components read `no_rows`, `H1: not yet decidable (no pair)`, `A4 … not testable on suite_version 3`, `--partial` exits 1 — while `by_suite_version["1"].h1.line` is `H1: established`; (b) one row of a batch with no manifest tagged 9 does the same. `--suite-version 1` restores the correct report, but the default is what the unattended harness reads. `--manifests DIR` walks the whole tree (`head/evals/harness/ablation-report.py:375`), so a smoke run of the next suite version beside the decided batches is the normal layout, not a contrived one.
**Why This Matters:** The header documents the default as "the highest present" (line 53), but "present" here includes rows DEC-0393 says are "listed, never decided"; the headline H1/A4 lines and the `--partial` exit code are then driven by rows that contribute nothing. The dissent rated this advisory because the override exists; I keep it blocking because the default is the path the harness takes.
**Required Fix:** Choose the default primary among rows that will enter a decision — reuse the smoke / no-manifest / arm-applicability predicates of `Analysis._classify` in a cheap pre-pass — and fall back to the current rule only when no such rows exist. Keep `--suite-version` as the explicit override. Add a test with a smoke batch at a higher suite_version.

---

## Observations

### 1. Complexity

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-report.py:992-1085` — `batch_record()` is 94 lines mixing STATUS.json parsing, tallying and a filesystem walk; `build()` (`head/evals/harness/ablation-report.py:1379-1637`) stays at ~260 lines even after the `render_*` extraction.
**Suggestion:** `SIMPLICITY[shrink]`: split `batch_record` into a STATUS.json reader and a grader-version walker; move the header/provenance block and the JSON assembly of `build()` into helpers like the renderers already extracted. net: -40 lines possible.
**Benefit:** Each piece becomes testable on its own and the TypeError above would have been one small function's bug.

### 2. Presentation

- **LOW** (confidence: high) `head/evals/harness/ablation-report.py:1156` — `trials_planned` from STATUS.json is interpolated raw into the batch-record table while every neighbouring cell goes through `md_cell()`. Reproduced: `"trials_planned": "20 | x"` shifts the row's columns (`| 20 | x / 18 |`).
**Suggestion:** `md_cell(e['trials_planned']) if e['trials_planned'] is not None else 'n/a'`.
**Benefit:** The table survives a sidecar the report does not control.

### 3. Documentation vs code

- **LOW** (confidence: high) `head/evals/harness/ablation-report.py:147` and `head/evals/harness/ablation-report.py:959` — the header says rate fallback applies to "a task whose a0 rows carry none" of the per-defect ids, and the rendered note says "where the rows carry no per-defect ids", but the code falls back when ANY valid a0 trial lacks ids (`all(... how in ("ids", "cap"))`).
**Suggestion:** Align the header and `render_budget` text to "when any valid a0 trial lacks per-defect ids", or compute the union over the id/cap trials and name the dropped trials in `reason`.
**Benefit:** The `method` column means what it says.

### 4. Path handling (read-only)

- **LOW** (confidence: medium) `head/evals/harness/ablation-report.py:1054` — `os.path.join(d, r["arm"])` uses a row's `arm` as a path component; `load_rows` only checks it is a non-empty string (the arm grammar `^[a-z][a-z0-9_]{0,63}$` lives in the row writer). A row with `"arm": "../.."` lists a parent directory and reads any `<task_id>-t<n>/grade.json` there.
**Suggestion:** Reject (or skip with a note) arms that fail the grammar before touching the filesystem.
**Benefit:** Only `grader_version` is surfaced and symlinks are skipped, so the exposure is small; the check keeps it that way.

### 5. Process

- **LOW** (confidence: high) `grimoires/loa/a2a/sprint-1/reviewer.md:1` — the implementation report is the PR description (a commit list); it carries no `## AC Verification` walkthrough and no stated assumptions. The skill's automatic CHANGES_REQUIRED on a missing walkthrough is noted but not what drives this verdict — the defects above do. The PR description also lists CHANGELOG, README and release-notes commits that are not in the five-file diff; the documentation that is in scope (both script headers, the bats headers, the fixture header) is updated and accurate apart from Observation 3.
**Suggestion:** On resubmission, add an AC table (field, test, `file:line`) for the row writer fields and each report state.
**Benefit:** The reviewer can check claims instead of re-deriving them.

### 6. Cross-model observation triaged as not a defect

- DISS-C-004 (advisory, `assess` lines 867-868) suspected `not_testable` would pre-empt the degradation guard when every cell of a primary's task types is excluded in both arms. Checked: `compare()` records such tasks in `unpaired` ("every cell of … excluded", `head/evals/harness/ablation-report.py:591-598`), so `assess()` proceeds to the share check. Reproduced on the `degraded` fixture with every a1 row degraded: `defect_catch_rate` reads `inconclusive_by_degradation` and H1 reads "inconclusive by degradation — not established". Not a defect.

---

## Rejected dissent payloads

- none — `metadata.rejected_summary` is empty and the named sidecar `grimoires/loa/a2a/sprint-1/adversarial-rejected-review.jsonl` holds 0 rows (both voices succeeded, `counted_as: independent_voice`).

---

## Cross-Model Observations

Envelope: `grimoires/loa/a2a/sprint-1/adversarial-review.json` (status `reviewed`, 2/2 voices, `consensus`). DISS-001 and DISS-C-001 (BLOCKING, grader-version TypeError) → Changes Required 1. DISS-C-002 (BLOCKING, string versions) → Changes Required 2. DISS-C-003 (ADVISORY, listed rows choose the primary) → Changes Required 3. DISS-C-005 (trials_planned) → Observation 2. DISS-C-006 (rate fallback wording) → Observation 3. DISS-C-004 → Observation 6 (not a defect).

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

Sprint success criterion: "review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict". The PR's own claims (from the two script headers) checked against the code and the tests:

| Criterion (PR claim) | Status | Notes |
|-----------|--------|-------|
| Row writer 1.2: `defects_missed` = `recall.missed` on review-catch rows, `[]` when all caught, null otherwise | Pass | `head/evals/harness/ablation-row.sh:410-413`; 5/5 new tests pass |
| Row writer 1.2: `regressions_final_green` boolean or null | Pass | `head/evals/harness/ablation-row.sh:414`; tests pass |
| `--validate` accepts legacy rows without the keys, rejects wrong types | Pass | `head/evals/harness/ablation-row.sh:165-170` |
| Rows of different suite_version never pooled; default primary the highest present | Fail | Changes Required 2 and 3 |
| Row without suite_version among two versions → exit 2 | Pass | `head/evals/harness/ablation-report.py:847-851`, AR-24 |
| H1/A4 read states (not_testable → degradation → degenerate → no_pair → tested) | Pass | `assess()` 864-880; AR-25…AR-29 pass; fully-excluded case verified |
| Degenerate single-task rate-fallback pair read as no valid pair | Pass | `head/evals/harness/ablation-report.py:631-637`; AR-28/29 |
| Presentation items change no decision | Pass | AR-35; sensitivity lines labelled, separate Analysis |
| Batch record "a missing file or directory is reported, never fatal" | Fail | Changes Required 1 |
| Precision / cost per true defect, budget-matched baseline | Pass | AR-33/AR-34 values verified by hand (see Verification) |

---

## Verification performed

- The real `evals/suites/ablation-2.0.yaml` is not in the PR; a suite file was reconstructed from the code's expectations and the pre-existing tests. With it, `head/evals/tests/ablation-report.bats` runs 33/35: AR-33 and AR-34 fail only because this host has jq 1.6, which prints the literal `1.0` as `1`; the computed values (`a1_full` precision 1.0, USD 2.222222 / 27 / 27; `rc-01` union 1.0, cost 3.0, a1 0.875, 10.0, −0.125) match the assertions. The repository already requires jq ≥ 1.7 (the pre-existing `label,` keyword shorthand at `head/evals/harness/ablation-row.sh:383` does not compile under 1.6), so this is not a finding.
- The five new tests in `head/evals/tests/ablation-row.bats` (402-479) pass 5/5 against minimal fabricated run directories (the fixture runs are not in the PR), with only that pre-existing line patched in a scratch copy for jq 1.6.
- Reproductions for Changes Required 1–3 and Observation 2 were run on the generated fixtures (`present`, `main`, `degraded`).
- Security checklist: no secrets; inputs are read-only files; symlinks refused for STATUS.json / grade.json / MANIFEST.json / --out; the only trust-boundary gap is Observation 4.

---

## Next Steps

1. Fix the three Changes Required items and add the three named planted-row tests.
2. Run `evals/tests/ablation-report.bats` and `evals/tests/ablation-row.bats` with jq ≥ 1.7 and yq v4.
3. Update the report in `grimoires/loa/a2a/sprint-1/reviewer.md` with an AC Verification walkthrough.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":1,"low":4},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T14:20:00Z"} -->
