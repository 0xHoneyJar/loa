---
schema_version: '1.0'
from: 'lead'
to: 'reviewer'
topic: 'cache-prefix-fixture'
ts_utc: '2026-07-06T00:00:00Z'
---
Fixed handoff body used only by tests/unit/hook-cache-prefix.bats to prove
surface_unread_handoffs (the function loa-l6-surface-handoffs.sh calls) is
byte-deterministic across two runs against the same on-disk state.
