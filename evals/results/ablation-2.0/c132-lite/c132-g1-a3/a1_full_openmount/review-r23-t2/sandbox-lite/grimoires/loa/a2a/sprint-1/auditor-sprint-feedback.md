# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)
**Change under review:** pr/head.diff — 16 files: `evals/harness/ablation-grade.sh` (new, 1299 lines; a Python program in a bash heredoc), `evals/harness/lib/seed_tasks.py` (new), `seed-bugfix-tasks.sh` / `seed-refactor-tasks.sh` (new wrappers), `seed-corpus-from-record.sh` (generated-path exclusion), `validate-suite.sh` (source.churn), four new/changed bats files, `docker-stub.sh`, two review-prs manifests and SHA256SUMS.

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

The grader's isolation design is mostly sound where it concerns the operator's own inputs: every task.yaml path goes through `safe_rel` ("`if not parts or ".." in parts: return None`", `head/evals/harness/ablation-grade.sh:251-256`), the container runs with "`--network none --read-only --tmpfs /tmp:rw,size=256m --user <uid>:<gid>`" (`:506-507`), git runs with "`GIT_CONFIG_GLOBAL: /dev/null, GIT_CONFIG_NOSYSTEM: 1`" (`:677-679`), no shell is spawned anywhere, and the seeder refuses symlinks and unsafe paths from history (`head/evals/harness/lib/seed_tasks.py:57-60`, `:152-153`). The SHA256SUMS in the head tree match the regenerated manifests (recomputed here: `manifests/pr-14.json: OK`, `manifests/pr-15.json: OK`).

The change cannot merge. The trust boundary the header promises, "It writes only <run-dir>/grading/ and the --out file" (`:41-42`), is crossed by a symlink-following chmod, and the measurement the grader exists to produce — the hidden-test pass rate — is forgeable by the graded agent: a two-hook `conftest.py` at an unprotected path turned two failing hidden tests into "2 passed", exit 0, `all_pass` true, in a reproduction run here against the head file's own functions. Eight high findings in total: six confirm the review's highs by independent reproduction, two are new (the agent-controlled pytest configuration, and the host executor running agent code unconfined with the operator's user site on `PYTHONUSERBASE`). The adversarial dissent (two voices) raised the forged-grade path independently and added a grader denial-of-service through agent-named file paths, recorded below as a medium.

Prerequisite note: `engineer-feedback.md` carries CHANGES REQUIRED, not "All good"; the Phase 0 prerequisite for a sprint audit is therefore unmet. The task instructions for this workspace direct the audit to run on the frozen PR regardless, so the audit proceeded and records the deviation here. No `br` database exists in this workspace, so the beads workflow was skipped. Docker and `patch` are not installed here, so every reproduction is against the head file's Python functions (extracted from the heredoc) and this host's Python 3.11.2, pytest 9.0.2 and bats at `/usr/local/bin/bats`.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 8 |
| Medium | 7 |
| Low | 10 |

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] Hidden-test run executes agent-controlled pytest configuration and trusts its output — the grade is forgeable

**Severity:** HIGH (confidence: high — reproduced)
**File:** `head/evals/harness/ablation-grade.sh:482-492` (shape_command), `:657-676` (prepare restores only listed paths), `:546-553` (parser takes the last summary line); `head/evals/harness/lib/seed_tasks.py:158-178` (`helper_files` protects only files present in history), `:384`, `:457`
**Issue:** `prepare()` restores `grader_protected` paths from the fixture and overlays `hidden/manifest.json`, then `run_suite(final, t.test_command)` runs "`python3 -I -s -m pytest -p no:cacheprovider -q --rootdir /workspace -rA …`" (`:492-493`) in the agent's final tree. pytest loads every `conftest.py` from the rootdir down to the test directory and every `pytest.ini` / `pyproject.toml` / `tox.ini` / `setup.cfg` at the root. `grader_protected` is a denylist the seeder derives from files that existed at the parent commit ("`if c in have: found.add(c)`", `seed_tasks.py:167`; "`for f in INFRA_ROOT_FILES: if f in have`", `:174-176`), so a root `conftest.py` or `pytest.ini` the repository never had is never protected and never removed. Reproduced with the head file's functions: a tree with `tests/test_hidden.py` holding two tests that `assert False`, plus an agent-added root `conftest.py`:
```python
def pytest_collection_modifyitems(session, config, items):
    for it in items:
        it.obj = lambda *a, **k: None
```
run with the exact argv `shape_command` produces → rc 0, "`2 passed in 0.01s`", `parse_pytest` → passed 2 / total 2 / bad ∅, `all_pass` → True. The dissent (DISS-001, DISS-C-001) describes the sibling vector: with `-s` nothing is captured, so a conftest that prints "`999 passed in 0.1s`" and calls `os._exit(0)` leaves a fake summary as the last line; `parse_pytest` takes "the LAST line matching SUMMARY_RX" (`:549-553`) and `total = max(total, static)` (`:637`) does not catch it. Also the fallback "`passed = total if rc == 0 else 0`" (`:633`) grants full marks to any `auto` command that exits 0 without a summary.
**Impact:** The agent under evaluation controls the number the ablation is about: `hidden_tests`, `suite_green_final`, `verdict_accuracy_per_gate` (`:1129`) and the reference self-check all derive from this run. Reward-hacking by editing test configuration is a documented model behaviour, not an exotic attacker; container isolation does not protect a result channel that is the agent's own stdout.
**Fix:** Run the hidden suite with `--noconftest -p no:cacheprovider -c /dev/null` (or `-c <protected ini>`) and re-inject the fixture's protected conftest explicitly (`-p` on a module copied under a grader-owned path, or `--confcutdir` set to a grader-owned directory); remove every root runner config the fixture lacks before the run; cross-check the `-rA` outcome lines against the static case list of the hidden files (every expected `path::name` must appear exactly once as PASSED) and treat a summary without matching outcome lines, a non-zero exit or a timeout as failing; drop the `rc == 0 ⇒ passed = total` fallback. Add AG tests for the conftest and fake-summary cases.
**Reference:** CWE-807 Reliance on Untrusted Inputs in a Security Decision — https://cwe.mitre.org/data/definitions/807.html; CWE-426 Untrusted Search Path — https://cwe.mitre.org/data/definitions/426.html

