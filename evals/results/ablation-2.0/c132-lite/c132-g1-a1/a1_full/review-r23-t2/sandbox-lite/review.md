head/evals/tests/pipeline-run.bats:498 — bare `! grep -rqF` inside the for loop is inert under bats (ERR trap and set -e skip `!`-inverted commands); the "no hidden byte reached the sandbox/snapshots/transcripts" assertion cannot fail (also line 503); reproduced on bats 1.13.0
head/evals/harness/ablation-grade.sh:864 — envelope_texts never reads anchor_line; real dissent envelopes carry anchor "path:symbol" + anchor_line with no file/line, so every defect caught only by the adversarial review or audit is graded as missed and absent from flags
head/evals/tests/ablation-grade.bats:16 — BATS_BIN is the author's personal dotfiles path; the symlink at line 48 dangles elsewhere and the stub PATH (line 51) only finds bats in /usr/bin, so AG-2 and AG-7 fail on any other host (bats is /usr/local/bin here)
head/evals/harness/ablation-grade.sh:710 — tarfile.data_filter / extractall(filter=) need Python ≥3.11.4; unchecked host interpreter (3.11.2 here) makes every run with a snapshot bundle exit 2 "internal error"
head/evals/harness/ablation-grade.sh:1091 — an unparseable base regression run sets base_ok=[] so newly_failing is always empty for exit-status-only regression commands; an unparseable final run reports every base test newly failing even at rc 0
head/evals/harness/ablation-grade.sh:652 — all_pass ignores rc and timed_out; a suite that prints its summary then hangs or crashes is green for gate accuracy and self-checks, and a forged summary line is never cross-checked against rc
head/evals/harness/ablation-grade.sh:964 — "hidden" substring and ABS_WORD on quoted route strings flag rg --hidden, grep "/api/users", ls /home as contamination; first hit short-circuits so one benign hit drops the run
head/evals/tests/ablation-grade.bats:501 — bare negations at 501, 502, 505, 512, 513 are inert; the DEC-0413 ids-only and no-source/eval checks cannot fail
head/evals/tests/seed-corpus.bats:189 — bare `! grep -qF` is inert; SC-7 would not notice src/real.sh being excluded
head/evals/harness/ablation-grade.sh:452 — hard dependency on evals/harness/freeze.sh, and the PR title's sixteen tasks and freeze are not in the diff; VS-1 (validate-suite.bats:32-44) counts committed tasks absent from this change
head/evals/harness/lib/seed_tasks.py:227 — patch invoked without --batch/-f and with inherited stdin; a missing-file prompt blocks the seeder on a TTY
head/evals/harness/lib/seed_tasks.py:196 — counts() reads the last line of stdout+stderr combined; a trailing stderr warning yields 0/0 and a spurious proof failure
head/evals/harness/seed-bugfix-tasks.sh:43 — header says refusals do not count toward --select, but a post-selection no-secrets refusal consumes a slot without back-fill
head/evals/harness/ablation-grade.sh:517 — on TimeoutExpired only the docker client is killed; the container keeps a rw mount into grading/<label> and the next fresh_dir can race it
head/evals/harness/ablation-grade.sh:213 — yq is required but never checked; a missing binary surfaces as "internal error: FileNotFoundError" instead of a startup usage error
head/evals/harness/ablation-grade.sh:1045 — grade() is 98 lines (load_task 100); split per concern
head/evals/harness/seed-corpus-from-record.sh:53 — 113-column header line, two sentences merged
Verdict: CHANGES_REQUIRED
