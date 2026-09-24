# Packet Index

- exact_evidence_format: aleph-exact-evidence/v1

## Packets

| packet_id | source_id | locator | span_hash | quote | criterion | status |
| --- | --- | --- | --- | --- | --- | --- |
| PKT-0701 | SRC-701 | L1-L1 | sha256:e14a3684de15463f43261a695ef56fc08e8d57b80a9e963a4eee91c2b3fee76b | With the filter enabled, the counter rose. | 1 | active |

## Exact evidence records

| evidence_key | packet_ids | evidence_state | fragment_count | join_policy | exact_evidence_hash | degraded_source_id | degraded_source_locator | degradation_reason |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EVID-0701 | PKT-0701 | exact | 1 | single-fragment | sha256:ba8d9c54b4c4fe9db5e228584b01f610f8a4e6f2524a4b82d0256ac57c34f254 | none | none | none |

## Exact fragments

| fragment_key | evidence_key | packet_id | fragment_order | source_id | locator | source_relation | byte_role | fragment_hash | exact_bytes_base64 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FRAG-0701 | EVID-0701 | PKT-0701 | 1 | SRC-701 | L1-L1 | frozen-source | exact-source-bytes | sha256:e14a3684de15463f43261a695ef56fc08e8d57b80a9e963a4eee91c2b3fee76b | V2l0aCB0aGUgZmlsdGVyIGVuYWJsZWQsIHRoZSBjb3VudGVyIHJvc2Uu |

## Evidence transformations

| transform_key | evidence_key | output_role | predecessor_exact_evidence_hash | effective_exact_evidence_hash | output_text | output_text_hash |
| --- | --- | --- | --- | --- | --- | --- |