### [HIGH-002] `remove_path` follows symlinks when chmod-ing — a mode change outside `<run-dir>/grading/`

**Severity:** HIGH (confidence: high — reproduced)
**File:** `head/evals/harness/ablation-grade.sh:235-244` (chmod at `:242`), symlinks preserved by `copy_tree` at `:283` and `:294`, reached from `fresh_dir(grading)` `:1053`, `put_file` `:305-306`, and the `finally: remove_path(SCRATCH)` at `:1295`
**Issue:** "`for r, ds, _fs in os.walk(p): for d in ds: os.chmod(os.path.join(r, d), 0o700)`" — `os.walk` lists a symlink to a directory in `ds` even with the default `followlinks=False`, and `os.chmod` follows it. Reproduced here: `target/` at 0755, `tree/evil -> ../target`, `remove_path(tree)` → `target` is 0700 and `tree` is gone. Two ways agent content reaches the pre-pass: (a) a symlink left in `sandbox/` is copied into `grading/final` ("`os.symlink(os.readlink(sp), dp)`", `:283`) and the next grade of the same run dir calls `fresh_dir(grading)`; (b) the grading tree is bind-mounted `rw` during the hidden run (`:507`), so the agent's test code can plant the link itself, and in host mode `HOME`/`TMPDIR` is a scratch directory (`:512-514`) that the same process removes in `finally` (`:1295`) — no regrade needed. `shutil.rmtree` itself is symlink-safe; only the pre-pass is not. Confirms the review's Change 3 and the review dissent's DISS-C-001.
**Impact:** Any directory the grading user owns, anywhere on the host, loses group/other access (or a read-only suite root gains owner write), driven by untrusted content, in violation of the header's write contract (`:41-42`).
**Fix:** `if not os.path.islink(path): os.chmod(path, 0o700)` in the pre-pass (or `os.chmod(..., follow_symlinks=False)` where `os.chmod in os.supports_follow_symlinks`); better, drop the pre-pass and use `shutil.rmtree(p, onexc=…)` that chmods only the failing non-link entry. Add a test with a symlinked directory in the sandbox and assert the target's mode after two grades.
**Reference:** CWE-59 Improper Link Resolution Before File Access — https://cwe.mitre.org/data/definitions/59.html; CWE-61 UNIX Symbolic Link Following — https://cwe.mitre.org/data/definitions/61.html

### [HIGH-003] `--executor host` runs agent-authored code unconfined with the operator's user site on `PYTHONUSERBASE`

