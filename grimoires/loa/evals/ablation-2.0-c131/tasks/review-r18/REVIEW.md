# Fairness review — review-r18

**Reviewer:** fairness session (Claude Opus 5.5), 2026-10-19 · **Author:** replication-author (Opus 5.5) · **Verdict:** PASS

## 1. No solution leak

PASS. TASK.md carries a neutral change summary, the `pr/` layout and the output contract. Judged against: "The change: glossaries, seams placed under test and a red-before-green testing discipline, the third part of a decision-surfaces release (one sprint of a release cycle)." That summary paraphrases the title of `evals/fixtures/review-prs/pr-18/PR.md`, "sprint-254 decision surfaces, part 3 — glossaries, seams under test, red-before-green". The agent reads that file anyway. PR.md is three lines: the title and a sprint/file-count line.

- `diff` of TASK.md against `ablation-2.0/tasks/review-03/TASK.md` shows exactly one changed line, line 3, the change-summary sentence.
- `diff` of the two `## Output contract` sections, from the heading to the end of file, is empty (byte-identical).
- A grep of TASK.md for defect ids, anchors, manifest, grader, label, arm ids and counts finds nothing beyond the generic "find the defects it introduces".
- `evals/harness/pipeline-run.sh` (lines 501–505) copies only `base head head.diff PR.md REVIEW-INSTRUCTIONS.md AUDIT-INSTRUCTIONS.md` into `pr/`. `fixture.yaml` is present in the fixture and is not copied.
- `grep -rFl -f <the 8 manifest id values>` over each of those six paths returns zero hits. A grep for `manifests/`, `recall-vs-defects` and `fix_regions` over the same paths also returns nothing.

## 2. Red then green

The manifest `evals/fixtures/review-prs/manifests/pr-18.json` holds 8 defects: 1 high, 2 medium, 5 low. It is a record fixture, approved by "lead 2026-10-14", with 116 fix regions. The one high defect is L06.

The accurate verdict is **CHANGES_REQUIRED**. The key rule gives CHANGES_REQUIRED if and only if a high or critical defect is in the key, and the success criterion states this verdict.

Every `anchor_line` and every `anchors[]` entry lies inside its `head/<file>`. A `python3 -I` check against each file's line count reported 0 out of range across the 8 defects.

The corpus exists: `evals/fixtures/review-prs/pr-18/{PR.md,head.diff,base/,head/}`, with 12 base files, 29 head files and a 2,194-line diff covering 29 files.

`recall-vs-defects.sh` (grader 1.2.0), run in a `mktemp -d` workspace:

```
synthetic findings citing every anchor:  {"pass":true,"score":100,"recall":1.0,"planted":8,"missed":[]}   exit 0
verdict-only file:                       {"pass":false,"score":0,"recall":0.0,"planted":8}               exit 1
```

## 3. Criterion mechanical

PASS. `diff` of task.yaml against review-03's differs only in `id`, `source` (origin pr-18, date 2026-10-13), the fixture id inside `success_criterion`, and `review_catch`.

- `criterion` is byte-identical to review-03's.
- `success_criterion` names the grader's rule, a `head/<path>:<line>` citation within 3 lines of a manifest anchor, and the exact verdict CHANGES_REQUIRED.
- `review_catch.fixture: review-prs/pr-18` and `manifest: evals/fixtures/review-prs/manifests/pr-18.json` both exist.
- `suite_version: 2`, `bounds: {max_turns: {}, timeout_min: {}}`, `fixture: null` and `grader_protected: []` all match review-03.

```
$ bash evals/harness/validate-suite.sh --root grimoires/loa/evals/ablation-2.0-replication --allow-partial --suite-file evals/suites/ablation-2.0.yaml
validate-suite: OK — 2 task(s) valid in /home/merlin/Documents/thj/code/loa/grimoires/loa/evals/ablation-2.0-replication (partial: type counts not enforced)
```

## Notes

- **Difficulty is comparable to review-03, slightly larger.** The diff is about twice as large, 2,194 lines over 29 files against 1,077 lines over 15. The key has the same count, 8 defects, but a lighter mix: 1 high, 2 medium, 5 low against 3/3/2.
- **Defect ids skip L04.** The ids run L01, L02, L03, L05 through L09. This is cosmetic: the grader counts `defects[]` entries, and `planted` is 8. It suggests a labelled candidate was dropped during key approval. The lead may want to confirm that from the labelling record, but it does not affect fairness.
- **Shared anchors.** L01 and L02 share lines 131 and 148 in `tools/check-glossary-terms.sh`, so one citation at either line credits both. This inflates recall slightly for any arm that finds either, and affects every arm equally.
- **Concentration.** Three of the 8 defects, including the only high one, sit in `.claude/scripts/red-test-check.sh`. The verdict-relevant defect and much of the recall depend on that one 346-line file.
- **Pipeline note from review-03 applies here too.** `REVIEW-INSTRUCTIONS.md`, copied into `pr/`, says to write `review.md` "in this directory", meaning `pr/`. TASK.md says the repository root. The lead should confirm that the grader reads only the root `review.md`.
