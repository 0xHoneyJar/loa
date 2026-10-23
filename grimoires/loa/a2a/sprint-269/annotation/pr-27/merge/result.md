# Annotation result — pr-27

| measure | n | kappa | observed agreement |
|---|---|---|---|
| hunks | 28 | 1.0000 | 1.0000 |
| incidents | 3 | 1.0000 | 1.0000 |
| severity | 18 | 1.0000 | 1.0000 |

- localization: 18 of 18 agreed defects overlap (share 1.0000), median anchor distance 0, 0 file mismatch(es)
- grouping: Jaccard 0.9730 (A 37 pair(s), B 36, both 36)
- items: 31; disagreements: 6; adjudicated: 6; adjudication share 0.1935
- defects: 13 (fix-commit 12, fix-commit+incident 1); review-driven share 0.7692
- review-derived key (c131): 5 of 7 defect(s) lie within ±3 lines of a v2 defect

| defect | file | anchors | severity | label_source | agreement | review_driven | members |
|---|---|---|---|---|---|---|---|
| V01 | evals/graders/recall-vs-defects.sh | 132,133,134,135,136,137 | high | fix-commit | agreed | true | H02 |
| V02 | evals/graders/recall-vs-defects.sh | 269,270,271,272,273,274 | medium | fix-commit | agreed | true | H03 |
| V03 | evals/graders/recall-vs-defects.sh | 298,299 | medium | fix-commit | agreed | true | H04 |
| V04 | evals/graders/recall-vs-defects.sh | 303,304,308,309 | medium | fix-commit | agreed | false | H05 |
| V05 | evals/graders/recall-vs-defects.sh | 329,330,331,332,333,337 | medium | fix-commit | adjudicated | false | H07 |
| V06 | evals/harness/ablation-grade.sh | 1629,1630,1631,1632,1633,1634,1635 | high | fix-commit | adjudicated | true | H09 |
| V07 | evals/harness/ablation-grade.sh | 1980,1981,1982,1985,1986 | high | fix-commit | agreed | true | H12 |
| V08 | evals/harness/ablation-grade.sh | 1986,1993,1994,1995 | high | fix-commit | adjudicated | true | H13 |
| V09 | evals/harness/ablation-grade.sh | 2007,2008,2009,2010,2011 | medium | fix-commit | agreed | true | H14 |
| V10 | evals/harness/ablation-grade.sh | 2065 | medium | fix-commit | adjudicated | true | H17 |
| V11 | evals/harness/ablation-grade.sh | 2159,2160,2161 | medium | fix-commit | agreed | true | H18 |
| V12 | evals/harness/ablation-grade.sh | 2203,2204,2205,2241,2243,2244,2245,2246,2247,2338,2343,2390,2391,2392,2464,2465,2466,2467 | medium | fix-commit+incident | adjudicated | true | H19,H20,H21,H22,H23,I02 |
| V13 | evals/harness/ablation-grade.sh | 2477,2478,2481,2482,2483 | medium | fix-commit | adjudicated | false | H24 |
