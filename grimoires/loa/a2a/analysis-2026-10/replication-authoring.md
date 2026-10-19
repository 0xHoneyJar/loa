# Replication suite authoring (cycle-130 out-of-sample, 2026-10-19)

## Files created

- `grimoires/loa/evals/ablation-2.0-replication/README.md`
- `grimoires/loa/evals/ablation-2.0-replication/tasks/review-r17/task.yaml` and `TASK.md` (pr-17)
- `grimoires/loa/evals/ablation-2.0-replication/tasks/review-r18/task.yaml` and `TASK.md` (pr-18)

The files were generated from review-03 by substitution. Diffing against review-03 shows only the id, origin, date, pr-NN, and the change summary. `criterion` is byte-identical. The `## Output contract` section is byte-identical for both tasks, checked with `diff`.

| fixture | defects | high | medium | low | verdict |
|---|---|---|---|---|---|
| pr-17 | 20 | 2 | 5 | 13 | CHANGES_REQUIRED |
| pr-18 | 8 | 1 | 2 | 5 | CHANGES_REQUIRED |

## Change summaries

- review-r17: "a decision-map workflow and a discipline for prototype tickets, the second part of a decision-surfaces release (one sprint of a release cycle)."
- review-r18: "glossaries, seams placed under test and a red-before-green testing discipline, the third part of a decision-surfaces release (one sprint of a release cycle)."

## Dates

Both head commits exist locally. `git log -1 --format=%cs` gives 2026-10-13 for cea919ca (pr-17) and for efacf754 (pr-18). I used 2026-10-13 for both. The 2026-10-14 fallback was unused. The same rule reproduces review-03's date of 2026-09-25 from pr-12's head.

## Validation

```
validate-suite: OK — 2 task(s) valid in .../ablation-2.0-replication (partial: type counts not enforced)
exit=0
```

## Recall self-tests

I built the synthetic files with `python3 -I` in mktemp dirs under /tmp.

| fixture | input | recall | detected/planted | exit |
|---|---|---|---|---|
| pr-17 | every anchor cited | 1.0 | 20/20 | 0 |
| pr-17 | verdict only | 0.0 | 0/20 | 1 |
| pr-18 | every anchor cited | 1.0 | 8/8 | 0 |
| pr-18 | verdict only | 0.0 | 0/8 | 1 |

## Surprises

- **pr-18 skips an id.** Its defect ids run L01 to L09 with no L04, so the count of 8 is correct.
- **Manifest exposure.** My first manifest read printed one full defect entry for each fixture as a format check, and the grader output lists defect ids. The summaries were written from the PR.md title lines only and name no defect. I did not open `labels/`.
- **Temp dirs.** The safety hook blocked `rm -rf "$d"`, so two temp dirs remain under /tmp. They contain only synthetic findings.

No commits; nothing under `.claude/` or the frozen suite touched.
