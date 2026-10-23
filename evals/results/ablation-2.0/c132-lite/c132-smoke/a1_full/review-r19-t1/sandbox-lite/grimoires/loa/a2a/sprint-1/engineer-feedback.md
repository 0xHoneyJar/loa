All good

Observations documented and non-blocking. See Observations below.

# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Change under review:** `pr/head.diff` — sprint-255 (cycle-129): guard register with origin and yield, pre-registered control arms on a record corpus, task kinds, path-scoped rule files (81 files)

---

## Overall Assessment

The change is coherent and well-tested. The guard register (`guard-yield.sh`, `guard-origins.yaml`, `floor.yaml`) enumerates hooks, fence markers, validator markers, gates and policies and cross-checks them both ways; the `--check` drift gate and the generated hooks table are in sync with the head `.claude/settings.json` (verified by running the script against the head framework). The task-kind validator, the `cycle-ratio.sh` tool, the control-arm driver (`run-arms.sh`), the arm toggles in `execute-agent.sh`, the arm report and the record-corpus seeder all come with bats suites that pass when run against the head tree (details under Test Evidence). Security posture is sound: ids are regex-validated, the yield never surfaces command text or cwd, audit rows are treated as untrusted, label files stay out of the sandbox, and secret-shaped strings are dropped or redacted.

No critical or high finding. Three medium and eight low observations follow, each with a concrete failure scenario; none blocks merge.

**Report caveat.** `reviewer.md` is the harness-supplied PR description and carries no `## AC Verification` section. The skill's automatic CHANGES_REQUIRED on a missing walkthrough targets an engineer-written report; here the review instructions state there is no implementation report and the sprint's single task is the change itself, so the verdict is derived from the code findings, not from the report's shape.

**Snapshot caveat.** The review fixture omits `grimoires/` (so `grimoires/loa/guards.md`, the tracked register the CI step `guard-yield.sh --check` compares against), `CHANGELOG.md`, `evals/fixtures/review-prs/` (the record fixtures pr-11 … pr-18, `labels/`, `manifests/`, `corpus.tsv`, `SHA256SUMS`, `record-pairs.tsv`) and `tools/check-prompt-budget.sh`. Those could not be verified from this workspace; see Documentation Verification.

**Verdict:** APPROVED

---

## Adversarial Cross-Model Review

`.claude/scripts/adversarial-review.sh --type review --sprint-id sprint-1 --diff-file pr/head.diff --json` refused before dispatch: `status: budget_exceeded`, estimate 627c over two voices (gpt-5.5-pro 472c, claude-headless 155c) against the `budget_scale: diff` effective cap of 600c (`budget_cents_max`). No findings were produced and no payload was rejected, so this review is single-voice. The refusal envelope is the script's stdout (`metadata.status = budget_exceeded`, `reason = budget`).

---

## Observations

### 1. Robustness — guard-yield.sh sources an external library in-process

- **MEDIUM** (confidence: medium) `head/.claude/scripts/guard-yield.sh:470` — `source "$HEREDOC_LIB"` runs in the main shell, gated only by a `grep` for the function name at line 468. If the library (or anything it sources) runs to completion of a script body instead of only defining functions, guard-yield.sh ends there: exit 0, no `guards.md`, no `.run/guard-yield.{md,json}`, no summary line, and `--json` prints nothing.
**File:** `head/.claude/scripts/guard-yield.sh:468-471`
**Issue:** Reproduced in this workspace, where a later-cycle `.claude/scripts/lib/heredoc-classifier.sh` (it sources the fence with `BDB_LIB_ONLY=1`) sits beside this PR's fence, which has no `BDB_LIB_ONLY` branch: sourcing the library ran the fence's main body, which read an empty stdin and exited 0. `bash -x` stops at the `source` line; every GY-* case then fails on the missing yield file. At PR head the library does not exist, so the shipped tree is unaffected; the hazard is the mount where the library and the fence are at different revisions.
**Why This Matters:** A guard that silently produces nothing with exit 0 is the failure mode the register exists to catch. `--check` exits before this point, so CI stays green while every host yield vanishes.
**Required Fix:** Probe the library in a subshell before sourcing (`( source "$HEREDOC_LIB" >/dev/null 2>&1 && declare -F heredoc_nonexec >/dev/null )`), or `source` inside a function that traps `EXIT`, and fall back to the `<<` heuristic with a WARN when the probe fails. Add a bats case with a library stub that calls `exit 0`.

