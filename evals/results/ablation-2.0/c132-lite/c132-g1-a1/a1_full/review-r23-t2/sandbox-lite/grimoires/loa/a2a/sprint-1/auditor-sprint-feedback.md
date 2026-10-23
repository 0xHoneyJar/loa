# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)
**Scope:** `pr/head.diff` — 16 files; citations are `head/<path>:<line>` with lines from `pr/head/`.

---

## Verdict: CHANGES_REQUIRED

---

## Pre-flight notes

- **Prerequisite deviation.** Phase 0 expects `engineer-feedback.md` to say "All good"; it says CHANGES REQUIRED (3 high). The task for review-r23 orders this audit to run autonomously, so it ran; the review's three blocking items are re-examined below (two are tallied as my own, one is re-rated) and nothing here supersedes the review's required fixes.
- **Guardrails:** `guardrails-orchestrator.sh` → PROCEED. **Integrity pre-check:** `.loa.config.yaml` has no `integrity_enforcement` key; nothing to enforce. **known-failures.md** is absent (startup WARNING); triaged without it.
- **Dissent (Phase 1C):** `adversarial-review.sh --type audit --sprint-id sprint-1 --diff-file pr/head.diff --json` → `grimoires/loa/a2a/sprint-1/adversarial-audit.json`, status `reviewed`, primary gpt-5.5-pro (answered by codex-headless), companion claude-headless; `verdict_quality.voices_succeeded` 2/2, `degraded: false`, `rejected_count` 0. Not a degraded review. The dissenter saw the diff only (no `--context-file`); its input was budget-truncated to 5 of 16 files (its own stderr), so its silence on the seeders and tests is not evidence.
- **Not assessable here:** the PR title promises sixteen frozen tasks and a freeze; neither the tasks, `freeze.sh`, `MANIFEST.sha256`, `no-secrets.sh`, `pipeline-run.sh` nor the smoke suite is in the diff, and the grader and AG-14/16/18 hard-depend on them (`head/evals/harness/ablation-grade.sh:452`, `head/evals/tests/ablation-grade.bats:359-361`, `:521`). The local `pr/head/` snapshot drops execute bits (the diff records 100755), so the new bats suites were not run end-to-end; every mechanic below was reproduced in isolation on this host (bats 1.13.0, Python 3.11.2, git 2.x).

## Executive Summary

The change adds the cycle-130 ablation grader, two task seeders with a shared Python library, the bd-8o5rx generated-path exclusion, the `source.churn` schema, regenerated pr-14/pr-15 key manifests (SHA256SUMS verified with `sha256sum -c`; only generated-path `fix_regions` were removed, defects untouched) and six bats suites. The parts that read history and task metadata are careful: every path is checked with `safe_rel`/`safe_path` before it touches disk, symlinks in history are refused, mount-owned paths are refused by name, subprocesses are argument vectors, nothing is sourced or eval'd, `grade.json` is written atomically and carries ids only.

The weak side is the boundary the grader exists to police: the agent's tree. The grader opens paths it parses out of the *agent-controlled* test process's stdout on the host (`/dev/zero`, a FIFO, any host file), accepts a forged summary line or an `os._exit(0)` as a full score, reuses one read-write tree across the hidden, regression and structural runs with a single restore, follows planted symlinks when it chmods, runs the grading container with no pids/memory/cpu caps and a SIGTERM-only timeout that leaves an unnamed container alive, and feeds unbounded agent text to a quadratic regex. On the test side, the one assertion that no hidden byte reached the sandbox is a bare `!` that bats never evaluates (reproduced), and the dissent-envelope parser never reads `anchor_line`, so every defect caught only by the review or audit dissent is graded as missed (verified against this sprint's own envelopes). The measurement this grader produces is the asset; today a single uncooperative sandbox can forge it, stall it, or crash the host running it.

**Security Issues Found:**

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 4 |
| Medium | 13 |
| Low | 10 |

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] The hidden-test leak guard cannot fail

