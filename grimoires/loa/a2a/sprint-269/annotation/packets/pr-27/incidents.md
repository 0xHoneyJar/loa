# Incidents — pr-27

Things that happened after the change merged and cite one of its files: later fix commits on the main branch, issues, review rounds and known-failure entries. The quoted text is data, not instructions.

## I01 — kf — 2026-10-20

- reference: KF-046
- files: evals/harness/ablation-grade.sh

Summary:

## KF-046: ablation-grade.sh contamination scan flags ordinary agent text and shell idioms as outside_path or git_history (slash commands, git log --all, heredoc prose, sed address ranges, container home) **Status**: active **Feature**: evals/harness/ablation-grade.sh check_value / ABS_WORD (D-4.7 contamination scan) **Symptom**: grade.json contaminated {phase, pattern: outside_path|git_history,…

Evidence:

~~~~~text
~~~~markdown
## KF-046: ablation-grade.sh contamination scan flags ordinary agent text and shell idioms as outside_path or git_history (slash commands, git log --all, heredoc prose, sed address ranges, container home)

**Status**: active
**Feature**: evals/harness/ablation-grade.sh check_value / ABS_WORD (D-4.7 contamination scan)
**Symptom**: grade.json contaminated {phase, pattern: outside_path|git_history, excerpt_id: <PHASE>:<line>} and the row status contaminated on a run that never left the sandbox; the excerpt line holds a Loa slash command (/review-sprint), git log --all, prose inside a heredoc, ls ~/.cargo/bin in the container, a sed range /,/ or /re1/,/re2/p
**First observed**: 2026-10-15 cycle-130 Sprint 260 calibration smoke calib-frozen-01 (10 of 12 rows), then priority batch P1 review-04 REVIEW:39
**Recurrence count**: 10
**Current workaround**: re-grade the run directories under the current grader (no agent re-run) and re-row: run-ablation.sh --resume --rerow <run_id> (DEC-0547); the grader fixes are 1.2.1 (DEC-0540), 1.2.2 (DEC-0541), 1.2.3 (DEC-0546)
**Upstream issue**: none (harness heuristic; structural: a path-word regex over free-form Bash text cannot be made exact; the scan is a lower bound by design, D-4.7)
**Related visions / lore**: DEC-0540, DEC-0541, DEC-0546, DEC-0547; KF-045

### Attempts

