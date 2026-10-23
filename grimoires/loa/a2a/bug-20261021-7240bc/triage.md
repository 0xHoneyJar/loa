# Bug Triage: `seed-corpus-from-record.sh --build-manifest` regresses the curated multi-site manifests because `labels/pr-NN.tsv` cannot express them (bd-y4pqj)

## Metadata
- **schema_version**: 1
- **bug_id**: 20261021-7240bc
- **classification**: data_drift_bug (two sources of truth; the generator's grammar cannot represent the curated artefact)
- **severity**: medium
- **eligibility_score**: 3
- **eligibility_reasoning**: Reproducible steps with exact output (+2): on a scratch copy of the corpus, `seed-corpus-from-record.sh --build-manifest pr-17 --corpus /tmp/c132-labels-5scS/review-prs` (2026-10-21T00:40Z) rebuilt pr-17 with 13 of 20 defects losing anchors (L06 `anchors` None vs curated `[637, 642, 651, 653, 655, 657, 691]`; L14 `[398, 408, 414, 437]` vs `[398, 407, 408, 414, 437, 474, 476, 478, 480, 482]`), pr-18 7 of 8, pr-12 7 of 8, and `approved_by` regressing to `lead 2026-10-14`. Regression from a known baseline (+1): the curated manifests are the tracked artefact at pin `798d88cf` (cycle-131 Task 1.5, DEC-0626) that every cycle-131 row was graded against; a rebuild silently replaces the key. No disqualifier (no new endpoint, UI, schema or configuration key: the TSV grammar gains one value form for an existing column).
- **test_type**: unit
- **risk_level**: low
- **created**: 2026-10-21T00:52:00Z

## Reproduction
### Steps
1. `S=$(mktemp -d); cp -r evals/fixtures/review-prs "$S/review-prs"`.
2. `bash evals/harness/seed-corpus-from-record.sh --build-manifest pr-17 --corpus "$S/review-prs"` (exit 0).
3. `diff <(jq -S . "$S/review-prs/manifests/pr-17.json") <(jq -S . evals/fixtures/review-prs/manifests/pr-17.json)`.
4. Repeat for pr-11 … pr-18.

### Expected Behavior
- Step 3: no difference — the labels file is the single source the manifest is generated from, so `--build-manifest` reproduces the tracked manifest byte for byte (same `anchors`, same `approved_by`), and a bats case pins that for every record fixture.
- Every curated anchor line can be expressed in the TSV, including the 11 of 221 whose text is not unique in the head file.

### Actual Behavior
- Step 3: pr-17 — 13 of 20 defects differ in `anchors` (every anchor added by Task 1.5 is missing; several defects fall back to a single `anchor_line` with no `anchors` key); `approved_by` is `lead 2026-10-14` (from the TSV header) instead of `lead 2026-10-19 (multi-site anchors, cycle-131 Task 1.5; curated by implementer D)`. pr-18: 7 of 8; pr-12: 7 of 8 (observed 2026-10-21T00:40Z).
- Root cause: Task 1.5 edited `manifests/pr-11 … 18.json` directly (`anchors[]` extended, `approved_by` rewritten) while `labels/pr-NN.tsv` kept the seeded rows; `build_manifest` (`seed-corpus-from-record.sh:219-275`) derives every anchor from a `must_match` text that must occur on exactly one head line (`unique_line`, `:215-217`), so 11 curated lines (bare `}` and similar) have no possible row.

### Environment
main `16e0b48b`, branch `fix/cycle-132-bugs`; Python 3.13 (the seeder's embedded program); corpus `evals/fixtures/review-prs` with `SHA256SUMS` frozen; `evals/tests/seed-corpus.bats` SC-1 … SC-8 (no reproduction case).

## Analysis
### Suspected Files
| File | Line(s) | Confidence | Reason |
|------|---------|------------|--------|
| `evals/harness/seed-corpus-from-record.sh` | 183-201 | high | `read_labels`: header `# approved-by:` is the only approval source; rows are text-only |
| `evals/harness/seed-corpus-from-record.sh` | 215-275 | high | `build_manifest`: `unique_line` text matching only; no explicit-line form; `approved_by` from the header |
| `evals/harness/seed-corpus-from-record.sh` | 720-745 | medium | the label writer and its header comment (`curate must_match (one row per anchor)`) — the grammar documentation to extend |
| `evals/fixtures/review-prs/labels/pr-11 … pr-18.tsv` | all | high | missing one row per curated anchor; stale `# approved-by:` line |
| `evals/fixtures/review-prs/manifests/pr-11 … pr-18.json` | all | medium | the curated truth to reproduce byte for byte (must not change) |
| `evals/fixtures/review-prs/SHA256SUMS` | all | medium | refreezes after the labels change (`--freeze`); `--check` must pass |
| `evals/tests/seed-corpus.bats` | 45-200 | low | SC-1 … SC-8 must keep passing; the new reproduction case lands here |

### Related Tests
| Test File | Coverage |
|-----------|----------|
| `evals/tests/seed-corpus.bats` | seeding, secrets, grading, approval, curation, dry-run, generated-path exclusions (SC-1 … SC-8) |
| `evals/tests/ablation-grade.bats`, `recall-vs-defects` tests | consume manifests; unaffected when the manifests are byte-identical |
| (none) | `--build-manifest` reproduces the tracked manifests |

### Test Target
Extend `evals/tests/seed-corpus.bats`, failing first:
- SC-9 for each of pr-11 … pr-18, a scratch corpus holding only `labels/`, `manifests/`, `pr-NN/fixture.yaml` and the `pr-NN/head/<file>`s the labels name: `--build-manifest pr-NN` exits 0 and `cmp` of the rebuilt manifest against the tracked one is byte-identical (fails today on every record fixture).
- SC-10 a label row whose `must_match` is `@L<n>` anchors line n of the head file; `@L0`, `@L<past end>` and a non-integer are refused with the row named (fails today: `must_match '@L5' is not on exactly one line`).
- SC-11 `--sync-labels pr-NN` (new mode) emits, for every manifest anchor without a row, a row whose `must_match` is the line's text when unique in the file, else `@L<n>`, and rewrites the `# approved-by:` header from the manifest's `approved_by`; running it twice changes nothing (fails today: mode unknown).
- SC-12 after `--sync-labels` + `--freeze`, `--check` passes (fails today: no mode).

### Constraints
- The curated manifests are the truth and do not change: the fix brings the labels and the generator to them; a byte-identical rebuild is the acceptance test. Key order and `json.dump(indent=2)` formatting are already identical (verified on pr-17).
- The TSV grammar gains exactly one value form for the existing `must_match` column — `@L<n>` (explicit head line, 1-based, validated against the file's length) — used only where the line text is not unique; text stays the preferred, renumbering-robust form. The header comment documents it.
- `label_source` of synced rows stays that of the primary row (the curated anchors are the same defect's sites; cycle-131 DEC-0626); no new `label_source` value.
- `curation.tsv` keeps working on re-seed (SC-5); `--approve` keeps its semantics (the header line is the approval record; `--sync-labels` copies the manifest's `approved_by` into it so a rebuild reproduces it).
- `SHA256SUMS` refreezes; `--check` passes; `evals/tests/` stays green (534 cases + new); `bash -n`; stdlib Python; no live model calls.

## Fix Strategy
Extend `read_labels`/`build_manifest` so a `must_match` of the form `@L<n>` resolves to head line n (validated) while text rows keep `unique_line`; add `--sync-labels pr-NN` that reads the tracked manifest and the labels, appends one row per anchor that has no row (text when unique, else `@L<n>`), rewrites the `# approved-by:` header from the manifest, and is idempotent; run it over pr-11 … pr-18, refreeze `SHA256SUMS`, and add SC-9 … SC-12 so a drift can never return unnoticed. Update the labels header comment and the script header (modes, grammar).

### Fix Hints
Structured hints for multi-model handoff (each hint targets one file change):

| File | Action | Target | Constraint |
|------|--------|--------|------------|
| `evals/harness/seed-corpus-from-record.sh` | add | `@L<n>` form in `build_manifest` (validated explicit line) | text rows unchanged; errors name the row |
| `evals/harness/seed-corpus-from-record.sh` | add | `--sync-labels pr-NN` mode (rows per missing anchor; header from manifest; idempotent) | never edits the manifest; prints what it added |
| `evals/harness/seed-corpus-from-record.sh` | fix | header and labels-header comment: modes and the `@L<n>` grammar | one paragraph each |
| `evals/fixtures/review-prs/labels/pr-11 … pr-18.tsv` | fix | synced rows + approved-by header | generated by `--sync-labels`, not by hand |
| `evals/fixtures/review-prs/SHA256SUMS` | fix | refreeze | `--check` passes |
| `evals/tests/seed-corpus.bats` | add | SC-9 … SC-12 | scratch corpus with only the needed head files |
