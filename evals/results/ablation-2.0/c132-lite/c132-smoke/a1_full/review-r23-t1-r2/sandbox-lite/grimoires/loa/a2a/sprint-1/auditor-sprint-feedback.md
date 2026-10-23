# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)
**Scope:** `pr/head.diff` (16 files): `evals/harness/ablation-grade.sh`, `evals/harness/lib/seed_tasks.py`, `seed-bugfix-tasks.sh`, `seed-refactor-tasks.sh`, `validate-suite.sh`, `seed-corpus-from-record.sh`, the `pr-14`/`pr-15` manifests and `SHA256SUMS`, `evals/tests/fixtures/docker-stub.sh`, and six bats suites. Citations are `head/<path>:<line>` with lines from `pr/head/`.
**Methodology:** Systematic 5-category review (Security, Architecture, Code Quality, DevOps; Blockchain not applicable), recon of sources and sinks, forward/backward tracing of agent-controlled data, two-voice security dissent on the diff only.

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

The change adds the cycle-130 ablation grader (bash-wrapped Python, 1,299 lines), two task seeders over a shared library, a `source.churn` schema, the bd-8o5rx generated-path exclusion, and bats suites. The grader's documented trust model is sound in intent: the sandbox is treated as tamperable, `meta/` is never read, manifest paths go through `safe_rel`, snapshots are extracted via a scratch bare repository, and summaries carry ids only. The seeders stage privately and prove red/green before publishing. The regenerated manifests are byte-exact against `SHA256SUMS`, and every removed `fix_regions` row is a generated path while the defect lists are untouched (verified by diffing the base and head JSON).

The audit cannot approve the sprint. The grader's trust boundary is breached at three points by data the graded agent controls: the pytest output parser opens any path a test line names and reads it without bound (reproduced: a FIFO or `/dev/zero` stalls the grader indefinitely); the hidden-test result itself is derived from the stdout of a process whose configuration and imported modules the agent controls (reproduced: one printed summary line yields a perfect 7/7 grade with zero real outcomes); and the cleanup routine chmods through agent-planted symlinks onto host directories (reproduced: 755 to 700). Host-executor mode additionally runs the sandbox's code as the operator with no guard. On top of these, the four blocking portability and correctness defects from the review stand unchanged: the Python 3.12-only tar filter, the seeder's poisoned staging directory, the silently-skipping `git apply` fallback, and the personal `bats` path in the grader's test suite. The seeder also drops executable bits from every fixture file it writes, which makes shell-tool tasks, the dominant case for this repository, unseedable.

Prerequisite note: the review gate ended in CHANGES_REQUIRED, not "All good". The audit ran on the orchestrator's instruction to produce a verdict regardless; this is recorded here so the golden path does not read the audit as a post-approval gate.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 7 |
| Medium | 11 |
| Low | 16 |

**Overall Risk Level:** HIGH

---

## Category Scores (Rubric-Based Assessment)

| Category | Score | Dimensions |
|----------|-------|------------|
| Security | 3.0/5 | IV:2 AZ:3 CI:4 IN:4 AV:2 |
| Architecture | 2.8/5 | MO:3 SC:3 RE:2 CX:3 ST:3 |
| Code Quality | 3.4/5 | RD:4 TC:3 EH:3 TS:3 DC:4 |
| DevOps | 2.8/5 | AU:3 OB:3 RC:3 AC:2 DS:3 |
| Blockchain | n/a | not applicable (weight redistributed) |
| **Overall** | **3.0/5** | *weighted: Security 33%, others 22% each* |

Scoring notes: IV 2 because agent-emitted text reaches `open()` and agent-written config reaches the result process; AV 2 because a single sandbox artefact (FIFO, mode-000 file, multi-GB file) aborts or stalls the grade; AC 2 because host mode runs untrusted code as the operator; RE 2 because docker client failures and parser gaps become plausible grades rather than tool errors.

---

## Scope limits

- The bats suites could not be executed: the repository tree they run against (`evals/harness/freeze.sh`, `pipeline-run.sh`, `ablation-row.sh`, `evals/graders/recall-vs-defects.sh`, `no-secrets.sh`, the stub fixtures and the smoke tasks) is not in this workspace. The grader and the seeder library were exercised directly with throwaway fixtures; every reproduction below was run on this host (Python 3.11.2, no GNU `patch`, `TMPDIR=/workspace/.eval/tmp`, bats at `/usr/local/bin/bats`, `yq` present).
- `grimoires/loa/known-failures.md` is absent (hook warning at session start); triaged without it.
- No `.reviewignore` exists; the whole diff was in scope. `.claude/`, `grimoires/`, `.beads/` and `.run/` were not audited.
- Trust assumptions used throughout: `<run-dir>/sandbox/` and everything the agent's test process prints are UNTRUSTED (the header says so at `head/evals/harness/ablation-grade.sh:35-42`); the task directory, `index.json`, `transcripts/` and `eval/` are harness-written and trusted; the seeders read the repository's own history, which is semi-trusted.

---

## Security Dissenter Analysis (Phase 1C)

