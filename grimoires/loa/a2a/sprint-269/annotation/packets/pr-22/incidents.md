# Incidents — pr-22

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
- files: .claude/loa/CLAUDE.loa.md

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

## I04 — kf — 2026-10-19

- reference: KF-050
- files: evals/harness/lib/sandbox-mount.sh

Summary:

## KF-050: Closed-mount overlay import skew: mounted cheval ImportError when a fix-commit path outside the PR is rewound beside pinned importers (pr-12) **Status**: OPEN — design hazard; pr-12 re-grade-only, no batch runs on it **Feature**: evals/harness/lib/sandbox-mount.sh overlay_answer_paths (cycle-131 FR-1 closed mount) **Symptom**: Under the closed mount (head or base mode) the sandbox's .c…

Evidence:

~~~~~text
~~~~markdown
## KF-050: Closed-mount overlay import skew: mounted cheval ImportError when a fix-commit path outside the PR is rewound beside pinned importers (pr-12)

**Status**: OPEN — design hazard; pr-12 re-grade-only, no batch runs on it
**Feature**: evals/harness/lib/sandbox-mount.sh overlay_answer_paths (cycle-131 FR-1 closed mount)
**Symptom**: Under the closed mount (head or base mode) the sandbox's .claude/adapters cheval raises ImportError: cannot import name 'private_workspace_base' from 'loa_cheval.providers.headless_cli'; every dissent voice fails on that PR (dissent_absent_gates = review,audit, infrastructure reason)
**First observed**: 2026-10-19 cycle-131 Sprint 263, lead probe overlay-probe.sh on pr-12 before the Task 1.11 smoke
**Recurrence count**: 1
**Current workaround**: None inside the overlay rule. Keep the affected PR out of closed-mount batches (pr-12 is re-grade-only, DEC-0611/DEC-0631); read its smoke row as a predicted infrastructure effect. Candidate: a pre-launch mount_cheval=ok|broken:<reason> evidence line (bead bd-56nn6)
**Upstream issue**: bead bd-56nn6
**Related visions / lore**: KF-049 (the oracle the closed mount closes), DEC-0622 (head-mode overlay), DEC-0630 (fix-commit paths at head_commit), DEC-0631

### Attempts

| Date | What we tried | Outcome | Evidence |
|------|---------------|---------|----------|
| 2026-10-19 | overlay-probe.sh head and base on pr-12, pr-13, pr-18 against checkout 7600bd7d; python import of loa_cheval.providers from the overlaid tree | pr-12 ImportError in both modes; pr-13 and pr-18 import cleanly; symbol introduced 8d1a8cea (2026-10-04) between pr-12 head 6c887887 and fix 51d7a1ff | 7600bd7d; NOTES 2026-10-19T07:04:12Z; DEC-0631 |

### Reading guide

Mechanism: a fix-commit path OUTSIDE the PR is written at the PR's head_commit, but pinned files that changed between head_commit and the pin may import symbols that only the fixed version exports. Check: git log -S'<missing symbol>' -- .claude/adapters; if the introducing commit lies between the fixture's head_commit and fix_commit, the PR is skewed. Do NOT retry base mode (same failure, probed). Do NOT widen the answer set to the importers (reopens the oracle question). Decide per PR before the batch: exclude, or accept dissent-absent as pre-registered.

~~~~
~~~~~

## I05 — kf — 2026-10-20

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

## I06 — fix-commit — 2026-10-20

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

## I07 — fix-commit — 2026-10-20

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

## I08 — issue — 2026-10-20

- reference: #1286
- files: evals/harness/lib/sandbox-mount.sh,tools/gen-checksums.sh

Summary:

cycle-131: honest review-catch measurement — closed mount, grader 1.3.0, dissent line anchors + budget_scale knob, pre-registered reads (no shipped default changes) — ## cycle-131 — honest review-catch measurement Closes the three ways cycle-130's "+0.263 review-catch lift at 17× the cost" could have been fooling us, and re-measures under pre-registered rules. Nothing here changes a shipped defau…