### 2. Evaluation validity — auxiliary-model usage reads as model skew

- **MEDIUM** (confidence: low) `head/evals/harness/arms-report.py:144-146` — every `models_used` key with output tokens joins the arm's model set, and `:281` turns a set of size > 1 into `inconclusive`. If the CLI reports any auxiliary model in `modelUsage` for a normal run (a small model used for a title or a tool-call summary), every non-baseline arm reads `inconclusive` on every batch and the pre-registered comparison can never conclude.
**File:** `head/evals/harness/arms-report.py:144-146`, `head/evals/harness/arms-report.py:281`
**Suggestion:** Decide skew on the executor model id plus `refusal_fallbacks` (already recorded by `execute-agent.sh`), or ignore auxiliary models below a small output share; keep the full `models_used` list in the report as information.
**Benefit:** The control-arm verdicts stay reachable; a real fallback is still named through `refusal_fallbacks`.

### 3. Arm toggles — the constraints.json surface is not verified

- **MEDIUM** (confidence: medium) `head/evals/harness/execute-agent.sh:256` — `jq … > "$cj.tmp" && mv "$cj.tmp" "$cj"` is a `&&` list, so a jq failure (a `constraints.json` whose top level is not an object with a `constraints` array) is not caught by `set -e`; the sandbox keeps its Karpathy rows and an empty `constraints.json.tmp`, the trial proceeds, and `executor.json` records `arm: no_karpathy` with evidence that mentions only `CLAUDE.loa.md`. The header (`:60-62`) promises every toggle "is verified absent afterwards"; this surface is not.
**File:** `head/evals/harness/execute-agent.sh:256-258`
**Suggestion:** Check the jq exit status explicitly, then assert no row matches `karpathy` and fail the trial (exit 2) otherwise, as the `CLAUDE.loa.md` branch at `:251-253` already does.
**Benefit:** An arm never silently runs as a partial baseline, which is the invariant the toggles are built on.

### 4. Documentation drift inside guard-yield.sh

- **LOW** (confidence: high) `head/.claude/scripts/guard-yield.sh:29-30` — the header says the cwd and burst replay rules apply "for rows that predate the flag"; `def replay` at `:499` applies them to every row. A live session that trips ten blocks in one minute, or a checkout under `$TMPDIR`, is excluded as replay even when its rows carry no `replay` flag.
**Suggestion:** Either scope the heuristics to rows without a `replay` key (`has("replay") | not`) or reword the header to describe what the code does.

### 5. Transport-failure classification is broad

- **LOW** (confidence: medium) `head/evals/harness/run-arms.sh:314` — the retry decision greps `agent-output.json` and the stderr log for `network`, `socket hang up` and `5[0-9][0-9] `. The output JSON embeds the model's final text; a review that mentions "network" or a line count such as "1500 " turns an exit-1 agent error into `transport_error`, costing a retry and leaving the arm `partial` instead of recording `agent_error`.
**Suggestion:** Match the structured fields only (`exit_code`, `subtype`, `api_error_status`) plus stderr, not the result text.

### 6. Redaction counter over-counts

- **LOW** (confidence: high) `head/evals/harness/seed-corpus-from-record.sh:128` — `REDACTED[0]` accumulates across the `head.diff` pass and every `base/` and `head/` file write, so a secret-shaped string in a modified file is counted three times; the `.dropped.txt` header at `:756` then overstates the redactions.
**Suggestion:** Count during one pass (the `head.diff` text) or count distinct `(path, line)` hits.

### 7. Rename parsing in the binary filter

