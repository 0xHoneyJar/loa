# Implementer D report: Sprint 263 Task 1.5 (manifests v1 snapshot, blind multi-site anchors)

Worktree `/home/merlin/Documents/thj/code/loa-wt-s1d` (branch `wt/cycle-131-s1d`, base 7600bd7d). No commits, no model calls.

## What was built
- `evals/fixtures/review-prs/manifests/v1/pr-01.json … pr-18.json`: byte-identical copies of the eighteen original manifests (new).
- `evals/fixtures/review-prs/manifests/pr-11.json … pr-18.json`: `anchors[]` extended on 44 defects with 112 lines, and `approved_by` re-stamped to `lead 2026-10-19 (multi-site anchors, cycle-131 Task 1.5; curated by implementer D)`. pr-01 … pr-10 are unchanged.
- `evals/fixtures/review-prs/SHA256SUMS`: regenerated with `seed-corpus-from-record.sh --freeze`, an offline rehash. It went from 842 to 860 entries: 18 new v1 files plus 8 changed digests.
- `grimoires/loa/a2a/sprint-1/anchors-curation.md`: the curation note. It has one table per manifest with each defect's original anchors, added lines, review text of 20 words or fewer, and label source. It also lists the blinding statement, the count, other-file citations and head-absent citations.
- `grimoires/loa/a2a/sprint-1/reviewer-d.md`: a copy of this report.

## How it was tested
```
cd /home/merlin/Documents/thj/code/loa-wt-s1d
for f in evals/fixtures/review-prs/manifests/pr-*.json; do cmp "$f" "${f%/*}/v1/${f##*/}"; done   # before curation: no output
bash evals/harness/seed-corpus-from-record.sh --freeze   # froze 860 files in SHA256SUMS
bash evals/harness/seed-corpus-from-record.sh --check    # corpus OK: 860 files match SHA256SUMS
bash -c '~/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats evals/tests/'   # 1..447, 447 ok, 0 not ok
```
No new bats file was added. The task is data curation and owns no test file. The full `evals/tests/` suite ran 447 cases: 447 ok, 0 not ok, 0 skip.

## AC evidence
- PASS. **v1 is byte-identical to the originals.** `cmp` printed nothing for all 18 files right after the copy. v1 also byte-equals `git show ba11b860:evals/fixtures/review-prs/manifests/pr-NN.json` for all 18, which is Task 1.9 step 0, checked in advance.
- PASS. **Every added anchor exists in `head/<file>`.** The apply script asserts each added line is between 1 and the file's length and is non-blank. It reported `errors 0`. Each line was also read by hand to confirm it holds the code the review describes.
- PASS. **`seed-corpus-from-record.sh --check` passes.** Output: `corpus OK: 860 files match SHA256SUMS`, rc 0.
- PASS. **The curation note is complete.** It covers all 18 manifests: a table per manifest for pr-11 … pr-18 and one paragraph for pr-01 … pr-10. It includes the blinding statement, the count (44 defects, 112 lines) and the other-file and head-absent lists.
- PASS. **`jq` parses every manifest.** `jq empty` succeeded on all 18 current files and all 18 v1 files.
- PASS. **No key other than `anchors` and `approved_by` changed.** For every manifest, `diff <(jq -S 'del(.approved_by) | .defects |= map(del(.anchors))' v1/pr-NN.json) <(same on pr-NN.json)` was empty, all 18 of 18. A Python check also confirmed that no original anchor was removed, `anchor_line` is unchanged and `anchors` is sorted.
- PASS. **Formatting is preserved.** Changed manifests are written as `json.dumps(indent=2, ensure_ascii=True)` without a trailing newline. That reproduces the original bytes exactly; this was asserted before rewriting.

## DECISION bullets
- DECISION: "every head line the human finding named" covers explicit `path:line` citations, range endpoints, and the distinct statements inside a range that the finding names. It also covers code the finding names by identifier or quote, such as "`_ceiling_unverified` read in the RateLimitError and ProviderContextLimitError arms", resolved in `head/`. Most record findings name functions and expressions, not numbers. A numbers-only reading would have added almost nothing, which defeats FR-2's multi-site intent.
- DECISION: some reviews cite line numbers from a later commit than the fixture head: pr-13 (4992b5a6), pr-14 audit (005b9105), pr-15 (58f87195, cbfccab2), pr-17 audit (30727c95) and pr-18 audit (3b0f8bf3). For these, I read the file at the reviewed commit with `git show <sha>:<path>` and mapped each citation to the `head/` line holding the same code. Raw numbers whose `head/` line holds other code were never added. These are source-tree reads, not arm outputs.
- DECISION: when a cited code site does not exist in the fixture head, nothing is added and the citation is listed as HEAD-ABSENT. Cases: pr-15 L01 (`is_throttle_message`), pr-15 L02 (`_config_untrusted_reason` and the related lines), pr-14 L02 (`canonical_root`/`logical_root` and the trust-input case), and pr-17 L10 (the `.run`/`.beads` newer-than check).
- DECISION: pr-15 L03 is mapped by content. The head's rate-limit branch markers `429` and `quota` (547, 551) and `raise RateLimitError` (553) precede the static-auth `raise ConfigError` (583). That is the precedence the audit names, even though the head does not yet have `_throttle`.
- DECISION: pr-01 … pr-10 get no new anchors. They carry no `label_source`/`source` and have no record review; pr-09 and pr-10 have no defects. Their manifests carry no `approved_by` key and stay byte-identical. sprint.md Task 1.5 says "pr-05 … pr-18", but pr-05 … pr-10 have no human review to curate from, so the result is the same.
- DECISION: blank lines at a range endpoint are skipped, for example pr-16 `check-round-independence.sh:63`. A non-code endpoint inside the range, such as a `fi` or `else`, is kept as the rule says. The 6-line cap per defect was respected; the maximum added is 6, on pr-17 L06 and L14.
- DECISION: citations in a file other than `defect.file` are not added; the note lists them. When a finding names a sentence's site that the review then refutes, it is not added. Example: `op_resolve` in pr-17 L11, whose raw-field claim the audit refutes.
- DECISION: `SHA256SUMS` was regenerated with the script's own `--freeze` flag. It is offline and only rehashes files under the corpus, so it needs neither network nor record access.

## What the lead must do
- **Re-approve the eight changed manifests.** pr-11 … pr-18 carry the curated-by-D `approved_by` stamp. Spot-check the tables in `anchors-curation.md`. The judgment-heavy rows are pr-13 L02, pr-14 L02, pr-15 L03, pr-17 L06/L09/L14 and pr-18 L01/L08.
- **Keep the labels in step with the manifests.** `seed-corpus-from-record.sh --build-manifest <fx>` regenerates `manifests/pr-NN.json` from `labels/pr-NN.tsv`, "one row per anchor". The new anchors are not in `labels/*.tsv`, which is outside my ownership. Rebuilding any of pr-11 … pr-18 from labels would silently drop them. Either add label rows for the new anchors, or record that pr-11 … pr-18 must not be rebuilt from labels after this task.
- **Regenerate `.claude/checksums.json` if the corpus is listed there.** I did not touch it.
- **No rule change was needed.** Per-defect anchor count rises to at most 10 (pr-17 L14). The grader's existing "any line in `anchors[]`" rule consumes this with no shape change, per DEC-0616 and no new key.
- **Integration order.** Apply this patch before Task 1.9's re-grade. `recall_pm3_v1` reads `manifests/v1/`, which this patch creates.
