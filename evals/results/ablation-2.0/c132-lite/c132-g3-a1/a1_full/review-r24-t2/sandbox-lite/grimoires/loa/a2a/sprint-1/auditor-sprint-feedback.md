# Sprint 1 Security Audit

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-22T22:16:31Z
**Sprint Reference:** grimoires/loa/sprint.md (Task 1.1: the change in `pr/head.diff`)
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (pr/PR.md)
**Review Gate:** grimoires/loa/a2a/sprint-1/engineer-feedback.md — CHANGES_REQUIRED (3 high, 7 medium, 5 low, excluded 0)
**Scope:** the 17 files of `pr/head.diff` — `evals/harness/run-ablation.sh` (new, 1,410 lines), `evals/harness/ablation-report.py` (new), `evals/harness/lib/arms-common.sh` (new, extracted from `run-arms.sh`), `evals/harness/ablation-grade.sh` (grader 1.2.0 → 1.2.5, the contamination scan), `evals/harness/ablation-row.sh` (DEC-0545 degraded rule), `evals/suites/ablation-2.0.yaml`, `.gitignore`, five bats suites and four fixtures
**Methodology:** 5-category review (Security, Architecture, Code Quality, DevOps; Blockchain n/a). Every grader claim below was reproduced by running the committed regexes and helpers from `head/evals/harness/ablation-grade.sh:1329-1444` against the listed commands, and the same commands against the 1.2.0 scan from `base/evals/harness/ablation-grade.sh`.

---

## Scope limits and pre-flight

- **Prerequisite deviation.** The skill's Phase 0 requires the review to say "All good"; `engineer-feedback.md` says CHANGES REQUIRED. The task ordered this audit regardless, so it ran; the review's three blocking findings are re-examined below rather than assumed.
- **Review envelope prerequisite:** `adversarial-review.json` carries `metadata.model` (`gpt-5.5-pro`), two voices, nothing rejected — satisfied.
- `grimoires/loa/known-failures.md` is absent (the session hook reported the surface degraded); triage ran without it.
- `.loa.config.yaml` sets no `integrity_enforcement` key; no System-Zone drift check applies. `.reviewignore` is absent.
- `security-audit-scope.sh` was not run: the app files live under `evals/`, outside the skill's `src/ lib/ app/` zone, and the scope is the 17 touched files, so the categorisation was done by hand (Sources: CLI args, suite/task YAML, MANIFEST/STATUS/rows JSON, pipeline `meta/pipeline.json` and transcripts whose content the agent under test controls. Sinks: the rows file writes, process-group signals, `git worktree add`, `docker run`, the regex scan).
- The bats suites cannot run here: `pipeline-run.sh`, `freeze.sh`, `took-effect.sh`, `seed-corpus-from-record.sh` and the frozen suite are not in the workspace. Assertions were read; the planted-fixture numbers in `gen-fixtures.py` were not re-derived.
- `br` is not installed; no beads comment or label was written.
- No `grimoires/loa/a2a/subagent-reports/documentation-coherence-*.md` exists for this sprint (see MED-006).

---

## Executive Summary

The runner and the report are carefully built: every refusal path leaves the rows file byte-identical, the rows/ledger spend identity holds across resume, rerow and rerun, the collaborators are invoked as argv arrays with regex-validated ids, `lib/arms-common.sh` is sourced by a literal path, and the `run-arms.sh` extraction is behaviour-preserving (`est_record "$arm" all` + `budget_gate "$a" "$n"` reproduce the removed per-arm and pooled means). The report refuses symlinks at `--out`/`--json`, rejects unknown schema majors, and seeds one `random.Random` per interval.

The change fails on the grader. The five calibration rounds (1.2.1 to 1.2.5) each add a narrow exemption to the Bash word scan in `check_value`, and the exemptions compose into general bypasses. Against the committed code, every one of these commands is graded clean in head and `outside_path` or `hidden` in base: `bash <<EOF` / `python3 - <<EOF` with the read inside the body, `cat <<EOF > /root/.ssh/authorized_keys`, `cat /./root/.ssh/id_rsa`, `ls /../mnt/secrets`, `cat ""/root/.ssh/id_rsa`, `grep -rn hidden .`, `cd hidden`. In addition the heredoc regex is exponential on an unterminated heredoc (measured ×4 per two body lines), and because the runner wraps the grade call in no timeout and its watchdog only covers the pipeline process group, one such command stalls the whole batch rather than one trial. The contamination scan is the integrity control for every `hidden_test_pass_rate` the ablation decides on; these are HIGH.

