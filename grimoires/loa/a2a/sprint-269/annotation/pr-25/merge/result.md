# Annotation result — pr-25

| measure | n | kappa | observed agreement |
|---|---|---|---|
| hunks | 29 | 0.8380 | 0.9655 |
| incidents | 10 | n/a | 1.0000 |
| severity | 3 | -0.2000 | 0.3333 |

- localization: 3 of 3 agreed defects overlap (share 1.0000), median anchor distance 0, 0 file mismatch(es)
- grouping: Jaccard 0.3725 (A 19 pair(s), B 51, both 19)
- items: 39; disagreements: 12; adjudicated: 12; adjudication share 0.3077
- defects: 4 (fix-commit 4); review-driven share 1.0000
- review-derived key (c131): 0 of 1 defect(s) lie within ±3 lines of a v2 defect

| defect | file | anchors | severity | label_source | agreement | review_driven | members |
|---|---|---|---|---|---|---|---|
| V01 | evals/harness/ablation-grade.sh | 1079,1080,1081,1086,1087,1093,1096,1098,1100 | high | fix-commit | adjudicated | true | H04 |
| V02 | evals/harness/pipeline-run.sh | 633,634,635,636,637,640 | critical | fix-commit | adjudicated | true | H07 |
| V03 | evals/harness/run-ablation.sh | 786,788,806 | medium | fix-commit | adjudicated | true | H14 |
| V04 | evals/harness/run-ablation.sh | 806,814,815,816,817 | high | fix-commit | adjudicated | true | H16 |
