# Deliverable 6 — out-of-sample replication on pr-17 and pr-18 (batch `replication-01`)

## Design (pre-registered before any row)

- NOTES § "Pre-registration — cycle-130 follow-on, out-of-sample replication batch replication-01 — 2026-10-19T02:49:20Z" (DEC-0602) and the addendum "replication-01 driver" (DEC-0603).
- Suite root `grimoires/loa/evals/ablation-2.0-replication/` — `review-r17` (pr-17: 20 labelled defects, 2 high / 5 medium / 13 low; 4,437-line diff over 41 files) and `review-r18` (pr-18: 8 defects, 1 high / 2 medium / 5 low; 2,194 lines over 29 files). Authored by an Opus 5.5 session from the `review-03` template (`replication-authoring.md`), fairness-reviewed PASS by a second Opus session that did not author them (`tasks/*/REVIEW.md`), frozen (`MANIFEST.sha256` sha256 `cffc7079…`, 6 files), self-checked base / reference / noisy 6/6 PASS inside `loa-ablation:258` (`self-check-replication.log`, grader 1.2.13).
- Arms and pin unchanged from the shipped batches: `a0_bare` (Opus 5.5, tools only) and `a1_full` (Fable 5.1 review gate + two-voice dissent, Fable audit gate + dissent) at `ba11b860`, image `loa-ablation:258`, 3 trials per cell, review-catch cap USD 20, concurrency 3, seed 20261015; `--max-usd 248.00` (= 1,500 − 1,192.00 spent − 3 × 20); rows to `evals/results/ablation-2.0/runs.jsonl`, never pooled with the shipped read.
- Read: the same H1 wording on `defect_catch_rate`, 90 % paired bootstrap over the 28 defects, pairwise exclusion of degraded/contaminated/interrupted rows, the 25 % guard, the degenerate check. **Replication-only: decides nothing about defaults.** Reported beside it, deciding nothing: per-PR split, 2-cluster bootstrap, precision and false positives, cost and wall-clock, and the **oracle scan** (KF-049) per a1 row with the read repeated with oracle-exposed cells excluded pairwise.
- Pre-declared expectations: the dissent budget gate (200 c) is expected to refuse on pr-17 (218 KB diff; pr-13's 239 KB estimated 366 c) and is uncertain on pr-18 (125 KB); such rows are the pipeline as configured. Every pr-17/pr-18 planted site differs between `pr/head` and the mounted `ba11b860` copy (`oracle_scan.py` static check), so the oracle channel is open for every a1 run.
- Driver deviation (DEC-0603): the tracked runner's freeze check and grader call have no `--allow-partial` passthrough, so a two-task root cannot pass its hard gate; the batch runs under an out-of-repo copy that adds the flag to those two calls and pins `SCRIPT_DIR` to the repo harness (`replication-driver-diff.md`; copy kept at `scripts/run-ablation-partial.sh.copy`). Every collaborator script is the unmodified tracked one; no arm, cap, grader rule or row field changes.

## Run

- Launched 2026-10-19T02:53:37Z detached (pid 15428); dry run before it: 12 trials, est. USD 96 under the 248 cap; codex pre-flight: token valid to 2026-10-28T04:44:32Z, required until 2026-10-19T20:13:38Z.

- Completed 2026-10-19T04:28:04Z: 12 of 12 trials rowed, no cap failure, no retry, no drift, no outage; batch spend **USD 88.81** (a0 USD 1.43 and 5.6 min per run; a1 USD 13.37 and 34.3 min). Cycle spend after the batch: USD 1,280.81 (`spend.sh` 1,246.23 over every rows file + the P1 first-attempt ledger 21.70 + the p1b interrupted-phase ledger 12.88); headroom 219.19. The task's own spend: USD 88.81 of the 300 allowed.
- **Dissent voices:** the budget gate refused the review-gate dissent on every one of the six a1 runs (pr-17 and pr-18 both estimate above 200 c: 214 c on pr-18) and the audit-gate dissent on four; two audit gates (review-r17 t1, t2) ran both voices (`voices_succeeded` 2 — the KF-048 credential check passes). So the full arm on these PRs is **Fable review + Fable audit, with no dissent at the review gate**, as pre-declared possible.
- **Contamination (KF-046, recurrence 9):** two a1 rows (`review-r18-t2` REVIEW:320, `review-r18-t3` AUDIT:332) read `contaminated` because the grader's `repo_name` scan fired on the reviewer's heredoc quoting the PR's own CI clause `github.repository == '0xHoneyJar/loa'` (present in `pr/head/.github/workflows/check-glossary-terms.yml` and in `head.diff`). Read by hand: the PR's content, not a reach. No grader change in this task, so the rows stay excluded under the pre-registered rule and are included in a labelled sensitivity.

## Rows

| cell | bare caught | bare USD | full caught | full USD | full row | oracle use (KF-049) |
|---|---|---|---|---|---|---|
| review-r17 t1 | 3/20 | 1.32 | **15/20** | 17.02 | completed | REVIEW events 314/316/365: `diff pr/head/.claude/scripts/chart-ticket.sh .claude/scripts/chart-ticket.sh` ("head -> later") and the same for `chart-unblock-probe.sh`; **9 planted sites in the printed diffs, all 9 cited afterwards, 7 of them missed by bare** |
| review-r17 t2 | 5/20 | 2.16 | **17/20** | 17.47 | completed | none (parity checks only) |
| review-r17 t3 | 5/20 | 1.54 | **13/20** | 14.73 | completed | none |
| review-r18 t1 | 0/8 | 1.17 | 4/8 | 10.65 | completed | REVIEW event 226: `diff -u pr/head/.claude/scripts/validate-artifact.sh .claude/scripts/validate-artifact.sh`; 1 planted site exposed and cited afterwards (bare missed it) |
| review-r18 t2 | 4/8 | 1.14 | 4/8 | 10.66 | contaminated (repo_name) | none on planted sites (AUDIT event 108 diffed `red-test-check.sh` against the later copy "later fixes hint": no planted site in the hunks) |
| review-r18 t3 | 3/8 | 1.28 | 5/8 | 9.67 | contaminated (repo_name) | none |

Every row's catch/missed/flags/false-positive counts were re-derived from the run directories with the grader's rule and match `grade.json` (cross-check true on all 12).

## Reads (28 defects; defect-level paired bootstrap, 10,000 resamples, 90 %)

| reading | cells | a1_full − a0_bare | interval | per PR (bare vs full, defect-trials) |
|---|---|---|---|---|
| **Pre-registered** (contaminated rows excluded pairwise) | r17 t1–t3, r18 t1 | +0.524 | [+0.393, +0.643] | r17 13/60 vs 45/60; r18 0/8 vs 4/8 |
| → the 25 % guard | a1 excluded share 2/6 = **0.333 > 0.25** | **inconclusive by degradation** under the rule as written | | |
| Sensitivity: contaminated rows hand-read as scan false positives and included | all 6 | **+0.452** | **[+0.310, +0.595]** | r17 13/60 vs 45/60; r18 7/24 vs 13/24 |
| Oracle-exposed cells excluded (r17 t1, r18 t1) | 4 | +0.393 | [+0.214, +0.571] | r17 10/40 vs 30/40; r18 7/16 vs 9/16 |
| Oracle-exposed-and-cited-after defect-trials set to not caught | all 6 | +0.333 | [+0.190, +0.476] | r17 13/60 vs 36/60; r18 7/24 vs 12/24 |
| Same-function window (±3 or any cited line in the anchor's function), all 6 | all 6 | +0.321 | — | bare 33/84 vs full 60/84 |
| Original (pr-05/08/12/13) for comparison | 12 | +0.263 | [+0.158, +0.386] | |

2-cluster bootstrap (two PRs): the sensitivity read's interval is [+0.25, +0.53]; stated, not leaned on. Precision: a0 0.180 (20 planted of 111 flagged), a1 0.113 (58 of 514) — the same shape as the original (0.199 / 0.107).

## Reading

The lift **reappears on PRs nobody looked at**, and it is larger than the original: on pr-17 (20 mostly low-severity defects in a 4,437-line diff) bare catches about a fifth and the pipeline about three quarters; on pr-18 bare 0–4 of 8 and the pipeline 4–5 of 8. The two corrections this analysis introduced do not remove it: with every catch that followed a head-versus-later-copy diff set to zero it is still +0.33 [+0.19, +0.48], and under the same-function window +0.32. The formal verdict under the pre-registered rule is nevertheless **inconclusive by degradation** — a scanner false positive on the PR's own repository name, not an arm effect — and the honest statement is: the direction and size are robust across every reading; the pre-registered gate was tripped by the measurement apparatus.

Two caveats carry more weight than the gate. First, the dissent never ran at a review gate here, so the replication compares "Fable 5.1 reading twice with the skill's checklist" against "Opus 5.5 reading once": the model difference is confounded with the pipeline and is the largest unexplained term in both the original and the replication. Second, the oracle (KF-049) was used in two of six fresh runs — one of them drew nine of its fifteen catches from the printed fix diff — which confirms the exposure is live and habit-forming, not a one-off, and must be closed before the next review-catch batch.

