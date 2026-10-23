# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md (Task 1.1: the change in `pr/head.diff`)
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)
**Review Feedback:** grimoires/loa/a2a/sprint-1/engineer-feedback.md (verdict CHANGES_REQUIRED, high 4 / medium 7 / low 8, excluded 1)
**Dissent envelope:** grimoires/loa/a2a/sprint-1/adversarial-audit.json (`gpt-5.5-pro` primary, `claude-headless` companion, `counted_as: independent_voice`, status `reviewed`, 2/2 voices, 0 rejected payloads)

---

## Verdict: CHANGES_REQUIRED

---

## Prerequisite deviation

Phase 0 requires `engineer-feedback.md` to say "All good". It does not: the senior-lead review returned CHANGES_REQUIRED. The task instruction for this run ("run /audit-sprint sprint-1 … work autonomously") asked for the audit regardless, so the audit was performed and this deviation is recorded here. No `COMPLETED` marker is written. The pre-flight `.claude/scripts/validate-sprint-id.sh` resolution was not run: `ledger.json` maps `sprint-1` to global sprint 1, so the directory is `a2a/sprint-1/` either way.

## Executive Summary

The change adds the cycle-130 ablation grader (`evals/harness/ablation-grade.sh`, a bash shim that `exec`s a `python3 -I` program from a quoted heredoc), the bug-fix and refactor seeders (`seed-bugfix-tasks.sh`, `seed-refactor-tasks.sh`, `lib/seed_tasks.py`), the bd-8o5rx rule in `seed-corpus-from-record.sh`, `source.churn` in `validate-suite.sh`, the pr-14/pr-15 manifest rewrites with their SHA256SUMS lines, and tests.

What holds up. The grader's declared trust boundary is largely real: nothing is sourced or `eval`'d from a variable (`ablation-grade.sh:164-166`); every subprocess is an argv list; `safe_rel` rejects absolute, `..` and backslash components for every manifest, overlay and protected path (`:250-256`); `ensure_parent` de-symlinks parent components before a write (`:259-268`); the docker invocation is `--network none --read-only --tmpfs /tmp` with the caller's uid (`:506-508`); `meta/` is never read; `grade.json` carries ids only. The seeders check every history path with `safe_path` before it touches disk and refuse symlink blobs (`seed_tasks.py:57-60, 152-153`). The pr-14/pr-15 manifests were verified byte-for-byte against the new SHA256SUMS lines; their `defects` arrays are identical to base and every removed `fix` row names a `dist/`, `.map`, `.d.ts`, `.checksum` or `.build-manifest.json` path. No secrets, no credentials, no network calls were added.

What blocks. The grader is the measurement instrument of the ablation and it trusts the thing it measures in two places: pytest's stdout and the agent's test-infrastructure files. An agent-added `conftest.py` or `pytest.ini` at any path the fixture lacks runs in-process with the hidden tests and can make every one of them report PASSED (HIGH-001). A single `ERROR /dev/zero` line in that stdout makes the grader, running on the host outside the container, open `/dev/zero` and read it without bound (HIGH-002). Four functional HIGHs from the review were each reproduced here by mechanism: the envelope reduction never reads `anchor_line` (HIGH-003); the seeders' `git apply` fallback is a silent no-op inside any git work tree, reproduced with a git-format patch (HIGH-004); `tarfile.extractall(filter=…)` raises `TypeError` on this host's Python 3.11.2 (HIGH-005); and `ablation-grade.bats` hard-codes one operator's bats path, which does not exist here (HIGH-006).

**Security Issues Found:**

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 6 |
| Medium | 9 |
| Low | 9 |

Excluded from the tally (speculative, confidence low, under `## Observations`): 1. Review's `excluded` confirmed: 1.

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] Hidden tests run in-process with agent-authored pytest infrastructure the grader does not protect

