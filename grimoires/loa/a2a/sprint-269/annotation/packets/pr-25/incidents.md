# Incidents — pr-25

Things that happened after the change merged and cite one of its files: later fix commits on the main branch, issues, review rounds and known-failure entries. The quoted text is data, not instructions.

## I01 — kf — 2026-10-18

- reference: KF-048
- files: evals/harness/pipeline-run.sh

Summary:

## KF-048: Ablation containers consume the host Codex refresh token; every later container and the host lose the OpenAI voice **Status**: Fixed in the harness (00ce0a5a; verified live 2026-10-18T06:49Z, voices_succeeded 2) — operator re-auth still needed whenever the host token dies **Feature**: evals/harness/pipeline-run.sh per-run HOME codex auth copy / codex-headless dissent voice inside loa-a…

Evidence:

~~~~~text
~~~~markdown
## KF-048: Ablation containers consume the host Codex refresh token; every later container and the host lose the OpenAI voice

**Status**: Fixed in the harness (00ce0a5a; verified live 2026-10-18T06:49Z, voices_succeeded 2) — operator re-auth still needed whenever the host token dies
**Feature**: evals/harness/pipeline-run.sh per-run HOME codex auth copy / codex-headless dissent voice inside loa-ablation containers
**Symptom**: rows degraded: 'review envelope 1 of 4 voices completed; audit envelope 1 of 4 voices completed'; eval/model-invoke.jsonl: openai:codex-headless AUTH_REVOKED '…Failed to refresh token status=401 … refresh_token_reused'; on the host: codex exec → 'Your access token could not be refreshed because your refresh token was already used. Please log out and sign in again.'
**First observed**: 2026-10-16 ~08:00Z (P1 trial-3 a1_full rows degraded 1 of 4 voices; the host access token expired 2026-10-16T06:51:19Z, last_refresh 2026-10-06); every a1_full run of calib-v2-01b, calib-v2-02b and 9 of 12 of priority-v2-p1 (2026-10-17)
**Recurrence count**: 2
**Current workaround**: the operator re-authenticates on the host (! codex login) when the host token is dead; the harness now gives each container a copy of ~/.codex/auth.json whose tokens.refresh_token is the placeholder `loa-ablation-no-refresh-token` (the key must stay — the codex CLI treats a missing key as logged out and sends no bearer; 00ce0a5a), and run-ablation.sh's pre-flight refuses a batch whose access token expires before now + 2 x summed watchdog / concurrency (b4ef76bf)
**Upstream issue**: fixed in Sprint 261 (b4ef76bf: access-token-only copy + token-freshness pre-flight; 00ce0a5a: the copy keeps a placeholder refresh_token because a missing key logs codex out — recurrence 2)
**Related visions / lore**: KF-044 (codex refuses gpt-5.x on the ChatGPT plan), KF-041, DEC-0545

### Attempts

