# Packet Index — RUN-exact-evidence-fragments

- exact_evidence_format: aleph-exact-evidence/v1

## Packets

The `quote` cells below are display previews. Exact source bytes are only the
`exact_bytes_base64` values in the ordered fragment table.

| packet_id | source_id | locator | span_hash | quote | criterion | status |
|-----------|-----------|---------|-----------|-------|-----------|--------|
| PKT-0301 | SRC-301 | L3-L3 | sha256:554edaaf75e14b4da5c1ecbd6f6eeb64583dd7d7728241d1ea1bf06fd9777622 | The console recorded "exact" status for the flow. | 1 | active |
| PKT-0302 | SRC-301 | L8-L8 | sha256:725fc130d2473090f51c7456b74d34683b57793729f80ccea7b56aeb92931cfe | Adjacent fragment one. | 1 | active |
| PKT-0303 | SRC-301 | L9-L9 | sha256:7583e7540d920efd0e8c5398e42c7186e01130d35b3a52b221c3b817b391963c | Adjacent fragment two. | 1 | active |
| PKT-0304 | SRC-301 | L5-L5 | sha256:c8ba90350252679f81adf03141b242a732c691e79547b09102f6263102ab74b6 | First ordered fragment. | 1 | active |
| PKT-0305 | SRC-301 | L7-L7 | sha256:5d32e129bae31176ba374c97799d98da1738b1101b2029fcdb03dc0a9840b469 | Second ordered fragment. | 1 | active |

## Exact evidence records

| evidence_key | packet_ids | evidence_state | fragment_count | join_policy | exact_evidence_hash | degraded_source_id | degraded_source_locator | degradation_reason |
|--------------|------------|----------------|----------------|-------------|---------------------|--------------------|-------------------------|--------------------|
| EVID-0301 | PKT-0301 | exact | 1 | single-fragment | sha256:0ca32f456702bd71ce592fd5c3b29785fe1a3bf8c699bd558b2a1d9f472b0e2b | none | none | none |
| EVID-0302 | PKT-0302, PKT-0303 | exact | 2 | adjacent-fragments | sha256:4fcd9bea219f0215b4450d297932186879e355cd1fb1c9815f3586bacaa508ed | none | none | none |
| EVID-0303 | PKT-0304, PKT-0305 | exact | 2 | separate-fragments | sha256:c45e7502e3f47a213032d3a7b98db6a94b478043f36cb6e77923b24160e49da6 | none | none | none |
| EVID-0304 | none | degraded-non-exact | 0 | not-applicable | none | SRC-301 | L10-L10 | original bytes unavailable; rendering retained only as non-exact |

## Ordered fragments

| fragment_key | evidence_key | packet_id | fragment_order | source_id | locator | source_relation | byte_role | fragment_hash | exact_bytes_base64 |
|--------------|--------------|-----------|----------------|-----------|---------|-----------------|-----------|---------------|--------------------|
| FRAG-0301 | EVID-0301 | PKT-0301 | 1 | SRC-301 | L3-L3 | frozen-source | exact-source-bytes | sha256:554edaaf75e14b4da5c1ecbd6f6eeb64583dd7d7728241d1ea1bf06fd9777622 | VGhlIGNvbnNvbGUgcmVjb3JkZWQg4oCcZXhhY3TigJ0gc3RhdHVzIGZvciB0aGUg76yCb3cuCg== |
| FRAG-0302 | EVID-0302 | PKT-0302 | 1 | SRC-301 | L8-L8 | frozen-source | exact-source-bytes | sha256:725fc130d2473090f51c7456b74d34683b57793729f80ccea7b56aeb92931cfe | QWRqYWNlbnQgZnJhZ21lbnQgb25lLgo= |
| FRAG-0303 | EVID-0302 | PKT-0303 | 2 | SRC-301 | L9-L9 | frozen-source | exact-source-bytes | sha256:7583e7540d920efd0e8c5398e42c7186e01130d35b3a52b221c3b817b391963c | QWRqYWNlbnQgZnJhZ21lbnQgdHdvLgo= |
| FRAG-0304 | EVID-0303 | PKT-0304 | 1 | SRC-301 | L5-L5 | frozen-source | exact-source-bytes | sha256:c8ba90350252679f81adf03141b242a732c691e79547b09102f6263102ab74b6 | Rmlyc3Qgb3JkZXJlZCBmcmFnbWVudC4K |
| FRAG-0305 | EVID-0303 | PKT-0305 | 2 | SRC-301 | L7-L7 | frozen-source | exact-source-bytes | sha256:5d32e129bae31176ba374c97799d98da1738b1101b2029fcdb03dc0a9840b469 | U2Vjb25kIG9yZGVyZWQgZnJhZ21lbnQuCg== |

