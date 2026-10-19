# Sensitivities of the shipped H1 read (decide nothing; measurement-rule checks)

Source: `data/runs.json`, `scripts/window_sensitivity.py`, `scripts/oracle_scan.py`, the inline recomputation in the lead's session (seed 20261015, 10,000 resamples, 90 %). The shipped read: a1_full − a0_bare on `defect_catch_rate` **+0.263 [+0.158, +0.386]** over 19 defects (DEC-0597). The lead's independent recomputation gives the same point estimate and upper bound; the lower bound sits on a discreteness jump of the 19-unit bootstrap (+0.140 or +0.158 depending on the percentile convention — one defect-trial).

## 1. The citation window (grader rule: a citation within ±3 lines of a manifest anchor)

Same citations, same arms, wider windows. Bare writes one `head/<path>:<line>` per finding (the output contract); the full arm's feedback files carry `**File:**` ranges and several `:N` continuations per finding.

| window | bare caught /57 | full caught /57 | pooled Δ | task-mean bare | task-mean full | task-mean Δ |
|---|---|---|---|---|---|---|
| ±3 (shipped) | 31 | 46 | +0.263 | 0.668 | 0.854 | +0.186 |
| ±6 | 37 | 49 | +0.211 | 0.737 | 0.892 | +0.155 |
| ±10 | 41 | 50 | +0.158 | 0.796 | 0.902 | +0.106 |
| ±20 | 47 | 51 | +0.070 | 0.871 | 0.912 | +0.042 |
| ±3 or any cited line inside the anchor's enclosing function | 42 | 50 | +0.140 | 0.806 | 0.902 | +0.096 |

Per task at "±3 or same function": review-01 9/9 vs 9/9; review-02 9/9 vs 9/9; review-03 15/24 vs 21/24; review-04 9/15 vs 11/15.

Reading: about half of the shipped gap is where the line numbers land. Widening also credits unrelated findings (a wider window is not "truer"), so the same-function row is the defensible middle: the lift is about +0.14 pooled (+0.10 task-mean) rather than +0.26. The transcript reading (`mechanism-pr-12.md` §(e)) lists the concrete mislocated catches: bare described d1 at `verdict-derive.sh:137` (anchor 131) in all three trials, d7 at `:502` (anchor 487), d3 at `:1914`/`:2183` (anchors 1898/1906), d4 at `:2001`/`:2182` (anchor 2140); and the converse — six bare credits and five full credits whose prose is a different finding that happens to sit on an anchor line.

## 2. The mounted-framework oracle (KF-049)

Every a1_full sandbox mounts the pinned Loa tree (`ba11b860`) at `/workspace/.claude`, `tools/`, `tests/`. For every record PR of the corpus the fix commit is an ancestor of the pin, and for the synthetic PRs the mounted copy is the un-regressed code: **at every planted site of pr-05/08/12/13/16/17/18 the mounted copy differs from `pr/head`** (`oracle_scan.py` static check). The bare arm mounts nothing. Use, by the precise detector (a content `diff`/`comm`/`sdiff` with one `pr/` operand and one workspace operand; `cmp -s`, `md5sum`, `diff -q` do not count):

| run | gate | event | what | planted sites in the printed diff | cited after |
|---|---|---|---|---|---|
| review-04 t2 | REVIEW | 482 → 483 | `diff $H/.claude/hooks/session-start/loa-context-class.sh .claude/hooks/…` "head vs later workspace" (+ the protocol, include and stubs) | d1, d2, d3, d4 | all four; d5's credit came from the audit restating a leak-derived finding (`mechanism-pr-13.md` §(c)) |
| review-04 t2 | REVIEW | 311 | reference stubs vs workspace | none | — |
| all other 22 gates | — | — | parity checks only (`cmp -s`, `md5sum`, `diff -q`), or reads of the workspace copy's docs/usage text | none | — |

H1 with the tainted cell handled:

| reading | defect-level Δ [90 %] | task means 01 / 02 / 03 / 04 |
|---|---|---|
| as shipped | +0.263 [+0.158, +0.386] | 0.000 / +0.111 / +0.500 / +0.133 |
| review-04 t2 excluded pairwise (a1 excluded share 1/12) | +0.228 [+0.105, +0.351] | 0.000 / +0.111 / +0.500 / 0.000 |
| review-04 t2's catches set to zero | +0.175 [+0.035, +0.316] | 0.000 / +0.111 / +0.500 / −0.200 |

Reading: the oracle was used once in twelve runs, and that one use is the whole of pr-13's lift. The exposure, however, is structural and one-sided (only the full arm has it), so every review-catch lift measured under this harness is an upper bound until the mount is pinned to the PR's base or the PR-touched paths are removed from it.

## 3. Both corrections together (indicative)

Same-function window AND review-04 t2 excluded: review-03 remains the only PR with a lift (15/24 vs 21/24 under the same-function rule → +0.25 on that PR); review-01/02 saturate; review-04 reads 9/10 vs 9/10 on the remaining two trials. Pooled over the 52 remaining defect-trials: bare 42 − (review-04 t2's 3) = 39, full 50 − 5 = 45 → +0.115. This is the figure the ELI5 should carry as "what is left after the measurement artefacts": roughly a tenth of the defects, all of it on the one 1,077-line PR.
