# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md (Task 1.1: the change in `pr/head.diff`)
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)

---

## Overall Assessment

The change adds the cycle-130 ablation grader (`evals/harness/ablation-grade.sh`, a bash shim around a `python3 -I` program), the bug-fix and refactor task seeders (`seed-bugfix-tasks.sh`, `seed-refactor-tasks.sh`, `lib/seed_tasks.py`), the bd-8o5rx rule that generated artefacts never become fix regions (`seed-corpus-from-record.sh`, manifests pr-14/pr-15, SHA256SUMS), `source.churn` in `validate-suite.sh`, and tests for all of it.

What checks out: the pr-14/pr-15 manifests drop exactly the generated fix regions (`dist/`, `.map`, `.d.ts`, `.checksum`) and keep every defect (2 and 3 respectively), and the new SHA256SUMS lines match the files byte for byte. The generated-path rule in the corpus seeder is applied symmetrically at seed time and at `--build-manifest`, and the validator's `churn` schema is tight. The grader's trust boundary holds up to inspection: nothing is sourced or eval'd from a variable, `meta/` is never read, path safety (`safe_rel`, `ensure_parent`, `data_filter`) is consistent, and `grade.json` carries ids only. The seeders' selection logic is sound: with the environment normalised (an executable filesystem, `TMPDIR` outside any git repo, a stub for the untouched `no-secrets.sh`), 8 of the 10 seeder tests pass here and the other two fail only because this host lacks `patch` and the suite file.

What blocks: four HIGH findings, each reproduced or confirmed against a real artefact rather than inferred.

1. The review-catch reduction never reads `anchor_line`, so a dissent finding anchored on a symbol (the format every real envelope uses, including the one this review produced) contributes no citation and a caught defect grades as missed.
2. The seeders' `git apply` fallback is a silent no-op inside any git work tree; reproduced here, SR-3 wrote a task whose reference patch breaks the suite as "green at reference".
3. The grader calls `tarfile.extractall(filter=…)` / `tarfile.data_filter` and host-mode `python3 -P`, which need Python ≥ 3.11.4/3.12 and ≥ 3.11 respectively, with no version guard; on this host (3.11.2) every build grade with a gate snapshot exits 2.
4. `ablation-grade.bats` hard-codes an operator-specific bats path, so the grader's bats/TAP path is unverified anywhere but one machine.

The implementation report (pr/PR.md) carries no `## AC Verification` section and no record of the test suites having run; that alone is an automatic CHANGES_REQUIRED under the review protocol, independent of the findings below.

