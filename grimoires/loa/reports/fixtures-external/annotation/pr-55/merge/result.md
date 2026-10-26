# Annotation result — pr-55

| measure | n | kappa | observed agreement |
|---|---|---|---|
| hunks | 17 | 0.7213 | 0.8824 |
| incidents | 2 | 0.0000 | 0.5000 |
| severity | 4 | 1.0000 | 1.0000 |

- localization: 4 of 4 agreed defects overlap (share 1.0000), median anchor distance 0, 0 file mismatch(es)
- grouping: Jaccard 0.4800 (A 25 pair(s), B 12, both 12)
- items: 19; disagreements: 11; adjudicated: 11; adjudication share 0.5789
- defects: 5 (fix-commit 4, incident 1); review-driven share 0.0000

| defect | file | anchors | severity | label_source | agreement | review_driven | members |
|---|---|---|---|---|---|---|---|
| V01 | packages/vite/src/node/plugins/css.ts | 397 | medium | fix-commit | agreed | false | H06 |
| V02 | packages/vite/src/node/plugins/css.ts | 991 | medium | incident | adjudicated | false | I02 |
| V03 | packages/vite/src/node/plugins/importAnalysisBuild.ts | 315,316,317,318,331,332,333 | high | fix-commit | adjudicated | false | H12 |
| V04 | packages/vite/src/node/plugins/importAnalysisBuild.ts | 340,343,344 | medium | fix-commit | adjudicated | false | H13 |
| V05 | packages/vite/src/node/plugins/importAnalysisBuild.ts | 385,386,387,388,389 | medium | fix-commit | adjudicated | false | H14 |
