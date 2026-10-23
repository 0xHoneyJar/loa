# Annotation result — pr-19

| measure | n | kappa | observed agreement |
|---|---|---|---|
| hunks | 20 | 1.0000 | 1.0000 |
| incidents | 10 | n/a | 1.0000 |
| severity | 15 | 0.2308 | 0.7333 |

- localization: 14 of 15 agreed defects overlap (share 0.9333), median anchor distance 0, 0 file mismatch(es)
- grouping: Jaccard 1.0000 (A 1 pair(s), B 1, both 1)
- items: 30; disagreements: 7; adjudicated: 7; adjudication share 0.2333
- defects: 15 (fix-commit 15); review-driven share 0.8667
- review-derived key (c131): 9 of 11 defect(s) lie within ±3 lines of a v2 defect

| defect | file | anchors | severity | label_source | agreement | review_driven | members |
|---|---|---|---|---|---|---|---|
| V01 | .claude/scripts/guard-yield.sh | 219,220,221,222,223,224,225,226,227,228,229 | medium | fix-commit | agreed | true | H01 |
| V02 | .claude/scripts/guard-yield.sh | 329,330,331,332,333,334,335 | high | fix-commit | adjudicated | true | H02 |
| V03 | .claude/scripts/guard-yield.sh | 390,391,392,393,394,395,396,397,398 | medium | fix-commit | adjudicated | false | H03 |
| V04 | .github/workflows/bats-tests.yml | 90,91 | medium | fix-commit | agreed | true | H04 |
| V05 | evals/harness/execute-agent.sh | 163,164,165,166 | medium | fix-commit | adjudicated | true | H05 |
| V06 | evals/harness/execute-agent.sh | 254,255,256,257,258 | medium | fix-commit | agreed | true | H06 |
| V07 | evals/harness/execute-agent.sh | 288,289 | medium | fix-commit | agreed | true | H07 |
| V08 | evals/harness/run-arms.sh | 56 | medium | fix-commit | agreed | true | H09 |
| V09 | evals/harness/run-arms.sh | 127,128,129 | medium | fix-commit | agreed | true | H10 |
| V10 | evals/harness/run-arms.sh | 141,142,143,144,145,146,147,148,149,150,151 | medium | fix-commit | agreed | true | H11 |
| V11 | evals/harness/run-arms.sh | 231,232 | medium | fix-commit | agreed | true | H12 |
| V12 | evals/harness/run-arms.sh | 314,315 | medium | fix-commit | adjudicated | true | H13 |
| V13 | evals/harness/run-arms.sh | 336,337,338 | medium | fix-commit | adjudicated | true | H14 |
| V14 | evals/harness/seed-corpus-from-record.sh | 111,112,113,114,115,116 | high | fix-commit | adjudicated | true | H15 |
| V15 | evals/harness/seed-corpus-from-record.sh | 307,309 | medium | fix-commit | adjudicated | false | H16 |
