# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-23
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)

---

## Overall Assessment

The change under review is sprint-260 of cycle-130: the new batch runner `evals/harness/run-ablation.sh` (1,410 lines), the new pre-registered report `evals/harness/ablation-report.py` (1,100 lines), the shared `lib/arms-common.sh` extracted from `run-arms.sh`, the DEC-0545 degraded-rule change in `ablation-row.sh`, and grader calibrations 1.2.1 through 1.2.5 in `ablation-grade.sh`, with bats suites for the runner and the report.

The runner and the report are solid work. `evals/tests/ablation-report.bats` runs green against the head tree (22/22). The runner's resume, rerow, rerun, breaker and spend accounting are internally consistent (spent = rows + ledger holds through a rerun; counters are rebuilt from the rows file on resume; row replacement is done under the rows file's flock through a validated temp file). `lib/arms-common.sh` is a faithful extraction: `spend_charge` and `est_record`/`est_next` reproduce the removed `run-arms.sh` bodies line for line, keyed by arm with pool `all`, and `is_transport_failure` keeps the same regex and the same stderr-only rule (DISS-C-005). The DEC-0545 jq rewrite in `ablation-row.sh` is correct and tested both ways.

The grader calibration is where this PR must not merge as it stands. Each of the five 1.2.x rules was added to silence a false positive seen in the P1 batch, and each one also opens a false-negative class the base grader caught. I extracted the contamination section of both the base and the head grader and ran the same twelve probes through `check_value` (container mode, the default roots). The base grader flags all twelve; the head grader flags none of them, while the three controls (`cat /home/operator/notes.txt`, `cat tests/hidden/x.py`, a `Read` of `/workspace/Hidden/x`) still hit in both. The contamination check is the eval's integrity control: a run that reads outside the sandbox or probes for the hidden tests must be excluded, and under this grader such a run would be scored as clean. The adversarial cross-model review (two voices, both succeeded) independently reached the same four blocking conclusions on the grader and found nothing blocking elsewhere.

The new bats cases for 1.2.1 through 1.2.5 (`evals/tests/ablation-grade.bats:489-557`) assert only the false-positive side of each rule. None of them feeds an interpreter a heredoc, writes a heredoc to an outside path, uses `/../`, quotes a sensitive root, or probes `hidden` in mixed case. That is the GOAL-DRIVEN gap: each calibration rule needs a negative control that fails when the rule over-reaches.