**Severity:** HIGH (confidence: medium)
**File:** `head/evals/harness/ablation-grade.sh:492-493` (pytest argv shape), `head/evals/harness/ablation-grade.sh:657-674` (`prepare`), `head/evals/harness/lib/seed_tasks.py:384`, `head/evals/harness/lib/seed_tasks.py:457`, `head/evals/harness/validate-suite.sh:280`
**Issue:** `shape_command` runs the hidden tests as `python3 -I -s -m pytest -p no:cacheprovider -q --rootdir /workspace -rA …` with cwd = the agent's tree. Nothing passes `--noconftest`, `-c <grader-owned ini>`, `-o addopts=` or `PYTEST_DISABLE_PLUGIN_AUTOLOAD`, so pytest loads every `conftest.py` between `/workspace` and the hidden test file and any `pytest.ini` / `pyproject.toml` / `setup.cfg` / `tox.ini` in the tree. `prepare()` restores only the paths listed in `grader_protected`, and for a listed path the fixture lacks it removes it; a file the agent *adds* at an unlisted path survives. The seeders list only the infrastructure that exists at the parent commit (`helper_files`, `seed_tasks.py:158-177`; applied at `:384` and `:457`), and `validate-suite.sh:280` rejects listing a path that is not in the fixture, so a task whose fixture has no root `conftest.py` or runner ini (SB-1's fixture is exactly this shape: only `tools/mathx/tests/conftest.py` is protected) cannot even declare them protected. A three-line root `conftest.py` with a `pytest_runtest_call` hookimpl that replaces `item.runtest` makes every hidden test PASS with its real node id; pytest exits 0 and prints a genuine summary, so `parse_pytest` has nothing to detect.
**Impact:** `hidden_tests`, `snapshot_tests`, `verdict_accuracy_per_gate` and `structural` for any build task can be forced to a full pass by the evaluated agent, in container mode, without touching stdout. The ablation's main arm metric becomes untrustworthy for any agent that games tests; agents under "make the tests pass" instructions are known to do so without prompting. Confidence is medium only because it requires the agent to take that step; the mechanism itself is certain.
**Confirmed by cross-model review:** DISS-C-001 (claude-headless, HIGH). The review carried the seeder half as a MEDIUM (Observations §3).
**Fix:** (1) Run the hidden tests under grader-owned configuration: `-c /dev/null` or a grader-written ini outside the tree, `-p no:cacheprovider --noconftest`, with `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1`, and load the fixture's own conftest explicitly via `-p` only when the task declares it. (2) Have `prepare()` remove every runner-config name (`conftest.py` at the root and along each hidden dest's path, `pytest.ini`, `pyproject.toml`, `setup.cfg`, `tox.ini`, `.pth`) that the fixture lacks, regardless of `grader_protected`. (3) Let `validate-suite.sh` accept absent protected paths (the grader already handles them) and have the seeders list the standard names unconditionally. (4) Add an AG case: an agent-added root `conftest.py` with a runtest hook must not turn 5/7 into 7/7.
**Reference:** CWE-807 Reliance on Untrusted Inputs in a Security Decision — https://cwe.mitre.org/data/definitions/807.html ; CWE-693 Protection Mechanism Failure — https://cwe.mitre.org/data/definitions/693.html

### [HIGH-002] The grader opens host paths taken from agent-controlled pytest output without bound

