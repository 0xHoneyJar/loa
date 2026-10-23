# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)

Scope reviewed: `pr/head.diff`, all 17 files under `pr/head/` against `pr/base/`. Citations are `head/<path>:<line>` with line numbers from the `pr/head/` files.

---

## Overall Assessment

The batch runner (`run-ablation.sh`), the shared library extraction (`lib/arms-common.sh`), the report generator (`ablation-report.py`) and their tests are careful, well-documented work. Every script passes `bash -n` / `py_compile`; the 22 `ablation-report.bats` cases were executed here against the head files and pass; the DEC-0545 degraded rule in `ablation-row.sh` and the runner's drift guard agree on the model normaliser; the spend identities asserted in RAB-5/RAB-19 match the code paths. The runner's and grader's own bats suites could not be executed in this workspace (their collaborators `pipeline-run.sh`, `freeze.sh`, `took-effect.sh` and the frozen suite are outside the diff) and were verified by reading only.

The blocking problems sit in the grader calibration (`ablation-grade.sh` 1.2.2 to 1.2.5). I extracted the embedded contamination functions from both `pr/base` and `pr/head` into a Python harness and fed them the same Bash commands; the cross-model dissent (two voices, both succeeded) reached the same four regressions independently and added five more, all of which the harness confirmed. Three of the new skip rules are regressions with concrete failing inputs the base grader caught, and the heredoc regex behind one of them backtracks exponentially on an unterminated heredoc, which stalls a trial and therefore the batch. The contamination check is the only guard that keeps a run that reached the hidden tests or outside paths out of the pre-registered analysis, so these are not cosmetic.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Reliability: the heredoc regex backtracks exponentially

- **HIGH** (confidence: medium) `head/evals/harness/ablation-grade.sh:1377` — `HEREDOC` uses `(?:.*?\n)*?` under `re.S`; on a Bash command whose heredoc delimiter line never appears, the engine tries every partition of the newlines. Measured on the extracted function: 18 lines 0.10 s, 20 lines 0.42 s, 22 lines 1.72 s (×4 per two lines), so a 30-line unterminated heredoc takes minutes and 40 lines never returns.
**File:** `head/evals/harness/ablation-grade.sh:1377` (applied at `:1383`, called from `:1412`)
**Issue:** `strip_heredocs` runs on every Bash `tool_use` input of every transcript. Bash accepts an unterminated heredoc (warning "here-document delimited by end-of-file") and still executes it, so an agent that forgets the terminator produces exactly this input. `contamination()` (`:1476`) then never returns; `post_run` has no timeout around the grade (`head/evals/harness/run-ablation.sh:996`), the trial subshell never writes its `.result`, and `reap` (`run-ablation.sh:1194-1210`) waits forever. The watchdog covers only the pipeline (`.pgid`), not the grade. Dissent DISS-001 (BLOCKING) reports the same.
**Why This Matters:** One malformed command in one transcript hangs a whole batch with no row, no status change and no log line.
**Required Fix:** Make each repetition consume exactly one line and drop `re.S`:
```python
HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1[^\n]*\n(?:[^\n]*\n)*?[ \t]*\2[ \t]*(?=\n|$)")
```
Verified in the harness: 5,000 unterminated lines in 0.7 ms and identical output on the four heredoc shapes AG-10 uses (`cat > n.md <<EOF…`, a heredoc followed by a real reach, `python3 - <<'PY'`, `<<-EOF`). Add an AG case with a 40-line unterminated heredoc under a time bound.
**Reference:** CWE-1333 (Inefficient Regular Expression Complexity)

