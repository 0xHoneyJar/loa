# Annotation result — pr-24

| measure | n | kappa | observed agreement |
|---|---|---|---|
| hunks | 31 | 0.7842 | 0.9032 |
| incidents | 8 | 1.0000 | 1.0000 |
| severity | 10 | 0.2105 | 0.7000 |

- localization: 10 of 10 agreed defects overlap (share 1.0000), median anchor distance 0, 0 file mismatch(es)
- grouping: Jaccard 0.9630 (A 26 pair(s), B 27, both 26)
- items: 39; disagreements: 11; adjudicated: 11; adjudication share 0.2821
- defects: 9 (fix-commit 8, incident 1); review-driven share 0.7778
- review-derived key (c131): 4 of 4 defect(s) lie within ±3 lines of a v2 defect

| defect | file | anchors | severity | label_source | agreement | review_driven | members |
|---|---|---|---|---|---|---|---|
| V01 | evals/harness/ablation-grade.sh | 256 | low | fix-commit | agreed | false | H04 |
| V02 | evals/harness/ablation-grade.sh | 1329,1395 | medium | fix-commit | adjudicated | true | H05,H08 |
| V03 | evals/harness/ablation-grade.sh | 1369,1372,1373,1374,1377 | medium | fix-commit | adjudicated | true | H06 |
| V04 | evals/harness/ablation-grade.sh | 1372,1373,1374,1444 | low | fix-commit | adjudicated | true | H12 |
| V05 | evals/harness/ablation-grade.sh | 1377,1383 | medium | fix-commit | adjudicated | true | H07 |
| V06 | evals/harness/ablation-grade.sh | 1401,1402 | medium | incident | adjudicated | false | I01 |
| V07 | evals/harness/ablation-grade.sh | 1422,1423 | medium | fix-commit | adjudicated | true | H10 |
| V08 | evals/harness/ablation-grade.sh | 1438 | medium | fix-commit | agreed | true | H11 |
| V09 | evals/harness/run-ablation.sh | 976,978,980,996,997 | medium | fix-commit | adjudicated | true | H25,H26 |
