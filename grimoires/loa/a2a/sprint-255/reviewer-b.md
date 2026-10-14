# Implementation Report: Sprint 1 (global sprint-255), implementer B — control arms, record corpus, arm runner

**Date:** 2026-10-14
**Engineer:** implementer B, Claude Opus 5.5 subagent (model id `global.anthropic.claude-opus-5-5`)
**Sprint Reference:** grimoires/loa/sprint.md, Sprint 1, Tasks 1.4, 1.5, 1.6 (scripts)
**Worktree:** /home/merlin/Documents/thj/code/loa-wt-s1b (branch `wt/cycle-129-s1b` at `ffd25258`), nothing committed
**Patch:** ~/.cache/loa/cycle-129/patches/s1-b.patch (`git diff --cached --binary`, 713 files, 17 MB; 640 of the files are the verbatim fixture copies under `review-prs/pr-11 … pr-18`)

---

## Executive Summary

Both recall suites now pre-register their control arms and the verdict threshold. `execute-agent.sh` applies an arm to the sandbox copy only, after materialisation and immediately before the executor starts. A toggle that cannot take effect fails the trial with exit 2, so an arm never silently runs as its baseline. All six arm/suite combinations were proven against the real pinned worktree at `864069f2`. `compare.sh --ab` refuses mixed `source_commit` values, and `report.sh --arms` writes the pre-registered per-arm verdict with a percentile-bootstrap interval, refuted share and missed labels. `run-arms.sh` drives the batches against a detached worktree.

Eight record fixtures exist, `pr-11` … `pr-18` for sprints 247 … 254, carrying 55 labels and 810 fix regions. They are numbered from 11 because `pr-09` and `pr-10` already exist as clean controls. The labels live in the hidden `review-prs/labels/` directory, not inside `pr-NN/`, because the sandbox copies the whole fixture directory into the executor's workspace. The label files are left `# approved-by: pending` for the lead.

Two findings change what the lead should do next. First, the Fable 5.1 executor is not homogeneous. A safeguard refusal (category `cyber`) moved the proof trial to Opus 5.5 mid-session, and Opus wrote the review. Second, the executor inherited this agent session's coupling variables, including `CLAUDE_CODE_SUBAGENT_MODEL=opus`. That is fixed. The fallback cannot be switched off and is now recorded and treated as model skew. The executor choice is an open decision for the lead.

**Key Accomplishments:**
- Arms and threshold in both suites; sandbox-only toggles verified at executor start; 11 toggle tests
- `seed-corpus-from-record.sh`, 8 record fixtures (all eight sprints, none dropped), reproducible curation file, 6 seed tests
- `run-arms.sh` (pinned worktree, interleaving, retry, MANIFEST and STATUS, per-batch and suite-aggregate status), `report.sh --arms` with bootstrap and verdicts, `compare.sh --ab` source-commit refusal
- Two real single trials on `pr-01`: pipeline proven end to end (recall 1.0 both times), and the model-homogeneity problem found
- All 125 cases in the nine `evals/tests/*.bats` suites green, including `golden-path.bats`, which failed 33/33 on the base

---

## AC Verification