**Severity:** HIGH (confidence: high)
**File:** `head/evals/harness/ablation-grade.sh:576` (collection-error expansion), `head/evals/harness/ablation-grade.sh:536` (`def_line`), `head/evals/harness/ablation-grade.sh:566-567`
**Issue:** `parse_pytest` treats any `ERROR <node>` line whose node has no `::` as a collection-error file and runs `open(os.path.join(tree, f)).read()` (`:574-576`); `def_line` does the same for the path part of every outcome node (`:533-538`). The node text comes from the test process's stdout, which the agent's own test modules and conftest print to. `os.path.join(tree, "/dev/zero")` is `/dev/zero` (verified), so one printed line — `ERROR /dev/zero` followed by a valid summary — makes the grader process, which runs on the **host** even in container mode, read `/dev/zero` until memory is exhausted. The subprocess timeout no longer applies at that point. A sandbox symlink `tests/x.py -> /dev/zero` is copied verbatim by `copy_tree` (`:293-294`) and reached by the same `open()`; `../` components resolve outside the tree. The file contents never leave the grader, so this is availability, not disclosure.
```
ERROR /dev/zero
=== 1 error in 0.01s ===
```
**Impact:** One line of output from inside a `--network none` container hangs or kills the grader on the operator's host (exit 2 after the OOM, no `grade.json`, no row). Across a batch this is a reliable denial of grading for any task the agent chooses.
**Confirmed by cross-model review:** DISS-001 (gpt-5.5-pro, HIGH).
**Fix:** Resolve `os.path.realpath(os.path.join(tree, f))`, require `is_within(…, tree)` and `os.path.isfile` on the realpath, and read at most a fixed number of bytes (e.g. 2 MiB) in both `def_line` and the collection-error expansion; treat anything else as "no def line" / "no expansion". Add an AG case with `ERROR /dev/zero` in the stub output.
**Reference:** CWE-400 Uncontrolled Resource Consumption — https://cwe.mitre.org/data/definitions/400.html ; CWE-22 Improper Limitation of a Pathname to a Restricted Directory — https://cwe.mitre.org/data/definitions/22.html

### [HIGH-003] The envelope reduction never reads `anchor_line`, so symbol-anchored dissent findings yield no citation

**Severity:** HIGH (confidence: high)
**File:** `head/evals/harness/ablation-grade.sh:862-867`, `head/evals/harness/ablation-grade.sh:795-798`
**Issue:** `envelope_texts` emits `f["anchor"]` and a `file`/`path` + `line`/`line_start`/`start_line` pair, never `anchor_line`/`anchor_line_end`. The FR-4 envelope shape (`.claude/skills/auditing-security/resources/ADVERSARIAL-REVIEW.md` §"Numeric anchors": "Graders (the eval harness's envelope reduction) read `anchor_line` with the anchor's file as `path:line[-end]`") carries a symbol `anchor` such as `evals/harness/ablation-grade.sh:parse_pytest` plus `anchor_line: 576`; the `CITE` regex requires digits after the colon, so the symbol anchor produces nothing. Reproduced here: feeding a finding `{anchor: "evals/harness/ablation-grade.sh:envelope_texts", anchor_line: 862}` through `envelope_texts` → `citations` returns `[]`. Both envelopes in this sprint's own `a2a/sprint-1/` are of that shape (17 findings, 0 citations).
**Impact:** `recall`, `flags`, `missed` and `false_positives` for every A1-arm run systematically omit the dissent's contribution, the arm the ablation exists to measure. Review Changes Required §1 confirmed.
**Fix:** When `anchor_line` is an int, emit `f"{anchor_file}:{anchor_line}"` (and `-{anchor_line_end}` when present), with `anchor_file` the text before the last `:` of `anchor`, else `file`/`path`; keep the current fallbacks; extend AG-8 with a symbol anchor + `anchor_line`.
**Reference:** CWE-1288 Improper Validation of Consistency within Input — https://cwe.mitre.org/data/definitions/1288.html

### [HIGH-004] The seeders' `git apply` fallback is a silent no-op inside a git work tree

**Severity:** HIGH (confidence: high)
**File:** `head/evals/harness/lib/seed_tasks.py:225-230` (called from `:407` and `:473`; proof trees from `tempfile.mkdtemp()` at `:400`, `:467`)
**Issue:** Without `patch` on PATH, `apply_patch` runs `git apply -p1 <file>` in the proof tree. The reference patches are `git diff` output with `diff --git` headers (`:393-395`, `:461-463`), which git treats as top-level-relative: run from a subdirectory of any work tree, paths outside that subdirectory are ignored and the command exits 0. Reproduced here (`patch` absent, `TMPDIR=/workspace/.eval/tmp` inside the checkout): a git-format patch applied with `git apply -p1` from such a directory returned exit 0 and left the file unchanged; with `GIT_CEILING_DIRECTORIES` set it applied. The review reproduced the downstream effect: SR-3's suite-breaking refactor was reported green at reference and **written**; SB-1's correct fix was refused.
**Impact:** The red/green proof is the seeders' only guarantee before a task is moved into place; in this state it accepts a broken reference and refuses a good one, silently. `--self-check` cannot catch it on the same host because it requires `patch` unconditionally (`ablation-grade.sh:1175`).
**Fix:** Require `patch` (exit 2 with a clear message when absent), or run `git apply` with `GIT_CEILING_DIRECTORIES=<proof parent>` / `GIT_DIR` pointed at an empty directory **and** assert that at least one patched path changed.
**Reference:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html

