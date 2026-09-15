# Semantic Review

- semantic_review_format: aleph-semantic-review/v1

## subjects

| semantic_id | owner_stage | subject_kind | subject_path | subject_digest | predecessor_semantic_id | producer_receipt_ref |
| --- | --- | --- | --- | --- | --- | --- |
| SEM-0701 | S2 | packet-group | verification/harness/semantic-subjects/SEM-0701.json | sha256:4cdebf306fcda276d6d9a592eb8047a355ed70d0998b68b8285999d69edd4df3 | none | verification/harness/semantic-process/producer-0701.json@sha256:084c44e4b659f5cf1e6181a59e9b381d3b0a16b302c52f7e46742289a9a125d3 |
| SEM-0702 | S3 | claim | verification/harness/semantic-subjects/SEM-0702.json | sha256:cc6df338dfbc055141a184ff0d18f62ca9bf6f2035f81c6f39033334fe6af7fe | none | verification/harness/semantic-process/producer-0702.json@sha256:c6055db3c7c47c8e1d70244563a73c56e2af937fbd4b582876a49e2e9dc50577 |

## assignments

| review_id | semantic_id | assignment_path | assignment_digest |
| --- | --- | --- | --- |
| VER-0701 | SEM-0701 | verification/harness/semantic-assignments/VER-0701.json | sha256:ce7007dcb855a245ffbb06717ac53b4d6fe2f2a2c2f50c15778df2e0e6ab9a81 |
| VER-0702 | SEM-0702 | verification/harness/semantic-assignments/VER-0702.json | sha256:02d57f272d9fd1fa47bf1dffac1cbd2c06e65b3e9a6d375edd1e0b3cf523bd0e |

## results

| review_id | semantic_id | result_path | result_digest | execution_kind | execution_evidence_ref |
| --- | --- | --- | --- | --- | --- |
| VER-0701 | SEM-0701 | verification/harness/semantic-results/VER-0701.json | sha256:03f3cc52349659b6d51bc18fe8a2968e66c7f83db6d0d960dc5d3d2399b65a1c | manual-separate-pass | verification/harness/semantic-process/reviewer-0701.json@sha256:bf3c9a9f4d645b19a908566c9c8bca121de12576ec858e8b82382622b80f3f9a |
| VER-0702 | SEM-0702 | verification/harness/semantic-results/VER-0702.json | sha256:237252b4c108913816e722b69028fdb25164bd2453efe0f07e8c822fe351c1ef | manual-separate-pass | verification/harness/semantic-process/reviewer-0702.json@sha256:51db60af5a720cb36f6f1b19e417393e021199d0ee81db580c3dce4686688624 |

## resolutions

| resolution_id | semantic_id | outcome | review_ids | canonical_refs | origin_unit_refs | followup_semantic_ids |
| --- | --- | --- | --- | --- | --- | --- |
| SMR-0701 | SEM-0701 | admitted | ["VER-0701"] | ["PKT-0701"] | [] | [] |
| SMR-0702 | SEM-0702 | admitted | ["VER-0702"] | ["CC-0702"] | ["SEM-0701/U1"] | [] |
