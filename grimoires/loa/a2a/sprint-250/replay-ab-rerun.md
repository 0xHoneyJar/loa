# Task 4.8 (bd-ewrc) — Sprint 3 replay A/B re-run on grader 1.1.0

Pre-registration: `replay-ab-rerun-prereg.md`, fixed 2026-10-05T23:25Z, before any trial.

## Setup
- **Arms.** before = `main` 2079e719 (wt-main); after = 2fcd4af8 (wt-s4-after). Both prompt trees ran under the harness, grader 1.1.0 and manifests from the real tree at `e612fa2d`, so the harness is byte-identical for both arms.
- **Trials.** n = 9 per case per arm, `--trusted --concurrency 2`.
- **Runs.** Each run's `executor.prompt_tree_commit` was verified. Scripts are in `~/.cache/loa/cycle-126-dissent/launch-s4-ab-{before,after}.sh`.

| Case | Before run | After run |
|---|---|---|
| review-pr-05 | run-20261005-232645-e1ca2433 | run-20261005-232645-c9a2335d |
| review-pr-02 | run-20261006-003513-e29ad6d2 | run-20261006-003626-57be16f1 |
| audit-pr-02 | run-20261006-013530-73147c29 | run-20261006-013802-a663f872 |
| audit-pr-05 | run-20261006-020428-2e929277 | run-20261006-021143-d61074ea |
| audit-pr-03 | run-20261006-023113-668f1469 | run-20261006-024317-bc607195 |

## Results

| Case | Before, grader | After, grader | After, adjudicated | Gate (≥ before − 1, both measures) |
|---|---|---|---|---|
| review-pr-02 | 27/27 | 27/27 | 27/27 | pass |
| review-pr-05 | 27/27 | 27/27 | 27/27 | pass |
| audit-pr-03 | 27/27 | 27/27 | 27/27 | pass |
| audit-pr-02 | 27/27 | 25/27 | 26/27 | **fail** on the grader measure (−2); pass adjudicated (−1) |
| audit-pr-05 | 27/27 | 24/27 | 27/27 | **fail** on the grader measure (−3); pass adjudicated (0) |

The before arm has no grader-missed slots, so it had nothing to adjudicate and its adjudicated score equals its grader score.

### Blind adjudication of the five after-arm misses
An Opus 5.5 adjudicator saw only the fixture and the review `.md`, with arm and run id hidden. The packet and key are in `s4-blind/`, seed 20261006, and the key was not shown to the adjudicator.

| Key | Case / trial | Defect | Verdict | Borderline |
|---|---|---|---|---|
| S001 | audit-pr-05 t5 | D14-billing-400-terminal | FOUND (MEDIUM finding) | no |
| S002 | audit-pr-02 t3 | D06-prerelease-tags-rejected | MISSED (dropping prerelease parsing called "safe") | no |
| S003 | audit-pr-05 t1 | D14 | FOUND (MEDIUM finding) | no |
| S004 | audit-pr-02 t1 | D06 | FOUND (LOW-002) | no |
| S005 | audit-pr-05 t4 | D14 | FOUND (flagged observation, not tallied) | **yes** |

### Why the grader missed slots the adjudicator found
This is not a parser defect. The after-arm audits cite the wrong lines:
- **D14.** The anchor is `anthropic_adapter.py:140`; the other raise site is :223. All three D14 audits cite `head/…anthropic_adapter.py:87-90` / `:88` / `:102`, which is header construction and the streaming dispatch.
- **D06.** S004 cites `semver-bump.sh:161-166` / `:174-215`; the anchors are 57 and 83. This is the same class as the Sprint 3 before-arm D06 slots that the pre-registration left unanchored.

The defect is understood semantically, but the location is wrong. Manifest anchors were not widened, because that would fit the manifest to the results.

