# Annotation result — pr-21

| measure | n | kappa | observed agreement |
|---|---|---|---|
| hunks | 105 | 0.8428 | 0.9524 |
| incidents | 3 | n/a | 1.0000 |
| severity | 17 | 1.0000 | 1.0000 |

- localization: 16 of 17 agreed defects overlap (share 0.9412), median anchor distance 0, 0 file mismatch(es)
- grouping: Jaccard 0.6064 (A 724 pair(s), B 823, both 584)
- items: 108; disagreements: 70; adjudicated: 70; adjudication share 0.6481
- defects: 16 (fix-commit 16); review-driven share 0.9375
- review-derived key (c131): 1 of 2 defect(s) lie within ±3 lines of a v2 defect

| defect | file | anchors | severity | label_source | agreement | review_driven | members |
|---|---|---|---|---|---|---|---|
| V01 | .claude/adapters/cheval.py | 420,422,1813,1814,1815,1817 | high | fix-commit | adjudicated | true | H01,H02 |
| V02 | .claude/adapters/loa_cheval/audit/modelinv.py | 474,475,476 | medium | fix-commit | adjudicated | true | H03 |
| V03 | .claude/adapters/loa_cheval/config/endpoint_policy.py | 138,139,140 | low | fix-commit | agreed | true | H07 |
| V04 | .claude/adapters/loa_cheval/config/endpoint_policy.py | 153,156,157,159 | high | fix-commit | adjudicated | true | H09 |
| V05 | .claude/adapters/loa_cheval/config/endpoint_policy.py | 221,222,223,224,225,230,231,232,233 | medium | fix-commit | adjudicated | true | H11,H12 |
| V06 | .claude/adapters/loa_cheval/config/loader.py | 704 | high | fix-commit | adjudicated | true | H14 |
| V07 | .claude/adapters/loa_cheval/providers/base.py | 128,136,137,138,139,140 | high | fix-commit | adjudicated | true | H16 |
| V08 | .claude/adapters/loa_cheval/providers/base.py | 128,140,145 | medium | fix-commit | adjudicated | true | H17 |
| V09 | .claude/scripts/adversarial-review.sh | 3888,3889 | low | fix-commit | adjudicated | false | H26 |
| V10 | .claude/scripts/adversarial-review.sh | 4849,4850 | medium | fix-commit | agreed | true | H28 |
| V11 | .claude/scripts/lib/hop-locality.py | 116,117,118,119 | high | fix-commit | adjudicated | true | H32 |
| V12 | .claude/skills/bridgebuilder-review/resources/config.ts | 484,485,486,487,488 | high | fix-commit | adjudicated | true | H73 |
| V13 | .claude/skills/bridgebuilder-review/resources/config.ts | 671,672,673,676,678,679,681 | high | fix-commit | adjudicated | true | H80 |
| V14 | .claude/skills/bridgebuilder-review/resources/config.ts | 722,723,724,725,726,727,728,729,730,731,732 | high | fix-commit | adjudicated | true | H82 |
| V15 | .claude/skills/bridgebuilder-review/resources/main.ts | 464,465,466 | high | fix-commit | adjudicated | true | H89 |
| V16 | .claude/skills/scheduled-cycle-template/contracts/session-cap-bb/dispatcher.sh | 78,79,80,85,88,89 | medium | fix-commit | adjudicated | true | H90 |
