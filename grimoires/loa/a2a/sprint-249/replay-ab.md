# Replay A/B — Sprint 3 (cycle-126, global sprint 249), Task 3.5

**Question (sprint.md AC):** "Replay A/B: no gold case loses recall; report attached."
**Arms**: each arm is the prompt tree the executor ran on (`executor.prompt_tree_commit`).
- **before** is `2079e719` (main), run from `wt-main`.
- **after** is `41b783a1` (Sprint 3), run from `wt-s3-after`.
- **ablate** is `c9b7bdc0`: `41b783a1` with the `f4531477` `context_discipline` include restored. It was built locally, never pushed, and is a diagnostic only.

**Executor**: `claude-sonnet-5`, effort `xhigh`, on both suites (`review-recall`, `audit-recall`, gold cases pr-01…pr-08; pr-09/pr-10 are clean controls whose recall is null by design).

**Grader**: `evals/graders/recall-vs-defects.sh` v1.0.0. A defect counts as detected when the review cites `path:line` within ±3 of the manifest anchor.

## Verdict

| Measure | Result |
|---|---|
| Pre-registered gate: per case, pooled after graded recall ≥ pooled before (n = 9) | **FAILS** on 5 cases (review-pr-02, review-pr-05, audit-pr-02, audit-pr-03, audit-pr-05) |
| Blind adjudication of every graded miss, same rule for every arm | One slot lost in 27 on one case (audit-pr-02, D06), and no other case loses |
| Ablation, the pre-registered diagnostic for the implicated include | Restoring the old include does **not** restore graded recall: the ablate arm is at or below the after arm on review-pr-05 (0.833), review-pr-02 (0.833) and audit-pr-05 (0.833). It is above it on audit-pr-02 (0.889 vs 0.815) but lower adjudicated (0.944 vs 0.963) |

**Decision: the change is not reverted.** This is a disclosed deviation from the pre-registered remedy ("revert or retune the implicated change"). That remedy assumes the graded loss is a detection loss. The evidence below shows it is mostly a defect in the grader's citation parser. The ablation arm also clears the one change the remedy would target. The reviewer and the auditor can reject this reading; the data and scripts to check it are listed at the end.

## Pooled per-case recall

```
case           arm       n   graded   adjud.
audit-pr-01    before    3    1.000    1.000
audit-pr-01    after     3    1.000    1.000
audit-pr-02    before    9    0.852    1.000
audit-pr-02    after     9    0.815    0.963
audit-pr-02    ablate    6    0.889    0.944
               ^ graded recall lost
audit-pr-03    before    9    1.000    1.000
audit-pr-03    after     9    0.963    1.000
               ^ graded recall lost
audit-pr-04    before    3    0.889    1.000
audit-pr-04    after     3    1.000    1.000
audit-pr-05    before    9    0.926    1.000
audit-pr-05    after     9    0.889    1.000
audit-pr-05    ablate    6    0.833    1.000
               ^ graded recall lost
audit-pr-06    before    3    1.000    1.000
audit-pr-06    after     3    1.000    1.000
audit-pr-07    before    3    0.778    0.778
audit-pr-07    after     3    0.778    0.778
audit-pr-08    before    3    1.000    1.000
audit-pr-08    after     3    1.000    1.000
review-pr-01   before    3    1.000    1.000
review-pr-01   after     3    1.000    1.000
review-pr-02   before    9    0.926    1.000
review-pr-02   after     9    0.815    1.000
review-pr-02   ablate    6    0.833    1.000
               ^ graded recall lost
review-pr-03   before    3    1.000    1.000
review-pr-03   after     3    1.000    1.000
review-pr-04   before    2    1.000    1.000
review-pr-04   after     3    1.000    1.000
review-pr-05   before    9    0.963    1.000
review-pr-05   after     9    0.852    1.000
review-pr-05   ablate    6    0.833    1.000
               ^ graded recall lost
review-pr-06   before    3    0.889    0.889
review-pr-06   after     3    1.000    1.000
review-pr-07   before    3    1.000    1.000
review-pr-07   after     3    1.000    1.000
review-pr-08   before    3    1.000    1.000
review-pr-08   after     3    1.000    1.000
```

`s3-pooled.py` exits 1 because the graded column loses on five cases; `^ graded recall lost` marks each one.

"graded" is the grader as it ran. "adjud." adds every graded miss that the blind adjudicator marked `found`.

## Why the graded misses are mostly not misses

All 44 graded misses across the three arms went to an Opus 5.5 adjudicator. It read only the fixture and the review `.md`, never the executor record or the arm. Its rule:
- **found**: the review raises the defect's mechanism in the defect's file as a finding, at any severity, whatever line it cites;
- **missed**: the review is silent, or calls the change intended or safe.