`adversarial-review.sh --type audit --sprint-id sprint-1 --diff-file pr/head.diff --json` completed: two voices (codex-headless for the gpt-5.5-pro chain, claude-headless as companion), `companion_voice.status: succeeded`, `counted_as: independent_voice`, `verdict_quality.consensus_outcome: consensus`, `degraded: false`, no `locality.degraded_security_review` marker. Not a DEGRADED_SECURITY_REVIEW. Eight findings (2 HIGH, 4 MEDIUM, 2 LOW), all verified below: the two HIGH are tallied as findings of this audit (HIGH-006, HIGH-007); DISS-C-003 duplicates HIGH-005 and DISS-001/DISS-C-004 (both voices, the same defect) become MED-002; DISS-C-005 becomes MED-003; DISS-C-006 and DISS-C-007 are LOW-004 and LOW-005. Envelope: `grimoires/loa/a2a/sprint-1/adversarial-audit.json`.

---

## High Priority Security Issues (Fix Before Deployment)

Provenance tags: *(new)* found by this audit; *(review, confirmed)* raised by the review and independently verified here; *(dissent, verified)* raised by the security dissenter and verified here.

### [HIGH-001] The grader depends on a Python 3.12 tar API with no version guard *(review, confirmed)*

**Severity:** HIGH | **Confidence:** high
**File:** `head/evals/harness/ablation-grade.sh:710-714`
**Issue:** `extract_snapshot` calls `tarfile.data_filter(member, path)` (line 710) and `tf.extractall(tree, filter=keep)` (line 714). Neither exists before Python 3.12 (3.11.4+ backports them; Debian 12's 3.11.2 does not). Verified on this host: `python3 -c "import tarfile; 'data_filter' in dir(tarfile)"` prints `False` on 3.11.2. Any run with a REVIEW or AUDIT verdict reaches this path (`gates` non-empty at lines 1110-1113) and aborts through the generic handler at line 1290 with exit 2 and no `grade.json`; a run without snapshots grades fine, so the failure is silent until the first gated run. The grader runs the host's `python3` (line 166) and declares no minimum version anywhere.
**Fix:** check `sys.version_info >= (3, 12)` once at startup and raise `GradeError` naming the requirement, or extract member by member with `safe_rel` plus an explicit absolute/`..`/link-target check and no `filter=`. Document the minimum in the header; add a bats case grading a run with an `IMPLEMENT.bundle`.
**Reference:** CWE-1104 Use of Unmaintained/Incompatible Third-Party Components, https://cwe.mitre.org/data/definitions/1104.html

### [HIGH-002] A failed seeder candidate poisons every later candidate *(review, confirmed)*

**Severity:** HIGH | **Confidence:** high
**File:** `head/evals/harness/lib/seed_tasks.py:586-602` (allocation at `:373` and `:450`)
**Issue:** when `build_bugfix`/`build_refactor` returns `None`, `"skip"` or `"secret"`, the loop at lines 588-602 prints the reason and `taken.discard(tid)` releases the id, but the staged `stage/<tid>/` is never removed. The next candidate receives the same `tid` and `os.makedirs(fx)` at line 373 (450 for refactor) raises `FileExistsError` (errno 17, verified), which line 586 catches and reports as `proof-failed <sha>: [Errno 17] File exists`. From the first failure onward the seeder materialises nothing and misreports healthy commits. The bats suites never place a failing candidate before a passing one, so the gap is uncovered.
**Fix:** `shutil.rmtree(os.path.join(stage, tid), ignore_errors=True)` in every non-written branch before `continue`, or stage each candidate under its own `tempfile.mkdtemp(dir=stage)`. Add a test with a failing candidate followed by a clean one.
**Reference:** CWE-459 Incomplete Cleanup, https://cwe.mitre.org/data/definitions/459.html

### [HIGH-003] The `git apply` fallback silently applies nothing inside a repository *(review, confirmed)*

**Severity:** HIGH | **Confidence:** high
**File:** `head/evals/harness/lib/seed_tasks.py:225-230` (proof trees from `tempfile.mkdtemp` at `:400` and `:467`)
**Issue:** without GNU `patch` on `PATH` the proof runs `git apply -p1 <patch>` with `cwd=tree`. The seeder's `reference.patch` is `git diff` output with `diff --git` headers, which git treats as top-level-relative: when `tree` lies inside any git working tree, paths that do not start with the cwd prefix are skipped. Reproduced here (no `patch`, `TMPDIR` inside the checkout):

```
$ cd $TMPDIR/tmp.X/ref && git apply -v -p1 ref.patch
Skipped patch 'tools/x.py'.
rc=0                       # file unchanged
```

`apply_patch` returns `True` on an unpatched tree, so every clean fix is reported `not green at reference` and every clean refactor passes its proof against an unpatched tree. The grader's own `synth_run` hard-requires `patch` (line 1175), so the two tools already disagree on the dependency.
**Fix:** require `patch` in the wrappers' tool loop (`head/evals/harness/seed-bugfix-tasks.sh:75`, `head/evals/harness/seed-refactor-tasks.sh:64`) and drop the fallback, or `git init -q` a throwaway repository inside `tree` before `git apply`, and in both paths treat `Skipped patch` or zero changed files as failure.
**Reference:** CWE-754 Improper Check for Unusual or Exceptional Conditions, https://cwe.mitre.org/data/definitions/754.html

### [HIGH-004] The grader's bats suite hard-wires a personal dotfiles path for `bats` *(review, confirmed)*

**Severity:** HIGH | **Confidence:** high
**File:** `head/evals/tests/ablation-grade.bats:16` (symlinked into the stub image's PATH at `:48`)
**Issue:** `BATS_BIN="$HOME/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats"` is one developer's checkout. On this host the path does not exist while `bats` is at `/usr/local/bin/bats`; the symlink dangles and every bats-shaped case (AG-2 second half, AG-7's `bf-sh`, any `test_command` of `bats`) fails. The header promises "`bats` is the operator's bats-core" (lines 9-11). The TAP path and the asserted container argv (`timeout 120 bats --tap tests`, line 353) are therefore untested anywhere but one machine.
**Fix:** `BATS_BIN="$(command -v bats)"` (bats is running the file) with `skip` when resolution fails.
**Reference:** CWE-426 Untrusted Search Path (hard-coded environment assumption), https://cwe.mitre.org/data/definitions/426.html

### [HIGH-005] The pytest parser opens any path a test line names and reads it without bound *(new; dissent DISS-C-003 at MEDIUM)*

**Severity:** HIGH | **Confidence:** high
**File:** `head/evals/harness/ablation-grade.sh:576` (collection-error expansion) and `:536` (`def_line`); enabling scan at `:561-571`
**Issue:** `OUTCOME_RX` (line 530) matches `^(PASSED|FAILED|ERROR|XFAIL|XPASS) (\S+)` on every output line, and the test process's stdout is agent-controlled (the agent's module prints at import; `-s` disables capture in the image). For an `ERROR <node>` without `::`, line 576 does `open(os.path.join(tree, f)).read()`; for every outcome node `def_line` does the same at line 536. `os.path.join` discards `tree` for an absolute component and nothing rejects `..` or symlinks, so the grader reads arbitrary host paths, in breach of the "Reads ONLY" contract at lines 35-42. Reproduced three ways with the real `parse_pytest` code and a 5 s timeout, each hanging (exit 124):