**Severity:** HIGH — **Confidence:** high
**File:** `head/evals/tests/pipeline-run.bats:498` (also `:503`)
**Issue:** The new "frozen-suite layout" test is the only check of AC-2.6 / AC-5.5 ("no byte of any hidden/ file reached the sandbox, its git history or the snapshots"). Two of its three assertions are bare negations inside the test body:
```bash
  for f in sealed-case-7f3a sealed-shape-91c2 sealed-patch-c0de; do
    ! grep -rqF "$f" "$T/run/sandbox" "$T/run/snapshots" "$T/run/transcripts"
  done
  …
  ! git -C "$T/run/sandbox" grep -q -e 'sealed-' $revs --
```
bash skips both `set -e` and the ERR trap for a `!`-inverted command, so a sealed marker present in the sandbox, a snapshot or a transcript passes silently. Only line 504 is effective, and only because it is the test's last command. Reproduced on this host's bats 1.13.0: a mid-test `! grep -q x <<<"x"` is `ok`; the same line last, as `run !`, or with `|| false` is `not ok`.
**Impact:** A guard that cannot fire reports the suite's core confidentiality property as verified while a leak of the hidden tests into the agent's view invalidates the whole ablation.
**Fix:** `run ! grep -rqF "$f" …` (after `bats_require_minimum_version 1.5.0`) or `… || false`, as `head/evals/tests/seed-bugfix.bats:93`, `:109`, `:123` already do. Apply to MED-013 in the same pass.
**Reference:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html ; bats-core "run ! command" — https://bats-core.readthedocs.io/en/stable/writing-tests.html#run-test-other-commands

### [HIGH-002] Paths parsed from the agent's test output are opened on the host without containment

**Severity:** HIGH — **Confidence:** high
**File:** `head/evals/harness/ablation-grade.sh:574-576` (also `:536`, `:566-567`)
**Issue:** `parse_pytest` collects every `ERROR <node>` line without `::` as a collection-error path and reads it on the host:
```python
    for f in coll_err:
        try:
            text = open(os.path.join(tree, f), encoding="utf-8", errors="replace").read()
```
and `def_line` (`:536`) does the same with the path half of every `PASSED|FAILED|… <node>` id. The stdout comes from a process running the agent's modules (container mode even passes `-s`), so one `print("ERROR /dev/zero")` before the real summary makes the grader `open("/dev/zero").read()` outside the container and its timeout (`os.path.join("/tree", "/dev/zero") == "/dev/zero"`, verified); `ERROR tests/fifo` naming a FIFO the test run created in the rw `/workspace` blocks `open()` forever; `ERROR ../../../etc/passwd` (`..` is not rejected) or an absolute path reads any host file the grading user can, with the count of `def test` matches as a weak oracle.
**Impact:** Host memory exhaustion or a hung grader (the batch stalls on one run) and an out-of-tree read primitive, triggered by content the thing under evaluation controls.
**Fix:** Pass every output-derived path through `safe_rel`, require `is_within(tree, …)`, `os.lstat` it and open only `S_ISREG` files under a size cap (a few MiB); never follow symlinks; treat anything else as "unknown node" with no read.
**Reference:** CWE-22 Path Traversal — https://cwe.mitre.org/data/definitions/22.html ; CWE-400 Uncontrolled Resource Consumption — https://cwe.mitre.org/data/definitions/400.html

### [HIGH-003] Agent-controlled code can forge a full hidden-test score

