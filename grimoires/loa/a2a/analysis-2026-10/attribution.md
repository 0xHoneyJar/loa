# Deliverable 2 — voice attribution of every full-pipeline catch

Source: `data/runs.json` (24 valid runs; the grader's own rule re-applied per source file and per dissent voice; transcript timing from `events-REVIEW.jsonl` / `events-AUDIT.jsonl`). Script: `scripts/attribution.py`.

## The structural fact first

Under the grader's rule a dissent voice can only be credited through a numeric `file:line` anchor in its envelope. **None of the 24 dissent envelopes (12 runs × review + audit) carries one**: every finding anchors on a function name, a hunk header or a code line (`anchor_type` function/hunk/line), so `envelope:*` sources contribute 0 citations in every run (see the per-source columns in `data/runs.json`). Every credited catch therefore sits in text the Fable reviewer or auditor wrote. The dissent can only have contributed by influence — a voice naming a region before Fable wrote it down — which is what the timing below measures.

## First-citation class of the 46 full-arm catches (defect-trials)

| class | meaning | all catches | of the 15 full-only catches |
|---|---|---|---|
| `review_pre_dissent` | Fable reviewer cited it (concerns/draft/feedback) BEFORE the dissent returned | 15 | 5 |
| `review_post_dissent_named` | first cited after the dissent returned AND a voice had named the enclosing function/hunk | 8 | 2 |
| `review_post_dissent_unnamed` | first cited after the dissent returned, no voice named the region | 7 | 1 |
| `review_no_dissent_voice` | review gate whose dissent ran no voice (budget_exceeded on pr-13; killed on review-03 t1): Fable alone | 13 | 5 |
| `audit_gate` | first cited only in the AUDIT gate's feedback | 3 | 2 |
| `uncited` | caught by grader but no transcript citation found | 0 | 0 |

The 15 full-only catches are the whole lift (bare-only catches: 0). Split: review_pre_dissent 5, review_no_dissent_voice 5, audit_gate 2, review_post_dissent_named 2, review_post_dissent_unnamed 1.

## Did a dissent voice name the region at all? (symbol level, outside the grader's rule)

A review-gate dissent finding whose function anchor encloses a planted site, or whose hunk/line anchor text lies within ±3 lines of it: 18 of 57 defect-trials, 17 of them caught by Fable. By voice (`answered_by`): **claude-headless** named 18 (caught 17, bare had missed 7); **codex-headless** named 9 (caught 9, bare had missed 3). On pr-13 no voice ran (budget gate); on review-03 t1 the review dissent was killed by the 420 s cap.

## Reconstructions (task-mean catch rate, the report's statistic)

| configuration | task-mean catch rate | Δ vs bare | note |
|---|---|---|---|
| bare | 0.668 | — | 12 a0 runs |
| full (as shipped) | 0.854 | +0.186 | the pre-registered +0.263 is the defect-level statistic; task-mean matches the report's 0.854 − 0.668 = +0.186 |
| full without the AUDIT gate | 0.799 | +0.131 | grader rule over review.md + engineer-feedback.md + review envelope only; the audit's own citations dropped |
| full minus catches first cited after a voice named the region | 0.719 | +0.051 | lower bound for 'dissent removed': assumes every such catch was the dissent's |
| full minus every post-dissent review-gate catch | 0.542 | -0.126 | extreme bound: also drops post-dissent catches no voice named |

Per task: review-01: bare 1.00 / full 1.00 / no-audit 1.00 / no-dissent-lb 0.89; review-02: bare 0.89 / full 1.00 / no-audit 0.89 / no-dissent-lb 0.78; review-03: bare 0.25 / full 0.75 / no-audit 0.71 / no-dissent-lb 0.54; review-04: bare 0.53 / full 0.67 / no-audit 0.60 / no-dissent-lb 0.67.

Reading: under the grader's rule the dissent is invisible (0 credited citations) and removing the audit gate costs little catch; the honest 'dissent removed' figure lies between the lower bound and the shipped figure, because a Fable draft written after the dissent returned may or may not have used it — the transcript reading (deliverable 5) adjudicates the named cases one by one.

## Cost split (12 valid a1 runs)

| component | USD total | share |
|---|---|---|
| REVIEW_primary | 59.28 | 42.4% |
| REVIEW_dissent | 11.93 | 8.5% |
| AUDIT_primary | 56.49 | 40.4% |
| AUDIT_dissent | 11.97 | 8.6% |
| **total** | 139.67 | 100 % |

Dissent voices by model (cost-ledger rows): codex-headless USD 9.79, global.anthropic.claude-fable-5-1 USD 14.10. Per run: USD 11.64, of which dissent 1.99 (17.1%), AUDIT gate 5.70 (49.0%).

| task | runs | mean USD/run | review gate | audit gate | dissent (both gates) |
|---|---|---|---|---|---|
| review-01 | 3 | 9.08 | 4.23 | 4.85 | 1.86 |
| review-02 | 3 | 8.63 | 3.86 | 4.77 | 1.94 |
| review-03 | 3 | 17.05 | 8.92 | 8.13 | 4.17 |
| review-04 | 3 | 11.80 | 6.73 | 5.07 | 0.00 |

## Per catch (full arm)

| task | trial | defect | sev | bare | class | first event | voices naming the region (review gate) | credited sources |
|---|---|---|---|---|---|---|---|---|
| review-01 | 1 | d1 | critical | ✓ | review_pre_dissent | 334 (Write) | — | review, engineer-feedback, auditor-sprint-feedback |
| review-01 | 1 | d2 | high | ✓ | review_pre_dissent | 334 (Write) | — | review, engineer-feedback, auditor-sprint-feedback |
| review-01 | 1 | d3 | medium | ✓ | review_pre_dissent | 334 (Write) | claude-headless, codex-headless | review, engineer-feedback, auditor-sprint-feedback |
| review-01 | 2 | d1 | critical | ✓ | review_post_dissent_unnamed | 264 (Write) | — | review, engineer-feedback, auditor-sprint-feedback |
| review-01 | 2 | d2 | high | ✓ | review_post_dissent_unnamed | 264 (Write) | — | review, engineer-feedback, auditor-sprint-feedback |
| review-01 | 2 | d3 | medium | ✓ | review_post_dissent_named | 264 (Write) | claude-headless, codex-headless | review, engineer-feedback, auditor-sprint-feedback |
| review-01 | 3 | d1 | critical | ✓ | review_pre_dissent | 182 (Write) | — | review, engineer-feedback, auditor-sprint-feedback |
| review-01 | 3 | d2 | high | ✓ | review_post_dissent_unnamed | 268 (Write) | — | review, engineer-feedback, auditor-sprint-feedback |
| review-01 | 3 | d3 | medium | ✓ | review_pre_dissent | 182 (Write) | claude-headless, codex-headless | review, engineer-feedback, auditor-sprint-feedback |
| review-02 | 1 | d1 | high | ✓ | review_pre_dissent | 169 (Bash) | — | review, engineer-feedback, auditor-sprint-feedback |
| review-02 | 1 | d2 | medium | ✓ | review_pre_dissent | 169 (Bash) | — | review, engineer-feedback, auditor-sprint-feedback |
| review-02 | 1 | d3 | medium | ✗ | review_pre_dissent | 169 (Bash) | — | engineer-feedback, auditor-sprint-feedback |
| review-02 | 2 | d1 | high | ✓ | review_post_dissent_named | 326 (Bash) | claude-headless, codex-headless | engineer-feedback, auditor-sprint-feedback |
| review-02 | 2 | d2 | medium | ✓ | review_post_dissent_unnamed | 326 (Bash) | — | engineer-feedback |
| review-02 | 2 | d3 | medium | ✓ | review_post_dissent_unnamed | 326 (Bash) | — | engineer-feedback, auditor-sprint-feedback |
| review-02 | 3 | d1 | high | ✓ | review_post_dissent_named | 264 (Bash) | claude-headless, codex-headless | review, engineer-feedback, auditor-sprint-feedback |
| review-02 | 3 | d2 | medium | ✓ | review_post_dissent_unnamed | 264 (Bash) | — | review, engineer-feedback, auditor-sprint-feedback |
| review-02 | 3 | d3 | medium | ✓ | audit_gate | 215 (Bash) | — | auditor-sprint-feedback |
| review-03 | 1 | d1 | high | ✗ | audit_gate | 596 (Write) | — | auditor-sprint-feedback |
| review-03 | 1 | d2 | high | ✗ | review_no_dissent_voice | 714 (Bash) | — | review, engineer-feedback, auditor-sprint-feedback |
| review-03 | 1 | d4 | medium | ✗ | review_no_dissent_voice | 714 (Bash) | — | review, engineer-feedback, auditor-sprint-feedback |
| review-03 | 1 | d5 | medium | ✗ | review_no_dissent_voice | 714 (Bash) | — | engineer-feedback, auditor-sprint-feedback |
| review-03 | 1 | d6 | medium | ✗ | review_no_dissent_voice | 714 (Bash) | — | review, engineer-feedback, auditor-sprint-feedback |
| review-03 | 2 | d1 | high | ✗ | review_pre_dissent | 604 (Write) | claude-headless, codex-headless | engineer-feedback, auditor-sprint-feedback |
| review-03 | 2 | d2 | high | ✓ | review_pre_dissent | 604 (Write) | claude-headless | engineer-feedback, auditor-sprint-feedback |
| review-03 | 2 | d3 | high | ✗ | review_pre_dissent | 604 (Write) | claude-headless | engineer-feedback, auditor-sprint-feedback |
| review-03 | 2 | d4 | medium | ✓ | review_pre_dissent | 597 (Bash) | claude-headless | review, engineer-feedback, auditor-sprint-feedback |
| review-03 | 2 | d5 | medium | ✗ | review_pre_dissent | 597 (Bash) | claude-headless | review, engineer-feedback, auditor-sprint-feedback |
| review-03 | 2 | d6 | medium | ✓ | review_pre_dissent | 597 (Bash) | claude-headless, codex-headless | review, engineer-feedback, auditor-sprint-feedback |
| review-03 | 2 | d7 | low | ✗ | review_pre_dissent | 604 (Write) | claude-headless | engineer-feedback, auditor-sprint-feedback |
| review-03 | 3 | d1 | high | ✗ | review_post_dissent_named | 667 (Write) | claude-headless, codex-headless | engineer-feedback, auditor-sprint-feedback |
| review-03 | 3 | d2 | high | ✓ | review_post_dissent_named | 667 (Write) | claude-headless | engineer-feedback, auditor-sprint-feedback |
| review-03 | 3 | d3 | high | ✗ | review_post_dissent_named | 667 (Write) | claude-headless, codex-headless | engineer-feedback, auditor-sprint-feedback |
| review-03 | 3 | d4 | medium | ✓ | review_post_dissent_named | 667 (Write) | claude-headless | engineer-feedback, auditor-sprint-feedback |
| review-03 | 3 | d5 | medium | ✗ | review_post_dissent_unnamed | 667 (Write) | — | engineer-feedback, auditor-sprint-feedback |
| review-03 | 3 | d6 | medium | ✓ | review_post_dissent_named | 667 (Write) | claude-headless | engineer-feedback, auditor-sprint-feedback |
| review-04 | 1 | d2 | medium | ✓ | review_no_dissent_voice | 532 (Bash) | — | engineer-feedback, auditor-sprint-feedback |
| review-04 | 1 | d3 | low | ✓ | review_no_dissent_voice | 532 (Bash) | — | engineer-feedback, auditor-sprint-feedback |
| review-04 | 2 | d1 | low | ✓ | review_no_dissent_voice | 633 (Bash) | — | review, engineer-feedback, auditor-sprint-feedback |
| review-04 | 2 | d2 | medium | ✓ | review_no_dissent_voice | 633 (Bash) | — | review, engineer-feedback, auditor-sprint-feedback |
| review-04 | 2 | d3 | low | ✓ | review_no_dissent_voice | 633 (Bash) | — | review, engineer-feedback, auditor-sprint-feedback |
| review-04 | 2 | d4 | low | ✗ | review_no_dissent_voice | 633 (Bash) | — | review, engineer-feedback, auditor-sprint-feedback |
| review-04 | 2 | d5 | low | ✗ | audit_gate | 415 (Write) | — | auditor-sprint-feedback |
| review-04 | 3 | d1 | low | ✓ | review_no_dissent_voice | 432 (Write) | — | review, engineer-feedback, auditor-sprint-feedback |
| review-04 | 3 | d2 | medium | ✓ | review_no_dissent_voice | 432 (Write) | — | review, engineer-feedback, auditor-sprint-feedback |
| review-04 | 3 | d3 | low | ✓ | review_no_dissent_voice | 432 (Write) | — | review, engineer-feedback, auditor-sprint-feedback |