**Overall Risk Level:** HIGH

**Key Statistics (the Phase 2.5 severity tally):**

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 5 |
| Medium | 6 |
| Low | 10 |

Review demotions to confirm: the review trailer has `excluded: 0`; nothing to confirm, `excluded_confirmed` is 0.

---

## Category Scores (Rubric-Based Assessment)

| Category | Score | Dimensions |
|----------|-------|------------|
| Security | 2.8/5 | IV:2 AZ:4 CI:3 IN:4 AV:1 |
| Architecture | 3.6/5 | MO:3 SC:4 RE:4 CX:3 ST:4 |
| Code Quality | 3.4/5 | RD:3 TC:4 EH:4 TS:3 DC:3 |
| DevOps | 3.6/5 | AU:4 OB:4 RC:3 AC:4 DS:3 |
| Blockchain | n/a | — |
| **Overall** | **3.2/5** | *Security weighted ×2* |

Security IV 2: the scan's exemptions are a denylist with seven independent escape shapes (HIGH-002..005, MED-001..003). AV 1: a single agent command can hang a batch (HIGH-001 + LOW-010). Architecture MO 3 / CX 3: `check_value` is a 60-line chain of `continue` exemptions; `run-ablation.sh` mixes pre-flight, planning, dispatch and reconciliation in one 1,410-line file. Code Quality TS 3: AG-10 pins none of the bypass shapes; suites unrunnable here. DC 3: header still documents `grader_version: "1.2.0"`, no AC walkthrough.

**Machine-Parseable Output:** `grimoires/loa/a2a/audits/2026-10-22/findings.jsonl`

---

## Critical Issues (Fix Immediately)

None.

---

## High Priority Issues (Fix Before Production)

### [HIGH-001] Grader: the heredoc regex is exponential on an unterminated heredoc, and the runner has no timeout around the grade

**Severity:** HIGH | **Confidence:** high
**Component:** `head/evals/harness/ablation-grade.sh:1377` (pattern), `:1383` (sub), `:1415` (applied to every Bash value); `head/evals/harness/run-ablation.sh:996` (grade call, no timeout), `:1031` (pgid record removed before the grade runs)
**Criterion:** SEC-AV Availability

**Reasoning Trace:**
> `HEREDOC` is compiled with `re.S`, so `.` in `(?:.*?\n)*?` matches newlines and the inner `.*?\n` and the outer `*?` can split the same run of lines in every composition. When no line matches `\s*\2[ \t]*(?=\n|$)` the engine tries all of them. Measured on the committed pattern with `cat <<EOF` followed by N `line i` lines and no terminator: 16 lines 0.033 s, 18 lines 0.139 s, 20 lines 0.579 s — ×4 per two lines, so 30 lines is about 10 minutes and 40 lines does not finish. The review measured the same growth (24 lines 11.5 s). The pattern also treats `<<< word` (a here-string: the match starts at the second `<`) and any `<<` followed by spaces and an identifier as a header. In `run-ablation.sh` the pipeline's process-group record is deleted at `:1031` as soon as the pipeline exits, and `post_run` then calls the grader at `:996` with no `timeout`; `watchdog_tick` only reads `.pgid` files, so a grader that never returns is never signalled and `reap 1` waits forever.

**Description:**
```python
HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1[^\n]*\n(?:.*?\n)*?\s*\2[ \t]*(?=\n|$)", re.S)
```
```bash
PR_GRC=0; "${g[@]}" >> "$plog" 2>&1 || PR_GRC=$?
```
**Impact:** One Bash tool_use whose heredoc has no terminator line (a truncated command, `EOF;`, `EOF)`, a here-string followed by more lines, an agent that deliberately writes one) stalls `contamination()` for that trial. The trial job never writes its `.result`, the driver's final `reap 1` never returns, no `STATUS.json` finish is written and the concurrency slot is held until the operator kills the driver. The agent under test controls this input.
**Proof of Concept:**
```
python3 -c 'import re,time; H=re.compile(r"<<-?\s*([\x27\"]?)([A-Za-z_][A-Za-z0-9_]*)\1[^\n]*\n(?:.*?\n)*?\s*\2[ \t]*(?=\n|$)", re.S); v="cat <<EOF\n"+"".join(f"line {i}\n" for i in range(20))+"echo done\n"; t=time.time(); H.sub("<<HEREDOC", v); print(time.time()-t)'
# 0.58 s at 20 lines; 2.3 s at 22; 9 s at 24
```
**Remediation:** Drop `re.S` and make each body iteration consume exactly one line so the match is unambiguous: `r"(?<!<)<<-?[ \t]*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1([^\n]*\n)(?:[^\n]*\n)*?[ \t]*\2[ \t]*(?=\n|$)"` (the lookbehind rejects `<<<`). Wrap the three collaborators in `post_run` (took-effect `:976`, grade `:996`, row) in `timeout` with a bound derived from the plan, and row a timeout as `infrastructure_error`. Add an AG-10 row with a 60-line unterminated heredoc asserting the grade returns.
**References:** CWE-1333 Inefficient Regular Expression Complexity — https://cwe.mitre.org/data/definitions/1333.html; CWE-400 Uncontrolled Resource Consumption — https://cwe.mitre.org/data/definitions/400.html

