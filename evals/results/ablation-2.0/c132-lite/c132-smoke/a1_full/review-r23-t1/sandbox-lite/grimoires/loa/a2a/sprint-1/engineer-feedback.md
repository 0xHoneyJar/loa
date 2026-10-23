# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (pr/PR.md)

---

## Overall Assessment

The change adds the cycle-130 ablation grader (`evals/harness/ablation-grade.sh`, 1299 lines), the bug-fix and refactor task seeders (`seed-bugfix-tasks.sh`, `seed-refactor-tasks.sh`, `lib/seed_tasks.py`), the generated-path rule for fix regions in `seed-corpus-from-record.sh` (with the pr-14/pr-15 manifests and SHA256SUMS regenerated — checksums verified to match), the `source.churn` schema in `validate-suite.sh`, and bats coverage for all of it. The design is careful: trust boundaries are documented, every path from history or from the sandbox is validated, the grading trees never write into the sandbox, and the seeders prove red/green before a task is moved into place.

I exercised the new code directly rather than relying on the report: syntax checks on every script, the grader against synthetic runs in host mode, and both seeders against throwaway repositories. That surfaced four blocking defects, each reproduced on this host: the seeder's `git apply` fallback silently skips the reference patch when the proof tree sits under any git work tree (so every candidate "fails" its proof), the grader crashes on any run with a snapshot bundle on Python 3.11.2 because `tarfile.extractall(filter=)` is unavailable, the grader's bats suite hard-codes one operator's `$HOME` path for the bats binary, and an agent-authored root `conftest.py` forges a full pass of the hidden tests because the seeder protects only infrastructure files that already exist at the parent commit.

The cross-model dissent (gpt-5.5-pro via codex-headless, companion claude-headless; 2/2 voices, consensus, nothing rejected) returned eight advisory findings; six are real and are folded into the observations below with their own citations. `reviewer.md` is the PR description and carries no `## AC Verification` walkthrough; the PR title also names sixteen task directories and "the freeze" that are not in the diff (see Observations).

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Functionality — seeder proof is a false negative without `patch`

- **HIGH** (confidence: high) `head/evals/harness/lib/seed_tasks.py:225-230` — when `patch` is not installed, `apply_patch` runs `git apply -p1` with `cwd=tree`; if the proof tree lies anywhere under a git work tree (the seeder builds it with `tempfile.mkdtemp`, so any `TMPDIR` under a checkout — here `TMPDIR=/workspace/.eval/tmp`), git resolves patch paths against that repository's root, prints `Skipped patch 'tools/mathx/rounding.py'.` and exits 0. The seeder treats that as applied, runs the reference tests on the unpatched tree and reports `proof-failed <sha>: not green at reference (exit 1, 2 failed, 1 passed)`, exits 1 and writes nothing.
**File:** `head/evals/harness/lib/seed_tasks.py:225-230`
**Issue:** Reproduced with the SB-1 repository from `seed-bugfix.bats`: with `TMPDIR` under `/workspace` the run fails as above; with `TMPDIR=/tmp/rev/tmp` the same run prints `proof bugfix-01 …: red 2 failed / green 3 passed` and writes the task. A controlled check from a subdirectory of an unrelated repository showed `git apply` returning 0 with the file unchanged. The inverse also holds: a reference patch that does not apply is reported as applied.
**Why This Matters:** The whole point of the seeder is the red/green proof. On a host without `patch` (as this one) the proof's outcome depends on where `TMPDIR` points, and the failure mode is silent: every candidate is rejected and the operator sees "proof failed", not "patch skipped".
**Required Fix:** Either require `patch` in the wrappers' tool check (`seed-bugfix-tasks.sh:75`, `seed-refactor-tasks.sh:64`), as the grader's self-check already does implicitly, or make the fallback safe: run `git apply` with `GIT_CEILING_DIRECTORIES` set to the parent of the proof tree (or `git -C tree init -q` the scratch tree first), and treat any `Skipped patch` line on stderr as failure.
**Reference:** git-apply(1) — "When running from a subdirectory in a repository, patched paths outside the directory are ignored."

