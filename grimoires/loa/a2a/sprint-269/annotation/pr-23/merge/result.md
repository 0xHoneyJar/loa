# Annotation result — pr-23

| measure | n | kappa | observed agreement |
|---|---|---|---|
| hunks | 66 | 0.9380 | 0.9697 |
| incidents | 11 | 1.0000 | 1.0000 |
| severity | 28 | 0.8614 | 0.9286 |

- localization: 28 of 28 agreed defects overlap (share 1.0000), median anchor distance 0, 0 file mismatch(es)
- grouping: Jaccard 0.7922 (A 66 pair(s), B 72, both 61)
- items: 77; disagreements: 27; adjudicated: 27; adjudication share 0.3506
- defects: 13 (fix-commit 12, fix-commit+incident 1); review-driven share 0.6154
- review-derived key (c131): 1 of 1 defect(s) lie within ±3 lines of a v2 defect

| defect | file | anchors | severity | label_source | agreement | review_driven | members |
|---|---|---|---|---|---|---|---|
| V01 | evals/harness/ablation-grade.sh | 238,239,240,241,242 | high | fix-commit | adjudicated | true | H13 |
| V02 | evals/harness/ablation-grade.sh | 271,272,273,282,283,293,294,296,713,714 | high | fix-commit | adjudicated | true | H15,H16,H17,H31 |
| V03 | evals/harness/ablation-grade.sh | 493,673,674 | high | fix-commit | adjudicated | true | H20,H28 |
| V04 | evals/harness/ablation-grade.sh | 502,503,504,505,506,507,508,514,516,517,518,519,520,521,524 | medium | fix-commit | adjudicated | false | H21,H22 |
| V05 | evals/harness/ablation-grade.sh | 533,534,535,536,537,538,575,576,577 | medium | fix-commit | adjudicated | false | H23,H24 |
| V06 | evals/harness/ablation-grade.sh | 652,653,1091,1092,1093,1095,1209,1211,1214,1216,1219,1222,1224 | high | fix-commit | adjudicated | true | H27,H48 |
| V07 | evals/harness/ablation-grade.sh | 705,706,707,708,710,729,730,731,732 | medium | fix-commit | adjudicated | false | H30,H33 |
| V08 | evals/harness/ablation-grade.sh | 766,767,769,783,786,855,877,878,881 | medium | fix-commit | adjudicated | true | H35,H36,H37,H38 |
| V09 | evals/harness/ablation-grade.sh | 939,940,950,953,958,959,974,976,977,978,979,980,982 | medium | fix-commit+incident | adjudicated | false | H39,H40,H41,H42,I01 |
| V10 | evals/harness/ablation-grade.sh | 1080,1083,1089,1090,1091,1092,1093,1099,1100,1101,1102,1105,1121,1122,1129 | high | fix-commit | adjudicated | true | H45,H46 |
| V11 | evals/harness/ablation-grade.sh | 1240,1241 | medium | fix-commit | adjudicated | false | H49 |
| V12 | evals/harness/validate-suite.sh | 261,262 | low | fix-commit | adjudicated | true | H52 |
| V13 | evals/harness/validate-suite.sh | 276,279,280 | medium | fix-commit | adjudicated | true | H53 |
