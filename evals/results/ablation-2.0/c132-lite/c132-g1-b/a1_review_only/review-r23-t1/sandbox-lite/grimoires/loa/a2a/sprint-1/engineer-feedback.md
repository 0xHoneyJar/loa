# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)

---

## Overall Assessment

The change under review is `pr/head.diff`: the cycle-130 ablation grader (`evals/harness/ablation-grade.sh`, 1299 lines), the bug-fix / refactor task seeders (`seed_tasks.py` + two wrappers), the bd-8o5rx generated-path exclusion in `seed-corpus-from-record.sh` with the regenerated pr-14 / pr-15 manifests, the `source.churn` schema in `validate-suite.sh`, a `DOCKER_STUB_PATH` hook in the docker stub, and five bats files. The engineering is careful in many places: the trust boundary (no sourcing, `python3 -I`, path checks via `safe_rel`/`safe_path`), the grading-tree isolation (D-4.8), `tarfile.data_filter`, the meta/ boundary test, and the generated-path exclusion (verified: `SHA256SUMS` matches both regenerated manifests, only `fix_regions` changed, defect labels kept).

Review was of the code, not the report. Beyond reading every file, I ran the new seeder test files and the grader itself on a scratch copy of the head tree (`/tmp` is `noexec` and `patch` is absent on this host, which is itself what exposed one defect) and reproduced four of the five blocking findings:

- The grader's envelope reader never reads `anchor_line`, so a real two-voice dissent envelope (the one produced for this very review) contributes **zero** numeric citations to `gates-combined.md`.
- An agent-added root `conftest.py` with no fix at all grades the hidden tests **3/3 passed** (host mode; the container argv is the same pytest invocation).
- `sed -i '/TODO/d' file` in a Bash tool call marks the run `contaminated: outside_path`.
- With `patch` absent and the scratch tree inside a git checkout (`TMPDIR` under the repository, as in this harness), the `git apply` fallback prints `Skipped patch` and exits 0, so SR-3's suite-breaking refactor **passed its proof and was written as a task**, while every bug-fix proof failed spuriously.
- The new `ablation-grade.bats` hard-codes `BATS_BIN` to one developer's `$HOME/.local/dotfiles/...` path, so the grader's 18 tests cannot run on any other host or CI.

`reviewer.md` is the PR description verbatim; it carries no `## AC Verification` section, and its title promises "sixteen frozen-suite tasks under grimoires/loa/evals/ablation-2.0/tasks/" and "the freeze" that are not in the diff (no task directories, no `MANIFEST.sha256`). Per the review protocol that alone is an automatic CHANGES_REQUIRED; the five high findings make it so regardless.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Review-catch recall: dissent envelopes contribute no citations

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:862-867` — `envelope_texts` forwards the symbol `anchor` (`path:symbol`) and falls back to `file|path` + `line|line_start|start_line`; it never reads `anchor_line`, the field the dissent schema actually emits (ADVERSARIAL-REVIEW.md, cycle-131 FR-4: "Graders ... read `anchor_line` with the anchor's file as `path:line[-end]`"). Fed the envelope produced for this review (9 findings, every one `anchor: "<file>:<symbol>"`, `anchor_line: N`, no `file`/`line` keys), the reader yields 9 strings and the citation regex at line 795 parses **0** numeric citations.
**File:** `head/evals/harness/ablation-grade.sh:862-867`
**Issue:** The header (lines 96-97) promises "each finding's anchor (and file:line) in eval/adversarial-{review,audit}.json"; in practice only a toy shape (`anchor: "lib/x.sh:20"`, or `file`+`line`) is handled, and AG-8 (`head/evals/tests/ablation-grade.bats:402-403`) only tests that toy shape.
**Why This Matters:** Every arm that relies on the dissent to catch defects loses that recall; `flags`, `defects_caught`, `missed` and `false_positives` are wrong for review-catch tasks, and the arm comparison (DEC-0420) is biased against arms where the dissent finds what the model missed.
**Required Fix:** Emit `f"{anchor_file}:{anchor_line}"` (and `-{anchor_line_end}` when present) where `anchor_file` is the part of `anchor` before the last `:`; keep the symbol anchor only as a fallback. Add an AG-8 case using a real envelope row (anchor + anchor_line + anchor_line_end + voice).

### 2. Hidden-test gaming: agent-added root pytest configuration is honoured

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:657-674` — `prepare` restores only the paths listed in `grader_protected` and overlays the hidden files; everything else in the final tree is "sandbox/ as the agent left it", and the pytest argv (line 493, `--rootdir /workspace`) still loads a root `conftest.py`, `pytest.ini`, `pyproject.toml`, `setup.cfg` or `tox.ini` the fixture never had. Reproduced in host mode: a sandbox with NO fix plus a three-line `conftest.py` (`pytest_collection_modifyitems` setting `it.runtest = lambda: None`) grades `hidden_tests 3/3`, `regressions.newly_failing []`.
**File:** `head/evals/harness/ablation-grade.sh:657-674` (also `1076-1080`)
**Issue:** AG-2 proves the threat model is in scope (an agent-edited `tests/conftest.py` / `pytest.ini` is replaced), but the same threat via a file the fixture lacks is not neutralised; the seeders add `INFRA_ROOT_FILES` to `grader_protected` only when they exist at the parent commit (`head/evals/harness/lib/seed_tasks.py:174-176`), so for most seeded tasks there is no protection at the root.
**Why This Matters:** `hidden_tests`, `snapshot_tests` and every `verdict_accuracy` reflect agent-controlled pytest configuration, not the hidden tests. Arms differ in how often agents add such files, so the ablation signal is corrupted silently (dissent DISS-C-004 agrees).
**Required Fix:** In `prepare`, for every tree remove any `conftest.py`, `pytest.ini`, `pyproject.toml`, `setup.cfg`, `tox.ini` (and `.pytest_cache`, `__pycache__`) at any depth that does not exist in the fixture (or restore the fixture copy when it does), and pass `--confcutdir` / `-c` so pytest reads configuration only from the fixture-controlled location. Add a test with an agent-added root `conftest.py` expecting the hidden tests to still fail.