### 2. Correctness: heredoc stripping removes executed bodies and header-line targets

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:1412` — `body = strip_heredocs(val)` removes every heredoc body before the outside-path scan, and the regex also swallows the rest of the header line (`[^\n]*\n` at `:1377`). Harness results, container mode, all `None` on head and `outside_path` on base: `python3 - <<'PY'\nprint(open('/root/.ssh/id_rsa').read())\nPY`; `bash <<EOF\ncat /home/operator/secret\nEOF`; `cat <<'EOF' > /root/.ssh/authorized_keys\nssh-rsa …\nEOF`; `cat <<EOF | tee /home/operator/notes.txt\n…\nEOF`.
**File:** `head/evals/harness/ablation-grade.sh:1377-1383` (rule), `:1412` (application)
**Issue:** DEC-0541's rationale is "written report prose is data", which holds for a body written to a file. It does not hold (a) when the heredoc is the program (`bash`, `sh`, `python3 -`, `node -`, `perl -`, `eval`, `xargs`), the pattern this repository uses for its own Python and one Claude Code agents emit constantly, and (b) for the redirect or pipe target that follows `<<EOF` on the same line, which is the most common heredoc-with-redirect form and is a write outside the sandbox, not prose. Such a run is rowed `completed`, `contaminated: null`, and enters the paired analysis as valid data. Dissent DISS-002 and DISS-C-001 (both BLOCKING) report the two halves.
**Why This Matters:** The contamination check is the only mechanism excluding a run that reached outside the sandbox from the pre-registered decision. A silent false negative here biases the primaries the report decides on.
**Required Fix:** Replace only the body, never the header line: `HEREDOC.sub` should keep group text up to and including the first `\n` (e.g. make the header `([^\n]*\n)` a group and substitute `<<HEREDOC\1`). Then strip bodies only when the command word before `<<` is not an interpreter: scan each body whose command token matches `^(bash|sh|zsh|dash|python[0-9.]*|node|perl|ruby|awk|eval|xargs|env)$` with the same `ABS_WORD` loop. Add AG cases for `python3 - <<'PY'` reaching `/root/…` (hit), `cat <<'EOF' > /root/x` (hit) and `cat > notes.md <<EOF` naming `/home/operator` (clean).
**Reference:** CWE-184 (Incomplete List of Disallowed Inputs)

### 3. Correctness: the hidden-test probe is no longer detected in Bash commands

- **HIGH** (confidence: medium) `head/evals/harness/ablation-grade.sh:1329` — `HIDDEN_TOKEN` matches `hidden` only in capitals or adjacent to `/ . _ = -`. Harness results, head `None` / base `hidden`: `grep -ri hidden .`, `find . -iname '*hidden*'`, `ls hidden`, `cd hidden`, `cat hidden`, `ls HiddenTests`. Only `ls hidden/` still hits.
**File:** `head/evals/harness/ablation-grade.sh:1329`, applied at `:1394-1395`
**Issue:** DEC-0551 was motivated by prose inside a reviewer's heredoc ("any hidden interaction with store_true"). The fix tightened the rule for the whole command text, so the most direct probes for the answer key, a case-insensitive grep or find for the word, and a bare directory argument, pass as clean, while the Read/Grep/Glob fields (`:1396`) still use the case-insensitive substring. The header at `:166-168` still describes the old rule. Dissent DISS-C-005 reports the case-insensitive probes (it rated them ADVISORY; I rate the loss of `grep -ri hidden .` as blocking because `hidden_test_pass_rate` is the primary metric this probe compromises).
**Why This Matters:** A run that searched for and possibly read the hidden tests is counted as a valid `hidden_test_pass_rate` observation.
**Required Fix:** Outside heredoc bodies (where prose is not expected) use the base rule, `"hidden" in low` or at least `(?i)\bhidden`; inside heredoc bodies keep the token-shape rule. Keep the two DEC-0551 prose examples (both inside heredocs) as the clean cases, and add `grep -ri hidden .`, `find . -iname '*hidden*'` and `cd hidden && ls` as hits.
**Reference:** CWE-184

---

## Observations

### 1. Grader calibration — further false negatives against the base grader

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:1372-1374` — `in_quotes` decides "inside a literal" by the parity of `'` and `"` counts before the word, so one apostrophe inside a double-quoted string flips every later single-component word. Harness: `echo "don't panic"; cd /root && cat .ssh/id_rsa` → `None` (base: `outside_path`); `echo "it's fine" && ls /home` → `None`. Apostrophes in `echo` and commit-message strings are common agent output. Dissent DISS-003.
**File:** `head/evals/harness/ablation-grade.sh:1372-1374`, applied at `:1444`
**Suggestion:** Walk the text once tracking the open quote (a `'` inside `"…"` and a `"` inside `'…'` are literal, `\"` is escaped) instead of counting; or restrict the rule to the calibrated shape (`grep -E ' /tmp | /home '`) by requiring the quote to open on the same word.
**Benefit:** Keeps DEC-0551's accepted false-positive fix without reopening the `/root` `/home` false negative the single-component carve-out was meant to keep.