## Decision (pre-registered rule applied)
- **The gate fails.** audit-pr-02 and audit-pr-05 each lose more than 1 slot on the grader measure. The D06 trigger (≥ 2 after-arm misses where before found it) is also met on the grader measure.
- **Per the rule, ablate** the CLAUDE.loa.md trim and the constraints rationale rewrite separately:
  - **abl-why** = `67b7857c`: 2fcd4af8 with the constraints.json `why` fields reverted to 2079e719, then regenerated.
  - **abl-trim** = `1f66d420`: 2fcd4af8 with the CLAUDE.loa.md Reference Files table, truenames table and NOTES clause reverted.
  - Both are local only, never pushed.
- **Ablation runs.** Cases audit-pr-02 and audit-pr-05, n = 9 each, launched 2026-10-06T03:23Z. The harness is at `98d8a486`, which differs from `e612fa2d` only in `flatline-readiness.sh` and `model-residue.bats`; the grader, manifests and harness scripts are byte-identical.
- **Reading rule.** The implicated change is the arm that restores before-level grader recall (≥ 26/27 on audit-pr-02 and on audit-pr-05). That change is reverted test-first, and the affected cases are then re-run.
  - If both arms restore it, both changes are reverted.
  - If neither does, neither ablated change is implicated. The remaining Sprint 3 differences then go to the review and audit, with the evidence below. These are the auditing-security skill's parallelism-gate removal (41b783a1) and the include and context-class text.
- **The AC stays "Waived"** until the gate passes.

## Ablation results (grader 1.1.0, n = 9)

| Arm | Prompt tree | audit-pr-02 | audit-pr-05 | Runs |
|---|---|---|---|---|
| before | 2079e719 | 27 | 27 | (above) |
| after | 2fcd4af8 | 25 | 24 | (above) |
| abl-why (rationales reverted) | 67b7857c | 27 | 26 (D15 ×1) | run-20261006-032341-e6115c30, run-20261006-035626-5ed5f857 |
| abl-trim (CLAUDE.loa.md trim reverted) | 1f66d420 | 26 (D06 ×1) | 26 (D14 ×1) | run-20261006-032341-6d28d887, run-20261006-035540-a0f170f3 |

- **Both arms restore before-level grader recall** (≥ 26/27 on both cases). Per the reading rule written before these results, **both changes are reverted**.
- **Caveat, disclosed.** The effect is small against n = 9. The after arm has 5 missed slots in 54 and the before arm 0 in 54, which gives Fisher exact p ≈ 0.06. On the adjudicated measure the after arm loses 1 slot. "Both ablations restore" is also what a noisy after-arm draw would produce. The rule was pre-registered to settle exactly this, so it was applied as written and not argued down after the fact.
- **Where the effect shows.** Every after-arm loss is a citation-location miss; the content was not lost. In the before arm all nine D14 audits cite the head raise site (`:139-141`). In the after arm, t1, t4 and t5 cite only base lines (41-71) or the streaming dispatch.

## Revert (`bf988a43`)
- `CLAUDE.loa.md` is byte-identical to `main` again (10,225 B): the Reference Files table, the truenames table and the NOTES clause are back.
- The twelve `why` fields carry their 2079e719 text, and the golden NEVER/ALWAYS tables are re-rendered.
- `tools/check-prompt-budget.sh` sets `CLAUDE.loa.md` ≤ 10,240 B again. This gives up the Sprint 3 AC "CLAUDE.loa.md ≤ 9,216 B", in favour of the recall gate, and is disclosed for the review and audit.
- Unchanged: the protocol diet (131,189 B ≤ 160,000), the context class and the skills' parallelism sentence.
- **Tests.** `instruction-diet-revert.bats` IDR-1–3 and `prompt-budget.bats` PB-4/PB-6 were red first. IDR-4 checks the rendered rows against `constraints.json`. The Sprint 3 suite list is green (test-constraints 17/17).

## Post-revert re-run (affected cases, n = 9, prompt tree bf988a43)
Launched 2026-10-06T04:31Z (`launch-s4-final.sh`). Both the harness and the prompt tree are at bf988a43.

| Case | Before | Post-revert, grader | Run | Gate |
|---|---|---|---|---|
| audit-pr-02 | 27 | 27/27 | run-20261006-043137-a04495fc | pass |
| audit-pr-05 | 27 | 26/27 (D14 ×1, t9) | run-20261006-050413-d9c28c33 | pass |

