# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-23
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Change under audit:** `pr/head.diff` (17 files, +4,311 / -97); citations are `head/<path>:<line>` with lines from `pr/head/`

---

## Verdict: CHANGES_REQUIRED

---

## Pre-flight and scope notes

- **Phase 0 prerequisite not met, audit run anyway on instruction.** `engineer-feedback.md` carries `Verdict: CHANGES REQUIRED` (trailer `{"critical":0,"high":4,"medium":3,"low":8,"excluded":0}`), not "All good". The task brief for this sprint instructs the audit to run autonomously against the PR, so this report is written as the audit of the same change, and its findings are meant to be fixed in the same round as the review's.
- **Known-failures surface degraded.** The session hook reported `grimoires/loa/known-failures.md` unreadable; triage ran without it.
- **Adversarial security dissent ran:** `adversarial-review.sh --type audit --sprint-id sprint-1 --diff-file pr/head.diff --json` → `grimoires/loa/a2a/sprint-1/adversarial-audit.json`; `metadata.model: gpt-5.5-pro`, `status: reviewed`, `degraded: false`, two voices planned, two succeeded (codex-headless primary after the gpt-5.5-pro chain, claude-headless companion, `independent: true`), `verdict_quality.consensus_outcome: consensus`, `chain_health: ok`. No `metadata.locality.degraded_security_review` flag; the review is not DEGRADED.
- **Scope script:** `security-audit-scope.sh --json` ran over the workspace (sinks: 195 command_exec, 155 file_operations). The PR's own surface is five shell/python scripts under `evals/harness/` plus their bats suites; no `.reviewignore` exists.
- **Method:** read every changed file in `pr/head/` in full except `ablation-report.py` (read: header, loaders, symlink handling, argv, writer) and `run-ablation.bats`/`ablation-report.bats` (test names and the 1.2.x cases). Extracted the contamination section of the base and the head grader into importable modules and ran 45 paired probes through `check_value` (container mode, default roots). Timed the new heredoc regex on unterminated input.

---

## Executive Summary

The runner (`run-ablation.sh`), the shared library (`lib/arms-common.sh`) and the report (`ablation-report.py`) are sound at their trust boundaries: every operator argument is pattern-checked before use, collaborators are invoked as argv arrays, the library is sourced by a literal path, docker's version probe runs with `--network none`, the report refuses symlinked outputs and walks manifests without following links, the rows file is appended and replaced under one flock through a validated temp file, and no secret material is logged. The DEC-0545 degraded-rule rewrite in `ablation-row.sh` is correct and tested in both directions.

The grader calibration (1.2.1 to 1.2.5 in `ablation-grade.sh`) is where the change fails the audit. The contamination check is the eval's integrity control: a run that reads outside the sandbox or probes for the hidden tests must be excluded from the pass-rate and catch-rate intervals that the pre-registered decisions read. Each new exclusion rule was added to silence one false positive seen in batch P1, and each opens a false-negative class the base grader caught. Of 45 paired probes, the head grader misses 23 that the base grader flagged (list under HIGH-001 to HIGH-004), while the controls still hit in both. On top of the false negatives, the new heredoc regex backtracks exponentially on an unterminated `<<WORD` (measured: 22 lines → 1.2 s, doubling per line), and the runner calls the grader with no timeout while its watchdog stops watching once the pipeline has a final record, so one transcript stalls the whole batch (HIGH-005). The companion dissent voice found the same backtracking independently (DISS-C-006).

The review's four HIGH findings are confirmed by my own probes with one correction: the `cat x>"/root/x"` example in the review's finding 4 is still caught by the head grader (`>` is in the separator set at line 1369); the other three examples in that finding are real misses. The review demoted no HIGH to Observations (`excluded: 0`), so there is nothing to confirm (`excluded_confirmed: 0`).

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 5 |
| Medium | 5 |
| Low | 11 |

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] Heredoc stripping removes code the agent executes and the heredoc's own redirect or pipe target