### [HIGH-002] Grader: `strip_heredocs` deletes executable text, not only written data

**Severity:** HIGH | **Confidence:** high
**Component:** `head/evals/harness/ablation-grade.sh:1377` (the match includes the header remainder and the body), `:1383` (`HEREDOC.sub("<<HEREDOC", val)` replaces the whole match), `:1415` (`body = strip_heredocs(val)` before the path scan)
**Criterion:** SEC-IV Input Validation

**Reasoning Trace:**
> DEC-0541 says heredoc *bodies* are data. The regex match runs from `<<` through `[^\n]*\n` (the rest of the header line, including any redirect) and the body, and the substitution replaces all of it. So the path scan never sees (a) the header's redirect target, (b) a body fed to an interpreter, (c) a command substitution in an unquoted body. Reproduced against the committed `check_value` logic (head → no hit; base 1.2.0 scan → `outside_path`):
> `cat <<EOF > /root/.ssh/authorized_keys\nkey\nEOF`, `cat <<EOF >> /root/.bashrc\nalias x=y\nEOF`, `bash <<EOF\ncat /root/.ssh/id_rsa\nEOF`, `python3 - <<EOF\nprint(open('/mnt/data/key').read())\nEOF`, `cat <<EOF\n$(cat /root/secret.txt)\nEOF`. The dissent (DISS-C-001 and the rejected gpt-5.5-pro payload) raised the interpreter and substitution shapes; the review raised the redirect shape.

**Description:**
```python
def strip_heredocs(val):
    return HEREDOC.sub("<<HEREDOC", val)
...
        body = strip_heredocs(val)
```
**Impact:** The commonest ways to write a file (`cmd <<EOF > path`) and to run a script (`bash <<EOF`, `python3 - <<EOF`) are invisible to the outside-path check, so a read or write outside the sandbox through them is graded uncontaminated and its row's `hidden_test_pass_rate` enters the arm comparison. The `hidden`/`suite_path`/`repo_name` substring checks still read the full value, so only paths are lost.
**Remediation:** Capture the header remainder as a group and re-emit it (`HEREDOC.sub(r"<<HEREDOC\3", val)` with group 3 = `([^\n]*\n)`); keep the body in the scan when the command word before `<<` is an interpreter (`bash sh zsh python3 python perl ruby node env`) or the delimiter is unquoted (command substitution runs); strip only quoted-delimiter bodies of non-interpreter commands. Add AG-10 rows for each of the five shapes above expecting `outside_path`, and keep the reviewer-prose heredoc row clean.
**References:** CWE-184 Incomplete List of Disallowed Inputs — https://cwe.mitre.org/data/definitions/184.html

### [HIGH-003] Grader: a word beginning `/.` is skipped before normalisation, so `/./` and `/../` prefixes defeat the path check

**Severity:** HIGH | **Confidence:** high
**Component:** `head/evals/harness/ablation-grade.sh:1438` (`if w.startswith("/."): continue`), `:1330` (`ABS_WORD` admits `.` in every component)
**Criterion:** SEC-IV Input Validation (validate before canonicalise)

**Reasoning Trace:**
> DEC-0551 added the exemption for `pr/'"$v"'/.claude/…` remnants on the reasoning that no Linux root holds dot-directories. But `/.` is also the start of `/./root/…`, `/../mnt/…` and `/.//root/…`, all of which the shell resolves to a sensitive absolute path. `ABS_WORD` captures them as one word; the `continue` fires before `outside()` runs `os.path.normpath`. Reproduced: `cat /./root/.ssh/id_rsa`, `ls /../mnt/secrets`, `cat /.//root/x` → head no hit; base → `outside_path`. Raised by the dissent (DISS-C-002) and confirmed here.

