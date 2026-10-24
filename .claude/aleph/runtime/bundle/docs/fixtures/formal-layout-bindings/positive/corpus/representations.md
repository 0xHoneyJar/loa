# Source Representations

- source_representation_format: aleph-source-representation/v1

## representations

| representation_id | source_id | origin_kind | extraction_surface | state | reason | provenance_id |
| --- | --- | --- | --- | --- | --- | --- |
| REP-0001 | SRC-401 | unknown-origin | utf8-text | available | none | RPR-0001 |

## assets

| asset_id | representation_id | role | locus | media_type | encoding | byte_length | content_hash |
| --- | --- | --- | --- | --- | --- | --- | --- |

## provenance

| provenance_id | representation_id | type | actor | tool | tool_version | input_refs | output_refs | parameters_asset_id | declaration_asset_id |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RPR-0001 | REP-0001 | capture | capture-importer | stable-copy | 1 | [] | ["SRC-401"] | none | none |

## bindings

| binding_id | representation_id | carrier_id | start_byte | end_byte | page_id | region_id | byte_role | fragment_hash | exact_bytes_base64 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BND-0001 | REP-0001 | SRC-401 | 0 | 347 | none | none | frozen-source-bytes | sha256:15c980b0d84d5cb034d9fb449ae3f05b7672b2a413ad31c6e849e5acd0c3c984 | Rml4dHVyZSBoZWFkaW5nLgpPcmRpbmFyeSBjYWbDqSBzZXR1cCB0ZXh0LgpTaGFyZWQgYWxwaGEgYXBwbGllcy4gU2hhcmVkIGJldGEgYXBwbGllcy4KRGVmZXJyZWQgbm90ZSBhd2FpdHMgYSBzZWNvbmQgY3JpdGVyaW9uIGNoZWNrLgpGaXJzdCBoYWxmIG9mIGEgc3BsaXQgb2JzZXJ2YXRpb24sCmNvbm5lY3RvciB0ZXh0IHJlbWFpbnMgb3V0c2lkZSB0aGUgZXhhY3QgZnJhZ21lbnRzLAphbmQgdGhlIHNlY29uZCBoYWxmIGNvbXBsZXRlcyB0aGUgb2JzZXJ2YXRpb24uCkEgc3VidGxlIGNhbmRpZGF0ZSB3YXMgbWlzc2VkIG9uIHRoZSBwcmltYXJ5IHBhc3MuCkNsb3Npbmcgbm9uLWNhbmRpZGF0ZSB0ZXh0Lgo= |

## objects

| object_id | representation_id | kind | parent_id | state | reason | provenance_id | binding_ids | content_hash | coordinates |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| OBJ-0001 | REP-0001 | source | none | available | none | RPR-0001 | ["BND-0001"] | sha256:f8111450d1aa0b9b63e0c4b14e5199a46060d8d22c1aee3729cf740b4208e592 | {} |
| OBJ-0002 | REP-0001 | text | OBJ-0001 | available | none | RPR-0001 | ["BND-0001"] | sha256:f8111450d1aa0b9b63e0c4b14e5199a46060d8d22c1aee3729cf740b4208e592 | {} |

## associations

| association_id | representation_id | kind | subject_id | target_ids | state | reason | provenance_id |
| --- | --- | --- | --- | --- | --- | --- | --- |