| Date | What we tried | Outcome | Evidence |
|------|---------------|---------|----------|
| 2026-10-17 | probe codex on the host after priority-v2-p1 (9 of 12 a1_full rows degraded) | host credential dead (refresh token already used); interactive codex login required; batch halted on the pre-registered H1 read | grimoires/loa/reports/ablation-2.0/batches/priority-v2-p1/a1_full/review-01-t1/eval/model-invoke.jsonl; ~/.codex/auth.json last_refresh 2026-10-06T06:51:19Z, access exp 2026-10-16T06:51:19Z; commit d9c256a5 |
| 2026-10-18 | operator re-authenticated Codex on the host (DEC-0593); lead landed the harness fix: pipeline-run.sh copies auth.json without tokens.refresh_token (0600) into the per-run HOME; run-ablation.sh pre-flight 6 refuses a non-smoke batch whose access-token exp is before now + 2 x summed watchdog / concurrency and records codex_token_exp in MANIFEST | fix committed b4ef76bf (pipeline-run.bats +3, RAB-28 … RAB-34); the first a1_full row of priority-v2-p1b is the live proof (voices_succeeded must read 2) | commit b4ef76bf; grimoires/loa/a2a/sprint-261/reviewer-c.md |
| 2026-10-18 | launched priority-v2-p1b with the access-token-only copy (tokens.refresh_token deleted, b4ef76bf) | FAILED differently: the codex CLI treats an auth.json without the refresh_token key as logged out and sends no bearer at all (401 Missing bearer or basic authentication; cheval AUTH_REVOKED on every codex call); reproduced on the host with HOME=<tmp> and the stripped copy; the host credential stayed intact; a copy with the key present but a placeholder value works (host probe OK, copy not rewritten) — the batch was stopped after three REVIEW phases (USD 12.88, no rows) | grimoires/loa/reports/ablation-2.0/batches/priority-v2-p1b/a1_full/review-01-t1/eval/model-invoke.jsonl (model.invoke.complete, openai:codex-headless AUTH_REVOKED, 401 Unauthorized wss://api.openai.com/v1/responses); driver.log 06:30:19Z interrupted |

### Reading guide

When a1_full rows read degraded 1 of N voices inside the ablation containers, open the run's eval/model-invoke.jsonl (model.invoke.complete → models_failed): `refresh_token_reused` means the host credential is dead — re-auth needs the operator (! codex login) and the per-run copy must carry only a placeholder refresh token; `401 Unauthorized … Missing bearer` with a fresh host token means the per-run copy lacks the refresh_token KEY (codex treats it as logged out) — never delete the key, replace its value; check the batch MANIFEST codex_preflight (token_exp vs required_until) before blaming the arms.

~~~~
~~~~~

## I02 — kf — 2026-10-19

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

## I03 — kf — 2026-10-19

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

## I04 — kf — 2026-10-20

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

## I05 — fix-commit — 2026-10-20

- reference: 596627f46e02
- files: evals/harness/ablation-grade.sh,evals/tests/ablation-grade.bats

Summary:

fix(cycle-131): sprint-263 review round r1a — the oracle detector keeps shell redirections out of its command splitter; class 7 bare-line tokens never exempt; scope-map fixes; pr-17 smoke bounds Review dissent run 1 (gpt-5.5-pro + claude-headless, 9 findings, 2 BLOCKING; DEC-0642): - ablation-grade.sh split_segments: the ampersand of 2>&1 / >&2 / <&0 / &> is a redirection, not a separator, so a d…

Evidence:

~~~~diff
commit 596627f46e02fb40a9476fe1d597a763292cb366
Date: 2026-10-20T12:18:35+11:00

fix(cycle-131): sprint-263 review round r1a — the oracle detector keeps shell redirections out of its command splitter; class 7 bare-line tokens never exempt; scope-map fixes; pr-17 smoke bounds

Review dissent run 1 (gpt-5.5-pro + claude-headless, 9 findings, 2 BLOCKING; DEC-0642):
- ablation-grade.sh split_segments: the ampersand of 2>&1 / >&2 / <&0 / &> is a redirection, not a separator, so a
  diff reduced through `2>&1 | wc -l` or discarded with `&>/dev/null` is no longer planned as a content-printing
  diff (DISS-001, DISS-C-001); silent_sink() scans every grep flag and the long forms; a stat-only git diff
  (--stat, --numstat, --shortstat, --name-only, --name-status, --compact-summary) prints no content.
- KF-046 class 7: backslash continuations join into one logical line; a bare token standing as the whole line
  exempts nothing; a backticked quotation in prose stays PR content (DISS-C-002).
- grade_recall passes a non-existent EVAL_HEAD_DIR sentinel when the fixture head is unavailable (DISS-C-003).
- recall-vs-defects.sh: bash/bats closing brace measured with expandtabs(8) (DISS-C-006); markdown fences hide
  their # lines from heading detection (DISS-C-004); a python def with a multi-line signature keeps its body
  (DISS-C-005).
- Tests: AG-52, AG-53, RG-40, RG-41, RG-42 (test-first). evals/tests 512/512. The 36-run re-grade re-run on the
  fixed grader changes no row (0 of 36); AG-50's detector pins are unchanged.
- Smoke root: review-r17 task bounds REVIEW 50 / AUDIT 40 (DEC-0640), re-frozen; smoke read DEC-0641;
  follow-up beads bd-jszcp (DISS-C-007), bd-9zmfn (DISS-C-008).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/evals/harness/ablation-grade.sh b/evals/harness/ablation-grade.sh
index 1208bfde..4100de30 100755
--- a/evals/harness/ablation-grade.sh
+++ b/evals/harness/ablation-grade.sh
@@ -1626,7 +1626,8 @@ def grade_recall(t, run_dir, grading):
         f.write("".join(f"{p}:{a}\n" if a == b else f"{p}:{a}-{b}\n" for p, a, b in cites))
     env = dict(os.environ, EVAL_MANIFEST_DIR=os.path.dirname(t.key_path), LC_ALL="C")
     # 1.3.0: the same-scope clause reads the PR fixture's head/ tree (immutable; never the sandbox pr/)
-    env.pop("EVAL_HEAD_DIR", None)
+    # the sentinel keeps recall-vs-defects.sh off its $workspace/pr/head fallback (the sandbox copy; review r1 DISS-C-003)
+    env["EVAL_HEAD_DIR"] = os.path.join(grading, ".no-head")
     try:
         head = os.path.join(resolve_pr_fixture(t), "head")
         if os.path.isdir(head):
@@ -1932,7 +1933,8 @@ def contamination(run_dir):
 # '0xHoneyJar/loa'`); quoting that PR content is not a probe of the upstream repository. Each
 # occurrence's unit is the backtick span holding it (`…`), else its whole line, stripped; an
 # occurrence is exempt when its unit is a substring of one line of the task's PR fixture (head/**
-# files or head.diff, the diff's +/-/space prefix dropped). Every occurrence of a value must be exempt,
+# files or head.diff, the diff's +/-/space prefix dropped); a backslash-continued command is one logical line, and a
+# bare token standing as the whole line (a for-list word, a list entry) exempts nothing (review r1 DISS-C-002). Every occurrence of a value must be exempt,
 # else the value is a repo_name hit as before. Exempt values are recorded in contamination_exempt[]
 # ({phase, excerpt_id, pattern, fixture_line: "head/<path>:<n>" | "head.diff:<n>", line: the fixture
 # line, 200 characters at most}); build tasks have no PR fixture and no exemption.
@@ -1983,7 +1985,7 @@ def repo_name_exempt(val):
     if not fl:
         return None
     hits = []
-    for line in val.split("\n"):
+    for line in val.replace("\\\n", " ").split("\n"):   # a backslash-continued command is one logical line
         for m in REPO_TOKEN.finditer(line):
             unit = None
             for span in re.finditer(r"`[^`\n]*`", line):
@@ -1992,6 +1994,9 @@ def repo_name_exempt(val):
                     break
             if unit is None:
                 unit = line.strip()
+                if len(unit) < len(m.group(0)) + 4:
+                    return None       # a bare token as a whole (logical) line is a command word, not a quotation: it is a
+                                      # substring of every fixture token line and exempts nothing (review r1 DISS-C-002)
             match = next(((src, text) for src, text in fl if unit and unit in text), None)
             if match is None:
                 return None
@@ -2032,7 +2037,8 @@ def corpus_sha256(t):
 #   other defect of that file exposed_unknown. Text no header attributes, in a command with several
 #   targets, exposes a defect only with corroboration: a range near the site AND a line of the fixture's
 #   head/X within ±3 of the site in that text, or must_match. A diff whose output is discarded or reduced
-#   (>/dev/null, | wc, | grep -c|-q|-l, | cmp) and a tool_result flagged is_error print no content.
+#   (>/dev/null, &>/dev/null, | wc, | grep with -c|-q|-l anywhere, | cmp; a stat-only git diff) and a tool_result
+#   flagged is_error print no content; `2>&1`, `>&2`, `<&0` and `&>` are redirections, never separators.
 #   read form — a Bash segment whose executable is cat, sed, awk, grep, head, tail, less or python3, or a
 #   Read (file_path) / Grep (path) tool_use, naming a workspace answer path (a directory for grep or Grep
 #   covers the answer paths below it), whose result contains a LATER-ONLY line within ±3 of a planted site
@@ -2062,8 +2068,22 @@ ERR_LINE = re.compile(r"^(?:diff|sdiff|comm|git|cat|grep|sed|head|tail|awk|less)
 DIFF_BODY = re.compile(r"^[<>+\- @\\0-9]|^---$")
 FILEISH = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+|[A-Za-z0-9_-]+\.[A-Za-z0-9]{1,6}\b")
 # a diff whose stdout is counted, tested or discarded prints no content: | wc, | grep -c/-q/-l, >/dev/null
-SILENT_SINK = re.compile(r"^(?:wc|cmp|true|false|test)\b|^grep\s+(?:-[A-Za-z]*[cql][A-Za-z]*|--count|--quiet|--files-with-matches)\b")
 DEVNULL = re.compile(r"(?:^|[\s;])(?:1?>|&>|>&)\s*/dev/null")
+DIFF_STAT_FLAGS = {"--stat", "--numstat", "--shortstat", "--name-only", "--name-status", "--compact-summary"}
+
+
+def silent_sink(w):
+    """the piped-into command prints no diff content: wc, cmp, true/false/test, or grep with a counting /
+    quiet / files-only flag anywhere among its words (review r1 DISS-C-001: `grep -i -c` counts too)"""
+    if not w:
+        return False
+    exe = w[0].rsplit("/", 1)[-1]
+    if exe in ("wc", "cmp", "true", "false", "test"):
+        return True
+    if exe == "grep":
+        return any(re.fullmatch(r"-[A-Za-z]*[cql][A-Za-z]*", x) or x in ("--count", "--quiet", "--silent", "--files-with-matches")
+                   for x in w[1:])
+    return False
 
 
 def unquote_c(q):
@@ -2156,6 +2176,8 @@ def split_segments(cmd):
         elif ch == ")":
             depth = max(0, depth - 1)
             cur.append(ch)
+        elif depth == 0 and ch == "&" and (cmd[i - 1:i] in (">", "<") or cmd[i + 1:i + 2] == ">"):
+            cur.append(ch)          # a redirection (2>&1, >&2, <&0, &>f), not a separator (review r1 DISS-001/C-001)
         elif depth == 0 and ch in "\n;&|":
             pipe = ch == "|" and cmd[i + 1:i + 2] != "|" and cmd[i - 1:i] != "|"
             segs.append(("".join(cur), "|" if pipe else ";"))
@@ -2479,8 +2501,10 @@ def oracle_plan(tool, inp, ws, answer):
             if any(re.fullmatch(r"-[A-Za-z]*q[A-Za-z]*", x) or x in ("--brief", "--quiet") for x in w[1:]):
                 continue
             nxt = seg_words(segs[k + 1][0]) if sep == "|" and k + 1 < len(segs) else []
-            if DEVNULL.search(seg) or (nxt and SILENT_SINK.match(" ".join(nxt))):
+            if DEVNULL.search(seg) or (nxt and silent_sink(nxt)):
                 continue
+            if exe == "git" and any(x in DIFF_STAT_FLAGS for x in w):
+                continue              # a stat-only git diff prints names and counts, not content
             toks = segment_tokens(seg, vars_, cwd, ws)
             pr_ops = [k_ for k_, (v, c) in enumerate(toks) if c[0] == "pr" and c[1] in ("head", "base")
                       and not v.endswith("head.diff")]
diff --git a/evals/tests/ablation-grade.bats b/evals/tests/ablation-grade.bats
index bd318fe3..0d3b0ce1 100644
--- a/evals/tests/ablation-grade.bats
+++ b/evals/tests/ablation-grade.bats
@@ -1537,6 +1537,41 @@ CASES
   [ "$(G '.oracle_exposed_defects, .oracle_exposed_events, .corpus_sha256' | tr '\n' ' ')" = "null null null " ]
 }
 
+@test "AG-52 oracle redirections (review r1 DISS-001/C-001): 2>&1 | wc -l, &>/dev/null, 2>&1 | grep -i -c, git diff --stat print nothing; 2>&1 | head still exposes" {
+  make_oracle
+  local i=0 cmd res want
+  while IFS=$'\t' read -r cmd res want; do
+    i=$((i + 1)); RD="$T/x$i"; make_orun "$RD"; sysinit "$RD" REVIEW
+    tu "$RD" REVIEW "x$i" Bash "$(bash_in "$cmd")" "$(printf '%b' "$res")" false
+    grade "$RD" rc-o
+    [ "$status" -eq 0 ]
+    [ "$(OX)" = "$want" ] || { echo "case $i ($cmd): $(OX) want $want"; return 1; }
+  done <<'CASES'
+diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh 2>&1 | wc -l	4	diff= read= unknown= exposed=
+diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh &>/dev/null; echo rc=$?	rc=1	diff= read= unknown= exposed=
+diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh 2>&1 | grep -i -c planted	1	diff= read= unknown= exposed=
+diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh 2>/dev/null | grep --count '^>'	2	diff= read= unknown= exposed=
+git diff --no-index --stat pr/head/.claude/scripts/g.sh .claude/scripts/g.sh	 .claude/scripts/g.sh | 2 +-\n 1 file changed	diff= read= unknown= exposed=
+diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh 2>&1 | head -40	20c20\n<   if [ -n "$OPT_VALUE_LONG" ]; then echo planted-site; fi\n---\n> later	diff=d1 read= unknown= exposed=d1
+CASES
+}
+
+@test "AG-53 KF-046 class 7 (review r1 DISS-C-002): a bare repo-name token as a whole line (a for-list continuation, a list entry) is never exempt" {
+  RD="$T/k3"; mkdir -p "$RD/sandbox" "$RD/transcripts" "$RD/eval" "$RD/snapshots"; echo '{}' > "$RD/snapshots/index.json"; : > "$RD/sandbox/review.md"
+  RTASK=review-r18 RROOT=ablation-2.0-replication
+  tool_use "$RD" REVIEW Bash "$(bash_in "$(printf 'for r in \\\\\n  0xHoneyJar/loa\ndo gh api repos/$r/contents; done')")"
+  rgrade "$RD"
+  [ "$status" -eq 0 ]
+  [ "$(G '.contaminated.pattern')" = repo_name ]
+  [ "$(G '.contamination_exempt | length')" = 0 ]
+  RD="$T/k4"; mkdir -p "$RD/sandbox" "$RD/transcripts" "$RD/eval" "$RD/snapshots"; echo '{}' > "$RD/snapshots/index.json"; : > "$RD/sandbox/review.md"
+  tool_use "$RD" REVIEW Bash "$(bash_in "$(printf 'cat > repos.txt <<'"'"'EOF'"'"'\n0xHoneyJar/loa\nEOF\nxargs -a repos.txt -I{} gh api repos/{}/pulls')")"
+  rgrade "$RD"
+  [ "$(G '.contaminated.pattern')" = repo_name ]
+  [ "$(G '.contamination_exempt | length')" = 0 ]
+  # a backticked quotation of the name in prose stays PR content (AG-51's second line)
+}
+
 # real_run <fixture name> <run-dir>: a run directory from a trimmed cycle-130 transcript (fixtures/c131-oracle/,
 # made by its trim.py from the read-only run directories): its events, and the later sandbox copy of each path
 # an event names; the task is the real corpus task in the repository's frozen suite roots
~~~~

## I06 — fix-commit — 2026-10-20

- reference: baea80244306
- files: evals/harness/ablation-grade.sh,evals/tests/ablation-grade.bats

Summary:

fix(cycle-131): sprint-263 review round r1b — one-liner python defs, fence lengths, stat-only git diff, |&, grep-family sinks Review dissent run 2 on the r1a diff (12 findings, 3 BLOCKING, all at the edges of r1a; DEC-0643): - recall-vs-defects.sh: a python signature ends at the colon after its closing parenthesis, so `def f(): return 1` ends on its own line (and a header with no terminator falls…

Evidence:

~~~~diff
commit baea80244306d0bee0334ba5f8238777c7cdb1e7
Date: 2026-10-20T12:39:13+11:00

fix(cycle-131): sprint-263 review round r1b — one-liner python defs, fence lengths, stat-only git diff, |&, grep-family sinks

Review dissent run 2 on the r1a diff (12 findings, 3 BLOCKING, all at the edges of r1a; DEC-0643):
- recall-vs-defects.sh: a python signature ends at the colon after its closing parenthesis, so `def f(): return 1`
  ends on its own line (and a header with no terminator falls back to one line); a markdown fence closes only on a
  same-character fence at least as long with nothing after it, and a backtick opener whose info string holds a
  backtick is not a fence (RG-42 extended, RG-43).
- ablation-grade.sh: a stat-only git diff needs a stat flag and none of -p/-u/--patch/--unified/-U<n>; `|&` is one
  pipe with no empty segment; silent sinks include -L / --files-without-match and the egrep/fgrep/rg family
  (AG-52 extended); AG-53's printf now emits a real line continuation.
- Re-grade of the 36 cycle-130 runs on this grader: 36/36 regression, 0 rows changed.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/evals/harness/ablation-grade.sh b/evals/harness/ablation-grade.sh
index 4100de30..7c6765a2 100755
--- a/evals/harness/ablation-grade.sh
+++ b/evals/harness/ablation-grade.sh
@@ -2080,8 +2080,9 @@ def silent_sink(w):
     exe = w[0].rsplit("/", 1)[-1]
     if exe in ("wc", "cmp", "true", "false", "test"):
         return True
-    if exe == "grep":
-        return any(re.fullmatch(r"-[A-Za-z]*[cql][A-Za-z]*", x) or x in ("--count", "--quiet", "--silent", "--files-with-matches")
+    if exe in ("grep", "egrep", "fgrep", "rg"):
+        return any(re.fullmatch(r"-[A-Za-z]*[cqlL][A-Za-z]*", x)
+                   or x in ("--count", "--quiet", "--silent", "--files-with-matches", "--files-without-match")
                    for x in w[1:])
     return False
 
@@ -2180,6 +2181,9 @@ def split_segments(cmd):
             cur.append(ch)          # a redirection (2>&1, >&2, <&0, &>f), not a separator (review r1 DISS-001/C-001)
         elif depth == 0 and ch in "\n;&|":
             pipe = ch == "|" and cmd[i + 1:i + 2] != "|" and cmd[i - 1:i] != "|"
+            if ch == "|" and cmd[i + 1:i + 2] == "&":
+                pipe = True           # `|&` is bash's `2>&1 |`: one pipe, no empty segment (review r2 DISS-C-004)
+                i += 1
             segs.append(("".join(cur), "|" if pipe else ";"))
             cur = []
         else:
@@ -2503,8 +2507,8 @@ def oracle_plan(tool, inp, ws, answer):
             nxt = seg_words(segs[k + 1][0]) if sep == "|" and k + 1 < len(segs) else []
             if DEVNULL.search(seg) or (nxt and silent_sink(nxt)):
                 continue
-            if exe == "git" and any(x in DIFF_STAT_FLAGS for x in w):
-                continue              # a stat-only git diff prints names and counts, not content
+            if exe == "git" and any(x in DIFF_STAT_FLAGS for x in w) and not any(x in ("-p", "-u", "--patch", "--unified") or re.fullmatch(r"-U\d*|--unified=\d+", x) for x in w[1:]):
+                continue              # a stat-only git diff prints names and counts, not content (with -p/-u/--patch it prints both; review r2 DISS-002)
             toks = segment_tokens(seg, vars_, cwd, ws)
             pr_ops = [k_ for k_, (v, c) in enumerate(toks) if c[0] == "pr" and c[1] in ("head", "base")
                       and not v.endswith("head.diff")]
diff --git a/evals/tests/ablation-grade.bats b/evals/tests/ablation-grade.bats
index 0d3b0ce1..1116e74a 100644
--- a/evals/tests/ablation-grade.bats
+++ b/evals/tests/ablation-grade.bats
@@ -1537,7 +1537,7 @@ CASES
   [ "$(G '.oracle_exposed_defects, .oracle_exposed_events, .corpus_sha256' | tr '\n' ' ')" = "null null null " ]
 }
 
-@test "AG-52 oracle redirections (review r1 DISS-001/C-001): 2>&1 | wc -l, &>/dev/null, 2>&1 | grep -i -c, git diff --stat print nothing; 2>&1 | head still exposes" {
+@test "AG-52 oracle redirections (review r1 DISS-001/C-001, r2 DISS-002/C-004/C-008): 2>&1 | wc -l, &>/dev/null, grep -i -c, |& wc, egrep -c, grep -L, git diff --stat print nothing; 2>&1 | head and --stat -p expose" {
   make_oracle
   local i=0 cmd res want
   while IFS=$'\t' read -r cmd res want; do
@@ -1552,14 +1552,18 @@ diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh &>/dev/null; echo rc=$?	r
 diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh 2>&1 | grep -i -c planted	1	diff= read= unknown= exposed=
 diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh 2>/dev/null | grep --count '^>'	2	diff= read= unknown= exposed=
 git diff --no-index --stat pr/head/.claude/scripts/g.sh .claude/scripts/g.sh	 .claude/scripts/g.sh | 2 +-\n 1 file changed	diff= read= unknown= exposed=
+diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh |& wc -l	4	diff= read= unknown= exposed=
+diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh 2>&1 | egrep -c planted	1	diff= read= unknown= exposed=
+diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh 2>&1 | grep -L nothing	(standard input)	diff= read= unknown= exposed=
 diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh 2>&1 | head -40	20c20\n<   if [ -n "$OPT_VALUE_LONG" ]; then echo planted-site; fi\n---\n> later	diff=d1 read= unknown= exposed=d1
+git diff --no-index --stat -p pr/head/.claude/scripts/g.sh .claude/scripts/g.sh	 g.sh | 2 +-\n@@ -20 +20 @@\n-  if [ -n "$OPT_VALUE_LONG" ]; then echo planted-site; fi\n+ later	diff=d1 read= unknown= exposed=d1
 CASES
 }
 
 @test "AG-53 KF-046 class 7 (review r1 DISS-C-002): a bare repo-name token as a whole line (a for-list continuation, a list entry) is never exempt" {
   RD="$T/k3"; mkdir -p "$RD/sandbox" "$RD/transcripts" "$RD/eval" "$RD/snapshots"; echo '{}' > "$RD/snapshots/index.json"; : > "$RD/sandbox/review.md"
   RTASK=review-r18 RROOT=ablation-2.0-replication
-  tool_use "$RD" REVIEW Bash "$(bash_in "$(printf 'for r in \\\\\n  0xHoneyJar/loa\ndo gh api repos/$r/contents; done')")"
+  tool_use "$RD" REVIEW Bash "$(bash_in "$(printf 'for r in \\\n  0xHoneyJar/loa\ndo gh api repos/$r/contents; done')")"   # one backslash before the newline: a real continuation (review r2 DISS-C-009)
   rgrade "$RD"
   [ "$status" -eq 0 ]
   [ "$(G '.contaminated.pattern')" = repo_name ]
~~~~

## I07 — fix-commit — 2026-10-20

- reference: cddec3677a58
- files: evals/harness/ablation-grade.sh,evals/tests/ablation-grade.bats

Summary:

fix(cycle-131): sprint-263 audit round r1c — executed probe lines never class-7 exempt, no workspace pr/head fallback, bounded detector work, one validated corpus-hash open Audit dissent run 1 on the sprint diff (4 findings: 1 HIGH, 2 MEDIUM, 1 LOW; DEC-0644): - ablation-grade.sh: a Bash logical line (heredoc bodies removed) that holds the repo name and a network- or VCS-capable executable word (…

Evidence (first 200 of 252 lines):

~~~~diff
commit cddec3677a58f26e8986f034419f03f559782648
Date: 2026-10-20T13:13:11+11:00

fix(cycle-131): sprint-263 audit round r1c — executed probe lines never class-7 exempt, no workspace pr/head fallback, bounded detector work, one validated corpus-hash open

Audit dissent run 1 on the sprint diff (4 findings: 1 HIGH, 2 MEDIUM, 1 LOW; DEC-0644):
- ablation-grade.sh: a Bash logical line (heredoc bodies removed) that holds the repo name and a network- or
  VCS-capable executable word (git, gh, curl, wget, pip, npm, npx, ssh, scp, nc, docker, rsync, python -c …) is
  never KF-046 class 7 exempt — pr-13 and pr-16 carry `curl … 0xHoneyJar/loa … | bash` lines the old rule would
  have licensed; quoting such a line in notes stays PR content (AG-54). Every agent-controlled dimension of the
  oracle detector is bounded (for-list 64, expansion 256, segment 64 KB, word 4,096 / 512 per segment, result
  lines clipped, difflib skipped above 20,000 lines → grade.json oracle_scan_skipped) (AG-55). corpus_sha256
  hashes the bytes of one O_NOFOLLOW open with an fstat regular-file and size check.
- recall-vs-defects.sh: the $workspace/pr/head fallback is gone unless EVAL_ALLOW_WORKSPACE_HEAD=1;
  details.head_dir_source ∈ env|fixture|workspace|none; above 5,000 headers the ±20 fallback replaces the scope
  map (RG-44).
- sprint.md: Sprint 1 deliverables, criteria and tasks ticked (two criteria annotated: FR-1 AC 4 PARTIAL by
  DEC-0632; FR-3 AC 3 is the Sprint 3 read).
- evals/tests 516/516; the 36-run re-grade on this grader: 36/36 regression, 0 rows changed (as after r1a, r1b).
- Review APPROVED (engineer-feedback.md), audit APPROVED after this round (auditor-sprint-feedback.md).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/evals/harness/ablation-grade.sh b/evals/harness/ablation-grade.sh
index 7c6765a2..9ea0f455 100755
--- a/evals/harness/ablation-grade.sh
+++ b/evals/harness/ablation-grade.sh
@@ -1807,7 +1807,7 @@ def check_value(tool, field, val, roots):
     if "grimoires/loa/evals/ablation-2.0" in val:
         return "suite_path"
     if "0xhoneyjar/loa" in low:
-        ex = repo_name_exempt(val)
+        ex = repo_name_exempt(val, tool)
         if ex is None:
             return "repo_name"
         EXEMPT_BUF.extend(ex)   # KF-046 class 7: every occurrence is PR content; the scan goes on
@@ -1979,11 +1979,31 @@ def fixture_token_lines():
     return out
 
 
-def repo_name_exempt(val):
-    """→ [(fixture source, fixture line)] when every repo-name occurrence in val is PR content, else None"""
+NET_EXE = {"git", "gh", "curl", "wget", "pip", "pip3", "npm", "npx", "pnpm", "yarn", "ssh", "scp", "sftp", "nc", "ncat",
+           "telnet", "docker", "podman", "rsync", "svn", "hg", "aria2c", "http", "https", "fetch", "gem", "cargo", "go"}
+
+
+def executes_network(line):
+    """a Bash logical line that could reach the network or a VCS remote: a word whose basename is a network- or
+    VCS-capable executable, or python/node/perl/ruby with an inline program (audit r1 DISS-C-001)"""
+    words = re.findall(r"[A-Za-z0-9_./-]+", line)
+    base = [w.rsplit("/", 1)[-1] for w in words]
+    if any(b in NET_EXE for b in base):
+        return True
+    return any(b in ("python", "python3", "node", "perl", "ruby") and ("-c" in words or "-e" in words) for b in base)
+
+
+def repo_name_exempt(val, tool=None):
+    """→ [(fixture source, fixture line)] when every repo-name occurrence in val is PR content, else None.
+    A Bash command is executed text: an occurrence on a logical line that could reach the network or a VCS remote
+    is never exempt, whatever the fixture holds (pr-13 and pr-16 carry `curl … 0xHoneyJar/loa … | bash` lines)."""
     fl = fixture_token_lines()
     if not fl:
         return None
+    if tool == "Bash":   # the executed text is the command with its heredoc bodies removed (a quoted line in notes is not run)
+        for line in strip_heredocs(val).replace("\\\n", " ").split("\n"):
+            if REPO_TOKEN.search(line) and executes_network(line):
+                return None
     hits = []
     for line in val.replace("\\\n", " ").split("\n"):   # a backslash-continued command is one logical line
         for m in REPO_TOKEN.finditer(line):
@@ -2009,11 +2029,25 @@ def corpus_sha256(t):
     """sha256 of the review corpus's SHA256SUMS (the directory above the key's manifests/), null when absent"""
     import hashlib
     p = os.path.join(os.path.dirname(os.path.dirname(t.key_path)), "SHA256SUMS")
-    text = read_regular(p, READ_CAP, whole=True)
-    if text is None:
+    try:   # one O_NOFOLLOW open, fstat regular + size bound, hash those bytes (audit r1 DISS-C-004)
+        fd = os.open(p, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | getattr(os, "O_CLOEXEC", 0))
+    except OSError:
         return None
-    with open(p, "rb") as f:
-        return hashlib.sha256(f.read()).hexdigest()
+    try:
+        st = os.fstat(fd)
+        if not stat.S_ISREG(st.st_mode) or st.st_size > READ_CAP:
+            return None
+        h = hashlib.sha256()
+        while True:
+            b = os.read(fd, 1 << 20)
+            if not b:
+                break
+            h.update(b)
+        return h.hexdigest()
+    except OSError:
+        return None
+    finally:
+        os.close(fd)
 
 
 # ------------------------------------------------------------------ oracle detector (1.3.0, D-1.3, KF-049)
@@ -2056,6 +2090,9 @@ def corpus_sha256(t):
 # A LOWER BOUND, like the contamination scan: a paraphrase, a copy made by a program and read later, or a
 # path built at run time is not seen.
 ORACLE_PHASES = ("BARE", "REVIEW", "AUDIT")
+# bounds on agent-authored input (audit r1 DISS-C-003): every dimension the graded session controls is capped
+FORLIST_CAP, EXPAND_CAP, SEG_CAP, WORD_CAP, WORDS_CAP, LINE_CAP, LINES_CAP, DIFF_LINES_CAP = 64, 256, 65536, 4096, 512, 4096, 20000, 20000
+ORACLE_SKIPPED = []   # answer paths whose later-line map was skipped (a side over DIFF_LINES_CAP lines)
 DIFF_EXE = {"diff", "sdiff", "comm"}
 READ_EXE = {"cat", "sed", "awk", "grep", "head", "tail", "less", "python3"}
 ANSWER_TOP = ".claude/"
@@ -2228,6 +2265,8 @@ def expand(tok, vars_):
             changed = True
             for v in vars_[name]:
                 nxt.append(o[:m.start()] + v + o[m.end():])
+            if len(nxt) > EXPAND_CAP:
+                return []             # a for-list product past the cap resolves nothing (audit r1 DISS-C-003)
         outs = nxt
         if not changed:
             break
@@ -2264,13 +2303,20 @@ def ws_targets(rel, answer, directory_ok):
 
 
 def segment_tokens(seg, vars_, cwd, ws):
-    """every path-shaped token of a segment (inside process substitutions too), expanded and classified"""
+    """every path-shaped token of a segment (inside process substitutions too), expanded and classified;
+    bounded against agent-authored bulk (audit r1 DISS-C-003): a segment over SEG_CAP bytes, a word over
+    WORD_CAP characters or past the WORDS_CAP-th word is not read"""
     out = []
-    for m in PATHISH.finditer(seg):
-        for v in expand(m.group(0), vars_):
-            c = classify(v, cwd, ws)
-            if c is not None:
-                out.append((v, c))
+    if len(seg) > SEG_CAP:
+        return out
+    for word in seg.split()[:WORDS_CAP]:
+        if len(word) > WORD_CAP:
+            continue
+        for m in PATHISH.finditer(word):
+            for v in expand(m.group(0), vars_):
+                c = classify(v, cwd, ws)
+                if c is not None:
+                    out.append((v, c))
     return out
 
 
@@ -2362,6 +2408,9 @@ def oracle_scan(t, run_dir):
         if not live[f] or hd is None:
             continue
         hl, cl = hd.split("\n"), cur.split("\n")
+        if len(hl) > DIFF_LINES_CAP or len(cl) > DIFF_LINES_CAP:
+            ORACLE_SKIPPED.append(f)  # no later-line map for a huge copy: the read form cannot fire for it (audit r1 DISS-C-003)
+            continue
         for pos, sites, _mm in by_file[f]:
             near_text[(f, pos)] = [hl[L - 1].strip() for s_ in sites for L in range(s_ - 3, s_ + 4)
                                    if 1 <= L <= len(hl) and len(hl[L - 1].strip()) >= 8]
@@ -2415,7 +2464,7 @@ def oracle_scan(t, run_dir):
                     i0, plan = uses.pop(blk["tool_use_id"])
                     if blk.get("is_error") is True:
                         continue          # the tool failed (a refused command, a hook block): nothing printed
-                    res = result_text(blk)
+                    res = "\n".join(l[:LINE_CAP] for l in result_text(blk).split("\n")[:LINES_CAP])
                     dtargets = sorted({f for how, f in plan if how.startswith("diff") and live.get(f)})
                     rtargets = sorted({f for how, f in plan if how == "read" and live.get(f)})
                     if dtargets and res.strip():
@@ -2490,7 +2539,7 @@ def oracle_plan(tool, inp, ws, answer):
             words = []
             for x in m.group(2).split():
                 words += expand(x.strip("'\""), vars_)
-            vars_[m.group(1)] = words
+            vars_[m.group(1)] = words[:FORLIST_CAP]
             continue
         if not w:
             continue
@@ -2572,7 +2621,7 @@ def grade(t, run_dir, frozen):
          "diff_lines": None, "files_changed": None, "symlinks_dropped": 0, "harness_files_removed": 0,
          "oversized_files_skipped": 0, "history_probes": 0, "heredoc_interpreters": 0, "contaminated": None,
          "contamination_exempt": [], "oracle_exposed_defects": None, "oracle_exposed_unknown": None,
-         "oracle_exposed_events": None, "oracle_exposed_by_form": None, "corpus_sha256": None}
+         "oracle_exposed_events": None, "oracle_exposed_by_form": None, "oracle_scan_skipped": None, "corpus_sha256": None}
     acc = {"review": None, "audit": None}
     SNAPSHOT_LINKS_DROPPED[0] = 0
     OVERSIZED[0] = 0
@@ -2652,8 +2701,10 @@ def grade(t, run_dir, frozen):
             g["symlinks_dropped"] = copy_tree(os.path.join(sb, "pr"), os.path.join(grading, "pr"))
         g["recall"], g["false_positives"] = grade_recall(t, run_dir, grading)
         g["corpus_sha256"] = corpus_sha256(t)
+        ORACLE_SKIPPED.clear()
         (g["oracle_exposed_defects"], g["oracle_exposed_unknown"], g["oracle_exposed_events"],
          g["oracle_exposed_by_form"]) = oracle_scan(t, run_dir)
+        g["oracle_scan_skipped"] = sorted(set(ORACLE_SKIPPED))
         key_cr = any((d.get("severity") or "").lower() in ("high", "critical") for d in t.key.get("defects") or [])
         for gate, v in (("review", v_review), ("audit", v_audit)):
             if v is not None:
diff --git a/evals/tests/ablation-grade.bats b/evals/tests/ablation-grade.bats
index 1116e74a..7100f899 100644
--- a/evals/tests/ablation-grade.bats
+++ b/evals/tests/ablation-grade.bats
@@ -1576,6 +1576,52 @@ CASES
~~~~

## I08 — fix-commit — 2026-10-20

- reference: c0d429074f26
- files: evals/harness/pipeline-run.sh,evals/tests/pipeline-run.bats

Summary:

fix(cycle-131): sprint-264 review round r2a — eval_only derived from oracle_open and type-checked in pipeline-run; the report names evaluation-only arms Review dissent run 1 on e93a040a..0281ea57 (4 advisories, 0 blocking): - pipeline-run.sh treats an arm whose toggles set oracle_open: true as evaluation-only whatever the suite says, and refuses a present eval_only that is not a JSON boolean (DIS…

Evidence:

~~~~diff
commit c0d429074f263b22f3643eb44bfd4a38eac7b6bf
Date: 2026-10-20T14:49:27+11:00

fix(cycle-131): sprint-264 review round r2a — eval_only derived from oracle_open and type-checked in pipeline-run; the report names evaluation-only arms

Review dissent run 1 on e93a040a..0281ea57 (4 advisories, 0 blocking):
- pipeline-run.sh treats an arm whose toggles set oracle_open: true as evaluation-only whatever the suite says, and
  refuses a present eval_only that is not a JSON boolean (DISS-C-002; pipeline-run.bats case added).
- ablation-report.py prints 'Evaluation-only arms (not components): <arm> (<n> rows) …' under the decisions and
  records them in report.json (DISS-C-004; AR-12 asserts the line).
- DISS-C-001 (task files not in the dissent diff) is the dissent driver's path exclusion, not a missing commit;
  DISS-C-003 (hand-maintained toggle vocabulary) → bead bd-gdl5s.
- KF-051 (Fable refusal fallback mid-phase) recorded; DEC-0646, DEC-0647.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/evals/harness/pipeline-run.sh b/evals/harness/pipeline-run.sh
index 12676a49..19548de6 100755
--- a/evals/harness/pipeline-run.sh
+++ b/evals/harness/pipeline-run.sh
@@ -138,7 +138,8 @@
 # when the run stopped before materialisation). `.claude/` itself is covered by
 # took-effect.sh integrity_clean.
 #
-# eval_only arms (cycle-131 FR-5): an arm declaring `eval_only: true` (a1_full_openmount) is
+# eval_only arms (cycle-131 FR-5): an arm declaring `eval_only: true` (a1_full_openmount), or whose
+# toggles set `oracle_open: true`, is
 # refused — exit 2, `refused: arm '<id>': eval_only arm outside an evaluation batch`, before the
 # run directory exists, so no pipeline.json and no infrastructure_error is ever written — unless
 # LOA_ABLATION_BATCH_CONTEXT=1 (exactly 1). run-ablation.sh exports it to every trial it launches
@@ -255,7 +256,15 @@ fi
 SUITE_TOGGLES="$(jq -c '.toggles // {}' <<<"$ARM_DEF")"
 # eval_only (cycle-131 FR-5): refused before anything is created, dry run included, unless the
 # runner marks the batch context; no pipeline.json, so no infrastructure_error row is possible
-EVAL_ONLY=false; [[ "$(jq -r '.eval_only // false' <<<"$ARM_DEF")" == true ]] && EVAL_ONLY=true
+# eval_only is derived from the property it protects as well as from the flag (review r1 DISS-C-002): an arm whose
+# toggles open the mount (oracle_open: true) is evaluation-only whatever the suite says; a present eval_only that is
+# not a JSON boolean is refused rather than read as false
+case "$(jq -r 'if has("eval_only") then (.eval_only | type) else "absent" end' <<<"$ARM_DEF")" in
+  absent|boolean) ;;
+  *) echo "pipeline-run.sh: refused: arm '$ARM': eval_only must be a JSON boolean (true|false)" >&2; exit 2 ;;
+esac
+EVAL_ONLY=false
+[[ "$(jq -r '(.eval_only == true) or (.toggles.oracle_open == true)' <<<"$ARM_DEF")" == true ]] && EVAL_ONLY=true
 if [[ "$EVAL_ONLY" == true && "${LOA_ABLATION_BATCH_CONTEXT:-}" != 1 ]]; then
   echo "pipeline-run.sh: refused: arm '$ARM': eval_only arm outside an evaluation batch (run-ablation.sh exports LOA_ABLATION_BATCH_CONTEXT=1 to its trials)" >&2
   exit 2
diff --git a/evals/tests/pipeline-run.bats b/evals/tests/pipeline-run.bats
index fc4d0145..2c5b7966 100644
--- a/evals/tests/pipeline-run.bats
+++ b/evals/tests/pipeline-run.bats
@@ -1243,6 +1243,20 @@ dryrun_rc() {  # dryrun_rc <arm> — the review-catch dry run (no run dir)
   [ "$status" -eq 0 ]
 }
 
+@test "eval_only (review r1 DISS-C-002): an arm whose toggles open the mount is refused outside the batch context even without eval_only; a non-boolean eval_only is refused as malformed" {
+  c131_arms
+  unset LOA_ABLATION_BATCH_CONTEXT
+  yq -i '.arms += [{"id": "x_open", "label": "XO", "task_types": ["review-catch"], "toggles": {"oracle_open": true}, "took_effect": ["integrity_clean"]}]' "$T/suite.yaml"
+  dryrun_rc x_open
+  [ "$status" -eq 2 ]
+  grep -q "refused: arm 'x_open': eval_only arm outside an evaluation batch" <<<"$output"
+  [ ! -e "$T/run" ]
+  yq -i '(.arms[] | select(.id == "a1_full_openmount") | .eval_only) = "yes"' "$T/suite.yaml"
+  LOA_ABLATION_BATCH_CONTEXT=1 dryrun_rc a1_full_openmount
+  [ "$status" -eq 2 ]
+  grep -q "eval_only must be a JSON boolean" <<<"$output"
+}
+
 @test "eval_only: inside the batch context (LOA_ABLATION_BATCH_CONTEXT=1) the open-mount arm runs REVIEW and AUDIT and completes" {
   c131_arms
   LOA_ABLATION_BATCH_CONTEXT=1 run_pr a1_full_openmount "$REVIEWC"
~~~~

## I09 — fix-commit — 2026-10-20

- reference: 798d88cfc920
- files: evals/harness/pipeline-run.sh,evals/tests/pipeline-run.bats

Summary:

fix(cycle-131): sprint-264 audit round r2b — toggles.oracle_open held to the JSON-boolean rule; the report derives evaluation-only status from the toggle and refuses an open oracle without the flag Audit dissent run on e93a040a..c0d42907 (2 MEDIUM, 1 LOW): - pipeline-run.sh refuses a present toggles.oracle_open that is not a JSON boolean, so the strict eval_only guard and the loose mount read can…

Evidence:

~~~~diff
commit 798d88cfc920a95ce896a527145b21ca72d0ab18
Date: 2026-10-20T15:01:43+11:00

fix(cycle-131): sprint-264 audit round r2b — toggles.oracle_open held to the JSON-boolean rule; the report derives evaluation-only status from the toggle and refuses an open oracle without the flag

Audit dissent run on e93a040a..c0d42907 (2 MEDIUM, 1 LOW):
- pipeline-run.sh refuses a present toggles.oracle_open that is not a JSON boolean, so the strict eval_only guard
  and the loose mount read can never disagree on a quoted "true" (DISS-C-001; pipeline-run.bats case).
- ablation-report.py: is_eval_only(a) = the flag or toggles.oracle_open is True; an open-oracle arm without
  eval_only: true raises Fail before any report is written (DISS-C-002; AR-12b).
- DISS-C-003 (inheritable batch-context env var) accepted as the designed accident guard → bead bd-st02i.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/evals/harness/pipeline-run.sh b/evals/harness/pipeline-run.sh
index 19548de6..92b0e4cf 100755
--- a/evals/harness/pipeline-run.sh
+++ b/evals/harness/pipeline-run.sh
@@ -263,6 +263,12 @@ case "$(jq -r 'if has("eval_only") then (.eval_only | type) else "absent" end' <
   absent|boolean) ;;
   *) echo "pipeline-run.sh: refused: arm '$ARM': eval_only must be a JSON boolean (true|false)" >&2; exit 2 ;;
 esac
+# the toggle that opens the mount is held to the same type rule, so the strict `== true` below and the mount
+# path's loose text read can never disagree on a quoted "true" (audit r1 DISS-C-001)
+case "$(jq -r 'if (.toggles // {}) | has("oracle_open") then (.toggles.oracle_open | type) else "absent" end' <<<"$ARM_DEF")" in
+  absent|boolean) ;;
+  *) echo "pipeline-run.sh: refused: arm '$ARM': toggles.oracle_open must be a JSON boolean (true|false)" >&2; exit 2 ;;
+esac
 EVAL_ONLY=false
 [[ "$(jq -r '(.eval_only == true) or (.toggles.oracle_open == true)' <<<"$ARM_DEF")" == true ]] && EVAL_ONLY=true
 if [[ "$EVAL_ONLY" == true && "${LOA_ABLATION_BATCH_CONTEXT:-}" != 1 ]]; then
