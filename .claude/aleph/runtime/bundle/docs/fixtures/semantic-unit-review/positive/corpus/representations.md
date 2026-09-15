# Source Representations

- source_representation_format: aleph-source-representation/v1

## representations

| representation_id | source_id | origin_kind | extraction_surface | state | reason | provenance_id |
| --- | --- | --- | --- | --- | --- | --- |
| REP-0001 | SRC-701 | unknown-origin | utf8-text | available | none | RPR-0001 |

## assets

| asset_id | representation_id | role | locus | media_type | encoding | byte_length | content_hash |
| --- | --- | --- | --- | --- | --- | --- | --- |

## provenance

| provenance_id | representation_id | type | actor | tool | tool_version | input_refs | output_refs | parameters_asset_id | declaration_asset_id |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RPR-0001 | REP-0001 | capture | capture-importer | stable-copy | 1 | [] | ["SRC-701"] | none | none |

## bindings

| binding_id | representation_id | carrier_id | start_byte | end_byte | page_id | region_id | byte_role | fragment_hash | exact_bytes_base64 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BND-0001 | REP-0001 | SRC-701 | 0 | 42 | none | none | frozen-source-bytes | sha256:e14a3684de15463f43261a695ef56fc08e8d57b80a9e963a4eee91c2b3fee76b | V2l0aCB0aGUgZmlsdGVyIGVuYWJsZWQsIHRoZSBjb3VudGVyIHJvc2Uu |

## objects

| object_id | representation_id | kind | parent_id | state | reason | provenance_id | binding_ids | content_hash | coordinates |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| OBJ-0001 | REP-0001 | source | none | available | none | RPR-0001 | ["BND-0001"] | sha256:40e17f5b162d0776e141984a87c71de007ec82a5b4f92229b8513d6e579993a7 | {} |
| OBJ-0002 | REP-0001 | text | OBJ-0001 | available | none | RPR-0001 | ["BND-0001"] | sha256:40e17f5b162d0776e141984a87c71de007ec82a5b4f92229b8513d6e579993a7 | {} |

## associations

| association_id | representation_id | kind | subject_id | target_ids | state | reason | provenance_id |
| --- | --- | --- | --- | --- | --- | --- | --- |
