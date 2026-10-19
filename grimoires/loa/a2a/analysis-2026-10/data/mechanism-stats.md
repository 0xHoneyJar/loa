## Activity per gate (means over the 3 trials)

| arm | task | phase | turns | tool calls | test runs | exec probes | tool output KB | truncated results | head files read | planted regions printed (head) | planted hunks printed (diff) | defects |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| a0_bare | review-01 | BARE | 10 | 9 | 0.0 | 0.0 | 32 | 0.0 | 0.0 | 2.7 | 3.0 | 3 |
| a0_bare | review-02 | BARE | 8 | 7 | 0.0 | 0.7 | 22 | 0.0 | 0.7 | 3.0 | 3.0 | 3 |
| a0_bare | review-03 | BARE | 24 | 23 | 1.0 | 0.3 | 148 | 1.0 | 1.0 | 4.3 | 5.0 | 8 |
| a0_bare | review-04 | BARE | 31 | 30 | 2.3 | 0.7 | 141 | 0.3 | 2.3 | 0.3 | 0.0 | 5 |
| a1_full | review-01 | REVIEW | 31 | 30 | 4.0 | 2.7 | 118 | 0.0 | 3.0 | 1.3 | 3.0 | 3 |
| a1_full | review-01 | AUDIT | 44 | 43 | 3.7 | 4.0 | 131 | 0.3 | 3.0 | 0.3 | 3.0 | 3 |
| a1_full | review-02 | REVIEW | 26 | 25 | 4.3 | 3.0 | 114 | 0.3 | 3.0 | 2.0 | 3.0 | 3 |
| a1_full | review-02 | AUDIT | 33 | 32 | 5.3 | 3.7 | 138 | 0.3 | 3.0 | 1.7 | 3.0 | 3 |
| a1_full | review-03 | REVIEW | 61 | 60 | 18.0 | 7.0 | 223 | 1.3 | 5.7 | 2.3 | 5.3 | 8 |
| a1_full | review-03 | AUDIT | 46 | 45 | 9.7 | 4.7 | 233 | 1.7 | 6.7 | 4.7 | 5.3 | 8 |
| a1_full | review-04 | REVIEW | 42 | 52 | 14.0 | 5.0 | 261 | 0.3 | 11.0 | 0.7 | 0.0 | 5 |
| a1_full | review-04 | AUDIT | 48 | 47 | 9.7 | 4.3 | 205 | 0.0 | 13.0 | 0.7 | 0.0 | 5 |

## Read-and-missed vs never-read (defect-trials, any phase of the run)

| arm | task | caught & region printed | caught, region not printed | missed & region printed | missed, region never printed | missed but hunk printed from the diff |
|---|---|---|---|---|---|---|
| a0_bare | review-01 | 8 | 1 | 0 | 0 | 0/0 |
| a0_bare | review-02 | 8 | 0 | 1 | 0 | 1/1 |
| a0_bare | review-03 | 6 | 0 | 7 | 11 | 9/18 |
| a0_bare | review-04 | 0 | 8 | 1 | 6 | 0/7 |
| a1_full | review-01 | 4 | 5 | 0 | 0 | 0/0 |
| a1_full | review-02 | 8 | 1 | 0 | 0 | 0/0 |
| a1_full | review-03 | 12 | 6 | 2 | 4 | 4/6 |
| a1_full | review-04 | 1 | 9 | 2 | 3 | 0/5 |

'Region printed' = a `sed -n`/`awk` range over the head file covering the anchor ±3 (grep -n/-A output and whole-file `cat` are not counted, so this under-counts reading); 'hunk printed' = the diff lines of the defect's hunk were displayed (`cat`/`sed -n` over head.diff, `diff -u base head`).