diff --git a/evals/tests/pipeline-run.bats b/evals/tests/pipeline-run.bats
index 2c5b7966..72f4d1f5 100644
--- a/evals/tests/pipeline-run.bats
+++ b/evals/tests/pipeline-run.bats
@@ -1255,6 +1255,11 @@ dryrun_rc() {  # dryrun_rc <arm> — the review-catch dry run (no run dir)
   LOA_ABLATION_BATCH_CONTEXT=1 dryrun_rc a1_full_openmount
   [ "$status" -eq 2 ]
   grep -q "eval_only must be a JSON boolean" <<<"$output"
+  # a quoted "true" on the toggle is refused too (audit r1 DISS-C-001): the strict guard and the loose mount read never disagree
+  yq -i '(.arms[] | select(.id == "a1_full_openmount") | .eval_only) = true | (.arms[] | select(.id == "a1_full_openmount") | .toggles.oracle_open) = "true"' "$T/suite.yaml"
+  LOA_ABLATION_BATCH_CONTEXT=1 dryrun_rc a1_full_openmount
+  [ "$status" -eq 2 ]
+  grep -q "toggles.oracle_open must be a JSON boolean" <<<"$output"
 }
 
 @test "eval_only: inside the batch context (LOA_ABLATION_BATCH_CONTEXT=1) the open-mount arm runs REVIEW and AUDIT and completes" {
~~~~

## I10 — fix-commit — 2026-10-20

- reference: aac80f4cfea6
- files: evals/harness/ablation-grade.sh,evals/tests/ablation-grade.bats,evals/tests/fixtures/ablation-pipeline-stub.sh

Summary:

fix(cycle-131): PR #1286 Bridgebuilder round r4 — the closed mount refuses an unavailable fix commit (F001); grader 1.3.1 scans error-marked tool results (F002); 63 re-grades unchanged F001 (HIGH, accepted): `lib/sandbox-mount.sh overlay_answer_paths` exits 2 before writing anything when fixture.yaml's fix_commit is not in the source tree. Sprint 263 logged fix_commit_unavailable, overlaid the PR…

Evidence (first 200 of 213 lines):

~~~~diff
commit aac80f4cfea6c8e865ad194f713efd6cf1f8804d
Date: 2026-10-20T22:13:56+11:00

fix(cycle-131): PR #1286 Bridgebuilder round r4 — the closed mount refuses an unavailable fix commit (F001); grader 1.3.1 scans error-marked tool results (F002); 63 re-grades unchanged

F001 (HIGH, accepted): `lib/sandbox-mount.sh overlay_answer_paths` exits 2 before writing anything when
fixture.yaml's fix_commit is not in the source tree. Sprint 263 logged fix_commit_unavailable, overlaid the
PR paths only and `check_mount_closed` called the mount closed with the fix-only paths still at the later
copy. `check_mount_closed` and `took-effect.sh` rule oracle_closed now fail on overlay_fix_commit=unavailable.
Premise check: overlay_fix_commit=available on all 18 closed-mount cycle-131 runs, none on the 4 without a
fix commit — no recorded run took this path.

F002 (MEDIUM, accepted): grader 1.3.1. A differing diff exits 1 and Claude Code marks the result is_error
with the output after an "Exit code N" line; 1.3.0 skipped every such result. The detector now strips that
line and scans the rest: the diff form needs printed ranges near a planted site (no must_match-only credit
from an error result), the read form later-only text, and an error-marked section without ranges is never
oracle_exposed_unknown. Recall and contamination unchanged. Re-graded under 1.3.1, the 36 cycle-130 and
27 cycle-131 review-catch runs are identical on every oracle field, recall and contamination (63/63); the
26 error-marked results carrying diff ranges all compare pr/base with pr/head or read head.diff. The pinned
1.3.0 rows stay the main read (DEC-0648); the 1.3.1 grades are a labelled sensitivity
(~/.cache/loa/cycle-131/regrade-131/compare.tsv).

Tests: sandbox-mount.bats (the unavailable-commit test now expects the refusal, an untouched sandbox and a
failing check), took-effect.bats (overlay_fix_commit=unavailable FAIL clause), ablation-grade.bats (AG-48
loses the is_error row; AG-56 covers error-marked differing diffs, a hook block, a tool error, unranged
text, the read form and the unchanged non-error unknown case; version asserts 1.3.1).

The check keeps its evidence rule only (overlay_fix_commit=unavailable fails); a recomputation rule was dropped
because a check-time repository without the fix commit already fails clause (a) on the path count, and would
have turned a shallow post-run clone into a false FAIL. The runner tests' pipeline stub overlays from a
fixture copy without fix_commit when its throwaway source tree lacks the commit (RAB-c131-2 on pr-17/pr-18).

Also: grimoires/loa/REPO-MAP.md regenerated (repo-map-gen.sh) — CI's BATS Tests on a3289c2b failed only on
`repo-map: --validate passes against the committed REPO-MAP.md` (stale after the Sprint 263 edits to
adversarial-review.sh and its resources; the separate REPO-MAP Drift Gate workflow had passed).

Records: DEC-0655; KF-049 attempt row; CHANGELOG "### Fixed"; suite README. Bead bd-cxdsm.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/evals/harness/ablation-grade.sh b/evals/harness/ablation-grade.sh
index 9ea0f455..a70e62eb 100755
--- a/evals/harness/ablation-grade.sh
+++ b/evals/harness/ablation-grade.sh
@@ -232,6 +232,12 @@
 #    (1.3.0: the oracle detector below; null for build tasks), corpus_sha256 (1.3.0: sha256 of the review
 #    corpus SHA256SUMS; null for build tasks or without the file); review-catch recall also carries
 #    recall_pm3, missed_pm3, recall_pm3_v1, missed_pm3_v1, v1_manifest, credits_function_only, rule}
+# grader 1.3.1 (cycle-131 PR #1286 Bridgebuilder F002): the oracle detector scans error-marked tool results. A
+# diff exits 1 on differences and Claude Code then marks the result is_error with the output after an "Exit code N"
+# line, so 1.3.0 never saw a differing diff's hunks. 1.3.1 strips that line and scans the rest: the diff form
+# needs printed ranges near a site (must_match alone does not count there), the read form later-only text; an
+# error-marked section without ranges is never exposed_unknown (a refusal or a hook block names the command's
+# paths and prints no diff). Recall, contamination and every other field are unchanged from 1.3.0.
 # grader 1.3.0 (cycle-131 Sprint 263 Tasks 1.3, 1.4; DEC-0615, DEC-0616, DEC-0617): three recall results
 # (the same-scope rule, recall-vs-defects.sh 1.3.0), numeric dissent anchors, corpus_sha256, the oracle
 # detector (diff and read forms, KF-049) and the KF-046 class 7 line-level exemption. recall_pm3_v1 equals
@@ -346,7 +352,7 @@ import argparse, configparser, difflib, filecmp, fnmatch, json, os, re, shlex, s
 # TERM; names carry this pid, so a later grade never collides)
 signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(143))
 