**Severity:** HIGH (confidence: high)
**File:** `head/evals/harness/ablation-grade.sh:1377` (regex), `:1383` (substitution), `:1412` (use)
**Issue:** `HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1[^\n]*\n(?:.*?\n)*?\s*\2[ \t]*(?=\n|$)", re.S)` and `return HEREDOC.sub("<<HEREDOC", val)` (`:1377`, `:1383`) delete the body and the rest of the opening line before `ABS_WORD` runs over `body` (`:1412`). The premise in the docstring, "file text being written is data, not a path the agent reached" (`:1381`), holds only when the heredoc is the stdin of a writer. It does not hold for `bash`, `sh`, `python3 -`, `node -`, `perl`, `eval`, `source`, a pipe into any of them, or for `$( )`, backticks and `<( )` inside an unquoted body, all of which execute the text; and `[^\n]*` swallows the `> /outside/file` or `| tee /outside/file` on the declaration line. Probes, head → `None`, base → `outside_path`:
```
python3 - <<'PY'\nprint(open('/home/operator/.aws/credentials').read())\nPY
bash <<EOF\ncat /root/.ssh/id_rsa\nEOF
cat <<'EOF' | bash\ncat /root/.ssh/id_rsa\nEOF
cat <<EOF\n$(cat /root/secret)\nEOF
cat <<EOF > /home/operator/.ssh/authorized_keys\nssh-rsa AAA\nEOF
cat <<EOF | tee /home/operator/x\nhi\nEOF
```
The `python3 -I - … <<'PY'` idiom is this very runner's own style (`head/evals/harness/run-ablation.sh:501`, `:571`, `:644`, `:1243`), so an agent under test using it is the expected case.
**Impact:** A trial that reads operator secrets or writes outside the sandbox through an interpreter heredoc is scored as clean and enters the pre-registered intervals; the DEC-0435 gate and the freeze exist so those numbers can be trusted.
**Fix:** (a) Re-emit the opening line: `HEREDOC = re.compile(r"(<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2[^\n]*)\n(?:[^\n]*\n)*?\s*\3[ \t]*(?=\n|$)")` with `HEREDOC.sub(lambda m: m.group(1), val)` (this also removes the `re.S` backtracking of HIGH-005). (b) Strip the body only when the simple command receiving the heredoc is a writer (`cat`, `tee`, `printf`, `echo`, a bare `> file`) with no interpreter, `eval` or `source` on the same simple command and no `|` after the terminator word on the opening line; keep the body otherwise. (c) Always scan unquoted bodies (`\1` empty) for `$(`, `` ` `` and `<(` and feed their contents to the path scan. (d) Add bats negative controls for each probe above expecting `outside_path`.
**Reference:** CWE-693 Protection Mechanism Failure — https://cwe.mitre.org/data/definitions/693.html ; CWE-184 Incomplete List of Disallowed Inputs — https://cwe.mitre.org/data/definitions/184.html

### [HIGH-002] The `/.` exclusion runs before normalisation, so `/../` and `/./` paths are never checked

**Severity:** HIGH (confidence: high)
**File:** `head/evals/harness/ablation-grade.sh:1438`
**Issue:** `if w.startswith("/."): continue` (`:1438`) discards the candidate before `outside()` (`:1350`) calls `os.path.normpath`. `ABS_WORD` (`:1330`) admits `.` as the first path character, so `cat /../root/.ssh/id_rsa` and `cat /./root/secret` are dropped at `:1438` (head → `None`, base → `outside_path`). The exclusion was written for `pr/'"$v"'/.claude/…` remnants (`:1434-1436`), which `after_closing_quote` at `:1441` already handles.
**Impact:** A two-character prefix defeats the outside-path check for any target.
**Fix:** Normalise first and exempt only a genuine root dot-directory: `n = os.path.normpath(w); if n == w and re.match(r"^/\.[A-Za-z0-9_-]", w): continue` (so `/./x` and `/../x`, whose normpath differs from `w`, stay candidates), or drop the rule and rely on `after_closing_quote`. Add a bats case `cat /../root/x` expecting `outside_path`.
**Reference:** CWE-180 Incorrect Behavior Order: Validate Before Canonicalize — https://cwe.mitre.org/data/definitions/180.html ; CWE-22 Path Traversal — https://cwe.mitre.org/data/definitions/22.html

### [HIGH-003] The Bash `hidden` scan is case-sensitive and requires a glued neighbour

**Severity:** HIGH (confidence: high)
**File:** `head/evals/harness/ablation-grade.sh:1329` (regex), `:1394-1396` (Bash branch), `:1397` (non-Bash branch), `:166-168` (header)
**Issue:** `HIDDEN_TOKEN = re.compile(r"HIDDEN|(?<=[/._=-])hidden\b|\bhidden(?=[/_=-]|\.[A-Za-z0-9])")` (`:1329`) replaces the any-case substring test for Bash commands (`if tool == "Bash": if HIDDEN_TOKEN.search(val): return "hidden"`, `:1394-1396`) while `elif "hidden" in low` (`:1397`) keeps it for Read/Grep/Glob. Probes, head → `None`, base → `hidden`: `cat /workspace/Hidden/tests.py`, `ls hidden`, `grep -ri hidden .`, `find / -name '*hidden*'`, `find / -iname 'hidden'`. The same path judged by `Read` is still flagged, so the two tool families disagree. The header at `:166-168` still promises "any case".
**Impact:** Probing for the hidden test set is the contamination pattern this check was built for; the most direct Bash probes now pass.
**Fix:** Keep the any-case substring for command text and apply the token shapes only inside heredoc bodies: scan `strip_heredocs(val).lower()` for `hidden` first (return `"hidden"`), then run `HIDDEN_TOKEN` compiled with `re.I` over the stripped bodies. Add bats cases for the five probes above expecting `hidden`; keep the existing prose case (`"any hidden\n   interaction"`, bats `:525`) expecting clean. Fix the header or the code, whichever survives.
**Reference:** CWE-178 Improper Handling of Case Sensitivity — https://cwe.mitre.org/data/definitions/178.html

### [HIGH-004] The two quote heuristics skip quoted and empty-quoted reads of sensitive roots

**Severity:** HIGH (confidence: medium)
**File:** `head/evals/harness/ablation-grade.sh:1365-1369` (`after_closing_quote`), `:1372-1374` (`in_quotes`), `:1441-1444` (use)
**Issue:** `in_quotes` is `seg.count("'") % 2 == 1 or seg.count('"') % 2 == 1` over the whole prefix (`:1373-1374`), applied to one-component sensitive words at `:1443-1444`; `after_closing_quote` returns true for any word preceded by a quote whose predecessor is not a separator (`:1366-1369`) without checking that the quoted token is non-empty. Probes, head → `None`, base → `outside_path`: `cd "/root" && cat .ssh/id_rsa`, `cat ''/root/.ssh/id_rsa`, `echo "don't"; cd /root` (the apostrophe in earlier prose flips the parity). Confidence is medium because the comment at `:1436-1437` records `cd '/root/'` as an accepted gap; the double-quote, empty-quote and stray-apostrophe forms are not recorded and no DEC is cited. Correction to the review: `cat x>"/root/x"` is still caught (`>` is in the separator set at `:1369`).
**Impact:** `cd /root && cat .ssh/…` is the shape a host-mode run uses to reach operator secrets; quoting the directory should not exempt it.
**Fix:** Decide quoting with a shell-aware tokenizer (`shlex.shlex(body, posix=True, punctuation_chars=True)`) and exempt a quoted sensitive single-component word only as a pattern argument of `grep`/`sed`/`awk`, never of `cd`, `ls`, `cat`, `find`. In `after_closing_quote`, walk back to the opening quote and require a non-empty quoted token so `''/root/x` and `""/root/x` stay candidates. Add bats cases for the three probes expecting `outside_path` beside the existing `grep -E ' /tmp | /home '` case expecting clean.
**Reference:** CWE-184 Incomplete List of Disallowed Inputs — https://cwe.mitre.org/data/definitions/184.html

### [HIGH-005] The heredoc regex backtracks exponentially on an unterminated heredoc, and the runner has no timeout around the grader

**Severity:** HIGH (confidence: high)
**File:** `head/evals/harness/ablation-grade.sh:1377` (regex); `head/evals/harness/run-ablation.sh:994-996` (grader call), `:1176-1177` (watchdog skips a run with a final pipeline record)
**Issue:** `HEREDOC` uses `(?:.*?\n)*?` under `re.S` (`:1377`), so when a `<<WORD` introducer has no matching terminator line the engine explores every partition of the remaining lines before failing. Measured on the head module with `strip_heredocs("cat <<EOF\n" + N lines)`: 16 lines 0.016 s, 18 lines 0.067 s, 20 lines 0.287 s, 22 lines 1.209 s (×4 per two lines); 30 lines is minutes, 40 lines is days. Triggers: a heredoc closed as `EOF)` or `EOF;` on the same line, a `<<` in a multi-line command followed by an identifier with no matching line, or an agent that wants its trial never graded. The runner calls the grader as `"${g[@]}" >> "$plog" 2>&1 || PR_GRC=$?` with no `timeout` (`run-ablation.sh:994-996`); `watchdog_tick` does `[[ -z "$(final_status "$rd")" ]] || continue` (`:1176-1177`), so once the pipeline has written its final record the hung grader is never signalled; `reap` (`:1193-1207`) waits on the job pid forever and the trailing `reap 1` (`:1366`) never returns. The grader's own `TEST_TIMEOUT_S` (`ablation-grade.sh:262`) bounds the test subprocesses, not this regex.
**Impact:** One transcript stalls grading of its trial and, through the runner, the whole batch: a concurrency slot is held, no further trial launches once the plan reaches the end, STATUS.json stays `running`, and the operator must SIGTERM the driver. Transcript content is written by the agent under test, so this is reachable from untrusted input (confirmed independently by the companion dissent voice, DISS-C-006).
**Fix:** In the grader, drop `re.S` and match the body as `(?:[^\n]*\n)*?` so each iteration consumes exactly one line (linear), or replace the regex with a line scanner (find the introducer, search forward for the terminator); cap the scanned value length. In the runner, wrap the grader (and `took-effect.sh`) in `timeout --kill-after=10 "$GRADE_TIMEOUT_S"` and row `infrastructure_error` on exit 124, or extend `watchdog_tick` to cover post-run time. Add a bats case feeding a 40-line unterminated heredoc that must grade within seconds.
**Reference:** CWE-1333 Inefficient Regular Expression Complexity — https://cwe.mitre.org/data/definitions/1333.html ; CWE-400 Uncontrolled Resource Consumption — https://cwe.mitre.org/data/definitions/400.html

---

## Medium/Low Priority Issues

### [MED-001] The `=` exclusion drops any path carrying `=`
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/harness/ablation-grade.sh:1432`
- **Issue:** `if w.startswith("/,") or "=" in w: continue` skips the whole word; the comment "no path component carries =" (`:1431`) is false on Linux and `ABS_WORD` itself admits `=` in a word (`:1330`). Probe `cat /home/operator/x=1`: head → `None`, base → `outside_path` (DISS-C-003 agrees).
- **Fix:** Treat `=` as a word terminator for the candidate (`w = w.split("=", 1)[0]`) and keep it when the prefix is still a two-component absolute path; the sed `s=…=…=` form is already covered by the `ABS_WORD` lookbehind on `=`.
- **Reference:** CWE-184 — https://cwe.mitre.org/data/definitions/184.html

