# cycle-132 reproduction report

Written by `evals/analysis/c132/reproduce.sh` from a fresh clone of the stage-1 record commit. Every count below is recorded vs reproduced; an artefact is equal when its sha256 (or, for a row, its canonical JSON) matches the record.

## Environment

- bash: `5.2.37(1)-release`
- clone_head: `3be895f230aa1eef6137e632bffc26dc274c5e5f`
- host: `Linux 6.16.12+deb13-amd64 x86_64`
- image_digest: `sha256:4e37cb5fd4d85c3231b3ef11a0d6179b5a5452bc024c23a26a1bea2668e86f5f`
- image_digest_registered: `sha256:4e37cb5fd4d85c3231b3ef11a0d6179b5a5452bc024c23a26a1bea2668e86f5f`
- image_matches: `True`
- jq: `jq-1.7`
- lite_tree_present: `True`
- pin_tree_identical_to_head: `True`
- pipeline_pin: `fbd36a0c9880b244af08133013f3b6959b085c94`
- python: `Python 3.13.5`
- registration_sha256: `c9d98acb2668dabb4e7a9e3942bc6f1d880997cfe1e3e8c5cbc25cf42906eeb9`

## Hash table

| artefact class | count | equal | differ |
|---|---:|---:|---:|
| session grade.json | 433 | 433 | 0 |
| session gates-combined.md | 433 | 433 | 0 |
| pipeline-cell grade.json | 84 | 84 | 0 |
| pipeline-cell gates-combined.md | 84 | 84 | 0 |
| union-cell grade.json | 56 | 56 | 0 |
| union-cell gates-combined.md | 56 | 56 | 0 |
| INPUTS.json cells[*].grade_sha256 | 140 | 140 | 0 |
| rows (canonical JSON) | 140 | 140 | 0 |
| rows (bytes) | 140 | 140 | 0 |
| not graded in the record (skipped, listed below) | 7 | 7 | 0 |
| rows.jsonl file sha256 | 1 | 1 | 0 |
| INPUTS.json | 1 | 1 | 0 |
| final.md | 1 | 1 | 0 |
| final.json | 1 | 1 | 0 |
| placebo-phase1.md | 1 | 1 | 0 |
| placebo-phase1.json | 1 | 1 | 0 |

## Reads (recorded vs reproduced sha256)

| artefact | recorded | reproduced | rc |
|---|---|---|---:|
| rows.jsonl | `522e1980a1cca46bd3132c83abba8512b7b847acb951d8d98e9e7f7b3f7e41ad` | `522e1980a1cca46bd3132c83abba8512b7b847acb951d8d98e9e7f7b3f7e41ad` | |
| INPUTS.json | `17725093540e47b7c14f362a14536c84eec523b41df4b497af11c9170e7abb62` | `17725093540e47b7c14f362a14536c84eec523b41df4b497af11c9170e7abb62` | 0 |
| final.md | `0e4a42f4f01f9a79478a291939aacf7683e401a0e74465e0ecba39ee46d52db7` | `0e4a42f4f01f9a79478a291939aacf7683e401a0e74465e0ecba39ee46d52db7` | 0 |
| final.json | `17bf0668777d8eb222b46bea51007620210340cacdc4091a4659c3cb304923bd` | `17bf0668777d8eb222b46bea51007620210340cacdc4091a4659c3cb304923bd` | 0 |
| placebo-phase1.md | `346244fced08bb825d4b9c986e400994464a517f6f6a94884177c0b65ec5b8c3` | `346244fced08bb825d4b9c986e400994464a517f6f6a94884177c0b65ec5b8c3` | 0 |
| placebo-phase1.json | `ca52c25efe080585042fd295aa7be07c0604b647ae46f79bbd066993d0b108f0` | `ca52c25efe080585042fd295aa7be07c0604b647ae46f79bbd066993d0b108f0` | 0 |

## Differences

None.

## Not graded in the record

Run directories the record holds without a grade.json (the runner never graded them: a run interrupted by a host reboot, a session superseded by a retry, an invalid session) — not graded here either, excluded from every count above.
- session c132-g1-b/a0_bare_fable_matched/review-r23-t1/sessions/s2
- session c132-g1-b/a0_bare_fable_matched/review-r23-t1/sessions/s3
- session c132-g3-a2/a0_bare_matched/review-r20-t2/sessions/s10
- session c132-g3-b/a0_bare_fable_matched/review-r22-t1/sessions/s1
- session c132-g3-b/a0_bare_fable_matched/review-r22-t1/sessions/s2
- cell c132-g1-b/a1_review_only/review-r27-t1
- cell c132-g3-b/a1_review_only/review-r22-t1

## Sampled live rerun

Left for the lead: the registered live sample (REPRODUCE.md § Live rerun) runs with `reproduce.sh --live-sample FILE` and needs model credentials; its grades are reported against the arm's recorded range here.

## Sampled live rerun (DEC-0812: review-r24, one trial per arm, at the pin)

| arm | recorded recall_pm3 (trials 1, 2) | recorded range | rerun recall_pm3 | status | inside range |
|---|---|---|---|---|---|
| a1_full | 0.8889, 1.0000 | [0.8889, 1.0] | 0.8889 | completed | yes |
| a0_bare_matched | 1.0000, 1.0000 | [1.0, 1.0] | 0.8889 | completed | NO |
| a1_review_only | 0.7778, 0.8889 | [0.7778, 0.8889] | 0.6667 | completed | NO |

A rerun grade inside the recorded arm range confirms the apparatus; one outside is a named discrepancy. Spend: see runs.jsonl under the live scratch.