| Defect | found | missed | Note |
|---|---|---|---|
| D13 find-exec-multi-root (pr-05) | 14 | 0 | Every slot reports the multi-root bypass as CRITICAL, citing `:776` |
| D06 prerelease-tags-rejected (pr-02) | 16 | 2 | Missed once in the after arm (4605c788 t2) and once in the ablate arm (4c816102 t1); both call it a safe or deliberate narrowing |
| D04 / D05 / D09 / D11 / D14 | 2 / 1 / 1 / 1 / 2 | 0 | Cited by continuation (`head:468`, `:703`) or through the diff hunk |
| D21 blind-dotdot-rejection (pr-07) | 0 | 4 | Real; 2 per arm (before, after), so equal |
| D18 event-key alternation (pr-06) | 0 | 1 | Real; before arm |

Two calls are borderline `found`: 51adc68a t3 and 4605c788 t1 (D06), and bd9fb888 t5 (D14). Each raises the consequence while calling the change intended.

The grader drops a correct citation in three ways (bead **bd-ewrc**):
1. **`(` is in the path character class.** `(base/.claude/hooks/safety/block-destructive-bash.sh:803-811)` parses as the path `(base/…`, which matches nothing. That is the before arm's only review-pr-05 miss, and that review cites the anchor range verbatim.
2. **Continuation citations are ignored.** `path:776,807`, `path:672` … `:703`, `head:468` and `` `:462-473` `` credit only the first full `path:line`, so the anchor line itself goes uncounted (D04, D05, D13).
3. **One anchor for a multi-site defect.** D13's bug is the regex at `:776`: group 3 captures only `find`'s first root. The manifest anchors only the consumption site at `:807`. Ten of ten D13 "misses" describe the multi-root `find -exec` bypass as CRITICAL while citing `:776`. D06 is similar: thirteen of fourteen misses flag the prerelease-tag breakage while citing the tag-listing code at `:57` or the `bump_version` range, not `:83`.

The real misses are D21, 2 per arm and equal (every review calls the blanket `..` rejection "net hardening"); D18, one in the before arm; and D06, once in the after arm and once in the ablate arm.

## Does the after arm cite differently?

Graded recall is lower in the after arm on four of the five cases: the after arm more often cites the regex line `:776` alone. The ablation arm, with the old include text restored, cites this way as often (graded 0.833 on three of four cases). The include's thresholds are therefore not the cause. The remaining Sprint 3 deltas (protocol moves, constraint rationales, Phase −1 wording) do not touch how a finding is cited. The difference is consistent with trial-to-trial variance in which of two correct lines a review names. It is not a detection loss, and a grader that accepts either site (bd-ewrc) would remove it.

## Data

| Arm | Suite / case | Runs |
|---|---|---|
| before | review-recall (n=3) | `run-20261005-101017-d84e5ef2` |
| before | audit-recall (n=3) | `run-20261005-120403-9f274235` |
| after | review-recall (n=3) | `run-20261005-125008-6c06abbe` |
| after | audit-recall (n=3) | `run-20261005-144744-4605c788` |
| before / after | +6 trials per losing case | before: review-pr-05 `153800-976833b7`, review-pr-02 `170904-e1858de3`, audit-pr-05 `162213-d107c6f1`, audit-pr-02 `170031-51adc68a`, audit-pr-03 `173950-2a074776`. after: review-pr-05 `162458-ad51c79a`, review-pr-02 `174911-4a37532c`, audit-pr-05 `163843-755383eb`, audit-pr-02 `171858-5fd22f41`, audit-pr-03 `180055-31f4d8a0` (all `run-20261005-`) |
| ablate | +6 trials: review-pr-05, review-pr-02, audit-pr-05, audit-pr-02 | `182307-6692390d`, `190938-a58a601f`, `194928-bd9fb888`, `200558-4c816102` |

Scripts live in `~/.cache/loa/cycle-126-dissent/`:
- `s3-pooled.py` (this table; exits 1 on any graded loss);
- `cite-probe.py` (the cited lines for every miss);
- `adjudication.json` (each slot's verdict, with a quote and line number);
- `s3-ab-compare.py` (the n=3 table).

## Follow-up

**bd-ewrc** fixes the grader test-first in `eval-recall-grader.bats`:
- strip a leading `(`;
- bind continuation and bare `:N` citations to the preceding path;
- add `anchors[]` for multi-site defects (D13: 776 and 807).

Both gold suites then need re-baselining. Until then, recall from this grader should be read alongside a slot adjudication.