**Description:**
```python
            if w.startswith("/."):
                continue
```
**Impact:** A two-character prefix on any absolute path makes it invisible to the contamination scan, for every root and every depth.
**Remediation:** Normalise first and exempt second: compute `n = os.path.normpath(w)` and apply the dot-directory exemption only when `n` still begins with `/.` and has a dot-directory as its first component (`re.match(r"^/\.[A-Za-z0-9_-]", n)`); otherwise pass `n` to `outside()`. Add AG-10 rows for the three shapes.
**References:** CWE-180 Incorrect Behavior Order: Validate Before Canonicalize — https://cwe.mitre.org/data/definitions/180.html

### [HIGH-004] Grader: an empty quoted string (or `[`, `{`, `:`) before the path defeats `after_closing_quote`

**Severity:** HIGH | **Confidence:** high
**Component:** `head/evals/harness/ablation-grade.sh:1365-1368` (helper), `:1442` (applied)
**Criterion:** SEC-IV Input Validation

**Reasoning Trace:**
> DEC-0557 skips a word whose preceding character is a quote whose own predecessor is not whitespace or one of `=(<>|;&,`. In `cat ""/root/.ssh/id_rsa` the character before `/` is `"` and the one before that is `"`, which passes the test, so the word is dropped; the shell expands `""/root/.ssh/id_rsa` to `/root/.ssh/id_rsa`. Reproduced: `cat ""/root/.ssh/id_rsa`, `cat ''/mnt/secrets/x` → head no hit; base → `outside_path`. The same helper also skips `python3 -c "for p in ['/root/.ssh/id_rsa']: …"` because `[` precedes the quote (review Observation 4, reproduced). Raised by the dissent (DISS-C-003) and the review; confirmed here.

**Description:**
```python
def after_closing_quote(body, pos):   # DEC-0557: "$D"/x → the quote closes a token
    if pos < 2 or body[pos - 1] not in "'\"":
        return False
    before = body[pos - 2]
    return not (before.isspace() or before in "=(<>|;&,")
```
**Impact:** Prefixing any absolute path with `""` or `''` removes it from the scan entirely; absolute paths inside Python list literals in `-c` one-liners are likewise unscanned.
**Remediation:** Require the quoted segment that closes at `pos-1` to be non-empty and to end in a shape that can only be a path head: `$NAME"`, `${…}"`, `)"`, or a segment containing `/`. Add `[`, `{`, `:` to the separator set. AG-10 rows: `cat ""/root/x` → `outside_path`; `"$D"/evals/harness/x` stays clean.
**References:** CWE-184 Incomplete List of Disallowed Inputs — https://cwe.mitre.org/data/definitions/184.html

### [HIGH-005] Grader: the Bash `hidden` token rule misses discovery commands, mixed case and a bare directory name

**Severity:** HIGH | **Confidence:** high
**Component:** `head/evals/harness/ablation-grade.sh:1329` (`HIDDEN_TOKEN`), `:1395` (Bash branch), `:1397` (the substring check every other tool still gets)
**Criterion:** SEC-IV Input Validation

**Reasoning Trace:**
> In 1.2.0 every tool value was tested with `"hidden" in val.lower()`. 1.2.4 (DEC-0551) replaced that for Bash with a token regex so a reviewer's prose inside a heredoc ("any hidden interaction") would not count. The regex needs `HIDDEN` in capitals, or lowercase `hidden` glued to `/ . _ = -` or followed by `/ _ = -` or a file extension. Reproduced against the committed regex: `grep -rn hidden .`, `find . -name '*hidden*'`, `ls | grep -i hidden`, `cat /workspace/Hidden/tests.json`, `cd hidden; cat test_api.py`, `ls hidden` → no match; base → `hidden`. `strip_heredocs` exists for exactly the prose case and is not used by this check. AG-10 (`head/evals/tests/ablation-grade.bats:459`) pins only `tests/HIDDEN_cases.py`.

