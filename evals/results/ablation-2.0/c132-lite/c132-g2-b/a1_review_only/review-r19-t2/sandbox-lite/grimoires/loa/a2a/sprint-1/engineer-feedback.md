All good

Sprint 1 has been reviewed and approved. Observations documented and non-blocking. See Observations below.

# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (pr/PR.md: sprint-255 — guard register with origin and yield, pre-registered control arms on a record corpus, task kinds, path-scoped rule files; 81 files)

---

## Overall Assessment

The change is large (81 files, ~8,000 diff lines) and well-built. The three new scripts (`guard-yield.sh`, `run-arms.sh`, `seed-corpus-from-record.sh`), the `arms-report.py` verdict logic, the `validate_sprint_kinds` rule and the control-arm toggles in `execute-agent.sh` each ship with a bats suite that pins the failure modes, not just the happy path. I ran those suites against the PR's own files in scratch trees (the eval sandbox cannot execute the frozen `pr/head` tree in place): guard-yield 11/11, guard-origins 15/15, loa-status-guards 3/3, validate-artifact-sprint-kinds 11/11, sprint-seams 11/12 (SEAMS-9 needs a fixture outside the diff), cycle-ratio 6/6, arms-report 7/7, eval-recall-grader RG-28, recall-baseline-freshness BF-10..13, execute-agent EA-11/EA-12, arm-toggles 11/11, seed-corpus 6/6 (with `no-secrets.sh`, which is not in the diff, stubbed). Not run here: run-arms.bats (needs `sandbox.sh`, `grade.sh` and the pr-01 fixture), floor-snapshot (needs `origin/main`), rule-paths, prompt-budget PB-10.

I also cross-checked the fence markers against the origin map with the script's own awk (34 fence ids, 20 validator ids, all matched both ways), confirmed the generated hooks table in `hooks-reference.md` is byte-identical to what `guard-yield.sh --hooks-table` produces from the head origin map and the hook registrations, and confirmed `--check` passes once `grimoires/loa/guards.md` is generated.

No critical or high finding. The mediums are a possibly incomplete change set (record fixtures referenced but not shipped), one robustness gap in how `guard-yield.sh` sources its optional classifier, one design consequence of path-scoping the stash rule, an undocumented permission widening and oversize functions. None breaks delivered behaviour at head in a way I could demonstrate, every item carries a concrete scenario and a fix, and the test evidence is strong, so I am exercising the "pile of medium/low is your call" discretion in favour of approval. The complexity BLOCK rule (functions over 50 lines) is applied as `SIMPLICITY[shrink]` observations because every oversize function sits in a file whose header states its design and the repository's existing validators and harness scripts follow the same shape; the lead may still want the `arms-report.py` split before the Sprint 2 gate reads it.

Think Before Coding: `reviewer.md` is the PR description only (the evaluation brief says to skip steps that need the implementation report), so the AC-Verification automatic rule is not applied; the brief's single criterion is checked below.

**Verdict:** APPROVED

---

## Observations

### 1. Completeness — record fixtures referenced but not in the change set

- **MEDIUM** (confidence: medium) `head/evals/tasks/review-recall/review-pr-11.yaml:5` — the eight new review tasks and eight audit tasks (`review-pr-11..18`, `audit-pr-11..18`) name `fixture: review-prs/pr-NN`, and `head/evals/README.md:514` describes `record-pairs.tsv`, the hidden `labels/` and `manifests/` and a refreshed `SHA256SUMS`; none of those files is in this change (no `evals/fixtures/review-prs/` path in `head.diff`). `head/evals/suites/review-recall.yaml:7` and `head/evals/suites/audit-recall.yaml:7` glob `tasks/<suite>/**/*.yaml`, so both suites now contain tasks whose fixture directory `sandbox.sh create` cannot find, and `run-arms.sh --fixtures pr-11` dies at its fixture check.
**Suggestion:** Either ship the seeded fixtures, labels, manifests, `record-pairs.tsv` and `SHA256SUMS` in this change (the `.gitignore` edit un-ignoring `evals/fixtures/review-prs/*/*/.claude/skills/bridgebuilder-review/dist/` suggests that was the intent), or hold the sixteen task files until the fixtures land. If they were committed outside the base..head range, say so in the PR body.
**Benefit:** The recall suites stay runnable at every commit; the control-arm batch documented in the README can be reproduced from the merge commit.

### 2. Robustness — inline `source` of the optional heredoc classifier