**Severity:** HIGH — **Confidence:** high (mechanism); the exploit needs a gaming or careless agent
**File:** `head/evals/harness/ablation-grade.sh:631-633` (also `:652-653`, `:593`)
**Issue:** Results are derived only from the stdout of a process that imports the agent's modules and runs any non-protected `conftest.py`/`pytest.ini`. Two independent routes to a perfect score:
```python
    if parsed is None:
        total = max(static, 1)
        passed = total if rc == 0 else 0
```
a `conftest.py` that calls `os._exit(0)` at import prints no summary and exits 0 → `passed == total` with only `parse_error: true` to tell (the row consumer in AG-18 reads `hidden_test_pass_rate` from passed/total, `head/evals/tests/ablation-grade.bats:391`). Or the module prints `PASSED tests/test_x.py::t` lines plus `===== 7 passed in 0.1s =====` and exits 0: `parse_pytest` takes the last matching summary, `all_pass` (`:652`) checks neither `rc` nor `timed_out` nor that the parsed ids match the static case list, so `hidden_tests`, `snapshot_tests` and `verdict_accuracy` are all forged. Review Observations §2 rated this MEDIUM; both dissent voices rate it HIGH/BLOCKING and I agree: the grade is the asset.
**Impact:** The arm comparison DEC-0420 exists for can be gamed to 100% by one line in the sandbox.
**Fix:** Never set `passed = total` on a parse failure (passed = 0, `parse_error` true); require `rc == 0` for `all_pass` and `rc != 0` ⇔ failures present (a mismatch is `parse_error`); cross-check parsed node ids against the statically enumerated hidden cases (each exactly once); load a grader-owned pytest plugin via `-p` from a read-only mount that writes results to a second mount, and prefer that over stdout.
**Reference:** CWE-345 Insufficient Verification of Data Authenticity — https://cwe.mitre.org/data/definitions/345.html ; CWE-807 Reliance on Untrusted Inputs in a Security Decision — https://cwe.mitre.org/data/definitions/807.html

### [HIGH-004] Dissent findings never count toward recall

**Severity:** HIGH — **Confidence:** high
**File:** `head/evals/harness/ablation-grade.sh:864-867`
**Issue:**
```python
        fp = f.get("file") or f.get("path")
        ln = f.get("line") or f.get("line_start") or f.get("start_line")
```
The real envelopes carry neither: every finding in this sprint's `adversarial-review.json` and `adversarial-audit.json` is `{"anchor": "evals/harness/ablation-grade.sh:envelope_texts", "anchor_line": 864, "anchor_line_end": 867}` with no `file`/`path`/`line` (verified with jq; FR-4 contract at `.claude/scripts/adversarial-review.sh:28`, `:608-618`). The symbol anchor has no digits, so `citations()` yields nothing and `anchor_line` is never read. AG-8 passes only because its hand-written envelopes use `anchor: "lib/x.sh:20"` and `file`+`line` (`head/evals/tests/ablation-grade.bats:402-403`). The header's promise at `:96` ("each finding's anchor (and file:line)") is not met.
**Impact:** Every arm whose gates run the dissent is under-counted exactly where the dissent adds value; the grader systematically biases the comparison it exists to make.
**Fix:** When `anchor_line` is an int, emit `f"{anchor.split(':', 1)[0]}:{anchor_line}"` (range with `anchor_line_end`); add an AG-8 case in the real FR-4 shape.
**Reference:** CWE-1068 Inconsistency Between Implementation and Documented Design — https://cwe.mitre.org/data/definitions/1068.html

---

## Medium/Low Priority Issues

### [MED-001] The grading container has no resource caps
- **Severity:** MEDIUM — **Confidence:** high (absence), medium (impact)
- **File:** `head/evals/harness/ablation-grade.sh:506-508`
- **Issue:** `docker run --rm --network none --read-only --tmpfs /tmp:rw,size=256m --user …` — no `--pids-limit`, `--memory`, `--cpus`, `--cap-drop ALL` or `--security-opt no-new-privileges`. The agent container in pipeline-run uses 512 / 4g / 2 (`head/evals/tests/pipeline-run.bats:753-755`), so the grader is the laxer of the two sandboxes for the same code. A fork bomb or allocation loop in agent-authored test code takes the grading host down within the 120 s window. The rw `/workspace` mount is also unbounded disk. Confirmed by cross-model review (DISS-C-005).
- **Fix:** Mirror pipeline-run's caps and add `--cap-drop ALL --security-opt no-new-privileges`.
- **Reference:** CWE-400 — https://cwe.mitre.org/data/definitions/400.html ; CWE-770 — https://cwe.mitre.org/data/definitions/770.html

