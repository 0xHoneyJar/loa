# Source Walk Ledger

- source_walk_format: aleph-source-walk/v1
- source_position_format: zero-based-utf8-byte-half-open/v1

## Primary walk intervals

| walk_id | source_id | start_byte | end_byte | outcome | packet_ids | criterion_ref | producer_invocation_id | closure_state | reason | closure_note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| WLK-0701 | SRC-701 | 0 | 42 | admitted | PKT-0701 | admission:1 | manual-producer-0701 | closed | none | none |

## Extraction events

| event_id | source_id | start_byte | end_byte | shared_position_key | event_ordinal | packet_id | origin | producer_invocation_id | status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EVT-0701 | SRC-701 | 0 | 42 | SP-0701 | 1 | PKT-0701 | primary | manual-producer-0701 | committed |

## Resume cursors

| cursor_id | source_id | byte_offset | shared_position_key | next_event_ordinal | predecessor_walk_id | predecessor_event_id | source_hash | reason |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CUR-0701 | SRC-701 | 0 | none | none | none | none | sha256:e14a3684de15463f43261a695ef56fc08e8d57b80a9e963a4eee91c2b3fee76b | initial |
| CUR-0702 | SRC-701 | 42 | none | none | WLK-0701 | EVT-0701 | sha256:e14a3684de15463f43261a695ef56fc08e8d57b80a9e963a4eee91c2b3fee76b | source-complete |

## Fresh gap reviews

| gap_review_id | source_id | producer_invocation_id | reviewer_invocation_id | review_basis_cursor_id | review_basis_digest | result | candidate_start_byte | candidate_end_byte | proposed_packet_id | reconciliation_event_id | status | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GAP-0701 | SRC-701 | manual-producer-0701 | manual-gap-0701 | CUR-0702 | sha256:97da5ff0725245563c08fcdcc257a766418bc3a30dd9463192713831cecf5839 | no-gap-candidate-found | none | none | none | none | closed | Synthetic independent gap-review declaration. |

## Per-source completion

| source_id | source_hash | source_length_bytes | final_cursor_id | gap_review_ids | completion_state | declared_by | note |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SRC-701 | sha256:e14a3684de15463f43261a695ef56fc08e8d57b80a9e963a4eee91c2b3fee76b | 42 | CUR-0702 | GAP-0701 | complete | synthetic-manual-coordinator | Synthetic gap record; no actual review execution. |
