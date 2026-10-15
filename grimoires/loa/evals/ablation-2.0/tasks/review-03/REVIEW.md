# Fairness review — review-03

**Reviewer:** fairness session R1 (Claude Opus 5.5), 2026-10-15 · **Author:** implementer E · **Verdict:** PASS

## 1. No solution leak

PASS. TASK.md carries a neutral change summary, the `pr/` layout and the output contract. Judged against: "The change: a companion dissent voice for the adversarial review, a tolerant findings schema, a contract for rejected payloads and a repair model (one sprint of a release cycle)." That summary paraphrases the title of `evals/fixtures/review-prs/pr-12/PR.md` (copied to `pr/PR.md`), which the agent reads anyway. It names no defect, no anchor line and no grader artefact. A grep of everything the pipeline copies into `pr/` found no defect id. The copied files are base, head, head.diff, PR.md and the two instruction files, and `fixture.yaml` is not copied. The criterion is the generic review sentence shared with the smoke.

## 2. Red then green

The manifest `evals/fixtures/review-prs/manifests/pr-12.json` holds 8 defects: 3 high, 3 medium, 2 low (a record fixture, approved, with 161 fix regions). Every anchor line lies inside its `head/` file.

The corpus files `evals/fixtures/review-prs/pr-12/{PR.md,head.diff,base,head}` all exist (9 base files, 15 head files, a 1077-line diff).

The output contract section of TASK.md is byte-identical to `smoke/smoke-review-01/TASK.md`. A `diff` of the two sections from `## Output contract` to the end of the file is empty.

The accurate verdict is **CHANGES_REQUIRED**. The key rule gives CHANGES_REQUIRED if and only if a high or critical defect is in the key, and the success criterion states this verdict.

`recall-vs-defects.sh <ws> pr-12 <file>` scored a synthetic findings file citing every anchor with `recall 1.0`, `pass true`. It scored a verdict-only file with `recall 0.0`, `pass false`. That matches the suite README's scoring row.

## 3. Criterion mechanical

PASS. The success criterion is one line: the grader script's recall with the ±3-line rule, which matches the script's code, plus an exact verdict. The README defines the review-catch score as that recall value, so two graders running the script agree. For clarity, the lead may append "(score = recall value)". The smoke uses the same wording.

## Notes

- Difficulty: hard, about 30–50 Opus turns over a 2,241-line head script.
- The corpus fixture is 840K. `no-secrets.sh` exits 0 on it. There is no task fixture, and `grader_protected` is empty, which is correct for review-catch.
- Two key defects share one anchor line, so a single citation there credits both. This inflates recall slightly for any arm that finds either, and it affects every arm equally.
- This note concerns the pipeline, not the author, and applies to every review task. `pipeline-run.sh` copies `REVIEW-INSTRUCTIONS.md` into `pr/`. That file says to write `review.md` "in this directory", meaning `pr/`, and to end with the skill's verdict trailer. TASK.md says `review.md` goes at the repository root and nothing under `pr/` changes. The bare prompt uses TASK.md, but an agent that opens the instruction file sees a conflicting location. The lead should confirm that the grader reads only the root `review.md`, or drop the instruction files from the copy list.
