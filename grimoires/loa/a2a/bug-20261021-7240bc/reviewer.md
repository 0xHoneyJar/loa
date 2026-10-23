# sprint-bug-268 (bug 20261021-7240bc, bd-y4pqj) — implementer C report

Model: global.anthropic.claude-opus-5-5. Worktree: /home/merlin/Documents/thj/code/loa-wt-bugc (base 03e77312).
Red commit: c1477420 (fix: 98b27811)

## What was built
- **Task 1 (failing tests)**: `evals/tests/seed-corpus.bats` gains SC-9 to SC-12, plus helpers `scratch_record_fixture` (copies only labels/, manifests/, fixture.yaml and the head files the labels' `file` column names), `synthetic_at_fixture` (5-line pr-93 with two non-unique `}` lines) and `curate_manifest` (edits a manifest the way Task 1.5 did, keeping the builder's key order).
- **Task 2 (fix)**, all in `evals/harness/seed-corpus-from-record.sh`:
  - `resolve_anchor` (line 243). `@L<n>` names head line n; it is refused when it is not `@L` + positive integer (`@L0`, `@Lx`, `@L-1`, `@L4x`) or past the file's end. Text keeps `unique_line`. Errors read `<defect_id>: must_match '<value>' <why>`. `build_manifest` uses it and gains `write=True`; the output JSON is unchanged.
  - `sync_labels` (line 312) and the `--sync-labels pr-NN` mode (see the header block for the contract).
  - Synced pr-11 … pr-18: 112 rows added (100 text, 12 `@L<n>`). Every labels file got its `# approved-by:` line from the manifest. `--freeze` changed 8 SHA256SUMS lines, all for the labels files.
- **Task 3 (docs)**: script header modes list (line 13), the "Label grammar" and "--sync-labels" paragraphs (lines 47-65), the seeder's labels header comment (line 856).

