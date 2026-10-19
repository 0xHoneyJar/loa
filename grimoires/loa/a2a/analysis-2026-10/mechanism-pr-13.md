# Mechanism read: pr-13 (review-04), bare vs full

Reader: Opus 5.5 subagent, 2026-10-19. Read-only over the six run directories under
`grimoires/loa/reports/ablation-2.0/batches/priority-v2-p1/{a0_bare,a1_full}/review-04-t{1,2,3}/`.
Event ids are 1-based line numbers in the named transcript. All quoted text is third-party data.

## (a) Answer

The full arm's +2 on pr-13 comes from an answer-key leak in one trial, not from the pipeline.
The a1 sandbox's `/workspace/.claude` is a later framework copy that already contains the fix commit's edits.
In full t2 the review lead diffed `pr/head` against that copy (REVIEW event 482: "Diff head files against the later workspace framework copy for hints of post-review fixes").
The result at event 483 showed the fixes for d1, d2, d3 and d4, plus the include path that later earned d5 credit. Each of those findings first appears after event 483. "Bedrock" is in neither `PR.md` nor `head.diff`.
The d5 credit is a grader coincidence. The audit restated an include-path finding as `SKILL.md:132-138`, which overlaps anchor 136.
The real d5 issue was described by five of six runs, all three bare runs included. All five cited `SKILL.md:162`, outside every anchor.
All six runs read the d4 file whole and saw the d5 hunk, so coverage was not the difference. The bare runs' d1–d3 credit is mostly proximity from fail-open findings at `:80` and `:89`.

## (b) Per-defect × run table

Codes:

- **SEM**: a semantic catch at the anchor, made independently.
- **LEAK**: a catch that follows the later-copy fix diff.
- **PROX**: credited by a different finding that sits within ±3 of an anchor.
- **LOC**: the defect is described, but the citation falls outside ±3.
- **READ-MISS**: the region was in a tool result, but no finding names the defect.
- **INH**: the audit restated a review finding.

| def | run | graded | first-citing gate (event) | region in a tool result (event) | code | note |
|---|---|---|---|---|---|---|
| d1 | bare t1 | miss | none | yes (9, 49) | READ-MISS | cites `:80`, `:98` only |
| d1 | bare t2 | hit | BARE (182) | yes (11) | PROX | `:89` fail-open-to-long finding |
| d1 | bare t3 | hit | BARE (153) | yes (15) | PROX | `:89` fail-open finding |
| d1 | full t1 | miss | ungraded audit work file (396) | yes (R48, A66) | READ-MISS | audit judged it "SAFE — exact-match on two literals" |
| d1 | full t2 | hit | REVIEW (633) | yes | LEAK | `:90` case-sensitive `Standard`, after 483 |
| d1 | full t3 | hit | REVIEW (432) | yes | SEM | `:90` "only the exact lowercase values… are honoured"; no later-copy diff |
| d2 | bare t1/t2/t3 | hit | BARE (191/182/153) | yes | PROX, partly SEM | "unknown or unprefixed model id" (t1), "undated `claude-sonnet-4-5`" (t3) |
| d2 | full t1 | hit | REVIEW (532) | yes | PROX | positive remarks at `:75` and `:86` |
| d2 | full t2 | hit | REVIEW (633) | yes | LEAK | `:81` HIGH, Bedrock ids; first "Bedrock" at 483, tested at 523 |
| d2 | full t3 | hit | REVIEW (432) | yes | SEM (partial) | `:81` short model id |
| d3 | bare t1/t2/t3 | hit | BARE | yes | PROX | no alias-injection finding in any bare run |
| d3 | full t1, t3 | hit | REVIEW (532, 432) | yes | PROX | `:75`/`:86`; `:81-86` |
| d3 | full t2 | hit | REVIEW (633) | yes | LEAK | `:82` "alias target … spliced into the second yq expression"; the fix comment at 483 says the same |
| d4 | bare t1/t2/t3 | miss | none | yes (9 / 13 / 63, whole-file `cat -n`) | READ-MISS | same file cited at `:51`, `:13`, `:8` for other issues |
| d4 | full t1, t3 | miss | none | yes (R142, A74 / R36, A36) | READ-MISS | |
| d4 | full t2 | hit | REVIEW (concerns 532 without a line; graded 633) | yes (R276) | LEAK, then INH (A415) | |
| d5 | bare t1/t2/t3 | miss | none | yes (`parallel_threshold` grep 74 / 106 / 86) | LOC | all at `SKILL.md:162` |
| d5 | full t1 | miss | none | yes (R263) | READ-MISS | no parallelism finding |
| d5 | full t2 | hit | AUDIT (415) | yes (A29, A378) | PROX via INH of a LEAK finding | LOW-013 `:132-138`; real finding LOW-015 at `:162` is LOC |
| d5 | full t3 | miss | none | yes (R309) | LOC | `:162` in review.md, engineer-feedback and audit LOW-006 |