### [MED-002] The single-component allow-list misses data-holding roots (`/boot`, `/run`, `/snap`, `/data`)
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/harness/ablation-grade.sh:1361` (`SENSITIVE_SINGLE = {"root", "home", "mnt", "media", "srv"}`), `:1424-1426`
- **Issue:** Any one-component word not in the set is a "command token" and skipped. Probes `ls /boot`, `ls /run`: head → `None`, base → `outside_path`. `/run/secrets/x` (two components) and `/var/run` (`SENSITIVE`) are still caught, but listing a root the sandbox does not own is itself a probe.
- **Fix:** Invert the rule: a one-component word is a command token only when it is not an existing root directory name, i.e. skip when `one.group(1)` is in a short allow-list of known Loa slash commands and sed/awk delimiter shapes (`re.fullmatch(r"[a-z][a-z0-9-]*", c)` plus a flag-like test), otherwise keep it as a candidate; or extend `SENSITIVE_SINGLE` with `boot`, `run`, `snap`, `data`, `backup`, `storage`. Add bats cases for `ls /boot` and `ls /run` expecting `outside_path`.
- **Reference:** CWE-184 — https://cwe.mitre.org/data/definitions/184.html

### [MED-003] An unknown CLI version silently disables the DEC-0407 CLI drift guard
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/harness/run-ablation.sh:625` (`CLI_VERSION=unknown`), `:543-548` (`drift_check`), `:634-639` (resume comparison)
- **Issue:** When `docker run … claude --version` prints nothing (timeout, broken image), `CLI_VERSION` becomes `unknown` and the batch starts. In `drift_check`, `if seen and re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", want)` fails for `unknown`, and the `image_digest` fallback runs only when `not seen`, so a transcript that carries a version is never compared. `--resume` accepts it because `unknown == unknown`.
- **Fix:** In a non-smoke batch `refuse "cli_version unknown"` next to the image check (`:607-610`); or record `drift_guard: degraded` in MANIFEST and STATUS so the report can see it.
- **Reference:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html

