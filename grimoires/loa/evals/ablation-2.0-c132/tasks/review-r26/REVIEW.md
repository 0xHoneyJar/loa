# Fairness review — review-r26

**Reviewer:** lead, by the mechanical fairness checks of cycle-132 Task 1.11 (the three checks the cycle-131 fairness sessions applied, run as a script over the task, the fixture and the hidden key; no model session) · **Date:** 2026-10-21 · **Verdict:** PASS

## 1. No solution leak

PASS. TASK.md differs from the cycle-131 template (`ablation-2.0-c131/tasks/review-r18/TASK.md`) only on line 3 (changed lines: [2]), whose change summary is the fixture's `PR.md` title without its conventional-commit prefix and sprint tag — text the agent reads in `pr/PR.md` regardless (match: True). The remaining lines of TASK.md carry no anchor, manifest, label, grader or key words (0 hit(s)). `pipeline-run.sh` copies only `base head head.diff PR.md REVIEW-INSTRUCTIONS.md AUDIT-INSTRUCTIONS.md` into `pr/`; over those paths a grep for the hidden key's paths and column names (`review-prs/manifests/`, `review-prs/labels/`, `fix_regions`, `label_source`), outside the fixture's own copy of the harness code, finds 0 file(s), and a grep for the 0 defect descriptions finds 0. (The v2 defect ids `V01 …` are three-character tokens and are not grepped: they collide with ordinary test names and carry no information about the key.)

## 2. Red then green

PASS. The v2 manifest `evals/fixtures/review-prs/manifests/pr-26.json` holds 9 defects (0 critical, 1 high, 7 medium, 1 low), approved by `lead 2026-10-21`, label set `v2`, 54 fix regions. The accurate verdict is **CHANGES_REQUIRED** (the key rule: CHANGES_REQUIRED iff a high or critical defect is in the key). Every anchor lies inside its `head/<file>` (0 out of range). Image self-check (`grimoires/loa/reports/ablation-2.0/self-check-c132.txt`, grader 1.3.3, image loa-ablation:258): base PASS (recall 0.0 (0/9), false_positives 0); reference PASS (recall 1.0 (9/9), false_positives 0); noisy PASS (recall 1.0 (9/9), false_positives 26 vs reference 0).

## 3. Criterion mechanical

PASS. task.yaml differs from the template only in `id`, `source` (origin pr-26, the head date), the fixture id and the expected verdict inside `success_criterion`, and `review_catch` (the v2 manifest path and the matched arms' k) — 4 differing line(s); `criterion` is byte-identical; `bounds: {max_turns: {}, timeout_min: {REVIEW: 50, AUDIT: 40}}`, `suite_version: 2`, `fixture: null` and `grader_protected: []` are unchanged.

## Notes

- Difficulty: 9 defects over a 1424-line diff; the low-severity tail is 1 of 9.
- Shared or adjacent anchors inflate recall equally for every arm (the ±3 window); the key's anchors are the union of both blind annotators' in-hunk sites (DEC-0717).
- The task's `success_criterion` names the grader rule (pm3: a `head/<path>:<line>` citation within 3 lines of a key anchor) and the exact expected verdict.