### [HIGH-005] Undeclared Python ≥ 3.11.4 / 3.12 requirement crashes every gated build grade

**Severity:** HIGH (confidence: medium)
**File:** `head/evals/harness/ablation-grade.sh:710-714`, `head/evals/harness/ablation-grade.sh:492`, `head/evals/harness/ablation-grade.sh:166`
**Issue:** `extract_snapshot` calls `tarfile.data_filter` and `TarFile.extractall(tree, filter=keep)`, available only from Python 3.11.4 / 3.12. Verified on this host (3.11.2): `hasattr(tarfile, "data_filter")` is False and `extractall(..., filter=)` raises `TypeError: TarFile.extractall() got an unexpected keyword argument 'filter'`, which the top-level handler turns into `internal error … exit 2`. `extract_snapshot` runs whenever a gate verdict exists and a bundle is present (`:1110-1123`), i.e. every A1 run. Host mode additionally shapes pytest as `python3 -P` (`:492`), a 3.11+ flag. Nothing checks `sys.version_info`; the shim runs whatever `python3` is first on PATH. Confidence is medium only because the operator's grading host version is unknown.
**Impact:** No `grade.json` for the main arm on a Debian 12 / Ubuntu 22.04 interpreter; the failure is deep inside grading rather than a clear refusal. Note the fail-closed direction is correct: no insecure extraction happens on old interpreters.
**Fix:** Check `sys.version_info >= (3, 12)` (or feature-test `tarfile.data_filter`) at start and `die()` with the requirement; or guard with a manual filter equivalent (absolute names, `..`, links outside the tree) when `data_filter` is absent; drop `-P` below 3.11.
**Reference:** CWE-1104 Use of Unmaintained Third Party Components (runtime-compatibility class) — https://cwe.mitre.org/data/definitions/1104.html ; tarfile extraction filters — https://docs.python.org/3/library/tarfile.html#extraction-filters

### [HIGH-006] `ablation-grade.bats` depends on one operator's filesystem

**Severity:** HIGH (confidence: high)
**File:** `head/evals/tests/ablation-grade.bats:16`, `head/evals/tests/ablation-grade.bats:48`
**Issue:** `BATS_BIN="$HOME/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats"` is an absolute operator-specific path; `ln -s "$BATS_BIN" "$T/bin/bats"` then dangles on any other machine (here: path absent, bats is `/usr/local/bin/bats`). The stub PATH is `$T/bin:/usr/bin:/bin`, so the image stand-in's `bats --tap tests` exits 127, every bats-driven grade returns `parse_error: true`, and AG-2 (bf-sh half) and AG-7 fail.
**Impact:** The only coverage of `parse_tap`, the `bats --tap` shaping and bats-helper protection cannot run in CI or on a reviewer's machine; FAST-GATE parity for the TAP path is unverified.
**Fix:** `BATS_BIN="$(command -v bats)"` (skip the bf-sh cases when absent) or `$BATS_ROOT/bin/bats`.
**Reference:** CWE-1188 Insecure Default Initialization of Resource (hard-coded environment assumption) — https://cwe.mitre.org/data/definitions/1188.html

---

## Medium/Low Priority Issues

### Medium