Complexity: `grade()` (lines 1045-1142) is ~100 lines with 3-deep nesting in the build branch; acceptable for an orchestrating function but a `grade_build()` / `grade_review_catch()` split would make the gate-accuracy logic testable on its own. Over-engineering pass: Lean already. Ship.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Functionality — review-catch recall ignores numeric anchors

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:862-867` — `envelope_texts` emits the raw `anchor` string and a `file`+`line` pair, but never `anchor_line`; a finding anchored `path:symbol` with `anchor_line: N` (the cycle-131 FR-4 envelope shape) yields no `path:line` citation, so a defect the dissent caught is graded as missed.
**File:** `head/evals/harness/ablation-grade.sh:862-867`
**Issue:** `.claude/skills/reviewing-code/resources/ADVERSARIAL-REVIEW.md` §"Numeric anchors" says "Graders (the eval harness's envelope reduction) read `anchor_line` with the anchor's file as `path:line[-end]`". The reduction reads `anchor` (a symbol anchor such as `evals/harness/ablation-grade.sh:envelope_texts`), and `file`/`path` + `line`/`line_start`/`start_line`, none of which the dissent writes. The `CITE` regex (line 795-798) requires digits after the colon, so a symbol anchor produces nothing. The envelope this very review produced (`grimoires/loa/a2a/sprint-1/adversarial-review.json`) has ten findings, all with `anchor: "<path>:<symbol>"` and `anchor_line: <int>`; fed to `combined_findings`, they would produce zero citations. AG-8 only exercises a numeric `anchor: "lib/x.sh:20"` and a `file`+`line` pair, so the test passes while the real shape is dropped.
**Why This Matters:** `recall`, `flags`, `missed` and `false_positives` for every A1-arm run undercount the dissent's contribution — the arm the ablation exists to measure. The error is systematic, not noisy.
**Required Fix:** when `anchor_line` is an int, emit `f"{anchor_file}:{anchor_line}"` (and `-{anchor_line_end}` when present), taking `anchor_file` as the text before the last `:` of `anchor` (or `file`/`path`); keep the current fallbacks. Add an AG-8 case with a symbol anchor + `anchor_line`.

### 2. Functionality — the seeders' proof can silently pass an unapplied patch

- **HIGH** (confidence: high) `head/evals/harness/lib/seed_tasks.py:229` — without `patch` on PATH, `git apply -p1 <file>` run from a proof tree that lies inside any git work tree exits 0 without modifying a single file (git-format patch paths are resolved against the repository top level, and paths outside the current subdirectory are ignored), so "green at reference" is reported for a reference tree that is byte-identical to base.
**File:** `head/evals/harness/lib/seed_tasks.py:226-230` (called from 407 and 473)
**Issue:** `apply_patch` falls back to `git apply` when `shutil.which("patch")` is None. The proof trees come from `tempfile.mkdtemp()` (line 400, 467), i.e. `$TMPDIR`. Reproduced on this host (`patch` absent, `TMPDIR=/workspace/.eval/tmp` inside the checkout): a git-format patch applied with `git apply -p1` from such a directory returned exit 0 and left the file unchanged; the identical patch applied from `/tmp` changed it. Running the PR's own suites in that state: SR-3's suite-breaking refactor was reported `proof refactor-01 …: green at base (2 passed) / green at reference (2 passed)` and **written**, and SB-1's correct fix was refused with `not green at reference (exit 1, 2 failed, 1 passed)`. With `TMPDIR=/tmp` both behave as the tests expect.
**Why This Matters:** the red/green proof is the seeders' only guarantee ("moved into place only after its proof passed"). In the no-op case it accepts a broken reference patch and refuses a good one, both silently. The grader's `--self-check` would catch the broken task later, but it requires `patch` unconditionally (ablation-grade.sh:1175), so the same host cannot run the safety net either.
**Required Fix:** do not fall back silently. Either require `patch` (exit 2 with a clear message when it is missing) or run `git apply` with repository discovery disabled (e.g. `GIT_CEILING_DIRECTORIES` set to the proof tree's parent, or `GIT_DIR` pointed at an empty directory) **and** assert that at least one patched path changed before accepting the proof.

### 3. Portability — undeclared Python ≥ 3.12 requirement crashes the grader

- **HIGH** (confidence: medium) `head/evals/harness/ablation-grade.sh:710-714` — `tarfile.data_filter` and `TarFile.extractall(filter=…)` exist only from Python 3.11.4 / 3.12; on 3.11.2 (Debian 12's `python3`, and this host) `extractall` raises `TypeError: … unexpected keyword argument 'filter'`, which the top-level handler turns into `internal error … exit 2` for every build-task grade that has a gate verdict and an IMPLEMENT/FIX1 bundle.
**File:** `head/evals/harness/ablation-grade.sh:710-714` (and `:492`)
**Issue:** `extract_snapshot` runs whenever `v_review`/`v_audit` is set and a bundle exists (lines 1110-1123) — i.e. every A1 run. Verified here: Python 3.11.2 has neither `tarfile.data_filter` nor the `filter` keyword. Host mode additionally shapes pytest as `python3 -P -m pytest` (line 492); `-P` was added in 3.11, so a 3.10 host (Ubuntu 22.04) fails every host-mode suite run with `Unknown option: -P` and reports `parse_error: true, passed: 0`. Nothing in the script, its header or the tests states a minimum interpreter version, and the shim at line 166 runs whatever `python3` is first on PATH. Confidence is medium only because the operator's grading host version is unknown; the failure on a < 3.11.4 host is certain.
**Why This Matters:** the grader is the measurement instrument; on a common LTS interpreter it produces no `grade.json` for the main arm, and `ablation-row.sh` has no row.
**Required Fix:** check `sys.version_info` at start and `die()` with the requirement, or guard: use `data_filter` when present and otherwise fall back to the manual `safe_rel` + `tarfile.data_filter`-equivalent checks (absolute names, `..`, links outside the tree) before `extract`; drop `-P` on hosts below 3.11 (or make the host shape `python3 -m pytest` and document why).

### 4. Testing — ablation-grade.bats depends on one operator's filesystem

- **HIGH** (confidence: high) `head/evals/tests/ablation-grade.bats:16` — `BATS_BIN="$HOME/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats"` is an operator-specific absolute path; on any other machine the `ln -s` at line 48 creates a dangling `$T/bin/bats`, the image stand-in's `bats --tap tests` exits 127, and AG-2 (bf-sh half) and AG-7 fail.
**File:** `head/evals/tests/ablation-grade.bats:16`, `:48`
**Issue:** The stub PATH is `$T/bin:/usr/bin:/bin`; with the symlink dangling, `bats` resolves nowhere (bats-core installs to `/usr/local/bin` here and in most CI images), so every bats-driven grade in the suite returns `parse_error: true`, and AG-2's `2/3` and AG-7's `3/3 false` assertions fail. This is the only test coverage of `parse_tap`, the `bats --tap` shaping and the bats-helper protection.
**Why This Matters:** the file cannot pass in CI or on a reviewer's machine, so the grader's TAP path is unverified; FAST-GATE parity cannot be claimed for this sprint.
**Required Fix:** `BATS_BIN="$(command -v bats)"` (skip the bf-sh cases when absent), or point at `$BATS_ROOT/bin/bats` which bats-core exports to every test.

---

## Observations

### 1. Grading correctness (non-blocking)

- **HIGH** (speculative, confidence: low) `head/evals/harness/ablation-grade.sh:546-594` — hidden tests run in the same pytest process as agent-authored test modules and any non-protected `conftest.py`; the parser trusts stdout, so a module that prints `PASSED <hidden node>` lines plus `N passed in 0.01s` and calls `os._exit(0)` forges a full pass (`rc == 0`, parseable summary). Raised by the companion voice (DISS-C-005). Low confidence that an evaluated agent does this unprompted; high damage if it does. Mitigation when revisited: `--junitxml` to a path outside the tree and parse that, or cross-check `-rA` node ids against the known hidden node set.
**Suggestion:** record as a known limitation beside the contamination lower-bound note in the header.

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:1214` and `:1222` — the `base` self-check passes on `passed < total` alone. `run_suite`'s fallback (631-636) synthesises `total = max(static, 1), passed = 0` when the command produced no parseable summary and exited non-zero, so a task whose `test_command` cannot run at all (pytest missing from the image, a mistyped path) prints `self-check base …: PASS`. Only the `reference` check reveals it. (DISS-C-001)
**Suggestion:** require `not parse_error` (and `not timed_out`) in the base condition and name `parse_error` in the evidence string.

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-grade.sh:492` vs `head/evals/harness/lib/seed_tasks.py:201-208` — the seeders prove with `python3 -m pytest` (cwd on `sys.path`), the container grader with `python3 -I -s -m pytest` (cwd removed). A hidden test that imports a root-level package without a root `conftest.py` is green in the proof and red at grading; the reference self-check then fails with no hint that the interpreter flags differ. (DISS-C-003)
**Suggestion:** make the proof shape match the grader (`-I -s` plus `PYTHONUSERBASE`), or add `--rootdir`/`pythonpath` handling in both.

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-grade.sh:611-621` — TAP identities are keyed by description; two bats tests with the same description collapse to one position in `order`/`bad`, so `failed_names` and `regressions.newly_failing` can name the wrong test or lose one. (DISS-002)
**Suggestion:** key TAP results by test number (`n`) and derive `t<k>` from it.

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-grade.sh:296` — `copy_tree` calls `shutil.copyfile` with no error handling; one unreadable regular file in `sandbox/` (mode 000 left by a permissions test, a root-owned file from a container in host mode) raises `PermissionError` → `internal error`, exit 2, no `grade.json`. `churn()` guards the same reads with `except OSError`. (DISS-C-006)
**Suggestion:** catch `OSError`, skip the file, and record it (count only) in `grade.json`.

- **LOW** (confidence: medium) `head/evals/harness/ablation-grade.sh:588-589` — the summary counters are summed, so a test that FAILED and then ERRORed in teardown counts twice in `total` (the deduplicated `order` has one entry). `max(total, len(order))` corrects undercounts only. (DISS-003)

- **LOW** (confidence: medium) `head/evals/harness/ablation-grade.sh:1086-1090` — `prepare()` overlays the hidden files into the `base` tree before `regression_command` runs, so a directory-scoped regression command that covers a hidden dest is red at base and the base self-check's `suite_green` fails. This is a task-authoring constraint (regression_command must not include hidden dests) that neither the header nor `validate-suite.sh` states. (DISS-C-004)

- **LOW** (confidence: medium) `head/evals/harness/ablation-grade.sh:508`, `:514` — `timeout 120` without `-k` sends only SIGTERM; a test process that ignores it keeps running after the grader records `timed_out: true` (in container mode the container outlives the 180 s client timeout). (DISS-C-007) Add `-k 10`.

### 2. Contamination scan

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:964-969` — the `hidden` substring and the suite-path string are matched against `Grep.pattern` and `Bash.command`, so a legitimate search (`Grep pattern: "hidden"`, `grep -n grimoires/loa/evals/ablation-2.0 pr/head.diff`) marks a clean run `contaminated`. A review-catch task over a PR like this one, whose diff is full of `hidden/` and the suite path, would be flagged for reading its own input. The header documents the lower bound but not this false-positive class.
**Suggestion:** apply `hidden` only to path-shaped fields and path-shaped Bash words, or whitelist patterns that occur in the task's own `pr/head.diff`.

