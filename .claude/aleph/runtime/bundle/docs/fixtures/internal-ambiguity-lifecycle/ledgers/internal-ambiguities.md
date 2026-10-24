# Internal Ambiguities — RUN-internal-ambiguity-lifecycle

- internal_ambiguity_format: aleph-internal-ambiguity/v1

## T5.1 Ambiguity definitions

| ambiguity_id | source_entity_kind | source_entity_id | source_id | expression_locator | expression_start_byte | expression_end_byte | expression_sha256 | expression_bytes_base64 | basis_packet_ids | detected_by |
|--------------|--------------------|------------------|-----------|--------------------|-----------------------|---------------------|-------------------|-------------------------|------------------|-------------|
| AMB-1501 | CC | CC-0414 | SRC-0401 | L3-L3 | 44 | 56 | sha256:6d9d90463647c560b99be17d20a1790f424fdad2b57ac43597b1256166541564 | U2hhcmVkIGFscGhh | PKT-0401 | invocation:ambiguity-producer-01 |
| AMB-1502 | CC | CC-0417 | SRC-0401 | L3-L3 | 66 | 77 | sha256:375acd8b163c1e68f5f434c904d81816d8331ad157ad05afd851937bcff9bc71 | U2hhcmVkIGJldGE= | PKT-0401 | invocation:ambiguity-producer-02 |
| AMB-1503 | CC | CC-0413 | SRC-0401 | L8-L8 | 277 | 286 | sha256:dda18a0e21ae47c53b4309434cbc02ae8bf764fa83a6defbb719431242722aa7 | Y2FuZGlkYXRl | PKT-0405 | invocation:ambiguity-producer-03 |
| AMB-1504 | CC | CC-0412 | SRC-0401 | L7-L7 | 251 | 266 | sha256:529543aed4488b1ab312f422da242a8e4c56fcf0cf9574491faca99b6809e997 | dGhlIG9ic2VydmF0aW9u | PKT-0404 | invocation:ambiguity-producer-04 |
| AMB-1505 | CC | CC-0413 | SRC-0401 | L8-L8 | 270 | 276 | sha256:2298c2ae6c6faae4e835453a1eb00297caa584f342796e94d997dce69691a438 | c3VidGxl | PKT-0405 | invocation:ambiguity-producer-05 |

## T5.2 Reviewed assessments

| ambiguity_id | assessment_seq | predecessor_assessment_seq | search_scope_kind | search_source_id | search_completion_ref | search_basis_digest | candidate_state | candidate_refs | affected_relation_ids | resolution_state | carry_state | proposed_by | review_subject_digest | reviewed_by |
|--------------|----------------|----------------------------|-------------------|------------------|-----------------------|---------------------|-----------------|----------------|-----------------------|------------------|-------------|-------------|-----------------------|-------------|
| AMB-1501 | 1 | none | local-intervals | SRC-0401 | ["WLK-0403"] | sha256:e3b352cb1739eed4446639f9f9bf383d6945b9bda06bac156db028fe60e86914 | single | [{"kind":"PKT","id":"PKT-0401"}] | none | resolved-local | none | invocation:ambiguity-producer-01 | sha256:921eea5620f4f74f6af2eba7ca8d32fc3c8d5927a9984ece87e9b9cc8b763981 | VER-1501 |
| AMB-1502 | 1 | none | local-intervals | SRC-0401 | ["WLK-0403"] | sha256:354c9359123b1711e6105057db02b7ee62ff893748b7b082765961de875a89f4 | single | [{"kind":"PKT","id":"PKT-0401"}] | REL-1405 | resolved-local | none | invocation:ambiguity-producer-02 | sha256:4b4569cb1cd81fb17b60ab90889f4983a593570d2573cc1a5146a3691f6f9378 | VER-1502 |
| AMB-1503 | 1 | none | full-same-source | SRC-0401 | SRC-0401@CUR-0406@sha256:15c980b0d84d5cb034d9fb449ae3f05b7672b2a413ad31c6e849e5acd0c3c984 | sha256:580ad9aee5a5b3b060c0f734542e08956c097060b34d56dc672c54fc5c2f3a80 | null-no-candidate | [] | none | unresolved | none | invocation:ambiguity-producer-03 | sha256:971c8b4b48522d87dc994a48823f1f4eabce05cd1c990b1bd08f506e5caf201d | VER-1503 |
| AMB-1504 | 1 | none | full-same-source | SRC-0401 | SRC-0401@CUR-0406@sha256:15c980b0d84d5cb034d9fb449ae3f05b7672b2a413ad31c6e849e5acd0c3c984 | sha256:19821f2d77d372f00a596164b9cf64af79ec57b4efff21308905fa3df4ab5578 | multiple | [{"kind":"PKT","id":"PKT-0401"},{"kind":"source-locus","source_id":"SRC-0401","locator":"L5-L5","span_hash":"sha256:25dea1997e39c2ed75262a33b34ccaa124831178e6466da208a9c19ecd556fb0"}] | REL-1401, REL-1409 | unresolved | explicit | invocation:ambiguity-producer-04 | sha256:3416e414d0092cf6d07553e16600d1ad305d6c2bc7b503bc2e0b7a08e62770ee | VER-1504 |
| AMB-1505 | 1 | none | full-same-source | SRC-0401 | SRC-0401@CUR-0406@sha256:15c980b0d84d5cb034d9fb449ae3f05b7672b2a413ad31c6e849e5acd0c3c984 | sha256:ad2a4bdd1313b3b4073c8f93d0d7e0a54b057758c8caea9893f5b62817906472 | null-cannot-determine | [] | none | unresolved | none | invocation:ambiguity-producer-05 | sha256:d4b354b401bdc0f68bdd4502e5e7a20ba725a1362acd1c2b0c65aaee07117805 | VER-1505 |

## T5.3 Human procedural actions

| ambiguity_id | authority_seq | assessment_seq | action | selected_candidate_ref | authority_subject_digest | authority_ref | closure_provenance |
|--------------|---------------|----------------|--------|------------------------|--------------------------|---------------|--------------------|
| AMB-1503 | 1 | 1 | carry-unresolved | none | sha256:9d835528e9e0739cce7c5afc8fec56db69f547e3dd01b390a123d51a5863f2bc | authority-response:RESP-S4-AMB-1503-A1-Q1@sha256:dd728ca7797b7454b32227daf879b77c888abe16f6dc33375624dc32dd524196 | request:GATE-S4-AMB-1503-A1-Q1@sha256:268353b796330d61fd05370346a2bab2cb91f3a00317421af64f798c1a1c6510;response:RESP-S4-AMB-1503-A1-Q1@sha256:dd728ca7797b7454b32227daf879b77c888abe16f6dc33375624dc32dd524196 |
| AMB-1504 | 1 | 1 | restrict-downstream-use | none | sha256:977ae9579e4567483649ca009ae992e4624a9c710bbfcdbd687b4474051345c3 | authority-response:RESP-S4-AMB-1504-A1-Q1@sha256:878defa3a7e24cad0c4ac34cf8ebe5db4066a16a290140ca1cb407c342bbf577 | request:GATE-S4-AMB-1504-A1-Q1@sha256:7e1e3b7f2e041cfa351cb90e00e0669a5a57410d104740254c08802edb71d4dd;response:RESP-S4-AMB-1504-A1-Q1@sha256:878defa3a7e24cad0c4ac34cf8ebe5db4066a16a290140ca1cb407c342bbf577 |
