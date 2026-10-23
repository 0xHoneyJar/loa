# Annotation result — pr-22

| measure | n | kappa | observed agreement |
|---|---|---|---|
| hunks | 79 | 0.8857 | 0.9494 |
| incidents | 9 | 0.6087 | 0.8889 |
| severity | 25 | 0.5763 | 0.7600 |

- localization: 25 of 25 agreed defects overlap (share 1.0000), median anchor distance 0, 0 file mismatch(es)
- grouping: Jaccard 0.6139 (A 62 pair(s), B 101, both 62)
- items: 88; disagreements: 44; adjudicated: 44; adjudication share 0.5000
- defects: 20 (fix-commit 18, fix-commit+incident 1, incident 1); review-driven share 0.9000
- review-derived key (c131): 9 of 11 defect(s) lie within ±3 lines of a v2 defect

| defect | file | anchors | severity | label_source | agreement | review_driven | members |
|---|---|---|---|---|---|---|---|
| V01 | evals/harness/Dockerfile.ablation | 19,20 | medium | fix-commit | agreed | true | H01 |
| V02 | evals/harness/Dockerfile.ablation | 69,72 | low | fix-commit | agreed | true | H02 |
| V03 | evals/harness/ablation-row.sh | 122 | low | fix-commit | agreed | true | H08 |
| V04 | evals/harness/ablation-row.sh | 168,171,173,176,178,179,180,224,225,226 | high | fix-commit | adjudicated | true | H09,H12 |
| V05 | evals/harness/ablation-row.sh | 200,201,202,203,205,206 | high | fix-commit | adjudicated | true | H10 |
| V06 | evals/harness/ablation-row.sh | 230,313 | medium | fix-commit | adjudicated | false | H17 |
| V07 | evals/harness/ablation-row.sh | 247,285,303,304,305,306,307 | medium | fix-commit | adjudicated | true | H13,H15,H16 |
| V08 | evals/harness/ablation-row.sh | 326,327 | medium | fix-commit | adjudicated | true | H18 |
| V09 | evals/harness/execute-agent.sh | 212,213,214,215 | medium | fix-commit | adjudicated | true | H21 |
| V10 | evals/harness/execute-agent.sh | 268,269 | low | fix-commit | agreed | true | H23 |
| V11 | evals/harness/fingerprint.sh | 52,53,54,55 | low | fix-commit | agreed | true | H27 |
| V12 | evals/harness/freeze.sh | 66,67,68,69,70 | medium | fix-commit | adjudicated | true | H30 |
| V13 | evals/harness/pipeline-run.sh | 79,80 | high | incident | adjudicated | false | I01 |
| V14 | evals/harness/pipeline-run.sh | 486,487,488,492,497 | high | fix-commit+incident | adjudicated | true | H41,I03 |
| V15 | evals/harness/pipeline-run.sh | 775,776,777,778 | high | fix-commit | adjudicated | true | H42 |
| V16 | evals/harness/run-arms.sh | 378,391 | medium | fix-commit | adjudicated | true | H52,H53 |
| V17 | evals/harness/run-arms.sh | 505,506,507,508,522,523 | medium | fix-commit | adjudicated | true | H54,H55 |
| V18 | evals/harness/spend.sh | 121,122,134,135,136,137,138,139,140,141 | medium | fix-commit | adjudicated | true | H59,H60 |
| V19 | evals/harness/spend.sh | 159,160,169,173,174 | medium | fix-commit | adjudicated | true | H61,H62 |
| V20 | evals/harness/took-effect.sh | 86,87,88 | high | fix-commit | adjudicated | true | H65 |