**Description:**
```python
HIDDEN_TOKEN = re.compile(r"HIDDEN|(?<=[/._=-])hidden\b|\bhidden(?=[/_=-]|\.[A-Za-z0-9])")
...
        if HIDDEN_TOKEN.search(val):   # DEC-0551: token shapes only in command text
            return "hidden"
```
**Impact:** An agent that searches for, lists, or changes into the hidden test tree and then reads relatively is graded clean; contaminated trials inflate the arm's `hidden_test_pass_rate`.
**Remediation:** For Bash run `"hidden" in strip_heredocs(val).lower()` on the command text (bodies removed) and apply `HIDDEN_TOKEN` only to the stripped bodies if a prose exemption is still wanted. AG-10 rows for `grep -rn hidden .`, `find . -name '*hidden*'`, `cd hidden`, `cat Hidden/x` → `hidden`; the heredoc-prose row stays clean.
**References:** CWE-184 Incomplete List of Disallowed Inputs — https://cwe.mitre.org/data/definitions/184.html

---

## Medium Priority Issues (Address in Next Sprint)

### [MED-001] Grader: quote-parity heuristic flips on an apostrophe

**Severity:** MEDIUM | **Confidence:** high
**Component:** `head/evals/harness/ablation-grade.sh:1372-1374`, applied at `:1444`
**Description:** `in_quotes` counts raw `'` and `"` independently with no escape or nesting awareness. Reproduced: `echo "it's"; ls /root` → `/root` skipped (base flagged it).
**Impact:** Any earlier apostrophe exempts every later one-component sensitive word (`/root /home /mnt /media /srv`).
**Remediation:** Walk the body once tracking shell quoting state and record quoted spans; test `m.start(1)` against them. Or drop the heuristic and accept the `grep ' /tmp | /home '` false positive.
**References:** CWE-184 — https://cwe.mitre.org/data/definitions/184.html

### [MED-002] Grader: any `=` in a path word exempts it

**Severity:** MEDIUM | **Confidence:** high
**Component:** `head/evals/harness/ablation-grade.sh:1432`
**Description:** `"=" in w` drops a multi-component absolute path when any component carries `=`. Reproduced: `cat /home/operator/notes=secret.txt` → no candidate (base: `outside_path`). `=` is legal in file names.
**Impact:** Outside paths with `=` anywhere after the first component are unscanned.
**Remediation:** Treat `=` as the regex / key=value marker only in the first component (`re.match(r"^/[^/]*=", w)`).
**References:** CWE-184 — https://cwe.mitre.org/data/definitions/184.html

### [MED-003] Grader: the one-component whitelist of five names

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `head/evals/harness/ablation-grade.sh:1362`, `:1423`
**Description:** A one-component word not in `{root, home, mnt, media, srv}` is a command token. Reproduced: `ls /secrets`, `ls /data` → no candidate (base: `outside_path`); `/boot`, `/run`, `/Users` likewise.
**Impact:** Listing a top-level directory outside the allowed roots is not reported.
**Remediation:** Invert the rule: skip only a word shaped like a Loa slash command (`^/[a-z][a-z0-9-]*$`) that is not the argument of a filesystem command (`ls cd cat find stat du tree`), or a `/x/` delimiter after `s y = ~ '`; let `outside()` decide the rest.
**References:** CWE-184 — https://cwe.mitre.org/data/definitions/184.html

### [MED-004] Runner: the process-group records are deleted the instant the driver is signalled, so a pipeline that outlives it is never detected on resume

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `head/evals/harness/run-ablation.sh:941` (`rm -rf "$JOBS_DIR" "$LOCK" "$WORK"` in `cleanup`), `:938` (SIGTERM sent one line earlier, no wait), `:838-845` (the orphan check on the next start reads only `.jobs/*.pgid`)
**Description:** `on_signal` exits 1, `cleanup` sends SIGTERM to each recorded process group and immediately removes `.jobs/`. The header promises "A start (fresh or resumed) is refused while a process group recorded under `<batch>/.jobs/` by an earlier driver … is still alive", but after a SIGTERM the records are gone, so a pipeline still shutting down (a `docker run` forwarding the signal, a phase in its grace period) is invisible. RAB-13 (`head/evals/tests/run-ablation.bats:385`) itself polls for the group to die before resuming, which the script does not.
**Impact:** `--resume` launches the same trial into `-r2` while the first still spends against the same run cap; two pipelines write the same `<arm>/<task>-t<n>*` tree and both costs land on the batch.
**Remediation:** In `cleanup`, after SIGTERM wait up to `WATCHDOG_GRACE` for each group (`kill -0 -- "-$p"`), SIGKILL survivors, and remove a `.pgid` only once its group is gone; or leave `.jobs/` in place on the signal path and let the orphan check at `:838` do its job.
**References:** CWE-404 Improper Resource Shutdown or Release — https://cwe.mitre.org/data/definitions/404.html

