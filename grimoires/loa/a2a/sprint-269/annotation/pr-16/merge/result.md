# Annotation result — pr-16

| measure | n | kappa | observed agreement |
|---|---|---|---|
| hunks | 18 | 0.8800 | 0.9444 |
| incidents | 8 | n/a | 1.0000 |
| severity | 6 | 1.0000 | 1.0000 |

- localization: 6 of 6 agreed defects overlap (share 1.0000), median anchor distance 0, 0 file mismatch(es)
- grouping: Jaccard 0.3000 (A 9 pair(s), B 4, both 3)
- items: 26; disagreements: 11; adjudicated: 11; adjudication share 0.4231
- defects: 6 (fix-commit 6); review-driven share 0.6667
- review-derived key (c131): 3 of 4 defect(s) lie within ±3 lines of a v2 defect

| defect | file | anchors | severity | label_source | agreement | review_driven | members |
|---|---|---|---|---|---|---|---|
| V01 | .claude/scripts/grimoire-index.sh | 186,187,188,189,190,191,192 | medium | fix-commit | adjudicated | false | H01 |
| V02 | .claude/scripts/lib/dec-write-lib.sh | 250,251,252,253,261 | high | fix-commit | adjudicated | true | H02 |
| V03 | .claude/scripts/lib/dec-write-lib.sh | 626,627 | medium | fix-commit | adjudicated | true | H03 |
| V04 | .loa.config.yaml.example | 127,140 | medium | fix-commit | adjudicated | true | H07 |
| V05 | tools/check-round-independence.sh | 65,71,72,73,74,75,77,79,82 | medium | fix-commit | adjudicated | true | H16 |
| V06 | tools/check-round-independence.sh | 73,139,140,142,143 | low | fix-commit | adjudicated | false | H18 |