- **LOW** (confidence: medium) `head/evals/harness/seed-corpus-from-record.sh:312` — `p.split(" => ")[-1].strip("{}")` handles `old => new` but not `dir/{a => b}/f.bin` (yields `b}/f.bin`), so a renamed binary is not excluded from the fixture scope and lands in `head/`.
**Suggestion:** Parse `--numstat -z` or normalise the brace form before stripping.

### 8. SURGICAL — permission widening not named in the PR

- **LOW** (confidence: high) `head/.claude/skills/implementing-tasks/SKILL.md:28` — the app zone moves from `read` to `read-write` in the frontmatter. The skill body (`:76`) already said Read/Write, so this is a consistency fix, but it is a permission statement in a skill outside the four features the PR describes and the description does not mention it.
**Suggestion:** Name it in the PR body (one line) so the audit trail shows it was intended.

### 9. Aggregate status lock gives up silently

- **LOW** (confidence: medium) `head/evals/harness/run-arms.sh:287` — `aggregate_status` returns 0 after 5 s without the lock, so under contention the suite-level `STATUS.json` can lag the batch `STATUS.json`; `report.sh --arms` then refuses or reports stale counts without a hint.
**Suggestion:** Log the skipped aggregation, or retry once more at the end of the run before `set_state`.

### 10. Audit-segment glob is permissive

- **LOW** (confidence: medium) `head/.claude/scripts/guard-yield.sh:443` — `"$AUDIT_LOG".*` also matches `audit.jsonl.lock` or `audit.jsonl.tmp` siblings; a text sibling is parsed as rows (inflating `audit_rows_unparseable`), an unreadable one is exit 3.
**Suggestion:** Match rotated segments only (`"$AUDIT_LOG".[0-9]*` or a date suffix).

### 11. SIMPLICITY — long linear functions

- **LOW** (confidence: high) `head/evals/harness/arms-report.py:176-343` — `suite_report` is 168 lines; `head/.claude/scripts/validate-artifact.sh:976-1064` (`validate_sprint_kinds`, 88 lines) and `run_trial` in `run-arms.sh` (65 lines) also exceed the 50-line guide. Each is a single linear pipeline covered by bats (AR-1 … AR-7, KINDS-1 … KINDS-11, RA-1 … RA-5), so I am recording rather than blocking; extracting the verdict rule (`:273-304`) and the table row rendering from `suite_report` would be the first cut. No over-engineering beyond length. Lean already. Ship.

---

## Previous Feedback Status

No previous `engineer-feedback.md` existed for this sprint.

---

## Incomplete Tasks

None. Task 1.1 (the change in `pr/head.diff`) is complete.

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| "review the pull request, report each defect it introduces with the file and line it sits on" (sprint.md Success Criteria) | Pass | Findings above cite `head/<path>:<line>` |
| "give a merge verdict" | Pass | APPROVED; no critical or high finding |

---

## Test Evidence

Run from a copy of the head framework (`/workspace/.claude` = `pr/head/.claude`) plus the PR's `tests/`, `evals/` and `tools/`, on an exec-capable path (`/tmp` is mounted `noexec` here, which produced the first-round "Permission denied" noise). Two environment substitutions: a stub `tools/check-prompt-budget.sh` (the real tool is outside the snapshot) and the later-cycle `heredoc-classifier.sh` moved aside (Observation 1).