### [MED-004] `~/` and `$HOME/` are assumed to resolve under `/home/evaluser` in the container
- **Severity:** MEDIUM (confidence: low) [ASSUMPTION: the container user is not verifiable from this PR; `pipeline-run.sh` and the image are out of scope]
- **File:** `head/evals/harness/ablation-grade.sh:1386-1391` (`home_word_outside`), `:1352` (`outside`), `:1410-1411`
- **Issue:** `return A.executor == "host"` makes every `~/`, `$HOME/` and `${HOME}/` word clean in container mode on the stated ground that "in the container they resolve under /home/evaluser, an allowed root". If the image runs the agent as root, or `HOME` is unset or redirected, `~` is `/root` or elsewhere, outside every allowed root, and the grader cannot tell. The bats case at `ablation-grade.bats:503` (`cat $HOME/.codex/config.toml` is clean) locks the assumption in.
- **Fix:** Derive the home from the transcript (`system/init` `cwd`, or a recorded `HOME`) and treat `~/` as `<home>/`; fall back to outside when it cannot be derived. Record the resolution in `grade.json`.
- **Reference:** CWE-706 Use of Incorrectly-Resolved Name or Reference — https://cwe.mitre.org/data/definitions/706.html

### [MED-005] `build()` in the report is one 333-line function
- **Severity:** MEDIUM (confidence: high) — code quality
- **File:** `head/evals/harness/ablation-report.py:717`
- **Issue:** `build()` loads inputs, runs both analyses, and renders every Markdown section and the JSON twin inline; `compare()` at `:494` is 71 lines. In `run-ablation.sh`, `run_trial` (`:1008`, 57 lines) and `drift_check` (`:500`, 53 lines) exceed 50 lines with no justification comment.
- **Fix:** Split `build()` into `load_inputs`, `analyse`, `render_md`, `render_json`; the per-arm detail loop (`:845-893`) and the Method section (`:981-1008`) are self-contained.