### 2. Functionality — grader aborts on Python without the tarfile extraction filter

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:713-714` — `tf.extractall(tree, filter=keep)` requires Python 3.12, or the 3.11.4/3.10.12/3.9.17/3.8.17 backports. On this host (Python 3.11.2, `hasattr(tarfile, "data_filter")` is False) every grade of a run that has a snapshot bundle and a gate verdict dies with `ablation-grade: internal error: TypeError: TarFile.extractall() got an unexpected keyword argument 'filter'` and exit 2.
**File:** `head/evals/harness/ablation-grade.sh:713-714`
**Issue:** Reproduced with a synthetic bug-fix run in host mode: without a snapshot the grade succeeds (`hidden 0/2`); after adding `snapshots/IMPLEMENT.bundle`, `index.json` and a review trailer the grader exits 2. That is exactly the shape of every A1-arm run (REVIEW ran, so `implement` is graded), so `ablation-grade.bats` AG-6, AG-12 and AG-18 fail here too. The grader is the host-side component (it is what `python3 -I -` on the operator host runs), so the image's Python does not help.
**Why This Matters:** The grader hard-depends on an interpreter feature without checking for it, and the result is not a degraded grade but no grade.
**Required Fix:** Guard the call: when `tarfile.data_filter` exists use it; otherwise pre-filter members with the same `safe_rel`/`EXCLUDE_TOP` checks plus explicit rejections of absolute names, `..`, links, devices and members whose realpath lands outside `tree`, and pass them via `members=`. Alternatively pin the minimum Python in the header and fail fast with a `GradeError` naming it.
**Reference:** CWE-22 (the filter is the path-traversal defence; the fallback must keep it), Python docs tarfile "Extraction filters".

### 3. Testing — the grader's bats suite runs only on the author's machine

- **HIGH** (confidence: high) `head/evals/tests/ablation-grade.bats:16` — `BATS_BIN="$HOME/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats"` hard-codes one operator's dotfiles path; `make_bin` symlinks `$T/bin/bats` to it (line 48) and the docker stub's PATH is `$T/bin:/usr/bin:/bin` (line 51), which omits `/usr/local/bin`. On any other host the symlink dangles and bats-core installed under `/usr/local/bin` (as here) is not found: the `bf-sh` halves of AG-2 and AG-7 fail (`bats: command not found` → rc 127 → `parse_error`, `passed 0`).
**File:** `head/evals/tests/ablation-grade.bats:16`
**Issue:** The only tests of the 1299-line grader cannot run in CI or on a colleague's machine; a reviewer re-running them gets red for reasons unrelated to the grader.
**Why This Matters:** FAST-GATE parity: a test file that only passes locally is equivalent to an unrun test.
**Required Fix:** Resolve bats from PATH (`command -v bats`), honour `LOA_SEED_BATS` like the seeder does, and `skip` when neither resolves; include the resolved binary's directory in `DOCKER_STUB_PATH`.

### 4. Grading integrity — unprotected pytest configuration lets the graded tree forge its hidden-test result

- **HIGH** (confidence: medium) `head/evals/harness/ablation-grade.sh:657-674` — `prepare` restores or removes only the paths listed in `grader_protected`; everything else in the agent's tree is run as-is, and pytest loads any `conftest.py` (and `pytest.ini`/`pyproject.toml`/`setup.cfg`/`tox.ini`) it finds from the rootdir down. The seeder writes `grader_protected` from `helper_files` (`head/evals/harness/lib/seed_tasks.py:158-177`, `:384`), which lists only infrastructure files that EXIST at the parent commit, so a root `conftest.py` or ini file the fixture lacks is never removed from the graded tree.
**File:** `head/evals/harness/ablation-grade.sh:657-674` (and `head/evals/harness/lib/seed_tasks.py:384`)
**Issue:** Reproduced in host mode on a seeded-shape task (`grader_protected: [tests/conftest.py]`): the fixture alone grades `hidden 0/2`; adding a root `conftest.py` with a `pytest_runtest_makereport` hookwrapper that sets `rep.outcome = "passed"` grades `hidden 2/2, parse_error false` with no change to the source. A root `pytest.ini` with `addopts` is the same vector. Agents add root `conftest.py` files routinely (import-path fixes), so this is not only an adversarial path.
**Why This Matters:** `hidden_tests.passed/total` is the primary build metric of the ablation; an unprotected hook makes it agent-controlled while the grade reports a clean parse.
**Required Fix:** In the seeder, always list the standard pytest configuration paths (root `conftest.py`, `pytest.ini`, `pyproject.toml`, `setup.cfg`, `tox.ini`, and `conftest.py` in every test directory of `test_command`) in `grader_protected` even when absent, so `prepare` removes agent-added copies; have `validate-suite.sh` require them for pytest tasks; in the grader, additionally pass `-c /dev/null` (no ini from the tree) and `-p no:cacheprovider --confcutdir=<rootdir>` only if the task's own conftests remain loadable, or document that `grader_protected` is the sole defence and audit the sixteen frozen tasks for it.
**Reference:** CWE-807 (reliance on untrusted inputs in a security decision), pytest docs "conftest.py: local per-directory plugins".

---

## Observations

### 1. Seeder selection contract

- **MEDIUM** (confidence: high) `head/evals/harness/lib/seed_tasks.py:570-602` — `selected = cands[: a.select]` fixes the slate before building; a candidate that is skipped after selection (`no test at the parent names a touched file`, the covering-tests runner mix, a secret refusal) consumes its slot and no later candidate is pulled in. Reproduced: two refactor candidates, the newest without a covering test, `--select 1` → `selected 1, written 0`, exit 0, although `--select 2` writes the older one. The wrapper headers promise the opposite (`seed-refactor-tasks.sh:37-38`, `seed-bugfix-tasks.sh:43-44`).
**Suggestion:** Iterate over all candidates and stop when `written + failed == select`.
**Benefit:** `--select 4` yields four tasks when four qualify.

### 2. Refactor gates are judged without the structural check (dissent DISS-002)

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:1122` — snapshot trees run only `t.test_command`; `structural_command(t)` runs on `final` alone (line 1101). For a refactor whose functional suite is green at base, an unchanged IMPLEMENT snapshot passes everything the gate is judged on, so a review that APPROVED the un-refactored tree gets `verdict_accuracy_per_gate.review: true` (line 1129-1130).
**Suggestion:** For refactor tasks run the structural check on each graded snapshot and require both to pass in `all_pass`.
**Benefit:** Gate accuracy measures what the task asked for.

