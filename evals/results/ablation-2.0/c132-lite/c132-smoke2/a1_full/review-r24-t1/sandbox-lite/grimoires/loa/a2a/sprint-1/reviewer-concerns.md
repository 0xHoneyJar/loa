# Reviewer concerns — sprint-1 (PR: sprint-260 batch runner, report, grader 1.2.1–1.2.5)

Scope: `pr/head.diff` (17 files). Lines cite `pr/head/<path>`.

## Confirmed by probe (python harness over the embedded grader, base vs head)

1. `evals/harness/ablation-grade.sh:1377-1381` HEREDOC regex `(?:.*?\n)*?` under `re.S` backtracks exponentially on an unterminated heredoc (22 lines = 1.7 s, x4 per 2 lines). Bash accepts unterminated heredocs with a warning, so an agent transcript can hang `contamination()` and the whole trial (post_run has no timeout; reap waits forever).
2. `ablation-grade.sh:1377-1384` strips EVERY heredoc body before the outside-path scan, including heredocs fed to an interpreter (`bash <<EOF`, `python3 - <<'PY'`). `python3 - <<'PY'\nopen('/root/.ssh/id_rsa')\nPY` is now clean; base grader flagged it. A contaminated trial counts as valid data.
3. `ablation-grade.sh:1372-1374` `in_quotes` parity count: `echo "don't panic"; cd /root && cat .ssh/id_rsa` → clean (base: outside_path). Apostrophes in double-quoted strings are common.
4. `ablation-grade.sh:1330` HIDDEN_TOKEN misses a bare `hidden` word in Bash (`ls hidden`, `cd hidden`, `cat hidden`); base caught.
5. `ablation-grade.sh:1366-1370` `after_closing_quote`: `cat ''/root/.ssh/id_rsa` and `cat "$X"/root/...` → clean. `/.`-prefix skip hides `/.dockerenv` and host-mode `"$HOME"/.ssh`.

## Read-only concerns in run-ablation.sh

6. `run-ablation.sh:933-943` cleanup on a TERM'd driver removes `.jobs/` after sending TERM, so a pipeline that outlives TERM (docker child) is invisible to the "earlier driver still runs" guard at 838-845 on the next --resume.
7. `run-ablation.sh:863,1326-1341` `rerun_pending` in STATUS.json is never read back on --resume; flagged-but-unlaunched reruns become "done" again unless the flags are re-passed.
8. `run-ablation.sh:1120-1125,1158-1161` a trial that ends with no row loses its assumed-cap charge on resume (spend recomputed from rows + ledger only); `outage_tick "$rid" ""` resets the breaker for it.
9. `run-ablation.sh:1395` stale `cuts[]` loaded on resume makes a later partial end report "cut max_usd" whatever the cause.
10. `run-ablation.sh:1075` duplicate check greps the compact `"run_id":"…"` form; a non-compact row fails the batch with "rowed 0 times".

## ablation-report.py

11. Pairing is per task over whichever trials each side has (`compare`, 499-549); an arm with 3 valid trials vs control with 2 is still one pair. By design, but check the Method text claims it.
12. `_classify` 442: a task id seen with two task_types silently takes the last.

## Process

- No CHANGELOG / NOTES / DEC records in the diff although the commit list cites them.
- Implementation report (PR.md) has no AC verification walkthrough and no test-run evidence (bats/shellcheck).
- run-ablation.bats / ablation-grade.bats / ablation-row.bats cannot run here (collaborator scripts absent); ablation-report.bats ran: 22/22 pass.