- **LOW** (confidence: medium) `head/evals/harness/ablation-grade.sh:1365-1370` and `:1438` — `after_closing_quote` accepts an empty or variable-only quoted prefix (`cat ''/root/.ssh/id_rsa`, `cat "$X"/root/.ssh/id_rsa` with X unset → `None`), and the `/.` skip runs on the raw word before `normpath`, so `/./root/.ssh/id_rsa`, `/../root/.ssh/id_rsa`, `/.dockerenv` and host-mode `cat "$HOME"/.ssh/id_rsa` are all clean (base: `outside_path`). Adversarial shapes. Dissent DISS-004, DISS-C-002.
**Suggestion:** Require a non-empty quoted span in `after_closing_quote`; apply the `/.` skip only to a word that follows a closing quote, and normalise before any skip.

- **LOW** (confidence: medium) `head/evals/harness/ablation-grade.sh:1350-1352` and `:1409-1414` — in container mode `home_word_outside()` is false, so a `~/`, `$HOME/` or `${HOME}/` word is never normalised nor added as a candidate: `cat ~/../../root/.ssh/id_rsa`, `cat $HOME/../../etc/shadow` and a Read of `~/../../etc/shadow` are clean (base: `outside_path`). Dissent DISS-C-003.
**Suggestion:** In container mode, rewrite the home prefix to `/home/evaluser` and run the word through `outside()` like any other candidate.

- **LOW** (confidence: low) `head/evals/harness/ablation-grade.sh:1362` — `SENSITIVE_SINGLE` omits `Users` (macOS homes; host mode is a supported executor), `run` (`/run/secrets`), `private` and `data`; `cd /Users && ls` is clean in host mode (base: `outside_path`). Dissent DISS-C-004.
**Suggestion:** Add `Users`, `run`, `private` to the set, or invert it to a short allow-list of command-token shapes (Loa slash commands, sed/awk delimiters).

### 2. run-ablation.sh — process and state handling

- **MEDIUM** (confidence: medium) `head/evals/harness/run-ablation.sh:933-941` — `cleanup` sends TERM to each recorded process group and then unconditionally `rm -rf "$JOBS_DIR"`. A pipeline that outlives TERM (a `docker run` child, a phase that traps) keeps spending, but its `.pgid` record is gone, so the guard at `run-ablation.sh:838-845` cannot refuse the next `--resume`, which launches the same trial again into `-r2`. The header promises the guard only for a SIGKILLed driver; RAB-13 exercises it with a `sleep` that dies on TERM.
**Suggestion:** After TERM, wait up to `WATCHDOG_GRACE`, SIGKILL, and delete only the `.pgid` files whose group is dead; leave the others so the guard fires.
**Benefit:** Prevents a duplicate spending trial after an operator interrupt during a real container run.