**Severity:** HIGH (confidence: medium — design-level; requires the operator to choose host mode on a real run)
**File:** `head/evals/harness/ablation-grade.sh:511-516`, `:492` (`python3 -P` host shape), header `:25`, `:77-82`
**Issue:** "`full = ["env", "-i", "PATH=" + os.environ.get("PATH", …), "HOME=" + home, "LC_ALL=C", "TMPDIR=" + home, "PYTHONUSERBASE=" + site.getuserbase(), "timeout", …] + argv`" runs `test_command`, `regression_command` and `structural_command` as the grading uid, with full network, in a tree whose conftest, helpers and module under test are agent-authored (HIGH-001). `env -i` scrubs variables only: `~` is still reachable through `getpwuid`, and `PYTHONUSERBASE` is the CALLER's real user base, so agent code can write a `.pth` or `sitecustomize.py` into `~/.local/lib/python3.x/site-packages` and persist into every later non-`-I` Python the operator runs. The header documents host mode as a plain alternative ("`--executor MODE container (default; DEC-0491) or host`", `:25`) and notes it was used for the Sprint 258 smoke, so it is a live path; nothing warns, nothing restricts it to self-check. The seeders run the same way but on trusted history, which is fine. Raised independently by the dissent (DISS-C-002).
**Impact:** Credential read (`~/.ssh`, `~/.aws`, `~/.claude.json`) and persistent code execution on the grading host by the graded agent, with no record: the contamination scan covers transcripts, not grade-time execution.
**Fix:** Refuse `--executor host` for a real run directory unless an explicit opt-in flag is given, and print a one-line warning when it is; point `PYTHONUSERBASE` at a throwaway copy (or vendor pytest into the scratch home) rather than the caller's; where available wrap the host run in `bwrap`/`unshare -rn` with the tree as the only writable mount; document the threat in the header.
**Reference:** CWE-250 Execution with Unnecessary Privileges — https://cwe.mitre.org/data/definitions/250.html; CWE-427 Uncontrolled Search Path Element — https://cwe.mitre.org/data/definitions/427.html; OWASP A05:2021 Security Misconfiguration — https://owasp.org/Top10/A05_2021-Security_Misconfiguration/

### [HIGH-004] Contamination `outside_path` treats any quoted `/word` in a Bash command as a path — honest runs graded contaminated

**Severity:** HIGH (confidence: high — reproduced)
**File:** `head/evals/harness/ablation-grade.sh:940` (ABS_WORD), `:977-980` (candidate loop; the one-component exemption at `:978` requires a trailing slash)
**Issue:** "`for w in ABS_WORD.findall(val): if w.startswith("//") or re.match(r"^/[^/]+/$", w): continue; cands.append(w)`" and anything outside the roots is `outside_path`. Reproduced with the head file's `check_value` under the container roots: `grep -rn "/review-sprint" .claude` → `outside_path`; `grep -n '/implement' pr/head.diff` → `outside_path`; `echo "run /plan then /build"` → `outside_path`; `grep -rn "/health" src` → `outside_path`. The review-catch PRs are Loa changes full of slash-commands; a reviewer grepping for one is marked contaminated. Confirms the review's Change 1.
**Impact:** `contaminated` is a run-level verdict joined into runs.jsonl (header `:118-125`); a false positive discards or taints an honest run, and the header describes the scan as a LOWER bound, not an over-reporter.
**Fix:** Treat a Bash word as a path only when its first component is a real top-level directory (the fixed root set or `os.listdir("/")` of the image) or when it has two or more components and exists in the tree; drop the trailing-slash requirement in the one-component exemption; add the reproduced inputs to AG-11 as clean cases.
**Reference:** CWE-185 Incorrect Regular Expression — https://cwe.mitre.org/data/definitions/185.html

### [HIGH-005] Snapshot extraction uses the Python ≥ 3.11.4 / 3.12 `tarfile` filter API — every gated run dies with "internal error" on this interpreter