```
ERROR /tmp/x.fifo                  # absolute FIFO: open() blocks
PASSED /tmp/y.fifo::test_x         # def_line: open() blocks
ERROR ../../sandbox/z.fifo         # relative: the agent's own sandbox, container mode too
```

`ERROR /dev/zero` makes `.read()` consume memory until the grader dies; a symlink the agent leaves in the sandbox (`copy_tree` preserves symlinks, line 294) works without any traversal. No outer timeout bounds the grader process, so an unattended batch stalls, and the agent voids its own grade.
**Fix:** only parse outcome lines between pytest's `short test summary info` header and the summary line; before opening, require `safe_rel(node_path)` and `is_within(os.path.join(tree, path), tree)`; `os.lstat` and refuse anything but a regular file; cap the read (e.g. 1 MiB); on any refusal count the node as `bad` without reading.
**Reference:** CWE-22 Improper Limitation of a Pathname to a Restricted Directory, https://cwe.mitre.org/data/definitions/22.html; CWE-400 Uncontrolled Resource Consumption, https://cwe.mitre.org/data/definitions/400.html

### [HIGH-006] Hidden-test results are derived from output the graded agent's own code and config produce *(dissent DISS-C-001, verified)*

**Severity:** HIGH | **Confidence:** high
**File:** `head/evals/harness/ablation-grade.sh:1076-1081` (final tree and `run_suite`), `:481-499` (`shape_command`), `:546-594` (`parse_pytest`), `:657-674` (`prepare`)
**Issue:** `hidden_tests`, `failed_names`, `snapshot_tests` and therefore `verdict_accuracy` are computed from the stdout of one pytest process that loads the agent's `conftest.py` at every level, any `pytest.ini`/`pyproject.toml`/`setup.cfg`/`tox.ini` the fixture did not already own (only `grader_protected` paths are restored, and the seeders list only infrastructure that exists at the parent commit, `seed_tasks.py:158-177`), and the agent's modules that the hidden tests import. Nothing passes `--noconftest` or `-c <grader-owned ini>`. A `pytest_runtest_makereport` hookwrapper that sets `rep.outcome = "passed"` yields a clean summary; cruder still, the module under test printing a summary line and calling `os._exit(0)` is enough. Reproduced with the real parser:

```
out = "7 passed in 0.10s\n"   # no outcome lines at all
parse_pytest -> passed 7, total 7, order [], bad set()   # all_pass: True
```