- **MEDIUM** (confidence: medium) `head/.claude/scripts/guard-yield.sh:470` — `source "$HEREDOC_LIB" 2>/dev/null` runs the classifier in the script's own process. Anything that `exit`s inside it, or inside what it sources (the classifier is documented to source the fence in lib-only mode), ends `guard-yield.sh` with that status. I reproduced it with a classifier whose fence lacks `BDB_LIB_ONLY` handling: the fence runs as a hook, finds no stdin and `exit 0`s, so `guard-yield.sh` prints only the audit-log WARN, writes neither `guards.md` nor the yield files, and returns 0. No such library ships at head, so the PR's own tests pass; the hazard is a later classifier or fence edit. `--check` is unaffected because it exits before line 468.
**Suggestion:** Probe in a subshell first (`( source "$HEREDOC_LIB" && declare -F heredoc_nonexec ) >/dev/null 2>&1 || HEREDOC_LIB=""`), or run the classification loop (lines 471-483) inside a subshell that writes the index file, and treat a non-zero probe as "no classifier".
**Benefit:** A yield run can never report success without its outputs.

### 3. Design consequence — path-scoping the stash rule

- **MEDIUM** (confidence: medium) `head/.claude/rules/stash-safety.md:2-6` — the new `paths:` globs (`**/*.sh`, `**/*.bats`, `.claude/scripts/**`, `.claude/hooks/**`) load the rule only when such a file is read or edited. The rule is about `git stash` commands typed into the Bash tool, which touch no shell file, so in a Bash-only session the prose guidance about pre-commit `--keep-index` index shifts is no longer in context; the floor fence FR-1.2b covers only the swallowed-output forms. `tests/unit/rule-paths.bats` RP-2 records these globs as the SDD's (D-3.1, DEC-0129), so this is a decided design, and the `no_rule_files` arm is the instrument that measures it. Raised by the dissent as DISS-C-002.
**Suggestion:** Record the residual gap in the DEC-0129 row or the rule's body, and make the `no_rule_files` arm's missed labels the explicit evidence gate before any further narrowing of the globs.
**Benefit:** The data-loss pattern the rule exists for (recurred cycle-122) is tracked rather than assumed covered.

### 4. SURGICAL — undocumented permission widening in the implement skill

- **MEDIUM** (confidence: high) `head/.claude/skills/implementing-tasks/SKILL.md:28` — the app zone's `permission` moves from `read` to `read-write` with no mention in the PR title or body. The substance is plausibly right (`/implement` is where app writes are sanctioned), but `skill-invariants.md` in this same diff frames zone frontmatter as a control surface and `floor.yaml` protects `implement_gate.*`, so a silent widening inside a guard-register PR is exactly what the register is meant to make visible. Confirmed by the dissent as DISS-C-003.
**Suggestion:** Name the change and its reason in the PR body (or a DEC row), or split it out.
**Benefit:** Reviewers and the register can tell intended widenings from drift.

### 5. SIMPLICITY[shrink] — functions over the 50-line threshold

- **MEDIUM** (confidence: high) `head/evals/harness/arms-report.py:176` — `suite_report` runs ~170 lines and mixes loading, coverage checks, the three-rule verdict, bootstrap, row rendering and the missed-labels list; `head/evals/harness/run-arms.sh:319` `run_trial` is 67 lines; `head/.claude/scripts/validate-artifact.sh:976` `validate_sprint_kinds` is 94 lines (mostly one awk program); `head/evals/harness/seed-corpus-from-record.sh:57` embeds ~740 lines of straight-line Python with the label pipeline at top level. Each file's header states the design, which is the justification the BLOCK rule allows.
**Suggestion:** Extract `verdict_for_arm(arm, base, thresholds)` and `render_arm_row(...)` from `suite_report`; lift the seed script's label pipeline into functions (`parse_feedback`, `locate`, `anchor`, `write_fixture`). net: -150 lines possible.
**Benefit:** The verdict rule, which the Sprint 2 gate will read, becomes unit-testable on its own.

### 6. Error handling — swallowed jq failure in the Karpathy toggle