### [MED-005] Runner: the row is appended before it is validated

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `head/evals/harness/run-ablation.sh:1071` (`cat "$rowf" >> "$ROWS"` precedes `--validate`), `:1342` (`--resume` reads any row of the batch as done)
**Description:** An invalid row stays in the tracked `runs.jsonl` with the batch marked `failed`; the next `--resume` counts it as done and `ablation-report.py` reads it. `replace_row_try` (`:1237-1259`) already does validate-then-`mv` on a temp beside the rows file; the append path does not.
**Impact:** The tracked rows file carries a row the validator refused; the operator has to hand-edit it.
**Remediation:** Validate the candidate row on its own (or the concatenation into a temp beside the rows file) and append only on success; park the rejected row under `<batch>/rejected/`.
**References:** CWE-703 Improper Check or Handling of Exceptional Conditions — https://cwe.mitre.org/data/definitions/703.html

### [MED-006] Documentation: no AC verification, no test evidence, no coherence report, header documents the old grader version

**Severity:** MEDIUM | **Confidence:** high
**Component:** `grimoires/loa/a2a/sprint-1/reviewer.md:1` (= `pr/PR.md`), `head/evals/harness/ablation-grade.sh:188`
**Description:** The implementation report is a commit list: no `## AC Verification`, no record of the three new bats suites running (and they cannot run in this workspace). No `documentation-coherence-task-*.md` exists under `grimoires/loa/a2a/subagent-reports/`. Two commits in the description are CHANGELOG entries but `CHANGELOG.md` is not among the 17 files, so the security-relevant grader changes cannot be checked against it. The grader header at `:188` still documents `grader_version: "1.2.0"` while `GRADER_VERSION = "1.2.5"` (`:258`), so a reader of the output schema is told the wrong version.
**Impact:** The acceptance criteria and the five calibration rounds are verifiable from the diff alone; the audit cannot confirm the suites were green at head.
**Remediation:** Add the AC walkthrough with `file:line` evidence and the bats output for `run-ablation.bats`, `ablation-report.bats`, `ablation-grade.bats`; include the CHANGELOG hunk; fix `:188`.
**References:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html

---

## Low Priority Issues (Technical Debt)

### [LOW-001] Runner: counters advance after a failed in-place replacement
**Severity:** LOW | **Confidence:** high
**Component:** `head/evals/harness/run-ablation.sh:1150`, `:1155-1156`
**Description:** When `replace_row_try` fails (`STOP=invalid`) the run is still appended to `DONE_LIST` and `account_row` counts a row that is not in the file.
**Remediation:** Skip the done/account step when `STOP=invalid` was just set.

### [LOW-002] Report: the table header hardcodes the 90 % interval
**Severity:** LOW | **Confidence:** high
**Component:** `head/evals/harness/ablation-report.py:813`, `:941`
**Description:** "[90 % CI]" is literal while `--level` is configurable and marked at `:807`.
**Remediation:** Format the header from `args.level`.

### [LOW-003] Runner: a batch whose trials all end `cap_failure` exits 3
**Severity:** LOW | **Confidence:** medium
**Component:** `head/evals/harness/run-ablation.sh:1397`
**Description:** `total_completed -eq 0` reads `failed: no trial completed` although every row is valid and scorable (cap_failure scores 0 by the rules).
**Remediation:** Count `cap_failure` rows as scored for this check, or name the cap failures in the message.

### [LOW-004] Report: trials present in only one arm are averaged over unequal trial sets
**Severity:** LOW | **Confidence:** medium
**Component:** `head/evals/harness/ablation-report.py:501`
**Description:** `drop` removes a trial only when a cell exists and is invalid; a trial the control never ran stays in the arm's mean.
**Remediation:** Document the choice in the Method section, or drop trials absent on either side.

