# Annotation result — pr-26

| measure | n | kappa | observed agreement |
|---|---|---|---|
| hunks | 54 | 0.5507 | 0.8148 |
| incidents | 2 | n/a | 1.0000 |
| severity | 10 | 0.6296 | 0.9000 |

- localization: 10 of 10 agreed defects overlap (share 1.0000), median anchor distance 0, 0 file mismatch(es)
- grouping: Jaccard 0.8462 (A 45 pair(s), B 51, both 44)
- items: 56; disagreements: 23; adjudicated: 23; adjudication share 0.4107
- defects: 9 (fix-commit 9); review-driven share 0.7778
- review-derived key (c131): 0 of 0 defect(s) lie within ±3 lines of a v2 defect

| defect | file | anchors | severity | label_source | agreement | review_driven | members |
|---|---|---|---|---|---|---|---|
| V01 | evals/harness/ablation-report.py | 549,550,551 | medium | fix-commit | agreed | false | H13 |
| V02 | evals/harness/ablation-report.py | 595,596,597,598,757,758,773,776,778,797,798,965,968,1321 | medium | fix-commit | adjudicated | false | H14,H15,H16,H17,H20,H25 |
| V03 | evals/harness/ablation-report.py | 825,827,831,832,833,835,836,839,840 | medium | fix-commit | adjudicated | true | H18 |
| V04 | evals/harness/ablation-report.py | 847,848,849,850,851,1403 | medium | fix-commit | adjudicated | true | H28 |
| V05 | evals/harness/ablation-report.py | 1054,1062,1063,1064,1065,1066,1067,1068,1069,1070,1080,1081,1082 | high | fix-commit | adjudicated | true | H22 |
| V06 | evals/harness/ablation-report.py | 1117,1339,1351,1592,1611 | low | fix-commit | adjudicated | true | H23,H26,H27,H30,H31 |
| V07 | evals/harness/ablation-report.py | 1552,1553 | medium | fix-commit | agreed | true | H29 |
| V08 | evals/harness/ablation-report.py | 1675,1676,1677 | medium | fix-commit | adjudicated | true | H34 |
| V09 | evals/harness/ablation-row.sh | 165,166,167,168,412,413 | medium | fix-commit | adjudicated | true | H40,H42 |
