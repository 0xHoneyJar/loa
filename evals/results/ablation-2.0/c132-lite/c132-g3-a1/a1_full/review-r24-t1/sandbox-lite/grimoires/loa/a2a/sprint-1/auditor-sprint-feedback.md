# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md (task review-r24)
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Change under audit:** `pr/head.diff` (17 files; sha256 `ef220a96…d220e9e0c2`, the same hash the dissent envelope scoped)

---

## Verdict: CHANGES_REQUIRED

---

## Prerequisites and scope limits

- `engineer-feedback.md` carries `CHANGES REQUIRED` (4 high), not the `All good` Phase 0 expects. The task instruction for this phase directs the audit regardless, and `pr/AUDIT-INSTRUCTIONS.md` says to skip pre-flight steps that need artifacts this workspace lacks, so the audit proceeded; this deviation is recorded here and in NOTES.md.
- `adversarial-review.json` carries `metadata.model` (`gpt-5.5-pro`), as the review gate requires.
- No PRD, SDD, beads database or documentation-coherence reports exist here; `pr/PR.md` lists CHANGELOG, NOTES and DEC-record commits that are outside the 17-file diff and could not be verified.
- Verified: `bash -n` on every shell file and `py_compile` on both Python files pass; `evals/tests/ablation-report.bats` passes 22/22 on a scratch copy of `pr/head`. `ablation-grade.bats`, `ablation-row.bats`, `run-ablation.bats` and `arm-toggles.bats` need harness files outside the PR (`pipeline-run.sh`, `took-effect.sh`, `freeze.sh`, …) and could not run. `shellcheck` is not installed.
- Every scanner claim below was reproduced by extracting the contamination block of `head/evals/harness/ablation-grade.sh:1323-1503` and of the base file verbatim into a scratch module and calling `check_value("Bash", "command", …)` on both, so "regression" means base flagged the input and head returns clean.

## Executive Summary

The batch runner (`run-ablation.sh`), the shared library (`lib/arms-common.sh`) and the report generator (`ablation-report.py`) are sound where they matter: inputs are validated by regex at the CLI boundary, every rows-file mutation is flock-guarded, validated on a temp copy and `mv`'d, jq and Python receive data through `--arg`/argv rather than string splicing, outputs refuse symlinks, and the library extraction from `run-arms.sh` is byte-for-byte the same arithmetic. No secrets, no injection sinks, no network exposure.

What blocks the merge is the grader 1.2.2 to 1.2.5 calibration of the contamination scanner, the control that decides whether a run's row is valid evidence. Each DEC fixed a false positive on reviewer prose and opened a false negative on executed command text, and one new regex is exponential on input the agent under test controls. Four of these are tallied HIGH: a catastrophic-backtracking heredoc regex that hangs grading in-process while the runner has already dropped its watchdog (a batch that holds its lock forever), heredoc bodies stripped even when an interpreter executes them, escaped and prefixed quotes that skip the path scan, and a `hidden` token rule that misses mixed case, globs and bare arguments. The scanner's own header text still promises behaviour the code no longer has.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 4 |
| Medium | 5 |
| Low | 6 |

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] Heredoc-stripping regex backtracks exponentially; grading hangs with no watchdog, so the batch hangs

