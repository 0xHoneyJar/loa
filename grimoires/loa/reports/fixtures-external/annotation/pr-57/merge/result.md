# Annotation result — pr-57

| measure | n | kappa | observed agreement |
|---|---|---|---|
| hunks | 29 | 1.0000 | 1.0000 |
| incidents | 0 | n/a | n/a |
| severity | 5 | 0.6154 | 0.8000 |

- localization: 5 of 5 agreed defects overlap (share 1.0000), median anchor distance 0, 0 file mismatch(es)
- grouping: Jaccard 0.9130 (A 84 pair(s), B 92, both 84)
- items: 29; disagreements: 12; adjudicated: 12; adjudication share 0.4138
- defects: 4 (fix-commit 4); review-driven share 0.0000

| defect | file | anchors | severity | label_source | agreement | review_driven | members |
|---|---|---|---|---|---|---|---|
| V01 | libs/npm_cache/lib.rs | 77,78,79,80,81,82,83 | medium | fix-commit | adjudicated | false | H03 |
| V02 | libs/npm_cache/lib.rs | 412,465 | medium | fix-commit | agreed | false | H11 |
| V03 | libs/npm_cache/lib.rs | 571,572,573 | medium | fix-commit | adjudicated | false | H13 |
| V04 | libs/npm_installer/local.rs | 688,764,959,1058,1688,1689,1690,1692,1693,1695,1699 | high | fix-commit | adjudicated | false | H25,H26 |