### 3. Dissent envelopes contribute no citations (dissent DISS-001, DISS-C-006)

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:854-868` — `envelope_texts` emits `anchor` verbatim and `file`+`line`, but the adversarial envelopes the harness copies under `eval/` use `anchor: "<path>:<symbol>"` with `anchor_line`/`anchor_line_end` (this sprint's own `adversarial-review.json` is an example; AG-8 only exercises `anchor: "lib/x.sh:20"` and `file`/`line`). The `CITE` regex needs `:digits`, so real dissent findings never reach `gates-combined.md`, and recall under-counts arms where the dissent is what caught the defect, contrary to the header (lines 96-97).
**Suggestion:** When `anchor_line` is an int, split `anchor` at the first `:` and emit `path:anchor_line[-anchor_line_end]`.
**Benefit:** Review-catch recall credits the gate the design says it credits.

### 4. Contamination false positives on quoted slash strings (dissent DISS-C-003)

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:976-980` — `ABS_WORD` accepts a word preceded by `|`, `'`, `"`, `=` or `:`; checked here: `re.sub('/x/y', …)` yields `/x/y`. So `sed 's|/old/path|/new|'`, `grep '/api/v1'` or `echo "/a/b"` in any Bash tool call marks the run `contaminated: outside_path` on the first such command, and `"hidden" in low` (line 964) fires on a Grep pattern or a file name containing the substring. The header calls the scan a lower bound on leakage, but these are false positives that flag clean runs.
**Suggestion:** Only consider Bash words that are bare argv tokens (not inside quotes or sed/grep delimiters), and require a known top-level prefix (`/home`, `/root`, `/mnt`, `/srv`, `/media`, `/run`) for `outside_path`; scope `hidden` to path fields and words that resolve under the task directory.
**Benefit:** Arm comparisons are not biased by shell style.

### 5. The seeder proves under a different interpreter shape than the grader runs (dissent DISS-C-002)

- **MEDIUM** (confidence: medium) `head/evals/harness/lib/seed_tasks.py:201-210` vs `head/evals/harness/ablation-grade.sh:492-493` — the proof runs plain `python3 -m pytest` (cwd on `sys.path`); the grader rewrites the same command as `python3 -I -s` (container) or `python3 -P` (host) with `--rootdir`, removing the cwd entry. Tests that import fixture modules relative to the tree root pass the seeding proof and grade 0/N. `-P` also needs Python 3.11; on a 3.10 host every host-mode pytest run exits 2 (`Unknown option: -P`) and is recorded as `parse_error`, `passed 0`, not as a tool failure.
**Suggestion:** Share `shape_command` between seeder and grader (move it to `lib/`) so the proof uses the graded argv; treat rc 2 with no collected tests as a `GradeError`.
**Benefit:** A task that proves green cannot grade red for reasons unrelated to the agent.