- **The gate passes on both measures.** On every grader-missed slot, adjudication can only match or raise the grader's count. The single miss therefore needed no adjudication for the gate, though it may still be adjudicated for the record.
- The three cases that held in the re-run (review-pr-02/05, audit-pr-03) passed with the reverted changes still present. Reverting them restores the base text, so those cases were not re-run.
- **Sprint 3 AC "no gold case loses recall": met after the revert.** It moves from "Waived" to met, with the CLAUDE.loa.md budget AC given up as recorded above.

## Re-score on the review-round grader (sprint-250 review dissent run 2, n12)
Review rounds r250-1 (`17291942`) and r250-3 (`64c2eb09`) changed the citation parser that measures this gate. Grader 1.1.1 was revised in r250-3 without a version bump, since it is unreleased within this cycle. To check whether the gate result depended on the old parser, all 16 stored runs above were re-scored offline, from their stored outputs, under 1.1.0 and under the final grader. No model calls were made.

| Arm | Case | Run | 1.1.0 | final | Δ | Citations 1.1.0 → final |
|---|---|---|---|---|---|---|
| before | review-pr-05 | run-20261005-232645-e1ca2433 | 27/27 | 27/27 | 0 | 260→215 |
| after | review-pr-05 | run-20261005-232645-c9a2335d | 27/27 | 27/27 | 0 | 237→192 |
| before | review-pr-02 | run-20261006-003513-e29ad6d2 | 27/27 | 27/27 | 0 | 305→260 |
| after | review-pr-02 | run-20261006-003626-57be16f1 | 27/27 | 27/27 | 0 | 262→217 |
| before | audit-pr-02 | run-20261006-013530-73147c29 | 27/27 | 27/27 | 0 | 225→185 |
| after | audit-pr-02 | run-20261006-013802-a663f872 | 25/27 | 25/27 | 0 | 214→178 |
| before | audit-pr-05 | run-20261006-020428-2e929277 | 27/27 | 27/27 | 0 | 189→153 |
| after | audit-pr-05 | run-20261006-021143-d61074ea | 24/27 | 24/27 | 0 | 219→183 |
| before | audit-pr-03 | run-20261006-023113-668f1469 | 27/27 | 27/27 | 0 | 290→252 |
| after | audit-pr-03 | run-20261006-024317-bc607195 | 27/27 | 27/27 | 0 | 280→244 |
| abl-why | audit-pr-02 | run-20261006-032341-e6115c30 | 27/27 | 27/27 | 0 | 224→188 |
| abl-why | audit-pr-05 | run-20261006-035626-5ed5f857 | 26/27 | 26/27 | 0 | 220→181 |
| abl-trim | audit-pr-02 | run-20261006-032341-6d28d887 | 26/27 | 26/27 | 0 | 236→200 |
| abl-trim | audit-pr-05 | run-20261006-035540-a0f170f3 | 26/27 | 26/27 | 0 | 203→167 |
| post-revert | audit-pr-02 | run-20261006-043137-a04495fc | 27/27 | 27/27 | 0 | 230→194 |
| post-revert | audit-pr-05 | run-20261006-050413-d9c28c33 | 26/27 | 26/27 | 0 | 173→137 |

- **Detections.** Detection is identical on every trial of all 16 runs. The fall in citation count comes from spurious citations that are no longer counted: trailer and JSON numbers, dates, and URLs. No defect slot changed.
- **The gate decision, the ablation reading and the post-revert pass are unchanged.**
- **Round 4 (`27ff5a4b`, grader 1.1.2).** The URL look-back is now linear and no longer crosses a line break. All 16 runs re-score identically to the `64c2eb09` grader on both detections and citation counts. The final grader is therefore 1.1.2, and every figure in the table above holds for it.
- **Round 1 vs round 3.** The r250-1 grader and the final grader give identical citation counts on all 16 runs. Two over-strict guards in round 3's first draft were caught by this comparison before commit and are now pinned: `` (`:212`) `` in RG-23 and `:369-...` in RG-22.
