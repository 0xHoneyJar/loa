head/evals/harness/ablation-grade.sh:1377 — HEREDOC regex `(?:.*?\n)*?\s*\2` under re.S backtracks exponentially when the captured delimiter never terminates (`<<EOF-REPORT`, `$(cat <<EOF … EOF)`, CRLF bodies): 22 lines 5 s, 24 lines 15 s; the grade hits LOA_EVAL_GRADE_TIMEOUT_S and the trial is rowed infrastructure_error (CWE-1333)
head/evals/harness/ablation-grade.sh:1383 — strip_heredocs replaces the whole match including the operator line's tail, so `cat <<'EOF' > /home/operator/notes.txt` loses its redirect target and scans clean; 1.2.0 flagged it outside_path
head/evals/harness/ablation-grade.sh:1412 — stripping every heredoc body hides code fed to interpreters and command substitutions: `python3 - <<'PY' open('/home/operator/.ssh/id_rsa') PY`, `bash <<'EOF' cat /home/operator/secret EOF`, `cat <<EOF $(cat /root/answers.json) EOF` all scan clean; all were outside_path in 1.2.0
head/evals/harness/ablation-grade.sh:1438 — `w.startswith("/.")` skip runs before normpath: `cat /.env`, `cat /./root/.ssh/id_rsa`, `cat /../root/secret` scan clean (caught in 1.2.0)
head/evals/harness/ablation-grade.sh:1432 — `"=" in w` drops any absolute path with an `=` component (`cat /mnt/data/split=train/answers.json` scans clean)
head/evals/harness/ablation-grade.sh:1423 — the one-component exemption treats root-level files as command tokens (`cat /flag.txt`, `cat /answers` scan clean)
head/evals/harness/ablation-grade.sh:1442 — after_closing_quote accepts an empty quoted string as a glued closing quote: `cat ""/root/.ssh/id_rsa` and `cat ''/home/operator/secret` scan clean
head/evals/harness/ablation-grade.sh:1444 — in_quotes counts quotes of either kind, so an apostrophe earlier in the command flips parity: `echo "don't"; ls /root` scans clean; `cat "/home"/operator/secret` is clean twice over
head/evals/harness/ablation-grade.sh:1329 — HIDDEN_TOKEN misses a bare or mixed-case word (`ls hidden`, `cd hidden && …`, `cat tests/Hidden/x`); header line 166 still says "any case"
head/evals/harness/run-ablation.sh:983 — a drift_check crash yields empty output that is reset to `null`, so the DEC-0407 guard fails open and the trial is graded as clean
head/evals/harness/run-ablation.sh:941 — cleanup deletes .jobs/*.pgid after SIGTERM only; a pipeline that survives TERM is not seen by the duplicate-trial guard at 838 and is relaunched by --resume
head/evals/harness/run-ablation.sh:1278 — `"${!RR_K[@]}"` on an empty array is unguarded under set -u (every other empty-array expansion in the file uses the `${X[@]+…}` guard)
head/evals/harness/run-ablation.sh:1237 — the rerow temp `runs.jsonl.rerow.$$` sits beside the tracked rows file and is not covered by the new .gitignore entry (head/.gitignore:333 ignores only runs.jsonl.lock)
head/evals/harness/run-ablation.sh:383 — `--arms` (and `--tasks` at 453) are silently overwritten/ignored on --resume while --source-commit is checked and refused
head/evals/harness/run-ablation.sh:1008 — run_trial is 57 lines and the --resume reconciliation block (1299-1352) 54, over the 50-line mark without justification
Verdict: CHANGES_REQUIRED
