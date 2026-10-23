# Implementer B report: cycle-132 Sprint 1 (global 269), Tasks 1.4 and 1.5

Model: global.anthropic.claude-opus-5-5. Base 346dbb87; Patch: ~/.cache/loa/cycle-132/patches/s1-b.patch

## What was built
- **1.4:** `evals/harness/blind-session.sh` copies the packets into a mktemp sandbox. It runs `claude -p` with Read/Grep/Glob/Write, `--setting-sources ""`, the BARE env allowlist and the cap watchdog, in the container or on an opt-in host. It writes labels.json, transcript.jsonl, cost.json, taint.json, session.json, prompt.md and sandbox.sha256, with exit 0/1/2/3.
- **1.4 lib and tests:** `evals/harness/lib/session-exec.sh` holds verbatim copies of pipeline-run.sh's ENV_SHIM, PASS_KEYS, SECRET_KEYS, price_for and price_events. `evals/tests/blind-session.bats` has BS-1 to BS-9.
- **1.5 merge:** `evals/analysis/c132/{__init__.py, annotation_merge.py}` computes kappa ×3, localization and grouping agreement, adjudication.md, complete-record adjudication, group merge, dedupe ±3 and v2 rows, plus `--pool` and `--validate` (a stdlib JSON-Schema subset). Tests are `tests/test_annotation_merge.py` and `tests/fixtures/merge/annotation.schema.json`, a test stand-in for A's schema.
- **1.5 seeder:** `seed-corpus-from-record.sh` gains HEADER_V2, the extended enum, v2 row checks, v2 fields, `label_set` and `record.incidents_meta` in `--build-manifest`, and `--sync-labels` copying all columns. The header docs are updated.
- **1.5 schema and grader:** `evals/harness/schemas/review-manifest.schema.json` covers the hand-built, record/c131/v1 and v2 shapes. `ablation-grade.sh` gains `label_set`, `labels_meta` and `key_set_root`, which the v1 and corpus-digest lookups use. `recall-vs-defects.sh` gets the same c131 sibling rule.
- **1.5 migration:** git mv of `manifests/pr-11..18.json` to `manifests/c131/` and of `labels/pr-11..18.tsv` to `labels/review/`. Repointed task.yaml: ablation-2.0 review-03/04, c131 r17/r18, replication r17/r18, smoke-c131 review-03/04/r16/r17/r18. Four roots and SHA256SUMS were refrozen (only the paths moved).
- **1.5 tests:** seed-corpus.bats gains SC-V2-1 to SC-V2-5, and its `scratch_record_fixture`, SC-9 and SC-12 now read the frozen layout. ablation-grade.bats gains AG-LS1 and AG-LS2. manifest-v2.bats is new with MV-1 to MV-7. `evals/tests/fixtures/c131-regrade/` is trimmed from the record branch, with a SOURCE note.

## How it was tested
| File | Result |
|---|---|
| blind-session.bats | 9/9 |
| seed-corpus.bats | 23/23 |
| manifest-v2.bats | 7/7 |
| ablation-grade.bats | 58/58 |
| pipeline-run.bats + eval-recall-grader.bats | green |
| Combined run of the six files | 222/222 |
| test_annotation_merge.py | 23 OK |
| whole evals/tests/ | 563/564; see note |

```
~/.cache/loa/cycle-128/s2d/bin/bats evals/tests/blind-session.bats evals/tests/seed-corpus.bats evals/tests/ablation-grade.bats evals/tests/manifest-v2.bats evals/tests/pipeline-run.bats evals/tests/eval-recall-grader.bats
python3 -m unittest discover -s evals/analysis/c132/tests
~/.cache/loa/cycle-128/s2d/bin/bats evals/tests/   # ~/.cache/loa/cycle-132/logs/s1-b-full-evals-tests.log
```
The failure was ablation-row #136, a shared-/tmp race in a file I did not touch. It passes 41/41 alone with its own TMPDIR.

Also green: `--check`, `freeze.sh --check` (4 roots), bash -n, the trust scan, tools/check-*, no-secrets.sh.

## AC evidence
- PASS 1.4: BS-5 checks container reuse and BS-8 parity. BS-1 and BS-6 check the packet-only sandbox. BS-1 and BS-2 check the tools and label path. BS-1, BS-3 and BS-7 check the transcript, cost, taint and cap. BS-4 covers the adversarial packet (SKP-010). The exit codes are covered.
- PASS 1.5 merge: KappaTest checks kappa (2×2 gives 0.4, 4×4 gives 0.48/0.68, degenerate gives null). Localization and grouping agreement are checked. Unresolved, incomplete and unknown records are refused. Anchors are validated against head. Dedupe joins at ±3 and stays separate at 4. Rows are deterministic.
- PASS 1.5 v2: SC-V2-1 to SC-V2-5 cover labels v2 and `--build-manifest`. MV-5 and MV-7 cover the schema. MV-1, MV-2, SC-9 and SC-12 cover byte-identity. MV-3 and MV-4 cover paths and freeze.
- PASS 1.5 grader: AG-LS1 covers label_set and labels_meta. AG-LS2 covers the c131 re-grade equality on c131-b2-control-prices-a/a1_full/review-r17-t1: the recall block is exact.