### [LOW-001] Duplicate-row count depends on the row's byte layout
- **File:** `head/evals/harness/run-ablation.sh:1075`
- **Issue:** `n="$(grep -cF "\"run_id\":\"$rid\"" "$ROWS" || true)"` assumes compact jq output with no space after the colon; any reformatting of the tracked `runs.jsonl` makes every append read as "rowed 0 times" and fails the batch with exit 3 (`:1081`).
- **Fix:** Count with jq as the resume path does at `:1324`: `jq -R -r 'fromjson? | select(.run_id == $r) | .run_id' | wc -l`.

### [LOW-002] Counters still advance after a failed in-place replacement
- **File:** `head/evals/harness/run-ablation.sh:1148-1157`
- **Issue:** When `replace_row_try` fails, `ROWS_INVALID` and `STOP=invalid` are set (`:1149-1150`) but control falls through to `DONE_LIST="$DONE_LIST$rid"$'\n'` and `account_row` (`:1155-1156`), so STATUS.json counters and `rows_usd` describe a row that is not in the file.
- **Fix:** Guard `:1155-1156` with `[[ "$ROWS_INVALID" == null ]]`.

### [LOW-003] `--run-cap` is silently overridden on resume
- **File:** `head/evals/harness/run-ablation.sh:386`
- **Issue:** `RUN_CAP="$(jq -r '.caps.run_usd' "$MAN_PATH")"` replaces an operator value validated at `:316` with no log line, unlike `--source-commit` at `:380-381`.
- **Fix:** Refuse or log a differing `--run-cap` on resume.