### 6. An unreadable file in the sandbox aborts the grade

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:296` — `copy_tree` calls `shutil.copyfile` on every regular file; a mode-000 file the agent leaves behind raises `PermissionError`, caught only by the generic handler: `internal error: PermissionError: [Errno 13] Permission denied: …/sandbox/blocker.txt`, exit 2. Reproduced as uid 1000. `churn` already tolerates this (line 731-734); `copy_tree` does not.
**Suggestion:** Catch `OSError` per file, skip it and record the count in grade.json (or chmod the copy source as `remove_path` does for directories).
**Benefit:** The graded party cannot veto its own grade.

### 7. Churn and the final tree include dependency and build trees (dissent DISS-C-005)

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-grade.sh:1076-1077` and `:719-757` — only a fixed top-level list and `__pycache__`/`.pytest_cache` are excluded; a `.venv`, `node_modules`, `.tox` or `.mypy_cache` the agent created is copied into `grading/final`, counted in `files_changed`/`diff_lines`, and read whole into memory for `difflib`. `diff_lines` is a cross-arm metric.
**Suggestion:** Extend `EXCLUDE_ANY` with the usual dependency/build/cache directories (or honour the sandbox `.gitignore`), cap the per-file size for line diffs, and count larger files as 1 file / 0 lines.
**Benefit:** Churn measures the agent's edits.

### 8. Report and scope

- **MEDIUM** (confidence: high) `head/../pr/PR.md:1` — the title says "sixteen frozen-suite tasks under grimoires/loa/evals/ablation-2.0/tasks/" and the second commit "the grader, the freeze and bd-8o5rx", yet the diff holds no task directory, no `MANIFEST.sha256` and no `freeze.sh` change (16 files: harness, tests, fixtures). `reviewer.md` carries no `## AC Verification` walkthrough and no record of the test commands run. VS-1 was rewritten to count whatever is committed (`head/evals/tests/validate-suite.bats:31-45`), so nothing in this PR pins the sixteen tasks' existence or validity.
**Suggestion:** Either include the task directories and the freeze in this change or drop them from the description; add the AC walkthrough with `file:line` evidence and the bats/pytest commands that were run.
**Benefit:** The review can check what the PR claims.

### 9. Lower-severity notes

- **LOW** (confidence: high) `head/evals/harness/ablation-grade.sh:617-621` — `parse_tap` keys results by description; two `@test` names repeated across bats files collapse into one key, so `failed_names`/`newly_failing` ids are wrong while counts stay right (dissent DISS-C-004). Key by test number.
- **LOW** (confidence: high) `head/evals/harness/ablation-grade.sh:1091-1095` — when the final regression run has no parseable summary, `newly_failing` becomes every base-passing test even though `run_suite` credited `passed = total` for rc 0 (line 633); the regressions block contradicts itself (dissent DISS-C-007). Surface `parse_error` in the block and only derive `newly` from rc.
- **LOW** (confidence: medium) `head/evals/harness/ablation-grade.sh:561-571` — `OUTCOME_RX` is applied to every output line; under `-rA` pytest prints captured stdout of passed and failed tests, so a fixture tool printing `FAILED …`/`ERROR <path>` at line start is parsed as an outcome (an `ERROR` without `::` even decrements `total`) (dissent DISS-C-001). Scan only the "short test summary info" section.
- **LOW** (confidence: medium) `head/evals/harness/lib/seed_tasks.py:51-54` — `_git_env` keeps `HOME` but does not set `GIT_CONFIG_GLOBAL=/dev/null` as the grader does (`ablation-grade.sh:679`); a user `log.showSignature` or `color.ui=always` changes the parsed `git log`/`diff` output.
- **LOW** (confidence: high) `head/evals/harness/ablation-grade.sh:1057-1063` — a feedback file without a trailer yields `verdict.value: "none"` (a string sentinel) and `review.md`'s `Verdict:` line is then not consulted; the header describes `value` as the verdict or null. Line 1280 also prints Python's `None` in the human summary.
- **LOW** (confidence: medium) `head/evals/tests/validate-suite.bats:35-45` — VS-1 assumes a type with a count other than four produces exactly one `counts:` line; a type with more than four tasks may produce none, and the expected status flips with it.
- **LOW** (confidence: high) `head/evals/harness/ablation-grade.sh:213` and `:1175` — `yq` and `patch` are hard prerequisites (self-check reference dies with an `internal error` `FileNotFoundError` when `patch` is absent, as here) but neither the header's prerequisites nor a pre-flight check names them; the wrappers check only `git`/`python3`.
- **LOW** (confidence: high) `head/evals/harness/ablation-grade.sh:1045-1142` — complexity: `grade` (98 lines), `load_task` (`:319-419`, 101 lines), `build_bugfix` (`seed_tasks.py:370-436`) and `main` (`seed_tasks.py:547-620`) exceed the 50-line guideline without a justification comment; splitting `grade` into build/review-catch halves would also make the refactor-snapshot fix above local. `SIMPLICITY[shrink]`: otherwise lean; no over-engineering found. `Lean already. Ship.` once the above is addressed.
- **LOW** (confidence: medium) no CHANGELOG entry is part of the diff for the new grader, seeders or the schema change; add one per the repository's documentation rule.

