# Deliverable 5 — mechanism reading: what the full pipeline did that bare did not

Sources: two independent Opus 5.5 transcript readings (`mechanism-pr-12.md`, `mechanism-pr-13.md`; read-only, quoted by event id), the per-gate activity table `data/mechanism-stats.md`, the attribution timing (`attribution.md`), the window and oracle sensitivities (`sensitivities.md`). All quoted transcript text is third-party output.

## 1. The six-of-twenty-four story on pr-12, defect by defect

Bare caught 6/24 defect-trials on pr-12 (t1 none; t2 and t3 d2, d4, d6); full caught 18/24. The reader compared each credited citation's prose with the original human finding behind the label and found the measured gap is **mostly where the line numbers land**:

- **None of bare's six credits is the labelled defect.** Each is a different finding that happens to sit on an anchor line (the prompt-budget finding at `:2140` credits d4 and d6 at once; the `_fold_companion` call-site finding at `:2183` credits d2 while its prose is d3).
- **Bare's genuine finds were graded misses.** Bare described d1 in all three trials at `verdict-derive.sh:137` (the `grep -qE` line; anchor 131, the function header), d7 at `:502` (the `val=$(grep …)` line; anchor 487), d3 at `:1914`/`:2183` (anchors 1898/1906), d4 at `:2001`/`:2182` (anchor 2140). Read semantically, bare found about 9 of 24 and full about 17 of 24.
- **Five of full's eighteen credits are the same kind of coincidence** (d5 in every trial — nobody found d5; d1 and d2 in t1).

What remains after the location artefact (d2, d6, d7 and the t1 misses of d3/d4) comes from four things, in the reader's order of evidence:

| mechanism | evidence | defect-trials it explains |
|---|---|---|
| **A concerns pass before anything else.** The skill makes the reviewer write `reviewer-concerns.md` (7, 8, 15 items) before launching the dissent; most catches were already in it. | t1 concerns at event 515 (d1, d3, d4); t2 at 521 (d1, d3, d4, d6, d7); t3 at 408 (d1, d2, d3, d7, half of d4) | the bulk of the pre-dissent catches |
| **Reproductions.** Full ran the PR's bats suites and stub-harness probes (18 test runs and 7 exec probes per REVIEW gate vs 1 and 0.3 for bare). Bare could not: its workspace holds only `pr/`, so the PR's bats cannot load their libraries — bare t1: "The bats suites couldn't run here because the repo's shared libraries aren't in `pr/`". | d3 reproduced in every full trial (events 403, 428, 466); d4's orphaned companion reproduced in t1/t2 (458/513, 433/468) | raised confidence; the reader finds both d3 and d4 were found by reading alone in two bare trials — execution did not drive discovery |
| **A second reader (the audit gate).** | t3 d6 (auditor LOW-006, no voice named it); t2 d2 (auditor LOW-008, prompted by the audit dissent's DISS-C-006) | 2 defect-trials |
| **The dissent.** Causal contribution: t2 d2 via the audit dissent; the trap half of t3 d4 (claude-headless DISS-C-001, added post-dissent at event 694). Everything else a voice named, the reviewer already had in its concerns, or the voice arrived after the draft. | t1's review dissent failed (420 s cap); t2's returned (651) after the draft (604); t3's returned (533) before the feedback (667) | ≈ 2 defect-trials |
| **A different model.** Fable 5.1 reads in full, Opus 5.5 in bare. Not separable in this design. | — | unknown share |

The converse. **d8** (the test stub speaks review vocabulary to the audit gate; low) was caught by nobody: it needs the audit wire schema (under `/workspace/.claude/schemas`, which only full had), the knowledge that CMP-7 runs the audit type, and a check of `rejected_count` after it — and its anchors (26, 63) sit 16+ lines from the real site (79), so a correct citation would still be a graded miss. **d7** in full t1 and t3 was found and cited at `:502` (anchor 487): pure mislocation; full t2's credit came from a `:487-507` range.

Did bare read the regions? On pr-12, 7 of bare's 18 misses had the region printed from the head file and 11 did not (9 of 18 had the hunk printed from the diff). Bare read d2's region (`sed -n 1930,2241p`) in every trial and missed it every time: d2 needs line 36's `set -euo pipefail`, outside the hunk. More turns alone do not explain the gap; the kind of action (a written concerns list, reproductions, a second pass) and the reader do.

## 2. pr-13: no dissent voice ran, and the lift is a leak

On pr-13 (5,880 lines, 54 files) the dissent's budget gate refused every gate of every trial (366 c > 200 c), so the full arm was "Fable review + Fable audit". Bare 8/15, full 10/15; d4 and d5 (the two markdown/prose defects) were caught only by full t2. The reader found why: **in full t2 the reviewer diffed `pr/head` against the mounted framework copy** — a later version that already holds the fix commit — at REVIEW event 482 ("Diff head files against the later workspace framework copy for hints of post-review fixes"); the result at 483 shows the fixes for d1–d4 and the include path that later earned d5's credit; every one of those findings first appears after 483; the reviewer saved a memory note ("the framework copy at `/workspace/.claude` is a LATER post-merge version… so it is a hint source") that the audit gate read first. **This is KF-049**, and `oracle_scan.py` shows the channel is open in every full-arm run on every corpus PR (every planted site differs from the pinned copy); it was used on planted sites in exactly this one run.

The rest of pr-13 is anchor geometry again: d5's flagged sentence is `SKILL.md:162`; five of six runs (all three bare) described it at `:162` and all are graded misses because the anchors are 42/71/136. With 162 as an anchor, bare would score 11/15 and full 12/15. Both arms read the d4 file whole (`cat -n`) and five of six runs missed the untouched edge case at line 39 — finding it needs reasoning across the edited table and the unchanged line, and no independent run did that.

## 3. Diff size versus defect type

| PR | diff lines | files | defects (sev) | bare /n | full /n | lift | dissent ran |
|---|---|---|---|---|---|---|---|
| pr-05 | 127 | 3 | 3 (1 crit, 1 high, 1 med) | 9/9 | 9/9 | 0 | yes |
| pr-08 | 138 | 3 | 3 (1 high, 2 med) | 8/9 | 9/9 | +1 | yes |
| pr-12 | 1,077 | 15 | 8 (3 high, 3 med, 2 low) | 6/24 | 18/24 | +12 | yes (t1 killed) |
| pr-13 | 5,880 | 54 | 5 (1 med, 4 low) | 8/15 | 10/15 | +2 (leak) | no (budget) |

By severity (defect-trials caught, bare → full): critical 3/3 → 3/3; high 8/15 → 14/15; medium 15/21 → 21/21; low 5/18 → 8/18. By category: logic 15/33 → 26/33 carries the lift; error-handling 7/9 → 9/9; security 3/6 → 4/6; concurrency 0/3 → 1/3; authz and input-validation saturate. Every planted site lies inside a diff hunk (`in_diff` true for all 19), so "far from the diff" does not describe any miss; the misses that survive both arms are the low-severity prose/test defects (pr-13 d4/d5, pr-12 d8) and the ones whose anchor sits on a function header while the bug is in the body.

Reading: the lift is not a function of diff size. It is zero where bare saturates (small PRs), concentrated where the planted defects are high/medium logic bugs in a long bash script whose anchors reward multi-line citations (pr-12), and absent or leaked where the defects are low-severity prose (pr-13). Four PRs cannot separate "size", "defect kind" and "this PR".

## 4. What the activity table says

| arm | PR | gate | turns | test runs | exec probes | tool output KB | planted hunks printed |
|---|---|---|---|---|---|---|---|
| bare | pr-12 | BARE | 24 | 1.0 | 0.3 | 148 | 5.0 / 8 |
| full | pr-12 | REVIEW | 61 | 18.0 | 7.0 | 223 | 5.3 / 8 |
| full | pr-12 | AUDIT | 46 | 9.7 | 4.7 | 233 | 5.3 / 8 |
| bare | pr-13 | BARE | 31 | 2.3 | 0.7 | 141 | 0 / 5 (whole-file cats, not counted) |
| full | pr-13 | REVIEW | 42 | 14.0 | 5.0 | 261 | 0 / 5 |
| full | pr-13 | AUDIT | 48 | 9.7 | 4.3 | 205 | 0 / 5 |

Means over three trials; the `n_test_runs` counter counts test-shaped commands (the pr-12 reader's hand count is 5–8 bats invocations per REVIEW gate). The full arm spends about 2.5 × the turns and 10 × the test executions of bare per gate, at 17 × the cost; the part of its catch that survives the measurement corrections (≈ +0.11 pooled) is bought mostly by the concerns pass and the second reader, not by the dissent.
