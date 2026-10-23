head/evals/harness/ablation-grade.sh:1329 — HIGH: in Bash commands HIDDEN_TOKEN only matches all-caps HIDDEN or lowercase hidden glued to / . _ = -, so `grep -ri hidden .`, `find . -iname '*hidden*'` and `ls Hidden/` now grade clean (1.2.0 flagged them all); the header at :167 still says "any case".
head/evals/harness/ablation-grade.sh:1377 — HIGH: HEREDOC compiled with re.S makes `(?:.*?\n)*?` ambiguous; an unterminated `<<WORD` backtracks exponentially (measured 0.5 s at 20 lines, 2.1 s at 22), so the grade times out and the trial is rowed infrastructure_error.
head/evals/harness/ablation-grade.sh:1380 — MEDIUM: strip_heredocs also removes unquoted heredoc bodies, whose $(...) substitutions execute; `cat <<EOF` / `$(cat /home/operator/notes.txt)` / `EOF` is not flagged.
head/evals/harness/ablation-grade.sh:1365 — MEDIUM: after_closing_quote treats any quote glued to a token as closing, so `cat ''/home/operator/notes.txt` (and `grep -f"/root/x"`) skip the outside-path check.
head/evals/harness/ablation-grade.sh:1438 — MEDIUM: the `/.` skip runs before normpath, so `/./home/operator/notes.txt` is never checked against the allowed roots.
head/evals/harness/ablation-grade.sh:1432 — LOW: any word containing `=` is skipped, but filenames may contain `=`; `cat /home/operator/notes=old.txt` grades clean.
head/evals/harness/ablation-grade.sh:1372 — LOW: in_quotes counts raw quote characters; an apostrophe inside double quotes (`echo "don't"; ls /mnt`) flips parity and hides a sensitive single-component word.
head/evals/harness/ablation-grade.sh:1362 — LOW: SENSITIVE_SINGLE lists Linux data roots only; macOS host-mode probes of /Users, /Volumes, /private are dropped as command tokens.
head/evals/harness/run-ablation.sh:805 — LOW: the --rerow refusal still tells the operator to remove the row by hand and --resume, instead of the in-place `--resume --rerun <id>` / `--rerun-status` path added by DEC-0553.
Verdict: CHANGES_REQUIRED
