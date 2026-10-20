# Sprint 264 batch scans — 2026-10-20T09:34:52Z

Pin `798d88cfc920a95ce896a527145b21ca72d0ab18`. One line per row; rows decide nothing here (the reads are Sprint 265's).

## c131-b1-oracle-ab

{"state":"complete","finished":"2026-10-20T04:43:55Z","spent":57.6162095,"planned":3,"per_arm":{"a1_full_openmount":{"trials_planned":3,"launched":3,"completed":3,"failed":0,"excluded":0,"cap_failures":0,"degraded":0,"skipped_paused":0}}}

| run | status | pin ok | took-effect | degraded | oracle exposed | review voices / budget / anchors | audit voices / budget / anchors | absent | fallbacks | pm3 | new | v1 | USD |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| b1-oracle-ab-a1_full_openmount-review-r17-t1 | completed | yes | 4/3 | false - | d1+d6+d8+d10+d13+d17+d20 | 2/2 diff/406c 16/16 | 2/2 diff/406c 1/1 | - | 0 | 0.8 | 0.8 | 0.8 | 19.27 |
| b1-oracle-ab-a1_full_openmount-review-r17-t2 | completed | yes | 4/3 | false - | d1+d2+d6+d7+d8+d10+d11+d12+d13+d14+d15+d16+d17+d18+d20 | 2/2 diff/406c 16/16 | 2/2 diff/406c 10/10 | - | 0 | 0.85 | 0.85 | 0.75 | 21.06 |
| b1-oracle-ab-a1_full_openmount-review-r17-t3 | completed | yes | 4/3 | false - | d6+d12+d15 | 2/2 diff/406c 9/9 | 2/2 diff/406c 9/9 | - | 0 | 0.6 | 0.6 | 0.55 | 17.27 |

## c131-b2-control-prices-a

{"state":"partial","finished":"2026-10-20T07:15:31Z","spent":152.0302483,"planned":18,"per_arm":{"a0_bare":{"trials_planned":6,"launched":6,"completed":5,"failed":0,"excluded":1,"cap_failures":0,"degraded":0,"skipped_paused":0},"a0_bare_fable":{"trials_planned":6,"launched":6,"completed":6,"failed":0,"excluded":0,"cap_failures":0,"degraded":0,"skipped_paused":0},"a1_full":{"trials_planned":6,"laun

| run | status | pin ok | took-effect | degraded | oracle exposed | review voices / budget / anchors | audit voices / budget / anchors | absent | fallbacks | pm3 | new | v1 | USD |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| b2-control-prices-a-a0_bare_fable-review-r17-t1 | completed | yes | 6/5 | false - | - | -/- no envelope | -/- no envelope | - | 0 | 0.25 | 0.25 | 0.15 | 4.776 |
| b2-control-prices-a-a0_bare_fable-review-r17-t2 | completed | yes | 6/5 | false - | - | -/- no envelope | -/- no envelope | - | 0 | 0.35 | 0.45 | 0.2 | 4.844 |
| b2-control-prices-a-a0_bare_fable-review-r17-t3 | completed | yes | 6/5 | false - | - | -/- no envelope | -/- no envelope | - | 0 | 0.2 | 0.35 | 0.05 | 4.900 |
| b2-control-prices-a-a0_bare_fable-review-r18-t1 | completed | yes | 6/5 | false - | - | -/- no envelope | -/- no envelope | - | 0 | 0.0 | 0.0 | 0.0 | 3.550 |
| b2-control-prices-a-a0_bare_fable-review-r18-t2 | completed | yes | 6/5 | false - | - | -/- no envelope | -/- no envelope | - | 0 | 0.125 | 0.125 | 0.125 | 3.975 |
| b2-control-prices-a-a0_bare_fable-review-r18-t3 | completed | yes | 6/5 | false - | - | -/- no envelope | -/- no envelope | - | 0 | 0.25 | 0.375 | 0.0 | 3.635 |
| b2-control-prices-a-a0_bare-review-r17-t1 | completed | yes | 5/4 | false - | - | -/- no envelope | -/- no envelope | - | 0 | 0.4 | 0.4 | 0.2 | 1.752 |
| b2-control-prices-a-a0_bare-review-r17-t2 | completed | yes | 5/4 | false - | - | -/- no envelope | -/- no envelope | - | 0 | 0.35 | 0.5 | 0.25 | 1.315 |
| b2-control-prices-a-a0_bare-review-r17-t3 | completed | yes | 5/4 | false - | - | -/- no envelope | -/- no envelope | - | 0 | 0.45 | 0.5 | 0.25 | 1.572 |
| b2-control-prices-a-a0_bare-review-r18-t1 | contaminated | yes | 5/4 | false - | - | -/- no envelope | -/- no envelope | - | 0 | 0.125 | 0.125 | 0.0 | 1.212 |
| b2-control-prices-a-a0_bare-review-r18-t2 | completed | yes | 5/4 | false - | - | -/- no envelope | -/- no envelope | - | 0 | 0.25 | 0.25 | 0.125 | 0.971 |
| b2-control-prices-a-a0_bare-review-r18-t3 | completed | yes | 5/4 | false - | - | -/- no envelope | -/- no envelope | - | 0 | 0.5 | 0.5 | 0.375 | 1.404 |
| b2-control-prices-a-a1_full-review-r17-t1 | completed | yes | 4/3 | false - | - | 2/2 diff/406c 19/21 | 2/2 diff/406c 8/8 | - | 0 | 0.65 | 0.65 | 0.6 | 21.78 |
| b2-control-prices-a-a1_full-review-r17-t2 | completed | yes | 4/3 | false - | - | 2/2 diff/406c 5/5 | 2/2 diff/406c 9/9 | - | 0 | 0.65 | 0.65 | 0.5 | 19.11 |
| b2-control-prices-a-a1_full-review-r17-t3 | completed | yes | 4/3 | false - | - | 2/2 diff/406c 13/13 | 2/2 diff/406c 7/7 | - | 0 | 0.75 | 0.75 | 0.7 | 23.60 |
| b2-control-prices-a-a1_full-review-r18-t1 | contaminated | yes | 4/3 | false - | - | 2/2 diff/257c 7/7 | 2/2 diff/257c 4/4 | - | 0 | 0.625 | 0.625 | 0.625 | 18.40 |
| b2-control-prices-a-a1_full-review-r18-t2 | completed | yes | 4/3 | false - | - | 2/2 diff/257c 6/6 | 2/2 diff/257c 4/4 | - | 0 | 0.5 | 0.5 | 0.5 | 17.42 |
| b2-control-prices-a-a1_full-review-r18-t3 | completed | yes | 4/3 | false - | - | 2/2 diff/257c 8/8 | 2/2 diff/257c 5/5 | - | 0 | 0.875 | 0.875 | 0.875 | 17.79 |

## c131-b2-control-prices-b

{"state":"partial","finished":"2026-10-20T09:30:19Z","spent":82.8740455,"planned":6,"per_arm":{"a1_review_only":{"trials_planned":3,"launched":3,"completed":3,"failed":0,"excluded":0,"cap_failures":0,"degraded":0,"skipped_paused":0},"a1_no_dissent":{"trials_planned":3,"launched":3,"completed":2,"failed":0,"excluded":1,"cap_failures":0,"degraded":0,"skipped_paused":0}}}

| run | status | pin ok | took-effect | degraded | oracle exposed | review voices / budget / anchors | audit voices / budget / anchors | absent | fallbacks | pm3 | new | v1 | USD |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| b2-control-prices-b-a1_no_dissent-review-r17-t1 | completed | yes | 5/4 | false - | - | -/- no envelope | 2/2 diff/406c 8/8 | review | 0 | 0.75 | 0.75 | 0.6 | 16.30 |
| b2-control-prices-b-a1_no_dissent-review-r17-t2 | completed | yes | 5/4 | false - | - | -/- no envelope | 2/2 diff/406c 8/8 | review | 0 | 0.75 | 0.75 | 0.55 | 15.27 |
| b2-control-prices-b-a1_no_dissent-review-r17-t3 | contaminated | yes | 5/4 | false - | - | -/- no envelope | 2/2 diff/406c 12/12 | review | 0 | 0.6 | 0.6 | 0.4 | 17.05 |
| b2-control-prices-b-a1_review_only-review-r17-t1 | completed | yes | 4/3 | false - | - | 2/2 diff/406c 14/14 | -/- no envelope | - | 0 | 0.65 | 0.65 | 0.55 | 10.78 |
| b2-control-prices-b-a1_review_only-review-r17-t2 | completed | yes | 4/3 | false - | - | 2/2 diff/406c 12/12 | -/- no envelope | - | 0 | 0.65 | 0.65 | 0.5 | 11.72 |
| b2-control-prices-b-a1_review_only-review-r17-t3 | completed | yes | 4/3 | false - | - | 2/2 diff/406c 13/13 | -/- no envelope | - | 0 | 0.65 | 0.65 | 0.45 | 11.73 |

