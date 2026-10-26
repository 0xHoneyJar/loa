# Annotation result — pr-31

| measure | n | kappa | observed agreement |
|---|---|---|---|
| hunks | 5 | 1.0000 | 1.0000 |
| incidents | 1 | n/a | 1.0000 |
| severity | 3 | n/a | 1.0000 |

- localization: 3 of 3 agreed defects overlap (share 1.0000), median anchor distance 0, 0 file mismatch(es)
- grouping: Jaccard 1.0000 (A 4 pair(s), B 4, both 4)
- items: 6; disagreements: 1; adjudicated: 1; adjudication share 0.1667
- defects: 2 (fix-commit 1, fix-commit+incident 1); review-driven share 0.0000

| defect | file | anchors | severity | label_source | agreement | review_driven | members |
|---|---|---|---|---|---|---|---|
| V01 | pydantic/json_schema.py | 1983,1985,1986 | medium | fix-commit+incident | adjudicated | false | H02,I01 |
| V02 | pydantic/json_schema.py | 3242 | medium | fix-commit | agreed | false | H05 |