- **LOW** (confidence: high) `head/evals/harness/execute-agent.sh:256` — `(.constraints // []) |= map(...)` is not a valid update path when `.constraints` is absent; jq exits 5 with "Invalid path expression with result []" (verified). The failure is swallowed inside `apply_toggles || exit 2` (line 280), `constraints.json` is left untouched, `constraints.json.tmp` is left in the sandbox and `arm_evidence.karpathy_block` still reports success. The real `constraints.json` carries the key, so the arm is unaffected today. Raised by the dissent as DISS-C-005 (its "exit 2" reading is not what happens; the error is silent).
**Suggestion:** `jq 'if has("constraints") then .constraints |= map(...) else . end'` and fail the toggle on a non-zero jq.

### 7. run-arms.sh — lock, process tree and retry heuristics

- **LOW** (confidence: medium) `head/evals/harness/run-arms.sh:287` — a `.status.lock` directory left by a crashed run (SIGKILL between `mkdir` and `rmdir`) is never cleaned; every later `aggregate_status` gives up after ~5 s and returns 0, so the suite-level `STATUS.json` silently stops updating while the batch continues. `:246` — `cleanup` kills the job subshells only; a running `execute-agent.sh`/CLI grandchild survives an interrupted batch. `:301` — `$(find …)` is unquoted (a `--results-dir` with spaces breaks the aggregate). `:314` — the transport pattern `5[0-9][0-9] ` matches any "5xx " token in stderr (a line number, a byte count), so a non-transport failure can be retried and counted as `transport_error`.
**Suggestion:** Treat a stale lock dir by pid token like the batch lock; `kill -- -$pgid` or `setsid` the trial job; quote via `find … -print0 | xargs -0`; anchor the HTTP status pattern (`HTTP/[0-9.]+ 5[0-9][0-9]|status(=| )5[0-9][0-9]`).

### 8. seed-corpus-from-record.sh — redaction count

- **LOW** (confidence: high) `head/evals/harness/seed-corpus-from-record.sh:756` — `REDACTED[0]` is incremented for `head.diff` (line 331), again for every `base/` write (line 736) and again for every `head/` write (line 740), so the dropped-report line overstates the number of secret-shaped strings by up to 3x.
**Suggestion:** Count once (the `head.diff` pass) or report per-location counts.

### 9. Yield heuristics — unauthenticated replay flag and dead `deny` branch

- **LOW** (confidence: medium) `head/.claude/hooks/safety/block-destructive-bash.sh:528` — `LOA_AUDIT_REPLAY=1` is read from the hook's environment with no check that the caller is a corpus runner. A Bash-tool `VAR=1 cmd` prefix does not reach the hook, but an operator shell that exported it for a corpus run and then launched Claude Code tags every real block as `replay: true` for the whole session, and `guard-yield.sh` then reports zero real blocks for guards that fired. The fence still blocks; only the report is wrong. Raised by the dissent as DISS-C-001.
- **LOW** (confidence: high) `head/.claude/scripts/guard-yield.sh:528` — `block: (.action == "block" or .action == "deny")` is unreachable for `deny`: `$cand` at line 516 admits only `action == "block"` rows (plus implement-gate rows), so a hook that logs `deny` is never counted. Either widen line 516 or drop the `deny` alternatives at 528 and 530.
- **LOW** (confidence: medium) `head/.claude/scripts/guard-yield.sh:443` — `"$AUDIT_LOG".*` also matches non-JSONL siblings (`audit.jsonl.lock`, `.tmp`) and feeds their lines to the parser as unparseable rows.
- **LOW** (confidence: medium) `head/.claude/scripts/guard-yield.sh:529` — only the fence honours the replay flag; `implement-gate.sh` and the other audit writers do not, so bats replays of implement-gate rows inflate `telemetry_30d` unless the cwd or burst heuristics catch them.

### 10. Fragile suite exclusion for the task-kind fixture

- **LOW** (confidence: high) `head/evals/tasks/review-recall/review-kind-01.yml:1` — the task stays out of the review-recall suite only because the suite globs `*.yaml` and this file is `.yml`; `run-eval.sh` task discovery (head lines 198 and 283) finds both extensions, so a "run every task" invocation includes it despite the `not-in-ci` tag and the description.
**Suggestion:** Move it under `evals/tasks/review-kinds/` or give suites an explicit exclude/tag filter.

### 11. Items I could not verify from the change set

