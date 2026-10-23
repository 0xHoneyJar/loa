# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md
**Change under review:** `pr/head.diff` — feat(cycle-129): sprint-255 — guard register with origin and yield, pre-registered control arms on a record corpus, task kinds, path-scoped rule files (81 files)

---

## Overall Assessment

This is a large, well-tested change. The guard register (`guard-yield.sh`, `guard-origins.yaml`, `floor.yaml`) is internally consistent: regenerating the register from the PR's origin map, the PR's fence and validator markers and the live hook settings reproduces the PR's `hooks-reference.md` table byte for byte, `--check` reports in sync (95 guards), and every bats suite I could run against the head files passes (guard-origins 15/15, guard-yield 11/11, validate-artifact sprint-kinds 11/11, cycle-ratio 6/6, loa-status-guards 3/3, arms-report 7/7, arm-toggles 11/11, recall grader RG-28, compare BF-10..13, execute-agent EA-11/12). The task-kind validator, the kind-count tool and the control-arm toggles do what their tests say.

One defect blocks: `run-arms.sh` is not idempotent on its own deterministic batch name. The script explicitly admits a second run into a batch that already holds results for the same source and model, then re-plans every trial from scratch, appends duplicate rows to `results.jsonl`, overwrites the per-trial artifacts and resets the STATUS counters. `arms-report.py` counts every row, so the pre-registered verdict that licenses deleting a control can be computed over duplicated trials while STATUS.json reads `complete`. Several medium observations follow, three of them raised by the cross-model dissent (two voices, no rejected payloads).

Scope note: the fixture excludes `grimoires/` and the record corpus under `evals/fixtures/review-prs/`, so the tracked register `grimoires/loa/guards.md`, the eight record fixtures, their hidden labels and `SHA256SUMS` could not be inspected; nothing below claims a defect in them. The implementation report (`reviewer.md`) is the PR description and carries no `## AC Verification` walkthrough; the verdict below rests on the code finding, not on that omission.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Control-arm driver: re-running a batch duplicates trials and corrupts the verdict inputs