### [LOW-005] Row/runner: the DEC-0545 narrowing has no token-share threshold
**Severity:** LOW | **Confidence:** medium
**Component:** `head/evals/harness/ablation-row.sh:318-322` (`model_missing`), `head/evals/harness/run-ablation.sh:521` (`drift_check`: drift only when the requested model is absent)
**Description:** A phase in which the requested model appears with negligible usage and another model produces almost all output tokens is neither degraded nor drift; the extra model is telemetry (STATUS `extra_models`). The rules block pins `model_ids: fixed_per_batch`. Raised by the dissent (DISS-C-008).
**Remediation:** Flag degraded (or at least a STATUS warning) when an extra model's output-token share of the phase exceeds a threshold, or allow-list the known auxiliary models.

### [LOW-006] Grader: git history probes are telemetry with no check that the sandbox has no history
**Severity:** LOW | **Confidence:** medium
**Component:** `head/evals/harness/ablation-grade.sh:1404`
**Description:** `git log --all` / `git reflog` only increment `HISTORY_PROBES` (DEC-0540) on the assumption the sandbox is a fresh init at the base commit; nothing in the grader verifies that. Raised by the dissent (DISS-C-006).
**Remediation:** Assert the sandbox has exactly one reachable commit (or no `.git`) before treating the probes as harmless, or keep the count and fail the grade when the probe count is non-zero and the sandbox has history.

### [LOW-007] Grader: home-relative traversal is unscanned in container mode
**Severity:** LOW | **Confidence:** high
**Component:** `head/evals/harness/ablation-grade.sh:1389`, `:1413`
**Description:** `~/`, `$HOME/`, `${HOME}/` words are only checked when `home_word_outside()` is true (host mode). Reproduced: `cat ~/../../root/x` → no hit in container mode while the literal `cat /home/evaluser/../../root/x` normalises and is flagged. Impact is bounded by what the container exposes. Raised by the dissent (DISS-C-007).
**Remediation:** In container mode rewrite the home prefix to `/home/evaluser/` and pass the word through `outside()`.

### [LOW-008] Runner: stale-lock takeover is a check-then-act race
**Severity:** LOW | **Confidence:** medium
**Component:** `head/evals/harness/run-ablation.sh:829-832`
**Description:** Two drivers that both find `.lock/pid` dead can both `rm -rf "$LOCK"; mkdir "$LOCK"`; pid reuse can also report a live lock from an unrelated process.
**Remediation:** Use `flock` on `<batch>/.lock` (already relied on for the rows file) instead of a directory plus pid file.
**References:** CWE-367 TOCTOU — https://cwe.mitre.org/data/definitions/367.html

### [LOW-009] Runner: `append_and_validate` validates the whole shared rows file, so another batch's bad row fails this one
**Severity:** LOW | **Confidence:** medium
**Component:** `head/evals/harness/run-ablation.sh:1069-1077`
**Description:** `--validate "$ROWS"` runs over the tracked `runs.jsonl` shared by every batch; an invalid row written by another batch (or a hand edit) makes this batch's append fail with the error attributed to this `run_id`, and every later append fails the same way.
**Remediation:** Validate the candidate row (or `tail -1`) rather than the file; validate the whole file once at start-up and refuse then.

### [LOW-010] Runner: the post-run collaborators run with no timeout and outside the watchdog
**Severity:** LOW | **Confidence:** medium
**Component:** `head/evals/harness/run-ablation.sh:976` (took-effect), `:996` (grade), `:1031` (the pgid record is removed before `post_run`)
**Description:** The watchdog covers only the pipeline process group. A hung grader or took-effect script (HIGH-001 is one cause; a stuck `docker run` inside the grader is another) holds the trial job and the batch indefinitely.
**Remediation:** `timeout` each collaborator with a bound derived from the plan and row a timeout as `infrastructure_error`.

---

## Observations

No finding was marked speculative; nothing is excluded from the tally.

- **Runner input validation is good.** `--batch`, `--arms`, `--tasks`, `--rerow`/`--rerun` ids, `--image`, `--source-commit` and every env knob are regex-validated; the row and manifest readers reject unknown schema majors; collaborators are argv arrays; `source ./lib/arms-common.sh` is literal after `pushd "$SCRIPT_DIR"`.
- **Transport retry cannot be earned by the agent.** `is_pipeline_transport_failure` (`head/evals/harness/lib/arms-common.sh:75-98`) reads the CLI's stderr and `result` events only, with the phase label validated before it enters a path.
- **`run-arms.sh` extraction is parity-preserving:** `spend_charge` + `est_record "$arm" all "$CHARGED_COST"` reproduce the removed `ARM_SUM`/`POOL_SUM` arithmetic; no dangling symbol.
- **Spend identity holds.** `spent = rows_usd + ledger_usd + assumed charges` across resume, rerow and rerun paths; every refusal path leaves the rows file untouched.