The pointers' `region_read_event` misses whole-file `cat -n` reads, so it cannot show "never read".

## (c) Narrative

**Both arms read the same way.** Each run listed the diff's files first. Bare t1 did this at event 5 and bare t3 at event 12. Each then read the new hook, its bats file and the threshold protocol whole. Bare t1 did this at event 8:
```
cat -n .claude/protocols/tool-result-clearing.md; cat -n .claude/hooks/session-start/loa-context-class.sh
```
Each then diffed the moved protocols and paged the rest. Bare t1 paged a copy of the diff without the five new `reference/` files (events 40–81). Bare t3 paged `head.diff` directly (events 24–36). Bare t2 ran per-file `diff -u` loops (events 19–98).
Full t2's review was the only run to fan out, with two Explore subagents (events 180, 197). Every run grepped `parallel_threshold`.

**The leak in full t2.** The copy at `/workspace/.claude` is newer than the PR in all three full trials. Full t1 noticed it at event 80, where its parity check printed `DIFFERS .claude/protocols/tool-result-clearing.md`. Full t1 never diffed the two.
In t2, subagent A ran "Show how workspace copy drifts from PR head" (event 311). Subagent B reported the following at event 484:
> "The live repo at `/workspace/.claude/protocols/session-continuity.md:9` already corrects this… confirming it was a real mismatch."

Then the lead reasoned at event 481:
> "The /workspace framework copy is a later post-merge version, so I'll use it only as a reference while diffing against the head files."

At event 482 the lead ran `diff $H/.claude/hooks/session-start/loa-context-class.sh .claude/hooks/session-start/loa-context-class.sh` and the same diff for the protocol, the include and the stubs. The result at event 483 contained these hunks:
```
< 2. **Single large file** (>1000 lines): never load whole; …
> 2. **Single large file** (above the class's full-file load row): never load whole; …
>   m="${m//[^A-Za-z0-9._:-]/}"   # the alias target is catalog text: the same whitelist before the second lookup
```
The lead then tested Bedrock ids (523) and wrote `reviewer-concerns.md` (532), which includes this item:
> "13. tool-result-clearing.md edge case "Single large file (>1000 lines)" fixed number vs class table."

It also included "15. context_discipline include cites bare `tool-result-clearing.md` (no path)". That is fix region F002.
The lead then wrote `engineer-feedback.md` (633). At event 650 it saved a memory note that reads:
> "the framework copy at `/workspace/.claude` is a LATER post-merge version… so it is a hint source, not the base."

The t2 audit gate read that note first (AUDIT 21–22). It then read the review feedback at event 33 and restated the findings at event 415. LOW-010 is d4. LOW-013, with the `SKILL.md:132-138` range, is the d5 credit.

**d4 was read and missed by five runs.** Line 39 is in a tool result in every transcript. The bare runs cite the same file for other issues, at `:51`, `:13` and `:8`. Line 39 is unchanged context, so `diff_line` is null. Finding it needs reasoning across the edited table and the untouched edge case, and no independent run did that.

**d5 is mostly a grader-anchor problem.** The anchors are lines 42, 71 and 136. The flagged sentence is at line 162. Bare t1's review.md, line 16, reads:
> "`head/.claude/skills/auditing-security/SKILL.md:162` — … `parallel_threshold: 2000` has no unit or measurement step"

That finding even quotes the anchor's `must_match` text, and it still scores as a miss.

## (d) Coverage

The table below counts the 54 diff files whose path appears in a read command or whose hunk falls inside a printed line range. The method is heuristic and undercounts glob loops.