## DECISION bullets
- DECISION: pipeline-run.sh is untouched. Its bats harness copies only the libs it sources today, so a new `source` would turn pipeline-run.bats red. The lib holds verbatim copies, and BS-8 fails on drift.
- DECISION: the blind HOME holds no credential file (no codex copies). Host mode also uses the per-session HOME. Host mode needs LOA_EVAL_ALLOW_HOST_SESSION=1.
- DECISION: taint also covers Write outside the sandbox, `~` paths, absolute or `..` Glob patterns and Grep globs. A tainted role keeps its labels.json. Exit 3 wins over 1.
- DECISION: the prompt's `{{LABELS_PATH}}` is substituted, or one closing line is appended. A max-turns stop with a valid labels.json counts as completed.
- DECISION: recall-vs-defects.sh and the grader's v1 and corpus lookups resolve a manifests/c131/ key against manifests/v1/ and the corpus root. Without that, the c131 re-grade loses v1_manifest. The grader version is not bumped (C's 1.3.2).
- DECISION: label_set comes from the resolved key's directory (c131 or v1 directly under manifests/), else v2. labels_meta is by position only.
- DECISION: HEADER_V2 has the four columns from the brief (the SDD says three). Exactly 7 or 11 columns are accepted. A manifest is v2 only when an annotated row exists, and then every defect gets the four fields. annotators is a list, and `-` becomes null. label_set comes after fixture. incidents_meta holds only main_sha.
- DECISION: there is no seeder flag for the c131 rebuild (argparse is A's area). Tests rebuild on a scratch corpus.
- DECISION: smoke-c131's five task.yaml files were also repointed and refrozen, since they would otherwise dangle. REVIEW.md prose, corpus.tsv, dropped.txt and curation.tsv were left as they are.
- DECISION: description text never counts as a disagreement (it never matches); A's text is taken. Groups are compared by co-membership, and adjudication group ids live in A's namespace.
- DECISION: an incident-only defect without a category is listed for adjudication. A cross-file group is split by file. Severity takes the highest member, category the first member's. Ids are V01 and up.
- DECISION: --manifest-c131 is optional (new fixtures have none). --hunks-meta is required with --adjudication. labels.rows.tsv is a complete v2 labels file. --fix-rows carries the fix regions. --pool sums the tables.
- DECISION: the schema validator lives in annotation_merge.py --validate, because the rest of the package is D's. Unsupported keywords are refused.

## CHANGELOG entry text
### Added
- Added `evals/harness/blind-session.sh`. It runs one blind labelling role as a packet-only `claude -p` session with Read, Grep, Glob and Write only, in the container executor. It writes the transcript as the access log, plus cost and a taint verdict, and its shared mechanics live in `lib/session-exec.sh` (cycle-132 FR-2, D-7.1).
- Added `evals/analysis/c132/annotation_merge.py`. It computes Cohen's kappa on hunk verdicts, incident verdicts and severity, localization and grouping agreement, and an adjudication list. It merges complete adjudication records into labels v2 rows with cross-source deduplication and the review_driven tag (D-2.2).
- Added labels TSV v2 and manifest v2 (`label_set`, per-defect provenance) to `seed-corpus-from-record.sh`, with the schema `evals/harness/schemas/review-manifest.schema.json` (D-2.3).
- Added `label_set` and `labels_meta` to grade.json.
- Moved the frozen cycle-131 keys to `manifests/c131/` and their labels to `labels/review/`. The files are byte-identical, and a recorded cycle-131 run re-grades identically.

## What the lead must do
- **Merge order with A.** My seeder hunks are the constants after `HEADER`, `read_labels` and two helpers, the `build_manifest` loop and tail, `sync_labels`, and one header paragraph; argument parsing and seeding are untouched. In seed-corpus.bats, `scratch_record_fixture`, SC-9 and SC-12 changed, and SC-V2 is appended at EOF, so A's appends conflict only at EOF.
- **Merge order with C.** My ablation-grade.sh hunks, moved clear of C's: the v1 `read_json` line, a block before `# --- corpus digest (1.3.0)`, the `corpus_sha256` path line, 3 lines after `g["verdict_accuracy"]`, header lines after `contamination_exempt`. recall-vs-defects.sh is outside my list, but the change is required. C keeps the rule at 1.3.2, and AG-LS2 pins the recall block.
- **Refreeze, README and REPO-MAP.** Run `seed-corpus-from-record.sh --freeze` and `--check` after all patches. Update evals/README.md (~517) for labels/review/ and manifests/c131/, and regenerate REPO-MAP.
- **A's schema** (rewritten to my subset) validates with --validate and merges end to end; MV-6 may switch to it.
- **Task 1.6 flow:**
  1. Run annotation-packets.sh.
  2. Run `blind-session.sh --packets packets/pr-NN --prompt P --model global.anthropic.claude-opus-5-5 --out …/A`, then the same for B.
  3. Run `annotation_merge.py --fixture pr-NN --a A/labels.json --b B/labels.json --head-dir …/pr-NN/head --out D`. This is the kappa phase; exit 3 means there are disagreements.
  4. Write adj.json.
  5. Run the merge again with `--adjudication adj.json --hunks-meta <out>/pr-NN.hunks.meta.json --fix-rows labels/review/pr-NN.tsv --manifest-c131 manifests/c131/pr-NN.json`.
  6. Copy labels.rows.tsv to labels/pr-NN.tsv and set the approved-by line.
  7. Run `--build-manifest`, then `annotation_merge.py --validate <schema> manifests/pr-NN.json`, then `--freeze`.
  8. Run `--pool` over the kappa files.
- **Missing keys until 1.6.** The cycle-124 review-recall and audit-recall pr-11 to pr-18 tasks have no key until Task 1.6 writes the v2 manifests. They are not in CI.

## Round 2
- **Built:** `blind-session.sh --spend-row FILE` (DEC-0710 cap scope). Once the CLI has run, it appends one JSON line on every exit path: `{run_id, kind: "blind_session", out, model, started, finished, cost_usd, status: completed|failed|cap_hit|timeout|tainted, cap_hit}`. run_id is `blind-` + the first 12 hex of sha256(<absolute out> + started). The append runs under flock on `FILE.lock`, the ablation-row.sh pattern. The exit trap writes the row (as failed) if the driver stops after the CLI ran. With no flag, nothing is appended. The header documents the row as the way a blind session reaches the cycle meter.
- **Tested:** blind-session.bats 11/11 (BS-10, BS-11 new); `bash -n` OK. Patch: ~/.cache/loa/cycle-132/patches/s1-b-r2.patch (blind-session.sh, blind-session.bats); applies to 899c89ea.
- DECISION: a session with no result event (a cap or timeout kill) now reports `total_cost_usd` as the watchdog estimate plus the ledger, with `cost_source: estimate`. Before, cost.json said USD 0 and the meter would have undercounted every capped session. A session with a result event keeps `cost_source: result` and the same value as before.
- DECISION: an interrupted or agent-error session rows as `failed`. A relative `--spend-row` path resolves from the caller's cwd. A usage error (exit 2, before the CLI runs) writes no row.

## Round 3
- **Built (DISS-C-005):** every recognised set directory under `manifests/` (`c131`, `v1`, `review`) is now re-rooted the same way, in both `ablation-grade.sh` (`KEY_SETS`, `label_set`, `key_set_root`) and `recall-vs-defects.sh` (the `set_root` block). The corpus root is the parent of `manifests/`. The fixture head is `<corpus>/<pr>/head`. The v1 snapshot is `manifests/v1/<pr>.json`, which is the key itself for the v1 set. The corpus sums are `<corpus>/SHA256SUMS`. `label_set` gains `review`. The grader version is untouched (C's).
- **Tested on an export of 42537857 with the patch applied:** ablation-grade.bats + eval-recall-grader.bats + manifest-v2.bats ran 120 cases, all green. One is skipped by C's own guard: AG-c132-5 needs commit 346dbb87, which a plain export lacks. New cases: AG-LS3 (synthetic v1 and review keys), AG-LS4 (the recorded cycle-131 run graded against `manifests/v1/pr-17.json`: label_set v1, v1_manifest true, the corpus digest, and recall_pm3 equal to the c131 re-grade's recall_pm3_v1), AG-LS5 (the tracked `manifests/review/pr-27.json`, label_set review) and RG-B1 (the recall grader on c131, v1, review and a non-set sub-directory). `bash -n` is OK.
- DECISION: MV-3 was red on the branch, independent of this round. The c132 suite root rightly names the v2 keys that Task 1.6 wrote at `manifests/pr-11.json`, pr-14, pr-15 and pr-16. MV-3 now flags a `manifests/pr-1x.json` reference only when that file is not a v2 key. That is the regression it exists to catch: the frozen key back at its old path.
- Patch: ~/.cache/loa/cycle-132/patches/s1-b-r3.patch. It touches ablation-grade.sh, recall-vs-defects.sh, ablation-grade.bats, eval-recall-grader.bats and manifest-v2.bats, and `git apply --check` passes on HEAD 2ab4ca72.