---

## Cross-Model Observations

Two voices answered the audit dissent (`adversarial-audit.json`: primary `gpt-5.5-pro` via codex-headless, companion `claude-headless`; `verdict_quality.status` APPROVED, 2/2 succeeded, `chain_health` ok, not degraded). The primary's single payload was rejected for schema (below) and its body was read from the sidecar as advisory; the companion contributed eight findings. Triage:

- DISS-C-001 (interpreter-fed heredoc bodies stripped): reproduced; folded into HIGH-002.
- DISS-C-002 (`/.` prefix skipped before normalisation): reproduced; HIGH-003.
- DISS-C-003 (empty quoted string before a path): reproduced; HIGH-004.
- DISS-C-004 (`cd hidden`, `ls hidden`, mixed case): reproduced; folded into HIGH-005.
- DISS-C-005 (in_quotes parity): reproduced; MED-001.
- DISS-C-006 (history probes telemetry): accepted as LOW-006.
- DISS-C-007 (home-relative traversal in container mode): reproduced; LOW-007.
- DISS-C-008 (no token-share threshold on the DEC-0545 narrowing): accepted as LOW-005.
- The rejected gpt-5.5-pro payload (command substitution inside an unquoted heredoc body): reproduced; folded into HIGH-002.

The review's dissent (`adversarial-review.json`, 11 payloads, none rejected) was re-read; its DISS-001/DISS-C-003, DISS-C-001 and DISS-C-002 correspond to HIGH-005, HIGH-001 and HIGH-002 here.

## Rejected dissent payloads

- Index 0, `gpt-5.5-pro`, "[P2] Preserve executable substitutions when stripping heredocs", anchor `evals/harness/ablation-grade.sh:strip_heredocs` (lines 1380-1383): rejected for `severity-not-in-enum (got: medium)`; repair attempted and failed. Read from `adversarial-rejected-audit.jsonl` as advisory; its substance is confirmed and counted inside HIGH-002.

---

## Security Checklist Status

### Secrets & Credentials
- [x] No hardcoded secrets or credentials in the 17 files
- [x] The batch lock file is gitignored (`head/.gitignore:333`); run directories and logs are gitignored per batch (`run-ablation.sh:851-854`)

### Input Validation
- [x] CLI arguments, env knobs, ids and paths regex-validated at the runner's boundary
- [x] Schema-major checks on rows and manifests in the report
- [ ] The contamination scan's exemptions admit seven bypass shapes (HIGH-002..005, MED-001..003)

### Injection
- [x] No `eval`; collaborators invoked as argv arrays; jq/python receive data via `--arg`/argv/stdin
- [x] `source` by literal relative path only

### Availability
- [ ] Exponential regex on agent-controlled input (HIGH-001)
- [ ] No timeout around post-run collaborators (LOW-010)

### Process & Files
- [x] Symlink refusal at `--out`/`--json` and on MANIFEST.json in the report
- [x] Atomic `mv` for MANIFEST.json, STATUS.json and the rerow/rerun replacement
- [ ] Orphan detection lost after a signalled driver (MED-004); row appended before validation (MED-005)

### Documentation
- [ ] AC verification / test evidence / coherence report absent (MED-006)

---

## Verdict

Five HIGH findings in the contamination scan and its runner coupling (HIGH-001 to HIGH-005), six MEDIUM, ten LOW; zero CRITICAL. The one-way rule applies: critical + high > 0.

**Verdict:** CHANGES_REQUIRED

### Required before re-audit

1. Replace the five grader exemptions with a small shell-word classifier: track quoting state once, keep heredoc headers and interpreter/unquoted bodies, normalise before any exemption, and keep the 1.2.0 substring `hidden` check on command text (HIGH-002..005, MED-001..003). Make the heredoc pattern linear (HIGH-001).
2. Add AG-10 rows for every bypass shape named above, and one for a 60-line unterminated heredoc.
3. Wrap the post-run collaborators in `timeout` and keep `.jobs/*.pgid` until each group is gone (HIGH-001, MED-004, LOW-010).
4. Validate before append (MED-005); add the AC walkthrough, bats evidence and CHANGELOG hunk (MED-006).
5. Re-run `/review-sprint sprint-1`, then `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":5,"medium":6,"low":10},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-22T22:16:31Z"} -->
