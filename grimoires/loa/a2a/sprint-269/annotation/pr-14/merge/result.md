# Annotation result — pr-14

| measure | n | kappa | observed agreement |
|---|---|---|---|
| hunks | 95 | 0.9699 | 0.9895 |
| incidents | 26 | n/a | 1.0000 |
| severity | 21 | 0.6196 | 0.7619 |

- localization: 21 of 21 agreed defects overlap (share 1.0000), median anchor distance 0, 0 file mismatch(es)
- grouping: Jaccard 0.9219 (A 64 pair(s), B 59, both 59)
- items: 121; disagreements: 13; adjudicated: 13; adjudication share 0.1074
- defects: 17 (fix-commit 17); review-driven share 1.0000
- review-derived key (c131): 2 of 2 defect(s) lie within ±3 lines of a v2 defect

| defect | file | anchors | severity | label_source | agreement | review_driven | members |
|---|---|---|---|---|---|---|---|
| V01 | .claude/hooks/compliance/implement-gate.sh | 35,36 | high | fix-commit | agreed | true | H09 |
| V02 | .claude/hooks/compliance/implement-gate.sh | 52,53,55,56,57 | high | fix-commit | adjudicated | true | H10 |
| V03 | .claude/hooks/compliance/implement-gate.sh | 73,76,77,78,81,89,90,97,99 | high | fix-commit | adjudicated | true | H11 |
| V04 | .claude/hooks/compliance/implement-gate.sh | 123,127,128,129,134,135 | high | fix-commit | agreed | true | H13 |
| V05 | .claude/hooks/compliance/implement-gate.sh | 134,228 | low | fix-commit | agreed | true | H12 |
| V06 | .claude/hooks/compliance/implement-gate.sh | 135,228,230 | high | fix-commit | adjudicated | true | H17 |
| V07 | .claude/hooks/compliance/implement-gate.sh | 200,202,203,209,211,212 | medium | fix-commit | adjudicated | true | H15,H16 |
| V08 | .claude/scripts/check-permissions.sh | 164,167,168,169,238,239,242,246 | medium | fix-commit | agreed | true | H21,H22,H23 |
| V09 | .claude/scripts/detect-platform-features.sh | 35,36,62,66 | low | fix-commit | adjudicated | true | H25,H26 |
| V10 | .claude/scripts/flatline-orchestrator.sh | 582,583 | medium | fix-commit | adjudicated | true | H27 |
| V11 | .claude/scripts/lib-content.sh | 295 | low | fix-commit | agreed | true | H30 |
| V12 | .claude/scripts/model-adapter.sh | 655,656,657,659 | medium | fix-commit | adjudicated | true | H32 |
| V13 | .claude/scripts/validate-skill-capabilities.sh | 110 | medium | fix-commit | agreed | true | H35 |
| V14 | .claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts | 19,52,53 | medium | fix-commit | adjudicated | true | H44 |
| V15 | evals/graders/recall-vs-defects.sh | 61,62 | medium | fix-commit | adjudicated | true | H51 |
| V16 | evals/graders/recall-vs-defects.sh | 71,73,74,78 | medium | fix-commit | agreed | true | H52 |
| V17 | tools/check-prompt-budget.sh | 50,51 | medium | fix-commit | adjudicated | true | H95 |
