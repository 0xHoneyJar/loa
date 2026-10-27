# Packet Index — RUN-internal-ambiguity-lifecycle

- exact_evidence_format: aleph-exact-evidence/v1

## Packets

| packet_id | source_id | locator | span_hash | quote | criterion | status |
|-----------|-----------|---------|-----------|-------|-----------|--------|
| PKT-0401 | SRC-0401 | L3-L3 | sha256:5b0ed9a64d05d3b326e2dc22ded33e6da5cba645d01d0d47ed9c64e933f82afb | Shared alpha applies. | 1 | active |
| PKT-0402 | SRC-0401 | L3-L3 | sha256:5b0ed9a64d05d3b326e2dc22ded33e6da5cba645d01d0d47ed9c64e933f82afb | Shared beta applies. | 1 | active |
| PKT-0403 | SRC-0401 | L5-L5 | sha256:25dea1997e39c2ed75262a33b34ccaa124831178e6466da208a9c19ecd556fb0 | First half of a split observation, | 2 | active |
| PKT-0404 | SRC-0401 | L7-L7 | sha256:0be1c9a486c17a65573dcdba0945959ba4fbafe8ee2cdb962dc1a53e5e4f1e52 | and the second half completes the observation. | 2 | active |
| PKT-0405 | SRC-0401 | L8-L8 | sha256:5e5eb07287183a170cd6afb4a4e18257b8c1daba10039d450c130f98f785bd1b | A subtle candidate was missed on the primary pass. | 1 | active |

## Exact evidence records

| evidence_key | packet_ids | evidence_state | fragment_count | join_policy | exact_evidence_hash | degraded_source_id | degraded_source_locator | degradation_reason |
|--------------|------------|----------------|----------------|-------------|---------------------|--------------------|-------------------------|--------------------|
| EVID-0401 | PKT-0401 | exact | 1 | single-fragment | sha256:514dc0eda35e86bfa9de89e56c89ec44fa8edabb9eca0a2c204b7c02248b1972 | none | none | none |
| EVID-0402 | PKT-0402 | exact | 1 | single-fragment | sha256:514dc0eda35e86bfa9de89e56c89ec44fa8edabb9eca0a2c204b7c02248b1972 | none | none | none |
| EVID-0403 | PKT-0403, PKT-0404 | exact | 2 | separate-fragments | sha256:ed2775d5a77617d29f380e7119705fe7373c22ecd6e041bdd98c0a473090bfb0 | none | none | none |
| EVID-0404 | PKT-0405 | exact | 1 | single-fragment | sha256:5f0724f93ed0b659c24bccf0907e3b363058403950143fbcfcd5a20f47930bfd | none | none | none |

## Ordered fragments

| fragment_key | evidence_key | packet_id | fragment_order | source_id | locator | source_relation | byte_role | fragment_hash | exact_bytes_base64 |
|--------------|--------------|-----------|----------------|-----------|---------|-----------------|-----------|---------------|--------------------|
| FRAG-0401 | EVID-0401 | PKT-0401 | 1 | SRC-0401 | L3-L3 | frozen-source | exact-source-bytes | sha256:5b0ed9a64d05d3b326e2dc22ded33e6da5cba645d01d0d47ed9c64e933f82afb | U2hhcmVkIGFscGhhIGFwcGxpZXMuIFNoYXJlZCBiZXRhIGFwcGxpZXMuCg== |
| FRAG-0402 | EVID-0402 | PKT-0402 | 1 | SRC-0401 | L3-L3 | frozen-source | exact-source-bytes | sha256:5b0ed9a64d05d3b326e2dc22ded33e6da5cba645d01d0d47ed9c64e933f82afb | U2hhcmVkIGFscGhhIGFwcGxpZXMuIFNoYXJlZCBiZXRhIGFwcGxpZXMuCg== |
| FRAG-0403 | EVID-0403 | PKT-0403 | 1 | SRC-0401 | L5-L5 | frozen-source | exact-source-bytes | sha256:25dea1997e39c2ed75262a33b34ccaa124831178e6466da208a9c19ecd556fb0 | Rmlyc3QgaGFsZiBvZiBhIHNwbGl0IG9ic2VydmF0aW9uLAo= |
| FRAG-0404 | EVID-0403 | PKT-0404 | 2 | SRC-0401 | L7-L7 | frozen-source | exact-source-bytes | sha256:0be1c9a486c17a65573dcdba0945959ba4fbafe8ee2cdb962dc1a53e5e4f1e52 | YW5kIHRoZSBzZWNvbmQgaGFsZiBjb21wbGV0ZXMgdGhlIG9ic2VydmF0aW9uLgo= |
| FRAG-0405 | EVID-0404 | PKT-0405 | 1 | SRC-0401 | L8-L8 | frozen-source | exact-source-bytes | sha256:5e5eb07287183a170cd6afb4a4e18257b8c1daba10039d450c130f98f785bd1b | QSBzdWJ0bGUgY2FuZGlkYXRlIHdhcyBtaXNzZWQgb24gdGhlIHByaW1hcnkgcGFzcy4K |

## Evidence transformations

| transform_key | evidence_key | output_role | predecessor_exact_evidence_hash | effective_exact_evidence_hash | output_text | output_text_hash |
|---------------|--------------|-------------|---------------------------------|-------------------------------|-------------|------------------|
| XFORM-0401 | EVID-0401 | rendered | sha256:514dc0eda35e86bfa9de89e56c89ec44fa8edabb9eca0a2c204b7c02248b1972 | sha256:514dc0eda35e86bfa9de89e56c89ec44fa8edabb9eca0a2c204b7c02248b1972 | Shared alpha applies. | sha256:e5bcee7789c43d13725f5660c2e3339b5575c46bca732f79a54aca6bc8db2aef |
| XFORM-0402 | EVID-0402 | rendered | sha256:514dc0eda35e86bfa9de89e56c89ec44fa8edabb9eca0a2c204b7c02248b1972 | sha256:514dc0eda35e86bfa9de89e56c89ec44fa8edabb9eca0a2c204b7c02248b1972 | Shared beta applies. | sha256:ff2668d067f317830b464d48794a7b564d815053ac0eb5cbdec000c6b7121e10 |
| XFORM-0403 | EVID-0403 | rendered | sha256:ed2775d5a77617d29f380e7119705fe7373c22ecd6e041bdd98c0a473090bfb0 | sha256:ed2775d5a77617d29f380e7119705fe7373c22ecd6e041bdd98c0a473090bfb0 | First half of a split observation, [separate] and the second half completes the observation. | sha256:3fdf8e3e120d3bfa4f8ea2284ccc6114daa5e027f36d20d4f53ba0241639fbbb |
| XFORM-0404 | EVID-0404 | rendered | sha256:5f0724f93ed0b659c24bccf0907e3b363058403950143fbcfcd5a20f47930bfd | sha256:5f0724f93ed0b659c24bccf0907e3b363058403950143fbcfcd5a20f47930bfd | A subtle candidate was missed on the primary pass. | sha256:daad7713a96b76c6f79e930506ff6c82d880f3115aae956d1f29573820992fa5 |