| Suite | Result | Notes |
|-------|--------|-------|
| `guard-yield.sh --hooks-table` then `--check` | written, `in sync (95 guards)` | hooks table in `hooks-reference.md` matches head `settings.json`; register: 95 guards, 0 without origin, 3 dormant, 21 floor |
| tests/unit/guard-yield.bats | 11/11 | |
| tests/unit/guard-origins.bats | 15/15 | floor.yaml sha256 pin matches |
| tests/unit/validate-artifact-sprint-kinds.bats | 11/11 | |
| tests/unit/rule-paths.bats | 6/6 | |
| tests/unit/cycle-ratio.bats | 6/6 | |
| tests/unit/loa-status-guards.bats | 3/3 | |
| tests/unit/floor-snapshot.bats | 4 skipped | no `origin/main` in this checkout |
| tests/unit/sprint-seams.bats | 11/12 | SEAMS-9 needs the archived cycle-127 plan (outside the snapshot) |
| tests/unit/prompt-budget.bats | not runnable | `tools/check-prompt-budget.sh` outside the snapshot; PB-10's constants line unverified |
| evals/tests/arm-toggles.bats | 11/11 | |
| evals/tests/arms-report.bats | 7/7 | |
| evals/tests/execute-agent.bats | 10/12 | EA-8/EA-9 need task files outside the snapshot |
| evals/tests/recall-baseline-freshness.bats | 12/13 | BF-4 also fails with the base `compare.sh`/`compare-ab.py`: pre-existing, fixture-dependent |
| evals/tests/eval-recall-grader.bats | 26/28 | RG-16/RG-17 need `review-prs/manifests` (outside the snapshot); RG-28 (refuted share) passes |
| evals/tests/run-arms.bats, seed-corpus.bats | not runnable | need `sandbox.sh`, `grade.sh`, `no-secrets.sh` and the corpus, all outside the snapshot |
| `validate-artifact.sh --type glossary` on the new GLOSSARY entries | pass | |
| `validate-artifact.sh --type sprint` on `tests/fixtures/sprint-kinds/cycle-128-sprint.md` | pass, one WARN (23 untagged lines) | matches KINDS-10 |

---

## Documentation Verification

- `hooks-reference.md`: regenerated table in sync; prose updated. Pass.
- `GLOSSARY.md`: four entries added (Judgment, Kind counts, Mechanical, Operator, Volume ratio); validator passes.
- `evals/README.md`: control arms and record corpus documented with the run commands.
- `sprint-template.md`: task lines carry the `kind:` token (KINDS-11).
- CHANGELOG entry: not verifiable — `CHANGELOG.md` is excluded from the review snapshot.
- `grimoires/loa/guards.md` (the tracked register the CI `--check` step and GO-9 compare against): not verifiable — `grimoires/` is excluded from the snapshot. The PR's `.gitignore` does not ignore it (checked with `git check-ignore`); confirm it is committed alongside the map.
- Record fixtures pr-11 … pr-18 referenced by the new task files and the `.gitignore` negation: outside the snapshot.
- No new command or skill; no CLAUDE.md entry needed.

---

## Security Checklist

- [x] No hardcoded secrets or credentials (seeder drops secret-shaped findings and redacts fixture copies; no-secrets scan over every written file)
- [x] Input validation and sanitization present (ids `^[A-Za-z0-9._/:-]+$`, arm ids, model ids, batch names, SHAs, `--by`; table cells control-stripped and pipe-escaped)
- [x] Authentication/authorization correct (no change to hook registrations, deny list or floor files; floor pinned by sha256 and snapshot tests)
- [x] No SQL/XSS injection vulnerabilities (not applicable; jq/yq values passed by argument, python run with `-I`)
- [x] Dependencies secure (no new dependencies; yq v4 pinned by sha256 in CI)
- [x] Error messages don't leak sensitive data (yield outputs carry no command text, cwd, hostname or model name — GY-5)

---

## Code Quality Summary

**Strengths:**
- Two-way cross-checks everywhere a register can drift (marker vs call site, map vs settings, floor vs map, generated table vs committed table) with exit codes tests pin.
- Toggles verified at executor start by a stub snapshot, not by reading the source tree.
- Pre-registered thresholds live in the suite files and the report refuses to write a verdict before the run is complete.
- Replay rows are flagged at the source (`LOA_AUDIT_REPLAY`) by every writer, including the fence corpus and the arm driver.

**Areas for Improvement:**
- Isolate in-process `source` of optional libraries (Observation 1).
- Verify every toggled surface, not only the first (Observation 3).
- Keep header comments and heuristics in step (Observation 4).

---

## Next Steps

1. Proceed to `/audit-sprint sprint-1`.
2. Consider Observations 1 and 3 for the next sprint of this cycle; both have one-line tests.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":3,"low":8},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T08:55:00Z"} -->