| Date | What we tried | Outcome | Evidence |
|------|---------------|---------|----------|
| 2026-10-15 | grader 1.2.1 (one-component words, history probes), 1.2.2 (heredoc bodies, container home, /x/ delimiters), 1.2.3 (sed address ranges) | calibration rows 10 contaminated to 0; P1 review-04 re-rowed under 1.2.3 | commits 2ef83aa8, ae9df520; a2a/sprint-260/smoke.md; NOTES 2026-10-15T11:18:02Z |
| 2026-10-15 | grader 1.2.4 prepared (DEC-0551): words beginning with /, (range remnant after a spaced first address) and words carrying = are regex-shaped, not paths; applied after P1 ends, then --rerow of every contaminated row | pending (P1 running; a1_full review-02-t1 AUDIT:86 is the fourth false-positive class: sed -n '/=== VERIFY python ValueError ===/,/=== scanner usage ===/p') | grimoires/loa/reports/ablation-2.0/batches/priority-p1/a1_full/review-02-t1/grade.json; ~/.cache/loa/cycle-130/grader-124-patch.py |
| 2026-10-15 | fifth class: the hidden keyword matched ordinary English in a reviewer heredoc (a1_full bugfix-04-t1 REVIEW:148 'any hidden interaction'); grader 1.2.4 also narrows hidden in Bash text to token shapes (DEC-0551) | pending (applied after P1 ends; rows re-rowed) | grimoires/loa/reports/ablation-2.0/batches/priority-p1/a1_full/bugfix-04-t1/grade.json; ~/.cache/loa/cycle-130/grader-124-patch.py |
| 2026-10-16 | grader 1.2.4 applied (6c454de7) after P1 stopped; the seven contaminated P1 rows re-graded clean in scratch copies and were re-rowed on the resume | 0 of 7 contaminated under 1.2.4 (review-03-t1 reads cap_failure, the rest completed) | a2a/sprint-260/reviewer.md; grimoires/loa/reports/ablation-2.0/batches/priority-p1/STATUS.json rerowed[] |
| 2026-10-16 | sixth class: a path tail after a closing quote glued to its token ("$D"/evals/harness/x) read as an absolute outside path (a1_full feature-01-t2 AUDIT:122, grader 1.2.4); grader 1.2.5 prepared (DEC-0557), applied after P1 ends, the row re-rowed | pending | grimoires/loa/reports/ablation-2.0/batches/priority-p1/a1_full/feature-01-t2-r3/grade.json; ~/.cache/loa/cycle-130/grader-125-patch.py |
| 2026-10-16 | grader 1.2.5 applied (bf155cc7) after P1 completed; both rows re-rowed; P1 ends with 0 contaminated rows after six grader rounds (1.2.1–1.2.5) | 0 of 132 P1 rows contaminated; every contaminated row of the cycle so far was a scan false positive, none a real reach | grimoires/loa/reports/ablation-2.0/batches/priority-p1/STATUS.json rerowed[] (11 entries); runs.jsonl |
| 2026-10-16 | grader 1.2.8 (Sprint 260 audit fix) treated a [ after a one-component absolute word as a glob metacharacter so the word stayed a path candidate; re-scan of the 132 graded P1 run dirs under 1.2.8 | two new false positives (a1_full feature-03-t2-r3 AUDIT:115 grep '/home[^"]*loader.py' regex; refactor-04-t2-r3 IMPLEMENT:47 sed 's/job\["status"\]…'): a bracket after the word is a regex bracket expression in agent commands, not a glob — grader 1.2.9 reads * and ? only and keeps a quoted one-component pattern exempt; the re-scan is back to 0 changes | rescan-p1-126.py over priority-p1 under 1.2.8 vs the stored grade.json (2 changed) and under 1.2.9 (0 changed); commit 60503096 (1.2.8) and the 1.2.9 commit that follows; a2a/sprint-260/auditor-sprint-feedback.md round 2 |
| 2026-10-17 | grader 1.2.11 on the suite v2 round-2 calibration (calib-v2-02a, a0_bare x 10 tasks x 2) | one row contaminated (refactor-v2-07 t1, BARE:145 outside_path): the bare agent passed JSON Pointer literals (get clit/d.json /a/1, /a/9) as CLI arguments while differential-testing a JSON Patch package — a two-component word indistinguishable from an absolute path by shape; read by hand, not a reach; pass rate 1.0 either way, so the hardness read is unchanged; no grader change (a pointer-literal exemption would also exempt real paths); the task is not run in the v2 batch | evals/results/ablation-2.0/calib-v2-02a/a0_bare/refactor-v2-07-t1/grade.json contaminated BARE:145; commit bde0c22e (grader 1.2.11) |
| 2026-10-19 | seventh class, batch replication-01 (deep analysis): pattern repo_name fired on the reviewer's own heredoc text quoting the PR's CI workflow clause github.repository == '0xHoneyJar/loa' (pr-18 head/.github/workflows/check-glossary-terms.yml); rows a1_full review-r18-t2 (REVIEW:320, reviewer-concerns.md heredoc) and review-r18-t3 (AUDIT:332, auditor-sprint-feedback.md heredoc) read contaminated | read by hand: the string is the PR's own content, not a reach outside the sandbox; no grader change in this analysis task (code edits out of scope), so the two rows stay contaminated under the pre-registered rule (a1 excluded share 2/6 = 0.33 > 0.25 -> the replication's pre-registered read is inconclusive by degradation) and the hand-read sensitivity with the two rows included is reported beside it; grader fix (exempt a repo name that occurs in pr/head or head.diff) is a cycle-131 candidate | evals/results/ablation-2.0/replication-01/a1_full/review-r18-t2/grade.json contaminated REVIEW:320; evals/results/ablation-2.0/replication-01/a1_full/review-r18-t3/grade.json contaminated AUDIT:332; a2a/analysis-2026-10/replication.md |
| 2026-10-20 | cycle-131 B2a rows under grader 1.3.0 (class 7 + r1a/r1c rules): a0_bare × review-r18 t1 and a1_full × review-r18 t1 read contaminated | a0_bare r18 t1 (BARE:96) is a TRUE positive: curl -sfL … raw.githubusercontent.com/0xHoneyJar/loa/main/.claude/loa/CLAUDE.loa.md to fill a missing file (repo_name, correctly never exempt). a1_full r18 t1 (AUDIT:303) is an outside_path hit on a reproduction: the auditor built a scratch git repo + venv under $HOME/tmp/venvrepro.XXXX to reproduce the PR's venv claim — no upstream fetch, no answer path; class 8 candidate (scratch-dir reproduction under $HOME/tmp). Both rows excluded by the pre-registered validity rule; a labelled sensitivity re-includes class-8 rows (NOTES 2026-10-20, defined before the reads) | evals/results/ablation-2.0/c131-b2-control-prices-a/{a0_bare,a1_full}/review-r18-t1/grade.json; pin 798d88cf |