### 3. Seeders

- **MEDIUM** (confidence: medium) `head/evals/harness/lib/seed_tasks.py:196-198` — pytest proof counts are read from the single last line of `stdout + stderr`; any stderr emitted after pytest's summary (a `DeprecationWarning` at interpreter start, a user-site warning) makes the last line non-summary, `counts` returns 0/0, and the candidate is refused with `not red at base (… 0 failed, 0 passed)`.
**Suggestion:** search stdout alone with the grader's `SUMMARY_RX` over all lines, last match wins.

- **MEDIUM** (confidence: medium) `head/evals/harness/lib/seed_tasks.py:158-177`, `:384`, `:457` with `head/evals/harness/validate-suite.sh:280` — `grader_protected` is only the infrastructure that exists at the parent. A fixture with no `conftest.py`/`pytest.ini`/`pyproject.toml` leaves the agent free to add one that deselects or neutralises the hidden tests; the grader's `prepare()` would remove a listed path the fixture lacks, but the validator rejects listing one (`is not in the fixture`).
**Suggestion:** let the validator accept absent protected paths (the grader already handles them), and have the seeders list the standard runner-config names regardless of existence.

- **LOW** (confidence: low) `head/evals/harness/lib/seed_tasks.py:227` — `patch -s -p1 … -i` without `--batch`/`--forward` can prompt on `/dev/tty` (reversed or already-applied hunk) and hang an interactive seeding run; the grader passes `--batch --forward` (ablation-grade.sh:1175).