### [MED-001] `remove_path` follows directory symlinks when it `chmod`s, so a sandbox symlink changes the mode of a host directory
- **File:** `head/evals/harness/ablation-grade.sh:239-244`, reached via `head/evals/harness/ablation-grade.sh:1040-1041` (`fresh_dir(grading)` on re-grade) and `head/evals/harness/ablation-grade.sh:305-306` (`put_file` removing an existing dest)
- **Issue:** `os.walk(p)` lists symlinks-to-directories in `dirnames` even with `followlinks=False`, and `os.chmod(…, 0o700)` follows symlinks on Linux. `copy_tree` preserves agent symlinks into `grading/final` (`:282-283`). Reproduced here: a walk over a tree containing `sub/lnk -> <dir>` changed the target from 0755 to 0700. Any directory owned by the grader's uid (results root, `~/.cache`, a shared output directory) that the agent names as a symlink target is chmod'ed on the next re-grade of that run or on `prepare()` replacing a populated directory. `shutil.rmtree` itself is fd-based and safe; only the pre-pass is affected. (confidence: high)
- **Fix:** skip entries where `os.path.islink(os.path.join(r, d))` before `chmod`, or use `os.chmod(…, follow_symlinks=False)` guarded by `os.supports_follow_symlinks`, or drop the pre-pass and use `shutil.rmtree(onerror=…)`.
- **Cross-model:** DISS-002 (gpt-5.5-pro) and DISS-C-003 (claude-headless), both MEDIUM. CWE-59 — https://cwe.mitre.org/data/definitions/59.html

