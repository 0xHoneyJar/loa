# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, pr/PR.md)
**Change under review:** pr/head.diff (12 files; citations are `head/<path>:<line>` with line numbers from `pr/head/`)

---

## Overall Assessment

The per-type run caps (DEC-0567), the `--types` filter fix, the KF-048 credential copy and the KF-048 token pre-flight are implemented as described, are read from the manifest on `--resume`, and carry tests that assert the exact numbers (RAB-22 … RAB-34, the three KF-048 pipeline-run cases). The spend accounting changes in `lib/arms-common.sh` keep their RUN_CAP defaults for other callers.

One change does not hold: grader 1.2.11's `remove_colliding` deletes files from the grading tree by **basename alone**, and its reserved set is every `.py` file under the fixture's test directories plus every hidden-overlay `.py` destination, not the test modules pytest actually collects. The grader's own 1.2.11 note (`head/evals/harness/ablation-grade.sh:221`) says fixture suites ship sibling modules such as `helpers.py` and `_oracle_x.py`; any correct solution that adds a module with one of those names anywhere in the tree is unlinked before the hidden tests run and graded as failing. That is the same failure class 1.2.11 was written to remove (a correct solution graded as failing), now triggered by a different and more common input. Both dissent voices reached this finding independently (DISS-001, DISS-C-001).

The report (pr/PR.md) carries no `## AC Verification` walkthrough; the verdict below already follows from the HIGH finding, so that is noted rather than counted.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Functionality — grader 1.2.11 deletes non-test modules from the grading tree

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:1087` — `reserved` takes every `.py` basename under a fixture `tests/` or `test/` directory (only `__init__.py` and `conftest.py` excepted), and line 1081 adds every hidden-overlay `.py` destination basename (including `__init__.py` when an overlay ships one; only `conftest.py` is discarded at line 1088). The walk at lines 1090-1100 then unlinks any file with a reserved basename anywhere in the agent's tree that is not an overlay dest and not present in the fixture. Concrete input: fixture has `tests/helpers.py` (the pattern the 1.2.11 note itself cites); the agent's correct solution adds `src/<pkg>/helpers.py`; the file is deleted before `test_command` runs; the hidden tests import the package, hit ImportError, and the trial is rowed as failing with its cost spent. Nothing surfaces except a line in `grading/<label>.colliding-removed.txt`.
**File:** `head/evals/harness/ablation-grade.sh:1081`, `head/evals/harness/ablation-grade.sh:1087`, `head/evals/harness/ablation-grade.sh:1090-1100`
**Issue:** The rationale for removal (pytest's "import file mismatch" abort) only applies to modules pytest collects as test modules in package-less directories: `test_*.py` / `*_test.py` (and `conftest.py`, already excluded). Helper modules, oracles and `__init__.py` never cause that abort, yet their basenames are reserved, and the removal is not limited to test directories.
**Why This Matters:** A grader that deletes part of a correct solution produces a false negative that is indistinguishable in `grade.json` from a real failure; it biases every arm's hidden_test_pass_rate on exactly the tasks whose fixtures ship helper modules, and it does so silently. This is a grading-validity defect in the instrument the H1/A4 conclusions (DEC-0597) rest on.
**Required Fix:** Restrict `reserved` to pytest-collectable test module basenames: from the fixture walk at line 1087 take only names matching the suite's `python_files` pattern (default `test_*.py` or `*_test.py`), and apply the same filter to the overlay-derived set at line 1081 (never reserve `__init__.py`). Prefer additionally limiting the removal walk to directories that are not packages (see Observation 1). Add an AG case: fixture `tests/helpers.py` plus an agent-added `src/pkg/helpers.py` must survive `prepare()` and `colliding_tests_removed` must stay 0.
**Reference:** pytest import modes documentation (prepend mode: package-less test modules are imported by basename; the mismatch error is raised for test modules only). Dissent corroboration: DISS-001 (gpt-5.5-pro), DISS-C-001 (claude-headless).

**Example:**
```python
# Current (problematic) — head/evals/harness/ablation-grade.sh:1081 and :1087
reserved = {d.rsplit("/", 1)[-1] for d in owned if d.endswith(".py")}
...
reserved.update(n for n in fs if n.endswith(".py") and n not in ("__init__.py", "conftest.py"))