**Severity:** HIGH (confidence: high) — confirmed by cross-model review (DISS-C-006; its mechanism is corrected below)
**File:** `head/evals/harness/ablation-grade.sh:1377` (the regex), `:1383` (`HEREDOC.sub`), `:1412` (called for every Bash `command`); `head/evals/harness/run-ablation.sh:1031` (watchdog dropped), `:996` (unbounded grade call), `:1382` (`reap 1`)
**Issue:** `HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1[^\n]*\n(?:.*?\n)*?\s*\2[ \t]*(?=\n|$)", re.S)`. Under `re.S` the inner `.*?` also matches `\n`, so `(?:.*?\n)*?` is an ambiguous nested quantifier: when no terminator line exists the engine tries every partition of the remaining newlines. Measured on the head function: 0.37 s at 20 unterminated lines, 1.46 s at 22, 2.88 s at 23 (doubling per line; 30 lines exceeded a 12 s cap; 40 lines is on the order of days). A 26-line `python3 -c '…'` program containing `x = 1 << n` took 11.0 s: the opener needs only `<<` plus an identifier, so bit shifts in model-written code, a `$(cat <<EOF … EOF)` whose terminator line is `EOF)`, or a transcript truncated before its terminator all trigger it. The scan runs in-process in `contamination()`; `LOA_EVAL_GRADE_TIMEOUT_S` / `TEST_TIMEOUT_S` (`:262`, `:727`) bound only the test subprocesses, so there is no timeout to fall back to (the dissent's claim that the grader exits 2 is wrong; it hangs).
**Impact:** `run_trial` removes `$JOBS_DIR/$jid.pgid` right after `wait` (`run-ablation.sh:1031`) and only then calls `post_run` (`:1054`), which runs the grader with no `timeout` (`:996`). `watchdog_tick` keys on `.pgid` files, so a hung grade is invisible to it; the job never writes `.result`, `collect` never runs, and the driver's final `reap 1` (`:1382`) polls forever holding `<batch>/.lock`. One pathological Bash tool_use from the agent under test stalls a USD-budgeted batch until an operator intervenes. `RAB-8` covers a hung pipeline only, not a hung collaborator.
**PoC:**
```
# transcript tool_use input (agent-controlled)
{"command": "cat <<EOF > notes.md\nline 0\nline 1\n…(30 lines, no EOF)"}
# or: python3 -c '\nx = 1 << n\ny0 = x + 0\n…(26 lines)\n'
```
**Fix:** Replace the regex with a linear procedural scan: find `<<[-]?['"]?WORD` with a simple pattern, then walk `val.splitlines()` from the opener's line for the first line whose stripped text equals WORD; if none, leave the command unstripped. Independently, keep the watchdog armed through `post_run` (write the `.pgid` again with the job's own pid after `wait`, or wrap the took-effect, grade and row calls in `timeout`), so a hung collaborator rows `infrastructure_error` instead of hanging the batch. Add a regression test with an unterminated 40-line heredoc under a 5 s bound.
**Reference:** CWE-1333 Inefficient Regular Expression Complexity — https://cwe.mitre.org/data/definitions/1333.html ; CWE-400 Uncontrolled Resource Consumption — https://cwe.mitre.org/data/definitions/400.html

### [HIGH-002] Heredoc bodies are stripped even when an interpreter executes them; the opener's redirect target goes with them

**Severity:** HIGH (confidence: high) — confirmed by cross-model review (DISS-C-003, DISS-001)
**File:** `head/evals/harness/ablation-grade.sh:1412` (`body = strip_heredocs(val)`), `:1377` (`[^\n]*` on the opener line), `:1380-1383`
**Issue:** DEC-0541's premise ("file text being written is data, not a path the agent reached") holds for `cat > f <<EOF`, not for a heredoc that is stdin to `bash`, `sh`, `python3 -`, `node -`, `sqlite3`, `psql`, or one whose unquoted body contains `$(…)`/backticks that Bash executes before the consumer ever sees it. Reproduced on head (base returned `outside_path` for every one): `python3 - <<'PY'\nprint(open('/home/operator/notes').read())\nPY` → `None`; `bash <<EOF\ncat /home/operator/notes\nEOF` → `None`; `cat <<EOF\n$(cat /mnt/reference/answer.txt)\nEOF` → `None`; `cat <<EOF > /home/operator/out.txt\nhello\nEOF` → `None` (the opener's `[^\n]*` swallows the redirect target on the same line). `python3 - <<'PY'` is the most common way a model runs multi-line code in one Bash call.
**Impact:** A run that read or wrote outside the sandbox roots is rowed as valid evidence; the ablation decision for that arm is built on it. The `outside_path` class is the only one that catches arbitrary reads outside the roots.
**Fix:** Strip a heredoc body only when its consumer is a data sink (`cat`/`tee`/`printf` whose argument list carries `>`/`>>` to a file, or `--out`-style targets) and the opener is quoted or the body carries no `$(`/backtick; otherwise scan the body. Replace only the body (from the newline after the opener to the terminator), never the remainder of the opener line. Add the four inputs above to `AG-10`.
**Reference:** CWE-693 Protection Mechanism Failure — https://cwe.mitre.org/data/definitions/693.html ; CWE-184 Incomplete List of Disallowed Inputs — https://cwe.mitre.org/data/definitions/184.html