### [MED-002] `--executor host` runs the agent's tree natively with the operator's privileges and real user site, with no warning in the header
- **File:** `head/evals/harness/ablation-grade.sh:511-514`, `head/evals/harness/ablation-grade.sh:25`, `head/evals/harness/ablation-grade.sh:78-81`
- **Issue:** Host mode runs the task's test command in `grading/final` (a verbatim copy of the sandbox) under `env -i` with `PYTHONUSERBASE=<the caller's real user base>`. `env -i` scrubs variables only; pytest imports the agent's conftest and modules, so agent-authored code runs as the operator with filesystem and network access and can write a `.pth` into the operator's user site for persistence. The header describes host mode as the no-docker alternative without stating it is unsandboxed execution of untrusted output. The dissent rated this HIGH; it is audited as MEDIUM because host mode is an explicit operator opt-in (DEC-0491 makes container the default) and a run produced in host mode has already executed the same code natively. (confidence: medium)
- **Fix:** Say so in the header and in the `--executor host` help text; refuse host mode unless an explicit acknowledgement flag/env is set; point `PYTHONUSERBASE` at a read-only copy or a scratch user base with pytest installed.
- **Cross-model:** DISS-C-002 (claude-headless, HIGH → re-rated). CWE-653 Improper Isolation or Compartmentalization — https://cwe.mitre.org/data/definitions/653.html

### [MED-003] Gate verdicts are read from agent-writable sandbox files
- **File:** `head/evals/harness/ablation-grade.sh:1054-1056`, `head/evals/harness/ablation-grade.sh:764-779`
- **Issue:** `verdicts`, `verdict`, `verdict_accuracy_per_gate` and which snapshot a gate "read" all come from `sandbox/grimoires/loa/a2a/sprint-1/{engineer-feedback,auditor-sprint-feedback}.md`. The header calls the sandbox copies of the dissent envelopes tamperable and reads those from `eval/`, but the feedback files have no harness-side copy, and the implementer's FIX2 phase runs after AUDIT with write access to them. An implementer that appends an `APPROVED` trailer after fixing its code scores `verdict_accuracy: true` for a gate that never approved. The dissent's symlink variant does not hold: `os.path.isfile` is False for a symlink to a device, so `/dev/zero` is not reachable this way. (confidence: medium)
- **Fix:** Have `pipeline-run.sh` copy each gate's feedback file to `<run-dir>/eval/` when the gate finishes (as it does for envelopes) and read the verdicts from there; fall back to the sandbox copy only with a `verdict_source: sandbox` marker.
- **Cross-model:** DISS-C-004 (claude-headless, MEDIUM). CWE-807 — https://cwe.mitre.org/data/definitions/807.html

### [MED-004] The build/refactor `base` self-check passes on `passed < total` alone
- **File:** `head/evals/harness/ablation-grade.sh:1222`, `head/evals/harness/ablation-grade.sh:1214`, fallback at `head/evals/harness/ablation-grade.sh:631-636`
- **Issue:** `run_suite`'s fallback synthesises `total = max(static, 1), passed = 0, parse_error: true` when the command cannot run (pytest missing in the image, a mistyped path, exit non-zero), so `self-check base` prints PASS for an ungradable task; only `reference` reveals it. (confidence: high)
- **Fix:** require `not h["parse_error"]` and `not h["timed_out"]` in the base condition and name `parse_error` in the evidence string. Review Observations §1 (DISS-C-001 of the review envelope).

### [MED-005] The seeders' proof interpreter shape differs from the grader's
- **File:** `head/evals/harness/lib/seed_tasks.py:201-208` vs `head/evals/harness/ablation-grade.sh:492`
- **Issue:** the proof runs `python3 -m pytest` (cwd on `sys.path`); the container grader runs `python3 -I -s -m pytest` (cwd removed). A hidden test importing a root-level package without a root `conftest.py` is green at proof and red at grading, with no hint why. (confidence: medium)
- **Fix:** make the proof use the grader's shape (`-I -s` plus `PYTHONUSERBASE`), or share `shape_command`.

### [MED-006] TAP results are keyed by description
- **File:** `head/evals/harness/ablation-grade.sh:610-611`, `head/evals/harness/ablation-grade.sh:617-621`
- **Issue:** two bats tests with the same description collapse to one key in `bad`; reproduced: `ok 1 same / not ok 2 same / ok 3 other` → `bad = {"same"}`, `failed_names = ["t2"]` by luck of ordering; a duplicate that fails first would be misnamed. (confidence: medium)
- **Fix:** key by test number `n`, derive `t<k>` from it.

### [MED-007] `copy_tree` has no error handling on an unreadable file
- **File:** `head/evals/harness/ablation-grade.sh:296`
- **Issue:** one mode-000 or root-owned regular file in `sandbox/` raises `PermissionError` → `internal error`, exit 2, no `grade.json`; `churn()` guards the same reads with `except OSError` (`:731-734`). (confidence: medium)
- **Fix:** catch `OSError`, skip, and count skipped files in `grade.json`.

### [MED-008] Contamination scan matches the `hidden` substring and the suite path in Grep patterns and Bash commands
- **File:** `head/evals/harness/ablation-grade.sh:964-966`
- **Issue:** `check_value("Grep", "pattern", "hidden")` → `hidden`; `grep -rn grimoires/loa/evals/ablation-2.0 pr/head.diff` → `suite_path` (both reproduced). A review-catch task over a PR whose diff contains `hidden/` (this one) is marked contaminated for reading its own input. The header documents the lower bound, not this false-positive class. (confidence: high)
- **Fix:** apply `hidden` to path-shaped fields and path-shaped Bash words only, or whitelist strings present in the task's own `pr/head.diff`.

### [MED-009] Seeders read pytest counts from the single last line of stdout+stderr
- **File:** `head/evals/harness/lib/seed_tasks.py:196-198`
- **Issue:** reproduced: `"3 passed in 0.1s\nDeprecationWarning: foo\n"` → `(0, 0)`; the candidate is refused with `not red at base (… 0 failed, 0 passed)`. (confidence: high)
- **Fix:** search stdout alone with the grader's `SUMMARY_RX` over all lines, last match wins.

### Low

### [LOW-001] FAILED then ERROR on the same node counts twice in `total`
- **File:** `head/evals/harness/ablation-grade.sh:588-589` — reproduced: `1 failed, 1 passed, 1 error` with one node both FAILED and ERROR → `total 3`, `order` of 2. `max(total, len(order))` corrects undercounts only.

### [LOW-002] Hidden overlay is applied to the `base` tree before `regression_command` runs
- **File:** `head/evals/harness/ablation-grade.sh:1086-1090` — a directory-scoped regression command covering a hidden dest is red at base; this authoring constraint is stated neither in the header nor by `validate-suite.sh`.

### [LOW-003] `timeout 120` without `-k`
- **File:** `head/evals/harness/ablation-grade.sh:508`, `head/evals/harness/ablation-grade.sh:514` — SIGTERM only; a test that ignores it outlives the grader as a detached `--rm` container or a host process while `timed_out: true` is recorded. Add `-k 10`. Cross-model: DISS-C-005 (claude-headless, LOW).

### [LOW-004] `patch` without `--batch`/`--forward` in the seeders
- **File:** `head/evals/harness/lib/seed_tasks.py:227` — can prompt on `/dev/tty` for a reversed or already-applied hunk and hang an interactive seeding run; the grader passes both (`ablation-grade.sh:1175`).

### [LOW-005] Image stand-in execs `/usr/bin/python3` literally
- **File:** `head/evals/tests/ablation-grade.bats:46` — breaks every grading test on a host whose `python3` lives elsewhere. Use `$(command -v python3)`.

### [LOW-006] SB-6 assumes `$T` is not inside a git work tree
- **File:** `head/evals/tests/seed-bugfix.bats:183` — `$T` follows `TMPDIR`; here `TMPDIR` is inside the checkout and `git -C "$TMPDIR" rev-parse --git-dir` succeeds, so the "not a git repository" assertion fails for environmental reasons.

### [LOW-007] VS-1 derives its expectation from the committed suite
- **File:** `head/evals/tests/validate-suite.bats:31-44` — `n` and `short` are computed from the suite under test, so a wrong count can no longer be caught; `[ "$c" -eq 4 ] || short=…` also counts a type with more than four tasks as short.

### [LOW-008] Generated-path exclusion runs after the `head/<file> missing` check
- **File:** `head/evals/harness/seed-corpus-from-record.sh:232-236` — a `fix` row for a generated path the fixture scope dropped errors out of `--build-manifest` instead of being excluded; move the `generated_path` test above the `isfile` check.

### [LOW-009] `review_catch.manifest` and `review_catch.fixture` accept absolute paths that escape the suite root
- **File:** `head/evals/harness/ablation-grade.sh:407-411`, `head/evals/harness/ablation-grade.sh:436-437` — `os.path.join(REPO_ROOT, rc["manifest"])` returns the absolute path unchanged, so a task can name any JSON file as its key and any directory as its PR fixture (which `copy_tree` then copies into `grading/pr`). Task authors are trusted and the suite is frozen, so the exposure is limited to `--allow-unfrozen` authoring; AG-8 relies on it. Document it or restrict to the suite root and `evals/fixtures/`.

---

## Observations

- **HIGH** (speculative, confidence: low) `head/evals/harness/ablation-grade.sh:546-555`, `head/evals/harness/ablation-grade.sh:591-594` — a test module that prints forged `PASSED <hidden node>` lines plus a well-formed summary and calls `os._exit(0)` scores a full pass: `parse_pytest` takes the last summary line and trusts the PASSED lines (reproduced: a two-line forged output parses to `passed 1 / total 1`). This is the review's excluded finding (DISS-C-005 of the review envelope); it remains speculative because HIGH-001 gives an agent the same result through supported pytest hooks without forging anything, and an unprompted agent writing `os._exit` forgeries is the less likely route. Confirmed as excluded. Mitigation when revisited: `--junitxml` to a path outside the tree and parse that.

---

## Cross-Model Security Observations

Adversarial audit dissent ran (two voices, `gpt-5.5-pro` primary via `codex-headless`, `claude-headless` companion, `counted_as: independent_voice`, `consensus`, status `reviewed`, `degraded: false`); envelope at `grimoires/loa/a2a/sprint-1/adversarial-audit.json`. Not a degraded review. Triage:

| ID | Voice | Severity | Disposition |
|----|-------|----------|-------------|
| DISS-001 | gpt-5.5-pro | HIGH | Verified (`os.path.join` absolute override, symlink read) → HIGH-002 |
| DISS-002 | gpt-5.5-pro | MEDIUM | Verified (chmod followed a dir symlink in scratch) → MED-001 |
| DISS-C-001 | claude-headless | HIGH | Duplicate of the auditor's HIGH-001 — confirmed by cross-model review |
| DISS-C-002 | claude-headless | HIGH | Mechanism agreed; re-rated MEDIUM (operator opt-in, documented default is container) → MED-002 |
| DISS-C-003 | claude-headless | MEDIUM | Same as DISS-002 → MED-001 |
| DISS-C-004 | claude-headless | MEDIUM | Forgery half → MED-003; symlink half rejected (`isfile` is False for a device symlink) |
| DISS-C-005 | claude-headless | LOW | Confirms LOW-003 |

## Rejected dissent payloads

- None: `metadata.rejected_summary` is empty and the listed sidecar `adversarial-rejected-audit.jsonl` has 0 rows.

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added — none in the diff; seeders run `no-secrets.sh` on every materialised task (`seed_tasks.py:502-506`)
- [x] Input validation on new entry points — `safe_rel`/`safe_path` on every manifest, overlay, protected, history path; task-id regex (`:1259`); run-dir `:`/`,` check (`:1050`). Gap: pytest-output paths (HIGH-002)
- [ ] Trust boundary with the graded subject — not held: agent-authored pytest infrastructure runs in-process (HIGH-001); verdicts read from sandbox (MED-003)
- [x] Authentication/authorization — n/a
- [x] No shell/SQL/XSS injection — argv-only subprocesses; quoted heredoc; nothing sourced or `eval`'d from a variable (`:164-166`, AG-13)
- [x] Error handling doesn't leak info — `grade.json` ids only (AG-12); error text limited to the grader's own messages
- [ ] Tests cover security paths — AG-2/AG-4 cover protected-file restoration and symlinked dirs; nothing covers an added conftest, a hostile node id, a symlink target chmod, or the TAP path on a machine other than the author's (HIGH-006)
- [x] Dependencies — stdlib only; `tarfile` extraction is filtered where the API exists (HIGH-005 for where it does not)

## Documentation Audit

No `grimoires/loa/a2a/subagent-reports/documentation-coherence-*.md` exists in this workspace; the header blocks were verified manually against the code. They match closely, with three gaps: host mode is not described as unsandboxed (MED-002), the regression-command/hidden-dest constraint is unstated (LOW-002), and no minimum Python version is stated anywhere (HIGH-005). `pr/PR.md` (the implementation report) carries no AC-verification walkthrough and no record of the test suites having run.

## Rubric Scores

| Dimension | Score | Basis |
|-----------|-------|-------|
| SEC-IV Input validation | 3 | Thorough on declared inputs; pytest stdout and sandbox infra files are unvalidated inputs to a grading decision (HIGH-001, HIGH-002) |
| SEC-AZ Authorization | 4 | n/a surface; container isolation correct by default; host mode undocumented (MED-002) |
| SEC-CI Confidentiality/Integrity | 3 | Grade integrity can be forced by the graded subject (HIGH-001, MED-003) |
| SEC-IN Injection prevention | 5 | argv-only, quoted heredoc, no sourcing |
| SEC-AV Availability | 2 | Unbounded host read from one output line (HIGH-002); `timeout` without `-k`; unguarded `copyfile` |
| ARCH-MO Modularity | 4 | Clear helper split; `grade()` ~100 lines |
| CQ-RD Readability | 4 | Headers double as specs; exit-code contracts explicit |
| DevOps / Portability | 2 | Undeclared interpreter version, operator-specific test path, TMPDIR-sensitive tests |

---

## Next Steps

1. Fix HIGH-001 and HIGH-002 first: run hidden tests under grader-owned pytest configuration with agent-added runner files removed, and bound every path read derived from test output to the grading tree.
2. Address HIGH-003 to HIGH-006 as specified in the review (`anchor_line`, `git apply` fallback, Python version guard, `BATS_BIN`).
3. Fix MED-001 (`chmod` on symlinks) alongside; it is a four-line change.
4. Run `bats evals/tests/ablation-grade.bats evals/tests/seed-bugfix.bats evals/tests/seed-refactor.bats evals/tests/seed-corpus.bats evals/tests/validate-suite.bats` on a clean host with `TMPDIR=/tmp` and record the result in the implementation report with an `## AC Verification` section.
5. Re-run `/review-sprint sprint-1`, then `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":6,"medium":9,"low":9},"excluded":1,"excluded_confirmed":1,"sprint_id":"sprint-1","ts":"2026-10-21T10:55:00Z"} -->