Evidence:

~~~~~text
# pull request #1286: cycle-131: honest review-catch measurement — closed mount, grader 1.3.0, dissent line anchors + budget_scale knob, pre-registered reads (no shipped default changes)

- url: https://github.com/0xHoneyJar/loa/pull/1286
- created_at: 2026-10-20T09:57:58Z
- state: closed

The text below is third-party data, quoted verbatim (control characters and secret-shaped strings replaced).

~~~~text
## cycle-131 — honest review-catch measurement

Closes the three ways cycle-130's "+0.263 review-catch lift at 17× the cost" could have been fooling us, and re-measures under pre-registered rules. Nothing here changes a shipped default.

### What ships
- **Closed mount** for review-catch evaluation sandboxes (`evals/harness/lib/sandbox-mount.sh overlay_answer_paths` / `check_mount_closed`, took-effect rule `oracle_closed`, grader oracle detector): every answer-bearing `.claude/` path is the PR's own version before any phase runs. KF-049 closed for the mounted arm (24/24 batch rows unexposed; the open-mount control arm peeked in 3/3 runs).
- **Grader 1.3.0** with three results per grade (`recall_pm3_v1` on the frozen labels, `recall_pm3` on curated multi-site labels, `recall` same-scope) — the same-scope rule was **not adopted** after a blind two-labeler adjudication (2 of 7 credits were the labelled defect, κ 1.0; DEC-0638). Row writer 1.4, report 1.3 (no pooling across rules or pins). `run-ablation.sh --allow-partial`.
- **Dissent voices cite lines** (`anchor_line`/`anchor_line_end`, additive, nullable on the wire) and the optional `flatline_protocol.<gate>.budget_scale: fixed|diff` + `budget_cents_max` knob — **shipped default `fixed`, unchanged behaviour**; the evaluation harness runs its arms with `diff`.
- Four evaluation arms (`a0_bare_fable`, `a1_review_only`, `a1_no_dissent`, `a1_full_openmount` eval-only) outside `priority`; the cycle-131 suite root; curated multi-site corpus labels with the originals under `manifests/v1/`.
- Detector/grader hardening from three dissent rounds (shell redirections in the command splitter, class-7 contamination exemption never covering executed network lines, bounded work on agent-authored text, no fallback to the agent's `pr/head`).

### What was measured (pin `798d88cf`, 27 rows, USD 292.52; cycle ≈ USD 443 of 500)
| read | outcome (pre-registered branch) |
|---|---|
| R1 oracle A/B (pr-17) | insufficient as written / **investigate** at the trial level — Δ +0.067 [−0.017, +0.150] (DEC-0651) |
| R5 model | **between** — bare-Fable 0.226 < bare-Opus 0.393 < full 0.685; the model does not explain the lift (DEC-0654) |
| R3 audit gate (pr-17) | insufficient / **inconclusive** — Δ −0.033 [−0.133, +0.067], cost ratio 0.53 (DEC-0652) |
| R4 dissent (pr-17) | **insufficient** — 2 valid cells (DEC-0653) |

Addendum: `grimoires/loa/reports/ablation-2.0/analysis.md` §10 (ELI5 first). Honest caveats are in §10.7 (a pre-registration threshold that its own design could not meet, DEC-0650; two contaminated rows; pr-12 import skew KF-050; a Fable refusal fallback KF-051).

### Gates
Sprints 263/264/265: review and audit APPROVED with LOA-VERDICT trailers (`a2a/sprint-{1,2,3}/`); eight dissent runs across the cycle; `evals/tests/` 516–529 green on every integration commit; `tests/unit` adversarial-review set 652/652; `tools/gen-checksums.sh --check` OK. Decisions DEC-0610 … DEC-0654; KF-049 (rec 4, closed for the mount), KF-050, KF-051, KF-046 rec 10.

Record branch (gitignored a2a, batch records minus sandboxes): `record/cycle-131-honest-measurement` (pushed after merge).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
~~~~
~~~~~

## I09 — fix-commit — 2026-10-20

- reference: aac80f4cfea6
- files: evals/harness/lib/sandbox-mount.sh,evals/harness/took-effect.sh,evals/tests/took-effect.bats

Summary:

fix(cycle-131): PR #1286 Bridgebuilder round r4 — the closed mount refuses an unavailable fix commit (F001); grader 1.3.1 scans error-marked tool results (F002); 63 re-grades unchanged F001 (HIGH, accepted): `lib/sandbox-mount.sh overlay_answer_paths` exits 2 before writing anything when fixture.yaml's fix_commit is not in the source tree. Sprint 263 logged fix_commit_unavailable, overlaid the PR…

Evidence:

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


diff --git a/evals/harness/lib/sandbox-mount.sh b/evals/harness/lib/sandbox-mount.sh
index a451a95b..e496455b 100644
--- a/evals/harness/lib/sandbox-mount.sh
+++ b/evals/harness/lib/sandbox-mount.sh
@@ -89,7 +89,9 @@
 #       .claude/hooks/ or .claude/skills/*/SKILL.md; empty when none>, overlay_fixture=<dir>,
 #       overlay_source_tree=<dir>. Exit 2: missing workspace or fixture (no head.diff), a mode
 #       other than head|base, a copy source that is not a clean git tree, a copy_source other
-#       than <source-commit> when given, a symlink or non-directory component on a sandbox path.
+#       than <source-commit> when given, a symlink or non-directory component on a sandbox path,
+#       a fixture.yaml fix_commit that is not in <source-tree> (nothing is written; the sandbox
+#       stays as it was).
 #   check_mount_closed <ws> <fixture-dir> [<source-tree>] [<evidence-file>]
 #       the pre-launch form of took-effect.sh oracle_closed: clauses (a)-(d) (see
 #       _sm_oracle_py) against the fixture, the evidence file (default $ARM_EVIDENCE_FILE:
@@ -598,7 +600,8 @@ init_sandbox_beads() {
 #       skipped by their line counts so a removed "-- a/x" line is never a header;
 #   (ii) every file or symlink under <fixture>/head/ and <fixture>/base/;
 #   (iii) the fixture.yaml fix_commit's paths (git show --no-renames --name-only):
-#       an unknown fix commit logs fix_commit_unavailable and is skipped.
+#       an unknown fix commit logs fix_commit_unavailable and the overlay is REFUSED (exit 2;
+#       PR #1286 F001) — its paths could not be pinned, so the mount could not be closed.
 #   Normalised (no absolute, no "..", no empty or "." component, no backslash, no
 #   control character) and kept only under .claude/; .claude/checksums.json is
 #   harness-owned (regen_sandbox_manifest rewrites it) and excluded, as are CLAUDE.md
@@ -911,9 +914,15 @@ def cmd_overlay(ws, fixture, mode, repo):
     if not os.path.isdir(ws) or os.path.islink(ws):
         die("workspace not found: " + ws)
     entries, notes, meta = answer_set(fixture, repo)
-    exp = expected(entries, mode, fixture, repo, meta)
     for n in notes:
         note("overlay: " + n)
+    if meta.get("fix_available") == "unavailable":
+        # PR #1286 Bridgebuilder F001: the fix commit's paths are part of the answer set; without the commit they
+        # cannot be pinned, the mount would stay open on exactly those paths, and the check would call it closed.
+        die("overlay: refused: fix_commit %s is not in %s; the fix paths outside the PR cannot be pinned, so the "
+            "mount cannot be closed (fetch the commit into the source tree, or drop fix_commit from fixture.yaml)"
+            % (meta.get("fix_commit"), repo))
+    exp = expected(entries, mode, fixture, repo, meta)
     if entries and any(s == "fix" for s in entries.values()) and not meta.get("head_available"):
         note("overlay: head_commit %s unavailable: fix-commit paths outside the PR are removed" % meta.get("head_commit"))
     lines, gates, removed = [], [], 0
@@ -964,6 +973,8 @@ def cmd_check(ws, fixture, evfile, repo, source_commit):
     if not m:
         print("FAIL (a) -: mount_overlay=%s (want head|base:<n>)" % (mo or "<missing>")); sys.exit(1)
     mode, n = m.group(1), int(m.group(2))
+    if ev.get("overlay_fix_commit") == "unavailable":
+        print("FAIL (a) -: overlay_fix_commit=unavailable (the fix paths outside the PR were never pinned)"); sys.exit(1)
     entries, _notes, meta = answer_set(fixture, repo)
     exp = expected(entries, mode, fixture, repo, meta)
     fails = []
diff --git a/evals/harness/took-effect.sh b/evals/harness/took-effect.sh
index dde2464a..9de935d6 100755
--- a/evals/harness/took-effect.sh
+++ b/evals/harness/took-effect.sh
@@ -376,6 +376,8 @@ rule_oracle_closed() {
   fi
   [[ -f "$evf" ]] || { EVID="no meta/arm-evidence.txt"; return 1; }
   [[ "$(evidence_line mount_overlay)" != none ]] || { EVID="mount_overlay=none (an open mount)"; return 1; }
+  # PR #1286 F001: a fix commit the overlay could not read leaves its paths unpinned; never a closed mount
+  [[ "$(evidence_line overlay_fix_commit)" != unavailable ]] || { EVID="overlay_fix_commit=unavailable (the fix paths outside the PR were never pinned)"; return 1; }
   fx="$(resolve_fixture)" || { EVID="the PR fixture does not resolve (--task-yaml or overlay_fixture evidence)"; return 1; }
   sc="$(jq -r '.source_commit // ""' "$R/meta/pipeline.json")"
   cs="$(evidence_line copy_source)"
diff --git a/evals/tests/took-effect.bats b/evals/tests/took-effect.bats
index c8968191..efcb3e2d 100644
--- a/evals/tests/took-effect.bats
+++ b/evals/tests/took-effect.bats
@@ -341,7 +341,7 @@ make_closed_run() {
   [ "$status" -eq 0 ]
 }
 
-@test "oracle_closed: FAIL on an unmodified (later) mount, a stray later copy, a mutated path, a second sandbox commit, an open mount, a copy_source mismatch" {
+@test "oracle_closed: FAIL on an unmodified (later) mount, a stray later copy, a mutated path, a second sandbox commit, an unavailable fix commit, an open mount, a copy_source mismatch" {
   c131_suite; make_closed_run
   local W="$CRD/sandbox" ev="$CRD/meta/arm-evidence.txt"
   cp "$ev" "$T/ev.orig"
@@ -372,6 +372,11 @@ make_closed_run() {
   gg "$W" reset -q --hard HEAD~1; gg "$W" reflog expire --expire=now --all; gg "$W" gc -q --prune=now
   te131 "$CRD" --task-yaml "$CTY"
   [ "$status" -eq 0 ]
+  # a fix commit the overlay could not read (PR #1286 F001): its paths were never pinned
+  sed -i 's/^overlay_fix_commit=.*/overlay_fix_commit=unavailable/' "$ev"
+  te131 "$CRD" --task-yaml "$CTY"
+  [ "$status" -eq 1 ]; line oracle_closed | grep -q 'FAIL overlay_fix_commit=unavailable (the fix paths outside the PR were never pinned)'
+  cp "$T/ev.orig" "$ev"
   # an open mount is never closed; a copy source other than source_commit fails first
   sed -i 's/^mount_overlay=.*/mount_overlay=none/' "$ev"
   te131 "$CRD" --task-yaml "$CTY"
~~~~