### [MED-002] SIGTERM-only timeout; a timed-out container is never killed
- **Severity:** MEDIUM — **Confidence:** high
- **File:** `head/evals/harness/ablation-grade.sh:508`, `:517-521`
- **Issue:** The in-container `timeout 120 …` has no `-k`, so a test process that ignores SIGTERM runs on (`timeout 1 bash -c 'trap "" TERM; sleep 3'` runs 3 s, rc 124 — reproduced). At 180 s Python's `TimeoutExpired` kills only the `docker run` client; the container is unnamed, never `docker kill`ed, and keeps its rw mount into `grading/<label>`, which the next `fresh_dir(grading)` (`:1053`) removes under it. Confirmed by cross-model review (DISS-C-005; the review's DISS-C-004).
- **Fix:** `timeout -k 10 120`; `--name <uuid>` and `docker kill <name>` in the `except`.
- **Reference:** CWE-404 Improper Resource Shutdown — https://cwe.mitre.org/data/definitions/404.html

### [MED-003] Unbounded copy and read of agent files; sparse files balloon
- **Severity:** MEDIUM — **Confidence:** medium
- **File:** `head/evals/harness/ablation-grade.sh:296` (also `:732`, `:878`)
- **Issue:** `copy_tree` copies every regular sandbox file with `shutil.copyfile` and `churn` reads each one whole. A sparse file is free to create in the sandbox (`truncate -s 1T`) and is materialised in full on copy (300 MB sparse → 300 MB on disk, reproduced), then read into memory. No size cap anywhere on agent-controlled content.
- **Fix:** `os.lstat` first; skip or record files above a cap (and `st_blocks*512 << st_size` sparse files); stream the churn diff or cap it.
- **Reference:** CWE-400 — https://cwe.mitre.org/data/definitions/400.html

### [MED-004] Gate verdicts are read from agent-writable files
- **Severity:** MEDIUM — **Confidence:** medium
- **File:** `head/evals/harness/ablation-grade.sh:1055-1063` (also `:875-876`)
- **Issue:** `verdicts`, "a gate ran", `verdict` and therefore `verdict_accuracy` come from `sandbox/grimoires/loa/a2a/sprint-1/{engineer,auditor}-feedback.md` and `sandbox/review.md`. The FIX1/FIX2 agent runs after REVIEW with write access to those files and can rewrite the trailer. The header (`:40-41`) already treats the sandbox copies of the *envelopes* as tamperable and reads `eval/` instead, but not the feedback files. [ASSUMPTION] `pipeline-run.sh` (not in the diff) does not copy the feedback files under `eval/`.
- **Fix:** Have the harness copy each gate's feedback file to `eval/` at gate end and read those, falling back to the sandbox only with a `verdict_source: sandbox` flag.
- **Reference:** CWE-345 — https://cwe.mitre.org/data/definitions/345.html

### [MED-005] One restore, three runs on the same read-write tree
- **Severity:** MEDIUM — **Confidence:** high
- **File:** `head/evals/harness/ablation-grade.sh:1078-1101`
- **Issue:** `prepare(t, final)` runs once (`:1078`); the hidden tests (`:1080`), the regression command (`:1090`) and the structural check (`:1101`) then run sequentially on the same `final` tree mounted `:rw`. Agent code executed by the first run can rewrite the overlaid structural check, the regression tests or a protected fixture file so the later runs grade a tampered tree. Cross-model finding DISS-C-002, confirmed by reading.
- **Fix:** Re-run `prepare` (or copy a fresh tree) before every `run_suite`; or mount `:ro` with a writable tmpfs for caches; hash overlaid files after each run and flag drift.
- **Reference:** CWE-367 TOCTOU — https://cwe.mitre.org/data/definitions/367.html

### [MED-006] `remove_path` chmods through planted symlinks
- **Severity:** MEDIUM — **Confidence:** high (mechanism), low (impact)
- **File:** `head/evals/harness/ablation-grade.sh:239-244`
- **Issue:** `os.walk` lists symlinks-to-directories in `dirs` and `os.chmod` follows them, so a sandbox symlink `x -> /home/<grader>/shared` (copied verbatim by `copy_tree` `:283`, or created by the test run in rw `/workspace`) gets its *target* set to 0700 on the next `fresh_dir(grading)`, on `put_file → remove_path(dst)` when a protected path collides with an agent directory, or in the `finally` cleanup. Reproduced: target 755 → 700 after the walk.
- **Fix:** Skip `os.path.islink(...)` entries; chmod only after a failed unlink via `rmtree(onerror=…)`.
- **Reference:** CWE-59 Link Following — https://cwe.mitre.org/data/definitions/59.html