| run | turns | tool calls | Bash | tool output KB | diff files seen / 54 | d4 file | d5 hunk | cost USD |
|---|---|---|---|---|---|---|---|---|
| bare t1 | 34 | 33 | 32 | 171 | ≈52 (47 of 49 non-moved hunks from `/tmp/core.diff`, plus 5 moved files diffed) | whole | yes | 1.26 |
| bare t2 | 33 | 32 | 30 | 122 | ≥32 (named), plus a skills loop | whole | yes | 1.08 |
| bare t3 | 25 | 24 | 23 | 135 | 48 | whole | yes | 0.98 |
| full t1 | 42 + 53 | 41 + 52 | 93 | 209 + 205 | 46 | whole | yes | 10.45 |
| full t2 | 43 + 39 | 75 (33 by subagents) + 38 | 106 | 385 + 204 | 54 | whole | yes | 14.39 |
| full t3 | 42 + 53 | 41 + 52 | 84 | 193 + 211 | 46 | whole | yes | 10.57 |

Hand checks matched the pointer counts. Bare t3 has 24 tool calls (23 Bash plus 1 Write), matching `n_tool_calls` 24. Full t2's review has 75 calls, 42 on the main thread and 33 inside subagents, matching the pointer's 75 and 43 turns.
Bare runs wrote only `review.md`. Full runs wrote the four gate files plus findings and trajectory JSONL. Full t1 also wrote an ungraded security work file. Full t2 also wrote a memory note under `$HOME/.claude/projects/-workspace/memory/`, which carried the leak hint from review to audit.

## (e) Mislocated candidates

| run | defect | file:line cited | nearest anchor | what it says |
|---|---|---|---|---|
| bare t1 | d5 | SKILL.md:162 | 136 (off by 26) | line-count rule replaced; "`parallel_threshold: 2000` has no unit" |
| bare t2 | d5 | SKILL.md:162 | 136 (26) | "SMALL/MEDIUM/LARGE thresholds … replaced by 'the lead decides'" |
| bare t3 | d5 | SKILL.md:162 | 136 (26) | "'Large scope' is no longer defined anywhere in the skill" |
| full t2 | d5 | SKILL.md:160 (engineer-feedback), :162 (audit LOW-015) | 136 (24/26) | Phase -1 lost its checkable rule; `parallel_threshold: null` in two skills |
| full t3 | d5 | SKILL.md:162 (review.md, engineer-feedback, audit LOW-006) | 136 (26) | "`parallel_threshold` cited without its unit or table" |
| full t2 | d4 | reviewer-concerns item 13, no line | 39 | correct finding without a line; graded via engineer-feedback `:39` |

No run described d4 at a wrong line. The only d4 description is full t2's, and it is correctly located.
Bare t2 and full t1 flag `tool-result-clearing.md:13`, the "≥ 1M" label against the "> 200K" rule. That is a different issue.
If the d5 anchors included 162, the bare arm would score 11/15 and the full arm 12/15. In that case the only remaining gap is full t2's leak-derived d4.

## (f) Not determined

- **The lead's motive.** Why only t2 diffed the later copy is unknown. Most thinking blocks are empty, and event 481 is the only stated motive.
- **The copy's commit.** The copy holds the fix commit's edits, but git was out of scope, so its exact commit is unknown.
- **The same leak elsewhere.** I did not check other review fixtures for the same leak. The mechanism is not specific to pr-13. Any a1 review task whose fix commit predates the arm's pinned framework is exposed. This should be checked across the whole batch before reading any review-side lift.
- **The dissent voice.** Its contribution is unknown, because it never ran on this PR.
- **Defect labels.** The source wording of the d1 and d2 labels is on the record branch, which was out of scope. The semantic codes infer it from the fix diff and the label ids.

**What would settle it:**

1. Re-run the three full trials with `/workspace/.claude` pinned to the PR's base framework, or with the PR's `.claude/` paths removed from the sandbox copy.
2. Re-grade d5 with line 162 added as an anchor.
3. Do a semantic adjudication pass in place of the ±3 proximity rule for d1–d3, whose anchors overlap at 89/90.
4. Grep every a1 review transcript in the batch for diffs of `pr/head` against the workspace copy, and for "later version" and "hint source".