- **HIGH** (confidence: high) `head/evals/harness/run-arms.sh:255-257` — a second `run-arms.sh` invocation on an existing batch with the same source commit and model is admitted, re-plans every trial, appends duplicate rows and resets the counters, so the control-arm report and STATUS.json no longer describe one experiment.
**File:** `head/evals/harness/run-arms.sh:255-257` (admission), `:126` (deterministic default batch name), `:264` (counters restart at 0), `:408` (rows appended with `>>`), `:409-420` (artifacts copied over the previous trial's), `head/evals/harness/arms-report.py:135` and `:239` (every row is a cell; coverage counts duplicates)
**Issue:** The default `--batch` is a pure function of the fixture list (`batch-pr-01-pr-08-n8`). The pre-flight at lines 251-256 refuses a batch only when the recorded source or model differs; with the same pair it falls through to `write_manifest` (overwriting MANIFEST.json), rebuilds `PLAN` from scratch, starts `DONE`/`FAILED` at zero and appends each new row to `<arm>/results.jsonl` without reading what is already there. There is no resume, skip or de-duplication path. The script's own exit contract ("1 partial (some trial failed twice; results kept)") invites exactly this re-run to fill the gaps.
**Why This Matters:** `arms-report.py` is the pre-registered gate that may license removing a guard. After a re-run it sees two (or more) rows per (fixture, trial) cell: `fixture_means` and `trial_means` are biased toward whichever run was duplicated, `coverage_gaps` is satisfied by duplicates, `trials done` exceeds `trials_planned`, and STATUS.json still says `complete` with `trials_done` counting only the last run. The artifacts under `trial-N/` are overwritten while both rows survive, so the row/artifact pairing is broken. `run-arms.bats` RA-3 re-runs only with fresh `--batch` names, so the suite never exercises this path.
**Required Fix:** Either refuse a batch whose `<arm>/results.jsonl` already exists ("use another --batch", the same shape as line 255), or implement a real resume: read existing rows, skip (arm, fixture, trial) cells that already have a `completed` row, seed `DONE`/`FAILED` from them and keep MANIFEST.json. Add an RA test that re-runs the same batch and asserts one row per cell.
**Reference:** SDD D-2.3 (pre-registered verdict rule; the report must be computed over the planned cells exactly once).

---

## Observations

### 1. Guard register and floor

- **MEDIUM** (confidence: medium) `head/.claude/scripts/guard-yield.sh:470` — the heredoc classifier is sourced into the generator's own process; a lib whose sourced fence does not honour library mode runs the fence as a hook and ends `guard-yield.sh` with exit 0 and nothing written.
**File:** `head/.claude/scripts/guard-yield.sh:470`
**Suggestion:** Observed directly: with a `heredoc-classifier.sh` that sources the fence (`BDB_LIB_ONLY=1 source …`) and a fence without that mode, the trace stops at `source` and the script exits 0 before `install_file`; `--check` cannot catch it because it exits before the yield section. Call `heredoc_nonexec` through a subshell (`( source …; heredoc_nonexec "$cmd" )`) or verify the lib with `bash -n`/a probe in a subshell before sourcing, and treat a missing summary line as failure.
**Benefit:** The yield generation cannot silently produce no files while reporting success.

- **MEDIUM** (confidence: medium) `head/.claude/data/floor.yaml:42-50` — the floor advertises protections it does not pin: `implement_gate.*` is a floor key while `gate:implement-gate` and `hook:compliance/implement-gate.sh` are `floor: false` (`head/.claude/data/guard-origins.yaml:810`); `policy:permission-deny-list` is enforced by `permissions.deny` in `.claude/settings.json`, which `floor_files` does not pin (FS-3 pins only `.hooks`); `policy:operator-only-commands` is enforced by each command's `disable-model-invocation` frontmatter, not by `user-invoked-commands.txt` alone. Raised by the companion dissent (DISS-C-003).
**Suggestion:** Pin `.claude/settings.json` (or diff its `permissions.deny` against `settings.deny.json` in floor-snapshot.bats), cross-check `user-invoked-commands.txt` against the command files' frontmatter, and make `floor_keys` and the `floor:` rows agree on implement-gate.
**Benefit:** A cycle task cannot loosen a floor artefact while both floor suites stay green.

### 2. Rule files and skill frontmatter

- **MEDIUM** (confidence: medium) `head/.claude/rules/stash-safety.md:2-6` — path-scoping the stash rule to `*.sh`, `*.bats`, `.claude/scripts/**`, `.claude/hooks/**` makes the prose guard conditional on which files are edited, but `git stash push/pop … | tail -1` is typed into Bash regardless of the files in play; in an app-code session only the harness regex (FR-1.2b) remains. Raised by the companion dissent (DISS-C-001); rule-paths.bats attributes the globs to SDD D-3.1 / DEC-0129, so this is a recorded decision, flagged here as a residual risk.
**Suggestion:** Record in the DEC row that the fence, not the prose, is the only stash guard in non-shell sessions, or widen the globs.
**Benefit:** The decision's cost is explicit where the floor is reasoned about.

- **MEDIUM** (confidence: medium) `head/.claude/skills/implementing-tasks/SKILL.md:28` — `zones.app.permission` changes from `read` to `read-write`. SURGICAL: the PR title names the guard register, control arms, task kinds and path-scoped rule files; this hunk is none of them and is not explained in the diff. Also raised by the companion dissent (DISS-C-002).
**Suggestion:** The value is probably right (`/implement` is the skill that writes app code and `reviewing-code/SKILL.md` now points at the frontmatter as the zone source), but a security-relevant declaration should move with a one-line rationale or a DEC row.
**Benefit:** Anything that later consumes `zones:` (validate-skill-capabilities.sh, implement-gate) inherits an audited change, not drift.

### 3. Control-arm harness

- **MEDIUM** (confidence: medium) `head/evals/harness/run-arms.sh:326` — `date +%s%N | cut -c1-13` is GNU-only; on BSD/macOS `date` prints a literal `N`, so `$(( end_ms - start_ms ))` is an arithmetic error inside the background job under `set -e`, no row is written and every trial is `FAILED (no row written)`. The script states bash 3.2 compatibility (line 263) and the default model id was probed on a local CLI.
**Suggestion:** Use `python3 -c 'import time;print(int(time.time()*1000))'` (python3 is already a required tool) or seconds via `date +%s`.
**Benefit:** The driver runs where its author's own comments say it should.

- **LOW** (confidence: medium) `head/evals/harness/run-arms.sh:314` — `is_transport_failure` greps `agent-output.json` for `network` and `5[0-9][0-9] `; the executor's result text (a review that mentions a network call or a line number followed by a space) can classify a genuine agent error as transport and spend the one retry.
**Suggestion:** Match the stderr log and the structured `api_error_status`/`subtype` fields only, not the result text.

- **LOW** (confidence: high) `head/evals/harness/run-arms.sh:301` and `:79` — `aggregate_status` passes `$(find …)` unquoted to `jq -s`, and `--results-dir` is not validated, so a results directory with a space breaks the suite-level STATUS.json silently (`2>/dev/null`).
**Suggestion:** Validate `--results-dir` against the same character class as `--batch`, or feed the file list through `find -print0 | xargs -0`.

- **LOW** (confidence: medium) `head/evals/harness/execute-agent.sh:158` — in arm mode the prompt tree's `.loa.config.yaml` is copied over the sandbox after materialisation, clobbering any config the fixture itself carried; `:256` creates a `constraints` key in a sandbox `constraints.json` that had none.
**Suggestion:** Copy only when the sandbox has no config (or record the clobber in `arm_evidence`); use `if has("constraints") then … else . end` for the jq edit.

- **LOW** (confidence: high) `head/evals/harness/seed-corpus-from-record.sh:128`, `:331`, `:736`, `:740` — `REDACTED[0]` is incremented for the diff text and again for every base/head file written, so the "N secret-shaped test string(s) redacted" note in `labels/pr-NN.dropped.txt` over-reports by up to 3x.
**Suggestion:** Count once (the diff pass) and pass `count=False` to the file writes.

- **LOW** (confidence: medium) `head/evals/harness/seed-corpus-from-record.sh:312` — `p.split(" => ")[-1].strip("{}")` mis-parses git's abbreviated rename form `dir/{old => new}/file` (yields `new}/file`), so a renamed binary is not excluded from the fixture scope.
**Suggestion:** Expand `{a => b}` with a regex before taking the new name, or use `--name-status -M` output (already parsed below) to find renames.

- **LOW** (confidence: medium) `head/evals/harness/arms-report.py:219-220` — `sorted({m.get('source_commit') …})` raises `TypeError` when one manifest lacks the key (None beside str); every manifest run-arms.sh writes carries both, so only a hand-edited or foreign manifest trips it.
**Suggestion:** Filter `None` before sorting (the join already does).

### 4. Guard yield heuristics

- **LOW** (confidence: medium) `head/.claude/scripts/guard-yield.sh:443` and `:457-458` / `:500` — `"$AUDIT_LOG".*` also reads sibling files such as `audit.jsonl.lock` or `.bak` as segments (they only inflate `audit_rows_unparseable`), and the replay rule's temp prefix is the generator's own `TMPDIR`, so `TMPDIR=/` classifies every row as replay.
**Suggestion:** Restrict segments to `audit.jsonl.[0-9]*` and skip the prefix rule when it resolves to `/`.

### 5. Documentation and process

- **LOW** (confidence: low) `head/.github/workflows/check-prompt-budget.yml:5` and `head/tests/unit/prompt-budget.bats:113` — the header comment now states 160,000 / 114,688 B and PB-10 pins it to constants in `tools/check-prompt-budget.sh`, which is not in the change; the pin could not be verified here.
**Suggestion:** None if the tool already carries those constants; otherwise PB-10 is red on merge.

- **LOW** (confidence: high) `grimoires/loa/a2a/sprint-1/reviewer.md` — the implementation report is the PR description and has no `## AC Verification` walkthrough, no fast-gate (shellcheck/bats) evidence and no statement of assumptions (Think Before Coding). Not counted against the code; noted for the next round's report.

---

## Rejected dissent payloads

None. `adversarial-review.json` carries `rejected_summary: []` and `rejected_sidecars: []`; both voices (primary `gpt-5.5-pro` via codex-headless: clean; companion `claude-headless`: three ADVISORY findings) returned well-formed payloads. The three companion findings are triaged above as observations DISS-C-001 (stash-safety scoping), DISS-C-002 (implementing-tasks permission) and DISS-C-003 (floor pinning).

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| "review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict" (sprint.md Success Criteria) | Done | One blocking defect (run-arms.sh re-run), five medium and nine low observations, each with a `head/<path>:<line>` citation; verdict CHANGES_REQUIRED. |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (the seed script redacts secret shapes and runs `no-secrets.sh`; the test fixture assembles its fake key at runtime)
- [x] Input validation at trust boundaries (arm ids, batch names, fixture ids, commit ids, `--by`, `--now` are all regex-gated; hook commands are parsed against a canonical schema)
- [x] No shell injection paths found in the new scripts (values reach yq via `strenv`, jq via `--arg`)
- [x] Error messages do not leak command text, cwd or model names from the audit log (GY-5 passes)
- [ ] Floor completeness: see the MEDIUM on `floor.yaml:42-50`

---

## Code Quality Summary

**Strengths:**
- The register is a pure function of the repository and the drift gate is exercised in CI; my regeneration from the PR inputs matched the committed hooks table exactly.
- Every new script has a bats suite with failure-mode fixtures, and the suites pass against the head code.
- The control-arm toggles are verified from the executor's point of view (stub snapshots), not from the harness's.

**Areas for Improvement:**
- `run-arms.sh` needs an idempotent re-run story (the blocking finding).
- Portability claims (bash 3.2) are not matched by the GNU-only `date` call.
- Two security-relevant declarations (`zones.app.permission`, path-scoped `stash-safety.md`) changed without an in-diff rationale.

**Checks run by the reviewer:** fence-marker enumeration against the head fence (34 ids, 0 errors); origin-map, floor and validator cross-checks (all sets match); `guard-yield.sh --hooks-table` then `--check` on a composite root (in sync, 95 guards; `hooks-reference.md` identical to the PR); bats suites listed in the Overall Assessment. Not run: `run-arms.bats` and `seed-corpus.bats` (need `sandbox.sh`, `grade.sh`, `no-secrets.sh` and the record corpus, none in the fixture); `floor-snapshot.bats` (needs `origin/main`); `rule-paths.bats` RP-3/RP-4 (need the tracked file list).

Complexity: `run_trial` (~60 lines) and the `validate_sprint_kinds` awk are at the limit but single-purpose; no circular dependencies. Over-engineering pass: Lean already. Ship.

---

## Next Steps

1. Fix the `run-arms.sh` re-run path (refuse or resume) and add an RA test for a same-batch re-run.
2. Decide the floor and declaration observations (floor pinning, `zones.app.permission`, stash-safety scoping) with a DEC row each, or revert.
3. Re-run `bats tests/unit evals/tests` and `guard-yield.sh --check`; update `grimoires/loa/a2a/sprint-1/reviewer.md` with an `## AC Verification` walkthrough.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":5,"low":9},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T10:40:00Z"} -->
