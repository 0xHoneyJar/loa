# Sampling Record — RUN-slice-2

| stage | check | policy | population | checked | exhaustive-classes covered | changes caused (VER ids) |
|-------|-------|--------|------------|---------|----------------------------|--------------------------|
| S1 | criteria agreement | full tiny-corpus replay | 14 claim-bearing paragraphs plus scaffolding | all | yes | none |
| S2 | extraction coverage | every source and every paragraph | 4 sources | 4 | yes | none |
| S3 | entailment | every normalized claim against packet spans | 14 claims | 14 | yes | none |
| S4 | merge precision and contradiction sweep | every merge plus all claim pairs in the tiny inventory | 1 merge and 14 claims | all | yes | none |
| S5 | disposition refutation | every claim; includes every exclusion and contradiction | 14 claims | 14 | yes | none |
| S6 | evidence roles | every active edge and every carried or merged coverage target | 19 edges and 6 coverage targets | all | yes | none |
| S7 | feature honesty | every pre-cluster tag | 4 tags | 4 | yes | none |
| S8 | posture refutation | every route card and referent record | 4 cards and 3 referents | all | yes | none |
| S9a | risk and removal attack | all risk families and every load-bearing edge in adversarial clusters | 15 rows | 15 | yes | none |
| S9b | reconciliation refutation | every reconciliation row | 1 row | 1 | yes | none |
| S10 | synthesis faithfulness | every cluster paragraph and grouped-out paragraph | 5 paragraphs | 5 | yes | none |

These are fixture-simulated manual checks over a tiny corpus, not calibrated
agent-harness sampling defaults.
