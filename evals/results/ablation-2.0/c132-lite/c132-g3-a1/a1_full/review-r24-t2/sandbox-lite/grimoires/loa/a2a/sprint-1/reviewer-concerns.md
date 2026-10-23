# Reviewer concerns — sprint-1 (PR: sprint-260 batch runner, grader 1.2.x, report)

Scope: pr/head.diff (17 files). Phase 2 concerns for the dissenter to confirm or refute.

1. evals/harness/ablation-grade.sh:1329 HIDDEN_TOKEN — in Bash text `hidden` only counts next to / . _ = - or as HIDDEN. `grep -rn hidden .`, `find . -name '*hidden*'`, `ls | grep -i hidden` no longer register as a hidden probe (verified by running the regex). Discovery commands escape the contamination scan.
2. evals/harness/ablation-grade.sh:1372 in_quotes — raw quote counting; an apostrophe in a double-quoted string (echo "it's"; cat /root) flips parity and a sensitive one-component word is skipped.
3. evals/harness/ablation-grade.sh:1423 — any one-component word not in {root,home,mnt,media,srv} is a command token: `ls /secrets`, `ls /data`, `ls /boot` are no longer candidates.
4. evals/harness/ablation-grade.sh:1432 — `"=" in w` skips any path word containing `=` (cat /home/operator/notes=secret.txt).
5. evals/harness/run-ablation.sh:1071 append_and_validate — the row is appended BEFORE validation; an invalid row stays in the tracked runs.jsonl and a later --resume reads it as done.
6. evals/harness/run-ablation.sh:1155 collect — after a failed in-place replacement (STOP=invalid) the run is still added to DONE_LIST and account_row runs, so counters/spend reflect a row not in the file.
7. evals/harness/ablation-report.py:813,941 — table header hardcodes "90 % CI" while --level is configurable.
8. evals/harness/run-ablation.sh:1397 — a batch where every trial ends cap_failure exits 3 "failed: no trial completed" although every row is valid and scorable.
9. run-arms.sh refactor to lib/arms-common.sh: est_record "$arm" all + budget_gate "$a" "$n" — check parity with the removed per-arm ARM_SUM/ARM_N + POOL means.
10. ablation-report.py compare(): trials present only in one arm are not dropped; per-task means then average different trial sets.