- **LOW** (confidence: low) `head/.github/workflows/check-prompt-budget.yml:5` and `head/tests/unit/prompt-budget.bats:7` — both comments now say 160,000 B (warn 114,688 B) while `tools/check-prompt-budget.sh` is not in the diff; PB-10 pins the comment to the tool's constants, so this is either a stale-comment fix or a red test. Confirm PB-10 passes.
- **LOW** (confidence: low) `head/.github/workflows/bats-tests.yml:159` — the new CI drift gate and GO-9 need `grimoires/loa/guards.md` tracked and in sync; `grimoires/` is outside this frozen view, so I generated it and confirmed `--check` passes, but could not confirm it is committed. Same for the CHANGELOG entry per task.
- **LOW** (confidence: low) `head/.claude/skills/planning-sprints/resources/templates/sprint-template.md:60` — the dissent (DISS-C-004) asks whether whatever turns `⇐ {blockers | none}` into bead `--deps` tolerates the trailing `· kind: …` token. No script in the repository parses the marker (only `validate-artifact.sh` mentions it), so this is prose-driven and speculative; worth one line in the planning skill.

---

## Cross-Model Observations

Adversarial review: `adversarial-review.sh --type review --sprint-id sprint-1 --diff-file pr/head.diff` (envelope `grimoires/loa/a2a/sprint-1/adversarial-review.json`). Primary voice gpt-5.5-pro: `status: clean`, 0 findings, over 11 of 81 files that fit the budget. Companion voice claude-headless (independent voice): 6 ADVISORY findings, none blocking.

- DISS-C-001 (replay flag unauthenticated) — real, folded into Observation 9.
- DISS-C-002 (stash rule path-scoping) — real design consequence, folded into Observation 3.
- DISS-C-003 (implement skill app zone read → read-write) — confirms Observation 4.
- DISS-C-004 (template `⇐ … · kind:` and bead deps) — speculative, no mechanical parser exists; Observation 11.
- DISS-C-005 (jq alt-path on absent `.constraints`) — confirmed by running jq; its "exit 2" consequence is wrong (the error is swallowed), Observation 6 states the real effect.
- DISS-C-006 (inline `source` of the classifier) — confirms Observation 2; its claim that `--check` becomes a no-op is wrong, `--check` exits before the lib is sourced.

No dissent payload was rejected (`metadata.rejected_summary` is empty, no sidecar written).

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| "review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict" (task-brief.md) | Pass | Every observation above cites `head/<path>:<line>`; verdict APPROVED with 5 medium and 11 low observations, none blocking |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (seed script redacts secret shapes and runs `no-secrets.sh`; fixtures assemble fake keys at test time)
- [x] Input validation and sanitization present (arm ids, fixture ids, commit ids, batch names, model ids, feedback file names, `--by` all regex-gated; yield outputs carry no command text, cwd, host or model; table cells strip control characters and escape pipes; `python3 -I` for every embedded parser)
- [x] Authentication/authorization correct (n/a; the replay flag's trust gap is Observation 9 and affects a report, not a guard)
- [x] No SQL/XSS injection vulnerabilities (markdown tables sanitised; no shell `eval`)
- [x] Dependencies secure (jq, yq v4, python3 stdlib; `yq` version pinned by sha256 in CI)
- [x] Error messages don't leak sensitive data (seed drops a finding's text when it matches a secret pattern)

---

## Code Quality Summary

**Strengths:**
- The guard register is a pure function of the repository, drift-gated in CI, with the hand-written origin map validated both ways against the fence markers, the validator markers and the hook registrations; the floor set is pinned by sha256 and cross-checked.
- Control arms are pre-registered (ids, toggles, thresholds, bootstrap) in the suite files, applied to the sandbox copy only, and every toggle is verified to have taken effect or the trial fails; the report refuses to write verdicts before a run is complete.
- Tests pin failure modes: replay exclusion by three rules, the FP heuristic, drift in both outputs, exit codes for every refusal, model and source skew, refusal fallbacks, the fix-touches-file label rule, secret rejection.
- Privacy of the yield (no command text, cwd, host or model) is tested, not asserted.

**Areas for Improvement:**
- Oversize functions in `arms-report.py` and the seed script (Observation 5).
- Sourcing optional libraries inline (Observation 2).
- Scope hygiene: the implement-skill permission change and the missing record fixtures should be named in the PR body (Observations 1 and 4).

---

## Next Steps

1. Confirm the record fixtures, labels, manifests and `SHA256SUMS` are committed, or hold the sixteen task files.
2. Guard the classifier `source` with a subshell probe; fix the `constraints` jq path.
3. Name the implement-skill zone change in the PR body or a DEC row.
4. Optional before Sprint 2: split `suite_report` so the verdict rule is unit-testable.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":5,"low":11},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T17:45:00Z"} -->
