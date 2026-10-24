# Source Walk Ledger — RUN-source-walk-accounting

- source_walk_format: aleph-source-walk/v1
- source_position_format: zero-based-utf8-byte-half-open/v1

## Primary walk intervals

| walk_id | source_id | start_byte | end_byte | outcome | packet_ids | criterion_ref | producer_invocation_id | closure_state | reason | closure_note |
|---------|-----------|------------|----------|---------|------------|---------------|------------------------|---------------|--------|--------------|
| WLK-0401 | SRC-401 | 0 | 17 | excluded | none | exclusion:scaffolding | INV-primary-0401 | closed | matches the frozen scaffolding exclusion | none |
| WLK-0402 | SRC-401 | 17 | 44 | no-candidate-observed | none | none | INV-primary-0401 | closed | none | none |
| WLK-0403 | SRC-401 | 44 | 87 | admitted | PKT-0401, PKT-0402 | admission:1 | INV-primary-0401 | closed | none | none |
| WLK-0404 | SRC-401 | 87 | 134 | deferred | none | none | INV-primary-0401 | resolved | candidate decision postponed for a second criteria pass | second criteria pass found no qualifying candidate |
| WLK-0405 | SRC-401 | 134 | 169 | admitted | PKT-0403 | admission:2 | INV-primary-0401 | closed | none | none |
| WLK-0406 | SRC-401 | 169 | 221 | no-candidate-observed | none | none | INV-primary-0401 | closed | none | none |
| WLK-0407 | SRC-401 | 221 | 268 | admitted | PKT-0404 | admission:2 | INV-primary-0401 | closed | none | none |
| WLK-0408 | SRC-401 | 268 | 319 | no-candidate-observed | none | none | INV-primary-0401 | closed | none | none |
| WLK-0409 | SRC-401 | 319 | 347 | no-candidate-observed | none | none | INV-primary-0401 | closed | none | none |

## Extraction events

| event_id | source_id | start_byte | end_byte | shared_position_key | event_ordinal | packet_id | origin | producer_invocation_id | status |
|----------|-----------|------------|----------|---------------------|---------------|-----------|--------|------------------------|--------|
| EVT-0401 | SRC-401 | 44 | 87 | SP-0401 | 1 | PKT-0401 | primary | INV-primary-0401 | committed |
| EVT-0402 | SRC-401 | 44 | 87 | SP-0401 | 2 | PKT-0402 | primary | INV-primary-0401 | committed |
| EVT-0403 | SRC-401 | 134 | 169 | SP-0402 | 1 | PKT-0403 | primary | INV-primary-0401 | committed |
| EVT-0404 | SRC-401 | 221 | 268 | SP-0403 | 1 | PKT-0404 | primary | INV-primary-0401 | committed |
| EVT-0405 | SRC-401 | 268 | 319 | SP-0404 | 1 | PKT-0405 | gap-reconciliation | INV-orchestrator-0403 | committed |

## Resume cursors

Each cursor names the next unprocessed source position or event.

| cursor_id | source_id | byte_offset | shared_position_key | next_event_ordinal | predecessor_walk_id | predecessor_event_id | source_hash | reason |
|-----------|-----------|-------------|---------------------|--------------------|---------------------|----------------------|-------------|--------|
| CUR-0401 | SRC-401 | 0 | none | none | none | none | sha256:15c980b0d84d5cb034d9fb449ae3f05b7672b2a413ad31c6e849e5acd0c3c984 | initial |
| CUR-0402 | SRC-401 | 44 | none | none | WLK-0402 | none | sha256:15c980b0d84d5cb034d9fb449ae3f05b7672b2a413ad31c6e849e5acd0c3c984 | progress |
| CUR-0403 | SRC-401 | 44 | SP-0401 | 2 | WLK-0403 | EVT-0401 | sha256:15c980b0d84d5cb034d9fb449ae3f05b7672b2a413ad31c6e849e5acd0c3c984 | bounded-pause |
| CUR-0404 | SRC-401 | 87 | none | none | WLK-0403 | EVT-0402 | sha256:15c980b0d84d5cb034d9fb449ae3f05b7672b2a413ad31c6e849e5acd0c3c984 | resumed-shared-position |
| CUR-0405 | SRC-401 | 268 | none | none | WLK-0407 | EVT-0404 | sha256:15c980b0d84d5cb034d9fb449ae3f05b7672b2a413ad31c6e849e5acd0c3c984 | progress |
| CUR-0406 | SRC-401 | 347 | none | none | WLK-0409 | none | sha256:15c980b0d84d5cb034d9fb449ae3f05b7672b2a413ad31c6e849e5acd0c3c984 | source-complete |

## Fresh gap reviews

| gap_review_id | source_id | producer_invocation_id | reviewer_invocation_id | review_basis_cursor_id | review_basis_digest | result | candidate_start_byte | candidate_end_byte | proposed_packet_id | reconciliation_event_id | status | note |
|---------------|-----------|------------------------|------------------------|------------------------|---------------------|--------|----------------------|--------------------|--------------------|-------------------------|--------|------|
| GAP-0401 | SRC-401 | INV-primary-0401 | INV-gap-0402 | CUR-0406 | sha256:fc6948734400d99f10f8dafb64607b362aa17f6e30979ee92c56e0f41c22dde2 | gap-candidate-found | 268 | 319 | PKT-0405 | EVT-0405 | reconciled | fresh reviewer found one synthetic omission; orchestrator reopened exact bytes and committed the packet |

## Per-source completion

| source_id | source_hash | source_length_bytes | final_cursor_id | gap_review_ids | completion_state | declared_by | note |
|-----------|-------------|---------------------|-----------------|----------------|------------------|-------------|------|
| SRC-401 | sha256:15c980b0d84d5cb034d9fb449ae3f05b7672b2a413ad31c6e849e5acd0c3c984 | 347 | CUR-0406 | GAP-0401 | complete | manual-fixture-orchestrator | structural walk closed after gap reconciliation; no semantic recall claim |
