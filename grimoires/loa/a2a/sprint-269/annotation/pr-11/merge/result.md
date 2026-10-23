# Annotation result — pr-11

| measure | n | kappa | observed agreement |
|---|---|---|---|
| hunks | 18 | 0.7805 | 0.8889 |
| incidents | 15 | n/a | 1.0000 |
| severity | 8 | 0.0000 | 0.6250 |

- localization: 8 of 8 agreed defects overlap (share 1.0000), median anchor distance 0, 0 file mismatch(es)
- grouping: Jaccard 1.0000 (A 14 pair(s), B 14, both 14)
- items: 33; disagreements: 7; adjudicated: 7; adjudication share 0.2121
- defects: 5 (fix-commit 5); review-driven share 1.0000
- review-derived key (c131): 4 of 5 defect(s) lie within ±3 lines of a v2 defect

| defect | file | anchors | severity | label_source | agreement | review_driven | members |
|---|---|---|---|---|---|---|---|
| V01 | .claude/adapters/cheval.py | 2022,2032 | medium | fix-commit | adjudicated | true | H03,H04 |
| V02 | .claude/adapters/cheval.py | 2110,2256,2297 | medium | fix-commit | adjudicated | true | H05,H06,H07 |
| V03 | .claude/adapters/loa_cheval/metering/pricing.py | 171,172,173,174,175 | medium | fix-commit | agreed | true | H10 |
| V04 | .claude/adapters/loa_cheval/metering/pricing.py | 292,295 | medium | fix-commit | adjudicated | true | H12 |
| V05 | .claude/adapters/loa_cheval/routing/ceiling.py | 278,279,290,299 | medium | fix-commit | agreed | true | H14 |
