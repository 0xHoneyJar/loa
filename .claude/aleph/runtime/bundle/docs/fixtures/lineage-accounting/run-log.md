# Run Log — RUN-lineage-accounting

## 2026-08-14 08:00 UTC — S0 — entry

Created the synthetic source-walk accounting fixture.

## 2026-08-14 08:05 UTC — S0 — exit

Froze SRC-401 after the fixture-simulated scope and sensitivity sign-off.

## 2026-08-14 08:10 UTC — S1 — exit

Recorded extraction criteria before source traversal.

## 2026-08-14 08:20 UTC — S2 — entry

Started the primary ordered source walk.

## 2026-08-14 08:25 UTC — S2 — checkpoint

Paused after the first SP-0401 event with CUR-0403 naming event ordinal 2 as
the next work at the same byte position.

## 2026-08-14 08:30 UTC — S2 — resume

Resumed at SP-0401 event ordinal 2 without advancing beyond the shared source
position.

## 2026-08-14 08:40 UTC — S2 — gap-review

A distinct reviewer found one synthetic candidate omitted by the primary
walk. The orchestrator validated its exact evidence and reconciled GAP-0401.

## 2026-08-14 08:45 UTC — S2 — exit

Closed structural traversal and resume accounting for SRC-401. This does not
claim perfect recall or semantic review correctness.

## 2026-08-14 08:50 UTC — S3 — entry

Materialized the synthetic claim inventory and explicit zero-claim packet closure.

## 2026-08-14 09:00 UTC — S4 — exit

Recorded synthetic split, merge, duplicate, replacement, and supersession lineage.

## 2026-08-14 09:05 UTC — S5 — entry

Assigned current dispositions only to lineage-current claims. Historical predecessors remain durable with blank current dispositions.

## 2026-08-14 09:15 UTC — S11 — exit

Rendered only lineage-current claims into the synthetic Précis current view.
