# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Change under review:** `pr/head.diff` (12 files; harness, suite file, bats)

---

## Overall Assessment

The change bundles four things: per-task-kind run caps in `run-ablation.sh` (DEC-0567), the KF-048 codex credential handling (placeholder refresh token in `pipeline-run.sh`, access-token expiry pre-flight in `run-ablation.sh`), the `--types` jq fix, and grader 1.2.11's basename-collision cleanup in `ablation-grade.sh`. The cap plumbing, the pre-flight and the credential copy are careful and well tested: caps flow to dispatch, assumed charges and the in-flight reservation; `--resume` keeps the manifest's caps; no token value reaches argv or any log; the host `auth.json` is never written.

The grader change is the problem. `remove_colliding` reserves every `.py` basename found under the fixture's `tests/`/`test/` directories and every `.py` basename in the hidden overlay (including `__init__.py`), then walks the **whole** grading tree and unlinks any agent-added file with a reserved basename, wherever it lives. Pytest's import-file-mismatch abort only concerns collected test modules in package-less directories, so this deletes implementation modules a correct solution depends on (a fixture `tests/helpers.py` deletes the agent's `src/pkg/helpers.py`) and grades the solution as failing, silently except for a counter. That is the exact failure class 1.2.11 set out to remove. Both dissent voices reached the same conclusion independently (DISS-001, DISS-C-001). Directory overlays, which `load_task` allows, contribute nothing to the reserved set, so the guard is a no-op for them (DISS-002, DISS-C-002).

`reviewer.md` is the PR description and carries no `## AC Verification` section; with the brief standing in for the sprint plan that is noted, not counted.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Functionality — grader 1.2.11 deletes non-test modules by basename

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:1081-1100` — `reserved` is built from every fixture `.py` under a `tests/`/`test/` component (line 1087) and every overlay `.py` dest (line 1081); the walk at lines 1090-1100 then unlinks any agent-added file in the tree whose basename matches, with no restriction to collected test modules (`test_*.py` / `*_test.py`) or to package-less directories. Concrete failing input: fixture `tests/helpers.py` (the header at line 220 says fixture suites rely on `from helpers import …`), agent adds `src/pkg/helpers.py` and imports it from the solution. `helpers.py` is reserved; `src/pkg/helpers.py` is not in `owned`, not under `owned_dirs`, not in the fixture → unlinked at line 1100. The hidden suite then fails with `ModuleNotFoundError`; `grade.json` records `hidden_tests` failed and `colliding_tests_removed: 1`. A correct solution is graded wrong, silently.
**File:** `head/evals/harness/ablation-grade.sh:1081-1100`
**Issue:** The docstring (lines 1075-1078) scopes the rule to "package-less test modules" pytest imports by basename, but the code neither restricts `reserved` to test-module names nor checks whether the candidate sits in a package (`__init__.py` sibling) or in a directory the `test_command` collects at all. `tests/utils.py`, `tests/common.py`, `tests/fixtures/sample.py` all reserve names agents commonly add under `src/`.
**Why This Matters:** Every row of the Sprint 261 calibration batches is graded by this code. Arms that add modules (A1 with a sprint plan tends to) lose files; A0 BARE, which edits in place more often, does not. H1 (DEC-0597, `+0.263`) was computed under 1.2.11 and is exposed to this bias.
**Required Fix:** (a) Restrict the fixture-derived and overlay-derived `reserved` sets to names pytest collects: `test_*.py` and `*_test.py` (and drop `__init__.py`/`conftest.py` from the overlay-derived set as well, see finding 2). (b) Only unlink a candidate that pytest would import by basename: a file in a directory with no `__init__.py`, under a root the task's `test_command` collects. (c) Add a bats case: fixture `tests/helpers.py`, agent-added `src/pkg/helpers.py` imported by the solution, assert the file survives and `colliding_tests_removed` is 0.
**Reference:** pytest docs, "Import modes" (prepend/append: module name is the basename when no `__init__.py` is present; the mismatch error applies to collected test files).

**Example:**
```python
# Current (problematic): any .py under tests/ reserves its basename for the whole tree
reserved.update(n for n in fs if n.endswith(".py") and n not in ("__init__.py", "conftest.py"))

# Should be: only names pytest collects as test modules
def is_test_module(n):
    return n.endswith(".py") and (n.startswith("test_") or n.endswith("_test.py"))
reserved.update(n for n in fs if is_test_module(n))
# and at the candidate: skip files inside a package
if os.path.exists(os.path.join(r, "__init__.py")):
    continue
```

### 2. Functionality — an overlay `__init__.py` reserves `__init__.py` tree-wide

- **HIGH** (confidence: medium) `head/evals/harness/ablation-grade.sh:1081` — the overlay-derived set `{d.rsplit("/", 1)[-1] for d in owned if d.endswith(".py")}` has no exclusion list; the exclusions at line 1087 apply only to the fixture walk and line 1088 discards only `conftest.py`. A hidden overlay that ships `tests/__init__.py` (or any package marker) puts `__init__.py` in `reserved`, and every package initializer the agent created (`src/newpkg/__init__.py`) that is not in the fixture is unlinked at line 1100. The agent's new package stops being importable; the hidden suite fails.
**File:** `head/evals/harness/ablation-grade.sh:1081`
**Issue:** Asymmetric exclusions between the two sources of `reserved`. Confidence medium because it depends on a task overlaying an `__init__.py`; the suite tasks are not in this diff so it cannot be ruled out here.
**Why This Matters:** Same silent wrong-grade class as finding 1, with a single-file trigger that takes out a whole package.
**Required Fix:** Apply the same filter to both sources (`__init__.py`, `conftest.py` never reserved; only collected test-module names reserved). Cover with a bats case whose overlay includes `tests/__init__.py` and whose agent tree adds `src/newpkg/__init__.py`.

---

## Observations

### 1. Functionality — directory overlays are invisible to the collision guard

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-grade.sh:1079-1081` — `owned` excludes directory overlay entries (`if not os.path.isdir(f)`), and `reserved` derives only from `owned`; `owned_dirs` protects overlay contents from deletion but never enumerates their test files. `load_task` (lines 570-582) accepts a directory `src` (it checks `os.path.exists`, and `remove_harness` already carries `owned_dirs` for exactly this shape). For a task whose hidden tests arrive as a directory overlay, an agent-added `tests/extra/test_slug.py` survives, pytest aborts collection on the mismatch, and the row is graded failing with `colliding_tests_removed: 0`, so the 1.2.11 guarantee in the header (line 222) does not hold for those tasks.
**File:** `head/evals/harness/ablation-grade.sh:1079-1081`
**Suggestion:** When `os.path.isdir(f)`, `os.walk(f)` and add its collected test-module basenames to `reserved`; add a bats case with a directory overlay.
**Benefit:** The guard behaves the same whatever overlay shape a task author chose.

### 2. Validation — `suite_kind_cap` lets `false`/`null` entries fall through

- **LOW** (confidence: high) `head/evals/harness/run-ablation.sh:502-503` — jq's `//` treats `false` and `null` as absent: `caps.run_usd_by_type: false` yields `""` (fallback), and `run_usd_by_type: {build: false}` (YAML `build: no`) yields `""` too. The comment at line 499 promises "A present but malformed per-kind entry is refused, never skipped"; these two shapes are skipped and the batch runs on `run_usd`. RAB-22 covers the string and list shapes only.
**File:** `head/evals/harness/run-ablation.sh:502-503`
**Suggestion:** Test presence with `has($k)` and type with `type`, e.g. `if has($k) then (.[$k] | if type == "number" or type == "string" then tostring else "!" end) else "" end`, and the same for the map itself.
**Benefit:** The refusal matches its documentation; a typo'd cap cannot silently become 12.

### 3. Tests — `seed-*.bats` rely on a `--suite-version` flag outside this diff

- **LOW** (confidence: low) `head/evals/tests/seed-bugfix.bats:80` and `head/evals/tests/seed-refactor.bats:78` — both tests now pass `--suite-version` to the seed scripts, which are not among the touched files, so the flag must already exist. It could not be verified from `pr/`; if the scripts do not accept it, SB-1 and the refactor seed case fail on `suite_version 2`.
**File:** `head/evals/tests/seed-bugfix.bats:80`
**Suggestion:** Confirm `evals/harness/seed-bugfix.sh` and `seed-refactor.sh` parse `--suite-version` on this base, or add the flag in the same change.
**Benefit:** Keeps the bats suite green on the bump to suite v2.

### 4. Notes (not counted)

- Per-kind caps (`cap_for`, `RESERVE_CAP`, `account_row`, `collect`, `run_trial`, manifest `run_usd_by_type`, `--resume` from MANIFEST, `--run-cap` ignored on resume) read correctly end to end; RAB-22 through RAB-26 exercise each path, including the budget-gate boundary at 27.99 / 28 and 21.99 / 22.
- KF-048: `make_home` writes the per-run `auth.json` with `O_CREAT|O_TRUNC` at 0600, paths only in argv, host file untouched, unreadable or non-object JSON → one WARN and no credential; the pre-flight decodes only the JWT payload, prints no token material, skips on `--smoke`, refuses on `--dry-run` and `--resume`, and `write_manifest` is not called on `--resume` (line 1010) so the start's `codex_preflight` record is kept as documented. Treating every arm with `loa_mount` unset as codex-using is right: PLAN-phase Flatline and the gate dissent both reach codex, so only A0 is exempt.
- `--types` fix at `run-ablation.sh:565`: `.type as $t | … | index($t)` is correct and RAB-27 pins it.
- SIMPLICITY: `remove_colliding` is 30 lines, the pre-flight heredoc about 55; both are the minimum for their rule once the scoping in finding 1 is added. Lean already apart from the fix. `net: 0 lines possible`.

---

## Rejected dissent payloads

The dissent envelope (`adversarial-review.json`, two voices, both succeeded, `rejected_count` 0, empty `rejected_summary`) rejected nothing; there is nothing to triage. Triage of the accepted payloads: DISS-001 and DISS-C-001 → finding 1 (HIGH, counted); DISS-C-001's `__init__.py` point → finding 2 (HIGH, counted); DISS-002 and DISS-C-002 → observation 1 (MEDIUM); DISS-003 → observation 2 (LOW).

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | grader 1.2.11 over-deletes (findings 1, 2); directory-overlay gap (observation 1) |

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| "report each defect it introduces with the file and line it sits on" (task-brief.md) | Done | findings above, cited `head/<path>:<line>` |
| "give a merge verdict" (task-brief.md) | Done | CHANGES_REQUIRED |
| Per-kind caps reach dispatch, assumed charges, reservation, manifest, resume (DEC-0567) | Pass | `run-ablation.sh:515, 850-854, 1043-1053, 1187, 1284, 1322, 1534` |
| KF-048 placeholder refresh token, host untouched | Pass | `pipeline-run.sh:622-645` |
| KF-048 pre-flight refuses an expiring token, warns on a missing file | Pass | `run-ablation.sh:780-842` |
| Grader 1.2.11 removes only true pytest basename collisions | Fail | findings 1, 2; observation 1 |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (the placeholder string is not a credential)
- [x] Input validation and sanitization present (JWT payload decode guarded; `usd_ok` on every cap; see observation 2 for the `false` gap)
- [x] Authentication/authorization correct (per-run HOME cannot refresh; access token still scoped to the run)
- [x] No SQL/XSS injection vulnerabilities (n/a; paths only in argv, `python3 -I`)
- [x] Dependencies secure (no new dependency)
- [x] Error messages don't leak sensitive data (REFUSED.txt and WARN lines carry paths and instants only; RAB-28 asserts no token material)

---

## Code Quality Summary

**Strengths:**
- Every new cap path has a boundary test (RAB-25's 27.99/28 and 21.99/22 pairs).
- The credential copy keeps the key the codex CLI needs while making the token unusable for refresh, with the reasoning recorded in place.
- The pre-flight's manifest record (`codex_preflight`) makes a refused or skipped check auditable later.

**Areas for Improvement:**
- `remove_colliding` encodes a pytest rule more broadly than pytest applies it; scope the reserved set and the candidate set to what pytest actually collects.
- Keep the two sources of `reserved` symmetric in their exclusions.

---

## Next Steps

1. Fix findings 1 and 2 in `ablation-grade.sh` (scope `reserved` to collected test-module names, skip packaged candidates, exclude `__init__.py`/`conftest.py` from both sources); bump to 1.2.12 and add the two bats cases.
2. Decide whether directory overlays should feed `reserved` (observation 1) in the same bump.
3. Re-grade the Sprint 261 priority-v2-p1/p1b rows under the fixed grader and confirm the DEC-0597 H1 figure before it is relied on.
4. Update `grimoires/loa/a2a/sprint-1/reviewer.md` and re-run `/review-sprint sprint-1`.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":1,"low":2},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T11:20:35Z"} -->