# Should be — only modules pytest collects as test modules
TEST_MOD = re.compile(r"^(test_.*|.*_test)\.py$")
reserved = {b for b in (d.rsplit("/", 1)[-1] for d in owned) if TEST_MOD.match(b)}
...
reserved.update(n for n in fs if TEST_MOD.match(n))
```

---

## Observations

### 1. Grader — package modules are removed although they never collide

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:1090-1098` — the removal walk never checks for an `__init__.py` in the agent file's directory. Under pytest's default prepend mode `tests/extra/__init__.py` + `tests/extra/test_slug.py` is imported as `extra.test_slug` and does not collide with the package-less `tests/test_slug.py`; the docstring at line 1077 says the rule targets "package-less directories" but the code removes package modules too. The agent's own tests then vanish from `hidden_tests.total` (AG-35's comment at `head/evals/tests/ablation-grade.bats:1113` confirms agent tests are counted), skewing the pass rate in either direction. (DISS-C-003)
**Suggestion:** Skip files whose directory, or any ancestor up to the tree root, contains `__init__.py`.
**Benefit:** Removal happens only where pytest would actually abort collection.

### 2. Grader — directory overlays are not covered by the fix

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-grade.sh:1081` — only file-destination overlays feed `reserved`; an overlay whose source is a directory is recorded in `owned_dirs` (line 1080) and its inner `.py` files are never reserved. For a task whose hidden suite is delivered as a directory overlay, an agent `tests/test_slug.py` colliding with the overlay's `tests/hidden/test_slug.py` is left in place and the pre-1.2.10 "import file mismatch" abort still grades a correct solution as failing, while `grade.json` reports `colliding_tests_removed: 0`. (DISS-C-002)
**Suggestion:** Walk directory overlays and add their collectable test-module basenames to `reserved`.
**Benefit:** The 1.2.11 guarantee holds for every overlay shape `put_file` accepts.

### 3. Codex pre-flight — the horizon and the arm set over-approximate

- **MEDIUM** (confidence: medium) `head/evals/harness/run-ablation.sh:806` — `required` is now + 2 × Σ watchdog_s / concurrency, but `watchdog_s` is already twice the phase-sum timeout (RAB-1's comment at `head/evals/tests/run-ablation.bats:93`), so the horizon is four times the phase sum per trial and, on `--resume`, counts trials already rowed. With a ~10-day token (DEC-0593) a plan of roughly 100 a1_full build trials at concurrency 3 already fails the check even though the watchdog guarantees the batch ends in half that time. Line 792 (`uses_codex`) also counts `a4_no_gates` (phases PLAN, IMPLEMENT; no dissent) as codex-using, so an a4-only batch is refused for a credential it never uses. Fail-closed, and documented at lines 110-120, so not blocking. (DISS-C-005)
**Suggestion:** Use Σ watchdog_s / concurrency over the trials still to run (watchdog_s is the hard deadline), and derive the codex arm set from the planned phases (REVIEW or AUDIT present) rather than `loa_mount`.
**Benefit:** Legitimate batches and resumes are not refused; the pre-flight still catches the KF-048 case.

### 4. Grader — `colliding_tests_removed` sums over prepared trees

- **LOW** (confidence: high) `head/evals/harness/ablation-grade.sh:1019` — `COLLIDING[0] += remove_colliding(t, tree)` runs on every `prepare()` call (final at line 1708, base at 1723, each graded snapshot at 1748), so one agent file removed from three trees reports 3. It mirrors `harness_files_removed`, and AG-35 grades a single tree, so the multiplication is untested. (DISS-C-004)
**Suggestion:** Count distinct paths across trees, or document the field as a per-tree sum next to `harness_files_removed`.
**Benefit:** Batch-level sums and `> 0` filters on the field are not inflated.

### 5. Tests — the suite depends on artifacts outside this change

- **LOW** (confidence: medium) `head/evals/tests/seed-bugfix.bats:80` — the test passes `--suite-version` to `seed-bugfix.sh` (and `head/evals/tests/seed-refactor.bats:78` to `seed-refactor.sh`); neither script is in the diff and the base tests did not use the flag. RAB-27 (`head/evals/tests/run-ablation.bats:104`) expects exactly twelve build task directories and four review tasks with `suite_version: 2` under `grimoires/loa/evals/ablation-2.0/tasks`, plus a re-frozen MANIFEST.sha256; none of these are in the 12 reviewed files. [ASSUMPTION] They landed in the same cycle, but it cannot be verified from the PR. (DISS-C-006)
**Suggestion:** Confirm the companion commits are on the target branch before merge (run `evals/tests/*.bats` on the merged tree).
**Benefit:** The green state asserted by the PR description is reproducible from the merged tree.

---

## Rejected dissent payloads

None. `metadata.rejected_summary` is empty and the named sidecar `adversarial-rejected-review.jsonl` has zero rows; the companion produced no sidecar.

---

## Cross-Model Observations

Envelope `grimoires/loa/a2a/sprint-1/adversarial-review.json`: status reviewed, primary gpt-5.5-pro, companion claude-headless (independent voice), not degraded, 7 findings. DISS-001 and DISS-C-001 (BLOCKING) are the HIGH above; DISS-C-002, DISS-C-003, DISS-C-004, DISS-C-005 and DISS-C-006 (ADVISORY) are Observations 2, 1, 4, 3 and 5. No dissent finding was discarded.

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff` (goals as stated in pr/PR.md)

| Criterion | Status | Notes |
|-----------|--------|-------|
| Per-type run caps: suite `run_usd_by_type`, `--run-cap` override, manifest record, per-kind dispatch and assumed charges, max-cap in-flight reserve, `--resume` reads the manifest | Pass | `head/evals/harness/run-ablation.sh:500-515`, `:850-854`, `:1043-1053`; asserted by RAB-22 … RAB-26 |
| `--types` filter selects by the task's type | Pass | `head/evals/harness/run-ablation.sh:565`; RAB-27 |
| KF-048: container gets an access-token-only credential, host file untouched, 0600, unreadable file → one WARN and no credential | Pass | `head/evals/harness/pipeline-run.sh:622-645`; three pipeline-run cases at lines 938-985 |
| KF-048: batch pre-flight refuses a token that expires before the horizon, records `codex_preflight`, skips on `--smoke`, warns on a missing file | Pass (see Observation 3) | `head/evals/harness/run-ablation.sh:780-840`; RAB-28 … RAB-34 |
| Grader 1.2.11: colliding agent test files removed so a correct solution is not graded as failing | Fail | Removal keyed on every `.py` basename deletes non-test modules of a correct solution (Changes Required 1); AG-35 covers only the `test_*.py` shape |
| Suite v2 frozen (`suite_version: 2`, v2 task ids) | Not verifiable here | Task directories and MANIFEST.sha256 are outside the reviewed files (Observation 5) |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (the only literal is the placeholder refresh token, by design)
- [x] Input validation at trust boundaries: per-kind caps validated with `usd_ok` and malformed suite entries refused (`head/evals/harness/run-ablation.sh:500-507`); auth.json parsed with `python3 -I`, paths passed via argv
- [x] Credential handling: the host refresh token never reaches the container; token values never appear in argv, logs or REFUSED.txt (asserted at `head/evals/tests/pipeline-run.bats:960` and `head/evals/tests/run-ablation.bats:889-891`)
- [x] No injection vectors introduced (jq `--arg`, Python argv, no eval)
- [x] Error messages don't leak sensitive data (only exp instants are printed)
- [ ] Dependencies: n/a (no new dependencies)

---

## Code Quality Summary

**Strengths:**
- Every behavioural change ships a test that asserts the exact amounts (RAB-24's 37.5, RAB-25's 27.99/28 boundary, RAB-30's horizon window).
- The KF-048 fix is minimal and correctly scoped: one key replaced, mode 0600, fail-soft with a single WARN.
- The `--types` fix is a one-expression change with a regression case (RAB-27).

**Areas for Improvement:**
- `remove_colliding` reasons about pytest's collection rule but encodes a broader rule than pytest applies (see Changes Required 1, Observations 1-2).
- Complexity: functions stay under the 50-line threshold and nesting under 3; no over-engineering found. Lean already. Ship (after the fix above).

---

## Next Steps

1. Narrow `reserved` in `remove_colliding` to collectable test-module basenames and add the `helpers.py` regression case (Changes Required 1).
2. Decide on the package check and directory-overlay coverage (Observations 1-2) in the same grader bump.
3. Re-run `evals/tests/ablation-grade.bats` and `evals/tests/run-ablation.bats` on the merged tree.
4. Update the report in `grimoires/loa/a2a/sprint-1/reviewer.md` with an `## AC Verification` walkthrough and request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":3,"low":2},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T06:17:28Z"} -->