## Red run
At the red patch on a pristine `git archive HEAD` export (the same as in the worktree):
```
ok 1 … ok 8   (SC-1 … SC-8)
not ok 9 SC-9 --build-manifest reproduces every tracked record manifest (pr-11 … pr-18) byte for byte from its labels
#   `[ -z "$bad" ]' failed
# differs: pr-11 pr-12 pr-13 pr-14 pr-15 pr-16 pr-17 pr-18
not ok 10 SC-10 a must_match of @L<n> anchors head line n; …
#   `[ "$status" -eq 0 ]' failed          (today: must_match '@L4' is not on exactly one line)
not ok 11 SC-11 --sync-labels appends one row per manifest anchor …
#   `[ "$status" -eq 0 ]' failed          (today: argparse unknown option, exit 2)
not ok 12 SC-12 after --sync-labels and --freeze, --check passes; …
#   `[ "$status" -eq 0 ]' failed
```

## How it was tested
| Command | Result |
|---|---|
| `~/.cache/loa/cycle-128/s2d/bin/bats evals/tests/seed-corpus.bats` (red) | 12 cases: 8 pass, 4 fail |
| same (green) | 12/12 pass |
| `~/.cache/loa/cycle-128/s2d/bin/bats evals/tests/` | 535/535 pass, exit 0. HEAD ran 531: `ablation-grade.bats` has 3 `@test` lines bats does not count (59 vs 56), so the brief's 534 is a grep count. 531 + 4 new = 535. |
| `bash -n evals/harness/seed-corpus-from-record.sh` | ok |
| `tools/check-no-raw-sha256sum.sh`, `check-no-swallowed-jq.sh`, `check-no-raw-curl.sh` | all OK |
| `evals/graders/no-secrets.sh evals/fixtures/review-prs/labels` | pass |

E2E:
```
$ S=$(mktemp -d); cp -r evals/fixtures/review-prs "$S/review-prs"; bash evals/harness/seed-corpus-from-record.sh --build-manifest pr-17 --corpus "$S/review-prs"; cmp "$S/review-prs/manifests/pr-17.json" evals/fixtures/review-prs/manifests/pr-17.json && echo identical
pr-17: 20 label(s), 105 fix region(s); approved=True; SHA256SUMS 860 files
identical
$ bash evals/harness/seed-corpus-from-record.sh --check
corpus OK: 860 files match SHA256SUMS
$ git diff --stat -- evals/fixtures/review-prs/manifests
(empty)
```
A second `--sync-labels` over pr-11 … pr-18 printed `added 0 row(s) (0 text, 0 @L<n>); approved-by unchanged` for each.

## AC Verification
- Tests fail at the current code: PASS. See the red run above, on a pristine HEAD export.
- Test names describe the scenario: PASS, `evals/tests/seed-corpus.bats:264,277,302,333`.
- Tests are isolated: PASS. Scratch roots live under `$T` (BATS_TEST_TMPDIR). The tracked corpus is only read, and only the needed head files are copied (`seed-corpus.bats` `scratch_record_fixture`).
- Committed alone before the fix: LEAD. The red patch touches only the bats file (`bug-c-red.stat`).
- Failing tests now pass: PASS, 12/12.
- Manifests byte-identical: PASS, `git diff --stat -- evals/fixtures/review-prs/manifests` is empty.
- No regressions: PASS, full `evals/tests/` 535/535.
- Root cause fixed, no hand edits: PASS. Labels were written only by `--sync-labels`; each sync re-verified a byte-identical rebuild internally; no manifest was touched and no fixture was skipped.
- Fix does not weaken the test: the red patch is the final test file. The lead runs `red-test-check.sh`.
- Script header and labels header comment, `bash -n`: PASS, `seed-corpus-from-record.sh:13,47-65,856`.
- E2E pr-17 rebuild identical and `--check` passes: PASS (above).
- Every record fixture rebuilds byte for byte: PASS, SC-9 at `seed-corpus.bats:264`.

## DECISION bullets
- DECISION: any `must_match` starting with `@L` is the explicit form. It must be `@L` + a positive integer with no leading zero. `@L0`, `@Lx`, `@L-1`, `@L4x` and `@L007` are refused, not read as text. No tracked row starts with `@L` (checked).
- DECISION: a synced text row uses the head line's stripped text, and only when that text resolves back to the same line under `unique_line`. Empty text, tabs, `@L`-prefixed text, secret-shaped text and characters that split a line fall back to `@L<n>`. Rejected: unstripped text (trailing-space fragility) and the seeder's `anchor_text` length/trivial filter (it pushes short unique lines to the less robust `@L<n>`). Result: 112 rows, 12 `@L<n>`. The triage counted 11 non-unique lines; with the stripped-text rule there are 12.
- DECISION: synced rows go right after the defect's last existing row, not at the end of the file. This groups a defect's anchors for curators. The build is order-independent because anchors are `sorted(set(...))`, and the first row stays primary, so `anchor_line` and `must_match` do not change.
- DECISION: `--sync-labels` does not refreeze. It prints `run --freeze to refresh SHA256SUMS`, following the brief's sync-then-freeze sequence and SC-12. Rejected: auto-freezing like `--approve` does.
- DECISION (beyond the brief): after writing, `--sync-labels` rebuilds the manifest in memory with `build_manifest(fx, write=False)` and compares bytes. On a mismatch it restores the labels file and exits 1, so a half-synced labels file can never be left behind.
- DECISION: `--sync-labels` refuses with exit 1 when any of these hold: the manifest is missing; `approved` disagrees with `approved_by != "pending"`; `approved_by` has control characters or surrounding space; a manifest defect has no labels row; a labels defect is not in the manifest; the defect's file differs; an anchor is out of range; an existing row no longer resolves.
- DECISION: rows from `--sync-labels` copy every column except `must_match` from the defect's primary row, so there is no new `label_source` value.
- DECISION: the test helper `curate_manifest` puts `anchors` right after `anchor_line`, matching the builder and the Task 1.5 manifests. A first draft used jq, which appends the key at the end. The rebuild then differed and the self-check correctly refused, which was a test bug and not a script bug.
- DECISION: the `excluded generated path:` stderr lines that the self-check rebuild prints during `--sync-labels` are left in place. They are the existing `--build-manifest` diagnostics.

## CHANGELOG entry text (### Fixed)
- Fixed the labels files `evals/fixtures/review-prs/labels/pr-11 … pr-18.tsv` drifting from the curated manifests. `seed-corpus-from-record.sh` gained an explicit-line `must_match` form `@L<n>` and a `--sync-labels pr-NN` mode, and the eight labels files were synced. `--build-manifest` now reproduces every tracked manifest byte for byte (bug 20261021-7240bc, bd-y4pqj).

## What the lead must do
- Apply `bug-c-red.patch`, commit `test(20261021-7240bc): failing test`, then apply the rest of `bug-c-full.patch` and commit the fix. The full patch is cumulative and includes the test file.
- `grimoires/loa/a2a/` is git-ignored (`.gitignore:193`). `reviewer.md` exists in the worktree but is not in either patch. Copy it from this report and fill in `Red commit:`.
- Regenerate `REPO-MAP.md` and `.claude/checksums.json` if your pipeline needs it. No `.claude/` file was changed.
- Close bead bd-y4pqj.
- Note: re-seeding a record fixture from scratch still regenerates its labels without the synced rows. Run `--sync-labels` after any re-seed, or record the anchors in `curation.tsv`. This is unchanged behaviour and outside this sprint.
