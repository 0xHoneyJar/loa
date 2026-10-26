# Annotation result — pr-77

| measure | n | kappa | observed agreement |
|---|---|---|---|
| hunks | 9 | 1.0000 | 1.0000 |
| incidents | 0 | n/a | n/a |
| severity | 2 | n/a | 1.0000 |

- localization: 2 of 2 agreed defects overlap (share 1.0000), median anchor distance 0, 0 file mismatch(es)
- grouping: Jaccard 1.0000 (A 22 pair(s), B 22, both 22)
- items: 9; disagreements: 1; adjudicated: 1; adjudication share 0.1111
- defects: 2 (fix-commit 2); review-driven share 0.0000

| defect | file | anchors | severity | label_source | agreement | review_driven | members |
|---|---|---|---|---|---|---|---|
| V01 | cli/tools/installer/npm_compat.rs | 569,570,571,572,575,576,621,622,623 | medium | fix-commit | adjudicated | false | H08 |
| V02 | cli/tools/installer/npm_compat.rs | 609,610,611 | medium | fix-commit | agreed | false | H11 |