**AC-1.6**: "Both suites declare the canonical arm ids and the `ab.threshold` block; a sandbox prepared for `no_rule_files` has no rule files, for `no_karpathy` no Karpathy section, for `no_companion` `companion_voice: false`, for `no_audit_delta` no delta paragraph; `compare.sh --ab` refuses skewed model ids; `report.sh --arms` prints the per-arm verdict (PRD AC-2.1, AC-2.3, AC-2.4)"
- Status: `✓ Met`
- Evidence: `evals/suites/review-recall.yaml:35` (`arms:` with `baseline`, `no_companion` `informational: true` at `:44`, `no_karpathy` scope note at `:51`, `no_rule_files`), `:63` (`threshold:`); `evals/suites/audit-recall.yaml:27` (`arms:` `baseline`, `no_audit_delta` at `:31`), `:42` (`threshold:`); toggles in `evals/harness/execute-agent.sh:230` `apply_toggles()` (`companion_voice` `:238`, `karpathy_block` `:247`, `rule_files` `:260`, `audit_delta_instruction` `:268`), called at `:280` before the skill prompt is derived from the toggled copy; model skew `evals/harness/compare-ab.py:141`; per-arm verdict `evals/harness/arms-report.py:300` / `:309`, wired by `evals/harness/report.sh:38`.
- Test: `evals/tests/arm-toggles.bats:78` AT-1 (ids and threshold), `:114` AT-4, `:126` AT-5, `:140` AT-6, `:149` AT-7 (each asserts on the CLI stub's snapshot of the sandbox at executor start), `:170` AT-9 (exit 2 before the CLI); `evals/tests/recall-baseline-freshness.bats:228` BF-13 and the existing BF-8 (model skew); `evals/tests/arms-report.bats:50` AR-1 (verdict printed per arm).

**AC-1.7**: "At least six of the eight record fixtures exist with `fixture.yaml`, `head.diff`, instructions and an approved `labels.tsv` (a sprint with no accepted finding whose fix touches a cited file is dropped and the gap stated in `corpus.tsv` and the report); every label satisfies the fix-touches-file rule and carries `label_source`; every label passes `no-secrets.sh`; `SHA256SUMS` covers every file; `recall-vs-defects.sh` grades a label file (PRD AC-2.2)"
- Status: `⚠ Partial` (everything except the approval, which is the lead's step by SDD D-2.2)
- Evidence: all eight fixtures exist; table below. The rule is enforced at `evals/harness/seed-corpus-from-record.sh:550` (`if p not in fix_touched:`), and `label_source` comes from `source_kind()` at `:411`. no-secrets runs over the fixture directory and the hidden label files and fails the seed at `:774`. `SHA256SUMS` covers 842 files (`seed-corpus-from-record.sh --check`: "corpus OK: 842 files match SHA256SUMS"). The grader graded the real `pr-12` manifest against a hand-written review: recall 0.5 (4 of 8), 5 findings cited, 1 refuted (output under Testing Summary).
- Test: `evals/tests/seed-corpus.bats:45` SC-1 (kept, dropped by the rule, fix rows, hidden labels, freeze), `:86` SC-2 (secret rejected), `:96` SC-3 (grader grades the seeded label), `:110` SC-4 (approved-by header required).
- Notes: every `labels/pr-NN.tsv` starts `# approved-by: pending`. Approve each with `evals/harness/seed-corpus-from-record.sh --approve pr-NN --by "lead 2026-10-14"`, which rewrites the header, rebuilds the manifest and refreezes `SHA256SUMS`. `run-arms.sh` refuses unapproved fixtures unless `--allow-unapproved`.

**AC-1.8**: "`run-arms.sh --dry-run` lists the planned trials and writes a `MANIFEST.json`; batch 1 and batch 2 are started and their commands, log paths and `STATUS.json` paths recorded in the sprint report (PRD AC-2.4 precondition)"
- Status: `⚠ Partial` (the dry run is done; starting the batches is a lead step)
- Evidence: `evals/harness/run-arms.sh:208` (the `--dry-run` branch: plan listing plus `write_manifest "$mpath" true` at `:211`). The real dry runs planned 96 review and 48 audit trials per batch.
- Test: `evals/tests/run-arms.bats:40` RA-1.
- Notes: the commands, log paths and STATUS paths are in "Batch commands" below.

**AC-1.13**: "Every existing bats, pytest, vitest and fence-corpus suite is green on the sprint's final tree; the toolchain readiness check is recorded"
- Status: `⚠ Partial` (my scope only: `evals/`)
- Evidence: all 125 cases in the nine `evals/tests/*.bats` suites pass. `golden-path.bats` failed 33/33 on the base `ffd25258` because its setup did not copy `compat-lib.sh`; it is fixed in `evals/tests/golden-path.bats` (one `cp` line). `tools/check-no-raw-sha256sum.sh` (the CI scope, `.claude/scripts`) is clean. `evals/fixtures/sync-fixtures.sh --check` reports "All fixtures current." The eval workflow's trust-boundary scan finds 0 violations over `evals/harness` and `evals/graders`. All 57 JSON files in the new fixtures parse (ci.yml validates every `*.json`).
- Notes: the repo-wide bats, pytest, vitest and fence-corpus runs on the final merged tree are the lead's step.

### Record fixtures

| Fixture | Sprint | Files | head.diff | Labels (review/audit) | Fix regions | Dropped |
|---|---|---|---|---|---|---|
| pr-11 | 247 | 65 | 383 KB | 5 (3/2) | 18 | 4 |
| pr-12 | 248 | 15 | 66 KB | 8 (8/0) | 161 | 14 |
| pr-13 | 249 | 54 | 239 KB | 5 (1/4) | 49 | 7 |
| pr-14 | 250 | 88 | 238 KB | 2 (1/1) | 104 | 10 |
| pr-15 | 251 | 45 | 312 KB | 3 (1/2) | 239 | 6 |
| pr-16 | 252 | 39 | 229 KB | 4 (3/1) | 18 | 7 |
| pr-17 | 253 | 41 | 218 KB | 20 (9/11) | 105 | 5 |
| pr-18 | 254 | 29 | 125 KB | 8 (4/4) | 116 | 23 |

No sprint was dropped. `pr-14` (2 labels) and `pr-15` (3 labels) are thin. No Bridgebuilder finding qualified: each one concerns code added after the round-1 head or files from sprints 252 and 253 (`labels/pr-18.dropped.txt` names each).

---

## Tasks Completed

### Task 1.4: arms, toggles, `report.sh --arms`, freshness bats, `arm-toggles.bats`

**Files Created/Modified:**
| File | Action | Description |
|------|--------|-------------|
| `evals/suites/review-recall.yaml`, `audit-recall.yaml` | Modified | `ab.arms`, `ab.threshold`, every key commented |
| `evals/harness/execute-agent.sh` | Modified | arm resolution (`LOA_EVAL_ARM`, `LOA_EVAL_ARM_TOGGLES`, `LOA_EVAL_SUITE_FILE`), sandbox-only toggles with post-checks, skill prompt from the toggled copy, `.loa.config.yaml` materialised in arm mode, session decoupling, `arm`/`arm_toggles`/`arm_evidence`/`source_commit`/`models_used`/`refusal_fallbacks` in `executor.json` |
| `evals/harness/run-eval.sh` | Modified | `arm`, `source_commit`, `model_id` lifted onto every agent row |
| `evals/harness/compare-ab.py`, `compare.sh` | Modified | source-commit skew refused across trials and across control arms; control arms may share one prompt tree; any model in `models_used` counts toward skew |
| `evals/harness/arms-report.py` | Created | the report (stdlib only; yq reads the suite) |
| `evals/harness/report.sh` | Modified | `--arms [--suite] [--partial] [--results-dir] [--out] [--date]` |
| `evals/graders/recall-vs-defects.sh` | Modified | 1.2.0: `findings_cited`, `findings_refuted`, `refuted_share` from defect sites plus manifest `fix_regions`; recall rule unchanged |
| `evals/tests/arm-toggles.bats`, `arms-report.bats` | Created | 11 + 7 cases |
| `evals/tests/recall-baseline-freshness.bats` | Modified | BF-10 … BF-13 |
| `evals/tests/execute-agent.bats` | Modified | EA-11 (decoupling), EA-12 (refusal fallback recorded) |
| `evals/tests/eval-recall-grader.bats` | Modified | RG-28; RG-17 and RG-27 expect 1.2.0 |
| `evals/tests/fixtures/claude-stub.sh` | Modified | `STUB_SNAPSHOT_DIR`, `STUB_FAIL_COUNTER`, side-effect-free `--version`, more env keys |

The text the `no_audit_delta` toggle removes from the sandbox copy of `.claude/skills/auditing-security/SKILL.md` at `864069f2` (captured from `.eval/arm-removed.txt` on the real worktree):

```
Confirm the review's demotions independently: for each high the review trailer counts under
`excluded`, either confirm it (still speculative, still low confidence) or tally it as a finding
of your own; record the confirmed count in the trailer as `excluded_confirmed`.
```

### Task 1.5: `seed-corpus-from-record.sh`, fixtures pr-11 … pr-18, `seed-corpus.bats`

**Files Created/Modified:** `evals/harness/seed-corpus-from-record.sh` (created); `evals/fixtures/review-prs/record-pairs.tsv` (created: the commit pairs as data); `review-prs/pr-11 … pr-18/` (created); `review-prs/labels/{pr-NN.tsv, pr-NN.dropped.txt, curation.tsv}` (created); `review-prs/manifests/pr-11 … pr-18.json` (created); `review-prs/corpus.tsv` (8 `record` rows); `review-prs/SHA256SUMS` (refrozen, 842 files); `evals/tasks/{review,audit}-recall/*-pr-11 … 18.yaml` (16 created); `evals/fixtures/build-review-corpus.sh` (skips `#` lines and `record` rows); `evals/tests/seed-corpus.bats` and `evals/tests/fixtures/seed-record/` (created); `evals/README.md` (section added).

Modes: seed (`<sprint> <record-ref>`), `--dry-run`, `--build-manifest`, `--approve --by`, `--freeze`, `--check`; `--repo`, `--corpus` and `--tasks-dir` for tests.

### Task 1.6 (scripts): `run-arms.sh`

`evals/harness/run-arms.sh` (created) with `evals/tests/run-arms.bats` (5 cases). It reuses or creates `~/.cache/loa/cycle-129/arms-src-<sha12>` with `git worktree add --detach` and refuses one that is dirty or on another commit. It verifies the whole corpus at start and the fixture's own files before each trial. Trials are interleaved trial-major, then fixture, then arm. A transport failure (timeout, no result event, API error, rate or session limit) is retried once after `--retry-wait`, 300 s by default. Results go to `evals/results/arms/<suite>/<batch>/`, plus a suite-level aggregate `STATUS.json` (state precedence failed > running > partial > complete). Exits: 0 complete, 1 partial, 2 usage, 3 failed.

---

## Technical Highlights

- **Toggles proven at executor start, not after the toggle step.** The CLI stub snapshots the sandbox when it is launched (`STUB_SNAPSHOT_DIR`). Every assertion in `arm-toggles.bats` reads that snapshot, including the appended system prompt, which is now derived from the toggled sandbox `SKILL.md`.
- **The answer key never enters the sandbox.** Labels and the dropped-findings report sit beside the hidden `manifests/` directory.
- **Curation is data.** `labels/curation.tsv` holds 9 hand decisions with reasons and is re-applied on every seed. A row that matches no seeded label is an error.
- **Refuted share** is the grader's figure: a distinct cited `path:line-range` matching neither a defect site nor a `fix_regions` range, each widened by ±3 lines.
- **Verdict rule as implemented:** `no recall loss` needs the drop interval's upper bound at or below 0.10, the min-trial rule, the refuted-share rule, full coverage, no model or source skew, and no `--partial`. A violated recall rule with |drop| at or below the baseline's own trial spread reads `inconclusive` (no change can be named). A refuted-share violation always reads `recall loss`.

---

## Testing Summary

| Suite | Cases | Result |
|---|---|---|
| `evals/tests/arm-toggles.bats` | 11 | pass |
| `evals/tests/arms-report.bats` | 7 | pass |
| `evals/tests/eval-recall-grader.bats` | 28 | pass |
| `evals/tests/execute-agent.bats` | 12 | pass |
| `evals/tests/golden-path.bats` | 33 | pass (33/33 failing on the base) |
| `evals/tests/implement-discipline-grader.bats` | 10 | pass |
| `evals/tests/recall-baseline-freshness.bats` | 13 | pass |
| `evals/tests/run-arms.bats` | 5 | pass |
| `evals/tests/seed-corpus.bats` | 6 | pass |

```
LOA_HARNESS_CHECK=0 LOA_AUDIT_REPLAY=1 "$(cat ~/.cache/loa/cycle-128/bats-path)" evals/tests/*.bats   # 1..125, 125 ok
bash tools/check-no-raw-sha256sum.sh                         # OK — no raw sha256sum callers outside exempt set
evals/harness/seed-corpus-from-record.sh --check             # corpus OK: 842 files match SHA256SUMS
bash evals/fixtures/sync-fixtures.sh --check                 # All fixtures current.
```

The prompt's `.claude/scripts/check-no-raw-sha256sum.sh` does not exist; the lint is `tools/check-no-raw-sha256sum.sh`. With `--root evals` it reports pre-existing callers (`compare.sh`, `run-eval.sh`, `build-review-corpus.sh`) and verbatim test code inside fixture copies. CI does not scan `evals/`, and none of the new scripts call `sha256sum` (they hash with Python `hashlib`).

Grader proof on the real `pr-12` manifest (hand-written review citing L01, L02, L04/L06, one fix region and one unrelated line):

```
{"pass":false,"score":50,"recall":0.5,"planted":8,"detected":["L01-the-check-only-proves-the-heading-exists","L02-is-unguarded","L04-the-companion-is-forked-before-the-prima","L06-the-companion-runs"],"findings_cited":5,"findings_refuted":1,"refuted_share":0.2,"v":"1.2.0"}
```

### The real trials (review-recall, baseline, pr-01, source 864069f2, `--model claude-fable-5-1`)

| Trial | Wall time | Recall | Tokens (all four usage fields) | Cost | Output tokens by model |
|---|---|---|---|---|---|
| `one-trial-proof` (before the decoupling fix) | 325 s | 1.0 (3/3) | 423,391 | $3.23 | Fable 9,425 · Opus 5.5 11,085 |
| `one-trial-proof-2` (after the fix, transcript kept) | 513 s | 1.0 (3/3) | 312,646 | $3.54 | Fable 22,117 · Opus 5.5 11,364 |

Results: `evals/results/arms/review-recall/{one-trial-proof,one-trial-proof-2}/` in this worktree; logs `~/.cache/loa/cycle-129/logs/one-trial-proof{,-2}.log`. Trial 2's transcript shows the cause. Fable wrote 21 messages and read the fixture. Then `system/model_refusal_fallback` fired (`api_refusal_category: cyber`, `scope: session`, to `global.anthropic.claude-opus-5-5`), and Opus wrote `review.md`. Trial 1 kept no transcript; its split suggests the same cause, but that is not proven.

---

## Known Limitations

- **Executor homogeneity (decision for the lead).** Fable 5.1 safeguard refusals move a session to Opus 5.5, and no CLI flag turns that off. Under the current rule such trials are model skew, so the arm reads `inconclusive`. Most fixtures are security code. Options: (a) keep Fable (D33) and expect inconclusive arms; (b) run on `--model global.anthropic.claude-opus-5-5`, which is homogeneous and was the pre-D33 SDD pin (needs a DEC amendment); (c) keep Fable and accept fallback as part of the gate. I recommend (b).
- **What the eval sandbox can exercise.** The executor has Read, Grep, Glob and Write only, so it cannot run `adversarial-review.sh`. `no_companion` therefore changes only a config key the executor might read: it is a prompt-surface arm, consistent with its informational status. Likewise the audit eval has no review file, so `no_audit_delta` removes an instruction that has nothing to act on in these fixtures.
- **Thin fixtures.** `pr-14` has 2 labels and `pr-15` has 3. The 249, 250 and 251 record branches keep only the approving review round, not round 1.
- **Anchor quality.** Anchors are machine-chosen, and nine were hand-corrected. Unreviewed anchors on long functions may sit a few hunks from the defect; each label lists up to four sites, which widens credit.
- **Cost and time.** pr-01 cost $3.2–3.5 and 5–9 minutes per trial. Record diffs are 10–60 times larger, so I raised their task timeout to 3600 s. Batch 2 is likely several times batch 1's cost and wall time (estimate below).
- **Stale proof results.** The two proof batches live in this worktree's gitignored `evals/results/arms/review-recall/`. Running the real batches from this worktree would mix them into the suite aggregate; run from the main checkout, or delete `one-trial-proof*` first.

---

## Verification Steps

```
cd /home/merlin/Documents/thj/code/loa && git apply --index ~/.cache/loa/cycle-129/patches/s1-b.patch
LOA_HARNESS_CHECK=0 LOA_AUDIT_REPLAY=1 "$(cat ~/.cache/loa/cycle-128/bats-path)" evals/tests/*.bats
evals/harness/seed-corpus-from-record.sh --check
evals/harness/seed-corpus-from-record.sh 254 origin/record/cycle-128-a2a --dry-run   # reproduces pr-18's labels
less evals/fixtures/review-prs/labels/pr-1{1..8}.tsv evals/fixtures/review-prs/labels/curation.tsv
for f in pr-11 pr-12 pr-13 pr-14 pr-15 pr-16 pr-17 pr-18; do evals/harness/seed-corpus-from-record.sh --approve "$f" --by "lead 2026-10-14"; done
evals/harness/run-arms.sh --suite review-recall --arms baseline,no_companion,no_karpathy,no_rule_files --fixtures pr-01,pr-02 --trials 1 --source-commit 864069f2 --dry-run
```

---

## Batch commands

Run from a checkout where this patch is committed (MANIFEST records `harness_dirty`) and where the eight label files are approved and committed. `--model claude-fable-5-1` is the D33 executor; substitute `global.anthropic.claude-opus-5-5` for option (b). Each batch runs its two suites back to back at concurrency 2. Do not overlap the two batches (four concurrent CLIs is the KF-037 contention shape).

Batch 1 (pr-01 … pr-08; 96 review + 48 audit = 144 trials):

```
cd /home/merlin/Documents/thj/code/loa && mkdir -p ~/.cache/loa/cycle-129/logs && setsid nohup bash -c 'F=pr-01,pr-02,pr-03,pr-04,pr-05,pr-06,pr-07,pr-08; evals/harness/run-arms.sh --suite review-recall --arms baseline,no_companion,no_karpathy,no_rule_files --fixtures "$F" --trials 3 --source-commit 864069f2 --model claude-fable-5-1 --concurrency 2 --batch batch-1; evals/harness/run-arms.sh --suite audit-recall --arms baseline,no_audit_delta --fixtures "$F" --trials 3 --source-commit 864069f2 --model claude-fable-5-1 --concurrency 2 --batch batch-1' > ~/.cache/loa/cycle-129/logs/arms-batch-1.log 2>&1 < /dev/null &
```

Batch 2 (pr-11 … pr-18; 144 trials; after the eight `--approve` runs):

```
cd /home/merlin/Documents/thj/code/loa && mkdir -p ~/.cache/loa/cycle-129/logs && setsid nohup bash -c 'F=pr-11,pr-12,pr-13,pr-14,pr-15,pr-16,pr-17,pr-18; evals/harness/run-arms.sh --suite review-recall --arms baseline,no_companion,no_karpathy,no_rule_files --fixtures "$F" --trials 3 --source-commit 864069f2 --model claude-fable-5-1 --concurrency 2 --batch batch-2; evals/harness/run-arms.sh --suite audit-recall --arms baseline,no_audit_delta --fixtures "$F" --trials 3 --source-commit 864069f2 --model claude-fable-5-1 --concurrency 2 --batch batch-2' > ~/.cache/loa/cycle-129/logs/arms-batch-2.log 2>&1 < /dev/null &
```

Paths: logs `~/.cache/loa/cycle-129/logs/arms-batch-{1,2}.log`; per-batch `evals/results/arms/<suite>/batch-{1,2}/{STATUS.json,MANIFEST.json,run.log}`; Sprint 2 gate `evals/results/arms/review-recall/STATUS.json` and `evals/results/arms/audit-recall/STATUS.json`; report `evals/harness/report.sh --arms`.

| Estimate | Batch 1 | Batch 2 |
|---|---|---|
| Executor runs | 144 | 144 |
| Wall time at concurrency 2 | about 8.4 h (144 × 7.0 min mean of the two pr-01 trials ÷ 2) | 18–30 h if a record trial takes 15–25 min (not measured) |
| Cost | about $490 (144 × $3.4) | $1.5–3K (unmeasured; diffs 10–60× pr-01) |

All 288 runs match the pre-registration (16 fixtures × 6 arm-suite pairs with a shared baseline × 3 trials). The planned "about three minutes per run, seven hours" understates batch 1 alone.

---

## Assumptions

- [ASSUMPTION fact] The probe `claude -p --model claude-fable-5-1 'Reply with your exact model id only'` was accepted: result `claude-fable-5-1`, modelUsage `canonicalModel: claude-fable-5-1`, provider bedrock. The `global.anthropic.claude-fable-5-1` candidate was not needed. The default `--model` is `claude-fable-5-1`.
- [ASSUMPTION fact] Sprint 247: base `7246ae55^`, head `7246ae55` (the only implementation commit), fix `4b289413` (the last audit fix); feedback `engineer-feedback-round-1.md`, `auditor-sprint-feedback.md`.
- [ASSUMPTION fact] Sprint 248: base `6c887887^`, head `6c887887`, fix `51d7a1ff` (round 1ap, the last before completion); feedback `engineer-feedback-round-1.md` sections 1–5 only (sections 6–37 are later rounds on later commits), `auditor-sprint-feedback.md`.
- [ASSUMPTION fact] Sprint 249: base `41b783a1^`, head `41b783a1`, fix `36b71e4e` (round s3-1b); the record branch has only the approving `engineer-feedback.md`, plus `auditor-sprint-feedback.md`.
- [ASSUMPTION fact] Sprint 250: base `2fcd4af8` (sprint-249 close), head `d785fc9a` (the last implementation commit before review round 1, `17291942`), fix `e170de3d` (r250-9); feedback `engineer-feedback.md` (round 2, approval), `auditor-sprint-feedback.md`.
- [ASSUMPTION fact] Sprint 251: base `f43949d6^`, head `8ad37c55` (fr23b, before review dissent r251-1), fix `263a8d4c` (the Bridgebuilder round r251-6); feedback `engineer-feedback.md`, `auditor-sprint-feedback.md`.
- [ASSUMPTION fact] Sprint 252: base `8dc4a49d^`, head `8dc4a49d`, fix `16f38539`; feedback `engineer-feedback-r1.md`, `auditor-sprint-feedback.md`.
- [ASSUMPTION fact] Sprint 253: base `cea919ca^`, head `cea919ca`, fix `8f7932b2`; feedback `engineer-feedback-r1.md`, `auditor-sprint-feedback-r1.md`.
- [ASSUMPTION fact] Sprint 254: base `efacf754^`, head `efacf754`, fix `3758ddd0` (the Bridgebuilder round on PR #1279); feedback `engineer-feedback-r1.md`, `auditor-sprint-feedback-r1.md`, `bridgebuilder-triage.md`.
- [ASSUMPTION fact] `pr-09` and `pr-10` already exist as clean false-positive controls, so the record fixtures are `pr-11` … `pr-18`.
- [ASSUMPTION fact] The literal "look for what the review did not" is not in `auditing-security/SKILL.md` at `864069f2`; it was in the sprint-254 audit dispatch prompt (`auditor-sprint-feedback-r1.md:90` on the record). The toggle removes the paragraph quoted above and would take the literal phrase first if it existed (AT-8).
- [ASSUMPTION fact] At `864069f2`, `constraints.json` has no Karpathy row and the sandbox does not regenerate the kernel. The `constraints.json` toggle is defensive (AT-5). `.loa.config.yaml` has no `companion_voice` key, so it defaults on.
- [ASSUMPTION fact] The executor inherited `CLAUDE_CODE_SUBAGENT_MODEL=opus`, `CLAUDE_CODE_CHILD_SESSION`, `CLAUDE_CODE_SESSION_ID`, `CLAUDE_CODE_MESSAGING_SOCKET` and `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` from this session.
- [ASSUMPTION fact] Fable's safeguards refused proof trial 2 (category `cyber`) and the CLI fell back to `global.anthropic.claude-opus-5-5` for the rest of the session. `claude --help` shows no flag that disables refusal fallback.
- [ASSUMPTION fact] `golden-path.bats` failed 33/33 on base `ffd25258` (missing `compat-lib.sh` in its setup).
- [ASSUMPTION fact] Tracked test files carry fake secret-shaped keys (`sk-ant-…`). They fail `no-secrets.sh` in verbatim copies: 4–12 substitutions per fixture in pr-11, pr-12, pr-14 and pr-15.
- [ASSUMPTION decision] Labels live in the hidden `review-prs/labels/pr-NN.tsv`, not `pr-NN/labels.tsv`, because the sandbox copies the whole fixture directory.
- [ASSUMPTION decision] Fixture scope excludes `grimoires/`, `.beads/`, `.run/`, `evals/results/`, `CHANGELOG.md`, `.claude/checksums.json`, `REPO-MAP.md`, lock files and binaries; renames are detected (`-M`).
- [ASSUMPTION decision] `fix_commit` is the last commit that closed the sprint's feedback, so `head..fix` covers every round. A label's file must be in the fixture as well as touched by the fix (a reviewer can only cite `head/` files).
- [ASSUMPTION decision] A finding's locus is its first path cite. A bullet that opens with prose, a finding that calls itself pre-existing, and later-round sections are not labels.
- [ASSUMPTION decision] The anchor priority is: a quoted code snippet that is unique in the file (comment lines ignored in code), then fix hunks near the cited line or inside the cited symbol, then the definition line of a short function. A file-level finding is anchored on the file's fix hunks only when there are at most four; at most four anchors per label.
- [ASSUMPTION decision] Curation rows (`labels/curation.tsv`): pr-11 L04 re-anchored on `load_observed`; pr-12 L02 on `result=$(_fold_companion`; pr-12 L04 and L06 on the companion fork line; pr-12 L07 on `_adv_cred_present`; pr-13 L01 on the `LOA_CONTEXT_CLASS` comparisons; pr-17 L17 on `san1`. pr-14 L03 is dropped (the sanitiser it names does not exist at head). pr-18 L04 is dropped (a byte-budget note with no code site).
- [ASSUMPTION decision] Recall counts feedback labels only. `fix` rows feed refuted share only. The grader moves to 1.2.0, adding fields without changing the recall rule.
- [ASSUMPTION decision] The baseline-spread rule gates recall-rule violations only; a refuted-share violation is `recall loss`.
- [ASSUMPTION decision] Label files stay `# approved-by: pending`; approval is the lead's (`--approve`), and `run-arms.sh` refuses unapproved fixtures unless `--allow-unapproved`.
- [ASSUMPTION decision] In arm mode, every arm gets the source tree's `.loa.config.yaml`, so only the toggled key differs between arms.
- [ASSUMPTION decision] Results are per batch (`<suite>/<batch>/`) with a suite-level aggregate `STATUS.json`, so a second batch never shares a writer with the first.
- [ASSUMPTION decision] Secret-shaped strings in verbatim copies become `REDACTED-TEST-SECRET` consistently in `base/`, `head/` and `head.diff` (line numbers unchanged), and the count is recorded in `labels/pr-NN.dropped.txt`.
- [ASSUMPTION decision] Record-fixture tasks get `per_trial: 3600` (pr-01 … pr-10 keep 1500).
- [ASSUMPTION decision] I ran a second single real trial after the decoupling fix, with the transcript kept. The first trial's model split had to be explained before any batch starts. No other real trial was run.
- [ASSUMPTION decision] Batch 1 is `pr-01` … `pr-08` and excludes the clean controls `pr-09`/`pr-10`, keeping the pre-registered 288 runs.
- [ASSUMPTION decision] The transport retry waits 300 s by default (a session or rate limit needs time), and the bootstrap seed is fixed per (suite, arm), so reports are reproducible.
- [ASSUMPTION decision] Label categories come from a keyword heuristic over the title (security, concurrency, error-handling, test, docs, logic); they are descriptive only.
- [ASSUMPTION decision] `golden-path.bats` is fixed in place (it is under `evals/`, which this task owns).