## Evidence transformations

| transform_key | evidence_key | output_role | predecessor_exact_evidence_hash | effective_exact_evidence_hash | output_text | output_text_hash |
|---------------|--------------|-------------|---------------------------------|-------------------------------|-------------|------------------|
| XFORM-0301 | EVID-0301 | rendered | sha256:0ca32f456702bd71ce592fd5c3b29785fe1a3bf8c699bd558b2a1d9f472b0e2b | sha256:0ca32f456702bd71ce592fd5c3b29785fe1a3bf8c699bd558b2a1d9f472b0e2b | The console recorded "exact" status for the flow. | sha256:32789107f4bc09d91f1af4e631834be298683d4094739518a36dbd605f2ae10f |
| XFORM-0302 | EVID-0301 | normalized | sha256:0ca32f456702bd71ce592fd5c3b29785fe1a3bf8c699bd558b2a1d9f472b0e2b | sha256:0ca32f456702bd71ce592fd5c3b29785fe1a3bf8c699bd558b2a1d9f472b0e2b | The console recorded an exact flow status. | sha256:6c85920664cba21f21b4544d2c7726b3c2cad756c3e6950851c11b814ac21a2f |
| XFORM-0303 | EVID-0302 | rendered | sha256:4fcd9bea219f0215b4450d297932186879e355cd1fb1c9815f3586bacaa508ed | sha256:4fcd9bea219f0215b4450d297932186879e355cd1fb1c9815f3586bacaa508ed | Adjacent fragment one. Adjacent fragment two. | sha256:037a9f2a2d63a57e31ad60de19770e4efba014825f943de879bcc1e893466315 |
| XFORM-0304 | EVID-0303 | rendered | sha256:c45e7502e3f47a213032d3a7b98db6a94b478043f36cb6e77923b24160e49da6 | sha256:c45e7502e3f47a213032d3a7b98db6a94b478043f36cb6e77923b24160e49da6 | First ordered fragment. [gap] Second ordered fragment. | sha256:086bc48589fcc95053706633a1116358df3c5998b850c02e0450d50ddc37daed |
| XFORM-0305 | EVID-0303 | normalized | sha256:c45e7502e3f47a213032d3a7b98db6a94b478043f36cb6e77923b24160e49da6 | sha256:c45e7502e3f47a213032d3a7b98db6a94b478043f36cb6e77923b24160e49da6 | The first and second observations form an ordered pair. | sha256:0b7563865c38c3ab6a7ec03aea8df7c3f8fd59ea49147961753d12441d54aebd |
| XFORM-0306 | EVID-0304 | rendered | none | none | [unreadable glyph sequence] | sha256:9775062a220e66a4db4f945b363effb62c88e767eb5b2218f56c7b26094830e1 |

## Per-source completion

| source_id | walked | packets | declared complete by | note |
|-----------|--------|---------|----------------------|------|
| SRC-301 | yes | PKT-0301, PKT-0302, PKT-0303, PKT-0304, PKT-0305 | manual-fixture-extractor | selected spans recorded; degraded example is not a packet |
