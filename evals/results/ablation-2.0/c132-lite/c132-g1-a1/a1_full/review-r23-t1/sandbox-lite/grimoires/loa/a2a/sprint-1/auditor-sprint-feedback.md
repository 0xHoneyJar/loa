# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md (task review-r23)
**Scope:** the pull request in `pr/` — `pr/head.diff`, 16 files under `evals/` (the cycle-130 ablation grader `ablation-grade.sh`, the bug-fix and refactor seeders over `lib/seed_tasks.py`, the generated-path exclusion in `seed-corpus-from-record.sh`, the `source.churn` schema in `validate-suite.sh`, regenerated pr-14/pr-15 manifests and SHA256SUMS, and the bats suites). Citations are `head/<path>:<line>` with lines from `pr/head/`.
**Methodology:** Systematic 5-category review (Security, Architecture, Code Quality, DevOps; Blockchain not applicable), with proof-of-concept execution of the grader's parsing functions and an independent two-voice security dissent (`adversarial-audit.json`).
**Review gate state:** `engineer-feedback.md` is CHANGES_REQUIRED (7 high). The orchestration asked for the audit regardless; the Phase 0 "All good" prerequisite is therefore not met and this audit does not open the `COMPLETED` marker. The review's demotions are confirmed below (`excluded` 0 → `excluded_confirmed` 0).

---

## Executive Summary

The change is careful at the boundaries it names: every path from `task.yaml`, `hidden/manifest.json` and git history passes `safe_rel`/`safe_path`, every subprocess is an argument vector, snapshots are extracted through `tarfile.data_filter`, the container runs with `--network none --read-only` under the caller's uid, and `grade.json` carries ids only. SHA256SUMS matches the head manifests byte for byte, and the 41 fix rows removed from pr-14/pr-15 are exactly the generated paths the new rule names (defects untouched).