### 4. Tests

- **LOW** (confidence: medium) `head/evals/tests/ablation-grade.bats:46` — the image stand-in execs `/usr/bin/python3` literally; a host whose `python3` lives elsewhere (Homebrew, pyenv, a venv) breaks every grading test. Use `$(command -v python3)`.

- **LOW** (confidence: high) `head/evals/tests/seed-bugfix.bats:183` — `--repo "$T"` is expected to be "not a git repository", but `$T` is `BATS_TEST_TMPDIR`, which follows `TMPDIR`; with `TMPDIR` inside a checkout (as here) `git rev-parse --git-dir` succeeds and SB-6 fails. Use a directory created under a non-repo root, or assert on a file path.

- **LOW** (confidence: medium) `head/evals/tests/validate-suite.bats:31-44` — VS-1 now derives `n` and `short` from the committed suite, so it can no longer detect a wrong count; a type with more than four tasks is also counted as `short`, while `validate-suite.sh` may or may not report it.

### 5. Corpus seeder

- **LOW** (confidence: medium) `head/evals/harness/seed-corpus-from-record.sh:232-236` — in `--build-manifest` the `head/<file> missing` check runs before the generated-path exclusion, so a `fix` row for a generated path that the fixture scope dropped (e.g. `REPO-MAP.md`) fails the build with an error instead of being excluded.

---

## Cross-Model Observations

Adversarial review ran (two voices, `gpt-5.5-pro` primary, `claude-headless` companion, `counted_as: independent_voice`, status `reviewed`); envelope at `grimoires/loa/a2a/sprint-1/adversarial-review.json`. Triage:

| ID | Voice | Disposition |
|----|-------|-------------|
| DISS-001 | gpt-5.5-pro | Confirmed → Changes Required §1 (HIGH) |
| DISS-002 | gpt-5.5-pro | Confirmed, task-author-controlled inputs → Observations §1 (MEDIUM) |
| DISS-003 | gpt-5.5-pro | Confirmed, affects totals on already-failing runs only → Observations §1 (LOW) |
| DISS-C-001 | claude-headless | Confirmed → Observations §1 (MEDIUM) |
| DISS-C-002 | claude-headless | Confirmed; folded into Changes Required §3 (`-P` on < 3.11) |
| DISS-C-003 | claude-headless | Confirmed → Observations §1 (MEDIUM) |
| DISS-C-004 | claude-headless | By design per header; undocumented authoring constraint → Observations §1 (LOW) |
| DISS-C-005 | claude-headless | Plausible, unlikely unprompted → Observations §1 (HIGH, speculative, excluded) |
| DISS-C-006 | claude-headless | Confirmed → Observations §1 (MEDIUM) |
| DISS-C-007 | claude-headless | Confirmed → Observations §1 (LOW) |

## Rejected dissent payloads

- None: `metadata.rejected_summary` is empty and the listed sidecar `adversarial-rejected-review.jsonl` has 0 rows.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | The four HIGH findings above; an `## AC Verification` walkthrough and a record of the test suites having run in the implementation report |

---

## Acceptance Criteria Check

### Task 1.1: review the pull request, report each defect with file and line, give a merge verdict

| Criterion | Status | Notes |
|-----------|--------|-------|
| Generated artefacts never become fix regions (bd-8o5rx, AC-10.1) | Pass | `generated_path` applied at seed and `--build-manifest`; pr-14/pr-15 lose only generated fix regions, keep all defects; SHA256SUMS verified |
| `source.churn` validated | Pass | `validate-suite.sh:218-224`; VS-11 covers shape, negatives, non-mapping |
| Grader reads only the declared inputs, writes only grading/ and --out | Pass | Inspection; AG-13-style greps reproduced (`meta/` once, no `source`/`eval` of variables) |
| Grader grades review-catch recall from all gate outputs | Fail | `anchor_line` never read (Changes Required §1) |
| Grader runs on the operator host | Fail | Undeclared Python ≥ 3.12 requirement (Changes Required §3) |
| Seeders write a task only after a red/green proof | Fail | Proof silently passes with an unapplied patch when `patch` is absent and TMPDIR is inside a repo (Changes Required §2) |
| Tests runnable in CI | Fail | `ablation-grade.bats:16` operator path (Changes Required §4) |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [x] Input validation and sanitization present (`safe_rel`, `safe_path`, manifest/overlay checks, task-id regex)
- [x] Authentication/authorization — n/a
- [x] No SQL/XSS injection vulnerabilities — n/a; no shell interpolation, argv only
- [x] Dependencies secure — stdlib only; `tarfile` extraction uses `data_filter` (CWE-22) where available, see §3
- [x] Error messages don't leak sensitive data — grade.json ids only (AG-12 contract)

---

## Code Quality Summary

**Strengths:**
- Clear trust-boundary discipline in the grader: argv-only subprocesses, no sourcing, path normalisation before every write, snapshot extraction through a filter.
- Header blocks double as specifications and match the code closely; exit-code contracts are explicit.
- The seeders stage in a private directory and move into place only after proof + secret scan; refusals are by name.
- Manifest/SHA256SUMS edits are exact and reproducible.

**Areas for Improvement:**
- Declare and check runtime requirements (Python version, `patch`, `yq`) at start instead of failing deep inside.
- Keep the seeder proof's interpreter shape identical to the grader's so a proven task always grades.
- Tests must not depend on one machine's filesystem layout.

---

## Next Steps

1. Address the four HIGH findings above.
2. Run `bats evals/tests/ablation-grade.bats evals/tests/seed-bugfix.bats evals/tests/seed-refactor.bats evals/tests/seed-corpus.bats evals/tests/validate-suite.bats` on a clean host and record the result.
3. Update the report in `grimoires/loa/a2a/sprint-1/reviewer.md` with an `## AC Verification` walkthrough.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":4,"medium":7,"low":8},"excluded":1,"sprint_id":"sprint-1","ts":"2026-10-21T10:36:00Z"} -->
