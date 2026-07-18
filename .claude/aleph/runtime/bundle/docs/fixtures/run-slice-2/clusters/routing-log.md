# Routing Log — RUN-slice-2

This materialized log is included in the golden manual fixture to make the
routing replay inspectable. Manual runs may otherwise use card posture histories.

| # | date | event | cluster(s) | from -> to | trigger |
|---|------|-------|------------|------------|---------|
| 1 | 2026-07-16 | posture-assigned | RC-01 | unassigned -> adversarial-weighted | CC-105 and CC-106 remain an explicit contradiction |
| 2 | 2026-07-16 | posture-assigned | RC-02 | unassigned -> adversarial-weighted | CC-104 merge and removal effects require attack |
| 3 | 2026-07-16 | posture-assigned | RC-03 | unassigned -> unrouted-pending-external-referent | REF-02 requests an authority scope ruling for CC-107 |
| 4 | 2026-07-16 | posture-assigned | RC-04 | unassigned -> unrouted-pending-external-referent | REF-01 records missing market support for CC-108 |
| 5 | 2026-07-16 | referent-recorded | RC-04 | unrouted-pending-external-referent -> unrouted-pending-external-referent | REF-01 recorded as unresolved |
| 6 | 2026-07-16 | referent-recorded | RC-03 | unrouted-pending-external-referent -> unrouted-pending-external-referent | REF-02 asks for an authority scope ruling |
| 7 | 2026-07-16 | referent-resolved | RC-03 | unrouted-pending-external-referent -> unrouted-pending-external-referent | REF-02 supplied by sign-off |
| 8 | 2026-07-16 | posture-changed | RC-03 | unrouted-pending-external-referent -> adversarial-weighted | REF-02 supplied the scope ruling; NB-1 and NB-2 now undergo attack |
| 9 | 2026-07-16 | dependency-added | RC-02 | none -> RC-01 | retention and referral claims depend on the access-cluster boundary |
| 10 | 2026-07-16 | referent-recorded | RC-02 | adversarial-weighted -> adversarial-weighted | STM-13 exposed the external-generalization need recorded as REF-03 |
| 11 | 2026-07-16 | re-route-after-arm | RC-02 | adversarial-weighted -> unrouted-pending-external-referent | REF-03 remains unresolved after the bounded evidence-removal replay |
