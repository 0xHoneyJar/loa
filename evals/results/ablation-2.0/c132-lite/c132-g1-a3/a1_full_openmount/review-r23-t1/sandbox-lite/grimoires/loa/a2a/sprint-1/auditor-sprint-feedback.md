# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Change under audit:** `pr/head.diff` (16 files; cited as `head/<path>:<line>` from `pr/head/`)
**Review feedback:** grimoires/loa/a2a/sprint-1/engineer-feedback.md (CHANGES_REQUIRED, 4 high / 9 medium / 5 low, excluded 0)

---

## Verdict: CHANGES_REQUIRED

---

## Pre-flight and scope

- **Prerequisite deviation.** The skill's Phase 0 requires the review to say "All good"; the review verdict is CHANGES_REQUIRED. The task mandates this audit of the PR as it stands, so the audit proceeded and records the deviation here (also in `grimoires/loa/NOTES.md`). No `COMPLETED` marker is written.
- **Dissent gate.** `adversarial-review.json` carries `metadata.model: gpt-5.5-pro`; the audit dissent ran with `--diff-file pr/head.diff` (no `--context-file`) and completed with two independent voices (see Cross-Model Security Observations). Not degraded.
- **Guardrails / integrity.** Input guardrails: PROCEED. `integrity_enforcement` knob: `none`. `grimoires/loa/known-failures.md` is absent (KF-SURFACE warning) — triaged without it.
- **Scope limits.** `pipeline-run.sh`, `freeze.sh`, `recall-vs-defects.sh` and `no-secrets.sh` are not in the PR; their behaviour is inferred from callers and from `docker-stub.sh:56`. The sixteen tasks and `MANIFEST.sha256` the PR title names are not in the diff — unable to assess the freeze. No documentation-coherence subagent reports exist in this workspace; the shell headers were verified by hand against the code (see Documentation).
- **Working files.** `grimoires/loa/a2a/audits/2026-10-21/SECURITY_ANALYSIS_TODO.md` (sources, sinks, flows), `grimoires/loa/a2a/audits/2026-10-21/findings.jsonl` (structured findings).

## Executive Summary

The change adds the cycle-130 ablation grader (`ablation-grade.sh`, a 1130-line Python program in a bash heredoc), the two history seeders over `lib/seed_tasks.py`, the `source.churn` schema key, the bd-8o5rx generated-artefact rule with regenerated `pr-14`/`pr-15` manifests, and bats coverage. The path trust boundary is well built: `safe_rel`/`safe_path` on every history or manifest path, argv-only `git`/`yq`/`patch`/`docker`, no `source`/`eval`, symlink blobs refused, `SHA256SUMS` re-verified here (both manifests OK), every shell file passes `bash -n` and both Python bodies `py_compile`.

The grader's integrity against the agent it grades is the problem. The hidden-test metric is read from the stdout of a process that imports agent-authored code: reproduced on this host with the grader's exact argv, an agent-added `conftest.py` prints forged `PASSED` lines and a forged summary after two real failures and exits 0, and a root `pyproject.toml` silences pytest's own reporter so the grader sees only the forgery. The same output steers the grader into opening arbitrary host paths with unbounded reads (`/dev/zero`, a FIFO), so a graded agent can hang or exhaust the grader. The review's four blocking findings stand unchanged in the head (interpreter floor, whole-suite `hidden_tests`, dissent envelope shape, operator-specific bats path; the last is calibrated medium here). The container runs agent code with no process, memory or CPU limits.

**Security Issues Found:**

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 5 |
| Medium | 13 |
| Low | 7 |

Excluded (speculative, low confidence): 0. Review `excluded`: 0 → `excluded_confirmed`: 0.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] Hidden-test results are forgeable by agent code running inside the test process