### Cross-Model Observations

Both voices returned advisory findings only. DISS-002, DISS-C-001, DISS-C-002, DISS-C-003, DISS-C-004, DISS-C-005, DISS-C-006 and DISS-C-007 are triaged above (Observations 2, 3, 4, 5, 7 and 9). DISS-001 duplicates DISS-C-006. No dissent finding was discarded.

## Rejected dissent payloads

None: `metadata.rejected_summary` is empty and the sidecar `adversarial-rejected-review.jsonl` holds no rows.

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion (from the files' own headers) | Status | Notes |
|-----------|--------|-------|
| Seeder: task built in a private dir, moved only after red/green proof and no-secrets pass | Fail | Proof is a false negative when `patch` is absent and TMPDIR is under a repo (Changes Required 1); otherwise verified end to end on a throwaway repo (task.yaml, TASK.md, fixture contents match SB-1's expectations) |
| Seeder: refusals and skips do not count against `--select` | Fail | Post-selection skips consume slots (Observation 1) |
| Grader: snapshots extracted with `git bundle unbundle` + `git archive`, graded per gate | Fail | Crashes on Python 3.11.2 (Changes Required 2) |
| Grader: protected paths restored, hidden overlay written, sandbox never written | Partial | Verified on host; protection is only as complete as `grader_protected` (Changes Required 4) |
| Grader: dissent envelope anchors reduced into gates-combined.md | Fail | Real envelope shape not parsed (Observation 3) |
| Grader: ids-only grade.json, no timestamp or scratch path | Pass | Verified on the synthetic runs |
| Generated artefacts never fix regions; each exclusion printed once; defects untouched | Pass | Code matches header and SC-7/SC-8; pr-14/pr-15 manifests hold no generated paths; SHA256SUMS lines recomputed and match |
| `source.churn` validated as three non-negative integers | Pass | `validate-suite.sh:218-224`; VS-11 covers it |
| Tests runnable outside the author's machine | Fail | Changes Required 3 |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [x] Input validation and sanitization present (history paths, manifest entries, task ids, bundle commits)
- [ ] Authentication/authorization correct — n/a
- [ ] No SQL/XSS injection vulnerabilities — n/a; shell/git calls are argument vectors, nothing is eval'd or sourced
- [x] Dependencies secure — stdlib only; the tarfile filter fallback (Changes Required 2) must keep the traversal defence
- [x] Error messages don't leak sensitive data — grade.json carries ids only (verified)

---

## Code Quality Summary

**Strengths:**
- Trust boundaries are explicit and mostly enforced: `safe_rel`/`safe_path`, symlink handling in `prepare`/`ensure_parent`, no sourcing, `env -i` for test runs, ids-only output.
- Headers document the contract precisely, which made the contract violations above easy to pin down.
- The bats suites are thorough in intent (grading trees, contamination classes, meta/ boundary, self-check modes).

**Areas for Improvement:**
- Portability assumptions (Python ≥ 3.12 features, `patch`, a personal bats path, TMPDIR location) are unchecked and fail loudly or, worse, silently.
- The seeder and the grader should share the command shaping and the protected-path policy; today they disagree.

---

## Next Steps

1. Fix the four Changes Required (seeder patch fallback, tarfile filter fallback, bats resolution, protected pytest configuration).
2. Address Observations 1–5 (selection, refactor snapshots, envelope anchors, contamination false positives, proof/grade parity); the rest at your discretion.
3. Re-run `evals/tests/seed-bugfix.bats`, `seed-refactor.bats`, `ablation-grade.bats`, `seed-corpus.bats`, `validate-suite.bats`, `pipeline-run.bats` on a host other than the author's and record the commands and results in `reviewer.md` with an AC Verification walkthrough.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":4,"medium":8,"low":9},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T09:16:30Z"} -->