**Severity:** HIGH (confidence: high — reproduced)
**File:** `head/evals/harness/ablation-grade.sh:705-714` (`tarfile.data_filter` `:710`, `extractall(tree, filter=keep)` `:714`), generic handler `:1291`; `python3 -P` at `:492` is 3.11+
**Issue:** On this workspace's `/usr/bin/python3` 3.11.2: `hasattr(tarfile, "data_filter")` → False; `extractall(..., filter=…)` → "`TypeError: TarFile.extractall() got an unexpected keyword argument 'filter'`", caught at `:1290-1291` → "internal error", exit 2, no grade.json. `extract_snapshot` runs for every run with a REVIEW/AUDIT verdict and a snapshot bundle (`:1115-1120`), i.e. exactly the gated arms; ungated runs grade fine, so the failure looks arm-specific. Confirms the review's Change 2 (and its dissent's DISS-C-006).
**Impact:** The instrument fails on half the matrix with an opaque message; no version floor is declared.
**Fix:** Declare the floor once (`sys.version_info >= (3, 12)` → a clear `GradeError` and a header line), or guard: `if hasattr(tarfile, "data_filter")` else walk members, apply `safe_rel` plus a regular/dir/symlink-only check and absolute/escaping link-target rejection, and extract one by one. Apply the same floor to `-P`.
**Reference:** CWE-755 Improper Handling of Exceptional Conditions — https://cwe.mitre.org/data/definitions/755.html

### [HIGH-006] `envelope_texts` never reads `anchor_line` — dissent findings never reach `gates-combined.md`

**Severity:** HIGH (confidence: high — reproduced against the live envelope)
**File:** `head/evals/harness/ablation-grade.sh:854-867` (`:864-865`: "`fp = f.get("file") or f.get("path"); ln = f.get("line") or f.get("line_start") or f.get("start_line")`"); header promise `:96-97`
**Issue:** Real envelopes carry `anchor` as `path:symbol` plus `anchor_line` / `anchor_line_end` (both envelopes in this workspace: e.g. `"anchor": "evals/harness/ablation-grade.sh:envelope_texts", "anchor_line": 864`). Fed to the head file's `envelope_texts`, this workspace's `adversarial-review.json` (8 findings) yields 8 strings and 0 citations; `{"anchor":"lib/x.sh:handle","anchor_line":42}` → `['lib/x.sh:handle']` → `[]`. AG-8 passes only because its fixtures use `anchor: "lib/x.sh:20"` and `file`+`line` (`head/evals/tests/ablation-grade.bats:402-403`), shapes the producer does not write. Confirms the review's Change 4.
**Impact:** The arm-neutral reduction (DEC-0420) silently drops the dissent's findings, lowering recall for exactly the arms whose gates run it — a bias in the ablation's direction of interest.
**Fix:** When `anchor_line` is an int, split `anchor` on the first `:` and emit `path:anchor_line[-anchor_line_end]`; keep the fallbacks; change the AG-8 fixtures to the real shape so the test fails on the current code.
**Reference:** CWE-1023 Incomplete Comparison with Missing Factors — https://cwe.mitre.org/data/definitions/1023.html

### [HIGH-007] `all_pass` ignores the exit status and the timeout flag

**Severity:** HIGH (confidence: medium)
**File:** `head/evals/harness/ablation-grade.sh:652-653`; consumers `:1105`, `:1129`, `:1216`, `:1224`
**Issue:** "`return res["passed"] >= res["total"] and not res["bad"] and not res["parse_error"]`". Reproduced: output "`PASSED tests/t.py::test_a[1] / !!! KeyboardInterrupt !!! / 1 passed in 0.05s`" with rc 2 → passed 1 / total 1 → `all_pass` True. Code under test that raises `KeyboardInterrupt` after the first parametrized case leaves a clean partial summary; the static floor counts `def test` functions, not cases (`:429-430`). A run that `timed_out` after printing a summary is likewise "all pass". Confirms the review's Change 5 and the review dissent's DISS-002.
**Impact:** `verdict_accuracy_per_gate` marks a wrong APPROVED as accurate; the reference self-check passes on an interrupted suite.
**Fix:** `all_pass` must also require `res["rc"] == 0 and not res["timed_out"]`; record `rc` in `hidden_tests`; add a test with a suite that exits non-zero after a clean partial summary.
**Reference:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html

### [HIGH-008] The grader's test suite depends on one developer's dotfiles path for bats

**Severity:** HIGH (confidence: high — the path is absent here; bats is `/usr/local/bin/bats`)
**File:** `head/evals/tests/ablation-grade.bats:16`, `:48`, `:51`
**Issue:** "`BATS_BIN="$HOME/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats"`" is symlinked into the stub image's PATH ("`ln -s "$BATS_BIN" "$T/bin/bats"`", `:48`) whose PATH is `$T/bin:/usr/bin:/bin` (`:51`). On this host the dotfiles path does not exist and bats-core's default install is `/usr/local/bin`, so the link dangles, the stub's `bats --tap` is rc 127, the bf-sh run is a parse error with 0 passed, and AG-2 (`:268-269`) and AG-7 (`:352`) fail. The seeders already solve this with `LOA_SEED_BATS` (`head/evals/harness/seed-bugfix-tasks.sh:51`). Confirms the review's Change 6.
**Impact:** The only evidence that the grader's TAP path works passes on the author's machine alone; the delivered verification cannot run in CI or on a reviewer's host.
**Fix:** `BATS_BIN="${LOA_SEED_BATS:-$(command -v bats)}"` with `skip` when empty; same treatment for `/usr/bin/python3` at `:46` (see LOW-007).
**Reference:** CWE-1052 Excessive Use of Hard-Coded Literals in Initialization — https://cwe.mitre.org/data/definitions/1052.html

---

## Medium/Low Priority Issues

### [MED-001] `"hidden" in low` is a substring test over every scanned field
- **Severity:** MEDIUM (confidence: high — reproduced)
- **File:** `head/evals/harness/ablation-grade.sh:964`
- **Issue:** "`if "hidden" in low: return "hidden"`" — `grep -rn hidden_size model.py` → `hidden`; a Grep pattern `Hidden` → `hidden` (both reproduced). The harness text of this very PR contains the word in ordinary places.
- **Fix:** Word-boundary match (`\bhidden\b` and the path form `/hidden/`), restricted to path-shaped fields; state the false-positive risk in the header.
- **Reference:** CWE-185 — https://cwe.mitre.org/data/definitions/185.html

### [MED-002] Container lifecycle and resource limits: `timeout` without `-k`, orphaned container on the outer deadline, no pids/memory/capability limits
- **Severity:** MEDIUM (confidence: high)
- **File:** `head/evals/harness/ablation-grade.sh:506-508`, `:514`, `:517-521`
- **Issue:** "`A.image, "timeout", str(TEST_TIMEOUT_S)] + argv`" has no `--kill-after`; on the outer `TimeoutExpired` (`:519`) Python kills only the docker CLI, and `--rm` applies only when the container exits, so a test that ignores SIGTERM leaves a container running indefinitely with the grading tree mounted `rw`. In host mode the orphaned pytest keeps writing into `grading/<label>` while `regression_command` reads the same tree. The run also omits `--pids-limit`, `--memory`, `--cap-drop ALL` and `--security-opt no-new-privileges`, although `docker-stub.sh` already accepts the limit flags (`head/evals/tests/fixtures/docker-stub.sh:56`). The dissent rated this HIGH (DISS-002, DISS-C-003, DISS-C-005); the auditor keeps it MEDIUM because the scenario needs hostile code that traps SIGTERM, and the damage is host exhaustion rather than a wrong grade — but it is a cheap, standard hardening gap on a boundary that runs untrusted code.
- **Fix:** `timeout -k 10 120`; `--init --name <unique>` and `docker kill <name>` in a `finally`; `--pids-limit 256 --memory 1g --memory-swap 1g --cap-drop ALL --security-opt no-new-privileges`; in host mode run in its own process group and kill the group.
- **Reference:** CWE-400 Uncontrolled Resource Consumption — https://cwe.mitre.org/data/definitions/400.html; CWE-770 — https://cwe.mitre.org/data/definitions/770.html; CWE-250 — https://cwe.mitre.org/data/definitions/250.html

### [MED-003] `parse_pytest` opens host files named by agent-influenced test output — grader denial of service and a limited out-of-tree read
- **Severity:** MEDIUM (confidence: high — reproduced)
- **File:** `head/evals/harness/ablation-grade.sh:576` ("`text = open(os.path.join(tree, f), …).read()`" for an `ERROR <node>` line without `::`), `:536` (`def_line` opens every PASSED/FAILED node's path)
- **Issue:** `os.path.join(tree, f)` discards `tree` when `f` is absolute, and `..` is not rejected. Reproduced: an output line `ERROR <absolute path outside the tree>` made the grader read that file and expand its three `def test` functions into the total; `PASSED /etc/hostname::test_x` opened `/etc/hostname` without error. With `-s` the agent's code prints whatever it likes, so `ERROR /dev/zero` reads an infinite device until the grader is OOM-killed or hangs — the agent vetoes its own grade (exit 2) instead of receiving a failing one. Raised by the dissent (DISS-C-004).
- **Fix:** Validate node paths with `safe_rel()` and `is_within(tree)` before opening, `lstat` for a regular file, cap the read (1 MiB), and treat an unresolvable path as a plain `bad` outcome without expansion.
- **Reference:** CWE-22 Path Traversal — https://cwe.mitre.org/data/definitions/22.html; CWE-400 — https://cwe.mitre.org/data/definitions/400.html

### [MED-004] `--self-check base` passes on `passed < total` alone, so a run that executed nothing reports PASS
- **Severity:** MEDIUM (confidence: high)
- **File:** `head/evals/harness/ablation-grade.sh:1214` ("`ok = st["passed"] < st["total"] and green`"), `:1222` ("`ok = h["passed"] < h["total"] and suite_green`")
- **Issue:** With `parse_error: true` (pytest missing in the image, `-P` unsupported, a mount path with `:`) `run_suite` returns `passed = 0 < total` (`:633`), so base PASSes with nothing executed. Confirms the review's observation (and its dissent's DISS-C-005).
- **Fix:** Require `not h["parse_error"]` (and `rc` semantics once HIGH-007 lands) in the base branch for build and refactor.
- **Reference:** CWE-754 — https://cwe.mitre.org/data/definitions/754.html

### [MED-005] Refactor hidden run also collects the structural check when its dest lies under the test command's path; nothing validates the constraint
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/harness/ablation-grade.sh:1098-1105`, seeder hint `head/evals/harness/lib/seed_tasks.py:613-614`
- **Issue:** `run_suite(final, t.test_command, …)` runs e.g. `pytest tests`; a structural check overlaid at `tests/structural/test_x.py` is collected too, so `hidden_tests` is red at base by design, `suite_green_base` is false (`:1105`), and a correctly authored task fails `--self-check base`. Neither `validate-suite.sh` nor the headers state where the dest may land.
- **Fix:** Validate in `validate-suite.sh` that the structural dest is outside every `test_command` path, or deselect it in the hidden run (`--deselect`/`--ignore`), and say so in both headers.
- **Reference:** CWE-1068 Inconsistency Between Implementation and Documented Design — https://cwe.mitre.org/data/definitions/1068.html

### [MED-006] Complexity: `grade()` and `load_task()` are ~100 lines each inside a 1,100-line Python heredoc that cannot be imported or unit-tested
- **Severity:** MEDIUM (confidence: high)
- **File:** `head/evals/harness/ablation-grade.sh:166` (heredoc start), `:319-432` (`load_task`), `:1045-1142` (`grade`)
- **Issue:** Both functions are twice the 50-line threshold; `parse_pytest` is 54 and `main` 59. Because the program lives in `exec python3 -I - … <<'PY'`, no linter, `py_compile` step or pytest can target it, and this audit had to carve lines 167-1284 into a scratch module to run its reproductions. SIMPLICITY[shrink].
- **Fix:** Move the program to `evals/harness/lib/ablation_grade.py` (the seeders already use `lib/`) and keep the `.sh` as the `exec python3 -I` wrapper; split `grade()` into `grade_build()` / `grade_review_catch()` / `gate_accuracy()` and `load_task()` into `load_overlay()` / `load_review_catch()`.
- **Reference:** CWE-1120 Excessive Code Complexity — https://cwe.mitre.org/data/definitions/1120.html

### [MED-007] The PR description claims sixteen frozen tasks and "the freeze"; the change contains neither
- **Severity:** MEDIUM (confidence: high)
- **File:** `pr/PR.md:1-3` vs the 16-file list in `pr/head.diff`
- **Issue:** No file under `grimoires/` and no `MANIFEST.sha256` is in the diff, and the report carries no AC walkthrough. The task content (planted defects, TASK.md leak scans) and the freeze are unreviewed and unaudited here.
- **Fix:** State in the description where the tasks and the freeze travel, or add them to this change with their self-check evidence.
- **Reference:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html

### [LOW-001] Seeder proof parses the LAST line of stdout+stderr
- **Severity:** LOW (confidence: medium)
- **File:** `head/evals/harness/lib/seed_tasks.py:196-198`, `:213`
- **Issue:** "`tail = output.strip().splitlines()[-1]`" — a trailing stderr line (a plugin warning) yields 0 passed / 0 failed → spurious "not red at base".
- **Fix:** Scan for the last line matching a summary regex, as the grader does.
- **Reference:** CWE-754 — https://cwe.mitre.org/data/definitions/754.html

### [LOW-002] `patch` without `--batch --forward` can prompt on inherited stdin
- **Severity:** LOW (confidence: medium)
- **File:** `head/evals/harness/lib/seed_tasks.py:227`
- **Issue:** "`["patch", "-s", "-p1", "--no-backup-if-mismatch", "-i", patch_file]`" — an already-applied or reversed hunk makes `patch` ask; the grader's call (`ablation-grade.sh:1175`) has the flags.
- **Fix:** Mirror the grader; pass `stdin=subprocess.DEVNULL`.
- **Reference:** CWE-754 — https://cwe.mitre.org/data/definitions/754.html

### [LOW-003] Citation regex matches version tokens
- **Severity:** LOW (confidence: high — reproduced)
- **File:** `head/evals/harness/ablation-grade.sh:794-798`
- **Issue:** `citations("version 1.2.3:4")` → `[('1.2.3', 4, 4)]`, counted by `false_positives()` as a stray region. Inherited from recall-vs-defects.sh 1.1.2.
- **Fix:** Require the path to contain a `/` or a known extension list; note the FP source in the header.
- **Reference:** CWE-185 — https://cwe.mitre.org/data/definitions/185.html

### [LOW-004] `gate_verdict` returns the string `"none"`, which leaks into `verdict.value`
- **Severity:** LOW (confidence: high — reproduced)
- **File:** `head/evals/harness/ablation-grade.sh:764-779` (`return "none"` at `:774`, `:778`), `:1057-1060`
- **Issue:** A trailer-less `auditor-sprint-feedback.md` gives `verdict = {"value": "none"}` and masks a valid review verdict; the header documents only `APPROVED | CHANGES_REQUIRED | null`.
- **Fix:** Map `"none"` to `null` in `verdict`, or document the third value.
- **Reference:** CWE-1068 — https://cwe.mitre.org/data/definitions/1068.html

### [LOW-005] `fresh_dir(grading)` wipes the previous grading tree before `docker_ready()` can refuse
- **Severity:** LOW (confidence: high)
- **File:** `head/evals/harness/ablation-grade.sh:1053` vs `:1074`
- **Issue:** A missing image leaves the run dir without its prior grading output.
- **Fix:** Check docker before `fresh_dir`.
- **Reference:** CWE-696 Incorrect Behavior Order — https://cwe.mitre.org/data/definitions/696.html

### [LOW-006] VS-1 derives its expectations from the tree the validator reads
- **Severity:** LOW (confidence: medium)
- **File:** `head/evals/tests/validate-suite.bats:32-44`
- **Issue:** `n` and `short` are computed from the same `tasks/` and `smoke/` the validator counts, so a validator that miscounts the same way passes.
- **Fix:** Keep a fixed-expectation case on a synthetic suite (VS-2 covers part).
- **Reference:** CWE-1076 Insufficient Adherence to Expected Conventions — https://cwe.mitre.org/data/definitions/1076.html

### [LOW-007] `/usr/bin/python3` hardcoded in the image stand-in
- **Severity:** LOW (confidence: high)
- **File:** `head/evals/tests/ablation-grade.bats:46`
- **Fix:** `command -v python3`.
- **Reference:** CWE-1052 — https://cwe.mitre.org/data/definitions/1052.html

### [LOW-008] `review_catch.manifest` and `review_catch.fixture` are the only task.yaml paths not passed through `safe_rel`
- **Severity:** LOW (confidence: high; the input is trusted and frozen)
- **File:** `head/evals/harness/ablation-grade.sh:407-408`, `:434-439`
- **Issue:** "`os.path.join(REPO_ROOT, rc["manifest"])`" returns the value unchanged when it is absolute, so an absolute or `..` value resolves anywhere on disk; every other path field is gated.
- **Fix:** `safe_rel` both fields for consistency with the rest of `load_task`.
- **Reference:** CWE-22 — https://cwe.mitre.org/data/definitions/22.html

### [LOW-009] `secrets_clean` reports "a secret pattern" when the scanner itself is missing or broken
- **Severity:** LOW (confidence: high)
- **File:** `head/evals/harness/lib/seed_tasks.py:502-506`
- **Issue:** "`p = subprocess.run(["bash", no_secrets, tdir], …); return p.returncode == 0`" — a missing `no-secrets.sh` (rc 127) or a scanner crash is reported as a secret refusal. Fail-closed, which is right, but the message misleads the operator.
- **Fix:** Distinguish rc 1 (hit) from other codes and surface the scanner's stderr.
- **Reference:** CWE-392 Missing Report of Error Condition — https://cwe.mitre.org/data/definitions/392.html

### [LOW-010] Host-mode contamination roots whitelist the caller's credential stores
- **Severity:** LOW (confidence: medium)
- **File:** `head/evals/harness/ablation-grade.sh:952`
- **Issue:** "`roots |= {os.path.join(home, x) for x in (".claude", ".claude.json", ".codex", ".aws")}`" — an agent `Read` of `~/.aws/credentials` or `~/.claude.json` is never `outside_path`, so the only grade-time signal that the agent touched operator credentials is dropped. The scan's purpose is leakage, so this is a scope note rather than a defect in the leakage logic. Raised by the dissent (DISS-C-006).
- **Fix:** Keep the whitelist for `outside_path` but add a separately reported `credential_access` pattern, or narrow the whitelist to the files the agent CLI needs.
- **Reference:** CWE-778 Insufficient Logging — https://cwe.mitre.org/data/definitions/778.html

---

## Verified clean

- `head/evals/fixtures/review-prs/SHA256SUMS` matches both regenerated manifests (recomputed here); the removed rows are all `fix`-source regions under `dist/`, `.checksum`, `.d.ts.map`, `.build-manifest.json`; defect labels untouched.
- `head/evals/harness/seed-corpus-from-record.sh:202-213`, `:235-236`, `:709-713` — the exclusion fires only on `fix` rows and fix hunks, prints each path once; SC-7/SC-8 cover both paths.
- `head/evals/harness/validate-suite.sh:218-224` — churn schema rejects bools, negatives, missing keys and non-mappings; VS-11 covers each.
- `head/evals/harness/lib/seed_tasks.py` — argv-only git with a scrubbed environment (`:43-55`), `safe_path` on every history path (`:57-60`, `:138-144`), symlink blobs refused (`:152-153`), build-in-staging then `shutil.move` after proof and the secret scan (`:604`), `sanitise` strips paths, file names, test names and the word `hidden` from agent-facing text (`:251-262`).
- `head/evals/harness/ablation-grade.sh` — `safe_rel` on fixture, overlay src/dest, grader_protected, structural_check, reference_patch (`:319-391`); `is_within(t.fixture, t.dir)` (`:343`); `git_env` isolates config (`:677-679`); bundle names and commit ids validated (`:685-691`); `grade.json` holds ids only; `docker-stub.sh` PATH injection only when no `-e PATH` was given (`:76-79`).
- All shell files pass `bash -n`; the grader heredoc and `seed_tasks.py` compile.

## Documentation audit

No `grimoires/loa/a2a/subagent-reports/documentation-coherence-*.md` exists in this workspace (the frozen PR is the entire input), so coherence was verified manually: the three new script headers describe their inputs, outputs, exit codes and trust boundaries; `seed-corpus-from-record.sh` and `validate-suite.sh` headers were updated with the new rule and schema; `docker-stub.sh`'s header documents `DOCKER_STUB_PATH`. Gaps: the grader header does not state the Python floor (HIGH-005), the host-mode threat (HIGH-003), or that hidden-run output is trusted (HIGH-001); no CHANGELOG entry is in the diff. No secrets or internal URLs in docs or comments.

## Rubric scores

| Dimension | Score | Basis |
|-----------|-------|-------|
| SEC-IV Input validation | 3 | `safe_rel`/`safe_path` everywhere on operator input; agent output and agent-named paths trusted (HIGH-001, MED-003) |
| SEC-AZ Authorization | 3 | uid/gid, read-only root, no network in the container; host mode unconfined (HIGH-003) |
| SEC-CI Confidentiality/Integrity | 2 | grade forgeable by the graded party (HIGH-001); symlink chmod escapes the write contract (HIGH-002) |
| SEC-IN Injection | 5 | no shell, argv everywhere, git config isolated |
| SEC-AV Availability | 2 | no pids/memory limits, orphaned container, `/dev/zero` read (MED-002, MED-003) |
| ARCH-CX Complexity | 2 | 1,100-line heredoc, two ~100-line functions (MED-006) |
| CQ Testability | 2 | suite tied to one host (HIGH-008), fixtures not in the producer's shape (HIGH-006) |

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added
- [ ] Input validation on all new entry points (agent output and agent-named paths are trusted — HIGH-001, MED-003)
- [ ] Untrusted code confined (host mode — HIGH-003; container limits — MED-002)
- [x] No SQL/XSS/shell injection vulnerabilities
- [ ] Error handling doesn't mask failures (HIGH-005 opaque exit 2; LOW-009)
- [ ] Tests cover security paths (no test for symlinks, conftest hijack, rc≠0, real envelope shape)

---

## Adversarial dissent (Phase 1C)

`adversarial-review.sh --type audit --sprint-id sprint-1 --diff-file pr/head.diff --json` → `status: reviewed`, primary gpt-5.5-pro, companion claude-headless `succeeded`, `counted_as: independent_voice`, `degraded: false`, no `locality.degraded_security_review`. Eight findings: DISS-001 and DISS-C-001 (HIGH, forged grade via stdout/conftest) are confirmed by reproduction and tallied as HIGH-001 (with HIGH-007 for the exit-status half); DISS-C-002 (HIGH, host executor) is tallied as HIGH-003; DISS-002, DISS-C-003 and DISS-C-005 (container deadline, limits, capabilities) are confirmed by reading and tallied together as MED-002 at MEDIUM rather than the dissent's HIGH, for the reason stated there; DISS-C-004 (agent-named paths opened by the parser) is confirmed by reproduction and tallied as MED-003; DISS-C-006 (credential whitelist) is tallied as LOW-010. No advisory voices. Nothing was dismissed.

## Rejected dissent payloads

- None: `metadata.rejected_summary` is empty and the sidecar `adversarial-rejected-audit.jsonl` holds 0 rows.

## Review demotions

The review trailer carries `excluded: 0`; there is nothing to confirm. `excluded_confirmed: 0`.

---

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 8 |
| Medium | 7 |
| Low | 10 |

---

## Next Steps

**CHANGES_REQUIRED:**
1. Fix HIGH-001 and HIGH-002 first: they are the two places where the graded agent reaches past the grading tree or into the grade itself.
2. Fix HIGH-003 through HIGH-008 before re-audit; HIGH-004/005/006/007 are each a few lines plus a test that fails on the current code.
3. Re-run `/review-sprint sprint-1` then `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":8,"medium":7,"low":10},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-22T00:42:00Z"} -->