**Severity:** HIGH (confidence: high)
**File:** `head/evals/harness/ablation-grade.sh:549` (also `:530`, `:1080`, `:1129`)
**Issue:** `parse_pytest` takes the summary (`for l in reversed(lines): m = SUMMARY_RX.match(l.strip())`, :549-553) and the `-rA` outcome lines (`OUTCOME_RX`, :530) from the stdout of `python3 -I -s -m pytest … tests`. That process imports every `conftest.py` and reads every ini file in the tree; `prepare()` restores only the paths listed in `grader_protected`, which the seeders populate from files that already exist at the parent commit (`seed_tasks.py:384`, `:457`). Anything the agent *adds* at rootdir is loaded unchallenged.
**PoC (reproduced on this host, Python 3.11.2, pytest 9.0.2, the grader's argv):**
```
# tests/conftest.py written by the agent
import os, sys
def pytest_unconfigure(config):
    sys.stdout.write("PASSED tests/test_hidden.py::test_a\nPASSED tests/test_hidden.py::test_b\n===== 2 passed in 0.01s =====\n")
    sys.stdout.flush(); os._exit(0)
$ python3 -I -s -m pytest -p no:cacheprovider -q --rootdir $PWD -rA tests ; echo rc=$?
FAILED tests/test_hidden.py::test_a - assert 1 == 2
FAILED tests/test_hidden.py::test_b - assert 1 == 2
2 failed in 0.01s
PASSED tests/test_hidden.py::test_a
PASSED tests/test_hidden.py::test_b
===== 2 passed in 0.01s =====
rc=0
# grader's SUMMARY_RX picks: {'passed': 2}
```
Adding a root `pyproject.toml` with `[tool.pytest.ini_options] addopts = "-p no:terminal"` removes pytest's own lines entirely, so `outcomes` holds only the forged `PASSED` entries, `bad` is empty, `all_pass` (:653) is true, `hidden_tests` is 2/2 and `verdict_accuracy` (:1129-1130) follows. `all_pass` never consults `rc` either. The cross-model companion (DISS-C-001) reached the same conclusion by another route: `python_files`/`--ignore-glob` overrides plus N trivially passing tests of the agent's own.
**Impact:** `hidden_test_pass_rate` — the primary build-task metric — and `verdict_accuracy` can be set to 1.0 by the graded agent with a few lines of configuration, in every arm. The instrument the ablation rests on is forgeable.
**Fix:**
1. Before running the hidden suite, delete every `conftest.py`, `pytest.ini`, `pyproject.toml`, `setup.cfg`, `tox.ini` and `*.pth` in the tree that is not present in the fixture or the overlay (allowlist = fixture ∪ overlay dests), and run pytest with `-c /dev/null` (or `--override-ini`) so only grader-chosen options apply.
2. Score by node id, not by count: keep only `order`/`bad` entries whose path is an overlay destination (excluding `structural`), treat a hidden node missing from the listing as failed, and set `total = max(len(kept), static_cases)`.
3. Write `--junitxml` to a grader-chosen file and cross-check it against the summary; any mismatch → `parse_error`.
4. Add a bats case with a forging `conftest.py` and a `pyproject.toml` that must grade 0/N.
**Reference:** CWE-807 Reliance on Untrusted Inputs in a Security Decision — https://cwe.mitre.org/data/definitions/807.html; CWE-345 Insufficient Verification of Data Authenticity — https://cwe.mitre.org/data/definitions/345.html

### [HIGH-002] `hidden_tests` counts visible and agent-added tests

**Severity:** HIGH (confidence: high)
**File:** `head/evals/harness/ablation-grade.sh:1080` (also `:593`, `:637`)
**Issue:** `res = run_suite(final, t.test_command, t.static_cases)` runs the task's directory-wide `test_command` (`python3 -m pytest -q tests`, `seed_tasks.py:397`) and reports the whole result as `hidden_tests`; the static count (:637) is only a floor. AG-1 (`head/evals/tests/ablation-grade.bats:243`) asserts `7/7` for a hidden file of 5 cases because `tests/test_existing.py` is swept in, and the seeded TASK.md tells the agent to "add a regression test of your own" (`seed_tasks.py:432`). An agent that fixes nothing and adds 20 trivially passing tests reaches `hidden_tests` 22/27.
**Impact:** The headline metric rewards test volume, not correctness; confirmed review Changes Required §2 and dissent DISS-C-001.
**Fix:** The node-id scoping of HIGH-001 item 2; update AG-1 to expect `5/5`; report the whole-suite result separately if wanted.
**Reference:** CWE-807 — https://cwe.mitre.org/data/definitions/807.html

### [HIGH-003] Snapshot extraction crashes on Python < 3.11.4 (every gated arm exits 2)

**Severity:** HIGH (confidence: high)
**File:** `head/evals/harness/ablation-grade.sh:714` (also `:710`, `:492`)
**Issue:** `tf.extractall(tree, filter=keep)` and `tarfile.data_filter(member, path)` exist only on Python 3.12 or the 3.11.4+/3.10.12+/3.9.17+/3.8.17+ backports. Verified here: `python3 --version` → 3.11.2, `hasattr(tarfile, "data_filter")` → False. `extract_snapshot` runs whenever a gate verdict exists (:1110-1119), so every A1/A2/A3 run raises `TypeError`, caught at :1290 as exit 2 "internal error", while ungated arms grade fine — an arm-correlated hole. `python3 -P` (:492) is likewise 3.11+ only.
**Impact:** The per-arm aggregates `ablation-row.sh` builds from `grade.json` are biased by which arms ran a gate. Confirmed review Changes Required §1 (dissent DISS-C-006 of the review round concurred).
**Fix:** `if not hasattr(tarfile, "data_filter"): raise GradeError("ablation-grade needs Python >= 3.11.4 (tarfile filters)")`, or implement the member checks by hand (reject absolute names, `..`, links, devices — `safe_rel` already does most of it) and call `extractall(tree, members=…)` without `filter=`; pick `-P` only when `sys.version_info >= (3, 11)`.
**Reference:** Python tarfile extraction filters — https://docs.python.org/3/library/tarfile.html#extraction-filters; CWE-1104 Use of Unmaintained Third Party Components (interpreter floor) — https://cwe.mitre.org/data/definitions/1104.html

### [HIGH-004] Loa's own dissent envelope shape yields no citations (zero recall for dissent-only catches)

**Severity:** HIGH (confidence: high)
**File:** `head/evals/harness/ablation-grade.sh:864` (`:862-867`)
**Issue:** `envelope_texts` emits a finding's `anchor` string and, if present, `file|path` + `line|line_start|start_line`. Both envelopes produced in this sprint (`grimoires/loa/a2a/sprint-1/adversarial-review.json`, `adversarial-audit.json`) carry only `anchor: "evals/harness/ablation-grade.sh:<symbol>"`, `anchor_type: "function"`, `anchor_line: <int>` — no `file`, `path` or `line` key. The symbol anchor has no digits after the colon, so `citations()` (:818) parses nothing. AG-8 (`ablation-grade.bats:402-403`) tests two shapes the real script does not emit.
**Impact:** A defect caught only by the cross-model dissent is scored as missed, undercounting exactly the arms the ablation compares (DEC-0420 arm neutrality). Confirmed review Changes Required §3.
**Fix:** When `anchor` matches `^(?P<file>[^:]+):(?P<sym>[A-Za-z_]\w*)$` and `anchor_line` is an int, emit `f"{file}:{anchor_line}"` (and `-{anchor_line_end}` when present); accept `anchor_line` as a line key; add an AG-8 fixture copied from a real envelope.
**Reference:** CWE-20 Improper Input Validation — https://cwe.mitre.org/data/definitions/20.html

### [HIGH-005] Test output steers the grader into opening arbitrary host paths with unbounded reads

**Severity:** HIGH (confidence: high)
**File:** `head/evals/harness/ablation-grade.sh:576` (also `:536`)
**Issue:** The collection-error expansion opens `os.path.join(tree, f)` for every `ERROR <node>` line without `::` (:566-567, :574-581) and `def_line` opens `os.path.join(tree, path)` for every `PASSED|FAILED… <node>` line (:533-543); both `.read()` the whole file. Node text is agent-influenced output (HIGH-001). `os.path.join` discards `tree` when the node is absolute, `..` is never rejected, and `copy_tree` preserves agent symlinks verbatim (:283, :294), so `print("ERROR /dev/zero")`, a tree symlink `tests/x.py -> /dev/zero`, or a FIFO the agent created in its sandbox (whose absolute path it knows in host mode) gives an unbounded read — memory exhaustion of the grader process, outside the container and the 120 s test timeout — or a grader that blocks forever.
**Impact:** A graded agent can crash (exit 2) or hang the grader for its run and, under OOM, disturb the host; the read also reaches files outside the run directory the header promises never to read (content is only regex-counted, so disclosure is limited). Raised independently by the dissent primary (DISS-001, HIGH) and companion (DISS-C-003); the audit had the path aspect as low before the DoS angle.
**Fix:** Reject nodes whose path fails `safe_rel()` or `is_within(os.path.join(tree, path), tree)`; open with `O_NOFOLLOW`, `fstat` for `S_ISREG`, cap the read (1 MiB); apply in both `def_line` and the `coll_err` expansion.
**Reference:** CWE-22 Path Traversal — https://cwe.mitre.org/data/definitions/22.html; CWE-400 Uncontrolled Resource Consumption — https://cwe.mitre.org/data/definitions/400.html

---

## Medium Priority Issues

### [MED-001] Grading container has no process, memory or CPU limits and no cleanup on client timeout
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/harness/ablation-grade.sh:506` (`:506-508`, `:517-521`)
- **Issue:** The `docker run` argv has `--network none --read-only --tmpfs /tmp:rw,size=256m --user uid:gid` but no `--pids-limit`, `--memory`, `--cpus`, `--cap-drop ALL` or `--security-opt no-new-privileges`; `docker-stub.sh:56` lists `--pids-limit|--memory|--cpus` as flags the pipeline's own run uses, so the grader is the only unlimited container in the pipeline while running agent-authored test code. `timeout 120` is TERM-only (no `-k`), so a test that traps TERM runs on; the outer `subprocess.run(timeout=180)` then kills only the docker client and, with no `--name`, nothing kills the container, which keeps the rw mount of `grading/final` while the grader proceeds to `remove_path` it. The rw mount is also unbounded (a test can fill the host disk under `<run-dir>/grading/`). Dissent DISS-C-006 confirms.
- **Fix:** `--pids-limit 256 --memory 1g --memory-swap 1g --cpus 1 --cap-drop ALL --security-opt no-new-privileges`, `timeout -k 10 120`, a `--name <uuid>` and `docker kill` on `TimeoutExpired`.
- **Reference:** CWE-400 — https://cwe.mitre.org/data/definitions/400.html; CWE-770 — https://cwe.mitre.org/data/definitions/770.html

### [MED-002] `remove_path` chmods through agent-planted symlinks (write-boundary violation)
- **Severity:** MEDIUM (confidence: high) — dissent DISS-002 rated HIGH, DISS-C-005 MEDIUM; triaged medium: only directories the grader user owns are affected, owner access survives, no data loss.
- **File:** `head/evals/harness/ablation-grade.sh:242` (`:239-245`)
- **Issue:** `os.walk(followlinks=False)` still lists symlinks to directories in `ds`, and `os.chmod` follows them. `copy_tree` preserves the agent's symlinks verbatim (:283, :294), so a re-grade (`fresh_dir(grading)`, :1041) or a protected-directory restore (`put_file` → `remove_path`, :306) sets 0700 on the link target — the grader's home, a shared results directory, a socket directory — contradicting the header's "writes only grading/ and --out" (DEC-0413).
- **Fix:** Skip `os.path.islink(p)` entries before `chmod`, or `os.chmod(..., follow_symlinks=False)` where supported.
- **Reference:** CWE-59 Improper Link Resolution — https://cwe.mitre.org/data/definitions/59.html

### [MED-003] `--executor host` runs agent-authored code as the grader user with no runtime acknowledgement and no post-run freeze re-check
- **Severity:** MEDIUM (confidence: high) — dissent DISS-C-002 rated HIGH; triaged medium: opt-in, documented (header :77-81), container is the default (DEC-0491).
- **File:** `head/evals/harness/ablation-grade.sh:513` (`:510-515`)
- **Issue:** In host mode the test command runs with the caller's uid, network and filesystem; `env -i` and a scratch `HOME` are the only isolation, and `python3 -P -m pytest` still imports every `conftest.py` and `python_files` module from the agent's tree. Agent code can therefore read `~/.aws`, `~/.claude.json`, or rewrite the suite's `hidden/` tests and `MANIFEST.sha256` *after* `freeze_check` already ran (:1270), poisoning every later grade in every arm. Nothing warns at runtime; `grade.json` carries only `executor_mode: host`.
- **Fix:** Refuse `--executor host` for run-directory grading unless an explicit `--allow-host` flag is given (print a stderr warning); re-run `freeze.sh --check` after the test runs in host mode and exit 2 on drift; keep host mode for `--self-check` of trusted fixtures.
- **Reference:** CWE-250 Execution with Unnecessary Privileges — https://cwe.mitre.org/data/definitions/250.html; CWE-829 Inclusion of Functionality from Untrusted Control Sphere — https://cwe.mitre.org/data/definitions/829.html

### [MED-004] Verdict readers follow symlinks and read unbounded; verdicts come from agent-editable files
- **Severity:** MEDIUM (confidence: high)
- **File:** `head/evals/harness/ablation-grade.sh:766` (`:764-779`, `:782-790`)
- **Issue:** `gate_verdict` and `review_md_verdict` guard with `os.path.isfile()` only and then iterate `open(path)`, whereas `combined_findings` (:877) correctly adds `not os.path.islink(p)`. The three inputs (`sandbox/review.md`, the two a2a feedback files) are agent-writable: a symlink to `/dev/zero` yields one unbounded line (memory), a symlink to a FIFO blocks the grader, any readable host file is parsed for a trailer. Separately, the FIX1/FIX2 agent shares the sandbox with these files and can rewrite the reviewer's trailer, setting its own `verdict_accuracy` — the same tamperable-sandbox class the header already acknowledges for envelopes (:40-41). Dissent DISS-C-004.
- **Fix:** Reject symlinks and non-regular files, cap bytes read; derive verdicts from harness-owned copies under `eval/` (or a harness-recorded hash of the feedback file taken at gate time).
- **Reference:** CWE-59 — https://cwe.mitre.org/data/definitions/59.html; CWE-345 — https://cwe.mitre.org/data/definitions/345.html

### [MED-005] Regression suite runs after the hidden overlay
- **Severity:** MEDIUM (confidence: high)
- **File:** `head/evals/harness/ablation-grade.sh:1087` (`:1087-1090`)
- **Issue:** `prepare(t, base_tree)` overlays the hidden tests before `regression_command` runs on `base` and `final`; a regression command sweeping the overlay directory counts hidden cases, which fail at base by design, so `--self-check base` (:1219-1222) fails a correct task and pushes authors to `regression_command: null` (as both seeders already write).
- **Fix:** Run `regression_command` on copies taken before the overlay, or restore only `grader_protected` for that run.
- **Reference:** CWE-670 Always-Incorrect Control Flow — https://cwe.mitre.org/data/definitions/670.html

### [MED-006] `all_pass` ignores `rc` and `timed_out`
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/harness/ablation-grade.sh:653`
- **Issue:** `rc` and `timed_out` are recorded (:638) but never consulted; a suite killed after printing a passing summary (rc 124) still marks an APPROVED verdict accurate (:1129-1130) and a refactor suite green (:1105).
- **Fix:** `return res["rc"] == 0 and not res["timed_out"] and …`.
- **Reference:** CWE-754 Improper Check for Unusual Conditions — https://cwe.mitre.org/data/definitions/754.html

### [MED-007] Seeder proof and grader argv disagree on the import path
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/harness/ablation-grade.sh:492` (and `head/evals/harness/lib/seed_tasks.py:206-208`)
- **Issue:** The grader strips cwd from `sys.path` (`-I -s` in the image, `-P` on the host) while the seeders prove tasks with plain `python3 -m pytest` (cwd importable). A seeded task whose tests import by cwd passes its proof and grades 0/N in every arm.
- **Fix:** Share `shape_command`'s argv with the seeder proof, or make `--self-check reference` a hard pre-freeze step in `freeze.sh`.
- **Reference:** CWE-1068 Inconsistency Between Implementation and Documented Design — https://cwe.mitre.org/data/definitions/1068.html

### [MED-008] Silent null on snapshot failure; undocumented `"none"` verdict value
- **Severity:** MEDIUM (confidence: high)
- **File:** `head/evals/harness/ablation-grade.sh:1119` (and `:1057-1060`)
- **Issue:** A gate whose feedback file exists but whose snapshot cannot be extracted (missing bundle, non-hex or absent `index.json` entry, HIGH-003) hits `continue` and leaves `verdict_accuracy_per_gate[gate]` null, which the header (:110-111) reserves for "a gate that did not run". `verdict.value` can also be the literal `"none"` where the header promises APPROVED/CHANGES_REQUIRED/null.
- **Fix:** Record a reason (`snapshot_missing: [label]`) and map `"none"` to null in `verdict`.
- **Reference:** CWE-391 Unchecked Error Condition — https://cwe.mitre.org/data/definitions/391.html

### [MED-009] Contamination scan flags the substring `hidden` in ordinary inputs
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/harness/ablation-grade.sh:964`
- **Issue:** `"hidden" in low` marks `rg --hidden`, `find . -name '.hidden*'`, `ls --hide` and a Grep `pattern` of `hidden` as `contaminated`.
- **Fix:** Match a path component (`(^|/)hidden(/|$)`) and the `-i` word form; exclude the `--hidden` flag.
- **Reference:** CWE-185 Incorrect Regular Expression — https://cwe.mitre.org/data/definitions/185.html

### [MED-010] The tasks and freeze the PR describes are not in the change; VS-1 no longer asserts a count
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/harness/validate-suite.sh:1` (and `head/evals/tests/validate-suite.bats:31-44`)
- **Issue:** The PR title and `reviewer.md` claim "sixteen frozen-suite tasks under grimoires/loa/evals/ablation-2.0/tasks/" and "the freeze", yet `pr/head.diff` contains no file under `grimoires/` and no `MANIFEST.sha256`; VS-1 now derives its expected counts from whatever is committed, so it cannot fail on a wrong task count. The implementation report has no `## AC Verification` section.
- **Fix:** Include the task tree and `MANIFEST.sha256` or state where they land; keep VS-1 asserting a fixed `16`; add AC Verification.
- **Reference:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html

### [MED-011] `--select N` can write fewer than N tasks with exit 0
- **Severity:** MEDIUM (confidence: high)
- **File:** `head/evals/harness/lib/seed_tasks.py:570`
- **Issue:** `selected = cands[: a.select]` is fixed before building; a build-time `skip` (:593-597) or `secret` refusal (:588-592) consumes a slot and is never backfilled, contradicting both wrapper headers ("refusals and skips do not count", `seed-bugfix-tasks.sh:43-44`; `seed-refactor-tasks.sh:37-38`).
- **Fix:** Iterate over `cands` until `written + failed == a.select` or the list is exhausted.
- **Reference:** CWE-1068 — https://cwe.mitre.org/data/definitions/1068.html

### [MED-012] Grader body is an unlintable 1130-line heredoc with ~100-line functions
- **Severity:** MEDIUM (confidence: high)
- **File:** `head/evals/harness/ablation-grade.sh:166`
- **Issue:** Nothing lints or `py_compile`s the Python in CI (the audit extracted it by hand); `grade()` (:1045-1142) and `load_task()` (:319-419) each run ~100 lines. `seed_tasks.py` already shows the `lib/` pattern.
- **Fix:** Move the body to `evals/harness/lib/ablation_grade.py`, keep the `.sh` as the `exec python3 -I` wrapper, split `grade()` into build and review-catch halves.
- **Reference:** CWE-1120 Excessive Code Complexity — https://cwe.mitre.org/data/definitions/1120.html

### [MED-013] Test depends on one operator's dotfiles path for `bats`
- **Severity:** MEDIUM (confidence: high) — the review rated this HIGH; the audit calibrates it medium (CI evidence for the TAP path is lost; no production code path).
- **File:** `head/evals/tests/ablation-grade.bats:16` (and `:48`)
- **Issue:** `BATS_BIN="$HOME/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats"` is symlinked into the stub PATH; on any other machine the link dangles, `bats` execs 127 inside the stub, `run_suite` records `parse_error` 0/3, and AG-2 (:268-269) and AG-7 (:352-353) fail.
- **Fix:** `BATS_BIN="${LOA_TEST_BATS:-$(command -v bats || true)}"`; `skip "bats not on PATH"` in the two tests that need it when empty.
- **Reference:** CWE-1104 — https://cwe.mitre.org/data/definitions/1104.html

---

## Low Priority Issues

### [LOW-001] The no-secrets scan can be switched off from the wrapper's argv and misreports an absent scanner
- **File:** `head/evals/harness/seed-bugfix-tasks.sh:77` (`:77-78`; also `head/evals/harness/seed-refactor-tasks.sh:66-67`)
- **Issue:** `"$@"` follows the wrapper's `--no-secrets`, and argparse is last-wins, so a caller's `--no-secrets ''` disables `secrets_clean` (`seed_tasks.py:503-504`) silently. When `no-secrets.sh` is absent, rc 127 is read as a secret hit and every task is "refused … a secret pattern".
- **Fix:** Reject a caller-supplied `--no-secrets` in the wrapper; check the scanner exists in the missing-tool loop (exit 2 with its name); treat rc 127 as an error, not a hit.
- **Reference:** CWE-693 Protection Mechanism Failure — https://cwe.mitre.org/data/definitions/693.html

### [LOW-002] Credential directories are whitelisted by the host-mode contamination scan; lower-bound nature invisible in `grade.json`
- **File:** `head/evals/harness/ablation-grade.sh:953` (`:947-954`, `:962-984`)
- **Issue:** Host-mode allowed roots include `~/.aws`, `~/.claude.json` and `~/.codex`, so a Read of the caller's credentials is reported clean; the scan is substring-based and sidestepped by `hid""den`, `~/…` paths (ABS_WORD matches only words starting with `/`), relative traversal, or a script the agent writes. The header calls the scan a lower bound; `grade.json` exposes only `contaminated: null`. Dissent DISS-C-007.
- **Fix:** Add `scan_coverage: "lower_bound"` to `grade.json`; flag `~/.aws` and `~/.claude.json` reads as a `credential_path` pattern; expand `~` and `$HOME` before matching.
- **Reference:** CWE-778 Insufficient Logging — https://cwe.mitre.org/data/definitions/778.html

### [LOW-003] `review_catch.manifest` / `review_catch.fixture` are the only task.yaml paths not confined
- **File:** `head/evals/harness/ablation-grade.sh:407` (`:407-408`, `:436-437`)
- **Issue:** Every other task.yaml path goes through `safe_rel()`/`is_within()`; these two are joined raw, so an absolute or `..` path resolves anywhere. task.yaml is frozen (trusted) and the bats fixture rc-x relies on absolute paths (`ablation-grade.bats:175`), so exposure is limited to `--allow-unfrozen` authoring. Dissent DISS-C-008.
- **Fix:** Apply `safe_rel()` and require `is_within` of `REPO_ROOT` or the suite root; move the rc-x fixture to relative paths.
- **Reference:** CWE-22 — https://cwe.mitre.org/data/definitions/22.html

### [LOW-004] `counts()` reads only the last line of stdout+stderr
- **File:** `head/evals/harness/lib/seed_tasks.py:196`
- **Issue:** Any stderr emitted after the pytest summary (plugin warning, `ResourceWarning`) yields 0/0 and a spurious `proof-failed … not red at base` (exit 1).
- **Fix:** Scan lines in reverse for the summary as the grader's `SUMMARY_RX` does.
- **Reference:** CWE-754 — https://cwe.mitre.org/data/definitions/754.html

### [LOW-005] Seeder git calls honour the user's global config
- **File:** `head/evals/harness/lib/seed_tasks.py:52`
- **Issue:** `_git_env` passes `HOME` through and sets only `GIT_CONFIG_NOSYSTEM`; `log.showSignature=true` or a global `diff.external` changes the `%x1e`-delimited log (:86) and the patch bytes. The grader's `git_env` (`ablation-grade.sh:678-679`) sets `GIT_CONFIG_GLOBAL=/dev/null`.
- **Fix:** Mirror the grader: add `GIT_CONFIG_GLOBAL=/dev/null`.
- **Reference:** CWE-1188 Insecure Default Initialization — https://cwe.mitre.org/data/definitions/1188.html

### [LOW-006] python3 stand-in hardcodes `/usr/bin/python3`
- **File:** `head/evals/tests/ablation-grade.bats:46`
- **Issue:** Hosts whose `python3` is elsewhere (pyenv, Homebrew, `/usr/local/bin`) fail every container-path test.
- **Fix:** Use `$(command -v python3)` captured in `make_bin`.
- **Reference:** CWE-1104 — https://cwe.mitre.org/data/definitions/1104.html

### [LOW-007] `--self-check base` accepts an unrunnable suite
- **File:** `head/evals/harness/ablation-grade.sh:1222`
- **Issue:** `ok = h["passed"] < h["total"] and suite_green` passes when the test command cannot run at all (`parse_error`, passed 0 < total ≥ 1); the header promises "PASS when at least one hidden test fails".
- **Fix:** Require `not h["parse_error"] and not h["timed_out"]`; show `parse_error` in the evidence string.
- **Reference:** CWE-754 — https://cwe.mitre.org/data/definitions/754.html

---

## Observations

None excluded. Verified clean: both `pr-14.json`/`pr-15.json` match `SHA256SUMS` byte-for-byte; `generated_path` (`head/evals/harness/seed-corpus-from-record.sh:205-207`) filters `fix` rows only and leaves defect labels untouched as SC-7/SC-8 assert; the `source.churn` check (`head/evals/harness/validate-suite.sh:220-224`) excludes `bool`; `extract_snapshot` validates the commit as hex (:690), refuses symlinked bundles (:687) and runs git with a `/dev/null` global config; `write_grade` is tmp+`os.replace` under the harness-owned run directory; `shutil.rmtree` is fd-based so nested links are unlinked, not descended.

## Cross-Model Security Observations

`grimoires/loa/a2a/sprint-1/adversarial-audit.json`: `status: reviewed`, primary `gpt-5.5-pro` (answered by `codex-headless`), companion `claude-headless` (`counted_as: independent_voice`), `verdict_quality.consensus_outcome: consensus`, 2/2 voices, `degraded: false`, no `locality.degraded_security_review`. Eight findings, triaged:

- **DISS-001** (HIGH, primary) `parse_pytest` opens stdout-derived paths / `/dev/zero` — **adopted as HIGH-005** together with **DISS-C-003** (MEDIUM, same mechanism plus the FIFO case).
- **DISS-002** (HIGH, primary) `remove_path` follows attacker symlinks on chmod — **confirmed, triaged to MED-002** (grader-owned directories only; owner access survives); **DISS-C-005** (MEDIUM) is the same finding from the companion.
- **DISS-C-001** (HIGH, companion) count-based grading lets agent config/tests replace the hidden suite — **confirmed by cross-model review**: the audit's HIGH-001 (reproduced) and HIGH-002.
- **DISS-C-002** (HIGH, companion) host executor = code execution as the grader user — **confirmed, triaged to MED-003** (opt-in, documented, container default); its freeze-poisoning point is adopted in the fix.
- **DISS-C-004** (MEDIUM) `gate_verdict` symlink/FIFO and tamperable trailers — **adopted as MED-004**.
- **DISS-C-006** (MEDIUM) container limits, TERM-only timeout, orphan container — **confirmed by cross-model review**: MED-001.
- **DISS-C-007** (LOW) contamination bypass and credential-path whitelist — **adopted as LOW-002**.
- **DISS-C-008** (LOW) `review_catch` paths unconfined — **adopted as LOW-003**.

## Rejected dissent payloads

None. `metadata.rejected_summary` is empty, `rejected_count` is 0 and the sidecar `grimoires/loa/a2a/sprint-1/adversarial-rejected-audit.jsonl` has zero rows.

---

## Documentation

No `documentation-coherence-*` subagent reports exist in this workspace (the PR files are the entire input). Manual check: each new script's header documents its options, outputs and exit codes and matches the code read here, with the exceptions already counted (the header's `verdict_accuracy_per_gate` null and `verdict.value` contract, MED-008; the wrapper headers' `--select` promise, MED-011; the "writes only grading/ and --out" promise, MED-002/HIGH-005). The header states nothing about the grader's own interpreter requirement (HIGH-003). No secrets or internal URLs in docs or comments; the `BATS_BIN` path is a personal path, not a secret.

## Rubric Scores

| Dimension | Score (1–5) | Basis |
|-----------|-------------|-------|
| Security | 2 | Hidden-test results forgeable by the graded agent (HIGH-001/002), unbounded reads steered by test output (HIGH-005), no container limits (MED-001); path trust boundary otherwise well built |
| Architecture | 3 | 1130-line heredoc (MED-012); under-specified PR scope (MED-010) |
| Code Quality | 3 | Parse/accuracy edge cases (MED-005…009); clean argv-only subprocess use throughout |
| DevOps | 2 | Interpreter floor (HIGH-003); operator-specific test paths (MED-013, LOW-006) |
| Blockchain/Crypto | n/a | Not applicable |

## Security Checklist for This Sprint

- [x] No hardcoded secrets added (the `BATS_BIN` path is personal, not secret)
- [x] Input validation at the path trust boundary: `safe_rel`/`safe_path`, hex commit check, argv-only `git`/`yq`/`patch`/`docker`, no `source`/`eval` (AG-13)
- [ ] Test-result integrity against the graded agent: forgeable (HIGH-001, HIGH-002)
- [ ] Untrusted-output handling: unbounded opens of agent-named paths (HIGH-005); symlink-following verdict readers (MED-004)
- [ ] Write boundary: `remove_path` chmods through symlinks (MED-002)
- [ ] Resource limits on the grading container (MED-001)
- [x] Error messages leak no hidden-test names or excerpts (AG-12)
- [x] Dependencies: stdlib only; the `tarfile` filter is the right intent at the wrong floor (HIGH-003)

## Next Steps

1. Fix the five HIGH items: harden the hidden-suite run (remove non-fixture config files, `-c /dev/null`, node-id scoring, junitxml cross-check, a forging-conftest bats case), confine and cap every open of an output-derived path, guard the interpreter floor, parse the real envelope anchor shape.
2. Take MED-001…MED-004 in the same pass (container limits and kill-on-timeout, symlink-safe chmod, host-mode gate and post-run freeze re-check, symlink-safe verdict readers).
3. Decide the remaining medium and low items in `grimoires/loa/NOTES.md`; add `## AC Verification` to the implementation report and either include the sixteen tasks and `MANIFEST.sha256` or say where they land.
4. Run `/implement sprint-1` to fix, then `/review-sprint sprint-1` and `/audit-sprint sprint-1` again.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":5,"medium":13,"low":7},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T23:32:00Z"} -->