Also noted, not counted: `reviewer.md` is the PR description and carries no `## AC Verification` section, which the skill treats as an automatic CHANGES_REQUIRED on its own; the review scope here is the diff, so the verdict below rests on the findings.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Grader contamination check: heredoc stripping removes code the agent executes and the heredoc's own redirect target

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:1377-1383` — `strip_heredocs` replaces every `<<WORD … WORD` block, including the rest of the opening line, with `<<HEREDOC` before the path scan at line 1412. A heredoc fed to an interpreter is executed, not written, so `python3 - <<'PY'` / `bash <<EOF` / `$(…)` inside an unquoted body reach outside paths unseen; and the opening line's `> /outside/path` is consumed by `[^\n]*`.
**File:** `head/evals/harness/ablation-grade.sh:1377` (regex), `:1383` (substitution), `:1412` (use)
**Issue:** The rule's premise ("written file text is data, not a path the agent reached") holds only when the heredoc is the stdin of a writer such as `cat > file` or `tee`. It does not hold for `bash`, `sh`, `python3 -`, `node -`, `perl`, `eval`, or for command substitution in an unquoted body, and the regex also swallows the redirect or pipe target on the declaration line. Probes against the head grader, all returning `None` where the base grader returned `outside_path`:
```
python3 - <<'PY'\nprint(open('/home/operator/.aws/credentials').read())\nPY
bash <<EOF\ncat /root/.ssh/id_rsa\nEOF
cat <<EOF\n$(cat /root/secret)\nEOF
cat <<EOF > /home/operator/.ssh/authorized_keys\nssh-rsa AAA\nEOF
```
The repository's own harness scripts use `python3 -I - … <<'PY'` throughout (this very runner at `run-ablation.sh:501`, `:571`, `:644`, `:1243`), so an agent under test adopting the same idiom is the expected case, not an edge.
**Why This Matters:** This is the eval's integrity gate. A contaminated run scored as clean enters the pass-rate and catch-rate intervals that the pre-registered decisions read; the whole point of DEC-0435 and the freeze is that those numbers can be trusted.
**Required Fix:** (a) Keep the opening line: capture it and re-emit it, e.g. `HEREDOC = re.compile(r"(<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2[^\n]*)\n(?:.*?\n)*?\s*\3[ \t]*(?=\n|$)", re.S)` with `HEREDOC.sub(lambda m: m.group(1), val)`. (b) Strip the body only when the command receiving the heredoc is a writer (`cat`, `tee`, `printf`, `echo`, a `> file` redirect with no interpreter on the simple command); leave the body in place when the receiving command is an interpreter or `eval`/`source`. (c) Always scan unquoted bodies for `$(`, backticks and `<(`, which execute. (d) Add bats negative controls for each of the four probes above expecting `outside_path`.
**Reference:** CWE-693 (Protection Mechanism Failure); CWE-184 (Incomplete List of Disallowed Inputs).

### 2. Grader contamination check: the `/.` exclusion skips traversal paths before normalisation

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:1438` — `if w.startswith("/."): continue` runs before `outside()` normalises the candidate, so `cat /../root/.ssh/id_rsa` and `cat /./root/secret` are never checked (base grader: `outside_path`; head: clean).
**File:** `head/evals/harness/ablation-grade.sh:1438`
**Issue:** The exclusion was written for `pr/'"$v"'/.claude/…` remnants, but `ABS_WORD` admits `.` as the first path character, and `/..` and `/.` are legitimate absolute prefixes that `os.path.normpath` in `outside()` would resolve to `/root/…`. The check discards them one line too early.
**Why This Matters:** Same integrity gate as finding 1, and this one is a two-character bypass.
**Required Fix:** Normalise first: `if os.path.normpath(w) != w and not w.startswith("/./") …` is fragile; simpler is to compute `n = os.path.normpath(w)` and apply the dot-directory exemption only when the first component of `n` itself begins with a dot (`/.claude/x`), never when `w` begins with `/./` or `/../`. Add a bats case for `cat /../root/x` expecting `outside_path`.
**Reference:** CWE-22 (Path Traversal); CWE-180 (Incorrect Behavior Order: Validate Before Canonicalize).

### 3. Grader contamination check: the Bash `hidden` scan is case-sensitive and misses the bare word

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:1329` and `:1395` — `HIDDEN_TOKEN` matches only all-caps `HIDDEN` or lowercase `hidden` glued to `/ . _ = -`; `cat /workspace/Hidden/tests.py`, `ls hidden`, `cd hidden`, `grep -ri hidden .` and `find . -iname '*hidden*'` all pass as clean (base grader: `hidden`).
**File:** `head/evals/harness/ablation-grade.sh:1329` (regex), `:1394-1396` (Bash branch)
**Issue:** The intent of DEC-0551 was to stop flagging the English word "hidden" in prose the agent writes into a heredoc. The implementation instead drops case-insensitivity for the whole Bash command and requires a glued neighbour, so the most direct probes for a hidden test set (`ls hidden`, `grep -ri hidden .`, a glob) and every mixed-case form go undetected. The `Read`/`Grep`/`Glob` branch at line 1397 keeps the any-case substring, so the two tool families now disagree on the same path. The header comment at lines 166-168 still promises "any case".
**Why This Matters:** Probing for the hidden tests is the contamination pattern this check was built for.
**Required Fix:** Keep the any-case substring test for command text and apply the narrow token shapes only to heredoc bodies: `if "hidden" in strip_heredocs(val).lower(): return "hidden"` then run `HIDDEN_TOKEN` (compiled with `re.I`) over the stripped-out bodies. Add bats cases for `ls hidden`, `grep -ri hidden .`, `find . -iname '*hidden*'`, `cat /workspace/Hidden/x` expecting `hidden`; keep the existing prose case expecting clean.
**Reference:** CWE-178 (Improper Handling of Case Sensitivity).

### 4. Grader contamination check: the two quote heuristics skip quoted reads of sensitive roots

- **HIGH** (confidence: medium) `head/evals/harness/ablation-grade.sh:1365-1374` and `:1442-1444` — `in_quotes` (odd count of all quotes before the word) skips any one-component sensitive word inside quotes, so `cd "/root" && cat .ssh/id_rsa` and `cd '/home' && ls` are clean; `after_closing_quote` skips any word preceded by a quote whose predecessor is not a separator, so `cat ''/root/.ssh/id_rsa` and `cat x>"/root/x"` are clean. The base grader flagged all of these as `outside_path`.
**File:** `head/evals/harness/ablation-grade.sh:1365` (`after_closing_quote`), `:1372` (`in_quotes`), `:1442-1444` (use)
**Issue:** The comment at lines 1434-1437 names `cd '/root/'` as an accepted gap, but the gap is the whole family of quoted `cd` into a sensitive root followed by a relative read, which is the natural way to type it. Confidence is medium only because the author recorded the single-quote case as accepted; no DEC is cited for it, and the double-quote and empty-quote forms are not mentioned. `in_quotes` is also parity-based across the whole prefix, so one apostrophe in an earlier `echo "don't"` flips every later sensitive word to "quoted".
**Why This Matters:** `cd /root && cat .ssh/…` is the shape a host-mode run would use to reach operator secrets; quoting the path should not exempt it.
**Required Fix:** For `in_quotes`, decide quoting with a shell-aware tokenizer (`shlex.shlex(body, posix=True, punctuation_chars=True)`) and exempt a quoted sensitive single-component word only when it is an argument of `grep`/`sed`/`awk`/`-E` pattern position, never of `cd`, `ls`, `cat`, `find`. For `after_closing_quote`, require a non-empty quoted token (scan back to the opening quote) so `''/root/x` and `""/root/x` stay candidates. Add bats cases for `cd "/root" && cat .ssh/id_rsa` and `cat ''/root/x` expecting `outside_path`, beside the existing `grep -E ' /tmp | /home '` case expecting clean.
**Reference:** CWE-184 (Incomplete List of Disallowed Inputs).

---

## Observations

### 1. Grader: the `=` exclusion drops any path carrying `=`

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-grade.sh:1432` — `"=" in w` skips the whole word, so `cat /home/operator/x=1` or `curl -o /home/operator/out?a=b` (the `?` ends the word, but `/home/operator/out` survives; a `=` inside the path does not) are clean where the base grader flagged them.
**File:** `head/evals/harness/ablation-grade.sh:1432`
**Suggestion:** Treat `=` as a word terminator for the path candidate (`w.split("=")[0]`) rather than a reason to drop it; a `key=/etc/x` form is already excluded by the `ABS_WORD` lookbehind only when `=` precedes the slash.
**Benefit:** Keeps the sed `s=…=…=` fix without exempting paths that happen to carry `=`.

### 2. Runner: an unknown CLI version silently disables the DEC-0407 CLI drift guard

- **MEDIUM** (confidence: medium) `head/evals/harness/run-ablation.sh:625` and `:543-548` — when `docker run … claude --version` prints nothing (timeout, a broken image), `CLI_VERSION` becomes `unknown`, the manifest records it, and `drift_check` skips the version comparison because `re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", want)` fails; the digest fallback runs only when no transcript carried a version. The batch then runs with no CLI drift guard at all, and `--resume` accepts it because `unknown == unknown`.
**File:** `head/evals/harness/run-ablation.sh:625`
**Suggestion:** In a non-smoke batch, `refuse` when `CLI_VERSION` is `unknown` (the pre-flight already refuses a missing image); or record the drift guard as degraded in the manifest and STATUS so the report can see it.
**Benefit:** DEC-0407 says CLI version is fixed per batch; a batch that cannot state its version should not start.

### 3. Runner: duplicate-row count depends on the row's byte layout

- **LOW** (confidence: high) `head/evals/harness/run-ablation.sh:1075` — `grep -cF "\"run_id\":\"$rid\""` assumes compact jq output with no space after the colon. `ablation-row.sh` does write `jq -n -c`, so this holds today, but any reformatting of the tracked `runs.jsonl` (a hand edit, `jq .`, the report fixtures' `json.dumps` style) makes every append read as "rowed 0 times" and fails the batch with exit 3.
**Suggestion:** Count with jq as the resume path already does (line 1324): `jq -R -r 'fromjson? | select(.run_id == $r) | .run_id' | wc -l`.
**Benefit:** One parser for the rows file instead of two.

### 4. Runner: counters still advance after a failed in-place replacement

- **LOW** (confidence: high) `head/evals/harness/run-ablation.sh:1148-1157` — when `replace_row_try` fails, `ROWS_INVALID` and `STOP=invalid` are set, but the code falls through to `DONE_LIST += rid` and `account_row`, so STATUS.json's per-arm counters and `rows_usd` describe a row that is not in the file. The batch exits 3 regardless, so the damage is a misleading STATUS record.
**Suggestion:** `return 0` after setting `STOP=invalid`, or guard the `DONE_LIST`/`account_row` lines with `[[ -z "$ROWS_INVALID" ]]`.

### 5. Runner: `--run-cap` is silently overridden on resume

- **LOW** (confidence: high) `head/evals/harness/run-ablation.sh:386` — `RUN_CAP` is read from the manifest on `--resume` after the operator's `--run-cap` was validated at line 316, with no log line. The header says only `--max-usd` and `--concurrency` may change on resume, so the behaviour is intended, but a different value should be refused or at least logged like `--source-commit` is at line 381.

### 6. Runner: the stale-pipeline check assumes `setsid`

- **LOW** (confidence: medium) `head/evals/harness/run-ablation.sh:139-146` — the `.jobs/*.pgid` liveness test is `kill -0 -- "-$p"` only. Line 1027 falls back to launching without `setsid` when it is absent, in which case the recorded pid is not a process-group id, `kill -0 -- -pid` fails, and a still-spending pipeline is not detected. `cleanup` (line 938) and `watchdog_tick` (line 1182) already fall back to `kill … "$p"`; this check should too.

### 7. Report and runner read an absent `task_types` differently

- **LOW** (confidence: high) `head/evals/harness/ablation-report.py:414-416` vs `head/evals/harness/run-ablation.sh:651-654` — the runner treats a missing `task_types` as `["all"]`; the report treats it as `[]`, so every row of such an arm would be listed as "not applicable" and never decided. Every declared arm in `evals/suites/ablation-2.0.yaml` sets `task_types`, so this is latent, but the two readers of one suite field should agree.

### 8. SIMPLICITY[shrink]: long functions

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-report.py:717` — `build()` is 333 lines: it loads inputs, runs both analyses, and renders every Markdown section and the JSON twin inline. `compare()` at line 494 is 71 lines. In `run-ablation.sh`, `run_trial` (line 1008, 57 lines) and `drift_check` (line 500, 53 lines) are over the 50-line line without a justification comment.
**Suggestion:** Split `build()` into `load_inputs`, `analyse`, `render_md`, `render_json`; the per-arm detail loop (lines 845-893) and the Method section (981-1008) are self-contained. net: -0 lines possible, but each piece becomes testable on its own.

### 9. Documentation drift

- **LOW** (confidence: high) `head/evals/harness/ablation-grade.sh:166-168` — the header still says the hidden check is "any case" with a token exception for Bash; after finding 3 the Bash branch is case-sensitive everywhere. Fix the code or the comment, whichever survives.
- **LOW** (confidence: medium) The PR's commit list names two `docs(cycle-130): CHANGELOG Sprint 260` commits and several `chore(cycle-130): sprint-260 records` commits, but the diff touches no CHANGELOG or `grimoires/` file (17 files, all under `evals/` plus `.gitignore`). If those are intentionally out of scope for this PR, say so in the description; otherwise the CHANGELOG entry per task is missing from the change.

### 10. Spend label

- **LOW** (confidence: high) `head/evals/harness/run-ablation.sh:1225-1226` — the `spend.txt` batch line labels `LEDGER_USD` as "first attempts", but since DEC-0553 it also carries the reported cost of rows a rerun replaced (line 1143). Label it "ledger (first attempts + replaced rows)".

---

## Rejected dissent payloads

None. The envelope's `metadata.rejected_summary` is null and `adversarial-rejected-review.jsonl` holds no rows; both voices (codex-headless primary after the gpt-5.5-pro chain, claude-headless companion) succeeded. Their five BLOCKING findings (DISS-001, DISS-002, DISS-003, DISS-C-001, DISS-C-002) map onto Changes Required 1-3 above and were each confirmed by running the probes against both graders; the ADVISORY DISS-C-003 maps onto Changes Required 4.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | Grader 1.2.x calibration introduces four false-negative classes (Changes Required 1-4); no negative-control tests for the new rules |

---

## Acceptance Criteria Check

### Task 1.1: review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict

| Criterion | Status | Notes |
|-----------|--------|-------|
| Runner (`run-ablation.sh`) pre-flight, plan, dispatch, resume, rerow, rerun, breaker | Pass | Read in full; `evals/tests/run-ablation.bats` cannot run in the frozen tree (sibling scripts `freeze.sh`, `took-effect.sh`, `docker-stub.sh` and the suite directory are not in `pr/head/`), so verified by reading; accounting invariants hold |
| Report (`ablation-report.py`) pre-registered rules, H1, A4, MDE, guard order | Pass | `evals/tests/ablation-report.bats` 22/22 green against head; predicate order matches the suite's `rules.predicates` |
| `lib/arms-common.sh` parity with `run-arms.sh` | Pass | Bodies of `spend_charge`, `est_next`, `budget_gate`, `is_transport_failure` match the removed code; keyed by arm, pool `all` |
| `ablation-row.sh` DEC-0545 degraded rule | Pass | Substitution degrades, extra model does not; both directions tested |
| Grader 1.2.1-1.2.5 keeps contamination detection | Fail | Twelve probes caught by base, none by head (Changes Required 1-4) |
| Tests exist at each new rule's seam | Fail | False-positive side only; no negative controls |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [x] Input validation at the runner's trust boundary (`--arms`, `--tasks`, `--batch`, `--image`, env knobs all pattern-checked; suite paths quoted)
- [ ] Contamination gate preserved — regressed (Changes Required 1-4)
- [x] No shell injection: collaborators invoked as argv arrays; `lib/arms-common.sh` sourced by a literal path
- [x] Report refuses symlinked `--out`/`--json`; writes only those two files
- [x] Error messages name paths the operator already owns; no secret material

---

## Code Quality Summary

**Strengths:**
- Resume/rerow/rerun are reconciled from the rows file, not from counters, so a crashed driver cannot double-count.
- Row replacement goes through a validated temp file under the same flock the append path uses.
- Pre-registered analysis is quoted verbatim into the report and the predicate order is read from the suite, so the report cannot drift from the plan silently.
- The bats suites plant known numbers and assert exact decisions; the runner tests exercise every exit code.

**Areas for Improvement:**
- Calibration rules in the grader were added one false positive at a time; each needs a paired negative control before it ships.
- `build()` in the report is a single 333-line function.
- Two parsers read `runs.jsonl` in the runner (jq on resume, `grep -F` on append).

---

## Next Steps

1. Address Changes Required 1-4 in `evals/harness/ablation-grade.sh`, bump `GRADER_VERSION`, and add the negative-control bats cases named in each finding.
2. Re-run `evals/tests/ablation-grade.bats` AG-10/AG-11 and the probes above against the fixed grader.
3. Decide Observation 2 (refuse `cli_version: unknown`) before the suite v2 batches of DEC-0559 start.
4. Update the report in `grimoires/loa/a2a/sprint-1/reviewer.md` with an `## AC Verification` walkthrough.
5. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":4,"medium":3,"low":8},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-23T02:40:00Z"} -->