The grader's oracle, however, trusts the one input the graded agent controls completely: the stdout of a process that imports the agent's `conftest.py` and the module under test. A forged `N passed in 0.01s` line satisfies `all_pass` (reproduced: `passed 7 ≥ total 7, bad {}` → `True`; the exit status is never consulted), and node ids printed on `ERROR` lines are opened as host paths (`os.path.join(tree, "/etc/hostname")` → `/etc/hostname`; `/dev/zero` would exhaust the grader's memory). In `--executor host` the same agent code runs unsandboxed as the grader's user *before* the grader reads the transcripts, snapshot index and bundles it later grades. Together with the seven high findings the review already established (and which this audit confirms independently — three of them by execution), this is ten high findings. No critical finding: nothing here is reachable by an outside attacker; the threat actor is the evaluated agent, and the damage is to the integrity of the ablation's measurements and to the operator's host in host mode.

**Overall Risk Level:** HIGH

**Key Statistics:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 10 |
| Medium | 10 |
| Low | 7 |

---

## Category Scores (Rubric-Based Assessment)

**Scoring Method:** Each dimension scored 1-5 per `resources/RUBRICS.md`

| Category | Score | Dimensions |
|----------|-------|------------|
| Security | 3.0/5 | IV:3 AZ:4 CI:2 IN:4 AV:2 |
| Architecture | 3.4/5 | MO:4 SC:3 RE:3 CX:3 ST:4 |
| Code Quality | 3.6/5 | RD:4 TC:3 EH:3 TS:3 DC:5 |
| DevOps | 3.2/5 | AU:3 OB:4 RC:3 AC:3 DS:3 |
| Blockchain | n/a | *(not applicable)* |
| **Overall** | **3.3/5** | *Security weighted ×2* |

**Risk Level Mapping:** 4.5-5.0: LOW | 3.5-4.4: MODERATE | 2.5-3.4: HIGH | 1.0-2.4: CRITICAL

**Machine-Parseable Output:** `grimoires/loa/a2a/audits/2026-10-21/findings.jsonl`

---

## Critical Issues (Fix Immediately)

None.

---

## High Priority Issues (Fix Before Production)

### [HIGH-001] The hidden-test oracle is the agent's own stdout: a forged summary line grades as all-pass

**Severity:** HIGH | **Confidence:** high
**Component:** `head/evals/harness/ablation-grade.sh:653` (also `:546-555`, `:588-594`, `:624-639`, `:486-498`)
**Criterion:** SEC-CI: Confidentiality/Integrity
**Reasoning Trace:**
> `run_suite` → `exec_in_tree` runs `test_command` in the grading tree; the tree is `copy_tree(sb, final, EXCLUDE_TOP)` (`:1076`) — the agent's sandbox. pytest loads `conftest.py` from `/workspace` (no `--noconftest`, no `-c /dev/null`; `-I -s` only isolate the interpreter) and imports the module under test. `parse_pytest` takes the last line matching `SUMMARY_RX` (`:549-553`) and `passed = norm.get("passed", 0)` (`:590`); `all_pass` is `passed >= total and not bad and not parse_error` (`:653`) — `rc` is never read. Reproduced with the shipped functions: input `"tests/test_hidden.py::test_a PASSED\n===== 7 passed in 0.01s ====="` → `{'passed': 7, 'total': 7, 'bad': set()}`, `all_pass` → `True` with the static floor 3. bats is the same: `setup_suite.bash` beside the hidden `.bats` is agent-authored and runs before the hidden cases.
**Description:** "the hidden total is never below the static case count" (`:85-86`) floors `total` but nothing floors `passed` against real outcomes. A `conftest.py` with `pytest_sessionstart` (or import-time code in the package under test) that prints a summary with `passed ≥ static_cases` and calls `os._exit(0)` — or just exits non-zero, which `all_pass` ignores — passes every hidden test. `grader_protected` (AG-2) protects only the files the task author lists; a new `conftest.py` in any directory, a `pytest.ini` `addopts = -p <plugin>` (unless listed), or the module under test itself are all open.
**Impact:** `hidden_tests`, `verdict_accuracy_per_gate` (which gate "read a passing tree") and `structural.suite_green_*` can be set by the agent; the FR-6 metrics the suite exists to compare are forgeable per arm. This is the same threat class the sprint's own AG-2 test ("a helper that fakes the fix") treats as in scope.
**Remediation:** Treat stdout as a hint, never the oracle. (1) Fail the run on non-zero `rc` and when the summary's `passed` exceeds the count of `PASSED` outcome lines (`-rA` is already requested); (2) run pytest with `-c /dev/null --noconftest -p no:cacheprovider` plus an explicit `--rootdir`, and bats with `--no-tempdir-cleanup`-free defaults and the hidden `setup_suite.bash` overlaid; (3) write results through a channel the in-process code does not own — e.g. a grader-owned `--junitxml` on a second read-only-to-the-agent mount, cross-checked against the hidden file's static case names; (4) document the residual: import-time code in the module under test can still forge anything in-process, so the review-time `grader_protected` list should include every conftest/ini path by default (the seeder's `helper_files` already finds them).
**References:** CWE-345 Insufficient Verification of Data Authenticity — https://cwe.mitre.org/data/definitions/345.html ; CWE-807 Reliance on Untrusted Inputs in a Security Decision — https://cwe.mitre.org/data/definitions/807.html . Confirmed by cross-model review (DISS-002, DISS-C-004).

### [HIGH-002] pytest node ids from the test output are opened as host paths (traversal, and `/dev/zero` kills the grader)

**Severity:** HIGH | **Confidence:** high
**Component:** `head/evals/harness/ablation-grade.sh:576` (also `:533-543`, `:574-581`, `:583-586`)
**Criterion:** SEC-IV: Input Validation
**Reasoning Trace:**
> `OUTCOME_RX` (`:530`) captures `(PASSED|FAILED|ERROR) (\S+)` from the test stdout. An `ERROR` node without `::` goes to `coll_err` and is read with `open(os.path.join(tree, f), …).read()` (`:576`); every node's path goes through `def_line`, which does the same (`:536`). `os.path.join` discards `tree` for an absolute `f`, and `..` is not rejected. Reproduced: `parse_pytest("ERROR /etc/hostname\n===== 1 error in 0.01s =====", "/run/grading/final")` opened `/etc/hostname` on this host without error.
**Description:** The test runs inside the container, but the parse runs on the host, so the agent chooses which host file the grader's user opens. `/dev/zero` (or `/proc/kcore`, a FIFO under `/tmp`) makes `.read()` run until `MemoryError`/forever — caught by the outer `except Exception` as "internal error", exit 2: the run is ungraded. A readable host file leaks only a `def test…` line position, so the disclosure is weak; the denial of grading is not.
**Impact:** Any agent can void its own grade (an ungraded run is dropped from an arm's sample) or stall the batch; the read primitive crosses the DEC-0413 boundary the header promises ("Reads ONLY …").
**Remediation:** Resolve node paths with `safe_rel` and `is_within(tree)` before opening; `os.path.isfile` and `not islink`; cap the read (e.g. 1 MiB) — or stop reading files at all and take the def order from the hidden copies under `t.overlay`, which the grader already trusts.
**References:** CWE-22 Improper Limitation of a Pathname to a Restricted Directory — https://cwe.mitre.org/data/definitions/22.html ; CWE-400 Uncontrolled Resource Consumption — https://cwe.mitre.org/data/definitions/400.html . Confirmed by cross-model review (DISS-001, DISS-C-003).

### [HIGH-003] `--executor host` runs agent code unsandboxed, before the grader reads the evidence it later grades

**Severity:** HIGH | **Confidence:** high
**Component:** `head/evals/harness/ablation-grade.sh:511` (also `:510-515`, `:1080`, `:1107-1119`, `:1141`)
**Criterion:** SEC-AZ / ARCH-RE: isolation
**Reasoning Trace:**
> Host mode builds `env -i PATH=… HOME=<scratch> … timeout 120 <argv>` with `cwd=tree` (`:511-515`): the environment is scrubbed, the filesystem and network are not. `grade()` runs `run_suite(final, …)` at `:1080`; `snapshots/index.json` and the bundles are read at `:1107-1119` and `transcripts/events-*.jsonl` at `:1141`, afterwards. All of them lie under `<run-dir>`, writable by the grader's user — which is the user the agent's `conftest.py` now runs as.
**Description:** In host mode the test process (agent-authored tests, conftest, module under test) can rewrite the transcripts (erasing `hidden`/`outside_path` hits), replace `IMPLEMENT.bundle`/`index.json` so a fixed tree is graded for the REVIEW gate, read the operator's `~/.aws`, `~/.claude.json` and SSH keys, or install persistence. The header documents host mode as a working alternative (the Sprint 258 smoke used it) and AG-18 exercises it, with no warning that it removes the trust boundary the rest of the script is built on. DEC-0491 chose the container; host mode is one flag away.
**Impact:** Complete loss of grading integrity for the run and of host confidentiality for the operator, in a mode the test suite itself uses.
**Remediation:** Read every harness artefact (transcripts, index, bundles, envelopes) into memory *before* any test command runs; make host mode refuse unless `LOA_GRADE_UNSAFE_HOST=1` is set and print a banner; prefer a user namespace / `bwrap --unshare-all --ro-bind` wrapper when docker is unavailable.
**References:** CWE-653 Improper Isolation or Compartmentalization — https://cwe.mitre.org/data/definitions/653.html ; CWE-367 Time-of-check Time-of-use — https://cwe.mitre.org/data/definitions/367.html . Confirmed by cross-model review (DISS-C-001).

### [HIGH-004] Seeder: a failed proof leaves its staging directory, so every later candidate fails with `File exists`

**Severity:** HIGH | **Confidence:** high
**Component:** `head/evals/harness/lib/seed_tasks.py:601` (also `:373`, `:450`, `:588-602`, `:617`)
**Criterion:** CQ-EH: Error Handling
**Description:** `build_bugfix`/`build_refactor` create `stage/<tid>/fixture` with `os.makedirs(fx)` (`:373`, `:450`). On `proof-failed`, `skip` or `secret` the loop does `taken.discard(tid)` (`:591`, `:596`, `:601`) and `continue`; `stage/<tid>` is removed only at the end (`:617`). `next_id` (`:332-339`) consults `taken` and `tasks_dir`, not `stage`, so the next candidate receives the same id and `makedirs` raises `FileExistsError`, reported as another proof failure. The review reproduced `written 0` for two candidates in both modes; confirmed here by reading the control flow.
**Impact:** One bad fix commit at the top of the window (newest first) yields no tasks at all while exit code 1 says "a candidate failed its proof".
**Remediation:** `shutil.rmtree(os.path.join(stage, tid), ignore_errors=True)` on every non-success path before `taken.discard`, or stage each candidate in its own `mkdtemp`; add a two-candidate bats case where the newest fails.
**References:** CWE-459 Incomplete Cleanup — https://cwe.mitre.org/data/definitions/459.html

### [HIGH-005] Seeder: the `git apply` fallback can apply nothing and still return success, making the refactor proof vacuous

**Severity:** HIGH | **Confidence:** medium
**Component:** `head/evals/harness/lib/seed_tasks.py:229` (also `:225-230`, `:473-481`; wrappers `head/evals/harness/seed-bugfix-tasks.sh:75`, `head/evals/harness/seed-refactor-tasks.sh:64`)
**Criterion:** CQ-EH: Error Handling
**Description:** Without `patch` on PATH the fallback is `git apply -p1 <patch>` with `cwd=tree`. When the scratch tree lies inside another work tree (any `TMPDIR` under a checkout), git applies relative to that repository, prints "Skipped patch" for every file and exits 0; `apply_patch` returns `True` with the tree unchanged. The refactor proof is "green at base AND green at reference" (`:478-481`), trivially true on an unpatched tree, so a behaviour-breaking commit becomes a task (the review reproduced SR-3's `perf: skip the padding` becoming `refactor-01` PASS). The wrappers require only `git` and `python3`.
**Impact:** A task whose reference patch was never shown to apply enters the suite; `--self-check reference` would catch it only if run before the freeze.
**Remediation:** Require `patch` in both wrappers, or run `git apply` with `GIT_CEILING_DIRECTORIES` / `--directory` and treat "Skipped patch" or an unchanged tree as failure; assert at least one fixture file changed.
**References:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html

### [HIGH-006] Grader tests hard-code one developer's dotfiles path as the bats binary

**Severity:** HIGH | **Confidence:** high
**Component:** `head/evals/tests/ablation-grade.bats:16` (also `:48`)
**Criterion:** DO-AU: Automation
**Description:** `BATS_BIN="$HOME/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats"` and `ln -s "$BATS_BIN" "$T/bin/bats"` put a dangling symlink first on the stub container's PATH on every other machine; AG-2 (bf-sh) and AG-7 (bats TAP) then hit rc 127 and the `parse_error` branch. The header (`:11`) promises "`bats` is the operator's bats-core".
**Impact:** The grader's own test suite cannot pass on CI or any reviewer's machine; the leaked path also names a personal directory layout in a tracked file.
**Remediation:** `BATS_BIN="$(command -v bats)"` with `skip` when absent.
**References:** CWE-1052 Excessive Use of Hard-Coded Literals in Initialization — https://cwe.mitre.org/data/definitions/1052.html

### [HIGH-007] Seeder: refactor tasks leave the covering tests — the "suite stays green" oracle — editable by the agent

**Severity:** HIGH | **Confidence:** medium
**Component:** `head/evals/harness/lib/seed_tasks.py:457` (also `:455-456`, `:464`; locked in by `head/evals/tests/seed-refactor.bats:92`)
**Criterion:** SEC-CI: Confidentiality/Integrity
**Description:** The covering tests are copied into the fixture (`:455-456`) but only conftest/helper files become `grader_protected` (`:457`), and `hidden/manifest.json` is written empty (`:464`). The grader restores `grader_protected` and the overlay (`prepare`, `:657-674`) and then runs `test_command` on the final tree for `suite_green_final` (`:1105`) — on tests the agent may have reduced to `assert True`, while TASK.md says "the existing suite must stay green without edits". The bugfix seeder overlays its tests from `hidden/`; the refactor seeder does neither.
**Impact:** Four of sixteen suite tasks carry a tamperable oracle; combined with HIGH-008 the refactor type has no agent-independent signal.
**Remediation:** List every covering test under `grader_protected` or overlay them from `hidden/tests/` like the bugfix seeder; update SR-1.
**References:** CWE-693 Protection Mechanism Failure — https://cwe.mitre.org/data/definitions/693.html

### [HIGH-008] Grader: refactor `verdict_accuracy` never consults the structural check

**Severity:** HIGH | **Confidence:** high
**Component:** `head/evals/harness/ablation-grade.sh:1129` (also `:1122`, `:1100-1101`, `:397`)
**Criterion:** ARCH-ST / CQ: correctness of the FR-6 metric
**Description:** Snapshot trees are graded with `run_suite(tree, t.test_command, t.static_cases)` only (`:1122`); `structural_command(t)` runs on `final` alone (`:1100-1101`), and `t.static_cases` excludes the structural file (`:397`). For a refactor the covering suite is green at base by the seeder's own proof, so an untouched IMPLEMENT snapshot is `all_pass`; a REVIEW saying CHANGES_REQUIRED (correct) scores `false`, APPROVED scores `true`.
**Impact:** `verdict_accuracy`/`verdict_accuracy_per_gate` is inverted for one of four task types and biased toward APPROVED across arms. Both dissent voices in the review flagged it.
**Remediation:** For refactor tasks grade each snapshot with both `test_command` and `structural_command(t)`; define gate accuracy as structural green and suite green; record `structural` per snapshot; update the header (`:107-109`).
**References:** CWE-682 Incorrect Calculation — https://cwe.mitre.org/data/definitions/682.html

### [HIGH-009] Grader: the contamination scan flags `"$VAR"/dir` idioms as `outside_path`

**Severity:** HIGH | **Confidence:** high
**Component:** `head/evals/harness/ablation-grade.sh:940` (also `:976-983`)
**Criterion:** SEC-IV: Input Validation (false positive in a grade field)
**Reasoning Trace:**
> `ABS_WORD`'s lookbehind set includes `'` and `"`, so the `/` after a closing quote starts a "path". Reproduced with the shipped regex and roots: `cd "$PWD"/tests && python3 -m pytest -q` → `outside_path`; `bats '$ROOT'/tests` → `outside_path`; `ls /workspace/x` → clean.
**Description:** `contaminated` is set on the first hit in phase order; a routine quoted-variable path prefix in agent shell marks the run contaminated. The arms differ in how much shell the agent writes, so the false-positive rate differs per arm.
**Impact:** Valid runs are discounted unequally across arms — the comparison the suite exists for is corrupted.
**Remediation:** Do not start a path after a quote that follows a non-space character (or tokenise with `shlex` and test whole words); add AG-11 cases for `"$PWD"/x`, `'$T'/x`, `$(cmd)/x`, `${X}/x`.
**References:** CWE-185 Incorrect Regular Expression — https://cwe.mitre.org/data/definitions/185.html

### [HIGH-010] Grader: the review-catch reducer ignores `anchor_line`, so live dissent findings earn no recall

**Severity:** HIGH | **Confidence:** high
**Component:** `head/evals/harness/ablation-grade.sh:865` (also `:862-867`)
**Criterion:** ARCH-ST: contract with `adversarial-review.sh`
**Reasoning Trace:**
> `envelope_texts` emits `f["anchor"]` and a `file|path` + `line|line_start|start_line` pair. The envelope the dissent wrote for *this* audit carries `anchor: "evals/harness/ablation-grade.sh:parse_pytest"` with `anchor_line: 576` — a symbolic anchor plus an integer the reducer never reads. `citations()` needs `:digits`, so such a finding yields nothing. AG-8 passes because it fabricates envelopes with numeric anchors and `file`+`line` keys the writer never emits.
**Impact:** DEC-0420's arm-neutral reduction credits none of the dissent's catches with live envelopes, under-counting recall precisely for the arms that run the adversarial gates.
**Remediation:** When `anchor_line` is an int, emit `<path-of-anchor>:<anchor_line>[-<anchor_line_end>]` (path = anchor up to its last `:`); keep the existing keys as fallbacks; make AG-8 use the writer's real shape.
**References:** CWE-684 Incorrect Provision of Specified Functionality — https://cwe.mitre.org/data/definitions/684.html

---

## Medium Priority Issues (Address in Next Sprint)

### [MED-001] Seeder: `--select` consumes slots for build-time skips and refusals, contrary to the headers

**Severity:** MEDIUM | **Confidence:** high
**Component:** `head/evals/harness/lib/seed_tasks.py:570` (also `:588-597`; headers `head/evals/harness/seed-bugfix-tasks.sh:43-44`, `head/evals/harness/seed-refactor-tasks.sh:37-38`)
**Description:** `selected = cands[:a.select]` is fixed before build; a candidate skipped (no covering test) or refused (secret) inside the loop is not replaced, while the headers promise "refusals and skips do not count".
**Impact:** `--select 4` silently yields fewer tasks with exit 0.
**Remediation:** Iterate over `cands` until `written + failed == select`, or fix the headers.

### [MED-002] Grader: the Python floor (≥ 3.11.4 for `tarfile.data_filter`, ≥ 3.11 for `-P`) is undeclared and unchecked

**Severity:** MEDIUM | **Confidence:** high
**Component:** `head/evals/harness/ablation-grade.sh:710` (also `:714`, `:492`)
**Description:** On this host's 3.11.2, `'data_filter' in dir(tarfile)` is `False`: every snapshot extraction raises and the grade exits 2 "internal error" with no hint; host mode's `python3 -P` is 3.11+.
**Impact:** The grader is unusable on common interpreters without explanation; the bats suite cannot run here.
**Remediation:** Check `hasattr(tarfile, "data_filter")` and `sys.version_info` in `main()` and `die` with the floor; state it in the header.
**References:** CWE-703 Improper Check or Handling of Exceptional Conditions — https://cwe.mitre.org/data/definitions/703.html

### [MED-003] Grader: regression detection drops the baseline when its output is unparseable

**Severity:** MEDIUM | **Confidence:** high
**Component:** `head/evals/harness/ablation-grade.sh:1091` (also `:1092-1095`)
**Description:** `base_ok = [...] if not rb["parse_error"] else []`; for a `bash`/`node` regression command that exits 0 at base and non-zero at final, the synthetic `#1` case never enters `base_ok`, so `newly_failing` stays empty despite the regression — the header (`:85-88`) defines the fallback the code does not implement.
**Remediation:** When the base run is `parse_error` with rc 0, treat its synthetic cases as passing.
**References:** CWE-682 — https://cwe.mitre.org/data/definitions/682.html

### [MED-004] Grader: the container watchdog cannot kill a TERM-ignoring test, and the container is not hardened

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `head/evals/harness/ablation-grade.sh:508` (also `:506-507`, `:517-518`)
**Description:** `timeout 120 <cmd>` without `-k`; the outer `subprocess.run(timeout=180)` kills only the `docker run` client, the unnamed `--rm` container keeps running with the grading tree mounted. No `--pids-limit`, `--memory`, `--cpus`, `--cap-drop ALL` or `--security-opt no-new-privileges` is set.
**Impact:** Agent test code that traps TERM leaks a container per run and burns host CPU; a fork bomb or allocation loop inside the test is bounded only by the host.
**Remediation:** `timeout -k 10 120`; `--name` derived from the run dir and `docker kill` on `TimeoutExpired`; add `--cap-drop ALL --security-opt no-new-privileges --pids-limit 512 --memory 1g`.
**References:** CWE-400 — https://cwe.mitre.org/data/definitions/400.html ; CWE-772 Missing Release of Resource — https://cwe.mitre.org/data/definitions/772.html . Confirmed by cross-model review (DISS-C-006).

### [MED-005] Grader: the hidden overlay on the base tree distorts regressions and the base self-check

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `head/evals/harness/ablation-grade.sh:1087` (also `:1086`, `:1219`)
**Description:** `prepare(t, base_tree)` writes the hidden tests into the base tree before `regression_command` runs; when the regression target covers the hidden dest (`pytest tests` with hidden under `tests/`), hidden cases are double-counted in `regressions.base/final` and `--self-check base` cannot pass because `suite_green` (`:1219`) sees them failing at base by design.
**Remediation:** Run `regression_command` on trees carrying only the `grader_protected` restore, or enforce in `validate-suite.sh` that regression targets do not overlap hidden dests.
**References:** CWE-682 — https://cwe.mitre.org/data/definitions/682.html

### [MED-006] Grader: TAP results keyed by description collapse duplicate test names

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `head/evals/harness/ablation-grade.sh:618` (also `:617-621`, `:642-644`)
**Description:** `names[n]` is the description; two bats tests with the same description (legal, common across files) share one key in `order`/`bad`, so `failed_names` and `newly_failing` lose entries and `t<k>` can point at the wrong position.
**Remediation:** Key TAP results by test number and map to `t<n>` directly.
**References:** CWE-694 Use of Multiple Resources with Duplicate Identifier — https://cwe.mitre.org/data/definitions/694.html

### [MED-007] Seeder: pytest counts are read from the last line of stdout+stderr

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `head/evals/harness/lib/seed_tasks.py:196` (also `:197-198`)
**Description:** `tail = output.strip().splitlines()[-1]` on `stdout + stderr`; any trailing stderr line (an interpreter warning) hides the summary and the proof reads `0 failed, 0 passed`, failing a good candidate.
**Remediation:** Scan lines in reverse for the summary regex as `ablation-grade.sh:549-553` does.
**References:** CWE-754 — https://cwe.mitre.org/data/definitions/754.html

### [MED-008] Grader: unbounded reads and super-linear regexes over agent-controlled files can stall or OOM the grader

**Severity:** MEDIUM | **Confidence:** high
**Component:** `head/evals/harness/ablation-grade.sh:821` (also `:795-798`, `:800`, `:728-734`, `:752`, `:769`, `:786`)
**Reasoning Trace:**
> `citations()` runs `CITE` over the whole of `sandbox/review.md` and both feedback files. The `[A-Za-z0-9_./+()-]+\.` prefix backtracks O(n) per start on a run of path characters without a dot: measured 0.19 s for 20 000 characters and 0.78 s for 40 000 (quadratic → a 1 MiB line is minutes, 10 MiB hours). `TRAILER` (`:800`, `re.S`) is O(k·n) over unterminated verdict-trailer openers (`<!-- … {` with no closing `-->`). `churn()` reads every sandbox file fully (`:732`) and diffs with `difflib` (`:752`, quadratic in lines); `gate_verdict` iterates lines of agent files with no size cap (`:769`).
**Description:** None of these inputs is size-limited, and they are all written by the graded agent.
**Impact:** A single run can stall the grading batch (no outer timeout wraps the grader) or exhaust memory; both void the grade.
**Remediation:** Cap each agent-file read (e.g. 2 MiB; beyond that record `parse_error`/skip churn for that file), bound `CITE` to lines (`re.M` and a per-line scan), and run `churn` only on files below a size threshold.
**References:** CWE-1333 Inefficient Regular Expression Complexity — https://cwe.mitre.org/data/definitions/1333.html ; CWE-400 — https://cwe.mitre.org/data/definitions/400.html . Confirmed in part by cross-model review (DISS-C-007, DISS-C-002).

### [MED-009] Grader: the host-mode contamination allowlist whitelists the operator's `~/.aws` and `~/.codex`

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `head/evals/harness/ablation-grade.sh:953` (also `:950-954`, header `:120-122`)
**Description:** `allowed_roots` adds `~/.claude`, `~/.claude.json`, `~/.codex` and `~/.aws` to the roots a tool_use path may touch without `outside_path`. The transcripts record the *agent's* tool inputs, not the CLI's own file access; an agent `Read` of `~/.aws/credentials` is exactly the leakage the scan exists to flag. AG-11 asserts only the `~/.claude` case; `.aws`/`.codex` are untested and unexplained.
**Impact:** The most sensitive directories on the operator's host are exempt from the leakage signal in host mode; the scan already admits it is a lower bound, but this is a deliberate hole.
**Remediation:** Drop `.aws` and `.codex` from the allowlist (keep `~/.claude*` if the agent CLI legitimately writes there) and add a negative AG-11 case.
**References:** CWE-183 Permissive List of Allowed Inputs — https://cwe.mitre.org/data/definitions/183.html

### [MED-010] Process: the implementation report does not describe this diff

**Severity:** MEDIUM | **Confidence:** high
**Component:** `pr/PR.md:1` (carried as `grimoires/loa/a2a/sprint-1/reviewer.md`)
**Description:** The report names sixteen tasks under `grimoires/loa/evals/ablation-2.0/tasks/`, a freeze (`MANIFEST.sha256`) and `bd-8o5rx` closing evidence; the diff contains none of the tasks or the freeze and has no `## AC Verification` section. AG-14, AG-16, AG-18 and VS-1 depend on artefacts outside the diff (`freeze.sh`, the smoke tasks, `recall-vs-defects.sh`, `no-secrets.sh`), none of which could be verified here.
**Impact:** Documentation audit cannot confirm task-level coherence; reviewers cannot tell which claims the PR actually delivers.
**Remediation:** Split the description or include the artefacts; add an AC Verification table with `file:line` evidence.

---

## Low Priority Issues (Technical Debt)

### [LOW-001] Grader self-check: `patch` is a hard dependency with no tool check
**Severity:** LOW | **Confidence:** high
**Component:** `head/evals/harness/ablation-grade.sh:1175`
**Description:** `subprocess.run(["patch", …])` raises `FileNotFoundError` on a host without `patch`, surfaced as "internal error" exit 2 with no hint; inconsistent with the seeder's fallback.
**Remediation:** `shutil.which("patch")` in `main()` for `--self-check reference`, `die` with a clear message.

### [LOW-002] Grader: verdict readers follow symlinks and check only the leaf
**Severity:** LOW | **Confidence:** medium
**Component:** `head/evals/harness/ablation-grade.sh:766` (also `:783`, `:877`)
**Description:** `gate_verdict`/`review_md_verdict` use `isfile` only (reproduced: a symlink to a trailer file returns `APPROVED`); `combined_findings` refuses a symlinked leaf but not a symlinked `grimoires/`, `loa/`, `a2a/` or `sprint-1/` parent. Only a verdict word or citations are extracted, so disclosure is minimal. The dissent's `/dev/zero`/FIFO scenario here is refuted: `os.path.isfile` is false for devices and FIFOs.
**Remediation:** `os.path.realpath(p)` must stay within `sandbox/`; add `not islink` for symmetry with DEC-0413.
**References:** CWE-59 Improper Link Resolution Before File Access — https://cwe.mitre.org/data/definitions/59.html

### [LOW-003] Seeder tests assume properties of the temp directory and host
**Severity:** LOW | **Confidence:** high
**Component:** `head/evals/tests/seed-bugfix.bats:183` (also `head/evals/tests/seed-refactor.bats:97`)
**Description:** `--repo "$T"` is expected to be "not a git repository", which fails when `BATS_TEST_TMPDIR` lies inside a checkout (it does here); SR-1 calls `patch` without a `skip` guard.
**Remediation:** Use a directory with `.git` removed after `git init`; `command -v patch || skip`.

### [LOW-004] SIMPLICITY[shrink]: the citation parser is duplicated from `recall-vs-defects.sh`
**Severity:** LOW | **Confidence:** high
**Component:** `head/evals/harness/ablation-grade.sh:794` (also `:795-801`)
**Description:** `CITE`, `ONE`, `TRAILER`, `URL` re-implement the "1.1.2 parser"; the two can drift silently.
**Remediation:** Share the parser from one place.
**References:** CWE-1041 Use of Redundant Code — https://cwe.mitre.org/data/definitions/1041.html

### [LOW-005] Grader: `remove_path` chmods through symlinks the agent planted
**Severity:** LOW | **Confidence:** high
**Component:** `head/evals/harness/ablation-grade.sh:242` (also `:239-244`, `:1039-1042`, `:1295`)
**Reasoning Trace:**
> `os.walk(p)` (followlinks=False) still lists a symlink-to-directory in `dirs`; `os.chmod` follows it. Verified: a planted `tree/planted -> target` left `target` at mode 0700 after the walk. Triggered on re-grade (`fresh_dir(grading)`), on `put_file` replacing an agent directory, and on the `SCRATCH` cleanup.
**Description:** A symlink in the sandbox (copied verbatim into `grading/final`) pointing at any directory the grader's user owns — the suite root, a shared results dir, `~/.claude` — gets mode 0700.
**Remediation:** Skip `os.path.islink(...)` entries before `chmod`.
**References:** CWE-59 — https://cwe.mitre.org/data/definitions/59.html . Cross-model review (DISS-C-005).

### [LOW-006] Grader: gate verdicts are read from sandbox files the implementer can edit in FIX phases
**Severity:** LOW | **Confidence:** low
**Component:** `head/evals/harness/ablation-grade.sh:1055` (also `:1054-1056`)
**Description:** The header calls the sandbox copies of the dissent envelopes tamperable and reads the `eval/` copies instead, but `v_review`/`v_audit` — which select `verdict`, `verdict_accuracy` and which snapshot is graded — come from `sandbox/grimoires/loa/a2a/sprint-1/*.md`, writable by the implementer in FIX1/FIX2. Whether `pipeline-run.sh` keeps authoritative copies under `eval/` could not be verified from this diff.
**Remediation:** Have the harness copy the feedback files under `eval/` after each gate and read those.
**References:** CWE-345 — https://cwe.mitre.org/data/definitions/345.html . Cross-model review (DISS-C-008).

### [LOW-007] Seeder: git inherits the operator's global config; a missing `no-secrets.sh` is reported as a secret hit
**Severity:** LOW | **Confidence:** medium
**Component:** `head/evals/harness/lib/seed_tasks.py:52` (also `:51-54`, `:505-506`)
**Description:** `_git_env` passes `HOME` with `GIT_CONFIG_NOSYSTEM` but not `GIT_CONFIG_GLOBAL=/dev/null` (the grader does, `:679`), so `~/.gitconfig` (`diff.context`, `diff.algorithm`, `core.attributesFile`) shapes `reference.patch`. `secrets_clean` treats any non-zero exit of `bash <no-secrets>` — including a missing script, rc 127 — as "a secret pattern in the materialised task": fail-closed, but every candidate is refused with a misleading reason.
**Remediation:** Set `GIT_CONFIG_GLOBAL=/dev/null`; check the scanner exists in the wrappers and distinguish rc 1 (hit) from other failures.

---

## Observations

No speculative critical/high findings were excluded (`excluded` 0). Items noted but not counted:

- `run_tests` in the seeder executes the repository's historical test commands on the host (`head/evals/harness/lib/seed_tasks.py:201-222`). The repository is the operator's own and the wrapper headers say so; an operator pointing `--repo` at a foreign repository runs its tests unsandboxed. Informational.
- `evals/graders/no-secrets.sh`, `evals/harness/freeze.sh`, `evals/graders/recall-vs-defects.sh` and the smoke tasks are called by this change but are not in the PR: **unable to assess**.
- The bats suites were not executed here (Python 3.11.2 lacks `tarfile.data_filter`, `patch` absent, `/tmp` noexec); grader behaviour was verified by executing its parsing functions in isolation.

---

## Rejected dissent payloads

None. `metadata.rejected_summary` is empty and `adversarial-rejected-audit.jsonl` beside the envelope has no rows.

## Cross-Model Security Observations

Two voices answered (`gpt-5.5-pro` via `codex-headless`, companion `claude-headless`; consensus, 2/2 succeeded, `degraded: false`, no `DEGRADED_SECURITY_REVIEW`). Triage of the ten findings:

- DISS-001 (HIGH, host file read from `ERROR <path>`), DISS-C-003 (MEDIUM, same) → confirmed by execution; counted as HIGH-002.
- DISS-002 (HIGH, parseable summary accepted regardless of exit status), DISS-C-004 (MEDIUM, forged summary via conftest) → confirmed by execution; counted as HIGH-001.
- DISS-C-001 (HIGH, host executor runs agent code before transcripts/bundles are read) → confirmed by reading `grade()` order; counted as HIGH-003.
- DISS-C-002 (MEDIUM, symlinked verdict files; `/dev/zero`/FIFO) → symlink part confirmed (LOW-002); the device/FIFO part is refuted by `os.path.isfile`; the unbounded-read part folded into MED-008.
- DISS-C-005 (LOW, chmod through planted symlinks) → verified; LOW-005.
- DISS-C-006 (LOW, no `-k`, no container hardening) → folded into MED-004.
- DISS-C-007 (LOW, churn/TRAILER unbounded) → folded into MED-008 with the measured `CITE` cost.
- DISS-C-008 (LOW, gate verdicts from agent-editable sandbox files) → LOW-006, confidence low (harness behaviour outside the diff).

The dissent's `verdict_quality.status` is `APPROVED`; it is advisory and its three high findings are tallied above, so it does not change the verdict.

---

## Documentation Audit

No `grimoires/loa/a2a/subagent-reports/documentation-coherence-*.md` reports exist for this sprint; coherence was verified manually. Every script carries a header contract and the code matches it in the clauses checked, with these exceptions: the regression-fallback clause (`ablation-grade.sh:85-88`) is not implemented (MED-003); the `--select` clause of both seeder headers is contradicted by the code (MED-001); the bats header's "operator's bats-core" is contradicted by `:16` (HIGH-006). Security-critical code is commented (trust boundary, DEC references). No secrets or credentials in the diff (one personal filesystem path, HIGH-006). The implementation report does not match the diff (MED-010).

---

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 10 |
| Medium | 10 |
| Low | 7 |

Review demotions: the review trailer lists `excluded: 0`; confirmed, `excluded_confirmed: 0`.

---

## Security Checklist Status

- [x] No hardcoded secrets or credentials (a personal path, HIGH-006)
- [x] Input validation at trust boundaries for task.yaml, manifests and git history (`safe_rel`, `safe_path`, `tarfile.data_filter`)
- [ ] Input validation for the graded agent's outputs (HIGH-001, HIGH-002, MED-008)
- [ ] Oracle integrity against the graded agent (HIGH-001, HIGH-007, HIGH-008)
- [ ] Isolation of untrusted code in every executor mode (HIGH-003, MED-004)
- [x] No shell interpolation of untrusted strings; no `source`/`eval` from variables (AG-13 self-greps hold)
- [x] Dependencies: stdlib only; `yq`, `git`, `docker`, `patch` external (undeclared floors: MED-002, LOW-001)
- [x] `grade.json` carries ids only; `meta/` never read

---

## Verdict

**CHANGES_REQUIRED** — ten high findings (three reproduced by execution in this audit, two more reproduced by the review, the rest confirmed by reading). Fix HIGH-001 through HIGH-010, re-run the seeder and grader bats suites on a machine without the author's dotfiles and with Python ≥ 3.11.4, then request `/review-sprint sprint-1` again before the next audit.

---

*Generated by Paranoid Cypherpunk Auditor*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":10,"medium":10,"low":7},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T16:58:00Z"} -->
