# Annotation result — pr-20

| measure | n | kappa | observed agreement |
|---|---|---|---|
| hunks | 56 | 0.6291 | 0.8571 |
| incidents | 1 | n/a | 1.0000 |
| severity | 10 | 1.0000 | 1.0000 |

- localization: 10 of 10 agreed defects overlap (share 1.0000), median anchor distance 0, 0 file mismatch(es)
- grouping: Jaccard 1.0000 (A 38 pair(s), B 38, both 38)
- items: 57; disagreements: 13; adjudicated: 13; adjudication share 0.2281
- defects: 10 (fix-commit 10); review-driven share 0.3000
- review-derived key (c131): 1 of 4 defect(s) lie within ±3 lines of a v2 defect

| defect | file | anchors | severity | label_source | agreement | review_driven | members |
|---|---|---|---|---|---|---|---|
| V01 | .claude/hooks/safety/block-destructive-bash.sh | 190,191 | medium | fix-commit | adjudicated | false | H02 |
| V02 | .claude/hooks/safety/block-destructive-bash.sh | 548,550,551 | medium | fix-commit | agreed | false | H03 |
| V03 | .claude/hooks/safety/block-destructive-bash.sh | 1049,1050,1051,1052,1053,1054,1061,1067,1068 | high | fix-commit | adjudicated | false | H05,H06 |
| V04 | .claude/hooks/safety/block-destructive-bash.sh | 1206,1217 | high | fix-commit | agreed | false | H07 |
| V05 | .claude/scripts/lib/profile-lib.sh | 61 | low | fix-commit | agreed | true | H12 |
| V06 | .claude/scripts/loa-status.sh | 958 | low | fix-commit | agreed | false | H13 |
| V07 | .claude/skills/auditing-security/SKILL.md | 6,34,35 | medium | fix-commit | adjudicated | false | H14 |
| V08 | .claude/skills/reviewing-code/SKILL.md | 6,297 | medium | fix-commit | adjudicated | false | H16 |
| V09 | .loa.config.yaml.example | 312,325,1358,1404,1432,2932,2950,2962 | medium | fix-commit | adjudicated | true | H20,H21,H22,H23,H24,H25,H26,H27 |
| V10 | tools/check-knob-readers.sh | 40,41,43,44,45 | medium | fix-commit | adjudicated | true | H56 |