`passed` is taken from the summary line alone (line 590) and never cross-checked against the outcome lines or the static hidden case list. This is exactly the reward-hacking the suite's hidden/overlay/protected design exists to prevent, and it corrupts every ablation arm equally and silently.
**Fix:** pass `--noconftest -c /dev/null` (or a grader-owned ini) and `-p no:cacheprovider`; write results with `--junitxml` to a second, grader-owned mount and parse that; require the set of `PASSED` outcome lines to cover every static hidden case id and treat any mismatch between summary, outcomes and static count as `parse_error` with `passed = 0`; document in the header that in-process forgery by the module under test remains a residual risk (as the contamination scan already documents its lower bound), so the metric is read with that caveat.
**Reference:** CWE-807 Reliance on Untrusted Inputs in a Security Decision, https://cwe.mitre.org/data/definitions/807.html; CWE-345 Insufficient Verification of Data Authenticity, https://cwe.mitre.org/data/definitions/345.html

### [HIGH-007] `--executor host` runs the agent's sandbox code as the operator with no guard *(dissent DISS-C-002, verified)*

**Severity:** HIGH | **Confidence:** medium
**File:** `head/evals/harness/ablation-grade.sh:510-515` (host branch of `exec_in_tree`), `:194` (the option is accepted for any run directory)
**Issue:** in host mode the test command runs on the grading host as the invoking user with `cwd = final` (a copy of the agent's sandbox), the caller's full `PATH` and `PYTHONUSERBASE`, and the agent's conftest/config/modules loaded in-process (HIGH-006). `env -i` scrubs variables only; the code can still read `~/.aws`, `~/.claude.json`, `~/.codex` (paths the grader's own allow-list at lines 952-953 acknowledges exist) or edit the suite and sibling runs. Nothing restricts host mode to `--self-check`, where the tree is the trusted fixture, and the header (lines 77-81) presents host mode as a convenience for the Sprint 258 pytest issue without a warning. Confidence is medium because exploitation needs an operator to grade an untrusted run in host mode; the header suggests that happens.
**Fix:** refuse `--executor host` for a run directory unless an explicit `--trust-sandbox` flag is given, or restrict host mode to `--self-check`; in the header, state plainly that host mode executes the sandbox's code with the operator's privileges.
**Reference:** CWE-250 Execution with Unnecessary Privileges, https://cwe.mitre.org/data/definitions/250.html; OWASP A05:2021 Security Misconfiguration, https://owasp.org/Top10/A05_2021-Security_Misconfiguration/

---

## Medium Priority Issues

### [MED-001] The seeder drops file modes: every fixture script loses its executable bit *(new)*

**Severity:** MEDIUM | **Confidence:** high
**File:** `head/evals/harness/lib/seed_tasks.py:147-155` (`put_from` reads `mode` and uses it only to refuse symlinks), `:138-144` (`write_file` never chmods)
**Issue:** reproduced: a `100755` blob in history is written to the fixture as `644`, `executable=False`. Any bats test that runs a tool directly (`run "$BATS_TEST_DIRNAME/../hi.sh"`) fails with permission denied at base and at reference, so the proof fails with a misleading `not red at base` / `suite not green` reason. For a repository of shell scripts this is the common case, and the bats suites (all Python fixtures) never exercise it. The grader side preserves modes (`ablation-grade.sh:297`, `:311`), so a hand-fixed fixture grades correctly, hiding the seeder defect.
**Fix:** in `put_from`, `os.chmod(dest, 0o755 if mode == "100755" else 0o644)` after `write_file`; add a bats-runner seeding case.

### [MED-002] `remove_path` chmods through agent-planted symlinks onto host directories *(dissent DISS-001 and DISS-C-004, both voices, verified)*

**Severity:** MEDIUM | **Confidence:** high
**File:** `head/evals/harness/ablation-grade.sh:239-244` (the chmod walk), reached from `put_file` at `:306`, `prepare` at `:672`, `fresh_dir` at `:1041`
**Issue:** `os.walk(p)` with `followlinks=False` still lists symlinks-to-directories in `dirs`, and `os.chmod` follows symlinks on Linux, so line 242 changes the mode of the link's target. `copy_tree` preserves symlinks (lines 283, 294), and `prepare()` runs on the host in container mode too. Reproduced: an overlay destination (`tests/test_slug.py`) made into a directory holding `x -> <host dir>`; `remove_path` on it took the host directory from `755` to `700`. The agent can thus change permissions on any directory the grader user owns (shared project dirs, other runs' sandboxes, `~/.local`), while the grader believes it touched only `grading/`.
**Fix:** `if not os.path.islink(path): os.chmod(path, 0o700)`; better, drop the chmod walk and only chmod the directories `shutil.rmtree`'s `onerror` reports.
**Reference:** CWE-59 Improper Link Resolution Before File Access, https://cwe.mitre.org/data/definitions/59.html

### [MED-003] Gate verdicts are read from sandbox copies the implementing agent can rewrite *(dissent DISS-C-005, verified)*