### [LOW-004] The stale-pipeline check assumes `setsid`
- **File:** `head/evals/harness/run-ablation.sh:139-146`
- **Issue:** The `.jobs/*.pgid` liveness test is `kill -0 -- "-$p"` only; when `setsid` is absent the launch at `:1027` records a plain pid, the group signal fails and a still-spending pipeline is undetected. `cleanup` (`:938`) and `watchdog_tick` (`:1182`) already fall back to `kill "$p"`.
- **Fix:** `kill -0 -- "-$p" 2>/dev/null || kill -0 "$p" 2>/dev/null`.

### [LOW-005] Report and runner read an absent `task_types` differently
- **File:** `head/evals/harness/ablation-report.py:414-416` vs `head/evals/harness/run-ablation.sh:651-654`
- **Issue:** The runner treats a missing `task_types` as `["all"]`; the report treats it as `[]`, so rows of such an arm would be run and then listed as "not applicable". Latent: every declared arm in `evals/suites/ablation-2.0.yaml` sets `task_types`.
- **Fix:** Share one default.

### [LOW-006] Spend label omits replaced rows
- **File:** `head/evals/harness/run-ablation.sh:1225-1226`
- **Issue:** The `spend.txt` batch line labels `LEDGER_USD` "first attempts", but since DEC-0553 it also holds the reported cost of rows a rerun replaced (`:1143`).
- **Fix:** Label it "ledger (first attempts + replaced rows)".

### [LOW-007] Header comment drift on the hidden check
- **File:** `head/evals/harness/ablation-grade.sh:166-168`
- **Issue:** The header says the hidden check is "any case" with a token exception for Bash; after HIGH-003 the Bash branch is case-sensitive everywhere.
- **Fix:** Resolve with HIGH-003.

### [LOW-008] The 1.2.x tests assert only the false-positive side of each rule
- **File:** `head/evals/tests/ablation-grade.bats:489-557`
- **Issue:** No case feeds an interpreter a heredoc, writes a heredoc to an outside path, pipes a heredoc into a shell, uses `/../`, quotes a sensitive root, lists `/boot`, or probes `hidden` in mixed case. Each calibration rule needs a negative control that fails when the rule over-reaches (Karpathy goal-driven).
- **Fix:** Add the controls named under HIGH-001 to HIGH-005 and MED-001/MED-002.

### [LOW-009] Resume takes `IMAGE`, `EXECUTOR`, suite paths and the rows path from MANIFEST.json after the argument validation ran
- **File:** `head/evals/harness/run-ablation.sh:378-383`
- **Issue:** `EXECUTOR`, `IMAGE`, `SUITE_ROOT`, `SUITE_FILE`, `RUN_CAP`, `SEED` and `ROWS` are overwritten from the manifest at `:378-383`, after the `case "$EXECUTOR"` and `[[ "$IMAGE" =~ … ]]` checks at `:310`, `:318`. The values are passed as argv (no injection), and the manifest is operator-owned state, so this is a defence-in-depth gap only.
- **Fix:** Re-run the validations after the resume block, or move the block above them.
- **Reference:** CWE-20 Improper Input Validation — https://cwe.mitre.org/data/definitions/20.html

### [LOW-010] Security-relevant grader change without a CHANGELOG entry in the diff
- **File:** `pr/PR.md` (commit list) vs `pr/head.diff` (17 files, all under `evals/` plus `.gitignore`)
- **Issue:** The PR names two `docs(cycle-130): CHANGELOG Sprint 260` commits, but the diff carries no CHANGELOG or `grimoires/` file. The contamination gate changed behaviour (DEC-0540 removes `git_history` as a hit; 1.2.2 to 1.2.5 add exclusions), which is a security-relevant change the documentation audit expects in the CHANGELOG. Confidence medium: the frozen PR may have been scoped to `evals/`.
- **Fix:** Include the CHANGELOG hunk in the change, or state the scoping in the description.