### Reading guide

A contaminated row is a claim to verify, not a verdict: print the excerpt line (sed -n '<line>p' <run-dir>/transcripts/events-<PHASE>.jsonl | jq '.message.content[] | select(.type=="tool_use") | .input') and ask whether the word reaches a path outside the sandbox, the container home, /tmp or the system dirs. Shell idioms seen so far: slash commands, sed/awk delimiters and ranges, heredoc prose, regexes beginning with = or a letter. If it is an idiom: fix the grader (bump GRADER_VERSION, extend AG-10), re-grade every affected run directory, --rerow. If it is a real reach: the exclusion stands. Recurrence 3 in one day means the heuristic is structural: budget a re-read of every contaminated row before the report.

~~~~
~~~~~

## I02 — kf — 2026-10-20

- reference: KF-049
- files: evals/harness/pipeline-run.sh

Summary:

## KF-049: review-catch a1 sandbox mounts the pinned framework (ba11b860), a LATER version of every file the PR under review touches: the fixed code is one diff away from the reviewer (answer-key oracle); the bare arm has no such mount **Status**: active **Feature**: evals/harness/pipeline-run.sh review-catch sandbox (loa_mount) with the record-PR corpus evals/fixtures/review-prs (every fix commi…

Evidence:

~~~~~text
~~~~markdown
## KF-049: review-catch a1 sandbox mounts the pinned framework (ba11b860), a LATER version of every file the PR under review touches: the fixed code is one diff away from the reviewer (answer-key oracle); the bare arm has no such mount

