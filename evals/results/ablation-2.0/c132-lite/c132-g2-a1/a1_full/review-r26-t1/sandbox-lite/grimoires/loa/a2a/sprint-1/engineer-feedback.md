# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)
**Change under review:** `pr/head.diff` — sprint-262: ablation-row.sh 1.2 (defects_missed, regressions_final_green) and ablation-report.py 1.2.0 (suite_version partition, H1/A4 read states, degenerate pairs, sensitivity H1/A4 lines, batch record, precision, budget-matched baseline)

---

## Overall Assessment

The row-writer half of the change is clean: `defects_missed` and `regressions_final_green` are derived defensively in jq, validated as optional additive fields, documented in the header, and covered by five new bats cases whose assertions I checked against the jq program (including jq's `or` short-circuit protecting `.defects_missed[]` on a non-array). The `--help` sed range tracks the header growth exactly as before.

The report half is large (≈590 added lines) and mostly sound — the partition-by-version refactor, the degenerate-pair guard, the `assess()` read ladder and the new JSON shapes all behaved as documented when I executed the head script on the PR's own generated fixtures (sandbox with a reconstructed suite; AR-23 … AR-32 and AR-35 pass). Two defects block the merge, both verified by running the head code on a concrete input:

1. `partition()` is fed every loaded row, including rows the analysis itself will only *list* (smoke batches, rows with no manifest). A smoke batch of a newer suite_version therefore becomes the **primary** version: the main sections, top-level JSON `h1`/`a4`/`decisions` and the `--partial` exit code describe an empty version while the real data is demoted to a secondary section.
2. The grader-version tally sort in `batch_record()` raises `TypeError` for grader_version strings of mixed shape ("1.2.11" next to "1.2.11-rc1"), which is not a `Fail`, so the whole report aborts with a traceback and nothing is written — in a section the header promises is "never fatal". Both dissent voices (gpt-5.5-pro, claude-headless) found this independently.

Also note: `reviewer.md` is the PR description and carries no `## AC Verification` section; the sprint's acceptance criterion here is the review itself, so this is recorded, not counted.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Functionality — listed rows choose the primary suite version

- **HIGH** (confidence: high) `head/evals/harness/ablation-report.py:845` — `partition()` builds the version set from *all* rows, so rows that `Analysis._classify` will never decide (smoke batches, batches without a manifest) can become the primary version and empty the main sections.
**File:** `head/evals/harness/ablation-report.py:845` (key set), `:861` (primary = max), `:1403` (called on the raw `rows`)
**Issue:** The header promises "rows of a smoke batch … not decided, listed" (`head/evals/harness/ablation-report.py:68`) and "the main sections report … the highest present" (`:53-54`). Combining the two: a smoke batch run against the next suite version (the normal way to validate a suite before a batch) carries `suite_version: 3` while the real batch is `suite_version: 2`. Verified with the head script: 3 smoke rows at v3 appended to the `versions` fixture gave `primary_suite_version: 3`, `H1: not yet decidable (no pair)`, every decision `no_rows`, `--partial` exit 1, and the 24 real v2 rows were pushed into "## Suite version 2 … reported separately". Two manifest-less rows at v3 produced the same inversion (exit 0, so no signal at all). The same root cause makes `partition()` raise exit 2 for a *listed* row lacking `suite_version` when two versions are present (`:846-850`), blocking the report over a row that would never have entered a decision.
**Why This Matters:** The top-level JSON (`h1`, `a4`, `decisions`, `budget_matched`) is what the release notes and the regression-check recipe named in the PR consume; after this change they can silently describe the wrong version. `--suite-version` is a manual workaround, not a fix.
**Required Fix:** Partition only rows that survive the listing step (e.g. run `_classify`'s listing predicates — no manifest, smoke, arm not run, unknown type — before `partition()`, or have `partition()` take `mans` and skip rows whose batch is missing or `smoke: true`). Add a bats case: smoke batch at a higher `suite_version` beside a real batch → primary stays the real one; a listed row without `suite_version` does not exit 2.

### 2. Robustness — grader-version sort key mixes int and str

- **HIGH** (confidence: medium) `head/evals/harness/ablation-report.py:1082` — `sorted(gv.items(), key=…[int(p) if p.isdigit() else p …])` compares an `int` with a `str` whenever two `grader_version` values differ in shape at the same dot-segment; Python raises `TypeError`, which `main()` does not catch (`:1673-1676` catch `Fail` only), so no `report.md`/`report.json` is written.
**File:** `head/evals/harness/ablation-report.py:1082`
**Issue:** Verified: adding `{"grader_version": "1.2.11-rc1"}` to `pr-2/a0_bare/rc-01-t3/grade.json` in the `present` fixture → `TypeError: '<' not supported between instances of 'str' and 'int'` from `batch_record`, exit 1, both output files absent. The docstring at `:994` says this section is "reported, never fatal", and `grader_version` is free-form text read from grade.json; a batch re-rowed across a dev/rc grader build is exactly where mixed values appear. Confidence is medium only because the shipped graders (1.2.5 … 1.2.13) all emit pure numeric semver.
**Why This Matters:** An informational tally takes down the decision sections. CWE-248 (uncaught exception) in an operator-facing CLI that is otherwise careful to exit 2 with a named cause.
**Required Fix:** Use a total-order key, e.g. `tuple((0, int(p)) if p.isdigit() else (1, p) for p in parts)`, and/or wrap the whole `batch_record()` call so any exception degrades to `status_note` rather than aborting. Add a bats case with two grader_version strings of different shape in one batch.

---

## Observations

### 1. Correctness (non-blocking)

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-report.py:835` — `version_key` normalises `1`, `1.0` and `"1"` but not `"1.0"`/`"2.0"` strings; such a row forms its own version and, via `version_order` (`:839-840`, non-digit keys sort after digit keys), becomes the **primary**. Verified: setting `a0_bare` rows to `"2.0"` in the `degraded` fixture gave `by_suite_version` keys `["2","2.0"]`, `primary_suite_version: "2.0"`, and H1 "not yet decidable (no pair)" because a1 and a0 were split across versions. The row schema admits a string `suite_version` (ablation-row.sh `--validate`, `head/evals/harness/ablation-row.sh:147`), and the row writer copies it from the manifest/pipeline/task YAML, where `"2.0"` is a plausible spelling.
**Suggestion:** Parse `\d+(\.0+)?` (or any float-looking string that is integral) to the integer key; sort unknown strings *before* numeric keys, or refuse them with a `Fail`.
**Benefit:** Prevents a silent version split that reads as "no pair" instead of as a data problem.

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-report.py:1191` — the sensitivity H1/A4 lines are read from an `Analysis(cap_excluded=True, …)` through `assess()` (`:870-871`), whose degradation guard counts every excluded cell — including the cap failures this very figure exists to exclude. Verified: two cap-failure a1 trials per task in the `degenerate-2` fixture make the main H1 "not established" but the sensitivity H1 "inconclusive by degradation (a1_full excluded share 0.667 > 0.25)". The pre-existing per-arm sensitivity rows have the same property, but the new H1/A4 lines present it as a *state*, which reads as degradation where there is none.
**Suggestion:** Pass the cap-failure exclusions out of the share for the sensitivity read (e.g. `excluded_share(..., ignore_reason="cap_failure (sensitivity figure)")`), or state in `SENS_H_TREATMENT` that cap failures count toward the guard.
**Benefit:** The sensitivity line answers the question it is labelled with.

- **LOW** (confidence: medium) `head/evals/harness/ablation-report.py:913` — when the H1 reads are a mix of `inconclusive_by_degradation` and `no_pair`/`degenerate`, the line collapses to "not yet decidable (no pair)" and the degradation signal survives only in the per-comparison `read_text`. The header (`:118-120`) describes the degradation line as applying when "every testable primary" is degraded; a `no_pair` primary is arguably not testable yet. Consider treating `no_pair` like `not_testable` in the `live` filter, or documenting the current reading.

- **LOW** (confidence: low) `head/evals/harness/ablation-report.py:835` and `:1611` — a literal row value `"n/a"` passes `version_key` as a real key and collides with the "no version" sentinel used by `partition()` (`:852`) and `primary_suite_version` (`:1611`, which would then emit `null` for a present version). Reject non-numeric strings or use a non-string sentinel.

### 2. Testing

- **MEDIUM** (confidence: medium) `head/evals/tests/ablation-report.bats:487` and `:498` — AR-33 and AR-34 compare `jq -r` output of integral floats against `"1.0"`, `"3.0"`, `"10.0"`. jq 1.6 prints these as `1`, `3`, `10` (jq ≥ 1.7 preserves the literal); both tests fail on this host's jq 1.6 while every other new test (AR-23 … AR-32, AR-35) passes. No pre-existing AR test depended on this formatting. Either pin the jq version the CI fast gate installs (I could not verify it from the PR), or compare with `jq '… == 1.0'` / format through `tostring` with a fixed precision.

- **LOW** (confidence: high) `head/evals/tests/ablation-report.bats:290` — AR-20 validates every planted scenario with `ablation-row.sh --validate` except the new `present` scenario, which is the one that overrides `false_positives` and plants `defects_missed` variants most heavily. Add `present` to the list.

### 3. Security / hardening

- **LOW** (confidence: low) `head/evals/harness/ablation-report.py:1054` — `os.path.join(d, r["arm"])` uses the row's `arm` string as a path component. `load_rows` (`:363-366`) only checks it is a non-empty string; the arm grammar `^[a-z][a-z0-9_]{0,63}$` is enforced by the row writer, not the reader. A hand-edited row with `arm: "../../x"` makes the report list and read `grade.json` files outside the manifests tree (read-only, JSON-parsed, only `grader_version` surfaced). CWE-22. Validate `arm` against the grammar in `load_rows`, or `realpath`-check that `ad` stays under `d`.

### 4. Complexity (SIMPLICITY)

- **LOW** (confidence: high) `head/evals/harness/ablation-report.py:992-1085` — `batch_record()` is ~95 lines with four levels of nesting (status parsing, listing, dir matching, grade reading). Splitting the STATUS.json parse (`:1011-1047`) and the grader-version tally (`:1049-1083`) into two helpers would bring each under 50 lines and give the "never fatal" wrapper (finding 2) a single seam. `budget_matched()` (`:937-989`) is at the limit but reads linearly. The `build()` refactor into `render_*` helpers is a net improvement. Over-engineering pass: Lean already apart from this. `net: -0 lines possible`.

---

## Cross-Model Observations

Adversarial review envelope `grimoires/loa/a2a/sprint-1/adversarial-review.json` (primary gpt-5.5-pro via codex-headless, companion claude-headless, both succeeded, 3 findings):

- BLOCKING ×2 (both voices) — `batch_record` grader-version sort `TypeError`. **Counted** as Changes Required 2 above (I reproduced it).
- ADVISORY (claude-headless) — `budget_matched` indexes every trial's defect vector by `len(vecs[0][0])`. **Not a defect:** `defect_vector` sizes every vector by `self.task_defects[task_id]` (`head/evals/harness/ablation-report.py:541-551`), the per-task max of `defects_seeded`, so all vectors of one task have equal length; the `"none"` case returns `None` and is screened by the `all(vv is not None …)` test at `:960`.

## Rejected dissent payloads

None — `metadata.rejected_summary` is empty and the named sidecar `adversarial-rejected-review.jsonl` has zero rows.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | The two HIGH findings above (primary-version selection from listed rows; uncaught `TypeError` in the batch record) |

---

## Acceptance Criteria Check

### Task 1.1: review the pull request, report each defect with file and line, give a merge verdict

| Criterion | Status | Notes |
|-----------|--------|-------|
| ablation-row.sh 1.2 carries `defects_missed` / `regressions_final_green` (bd-yz1rd, bd-m0hw7) | Pass | `head/evals/harness/ablation-row.sh:410-414`; validate at `:165-170`; 5 bats cases `head/evals/tests/ablation-row.bats:403-479` |
| suite_version partition, never pooled | Fail | Correct for decided rows; listed rows leak into the partition (Changes Required 1) |
| not-testable / not-yet-decidable / degradation / degenerate reads | Pass | `assess()` `:864-878`, `h1a4()` `:898-934`; AR-25 … AR-29 pass in the sandbox |
| Sensitivity H1/A4, batch record, precision, budget-matched (informational) | Partial | Batch record can abort the report (Changes Required 2); sensitivity guard counts cap failures (Observation) |
| "none of them changes a decision, an H1/A4 state or an existing number" | Pass | AR-35 passes; decisions/h1 JSON of main/boundary/exclusions unchanged in shape |
| Fast-gate parity (formatter / type checker) | Unverified | `FAST-GATE:` the PR carries no record of a lint/format run for the Python or bats files; nothing in the PR files lets me confirm it. |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [ ] Input validation and sanitization present — `arm` reaches a filesystem path unvalidated (Observation 3, LOW)
- [x] Authentication/authorization correct (n/a — offline CLI)
- [x] No SQL/XSS injection vulnerabilities (markdown cells escaped via `md_cell`)
- [x] Dependencies secure (stdlib only; `yq` subprocess with a fixed argv)
- [x] Error messages don't leak sensitive data

---

## Code Quality Summary

**Strengths:**
- The jq derivations in the row writer fail soft to `null` on every unexpected shape and the validator keeps the fields optional, so pre-1.2 rows still validate (tested).
- `assess()`/`read_text()` make the H1/A4 reading an explicit, testable ladder; `usable()` threads the degenerate rule through `decide()` and `decidable` consistently.
- Fixture generator scenarios are well-documented and each new behaviour has a dedicated AR test; `write()` creates STATUS.json and run dirs read-only from the report's point of view (verified: no writes beside the manifests).

**Areas for Improvement:**
- Partition on the rows the analysis will actually decide, not on the raw load.
- Informational sections must not have a crash path; wrap them or make their keys total-ordered.
- Tests should not depend on jq's float-literal rendering.

---

## Next Steps

1. Fix Changes Required 1 and 2 with the bats cases named there.
2. Decide on the `"2.0"` string handling and the sensitivity guard treatment (Observations), and pin or neutralise the jq formatting dependency.
3. Re-run `evals/tests/ablation-report.bats` and `evals/tests/ablation-row.bats` against the real suite file.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":3,"low":5},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T06:45:06Z"} -->
