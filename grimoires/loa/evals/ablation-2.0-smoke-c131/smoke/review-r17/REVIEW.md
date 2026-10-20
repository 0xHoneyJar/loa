# Fairness review — review-r17

**Reviewer:** fairness session (Claude Opus 5.5), 2026-10-19 · **Author:** replication-author (Opus 5.5) · **Verdict:** PASS

## 1. No solution leak

PASS. TASK.md carries a neutral change summary, the `pr/` layout and the output contract. Judged against: "The change: a decision-map workflow and a discipline for prototype tickets, the second part of a decision-surfaces release (one sprint of a release cycle)." That summary paraphrases the title of `evals/fixtures/review-prs/pr-17/PR.md`, "sprint-253 decision surfaces, part 2 — the /chart decision map and the prototype-ticket discipline". The agent reads that file anyway. PR.md is three lines: the title and a sprint/file-count line.

- `diff` of TASK.md against `ablation-2.0/tasks/review-03/TASK.md` shows exactly one changed line, line 3, the change-summary sentence.
- `diff` of the two `## Output contract` sections, from the heading to the end of file, is empty (byte-identical).
- A grep of TASK.md for defect ids, anchors, manifest, grader, label, arm ids and counts finds nothing beyond the generic "find the defects it introduces".
- `evals/harness/pipeline-run.sh` (lines 501–505) copies only `base head head.diff PR.md REVIEW-INSTRUCTIONS.md AUDIT-INSTRUCTIONS.md` into `pr/`. `fixture.yaml` is present in the fixture and is not copied.
- `grep -rFl -f <the 20 manifest id values>` over each of those six paths returns zero hits. A grep for `manifests/`, `recall-vs-defects` and `fix_regions` over the same paths also returns nothing.

## 2. Red then green

The manifest `evals/fixtures/review-prs/manifests/pr-17.json` holds 20 defects: 2 high, 5 medium, 13 low. It is a record fixture, approved by "lead 2026-10-14", with 105 fix regions. The two high defects are L01 and L10.

The accurate verdict is **CHANGES_REQUIRED**. The key rule gives CHANGES_REQUIRED if and only if a high or critical defect is in the key, and the success criterion states this verdict.

Every `anchor_line` and every `anchors[]` entry lies inside its `head/<file>`. A `python3 -I` check against each file's line count reported 0 out of range across the 20 defects. The largest anchor is 846 in a 1,748-line file.

The corpus exists: `evals/fixtures/review-prs/pr-17/{PR.md,head.diff,base/,head/}`, with 25 base files, 41 head files and a 4,437-line diff covering 41 files.

`recall-vs-defects.sh` (grader 1.2.0), run in a `mktemp -d` workspace:

```
synthetic findings citing every anchor:  {"pass":true,"score":100,"recall":1.0,"planted":20,"missed":[]}   exit 0
verdict-only file:                       {"pass":false,"score":0,"recall":0.0,"planted":20}               exit 1
```

## 3. Criterion mechanical

PASS. `diff` of task.yaml against review-03's differs only in `id`, `source` (origin pr-17, date 2026-10-13), the fixture id inside `success_criterion`, and `review_catch`.

- `criterion` is byte-identical to review-03's.
- `success_criterion` names the grader's rule, a `head/<path>:<line>` citation within 3 lines of a manifest anchor, and the exact verdict CHANGES_REQUIRED.
- `review_catch.fixture: review-prs/pr-17` and `manifest: evals/fixtures/review-prs/manifests/pr-17.json` both exist.
- `suite_version: 2`, `bounds: {max_turns: {}, timeout_min: {}}`, `fixture: null` and `grader_protected: []` all match review-03.

```
$ bash evals/harness/validate-suite.sh --root grimoires/loa/evals/ablation-2.0-replication --allow-partial --suite-file evals/suites/ablation-2.0.yaml
validate-suite: OK — 2 task(s) valid in /home/merlin/Documents/thj/code/loa/grimoires/loa/evals/ablation-2.0-replication (partial: type counts not enforced)
```

## Notes

- **Difficulty is higher than review-03.** The diff is about four times larger, 4,437 lines over 41 files against 1,077 lines over 15. The key has 20 defects against 8, but the mix is lighter: 2 high, 5 medium, 13 low against 3/3/2. Expect lower absolute recall than review-03 for every arm, with the low-severity tail dominating the denominator.
- **Shared and adjacent anchors.** L02 and L11 share line 369 and L02 and L14 share line 414 in `chart-ticket.sh`. In `block-destructive-bash.sh`, L06 (637) and L12 (642) are 5 lines apart, so a citation at 639 or 640 credits both. In `chart-unblock-probe.sh`, L08 (62) and L10 (66) are 4 apart, so a citation at 63 to 65 credits both. Each of these inflates recall slightly for any arm that finds either neighbour, and affects every arm equally.
- **Six files carry several defects.** `chart-ticket.sh` alone holds 6 of the 20 defects. An arm that reads that one file closely gains a large share of the recall.
- **Pipeline note from review-03 applies here too.** `REVIEW-INSTRUCTIONS.md`, copied into `pr/`, says to write `review.md` "in this directory", meaning `pr/`. TASK.md says the repository root. The lead should confirm that the grader reads only the root `review.md`.