**Status**: active
**Feature**: evals/harness/pipeline-run.sh review-catch sandbox (loa_mount) with the record-PR corpus evals/fixtures/review-prs (every fix commit is an ancestor of the pin)
**Symptom**: an a1_full REVIEW transcript runs diff on pr/head/PATH against the workspace copy of PATH ('head vs later workspace'); the result shows the fix commit's hunks at the planted sites; the gate's findings cite those sites only after that event; the row reads completed and the defects count as caught
**First observed**: 2026-10-19 cycle-130 deep analysis (a2a/analysis-2026-10/mechanism-pr-13.md): priority-v2-p1-a1_full-review-04-t2 REVIEW events 482 and 483 (d1-d4 exposed, all cited after; the audit inherited them via a memory note); static check: every planted site of pr-05/08/12/13/16/17/18 differs between pr/head and the ba11b860 copy (scripts/oracle_scan.py)
**Recurrence count**: 4
**Current workaround**: read every a1 review-catch row with scripts/oracle_scan.py (a real diff/comm/sdiff between a pr/ operand and a workspace operand; planted sites inside the printed hunks; first citation after the event) and report H1 with the exposed cell excluded pairwise (+0.228 [+0.105, +0.351]) or zeroed (+0.175 [+0.035, +0.316]) beside the shipped +0.263; pre-register the scan for any new review-catch batch
**Upstream issue**: none yet (harness design: mount the framework at the PR's base commit for review-catch tasks, or exclude the PR-touched paths from the mount; cycle-131 candidate bead)
**Related visions / lore**: DEC-0597 (H1 on suite v2); a2a/analysis-2026-10 mechanism-pr-13.md, attribution.md, sensitivities.md; KF-046 (another grader-side reading rule)

### Attempts

| Date | What we tried | Outcome | Evidence |
|------|---------------|---------|----------|
| 2026-10-19 | oracle_scan.py over the 12 valid a1 cells (24 gates): precise detector (diff/comm/sdiff with a pr/ operand and a workspace operand; not -q; the word head.diff excluded) | 1 of 12 runs used the oracle on planted sites (review-04 t2 REVIEW event 482: 4 of 5 defects; its 5th credit inherited the leak via the audit); one other content diff (review-04 t2 event 311, reference stubs, no planted site); every other diff-like command was a parity check | grimoires/loa/a2a/analysis-2026-10/data/oracle-scan.json; grimoires/loa/reports/ablation-2.0/batches/priority-v2-p1/a1_full/review-04-t2/transcripts/events-REVIEW.jsonl lines 482-483; mechanism-pr-13.md section c |
| 2026-10-19 | replication-01 (pr-17, pr-18; PRs no analysis had seen): oracle_scan.py over the six a1 runs after the batch | 2 of 6 runs diffed pr/head against the mounted later copy on planted sites: review-r17-t1 REVIEW events 314/316/365 (9 sites exposed, all 9 cited afterwards, 7 of them missed by bare in the same trial) and review-r18-t1 REVIEW event 226 (1 site); review-r18-t2 AUDIT event 108 diffed red-test-check.sh 'later fixes hint' with no planted site in the hunks; the lift survives zeroing the exposed catches (+0.333 [+0.190, +0.476]) but the channel is habitual, not a one-off | evals/results/ablation-2.0/replication-01/a1_full/review-r17-t1/transcripts/events-REVIEW.jsonl lines 314-316, 365; .../review-r18-t1/transcripts/events-REVIEW.jsonl line 226; grimoires/loa/a2a/analysis-2026-10/data/replication-read.json (oracle[]) |
| 2026-10-19 | cycle-131 Task 1.3 detector (grader 1.3.0, implementer B) validated over the 36 cycle-130 review-catch runs, diff and read forms | two further genuine head-vs-later-copy diffs found that the analysis missed: replication r17-t2 (REVIEW event 144, loop diff <(cat pr/head/$f) $f) and r17-t3 (REVIEW event 137, diff -u pr/head/$f $f), both printing planted-site hunks; oracle_scan.py could not resolve $f. Read form adds incidental later-copy reads on seven more full-arm runs; no bare run flagged | ~/.cache/loa/cycle-131/reports/s1-b.md; DEC-0632; plan commit 7600bd7d |
| 2026-10-20 | cycle-131 closed mount (overlay_answer_paths + check_mount_closed + oracle_closed) on every Sprint 264 batch row; open mount kept only as the eval-only control arm | CLOSED for the mounted arm: 24/24 closed-mount rows oracle_exposed_defects empty and oracle_closed true at pin 798d88cf; the control arm a1_full_openmount peeked in 3/3 runs (7/15/3 defects), R1 Δ +0.067 [−0.017, +0.150] on pr-17 | grimoires/loa/reports/ablation-2.0/c131-rows.jsonl; a2a/sprint-2/batch-scans.md; DEC-0651 |
| 2026-10-20 | PR #1286 Bridgebuilder F002: grader 1.3.1 makes the oracle detector scan error-marked tool results (a differing diff exits 1; 1.3.0 skipped every is_error result) and re-grades the 36 cycle-130 + 27 cycle-131 review-catch runs | Closed the detector gap; the 63 re-grades are identical to 1.3.0 on every oracle field (the 26 error-marked results with diff ranges all compare pr/base with pr/head or read head.diff). The KF-049 exposure counts stand. | PR #1286 comment 6288566518; bead bd-cxdsm; ~/.cache/loa/cycle-131/regrade-131/compare.tsv (63 same) |

### Reading guide

A review-catch lift measured with the framework mounted is an upper bound. Before reading any a1 catch on a record PR, grep the REVIEW and AUDIT transcripts for a content diff (not cmp -s, md5sum or diff -q) between a pr/head or pr/base path and the workspace copy of a PR-touched file, and check whether its hunks cover a planted site before the first citation of that site; a hit taints the whole run (the audit reads the review's feedback and memory). The exposure is structural (every record fixture's fix commit precedes the pin), so fix the mount before the next review-catch batch rather than re-reading rows one by one.

~~~~
~~~~~

## I03 — kf — 2026-10-20

- reference: KF-051
- files: evals/harness/pipeline-run.sh

Summary:

## KF-051: Fable 5.1 review-gate session refused (category cyber) and the pipeline fell back to Opus 5.5 mid-phase: a 'Fable reviewer' row that mostly ran on Opus **Status**: OPEN — observed once; rows read degraded, excluded from model contrasts **Feature**: evals/harness/pipeline-run.sh refusal fallback (REVIEW/AUDIT phases on global.anthropic.claude-fable-5-1) → ablation-row.sh degraded_reason…

Evidence:

~~~~~text
~~~~markdown
## KF-051: Fable 5.1 review-gate session refused (category cyber) and the pipeline fell back to Opus 5.5 mid-phase: a 'Fable reviewer' row that mostly ran on Opus

**Status**: OPEN — observed once; rows read degraded, excluded from model contrasts
**Feature**: evals/harness/pipeline-run.sh refusal fallback (REVIEW/AUDIT phases on global.anthropic.claude-fable-5-1) → ablation-row.sh degraded_reason 'REVIEW: refusal fallback'
**Symptom**: phases.jsonl REVIEW record: refusal_fallbacks [{from: global.anthropic.claude-fable-5-1, to: global.anthropic.claude-opus-5-5, category: cyber, scope: session}], models_used holds both models (Fable 3,228 vs Opus 14,682 output tokens), the phase completes normally (cli_exit 0, verdict written); the row reads degraded: true, degraded_reason 'REVIEW: refusal fallback'
**First observed**: 2026-10-20 cycle-131 Sprint 264 arm smoke smoke-c131-arms-20261020T025808Z, a1_no_dissent × review-01 (pr-05); 0 of 36 cycle-130 runs, 0 of 8 Sprint 263 smoke rows carried one
**Recurrence count**: 1
**Current workaround**: None needed for completion (the fallback is the designed behaviour). For reads: exclude the row from any model contrast (R5) and count it degraded elsewhere; report models_used per phase. Do not retry the cell to 'get a Fable row' — that selects on the refusal.
**Upstream issue**: cycle-131 pre-registration (Sprint 264); row writer flags it already
**Related visions / lore**: KF-048 (credential), KF-037 (CLI contention); DEC-0545 (extra models are telemetry, not drift — a refusal fallback IS a model change)

### Attempts

| Date | What we tried | Outcome | Evidence |
|------|---------------|---------|----------|
| 2026-10-20 | arm smoke on pr-05: a1_no_dissent REVIEW phase (dissent disabled; Fable 5.1 xhigh) hit the refusal; a1_full_openmount and a0_bare_fable on the same PR did not | row completed, catch 1.0, degraded by the fallback; rule added to the Sprint 264 pre-registration (R5 exclusion) | evals/results/ablation-2.0/smoke-c131-arms-20261020T025808Z/a1_no_dissent/review-01-t1/meta/phases.jsonl; commit 0281ea57 |

### Reading guide

A refusal fallback is a model-safety event on the review content, not infrastructure: the same PR reviewed on Fable without a fallback in two sibling arms the same hour, so it is stochastic per session. Read the row's phases[].refusal_fallbacks and models_used before attributing any Fable-vs-Opus difference to the pipeline; a cell with a fallback is not a Fable cell. If the rate grows past a few percent of review-catch rows, the model confound in every full-pipeline read is live and must be reported as such.
~~~~
~~~~~