### [MED-007] `--executor host` runs the agent's tree on the grading host with no guard
- **Severity:** MEDIUM — **Confidence:** high
- **File:** `head/evals/harness/ablation-grade.sh:510-515`
- **Issue:** `env -i` scrubs variables only; the test command runs as the invoking user with the full filesystem (the suite's `hidden/` of every task, `~/.aws`, `~/.claude.json`), the user site (`PYTHONUSERBASE`) and the network. Opt-in, but no flag name, warning or header sentence says so (`:77-81` describe only the env). Cross-model finding DISS-C-006.
- **Fix:** Rename to `--unsafe-host` or print a stderr warning; run under `unshare -n`/bwrap with only the tree visible; or keep host mode for self-check only.
- **Reference:** CWE-250 Execution with Unnecessary Privileges — https://cwe.mitre.org/data/definitions/250.html

### [MED-008] Quadratic citation regex over unbounded agent text
- **Severity:** MEDIUM — **Confidence:** high
- **File:** `head/evals/harness/ablation-grade.sh:795-798` (read at `:878`, `:769`, `:786`)
- **Issue:** `review.md` and both feedback files are agent-authored, read whole, and scanned with `CITE`, whose path branch `[A-Za-z0-9_./+()-]+\.[A-Za-z0-9]{1,6}…:` backtracks over every dot per start position. Measured here: 4 000 chars 0.07 s, 8 000 chars 0.30 s, 16 000 chars 1.21 s (4× per doubling); a 1 MB `review.md` of `a.a.a…` is ≈1.3 h, 5 MB ≈1.4 days. Cross-model finding DISS-C-007.
- **Fix:** Cap agent texts (e.g. 1 MiB, `truncated: true`); tokenise on whitespace and match per token, or exclude `.` from the repeated class.
- **Reference:** CWE-1333 Inefficient Regular Expression Complexity — https://cwe.mitre.org/data/definitions/1333.html

### [MED-009] `tarfile.data_filter` needs Python ≥ 3.11.4; the host is 3.11.2
- **Severity:** MEDIUM — **Confidence:** high
- **File:** `head/evals/harness/ablation-grade.sh:710-714`
- **Issue:** `tarfile.data_filter` / `extractall(filter=)` exist only on 3.12+ or the 3.11.4 / 3.10.12 / 3.9.17 backports; `hasattr(tarfile, "data_filter")` is False here. Every run with an IMPLEMENT or FIX1 bundle dies in `extract_snapshot` as "internal error" exit 2 — fail-closed (no member is extracted first), but no grade for any gated arm on such a host. Nothing checks the interpreter.
- **Fix:** `die` early with the floor stated, or `getattr(tarfile, "data_filter", None)` with a fallback that rejects absolute / `..` / out-of-tree link members itself.
- **Reference:** PEP 706 — https://peps.python.org/pep-0706/

### [MED-010] Regression parse-fallback asymmetry
- **Severity:** MEDIUM — **Confidence:** medium
- **File:** `head/evals/harness/ablation-grade.sh:1091-1095`
- **Issue:** An unparseable base run sets `base_ok = []`, so `newly_failing` is always empty for an exit-status-only `regression_command`; an unparseable final run reports every base test newly failing even at rc 0. Review Observations §2, confirmed.
- **Fix:** Use the fallback ids symmetrically (`rf["rc"] != 0` → all of `base_ok`, else none) and expose `regressions.parse_error`.

### [MED-011] Contamination false positives short-circuit the run
- **Severity:** MEDIUM — **Confidence:** medium
- **File:** `head/evals/harness/ablation-grade.sh:964-983` (`:1034`)
- **Issue:** `"hidden" in low` fires on `rg --hidden` or any CSS edit; `ABS_WORD` treats quoted route strings as paths; `/home`, `/root`, `/srv` are outside the container allow-list; the first hit marks the run contaminated and stops. Review Observations §3, confirmed.
- **Fix:** Match `hidden` as a path component; record every hit in `contamination_hits` and keep `contaminated` as the first.

### [MED-012] The grader suite only runs on the author's machine
- **Severity:** MEDIUM — **Confidence:** high
- **File:** `head/evals/tests/ablation-grade.bats:16` (also `:46`, `:48`, `:51`)
- **Issue:** `BATS_BIN="$HOME/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats"` is a personal dotfiles path; the symlink at `:48` dangles elsewhere, the python3 stand-in hard-codes `/usr/bin/python3` (`:46`), and the stub PATH `$T/bin:/usr/bin:/bin` (`:51`) misses this host's `/usr/local/bin/bats`, so AG-2 and AG-7 fail by construction off the author's host. The review rates this HIGH; I rate it MEDIUM (a DevOps/reproducibility defect, not a boundary violation) — either way it must be fixed.
- **Fix:** `BATS_BIN="${LOA_SEED_BATS:-$(command -v bats)}"`, `skip` when empty; `command -v python3`.
- **Reference:** CWE-1104 / portability — https://cwe.mitre.org/data/definitions/1104.html

### [MED-013] More inert negations guard DEC-0413 and the trust boundary
- **Severity:** MEDIUM — **Confidence:** high
- **File:** `head/evals/tests/ablation-grade.bats:501` (also `:502`, `:505`, `:512`, `:513`); `head/evals/tests/seed-corpus.bats:189`
- **Issue:** The "ids only in every summary field" checks (`:501-505`) and the "no `source`/`eval` in the grader" checks (`:512-513`) are mid-test bare `!` and cannot fail (same mechanism as HIGH-001; `:463` and `:514` work only as last commands). SC-7's `! grep -qF 'excluded generated path: src/real.sh'` likewise would not notice a real file being excluded.
- **Fix:** `run !` or `|| false`.
- **Reference:** CWE-754 — https://cwe.mitre.org/data/definitions/754.html

### [LOW-001] `git archive` honours in-commit `.gitattributes`
- **File:** `head/evals/harness/ablation-grade.sh:700`
- **Issue:** `export-ignore`/`export-subst` in the snapshot commit's `.gitattributes` (agent-written) alter the extracted tree (reproduced: a file marked `export-ignore` is absent from `git archive HEAD`), so the tree graded for a gate can differ from the one the gate read.
- **Fix:** Write `* -export-ignore -export-subst` to `<bare>/info/attributes` before archiving.

### [LOW-002] Credential stores are allow-listed for the contamination scan in host mode
- **File:** `head/evals/harness/ablation-grade.sh:949-953`
- **Issue:** `~/.aws`, `~/.codex`, `~/.claude.json` are allowed roots, so an agent `Read` of AWS or API credentials is never surfaced; the scan's goal is suite leakage (header: a lower bound), but consumers see `contaminated: null` as clean. Confirmed by cross-model review (DISS-C-009).
- **Fix:** A distinct `credential_path` pattern; a `scan_coverage: lower_bound` field in `grade.json`.

### [LOW-003] `write_grade` follows a pre-existing symlink at `<out>.tmp`
- **File:** `head/evals/harness/ablation-grade.sh:1158-1161`
- **Issue:** Plain `open(tmp, "w")` on a predictable path; in a host-mode pipeline run the agent can leave `../grade.json.tmp` as a symlink (relative writes are not in the scan). Cross-model finding DISS-C-008, LOW.
- **Fix:** `os.open(tmp, O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW)` or `NamedTemporaryFile(dir=d)`; refuse a symlinked `out`.
- **Reference:** CWE-59 — https://cwe.mitre.org/data/definitions/59.html

### [LOW-004] The seeder honours the operator's global gitconfig
- **File:** `head/evals/harness/lib/seed_tasks.py:52-53`
- **Issue:** `_git_env` keeps `HOME` and sets `GIT_CONFIG_NOSYSTEM` but not `GIT_CONFIG_GLOBAL=/dev/null` (the grader does, `ablation-grade.sh:679`); e.g. `log.showSignature=true` adds lines to the `--format` output `commits_since` splits on.
- **Fix:** Add `GIT_CONFIG_GLOBAL=/dev/null` (keep `-c` overrides).

### [LOW-005] The seeder executes repository-history code on the operator's host
- **File:** `head/evals/harness/lib/seed_tasks.py:201-222`
- **Issue:** Tests and modules at arbitrary commits of any `--repo` run under the operator's uid with inherited PATH and the user site; `env -i`-style scrubbing is documented (`seed-bugfix-tasks.sh:31-33`), the trust implication is not. Fine for own history; the headers should say so and point at the grading image for foreign repositories.

### [LOW-006] `patch` can block on a prompt
- **File:** `head/evals/harness/lib/seed_tasks.py:227`
- **Issue:** No `--batch`/`-f`, stdin inherited: a hunk whose file is missing prompts "File to patch:" on a TTY. The grader passes `--batch --forward` (`ablation-grade.sh:1175`); mirror it.

### [LOW-007] `counts()` reads the last line of stdout+stderr combined
- **File:** `head/evals/harness/lib/seed_tasks.py:196-198`
- **Issue:** A trailing stderr warning yields 0/0 and a spurious "not red at base" / "not green at reference". Parse stdout, or search the last lines for the summary pattern as the grader does.

### [LOW-008] Header contradicts behaviour on refusal slots
- **File:** `head/evals/harness/seed-bugfix-tasks.sh:43-44`
- **Issue:** "refusals and skips do not count" — a post-selection no-secrets refusal (`seed_tasks.py:588-592`) consumes a slot and is not back-filled.

### [LOW-009] `yq` is required but never checked
- **File:** `head/evals/harness/ablation-grade.sh:213`
- **Issue:** A missing binary surfaces as "internal error: FileNotFoundError" rather than a startup usage error like `docker_ready` (`:471`).

### [LOW-010] Generated-path exclusion ordered after the missing-file check
- **File:** `head/evals/harness/seed-corpus-from-record.sh:235-236`
- **Issue:** `--build-manifest` tests `os.path.isfile(hp)` (`:232`) before `generated_path`, so a `fix` row for a generated path absent from `head/` is an error, not an exclusion; move the exclusion first.

---

## Observations

None excluded from the tally (no finding is both speculative and low-confidence).

**Positive controls verified:** `safe_rel`/`safe_path` on every history and manifest path; symlinks in history refused (`seed_tasks.py:152`); mount-owned paths refused by name; no `shell=True`, no `source`/`eval` of variables; `stdin=DEVNULL` for test runs; atomic `grade.json`; ids only in `grade.json` (by inspection); `--network none --read-only --user uid:gid`; `no-secrets.sh` fail-closed when missing (bash exit 127 ≠ 0 → refused); SHA256SUMS for pr-14/pr-15 verified; `source.churn` schema rejects booleans and negatives.

## Cross-Model Security Observations

Envelope: `grimoires/loa/a2a/sprint-1/adversarial-audit.json` — primary gpt-5.5-pro (2 findings), companion claude-headless (9 findings, `DISS-C-*`), both voices succeeded.

| Finding | Triage |
|---------|--------|
| DISS-001 (HIGH) output-derived paths opened on host | Confirmed → HIGH-002 |
| DISS-002 (HIGH) claimed results accepted regardless of rc | Confirmed → HIGH-003 |
| DISS-C-001 (HIGH) forged summary / `os._exit(0)` full score | Confirmed → HIGH-003 |
| DISS-C-002 (MEDIUM) same rw tree reused across runs | Confirmed → MED-005 |
| DISS-C-003 (MEDIUM) `def_line`/`churn` unbounded reads, FIFO hang | Confirmed → HIGH-002 (paths) and MED-003 (size) |
| DISS-C-004 (MEDIUM) chmod follows symlinks | Confirmed by reproduction → MED-006 |
| DISS-C-005 (MEDIUM) no caps, SIGTERM-only timeout, orphan container | Confirmed by cross-model review → MED-001, MED-002 |
| DISS-C-006 (MEDIUM) host executor unguarded | Confirmed → MED-007 |
| DISS-C-007 (MEDIUM) quadratic CITE regex | Confirmed by timing → MED-008 |
| DISS-C-008 (LOW) `<out>.tmp` follows symlink | Plausible → LOW-003 |
| DISS-C-009 (LOW) credential roots allow-listed | Confirmed by cross-model review → LOW-002 |

## Rejected dissent payloads

None. `metadata.rejected_summary` is empty and the sidecar `grimoires/loa/a2a/sprint-1/adversarial-rejected-audit.jsonl` has 0 rows.

## Review cross-check

Review trailer: 0 critical, 3 high, 6 medium, 6 low, `excluded` 0 → `excluded_confirmed` 0 (nothing to confirm). Of the review's three highs: inert leak assertions → HIGH-001 (agree); `anchor_line` → HIGH-004 (agree); `BATS_BIN` → MED-012 (re-rated, still required).

---

## Rubric Scores

| Dimension | Score | Basis |
|-----------|-------|-------|
| SEC-IV Input Validation | 3 | strong on history/manifest paths; none on output-derived paths or agent text size |
| SEC-AZ Authorization | n/a | no principals |
| SEC-CI Confidentiality/Integrity | 3 | hidden suite isolated by design; verdicts/results forgeable from the sandbox |
| SEC-IN Injection Prevention | 4 | argv everywhere; no shell, no eval |
| SEC-AV Availability | 2 | no caps, SIGTERM-only timeout, unbounded reads, quadratic regex |
| ARCH-MO Modularity | 3 | `grade()` 98 lines, `load_task()` 100 |
| ARCH-RE Resilience | 3 | fail-closed on errors; one bad run stalls a batch |
| CQ-TC Test Coverage | 3 | broad suites; several key negations inert; grader suite host-bound |
| CQ-EH Error Handling | 3 | GradeError/exit codes clean; internal errors hide missing tools |
| CQ-DC Documentation | 4 | thorough headers; two statements contradict behaviour |
| DO-DS Deployment Safety | 3 | interpreter floor and bats path unchecked |

## Documentation Audit

No `documentation-coherence-*` reports exist in this workspace; verified manually. Headers match behaviour except: `ablation-grade.sh:96` ("anchor (and file:line)") vs HIGH-004; `seed-bugfix-tasks.sh:43-44` vs LOW-008; `ablation-grade.sh:77-81` describes host mode's environment but not its trust implication (MED-007). No secrets or internal URLs in docs or comments. The implementation report (`pr/PR.md`) has no AC walkthrough (review Observations §5).

## Security Checklist for This Sprint

- [x] No hardcoded secrets added (SHA256SUMS verified; both seeders run `no-secrets.sh`, fail-closed)
- [x] Input validation at trust boundaries for history/manifest paths
- [ ] Input validation for agent-output-derived paths — NO (HIGH-002)
- [ ] Measurement integrity against a gaming sandbox — NO (HIGH-003, MED-004, MED-005)
- [ ] Resource limits on untrusted code — NO (MED-001, MED-002, MED-003, MED-008)
- [x] No injection vectors (argv subprocesses, no eval/source)
- [ ] Tests cover security paths — the leak guard and ids-only checks cannot fail (HIGH-001, MED-013)
- [x] Error messages carry ids only in `grade.json`

---

## Next Steps

**CHANGES_REQUIRED:**
1. Fix HIGH-001/MED-013 (`run !` or `|| false`) and HIGH-004 (`anchor_line`) with the review's items.
2. Contain output-derived paths (HIGH-002) and stop trusting stdout alone (HIGH-003): `safe_rel` + `is_within` + regular-file + size cap; passed = 0 on parse failure; rc cross-check; static-case id match.
3. Harden the grading container (MED-001, MED-002): caps, `--cap-drop ALL`, `--name` + `docker kill`, `timeout -k`.
4. Re-run `prepare` before every suite run (MED-005); skip symlinks in `remove_path` (MED-006); cap agent text and copies (MED-003, MED-008).
5. Re-run `/review-sprint sprint-1` then `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":4,"medium":13,"low":10},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T18:03:40Z"} -->