- **MEDIUM** (confidence: high) `head/evals/harness/run-ablation.sh:863` with `:1326-1341` — `RERUN_LIST` is seeded only from the `--rerun` / `--rerun-status` flags; `STATUS.json rerun_pending` (written at `:918`) is never read back. A resume that flags reruns and stops before dispatching them (a cut, the outage breaker, a signal) records them as pending, and the next plain `--resume` treats their stale rows as done and reports `complete`.
**Suggestion:** On resume, union `rerun_pending` from STATUS.json into `RERUN_LIST` (and into `RERUN_OLD` from the rows), or document that the flags must be re-passed and clear `rerun_pending` when they are not.
**Benefit:** The documented `rerun_pending` state becomes actionable instead of silently dropped.

- **LOW** (confidence: high) `head/evals/harness/run-ablation.sh:1120-1125` and `:1158-1161` — a trial that ends with no row is charged `RUN_CAP` in this driver only; on resume spend is rebuilt from rows + ledger (`:1304`, `:1344`) so the charge disappears, the pipeline's real `spent_usd` is never read, and `outage_tick "$rid" ""` (`:1123`) resets the breaker as if the trial had succeeded.
**Suggestion:** Read `meta/pipeline.json spent_usd` into the ledger for a rowless trial, and treat "no row" as neutral for the breaker rather than a reset.

- **LOW** (confidence: medium) `head/evals/harness/run-ablation.sh:1395` — `CUTS_JSON` is reloaded from the previous STATUS.json (`:1302`), so any later resume that leaves trials unrowed for another reason (paused arm, signal) ends with "partial (cut max_usd)".
**Suggestion:** Test `STOP == cut` for the message, keep `cuts[]` as history.

- **LOW** (confidence: medium) `head/evals/harness/run-ablation.sh:1075` — the duplicate check counts the compact form `"run_id":"…"` with `grep -cF`; a row written without `jq -c` (or by `json.dumps` with its default `": "` separator) counts 0 and the batch ends `failed 3` with "run_id rowed 0 times" although the row is present and valid. The resume path already uses jq (`:1324`).
**Suggestion:** Count with the same jq filter as `:1324`.

### 3. ablation-report.py

- **LOW** (confidence: low) `head/evals/harness/ablation-report.py:442` — `self.task_type[task] = ttype` takes the last row's type when a task id appears with two `task_type` values across batches; the Method text does not say which wins. Pairing in `compare` (`:494-549`) is per task over whatever trials each side holds, which the Method section describes correctly.
**Suggestion:** Raise `Fail` on a task id with conflicting types, as the arm_map conflict already does at `:431-433`.

### 4. Documentation and process

- **MEDIUM** (confidence: low) `head/evals/harness/ablation-grade.sh:258` — the grader version moves 1.2.0 → 1.2.5 and `run-ablation.sh` adds a dozen flags, yet the diff carries no CHANGELOG, NOTES or DEC record although six commit messages in the report cite "CHANGELOG Sprint 260" and DEC-0540 … DEC-0559; the frozen PR has 17 files, all under `evals/` and `.gitignore`. If those files exist on the real branch nothing is needed; if not, the calibration is undocumented outside the script header.
- The implementation report (`pr/PR.md`) has no `## AC Verification` walkthrough and no evidence that `bats evals/tests/*.bats` or shellcheck ran (`FAST-GATE:`). Not counted; the verdict rests on the code findings above.

### 5. Complexity

- **LOW** (confidence: high) `head/evals/harness/run-ablation.sh:1008-1064` — `run_trial` is 57 lines and `collect` (`:1118-1166`) 49; `head/evals/harness/ablation-report.py:717-1049` `build()` is about 330 lines of rendering. `SIMPLICITY[shrink]`: split `build()` into the analysis and the Markdown/JSON emitters; the runner functions are at the limit but each has a header comment. Over-engineering pass: Lean already. Ship.

---

## Cross-Model Observations

Dissent envelope: `grimoires/loa/a2a/sprint-1/adversarial-review.json` (type review, primary gpt-5.5-pro via codex-headless, companion claude-headless, 2/2 voices succeeded, chain_health ok). Nine findings; every one was re-checked in the harness against base and head before being folded in:

- DISS-001 (heredoc ReDoS) → Changes Required §1.
- DISS-002 and DISS-C-001 (executed heredoc bodies; header-line redirect target) → Changes Required §2.
- DISS-C-005 (case-insensitive `hidden` probes) → Changes Required §3, severity raised from ADVISORY.
- DISS-003 (`in_quotes` parity) → Observations §1 MEDIUM.
- DISS-004 and DISS-C-002 (glued quote, `/.` skip before normpath) → Observations §1 LOW.
- DISS-C-003 (home-prefix traversal in container mode) → Observations §1 LOW.
- DISS-C-004 (`SENSITIVE_SINGLE` omissions) → Observations §1 LOW.

## Rejected dissent payloads

- none — `metadata.rejected_summary` is empty and the listed sidecar `adversarial-rejected-review.jsonl` holds 0 rows.

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion (the PR's own scope) | Status | Notes |
|-----------|--------|-------|
| `run-ablation.sh`: pre-flight (hard gate, freeze, corpus, image, pinned tree), plan, dispatch, watchdog, retry, took-effect pause, drift guard, spend, resume, rerow, rerun, outage breaker | Pass (by reading) | `run-ablation.sh:556-638`, `640-690`, `1008-1064`, `1169-1210`, `1298-1352`; collaborators absent here so `run-ablation.bats` was not executed. Observations §2 |
| `lib/arms-common.sh` extracted from `run-arms.sh` without behaviour change | Pass | `arms-common.sh:53-157` vs the removed `run-arms.sh` blocks; `est_record`/`est_next` keyed by arm name equal the old index-keyed sums |
| `ablation-report.py`: pre-registered rules, guard first, bootstrap, MDE, cuts, H1/A4, md + json | Pass | `ablation-report.bats` 22/22 pass here |
| `ablation-row.sh` DEC-0545 degraded = substitution | Pass | `ablation-row.sh:316-321`; `ablation-row.bats:145-156` |
| Grader 1.2.1–1.2.5 calibration without new false negatives | Fail | Changes Required §1–3, Observations §1 |
| Suite `rules.predicates` order (DEC-0530) mirrored in report and tests | Pass | `ablation-2.0.yaml:89-95`, `ablation-report.py:588-591`, `arm-toggles.bats:268` |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [x] Input validation at the CLI boundary (`run-ablation.sh:307-351`: arm, batch, image, seed and env values are regex-checked; `ablation-report.py` refuses symlinked outputs and unknown schema majors)
- [x] No shell string interpolation: `subprocess.run([...])` list form (`ablation-report.py:246`), `jq --arg` throughout
- [ ] Contamination guard regressions (Changes Required §1–3) — the only security-relevant check in the diff, weakened
- [x] Error messages do not leak sensitive data

---

## Code Quality Summary

**Strengths:**
- Every rule carries its DEC id and the observed case that motivated it; the headers are complete specifications.
- Resume reconciliation treats the rows file as truth and the tests pin the spend identities (`spent = rows + ledger`).
- The report pins determinism per interval (`random.Random(seed)` per bootstrap) and quotes the pre-registered block verbatim; AR-12 checks it.

**Areas for Improvement:**
- Calibration against observed false positives has, four times in a row (1.2.2 to 1.2.5), widened a skip rule past the shape that triggered it; each widening needs a paired false-negative test against the base behaviour (the AG-10 block only asserts the new clean cases).
- The grade step has no timeout under the runner; any grader hang is a batch hang.

---

## Next Steps

1. Fix the heredoc regex, scope heredoc stripping to the body of file writes, and restore the `hidden` probe outside heredoc bodies (Changes Required §1–3), each with the paired AG cases.
2. Decide on the medium observations; the `in_quotes` and `rerun_pending` ones are small.
3. Re-run `bats evals/tests/ablation-grade.bats evals/tests/run-ablation.bats` and record the output in the report.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":4,"low":8},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T11:12:00Z"} -->