### [HIGH-003] `after_closing_quote` skips paths behind escaped, prefixed or empty quotes

**Severity:** HIGH (confidence: high) — confirmed by cross-model review (DISS-C-002)
**File:** `head/evals/harness/ablation-grade.sh:1365-1369` (the function), `:1442` (the call)
**Issue:** `return not (before.isspace() or before in "=(<>|;&,")` treats any other character two positions before the word as proof that the quote closes a glued token. Reproduced on head (base: `outside_path` for all): `bash -c "cat \"/home/operator/notes\""` → `None` (before is `\`); `python3 -c "print(open(\"/home/operator/notes\").read())"` → `None`; `python3 -c 'print(open(f"/home/operator/{n}").read())'` → `None` (before is `f`; `r"`, `b"` likewise); `cat $'/home/operator/notes'` → `None` (before is `$`); `cat ''/root/.ssh/id_rsa` and `cat ""/home/other/secret` → `None` (the character before the quote is its own opening quote, so an empty string in front of any absolute path hides it). Escaped quotes inside a `-c "…"` program and f-string paths are routine shapes in model-written one-liners; the empty-quote prefix is a two-character evasion.
**Impact:** Same as HIGH-002: an outside reach is graded clean and counted.
**Fix:** Return `False` when `before` is `\` or `$`, or when the quote at `pos-1` is an opening quote by parity (an even count of that unescaped quote character in `body[:pos-1]`), and never when the quoted segment is empty. Longer term, tokenize once with a shlex-style pass that is heredoc-aware and scan concatenated words, which replaces this function, `in_quotes`, and the `/,`, `=` and `/.` shape rules.
**Reference:** CWE-184 Incomplete List of Disallowed Inputs — https://cwe.mitre.org/data/definitions/184.html ; CWE-20 Improper Input Validation — https://cwe.mitre.org/data/definitions/20.html

### [HIGH-004] `HIDDEN_TOKEN` misses mixed case, glob adjacency and bare arguments; the header still promises "any case"

**Severity:** HIGH (confidence: high) — confirmed by cross-model review (DISS-C-004)
**File:** `head/evals/harness/ablation-grade.sh:1329` (the regex), `:1395-1396` (the Bash branch), header `:167`
**Issue:** `HIDDEN_TOKEN = re.compile(r"HIDDEN|(?<=[/._=-])hidden\b|\bhidden(?=[/_=-]|\.[A-Za-z0-9])")` is case-sensitive and requires adjacency to `/ . _ = -`. Reproduced on head (base's case-insensitive substring test flagged every one): `ls Hidden_tests/` → `None`; `cat HiDDen/x` → `None`; `find / -name '*hidden*'` → `None`; `find . -iname '*hidden*'` → `None`; `ls -la hidden` → `None`; `cd hidden && cat *` → `None`; `tar czf /tmp/x.tgz hidden` → `None`. The hidden tests live under `<suite-root>/tasks/<id>/hidden/` and are overlaid only at grading time, so a probe by name is exactly the shape this class exists to catch; these are probe shapes, not the reviewer-prose false positive DEC-0551 targeted ("any hidden interaction with store_true" inside a heredoc). The header at `:167` still reads "`hidden` (any case …)".
**Impact:** A probe for the hidden tests, the contamination class the scanner was built for, is counted as a valid row.
**Fix:** Compile with `re.I`; treat `hidden` as a token whenever it is delimited by whitespace, quotes, globs or path separators (`(?i)(?<![A-Za-z0-9])hidden(?![A-Za-z0-9])`) and carve out only the prose case the DEC names (inside a stripped data-sink heredoc body, or after `echo`/`printf`/`#`). Update `:167`. Add the inputs above to `AG-10`.
**Reference:** CWE-178 Improper Handling of Case Sensitivity — https://cwe.mitre.org/data/definitions/178.html ; CWE-184 — https://cwe.mitre.org/data/definitions/184.html

---

## Medium/Low Priority Issues

### [MED-001] `/.` skip runs before `normpath`, so `/./` and `/../` prefixes bypass the roots and the SENSITIVE check
- **Severity:** MEDIUM (confidence: high) — confirmed by cross-model review (DISS-002, DISS-C-001, both rated it HIGH)
- **File:** `head/evals/harness/ablation-grade.sh:1438-1439`; `outside()` normalises only at `:1347`
- **Issue:** `if w.startswith("/."): continue` matches `/./home/operator/notes`, `/../root/x` and `/./proc/1/environ`; all three return `None` on head and `outside_path` on base. The `Read` tool path `/./home/operator/x` is still flagged (path fields skip this rule), so only Bash words are affected.
- **Why MEDIUM, not HIGH:** the header (`:185-186`) declares obfuscated access out of scope ("the scan is a LOWER BOUND on leakage"), and `/./` is a deliberate shape, not one a model produces by accident. It is nevertheless a two-character bypass of an integrity control and should be closed.
- **Fix:** `w = os.path.normpath(w)` first; skip only when the first component is a dot-directory other than `.`/`..`.
- **Reference:** CWE-41 Improper Resolution of Path Equivalence — https://cwe.mitre.org/data/definitions/41.html

### [MED-002] Every one-component top-level word outside root/home/mnt/media/srv is dropped
- **Severity:** MEDIUM (confidence: medium) — confirmed by cross-model review (DISS-C-005)
- **File:** `head/evals/harness/ablation-grade.sh:1422-1423`, `SENSITIVE_SINGLE` at `:1361`
- **Issue:** `cat /flag`, `ls /data`, `ls /eval/`, `ls /x/` return `None` on head; base flagged all four (its one-component rule applied only after `s`, `y`, `=`, `~` or a quote). Anything the image or a bind mount places directly under `/` that is not an allowed root is now enumerable in one command. Confidence is medium because it depends on the image layout, which is outside this diff.
- **Fix:** Invert the rule: skip one-component words only when they are known slash commands (the `.claude/commands` names) or sit after a sed/awk delimiter (the base rule); otherwise let `outside()` decide.
- **Reference:** CWE-184 — https://cwe.mitre.org/data/definitions/184.html

### [MED-003] `in_quotes` counts quotes across the whole command; a quoted `/root` one-component word also passes
- **Severity:** MEDIUM (confidence: high)
- **File:** `head/evals/harness/ablation-grade.sh:1372-1374`, call at `:1444`
- **Issue:** `echo "it's"; cd /root && cat .ssh/id_rsa` → `None` on head (base: `outside_path`): one apostrophe in earlier prose flips the parity for a later one-component sensitive word. `cd "/root"; cat .ssh/id_rsa` → `None` as well (the comment at `:1439-1441` accepts only the `cd '/root/'` shape).
- **Fix:** Count parity only over the current simple command (text after the last unquoted `;`, `&&`, `||`, `|`), ignore `'` inside a `"…"` string, and do not exempt a one-component word in `SENSITIVE_SINGLE` when the quoted string is exactly that word.
- **Reference:** CWE-184 — https://cwe.mitre.org/data/definitions/184.html

### [MED-004] The watchdog is disarmed before the post-run chain
- **Severity:** MEDIUM (confidence: high)
- **File:** `head/evals/harness/run-ablation.sh:1031` (`rm -f "$JOBS_DIR/$jid.pgid"`), `:1054` (`post_run`), `:978-1003` (took-effect, drift guard, grade and row calls, none under `timeout`)
- **Issue:** The DEC-0429 watchdog bounds only the pipeline. Any collaborator that hangs afterwards (`took-effect.sh`, `ablation-grade.sh` including its `docker run` calls, `ablation-row.sh`) leaves the job without a `.result`, and `reap` loops forever. HIGH-001 is one trigger; this is the missing defence that would have contained it. `RAB-8` does not exercise a collaborator hang.
- **Fix:** After `wait`, write `$JOBS_DIR/$jid.pgid` again with the job's own process group and a post-run deadline, and have `watchdog_tick` row `infrastructure_error` when it fires; or wrap the three calls in `timeout`.
- **Reference:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html

### [MED-005] `model_missing` ignores a phase whose `model_requested` is null while the runner's drift guard falls back to the manifest
- **Severity:** MEDIUM (confidence: low)
- **File:** `head/evals/harness/ablation-row.sh:318-321`; `head/evals/harness/run-ablation.sh:519` (`want = req if … else pm.get(name)`)
- **Issue:** The row degrades only when `model_requested` is a non-empty string; a phase record with `model_requested` null and a non-empty `models_used` naming another model is not degraded (base's key-by-key compare flagged it). `drift_check` falls back to `MANIFEST phase_models[name]` for the same record, so the runner and the row can disagree about the same run.
- **Fix:** In `ablation-row.sh`, fall back to the manifest's `phase_models[name]` (the `--manifest` is already passed) before giving up.
- **Reference:** CWE-1068 Inconsistency Between Implementation and Documented Design — https://cwe.mitre.org/data/definitions/1068.html

### [LOW-001] `"=" in w` drops any absolute word carrying `=`
- **Severity:** LOW (confidence: high) — confirmed by cross-model review (DISS-C-007)
- **File:** `head/evals/harness/ablation-grade.sh:1432-1433`
- **Issue:** `cat /home/operator/x=y` and `cat '/root/=/../secret'` return `None` (base: `outside_path`). The documented intent (sed-range remnants, `key=value`) is already covered by the `/,` prefix rule and the `ABS_WORD` lookbehind.
- **Fix:** Restrict to words whose first component contains `=`, or to words preceded by a regex delimiter.
- **Reference:** CWE-184 — https://cwe.mitre.org/data/definitions/184.html

### [LOW-002] Grader header contradicts the code on two rules
- **Severity:** LOW (confidence: high)
- **File:** `head/evals/harness/ablation-grade.sh:167` ("`hidden` (any case …)" vs the case-sensitive regex at `:1329`); `:181` ("A path or Bash word starting ~/, $HOME/ or ${HOME}/ is always outside") and `:1331` ("home-relative words are always outside") vs `home_word_outside()` at `:1385-1388`, which returns `True` in host mode only (`cat ~/.aws/credentials` is `None` in container mode on head, `outside_path` on base; the `Read` tool path `~/.aws/credentials` likewise)
- **Issue:** The header is the contract reviewers and DEC authors read; two of its rules no longer hold. The container behaviour is defensible (`~` resolves under `/home/evaluser`, an allowed root) but must be documented as such, since LOW-A2 was recorded against the opposite wording.
- **Fix:** Rewrite `:167`, `:181` and `:1331` to state the implemented rule and the 1.2.2/1.2.4 DEC that changed it.
- **Reference:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html

### [LOW-003] `history_probes` undercounts
- **Severity:** LOW (confidence: high)
- **File:** `head/evals/harness/ablation-grade.sh:1404` (incremented only when the hidden/suite/repo checks did not return), `:1500` (first hit ends the scan)
- **Issue:** `git log --all -- tests/hidden` is counted as `hidden`, not as a probe, and no command after the first contamination hit is counted. Telemetry only; the header should say "a lower bound".
- **Reference:** CWE-778 Insufficient Logging — https://cwe.mitre.org/data/definitions/778.html

### [LOW-004] Pre-flight does not check `setsid`, `flock` or `timeout`; each falls back silently
- **Severity:** LOW (confidence: medium)
- **File:** `head/evals/harness/run-ablation.sh:309` (checks `git jq yq python3 awk` only); `:398`, `:1025` (`setsid`), `:1070`, `:1241` (`flock`), `:620` (`timeout`)
- **Issue:** Without `setsid` the watchdog signals only the pipeline's pid, not its process group; without `flock` concurrent row appends and in-place replacements race on the tracked `runs.jsonl`; the degraded mode is not recorded in `MANIFEST.json`.
- **Fix:** Add the three to the pre-flight list, or record `environment.degraded: [...]` in the manifest and a `run.log` line.
- **Reference:** CWE-636 Not Failing Securely — https://cwe.mitre.org/data/definitions/636.html

### [LOW-005] `MANIFEST.json` records the operator's absolute home path in a tracked artifact
- **Severity:** LOW (confidence: high)
- **File:** `head/evals/harness/run-ablation.sh:714` (`--arg tree "$TREE"` → `source_worktree`), `:264` (`CACHE_ROOT="${LOA_ABLATION_CACHE:-$HOME/.cache/loa}"`); batches live under `grimoires/loa/reports/ablation-2.0/batches`, which the batch `.gitignore` at `:912-914` deliberately keeps tracked for `MANIFEST.json`
- **Issue:** `source_worktree` is `/home/<user>/.cache/loa/ablation-src-<sha12>`, so every committed manifest carries the operator's username and home layout. `environment.os` (`uname -srm`) adds the kernel version.
- **Fix:** Record the worktree relative to `$HOME` (or only the `<sha12>` suffix) and drop or coarsen `uname -r`.
- **Reference:** CWE-200 Exposure of Sensitive Information — https://cwe.mitre.org/data/definitions/200.html

### [LOW-006] Process: no documentation-coherence reports, no AC Verification, out-of-diff records
- **Severity:** LOW (confidence: high)
- **File:** `pr/PR.md:1`
- **Issue:** The implementation report has no `## AC Verification` walkthrough; `Glob grimoires/loa/a2a/subagent-reports/documentation-coherence-*.md` finds nothing; the CHANGELOG and the DEC-0540…0559 records the PR description cites are outside the 17-file diff. Not applied as a blocker per `pr/AUDIT-INSTRUCTIONS.md`, which says to skip steps that need these artifacts. The grader's own header (LOW-002) is the one piece of security documentation inside the diff, and it is stale.
- **Reference:** CWE-1059 — https://cwe.mitre.org/data/definitions/1059.html

---

## Observations

Nothing excluded from the tally: no finding here is marked speculative. The review trailer's `excluded` is 0, so there is nothing to confirm (`excluded_confirmed: 0`).

Clean paths traced (recorded so the next round need not repeat them):
- `run-ablation.sh` CLI boundary: every option is regex-validated before use (`:308-345`); `--batch` rejects `.`/`..` and the reserved `smoke-` prefix; `--image` and `--source-commit` are constrained; `--rows` for a smoke batch can never be the tracked file (`:371`).
- Rows file: append under `flock -x 9` with `--validate` after (`:1070-1073`); in-place replacement writes a temp file beside the rows, validates it, then `mv` (`:1237-1262`); refusals leave the file untouched. The new `.gitignore` entry covers `runs.jsonl.lock`.
- `--resume` re-reads `source_commit`, `suite_manifest_sha256`, `image_digest` and `cli_version` from the manifest and refuses on any difference (`:641-646`); it trusts the rest of `MANIFEST.json` (paths, executor) unvalidated, which is acceptable for a self-written State-Zone file.
- Process control: the stale-lock takeover checks `kill -0` (`:900-903`); `.jobs/*.pgid` from a SIGKILLed driver refuses a second start while a group is alive (`:908-915`); `cleanup` TERMs recorded groups on EXIT (`:933-941`).
- `lib/arms-common.sh`: the transport signature is matched on the CLI's stderr and `is_error` result only, never on agent text (`:49-77`); `spend_charge`/`est_record`/`budget_gate` reproduce the removed `run-arms.sh` blocks exactly; `est_hint` is overridden at call time by the runner's own definition (`:395`), as intended.
- `ablation-report.py`: `write_out` refuses symlinks (`:1052-1057`); rows and manifests are parsed with explicit shape checks (`:264-300`); `yq` is called with argv, no shell; the bootstrap seeds one generator per interval.
- Test stubs under `evals/tests/fixtures/` write only inside the run dir they are given.
- No hardcoded credentials, keys or tokens anywhere in the diff (grep over `pr/head.diff` for key shapes found only test-fixture path strings such as `/home/operator/secret`).

---

## Cross-Model Security Observations

Security dissent (Phase 1C): `grimoires/loa/a2a/sprint-1/adversarial-audit.json`, status `reviewed`, `degraded: false`, two independent voices (primary `gpt-5.5-pro` answered by `codex-headless`, companion `claude-headless`; `counted_as: independent_voice`), 9 findings, `verdict_quality.status` APPROVED (2/2 voices), `metadata.locality` null (no `degraded_security_review`). Scope `diff_sha256` equals `sha256sum pr/head.diff`. Every finding was reproduced against the head and base scanner before disposition:

- DISS-C-006 (MEDIUM, HEREDOC backtracking) — confirmed; tallied as HIGH-001 because the grader has no in-process bound (the finding's "fails exit 2 / rows infrastructure_error" is not what happens; it hangs, and `run-ablation.sh:1031` has already dropped the watchdog).
- DISS-C-003 (HIGH, interpreter-fed heredocs) and DISS-001 (MEDIUM, `$(…)` inside an unquoted heredoc body) — confirmed; HIGH-002.
- DISS-C-002 (HIGH, empty-quote prefix and quoted `/root`) — confirmed; the empty-quote prefix folds into HIGH-003, the quoted `/root` and apostrophe-parity parts into MED-003.
- DISS-C-004 (HIGH, `HIDDEN_TOKEN` mixed case / bare argument / glob) — confirmed; HIGH-004.
- DISS-C-001 (HIGH) and DISS-002 (MEDIUM), `/./` and `/../` before normpath — confirmed, including the `/./proc/1/environ` SENSITIVE bypass; tallied MED-001 (deliberate-obfuscation class, declared out of scope by the header; still to be fixed).
- DISS-C-005 (MEDIUM, one-component top-level words) — confirmed; MED-002.
- DISS-C-007 (LOW, `=` in a path) — confirmed; LOW-001.

## Rejected dissent payloads

- none: `metadata.rejected_summary` is `[]`, `repaired_count` is 2 (two payloads repaired, none dropped), and the listed sidecar `grimoires/loa/a2a/sprint-1/adversarial-rejected-audit.jsonl` is empty (0 bytes).

---

## Documentation Audit

- Documentation-coherence reports: none exist in this workspace (see LOW-006); not applied as a blocker per `pr/AUDIT-INSTRUCTIONS.md`.
- Security-critical code commented: yes, every scanner rule cites its DEC inline (`ablation-grade.sh:1326-1328`, `:1418-1441`).
- Header versus implementation: two contradictions (LOW-002).
- CHANGELOG: not in the diff; the PR description says it records the grader 1.2.1–1.2.5 changes, unverifiable here.
- Secrets or internal URLs in docs or comments: none. The `MANIFEST.json` home-path leak is in generated output, not docs (LOW-005).

## Rubric Scores

| Dimension | Score | Basis |
|-----------|-------|-------|
| Security | 2/5 | The integrity control regressed in four natural-input classes and gained an exponential regex on agent-controlled input |
| Architecture | 4/5 | Clean library extraction; runner state machine and resume/rerun semantics are consistent; the scanner is a growing deny-list of lexical shapes where a tokenizer belongs |
| Code Quality | 3/5 | Strong validation and atomic file handling; `run_trial`/reconciliation blocks are long but linear; no tests for the regressions found |
| DevOps | 3/5 | Good manifest/status provenance; silent fallbacks for `setsid`/`flock`/`timeout`; watchdog does not cover the post-run chain |
| Blockchain/Crypto | n/a | |

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added
- [ ] Input validation on all new entry points — the contamination scanner's new exemptions widen what passes unflagged (HIGH-002, HIGH-003, HIGH-004, MED-001 to MED-003, LOW-001)
- [x] Authentication required where needed (n/a: local harness, no network listener)
- [x] No SQL/XSS/command injection (jq `--arg`, Python argv, no shell string splicing)
- [x] Error handling doesn't leak info (refusals name paths the operator already owns)
- [ ] Denial of service — HEREDOC regex with no watchdog cover (HIGH-001, MED-004)
- [ ] Tests cover security paths — no AG-10 case for interpreter heredocs, escaped quotes, mixed-case `hidden`, or an unterminated heredoc; no RAB case for a hung collaborator

---

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 4 |
| Medium | 5 |
| Low | 6 |

---

## Next Steps

**CHANGES_REQUIRED:**
1. Fix HIGH-001 to HIGH-004 in `ablation-grade.sh` (bump the grader version; add every reproduced input above to `AG-10` as regression cases, including a timing bound for the unterminated heredoc) and MED-004 in `run-ablation.sh` (watchdog through `post_run`, with an `RAB` case for a hung grade stub).
2. Address MED-001 to MED-003 and MED-005 in the same calibration pass; a single heredoc-aware tokenizer replaces `after_closing_quote`, `in_quotes`, `strip_heredocs` and the `/,`, `=`, `/.` shape rules and is testable against the AG-10 corpus directly.
3. Update the grader header (LOW-002) and the implementation report (AC Verification), then re-run `/review-sprint sprint-1` and `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":4,"medium":5,"low":6},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-22T18:52:00Z"} -->