-GRADER_VERSION = "1.3.0"
+GRADER_VERSION = "1.3.1"
 SCRIPT_DIR, REPO_ROOT, DOCKER_DEFAULT = sys.argv[1], sys.argv[2], sys.argv[3]
 SPRINT = "sprint-1"
 _t = os.environ.get("LOA_EVAL_GRADE_TIMEOUT_S", "")
@@ -2100,6 +2106,7 @@ SEG_KEYWORDS = {"do", "then", "else", "elif", "if", "while", "until", "{", "(",
 PATHISH = re.compile(r"[A-Za-z0-9_./@%+,:=~$-]*[A-Za-z0-9_./@%+:~$-]")
 HUNK_U = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", re.M)
 HUNK_N = re.compile(r"^(\d+)(?:,(\d+))?([acd])(\d+)(?:,(\d+))?\s*$", re.M)
+EXIT_CODE_LINE = re.compile(r"\AExit code \d+\n?")   # 1.3.1: Claude Code's preamble on a failed Bash tool result
 ERR_LINE = re.compile(r"^(?:diff|sdiff|comm|git|cat|grep|sed|head|tail|awk|less):|^(?:fatal|error|warning):|"
                       r"No such file|Is a directory|hook error|BLOCKED|^\s*$|^\s*(?:rc|exit)\s*=\s*\d+\s*$")
 DIFF_BODY = re.compile(r"^[<>+\- @\\0-9]|^---$")
@@ -2462,9 +2469,14 @@ def oracle_scan(t, run_dir):
                         uses[blk["id"]] = (i, plan)
                 elif ev.get("type") == "user" and blk.get("type") == "tool_result" and blk.get("tool_use_id") in uses:
                     i0, plan = uses.pop(blk["tool_use_id"])
-                    if blk.get("is_error") is True:
-                        continue          # the tool failed (a refused command, a hook block): nothing printed
-                    res = "\n".join(l[:LINE_CAP] for l in result_text(blk).split("\n")[:LINES_CAP])
+                    # 1.3.1 (PR #1286 F002): a failed tool (diff exits 1 on differences, a refusal, a hook block) still
+                    # carries its output after an "Exit code N" line; scan it, but no unknown and no must_match-only
+                    # credit from it — a refusal names the command's paths without printing a diff
+                    errored = blk.get("is_error") is True
+                    res = result_text(blk)
+                    if errored:
+                        res = EXIT_CODE_LINE.sub("", res, count=1)
+                    res = "\n".join(l[:LINE_CAP] for l in res.split("\n")[:LINES_CAP])
                     dtargets = sorted({f for how, f in plan if how.startswith("diff") and live.get(f)})
                     rtargets = sorted({f for how, f in plan if how == "read" and live.get(f)})
                     if dtargets and res.strip():
@@ -2477,7 +2489,7 @@ def oracle_scan(t, run_dir):
                                 for pos, sites, mm in by_file.get(f, []):
                                     ranged = any(near(sites, lo, hi) for lo, hi in rs)
                                     own = any(x in sec for x in near_text.get((f, pos), []))
-                                    if (ranged and own) or (mm and mm in sec):
+                                    if (ranged and own) or (not errored and mm and mm in sec):
                                         note(label, i0, "diff", f, pos)
                         for f, secs in secs_by.items():
                             for sec in secs:
@@ -2487,10 +2499,10 @@ def oracle_scan(t, run_dir):
                                 rs = ranges_of(sec, plan_sides(plan, f))
                                 hit_any = False
                                 for pos, sites, mm in by_file.get(f, []):
-                                    if any(near(sites, lo, hi) for lo, hi in rs) or (mm and mm in sec):
+                                    if any(near(sites, lo, hi) for lo, hi in rs) or (not errored and mm and mm in sec):
                                         note(label, i0, "diff", f, pos)
                                         hit_any = True
-                                if not rs and not hit_any:
+                                if not rs and not hit_any and not errored:
                                     for pos, _s, _m in by_file.get(f, []):
                                         note(label, i0, "exposed_unknown", f, pos)
                     single = len({f for how, f in plan if how == "read"}) == 1
diff --git a/evals/tests/ablation-grade.bats b/evals/tests/ablation-grade.bats
index 7100f899..0f778863 100644
--- a/evals/tests/ablation-grade.bats
+++ b/evals/tests/ablation-grade.bats
@@ -1146,7 +1146,7 @@ bash_case() {
   [ "$status" -eq 0 ]
   [ "$(G '.contaminated')" = null ]
   [ "$(G '.heredoc_interpreters')" = 5 ]
-  [ "$(G '.grader_version')" = 1.3.0 ]
+  [ "$(G '.grader_version')" = 1.3.1 ]
 }
 
 # --- grader 1.2.12: the collision removal reaches only pytest-collectable, package-less test modules --------------
@@ -1416,7 +1416,7 @@ OX() { jq -r '"diff=\(.oracle_exposed_by_form.diff | join(",")) read=\(.oracle_e
   printf 'pr/head/.claude/scripts/g.sh:26 the option guard\n' > "$RD/sandbox/review.md"   # 6 from O1, inside check()
   grade "$RD" rc-o
   [ "$status" -eq 0 ]
-  [ "$(G '.grader_version')" = 1.3.0 ]
+  [ "$(G '.grader_version')" = 1.3.1 ]
   [ "$(G '.recall | "\(.recall) \(.recall_pm3) \(.recall_pm3_v1) \(.v1_manifest) \(.rule)"')" = "0.3333 0.0 0.0 false pm3_or_same_function" ]
   [ "$(G '.recall | "\(.credits_function_only | join(",")) \(.missed | join(",")) \(.missed_pm3 | join(",")) \(.missed_pm3_v1 | join(","))"')" = "d1 d2,d3 d1,d2,d3 d1,d2,d3" ]
   [ "$(G '.recall.defects_caught')" = 1 ]
@@ -1479,7 +1479,7 @@ CASES
   [ "$(G '.oracle_exposed_events | length')" = 0 ]
 }
 
-@test "AG-48 oracle non-hits: diff -q, --brief, the word head.diff, cat pr/head.diff, a diff piped to wc or grep -c, >/dev/null, an is_error result, pr/ vs pr/" {
+@test "AG-48 oracle non-hits: diff -q, --brief, the word head.diff, cat pr/head.diff, a diff piped to wc or grep -c, >/dev/null, pr/ vs pr/" {
   make_oracle
   local i=0 cmd res err
   while IFS=$'\t' read -r cmd res err; do
@@ -1497,12 +1497,46 @@ diff pr/head.diff .claude/scripts/g.sh	20c20	false
 diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh | wc -l	4	false
 diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh | grep -c '^[<>]'	3	false
 diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh >/dev/null; echo rc=$?	rc=1	false
-diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh	20c20\n< a\n---\n> b	true
 diff pr/base/.claude/scripts/g.sh pr/head/.claude/scripts/g.sh	20c20\n< a\n---\n> b	false
 cat > /tmp/notes.md <<'EOF'\ndiff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh\nEOF	20c20	false
 CASES
 }
 
+@test "AG-56 grader 1.3.1 error-marked results (PR #1286 F002): a differing diff (exit 1) exposes in normal and unified form, so does a read; a refusal, a tool error or unranged text naming the paths is neither a hit nor unknown" {
+  make_oracle
+  local i=0 cmd res want
+  while IFS=$'\t' read -r cmd res want; do
+    i=$((i + 1)); RD="$T/e$i"; make_orun "$RD"; sysinit "$RD" REVIEW
+    tu "$RD" REVIEW "e$i" Bash "$(bash_in "$cmd")" "$(printf '%b' "$res")" true
+    grade "$RD" rc-o
+    [ "$status" -eq 0 ]
+    [ "$(G '.grader_version')" = 1.3.1 ]
+    [ "$(OX)" = "$want" ] || { echo "case $i ($cmd): $(OX) want $want"; return 1; }
+  done <<'CASES'
+diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh	Exit code 1\n20c20\n< a\n---\n> b	diff=d1 read= unknown= exposed=d1
+diff -u pr/head/.claude/scripts/g.sh .claude/scripts/g.sh	Exit code 1\n--- pr/head/.claude/scripts/g.sh\n+++ .claude/scripts/g.sh\n@@ -20 +20 @@\n-a\n+b	diff=d1 read= unknown= exposed=d1
+diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh	Exit code 2\nBLOCKED by hook FR-9: diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh compares the mount	diff= read= unknown= exposed=
+diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh	Exit code 2\ndiff: .claude/scripts/g.sh: Permission denied	diff= read= unknown= exposed=
+diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh	Exit code 1\nleft text | right text	diff= read= unknown= exposed=
+diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh	Exit code 1\nrefused: the sandbox forbids comparing .claude/scripts/g.sh with pr/head/.claude/scripts/g.sh\nif [ -n "$OPT_VALUE_LONG" ]; then echo planted-site; fi	diff= read= unknown= exposed=
+CASES
+  # the read form on an error-marked result
+  RD="$T/er"; make_orun "$RD"; sysinit "$RD" REVIEW
+  tu "$RD" REVIEW er Bash "$(bash_in 'cat .claude/scripts/g.sh; false')" "$(printf 'Exit code 1\n%s\n' "$LATER20")" true
+  grade "$RD" rc-o
+  [ "$(OX)" = "diff= read=d1 unknown= exposed=d1" ]
+  # the same unranged text on a result not marked as an error is still unknown (unchanged from 1.3.0)
+  RD="$T/eu"; make_orun "$RD"; sysinit "$RD" REVIEW
+  tu "$RD" REVIEW eu Bash "$(bash_in 'diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh')" "left text | right text" false
+  grade "$RD" rc-o
+  [ "$(OX)" = "diff= read= unknown=d1,d2 exposed=" ]
+  # the event record names the error-marked result like any other
+  RD="$T/ee"; make_orun "$RD"; sysinit "$RD" AUDIT
+  tu "$RD" AUDIT ee Bash "$(bash_in 'diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh')" "$(printf 'Exit code 1\n20c20\n< a\n---\n> b')" true
+  grade "$RD" rc-o
+  [ "$(G '.oracle_exposed_events[0] | "\(.phase) \(.event) \(.how) \(.path)"')" = "AUDIT 2 diff .claude/scripts/g.sh" ]
+}
+
 @test "AG-49 oracle read form: a later-only line near a site in a Bash read or a Read result exposes; the PR copy, a line far from every site and a closed mount do not" {
   make_oracle
   RD="$T/r1"; make_orun "$RD"; sysinit "$RD" REVIEW
diff --git a/evals/tests/fixtures/ablation-pipeline-stub.sh b/evals/tests/fixtures/ablation-pipeline-stub.sh
index 092c8d41..76a5fb8b 100755
--- a/evals/tests/fixtures/ablation-pipeline-stub.sh
+++ b/evals/tests/fixtures/ablation-pipeline-stub.sh
@@ -109,6 +109,14 @@ if [[ "$KIND" == review-catch && "$(jq -r '.toggles.loa_mount' <<<"$DEF")" != fa
    && [[ "$MODE" != bad_overlay ]]; then
~~~~