### 3. Contamination scan: false `outside_path` on ordinary shell commands

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:940` — `ABS_WORD` treats any delimiter-preceded token starting with `/` as an absolute path, and the only exemption (line 978) is the exact one-component `/x/`. Reproduced: a transcript whose only Bash call is `sed -i '/TODO/d' src/textkit/slug.py` grades `contaminated: {"phase":"IMPLEMENT","pattern":"outside_path"}`; `sed -n '/foo/,/bar/p' x.md` → `/foo/,/bar/p`; `awk '/start/,/end/' f` → `/start/,/end/`; a quoted route string `"/api/users"` is flagged the same way.
**File:** `head/evals/harness/ablation-grade.sh:940` and `976-980`
**Issue:** The header documents the scan as a lower bound (misses) but it also produces false positives on command shapes a shell-heavy Loa agent emits constantly, and `contaminated` is the field that decides whether a run is admissible (DEC-0493).
**Why This Matters:** Valid runs are silently discarded or flagged, and the rate differs by arm (the gated arms run more review/sed/awk commands), biasing the ablation. Both dissent voices (DISS-C-001) call this blocking.
**Required Fix:** Only treat a Bash word as a path when its first component exists in the allowed-root vocabulary or when the word resolves outside and also *looks* like a filesystem path (e.g. skip tokens inside single quotes following `sed`/`awk`/`grep -E`, tokens containing `,`/`^`/`$`/`*`, and any token that ends with a sed command letter after a closing `/`); add tests for the sed/awk/grep shapes and for a quoted route string.

### 4. Seeder proof: the `git apply` fallback silently applies nothing inside a repository

- **HIGH** (confidence: high) `head/evals/harness/lib/seed_tasks.py:225-230` — when `patch` is not on PATH, `apply_patch` runs `git apply -p1 FILE` in the scratch tree. Because the patch carries `diff --git a/… b/…` headers, `git apply` run from a directory that lies inside any git working tree (the scratch tree is `tempfile.mkdtemp()`, i.e. `$TMPDIR`; here `TMPDIR=/workspace/.eval/tmp`, inside the checkout) resolves paths against that repository, prints `Skipped patch 'tools/mathx/rounding.py'.` and exits **0**. The proof then runs against the unpatched tree. Reproduced with the PR's own tests: SB-1 → `proof-failed … not green at reference (exit 1, 2 failed, 1 passed)`; SR-3 → the suite-breaking `perf: skip the padding` commit printed `proof refactor-01 …: green at base (2 passed) / green at reference (2 passed)` and **was written as a task** (expected exit 1).
**File:** `head/evals/harness/lib/seed_tasks.py:225-230`
**Issue:** The fallback's exit code is trusted as proof that the reference patch applied. For refactor tasks that inverts the seeder's core guarantee ("green with the reference patch"); for bug-fix tasks it makes every candidate fail.
**Why This Matters:** A task whose reference patch breaks the suite can enter the frozen suite; the header's "proof" becomes fiction exactly on hosts without `patch` (this harness is one). CWE-252 (unchecked return value semantics).
**Required Fix:** Require `patch` (as the grader does at `ablation-grade.sh:1175`) and refuse with exit 2 when missing, or run the fallback with `GIT_CEILING_DIRECTORIES=<parent of tree>` (and `--check -v` rejecting any `Skipped patch` line). Then verify the patched tree differs from the base tree before running the proof. SB-1 and SR-3 should run in CI with `TMPDIR` inside the checkout to lock this in.

### 5. The grader's test suite is pinned to one developer's machine

- **HIGH** (confidence: high) `head/evals/tests/ablation-grade.bats:16` — `BATS_BIN="$HOME/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats"` is a path that exists on one workstation; line 48 symlinks it into the image stand-in `PATH`, so on any other host / CI `bats` inside the stub is a dangling link and AG-2 (bf-sh), AG-7 (bf-sh) and anything that shapes a `bats` command fail. Line 46 likewise hard-codes `/usr/bin/python3`.
**File:** `head/evals/tests/ablation-grade.bats:16` (and `:46`, `:48`)
**Issue:** A 1299-line grader lands with a 591-line test file that cannot pass anywhere but the author's laptop. The implementation report gives no evidence the bats suite was run at all (FAST-GATE: no test or lint run is recorded).
**Why This Matters:** The grader is the measurement instrument of the whole ablation; it is effectively untested in CI.
**Required Fix:** `BATS_BIN="$(command -v bats)"` with a `skip` when absent; `python3` stand-in via `command -v python3`. Record the bats run (all five new/changed files) in the implementation report.

---

## Observations

### 1. Seeders

- **MEDIUM** (confidence: high) `head/evals/harness/lib/seed_tasks.py:570` — `selected = cands[:a.select]` fixes the slots before building; a selected candidate that turns out `skip` (refactor: no covering test, line 444) or `secret` (lines 435/498) consumes a slot and is not replaced by the next candidate. The wrapper headers say the opposite ("refusals and skips do not count", `head/evals/harness/seed-bugfix-tasks.sh:43-44`; "a commit without a covering test is skipped and does not count", `head/evals/harness/seed-refactor-tasks.sh:37-38`). With five refactor candidates and `--select 4`, one lacking a covering test yields three tasks.
**Suggestion:** Iterate over all candidates and stop when `written + failed == select`.

- **MEDIUM** (confidence: medium) `head/evals/harness/lib/seed_tasks.py:196-198` — pytest counts are read from the last line of `stdout + stderr` concatenated; any stderr output after the summary (a Python warning at exit, a plugin message) makes `tail` a non-summary line, so `passed/failed` read 0 and the proof fails with a misleading reason. Parse stdout only, or scan backwards for the summary regex as the grader does.

- **LOW** (confidence: medium) `head/evals/tests/seed-bugfix.bats:183` — SB-6's "non-repository" case passes `--repo "$T"`; when `BATS_TEST_TMPDIR` lies inside a git checkout (this harness: `/workspace/.eval/tmp/...`) `git -C $T rev-parse --git-dir` succeeds, the enclosing repository is read and the seeder exits 0 (reproduced). `seed_tasks.py:538` could compare `rev-parse --show-toplevel` with the given directory; the test could use `mktemp -d /tmp/...`.

- **LOW** (confidence: medium) `head/evals/harness/lib/seed_tasks.py:227` — `patch -s -p1 … -i` without `--batch`/`--forward` (the grader uses both at `ablation-grade.sh:1175`); a reversed or already-applied hunk makes `patch` prompt on a tty.

- **LOW** (confidence: low) `head/evals/harness/lib/seed_tasks.py:52-53` — the git environment keeps `HOME` without `GIT_CONFIG_GLOBAL=/dev/null` (the grader sets it at line 679), so a user `log.showSignature`, `diff.external` or `core.autocrlf` can alter the parsed `--format`/`--numstat` output.

### 2. Grader correctness and robustness

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:239-244` — `remove_path` pre-chmods every entry of `ds` from `os.walk(followlinks=False)`; symlinks to directories are listed in `ds`, and `os.chmod` follows symlinks, so an agent-planted `tests/test_slug.py/x -> /home/<user>/project` makes the grader (always host-side) chmod the target to `0o700`. `shutil.rmtree` is symlink-safe; the pre-pass is not. Use `os.chmod(..., follow_symlinks=False)` / skip `islink`. CWE-59, CWE-732. (DISS-C-002)

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-grade.sh:652-653` — `all_pass` ignores `rc` and `timed_out` when a summary parsed; a TAP/pytest run that printed its plan and passing lines and then hung or failed in teardown (`rc=124`) counts as fully green, so an APPROVED gate gets `verdict_accuracy=true` on a tree whose test command did not succeed. Require `rc == 0 and not timed_out`. (DISS-002)

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-grade.sh:506-508` and `517-521` — the in-container `timeout 120` sends one TERM (no `-k`), and when the outer `subprocess.run(timeout=180)` fires it kills only the `docker run` client; the container keeps running with the bind mount on `grading/final`, so the next `fresh_dir` races a live mount. Use `timeout -k 10 120`, `--init`, and name the container so a timeout can `docker kill` it. (DISS-C-006)

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-grade.sh:1099-1105` — `suite_green_base` runs `test_command` on the base tree after `prepare` overlaid every manifest entry including the structural check; when its dest lies under the covered test directory (the natural choice, e.g. `tests/test_structure.py`), it is red at base by design and `suite_green_base` is false for every run, so `--self-check base` can never PASS and the failure message does not say why. Exclude the structural dest from the suite runs or document/validate the placement (the seeder's `todo` line gives no placement rule). (DISS-C-007)

- **LOW** (confidence: medium) `head/evals/harness/ablation-grade.sh:690-702` — `extract_snapshot` returns False silently for a missing bundle, bad commit id, failed `unbundle` (thin bundle) or `archive`; `grade` just `continue`s, leaving `verdict_accuracy_per_gate` null, indistinguishable from "gate did not run", with nothing on stderr. Print a warning naming the label and reason. (DISS-C-003)

- **LOW** (confidence: medium) `head/evals/harness/ablation-grade.sh:588-593` — `total` counts `skipped`/`xfailed`, and `static_cases` counts every `def test…(` whether or not pytest collects it, so a hidden file with one `skipif` or a nested `def test_helper()` makes `all_pass` permanently false (self-check reference FAIL, every APPROVED verdict scored inaccurate) with no hint that the grader is at fault. (DISS-C-005)

- **LOW** (confidence: medium) `head/evals/harness/ablation-grade.sh:1175` — `--self-check reference` requires `patch`; when absent the `FileNotFoundError` surfaces as `internal error: FileNotFoundError` (exit 2) rather than a named requirement. Check `shutil.which("patch")` and raise a `GradeError`.

- **LOW** (confidence: medium) `head/evals/harness/ablation-grade.sh:714` — `extractall(..., filter=keep)` needs Python ≥ 3.12 or the 3.8.17/3.9.17/3.10.12/3.11.4 backports; on an older interpreter the `TypeError` becomes an exit-2 internal error. State the floor in the header or guard it.

### 3. Report, scope and documentation

- **MEDIUM** (confidence: high) `pr/PR.md:1` — the title and the two commit subjects promise "sixteen frozen-suite tasks under grimoires/loa/evals/ablation-2.0/tasks/ (bugfix-01…04, refactor-01…04 …)" and "the freeze"; the diff contains no `tasks/*` directory and no `MANIFEST.sha256`. `reviewer.md` is the description verbatim, has no `## AC Verification` section and no record of the test runs (FAST-GATE). Either the deliverable is incomplete or the description is wrong; the report must say which and walk the sprint criterion with `file:line` evidence.

- **LOW** (confidence: low) `head/evals/harness/ablation-grade.sh:1` — no CHANGELOG or operator-doc change accompanies three new operator-facing scripts (`ablation-grade.sh`, two seeders) and a schema change (`source.churn`); if this repository keeps a CHANGELOG for `evals/`, add entries.

### 4. SIMPLICITY / complexity

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:166` — SIMPLICITY[shrink]: 1130 lines of Python live in a quoted heredoc inside a bash wrapper (`exec python3 -I - … <<'PY'`), which defeats linting, tracebacks with line numbers, `-m pytest`-style unit tests and editor tooling; the seeders already use the right shape (`lib/seed_tasks.py` + thin wrapper). Functions over the 50-line ceiling without justification: `grade` (1045-1142, 97 lines), `load_task` (319-419, 100 lines), `seed_tasks.py:main` (547-620), `build_bugfix` (370-436), `build_refactor` (439-499). Move the Python to `lib/ablation_grade.py`; split `grade` into `grade_build` / `grade_review_catch` / `grade_gates`. Net: the wrapper shrinks to ~15 lines; `net: -0 lines possible` overall (a restructuring, not a deletion). Lean enough otherwise.

---

## Cross-Model Observations

Two voices (`gpt-5.5-pro` primary, `claude-headless` companion, `counted_as: independent_voice`), nine findings, zero rejected. Triage: DISS-001 → Changes Required §1; DISS-002 → Observations §2 (MEDIUM); DISS-C-001 → Changes Required §3 (independently reproduced); DISS-C-002 → Observations §2 (MEDIUM); DISS-C-003 → Observations §2 (LOW); DISS-C-004 → Changes Required §2 (independently reproduced); DISS-C-005 → Observations §2 (LOW); DISS-C-006 → Observations §2 (MEDIUM); DISS-C-007 → Observations §2 (MEDIUM).

## Rejected dissent payloads

None. `metadata.rejected_summary` is empty and the listed sidecar `adversarial-rejected-review.jsonl` has zero rows.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | The described deliverable (sixteen task directories, suite freeze) is absent from the diff; five high findings above; no AC Verification in the report |

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| "review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict" (sprint.md) | Fail | Defects reported above with `head/<path>:<line>`; merge verdict: CHANGES_REQUIRED |
| Generated artefacts never become fix regions (bd-8o5rx, header `seed-corpus-from-record.sh:46-54`) | Pass | `generated_path`/`note_excluded` correct; pr-14 104→95 and pr-15 239→207 fix rows, defects untouched, SHA256SUMS verified with `sha256sum -c` |
| `source.churn` schema (`validate-suite.sh:214-225`) | Pass | Non-negative ints, bool excluded, unknown keys still refused |
| Grader reads only the documented inputs (DEC-0413) | Pass | AG-13 holds; `meta/` appears once, in the header |
| Grader is deterministic and id-only | Pass (as far as read) | No timestamps/paths written; ids `t<k>`/`d<k>` |
| Seeder proof "red at base, green at reference" | Fail | §4: fallback inverts the guarantee on hosts without `patch` |
| Grader tests run in CI | Fail | §5 |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (a hard-coded developer path, §5, is not a secret)
- [ ] Input validation and sanitization present — path checks are good; `remove_path` follows symlinks on chmod (Observations §2), agent-added pytest configuration honoured (§2)
- [x] Authentication/authorization correct (n/a)
- [x] No SQL/XSS injection vulnerabilities (no shell interpolation; argv vectors throughout)
- [x] Dependencies secure (stdlib only)
- [x] Error messages don't leak sensitive data (`excerpt_id` only; verified AG-10/AG-12 intent in code)

---

## Code Quality Summary

**Strengths:**
- Trust boundary held throughout (`python3 -I`, argv-only subprocesses, `safe_rel`/`safe_path`, `tarfile.data_filter`, no `.claude/` sourcing).
- Grading-tree isolation and byte-identical sandbox guarantee are well thought out and tested (AG-1, AG-4).
- Generated-path exclusion is minimal, surgical and verified end to end (manifests + checksums).

**Areas for Improvement:**
- Trust the exit code of nothing you did not verify (`git apply`, `all_pass` vs `rc`).
- Heuristic scanners need negative tests for common command shapes.
- Keep test infrastructure portable; a grader nobody can test is not a grader.

---

## Next Steps

1. Fix the five Changes Required items; add the regression tests named in each.
2. Run `bats evals/tests/ablation-grade.bats evals/tests/seed-bugfix.bats evals/tests/seed-refactor.bats evals/tests/seed-corpus.bats evals/tests/validate-suite.bats evals/tests/pipeline-run.bats` with `TMPDIR` inside the checkout and record the result.
3. Reconcile the PR description with the diff (ship the sixteen tasks and the freeze, or retitle) and add an `## AC Verification` walkthrough to `grimoires/loa/a2a/sprint-1/reviewer.md`.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":5,"medium":8,"low":8},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T03:49:19Z"} -->