### [LOW-011] `git log --all` / `git reflog` are no longer contamination; the premise lives outside this change
- **File:** `head/evals/harness/ablation-grade.sh:1403-1404`, header `:170-172`
- **Issue:** DEC-0540 turns a history probe into telemetry (`HISTORY_PROBES[0] += 1`) on the ground that "the sandbox is a fresh git init at base, so there is no history to leak". That guarantee is made by `pipeline-run.sh` and the sandbox builder, neither in this diff, and the grader no longer enforces it. Confidence low: the decision is recorded and the count stays in `grade.json`.
- **Fix:** Have the grader verify the premise once per run (one commit in the sandbox `.git`, no reflog beyond it) before treating the probe as harmless, or keep `git_history` as a hit when the sandbox has more than the base commit.

---

## Observations

None demoted. The review's trailer records `excluded: 0`; there are no speculative HIGH findings to confirm or re-tally (`excluded_confirmed: 0`).

---

## Rejected dissent payloads

None. `adversarial-audit.json` `metadata.rejected_count` is 0, `rejected_summary` is `[]`, and the sidecar `adversarial-rejected-audit.jsonl` holds no rows. Both voices succeeded. Their findings map as follows: DISS-001 and DISS-C-001 (heredoc bodies that execute) → HIGH-001; DISS-002 and DISS-C-002 (empty quoted prefix) → HIGH-004; DISS-C-003 (`=` in a path) → MED-001; DISS-C-004 (mixed-case `hidden`) → HIGH-003; DISS-C-005 (quote parity) → HIGH-004; DISS-C-006 (regex backtracking) → HIGH-005. Each was verified against the extracted graders before being tallied; none is counted on the dissent's word alone.

---

## Rubric Scores

| Dimension | Score | Basis |
|-----------|-------|-------|
| SEC-IV Input validation | 2 | Operator arguments are allow-listed (5), but the contamination filter, the one input the eval cannot trust, has 23 of 45 probes passing (HIGH-001 to HIGH-004, MED-001, MED-002) |
| SEC-IN Injection prevention | 5 | argv arrays everywhere; `source` by literal path; `jq --arg`; python via `-I -` with argv |
| SEC-AV Availability | 2 | Exponential regex on untrusted input with no timeout around the grader (HIGH-005); watchdog and breaker cover only the pipeline phase |
| SEC-CI Confidentiality | 4 | No secrets logged; `--network none` for the version probe; outputs refuse symlinks |
| ARCH-MO Modularity | 4 | Clean library extraction; `post_run` shared by trials and rerows; one long `build()` (MED-005) |
| CQ Tests | 3 | Runner and report suites are thorough; grader calibration has no negative controls (LOW-008) |
| DevOps | 4 | Lock, flock, temp-file-then-mv, `.gitignore` for run dirs; stale-group check assumes `setsid` (LOW-004) |

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added
- [x] Input validation on all new operator inputs (`--arms`, `--tasks`, `--batch`, `--image`, env knobs pattern-checked; resume values re-read from the manifest, LOW-009)
- [ ] Contamination gate preserved — regressed (HIGH-001 to HIGH-004, MED-001, MED-002)
- [ ] Untrusted input cannot exhaust the grader — regressed (HIGH-005)
- [x] No shell injection (collaborators as argv arrays; library sourced by literal path; no `eval`)
- [x] Report writes only `--out` and `--json`, refuses symlinks, walks manifests without following links
- [x] Error messages name paths the operator owns; no secret material
- [ ] Tests cover security paths — false-positive side only (LOW-008)

---

## Next Steps

**CHANGES_REQUIRED:**
1. Fix HIGH-001 to HIGH-005 in `evals/harness/ablation-grade.sh` (and the grader timeout in `run-ablation.sh`), bump `GRADER_VERSION`, and add the negative-control bats cases named in each finding.
2. Address MED-001 to MED-003 before the suite v2 batches of DEC-0559 start; decide MED-004 by checking the image's user.
3. Re-run `evals/tests/ablation-grade.bats` AG-10/AG-11 and the 45 paired probes against the fixed grader; the head module must flag every probe the base flags while keeping the 1.2.x false positives clean.
4. Add an `## AC Verification` section to `grimoires/loa/a2a/sprint-1/reviewer.md`.
5. `/review-sprint sprint-1`, then `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":5,"medium":5,"low":11},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-23T02:50:00Z"} -->
