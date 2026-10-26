# Annotation result — pr-30

| measure | n | kappa | observed agreement |
|---|---|---|---|
| hunks | 4 | 1.0000 | 1.0000 |
| incidents | 4 | n/a | 1.0000 |
| severity | 2 | n/a | 1.0000 |

- localization: 2 of 2 agreed defects overlap (share 1.0000), median anchor distance 0, 0 file mismatch(es)
- grouping: Jaccard 0.5000 (A 6 pair(s), B 3, both 3)
- items: 8; disagreements: 4; adjudicated: 4; adjudication share 0.5000
- defects: 2 (fix-commit 2); review-driven share 0.0000

| defect | file | anchors | severity | label_source | agreement | review_driven | members |
|---|---|---|---|---|---|---|---|
| V01 | packages/vite/src/node/optimizer/optimizer.ts | 149,150,151,152,153,154,155,156 | medium | fix-commit | adjudicated | false | H01 |
| V02 | packages/vite/src/node/optimizer/optimizer.ts | 149,150,155,156,340,341 | medium | fix-commit | adjudicated | false | H02 |