**Severity:** MEDIUM | **Confidence:** high
**File:** `head/evals/harness/ablation-grade.sh:1054-1063` (verdict sources), `:764-779` (last trailer wins), `:1110-1113` (a verdict's presence decides which snapshot is graded)
**Issue:** the header rules sandbox copies of gate artefacts tamperable and reads the dissent envelopes from `eval/` for that reason (lines 40-41), but `engineer-feedback.md`, `auditor-sprint-feedback.md` and `review.md` are read from `sandbox/`. The agent writes to the sandbox in FIX1/FIX2 after the gates ran; appending one more verdict trailer line with `"verdict":"APPROVED"` (the last trailer wins, line 772) or creating `auditor-sprint-feedback.md` flips `verdict`, `verdicts.*`, `verdict_accuracy` and which snapshot is graded. No harness copy of the feedback files exists under `eval/`.
**Fix:** have `pipeline-run.sh` copy each gate's feedback file to `<run-dir>/eval/` immediately after the gate, and read verdicts from there (sandbox copies for review-catch citations only, as now).
**Reference:** CWE-807, https://cwe.mitre.org/data/definitions/807.html

### [MED-004] Seeder proof parsing reads only the last line of stdout+stderr *(review, confirmed)*

**Severity:** MEDIUM | **Confidence:** high
**File:** `head/evals/harness/lib/seed_tasks.py:196-198` (`:213` concatenates stdout and stderr)
**Issue:** any stderr line after pytest's summary (a `pytest_sessionfinish` hook, a plugin warning) makes `counts()` return 0/0 and the proof fails spuriously. The grader already has a robust regex over all lines (`ablation-grade.sh:528`).
**Fix:** parse stdout only and locate the summary by regex over all lines; share one parser between the seeder and the grader.

### [MED-005] `covering_tests` matches a module stem as a bare word anywhere in any test file *(review, confirmed)*

**Severity:** MEDIUM | **Confidence:** high
**File:** `head/evals/harness/lib/seed_tasks.py:350`
**Issue:** stems such as `left`, `util`, `config` match prose and comments; the matched test is pulled into the fixture and the test command without its siblings and the proof fails at base.
**Fix:** match import statements or path fragments and prefer tests sharing an ancestor directory with the touched source.

### [MED-006] Refactor verdict accuracy ignores the structural check *(review, confirmed)*

**Severity:** MEDIUM | **Confidence:** medium
**File:** `head/evals/harness/ablation-grade.sh:1126-1130` versus `:1099-1106` and `:1209-1216`
**Issue:** a gate's snapshot is judged with `all_pass(test_command)` only, so an APPROVED review of an unrefactored tree (suite green, structural red) is scored accurate, while the self-check defines refactor success as structural green and suite green.
**Fix:** for refactor tasks a snapshot "passes" when the structural command and the suite both pass.

### [MED-007] Dissent-envelope anchors are never turned into citations *(review, confirmed; verified on both envelopes here)*

**Severity:** MEDIUM | **Confidence:** high
**File:** `head/evals/harness/ablation-grade.sh:862-867`; claim at `:96`
**Issue:** `envelope_texts` forwards `anchor` and reads `line`/`line_start`/`start_line`, but the envelopes `adversarial-review.sh` writes carry `anchor` as `path:symbol` and the line in `anchor_line`/`anchor_line_end` (both `adversarial-review.json` and `adversarial-audit.json` for this sprint: e.g. `{"anchor":"head/evals/harness/ablation-grade.sh:envelope_texts","anchor_line":864}`; no `line`, `file` or `path` key anywhere). `citations()` cannot parse `path:symbol`, so dissent findings contribute nothing and review-catch recall undercounts every arm with dissent.
**Fix:** read `anchor_line`/`anchor_line_end`, take the file component of `anchor` (before the last `:`), emit `file:line[-end]`.

### [MED-008] The grader's shaped pytest argv differs from the seeders' proof argv *(review, confirmed)*

**Severity:** MEDIUM | **Confidence:** medium
**File:** `head/evals/harness/ablation-grade.sh:492-493` versus `head/evals/harness/lib/seed_tasks.py:206-208`
**Issue:** `-I -s` (image) and `-P` (host) remove the cwd entry that plain `python3 -m pytest` prepends to `sys.path`; a test importing a repo-root package without a conftest `sys.path` insert passes the seeder's proof and fails under the grader for every arm, the reference patch included.
**Fix:** prove with the grader's shaped argv, or keep the tree on `sys.path` (`-e PYTHONPATH=/workspace`).

### [MED-009] Docker client failures are recorded as plausible all-fail grades *(review, confirmed)*

**Severity:** MEDIUM | **Confidence:** medium
**File:** `head/evals/harness/ablation-grade.sh:517-524`, `:631-636`
**Issue:** rc 125/126/127 from the docker client (daemon, mount, no `timeout` in the image) returns as a test result; `run_suite` records `passed 0, total = static, parse_error: true`, which joins `runs.jsonl` as a grade although the header promises exit 2 for a tool failure. `docker_ready()` checks only that the image exists.
**Fix:** treat rc in {125, 126, 127} with no parseable summary as `GradeError`; smoke-run `timeout 1 true` in `docker_ready()`.

### [MED-010] One unreadable regular file in the sandbox aborts the grade *(review, confirmed)*

**Severity:** MEDIUM | **Confidence:** high
**File:** `head/evals/harness/ablation-grade.sh:296`
**Issue:** `copy_tree` handles FIFOs, sockets and symlinks but `shutil.copyfile` on a mode-000 file raises `PermissionError`, uncaught; exit 2, no `grade.json`. The agent controls the sandbox; permission tests leave such files routinely.
**Fix:** catch `OSError` per file, skip and count it; or `chmod u+r` first.

### [MED-011] The PR description and VS-1 claim tasks and a freeze the diff does not contain *(review, confirmed)*

**Severity:** MEDIUM | **Confidence:** high
**File:** `pr/PR.md` versus the diff file list; `head/evals/tests/validate-suite.bats:32-45`
**Issue:** the title and first commit claim "sixteen frozen-suite tasks under grimoires/loa/evals/ablation-2.0/tasks/" and "the freeze"; the diff holds no task directory and no `MANIFEST.sha256`. VS-1 now reads the committed suite's `tasks/*/task.yaml`, so its expectations depend on files this change does not deliver. `reviewer.md` carries no `## AC Verification` section.
**Fix:** either the tasks and the freeze belong in this PR, or the description and VS-1 must stop referring to them; add the AC verification section.

---

## Low Priority Issues

### [LOW-001] Seeder subprocesses inherit stdin; `patch` runs without `--batch`/`--forward` *(new)*
- **File:** `head/evals/harness/lib/seed_tasks.py:227`, `:230`, `:212`
- **Confidence:** medium
- **Issue:** `apply_patch` and `run_tests` never set `stdin=subprocess.DEVNULL`; GNU `patch` without `--batch` can prompt on a tty for a reversed or already-applied hunk and block forever, and a test that reads stdin blocks until `RUN_TIMEOUT`. The grader's `synth_run` passes `--batch --forward` (line 1175).
- **Fix:** `stdin=subprocess.DEVNULL` on both calls; `--batch --forward` on `patch`.

### [LOW-002] The grader suite's python3 stand-in hard-codes `/usr/bin/python3` *(new)*
- **File:** `head/evals/tests/ablation-grade.bats:46`
- **Confidence:** high
- **Issue:** a second host assumption in the same suite as HIGH-004; fails on any host whose `python3` is elsewhere (pyenv, Homebrew, Nix).
- **Fix:** resolve `command -v python3` at setup time.

### [LOW-003] `yq` is an undeclared dependency and the wrong flavour fails silently *(new)*
- **File:** `head/evals/harness/ablation-grade.sh:213`
- **Confidence:** medium
- **Issue:** `load_yaml` requires mikefarah `yq` (`-o=json`); the Python `yq` wrapper rejects the flag and every task reports "task yaml does not parse". Neither the header nor `--help` names `yq`, `git`, `patch` or `timeout` in the image as dependencies.
- **Fix:** check `yq --version` once and name the dependencies in the header.

### [LOW-004] Container hardening gaps and no kill on timeout *(dissent DISS-C-006, verified; includes the review's timeout finding)*
- **File:** `head/evals/harness/ablation-grade.sh:506-508`, `:517-521`
- **Confidence:** medium
- **Issue:** the invocation sets `--network none --read-only --tmpfs --user` but omits `--cap-drop ALL`, `--security-opt no-new-privileges`, `--pids-limit` and `--memory` (the docker stub already accepts the latter two at `docker-stub.sh:56`, so the run itself is likely more hardened than its grader); the tmpfs lacks `noexec`. On the outer `TimeoutExpired` only the client dies; the container keeps the grading tree mounted rw and can keep writing into `final` while the grader reads it.
- **Fix:** add the four flags and `noexec`; pass `--name` and `docker kill` on timeout.
- **Reference:** CWE-250, https://cwe.mitre.org/data/definitions/250.html

### [LOW-005] Unbounded reads and quadratic diffs over agent-controlled files *(new; dissent DISS-C-007 confirms)*
- **File:** `head/evals/harness/ablation-grade.sh:732`, `:752`, `:296`, `:823`
- **Confidence:** medium
- **Issue:** `churn` reads every changed file fully into memory and runs `difflib.unified_diff` (worst case quadratic); `copy_tree` copies any regular file regardless of size; `citations()` re-splits a 4 KiB window for every match. A multi-GB sparse file or a review.md with a citation every few bytes stalls the grade for hours before any test runs.
- **Fix:** skip files above a size cap in `churn` (count them as changed, no line diff); cap `copy_tree` and `citations()` input sizes.
- **Reference:** CWE-400, https://cwe.mitre.org/data/definitions/400.html

### [LOW-006] In-build skips and secret refusals consume a `--select` slot *(review, confirmed)*
- **File:** `head/evals/harness/lib/seed_tasks.py:570`
- **Issue:** `selected = cands[:a.select]` is fixed before building; a `"skip"`/`"secret"` inside `build_refactor` leaves fewer than N tasks although later candidates qualify, contrary to `seed-refactor-tasks.sh:37-38`.

### [LOW-007] Any non-zero exit of the no-secrets scanner is reported as a secret hit *(review, confirmed)*
- **File:** `head/evals/harness/lib/seed_tasks.py:502-506`
- **Issue:** a missing script or exit 127 becomes `refused …: a secret pattern`. Fail-closed is right; the message is wrong. Distinguish exit 1 from tool errors (exit 2).

### [LOW-008] Subject regex over-matches *(review, confirmed)*
- **File:** `head/evals/harness/lib/seed_tasks.py:25`
- **Issue:** `^(fix|bug)` matches `fixture…`, `fixed-point…`, `bugbear…`; the refactor set matches every `chore(release): …`. Anchor on the conventional-commit type: `^(fix|bug)(\(|!|:)`.

### [LOW-009] The seeder's git environment keeps the user's global config *(review, confirmed)*
- **File:** `head/evals/harness/lib/seed_tasks.py:51-54`
- **Issue:** `HOME` is kept and only `GIT_CONFIG_NOSYSTEM` is set; `log.showSignature`, `diff.context`, `diff.algorithm` reshape the parsed log and `reference.patch`. Add `GIT_CONFIG_GLOBAL=/dev/null` as the grader does (`ablation-grade.sh:679`).

### [LOW-010] `all_pass` ignores the exit code and timeout once a summary parsed *(review, confirmed)*
- **File:** `head/evals/harness/ablation-grade.sh:653`
- **Issue:** a runner that prints `1..1 / ok 1` and exits non-zero (teardown failure, timeout after the plan) is "fully passing".

### [LOW-011] `OUTCOME_RX` scans every output line, including captured sections *(review, confirmed; the enabling condition of HIGH-005)*
- **File:** `head/evals/harness/ablation-grade.sh:561-571`, `:589`
- **Issue:** `-rA` prints captured output; a captured line beginning `FAILED …`/`ERROR …` becomes an outcome, and `ERROR word` without `::` decrements `total`. Restrict the scan to the `short test summary info` section.

### [LOW-012] Contamination roots follow the grader's `--executor`, not how the run executed *(review, confirmed)*
- **File:** `head/evals/harness/ablation-grade.sh:947-954`
- **Issue:** grading a host-executed run in container mode whitelists all of `/home/evaluser`, so reads of sibling run dirs are never `outside_path`. Derive the model from the transcripts' init cwd.

### [LOW-013] TAP results are keyed by description *(review, confirmed)*
- **File:** `head/evals/harness/ablation-grade.sh:617-621`
- **Issue:** two bats tests with the same description collide in `names`/`bad`; `failed_names` and positions are wrong for that file. Key by test number.

### [LOW-014] `"hidden" in low` flags any command containing the substring *(review, confirmed)*
- **File:** `head/evals/harness/ablation-grade.sh:964-965`
- **Issue:** `ls -a .hidden_cache`, `grep -i hidden docs/` are false positives, not misses. Use a word boundary plus the known hidden paths.

### [LOW-015] `--self-check reference` hard-requires `patch` and surfaces its absence as an internal error *(review, confirmed)*
- **File:** `head/evals/harness/ablation-grade.sh:1175`
- **Issue:** `FileNotFoundError` becomes `internal error`, and `patch` is listed nowhere as a dependency (the seeder falls back instead, HIGH-003).

### [LOW-016] The generated-path exclusion runs after the missing-file check *(review, confirmed)*
- **File:** `head/evals/harness/seed-corpus-from-record.sh:233-236`
- **Issue:** a `fix` row for a generated artefact absent from `head/` fails the manifest build (line 233) although line 235 would drop the row anyway. Move the exclusion above the file check. The seeding-side exclusion at lines 710-712 is ordered correctly.

---

## Observations

Non-tallied notes.

- `bounds: {max_turns: {}, timeout_min: {}}` written by `seed_tasks.py:286` is valid against `validate-suite.sh:281-290` (an empty phase map passes); no defect.
- The regenerated manifests are correct: `pr-14` drops 9 `fix_regions` rows, `pr-15` drops 32, all generated paths by the head rule, no remaining generated path, defects and other keys byte-identical, ids renumbered contiguously, both checksums in `SHA256SUMS` match.
- `validate-suite.sh:218-224` rejects booleans as churn counts (`not isinstance(v, bool)`), a detail many validators miss.
- The `.pyc` under `pr/head/evals/harness/lib/__pycache__/` is an untracked artefact of the review phase's direct execution, not part of the change; it was left in place.
- Beads (`br`) is not installed in this workspace; the beads steps of the audit workflow were skipped.

---

## Rejected dissent payloads

None. The envelope `adversarial-audit.json` carries `rejected_summary: []`, `rejected_count: 0`, lists `adversarial-rejected-audit.jsonl` as its sidecar and that file holds no rows (0 bytes). Both voices completed (codex-headless, claude-headless; `counted_as: independent_voice`); all eight findings are triaged above: DISS-C-001 and DISS-C-002 tallied HIGH, DISS-001/DISS-C-004 and DISS-C-005 tallied MEDIUM, DISS-C-006 and DISS-C-007 tallied LOW, DISS-C-003 folded into HIGH-005.

---

## Review demotions

The review trailer carries `excluded: 0`; there were no speculative low-confidence highs to confirm. `excluded_confirmed: 0`.

---

## Documentation Audit

No `documentation-coherence-task-*.md` or `documentation-coherence-sprint-*.md` reports exist under `grimoires/loa/a2a/subagent-reports/`; documentation was verified manually. Each script carries a complete header contract (usage, read/write boundary, exit codes, tested-by). Security-critical code is commented (the trust boundary at `ablation-grade.sh:35-42`, `156-157`). Gaps: the header claims at lines 35-42 ("Reads ONLY") and 96 (envelope anchors) do not hold (HIGH-005, MED-007); host mode's privilege implication is undocumented (HIGH-007); dependencies (`yq`, `patch`, Python 3.12, `timeout` in the image) are unnamed (HIGH-001, LOW-003, LOW-015); the PR description does not match the diff and the implementation report has no AC verification (MED-011). No CHANGELOG is part of the change; no secrets or internal URLs appear in docs or comments (the hard-coded path at `ablation-grade.bats:16` is a personal path, not a credential).

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added (grep of the diff for key, token and private-key patterns: clean)
- [ ] Input validation at trust boundaries: manifest and history paths are validated (`safe_rel`, `safe_path`, symlink blobs refused), but test-process output reaches `open()` unvalidated (HIGH-005) and agent config reaches the result process (HIGH-006)
- [ ] No privilege escalation paths: host mode runs sandbox code as the operator (HIGH-007); cleanup chmods through symlinks (MED-002)
- [x] No code sourced or eval'd from variables (AG-13 pins this; git and docker are argument vectors)
- [x] Container runs `--network none --read-only --user uid:gid` with one rw mount (hardening gaps in LOW-004)
- [ ] Error handling: agent-controlled artefacts abort or stall the grade (HIGH-005, MED-010, LOW-005); docker client failures become grades (MED-009)
- [x] Error messages and `grade.json` leak no hidden-test names or excerpts (ids only; AG-12)
- [ ] Tests cover security paths: the grader suite cannot run off one machine (HIGH-004, LOW-002); no test covers a forged summary, a symlinked overlay dest, a failing-then-passing seed candidate, or a bats-runner seed

---

## Threat Model Summary

**Trust boundaries:** harness-written run metadata (`index.json`, `transcripts/`, `eval/`) and the frozen suite are trusted; `sandbox/` content, snapshot bundles' trees, and every byte the test process prints are attacker-controlled; the grader process runs on the host as the operator.

**Attack vectors:** test-process stdout to `open()` (HIGH-005: high); agent config/modules in the result process (HIGH-006: high); host executor (HIGH-007: high when used); symlinks in the copied tree reaching `os.chmod` (MED-002: medium); sandbox gate files rewritten after the gates (MED-003: medium); oversized or unreadable sandbox files (MED-010, LOW-005: low-medium).

**Mitigations present:** `safe_rel` on every manifest path, `is_within` on the fixture, bare-repo bundle extraction with a path filter, symlink-aware copy and removal (except the chmod), `--network none --read-only --user`, `env -i` on the host, ids-only output, no shell interpolation anywhere.

**Residual risks after the fixes above:** in-process forgery by the module under test (document as a lower bound, like the contamination scan); host mode by operator choice.

---

## Positive Findings

- Every subprocess is an argument vector; no shell string anywhere in 2,000 lines of new code.
- Snapshot extraction through a scratch bare repository with `GIT_CONFIG_GLOBAL=/dev/null` and `GIT_CONFIG_NOSYSTEM`.
- `grade.json` is deterministic (no timestamps, no scratch paths) and written atomically; AG-12 proves `meta/` independence byte for byte.
- The seeders stage privately, prove before publishing, run the proof under `env -i`, and refuse mount-owned paths and symlink blobs by name.
- The generated-path exclusion is implemented twice (seeding and manifest build) with one shared rule and a one-line-per-path stderr report, and the regenerated manifests are exactly what the rule produces.

---

## Next Steps

1. Fix the seven HIGH findings: version guard or filter-free extraction (HIGH-001); per-candidate stage cleanup (HIGH-002); require `patch` or make `git apply` safe (HIGH-003); resolve `bats` from PATH (HIGH-004); bound and confine the parser's file reads (HIGH-005); `--noconftest -c /dev/null`, JUnit results on a grader-owned mount and summary/outcome cross-checks (HIGH-006); gate host mode (HIGH-007).
2. Fix MED-001 (file modes), MED-002 (`islink` before `chmod`) and MED-003 (read verdicts from `eval/`), then the remaining mediums.
3. Add regression cases: a forged summary line; a symlinked overlay destination; `ERROR ../../x` in test output; a failing-then-passing seed candidate; a bats-runner seed; a gated run with an `IMPLEMENT.bundle` on the CI Python.
4. Make `PR.md`, VS-1 and the diff agree on where the sixteen tasks and the freeze live; add `## AC Verification` to `reviewer.md`.
5. Run `/implement sprint-1` for the fixes, then `/review-sprint sprint-1` and `/audit-sprint sprint-1` again.

---

**Audit Completed:** 2026-10-21T10:12:00Z

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":7,"medium":11,"low":16},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T10:12:00Z"} -->
