# Annotation result — pr-28

| measure | n | kappa | observed agreement |
|---|---|---|---|
| hunks | 9 | 1.0000 | 1.0000 |
| incidents | 2 | n/a | 1.0000 |
| severity | 3 | 1.0000 | 1.0000 |

- localization: 3 of 3 agreed defects overlap (share 1.0000), median anchor distance 0, 0 file mismatch(es)
- grouping: Jaccard 1.0000 (A 4 pair(s), B 4, both 4)
- items: 11; disagreements: 1; adjudicated: 1; adjudication share 0.0909
- defects: 3 (fix-commit 3); review-driven share 1.0000
- review-derived key (c131): 2 of 2 defect(s) lie within ±3 lines of a v2 defect

| defect | file | anchors | severity | label_source | agreement | review_driven | members |
|---|---|---|---|---|---|---|---|
| V01 | evals/harness/ablation-report.py | 1913 | high | fix-commit | agreed | true | H01 |
| V02 | evals/harness/ablation-report.py | 1927,1928,1929,1930,1931,1932 | low | fix-commit | adjudicated | true | H02 |
| V03 | evals/harness/pipeline-run.sh | 258,259 | high | fix-commit | agreed | true | H06 |
