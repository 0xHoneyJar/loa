# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)

---

## Overall Assessment

The change under review is sprint-255: the guard register (`guard-yield.sh`, `guard-origins.yaml`, `floor.yaml`, the generated hooks table), the task-kind rule in `validate-artifact.sh` plus `tools/cycle-ratio.sh`, pre-registered control arms for the eval harness (`execute-agent.sh`, `run-arms.sh`, `arms-report.py`, `seed-corpus-from-record.sh`, `compare-ab.py`) and path-scoped rule files. 81 files, about 8,000 diff lines.

What was verified, not just read: I composed the head files over a framework checkout and executed the new code. `guard-yield.sh --hooks-table` regenerates the committed `hooks-reference.md` block byte for byte; `guard-yield.bats` passes 11/11, `guard-origins.bats` 14/15 (GO-9 fails only because `grimoires/loa/guards.md` is outside this fixture's scope), `validate-artifact-sprint-kinds.bats` 11/11, `rule-paths.bats` 6/6, `cycle-ratio.bats` 6/6, `loa-status-guards.bats` 3/3, `arms-report.bats` 7/7, `arm-toggles.bats` 11/11, `recall-baseline-freshness.bats` BF-10..13 4/4, `eval-recall-grader.bats` RG-28 passes (RG-17 needs the corpus directory, absent here). `sprint-seams.bats` SEAMS-9 and `seed-corpus.bats` need fixtures or graders that are not in this change set and could not be run.

The code is careful and well tested. One defect blocks: the `rule_files` control-arm toggle does not honour the harness's own invariant that an arm never silently runs as its baseline (Changes Required §1). The remaining findings are non-blocking observations, including a reproduced silent exit in `guard-yield.sh` when its optional heredoc library is present, and three functions over the complexity thresholds.

Process note: the implementation report (`pr/PR.md`) carries no `## AC Verification` walkthrough; per the review instructions for this frozen PR that pre-flight is skipped and not counted here.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Control-arm contract: `rule_files` toggle can run an arm as its baseline

- **HIGH** (confidence: high) `head/evals/harness/execute-agent.sh:266` — when neither `stash-safety.md` nor `skill-invariants.md` exists in the sandbox, the `rule_files` toggle records `removed: none present` and continues; the `no_rule_files` arm then runs identically to `baseline`, which the header at `head/evals/harness/execute-agent.sh:65` says is exit 2 ("a toggle that cannot take effect is exit 2 (an arm never silently runs as its baseline)").
**File:** `head/evals/harness/execute-agent.sh:260-267`
**Issue:** Rules are materialised only when the prompt tree has them (`head/evals/harness/execute-agent.sh:146`, `if [[ -d "$PROMPT_TREE/.claude/rules" ]]`). A `--source-commit` that predates the two rule files, or any tree without `.claude/rules/`, makes the toggle a no-op. The post-check at line 264 only asserts absence, which is trivially true. The other three toggles (`companion_voice`, `karpathy_block`, `audit_delta_instruction`) fail closed when they find nothing to remove; this one does not. `arm-toggles.bats` AT-9 covers the fail-closed path for the other toggles but not this one.
**Why This Matters:** The pre-registered verdict in `arms-report.py` reads `no recall loss` for an arm whose only difference from baseline is the evidence string, and `arm_evidence` never reaches the report. SDD D-2.1 and `evals/README.md` say an arm verdict may license removing a control; a null experiment on the rule files would license deleting them. This is exactly the failure the "never silently runs as its baseline" invariant exists to prevent.
**Required Fix:** Fail the trial when nothing was removed, matching the other toggles, and add the AT-9-style case for it:
```bash
# Current (problematic)
_evidence rule_files "removed:${gone:- none present}"

# Should be
[[ -n "$gone" ]] || { echo "ERROR: rule_files toggle: no rule file present in the sandbox .claude/rules/" >&2; return 2; }
_evidence rule_files "removed:$gone"
```
**Reference:** SDD D-2.1 (toggle contract); `evals/README.md` "Control arms and the record corpus" ("fails the trial (exit 2) when a toggle cannot take effect").

---

## Observations

Non-blocking. Medium and low findings, each with a concrete scenario.

### 1. Robustness of the guard register generator

- **MEDIUM** (confidence: medium) `head/.claude/scripts/guard-yield.sh:470` — `source "$HEREDOC_LIB"` runs the library in the generator's own process; a library whose top level exits (or sources something that does) ends `guard-yield.sh` with exit 0, no output and nothing written. Reproduced: with the later-cycle `heredoc-classifier.sh` (which sources the fence) beside this PR's fence, every write-mode run and 7 of 11 `guard-yield.bats` cases silently produced no `guards.md` or yield file while reporting success. The script names a file it does not own as its optional dependency; evaluate the classifier in a subshell (or a `bash -c` helper that prints the indices) so a side effect in the library cannot terminate the generator, and treat "no files written" as a failure.
**Suggestion:** Run the `heredoc_nonexec` loop inside `( source "$HEREDOC_LIB"; ... )` and check `[[ -f "$YIELD_DIR/guard-yield.json" ]]` before the success line.
**Benefit:** An operator regenerating the register cannot be told "wrote" when nothing was written.

- **LOW** (confidence: medium) `head/.claude/scripts/guard-yield.sh:523` — `"fence:" + .pattern_id` adds a string to the raw field; a row whose `pattern_id` is a JSON number (`5` passes the `tostring | test(...)` guard) makes jq abort the whole join and the script exits 3 for one odd row. Use `("fence:" + (.pattern_id | tostring))`.

- **LOW** (confidence: medium) `head/.claude/scripts/guard-yield.sh:443` — `"$AUDIT_LOG".*` also matches `audit.jsonl.lock`, `audit.jsonl.tmp` or editor leftovers beside the log; their contents are read as rows and inflate `audit_rows_unparseable`. Restrict to rotated segments (for example `"$AUDIT_LOG".[0-9]*`).

- **LOW** (confidence: high) `head/.claude/scripts/guard-yield.sh:8` — the header says "one row per unique script" for hooks, but `render_hooks_block` emits one row per registration (`write-mutation-logger.sh` appears twice in the generated table, as GY-8 asserts). Fix the comment.

### 2. Floor design gap (cross-model DISS-C-001, confirmed)

- **MEDIUM** (confidence: medium) `head/.claude/data/guard-origins.yaml:163` — the fence hook row `hook:safety/block-destructive-bash.sh` is `floor: false` while its sixteen `fence:FR-SZ*`/`FR-1.2b` rows are `floor: true` (`head/.claude/data/floor.yaml:14-41`). A change that drops the fence's `PreToolUse:Bash` registration from `settings.json` and its hook row from the map together passes `guard-yield.sh --check` (no dangling row), `guard-origins.bats` (floor rows unchanged; the markers still resolve in the script) and the corpus replay (which executes the script directly). `floor-snapshot.bats` FS-3 catches it only when `origin/main` is reachable, and it skips otherwise. Add `hook:safety/block-destructive-bash.sh` (and its registration) to `floor_guards`, or make `guard-yield.sh` refuse when a floor fence has no registered hook.

### 3. Path-scoped rule semantics (cross-model DISS-C-004, confirmed)

- **MEDIUM** (confidence: medium) `head/.claude/rules/stash-safety.md:2-6` — the `paths:` globs scope the rule to sessions that touch `*.sh`, `*.bats`, `.claude/scripts/**` or `.claude/hooks/**`. The rule governs `git stash` commands the model issues through Bash, which happen in sessions editing only Markdown or YAML too; in those sessions the rule is no longer in context and only the FR-1.2b fence (swallowed-output shapes) remains. If the scoping is deliberate (DEC-0129), record that the unswallowed stash-wrap guidance is now fence-only and cover it with the `no_rule_files` arm result before relying on it.

### 4. Complexity (skill thresholds)

- **MEDIUM** (confidence: high) `head/evals/harness/arms-report.py:176-343` — `suite_report` is 168 lines with nesting over three deep (`for a in order` → `else` → `if reasons … else` → `if not violated … elif`) and no early returns. Split the per-arm verdict (lines 247-305) into a function returning `(verdict, reasons)` and the table/missed-labels rendering into another.
- **MEDIUM** (confidence: high) `head/.claude/scripts/validate-artifact.sh:976-1064` — `validate_sprint_kinds` is 89 lines; the embedded awk parser (lines 1004-1042) duplicates the task-line scanner in `head/tools/cycle-ratio.sh:46-66` (same section-state machine and token regex). Factor the scanner into `lib/` (as `md-fence.awk` already is) so the validator and the release-notes tool cannot drift.
- **LOW** (confidence: high) `head/evals/harness/run-arms.sh:319-384` — `run_trial` is 66 lines with a retry loop four levels deep; extract the attempt body.

`SIMPLICITY`: no over-engineering beyond the above. net: -60 lines possible (shared scanner, split report).

### 5. Smaller defects

- **LOW** (confidence: high) `head/.claude/scripts/loa-status.sh:956` — every `jq -er` failure, including a present-but-malformed `guard-yield.json` or a schema drift between writer and reader, prints `no yield file (.run/guard-yield.json)`. LSG-3 pins this. Say "unreadable yield file" when the file exists so an operator does not regenerate in vain and a schema mismatch is visible.
- **LOW** (confidence: medium) `head/evals/harness/run-arms.sh:314` — `is_transport_failure` greps agent stderr and output for `network` and `5[0-9][0-9] ` anywhere; a review that mentions "network" or a line number like "line 503 " in the model's own output classifies a genuine agent failure as transport and costs a `--retry-wait` (default 300 s) retry. Anchor the patterns to the CLI's error lines.
- **LOW** (confidence: high) `head/.claude/skills/implementing-tasks/SKILL.md:28` — the app zone flips from `read` to `read-write` with no mention in the PR description or title (SURGICAL). The change is probably right for `/implement`, but it changes what `validate-skill-capabilities.sh` and the zone reviewers see; state it, or move it to its own change.
- **LOW** (confidence: low) `head/.github/workflows/check-prompt-budget.yml:5` — the header comment now states 160,000 B / 114,688 B while `tools/check-prompt-budget.sh` is not in this change set; PB-10 (`head/tests/unit/prompt-budget.bats:116-128`) pins the comment to the tool's constants, so this is only a defect if the tool still says 200,000 / 143,360. Could not verify here.
- **LOW** (confidence: medium) `head/.claude/hooks/safety/block-destructive-bash.sh:528` — replay tagging reads the ambient `LOA_AUDIT_REPLAY`; a shell profile or a parent process that exports it marks every live block `replay: true` and the yield under-reports real catches (DISS-C-005). Consider requiring a second marker the harness alone sets (for example the sandbox cwd rule already in `guard-yield.sh`).

### 6. Change-set completeness (cannot verify from the fixture)

- **MEDIUM** (confidence: low) `head/.github/workflows/bats-tests.yml:159` — the new CI gate runs `guard-yield.sh --check`, which exits 1 when `grimoires/loa/guards.md` is absent (`head/.claude/scripts/guard-yield.sh:422`), and that tracked register is not in this change set. `seed-corpus-from-record.sh` excludes `grimoires/` from fixtures (`head/evals/harness/seed-corpus-from-record.sh:307`), so the real PR very likely carries it; confirm the register is committed and in sync, or the first CI run after merge is red.
- **LOW** (confidence: low) `head/evals/tasks/review-recall/review-pr-11.yaml:5` — the sixteen new tasks reference fixtures `review-prs/pr-11` … `pr-18`, hidden manifests and labels that are not in this change set; `run-arms.sh` refuses a missing fixture or manifest (exit 2). Same caveat about fixture scope.

---

## Cross-Model Observations

Adversarial review ran on `pr/head.diff` (primary `gpt-5.5-pro`, companion `claude-headless`, `counted_as: independent_voice`, status `clean`). Five advisory findings, none blocking, none rejected:

- DISS-C-001 floor gap — confirmed, recorded as Observation §2.
- DISS-C-002 `⇐` deps parser — not a defect: `create-sprint-task.sh` takes `--deps` as an explicit argument; no script slices the task line.
- DISS-C-003 malformed yield reads as missing — confirmed, Observation §5 (LOW).
- DISS-C-004 stash-safety scoping — confirmed, Observation §3.
- DISS-C-005 ambient `LOA_AUDIT_REPLAY` — confirmed, Observation §5 (LOW).

## Rejected dissent payloads

None: `metadata.rejected_summary` is empty and no `adversarial-rejected-review*.jsonl` sidecar was written.

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| Review the pull request | Pass | Every touched file read; new scripts and tests executed on a composed head tree (results in Overall Assessment) |
| Report each defect with file and line | Pass | One HIGH under Changes Required; 16 observations with `head/<path>:<line>` citations |
| Give a merge verdict | Pass | CHANGES_REQUIRED (one high; one-way rule) |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (seed tool redacts secret shapes and runs `no-secrets.sh`; fixtures assemble fake keys at test time)
- [x] Input validation at trust boundaries (`guard-yield.sh` canonical hook schema, control-character and id checks; `run-arms.sh` argument regexes; `seed-corpus` path checks)
- [x] No shell injection from data (ids pass `^[A-Za-z0-9._/:-]+$`; `--approve --by` is validated; `python3 -I` for parsers)
- [x] Privacy: yield outputs carry no command text, cwd or model name (GY-5 passes)
- [x] Error messages don't leak sensitive data

---

## Code Quality Summary

**Strengths:**
- Every new script ships with a bats suite that drives real inputs (fixture audit logs, a throwaway git repo with base/head/fix/record commits, a stubbed CLI); the suites pass on the head tree.
- `guard-yield.sh` fails closed on schema violations (exit 5) and keeps the tracked register structural so `--check` is deterministic.
- The control-arm design records provenance (source commit, toggles, evidence, refusal fallbacks) and refuses skewed comparisons.

**Areas for Improvement:**
- The `rule_files` toggle breaks the one invariant the arm design states (Changes Required §1).
- Long functions in `arms-report.py`, `validate-artifact.sh` and `run-arms.sh`; a duplicated task-line scanner.
- The generator trusts an optional library it does not own.

---

## Next Steps

1. Fix the `rule_files` toggle to fail closed and add the AT-9 case for it.
2. Address or explicitly accept the medium observations (generator subshell, floor row, stash-safety scope, complexity).
3. Confirm `grimoires/loa/guards.md` and the record fixtures are in the real change set.
4. Update the report in `grimoires/loa/a2a/sprint-1/reviewer.md` and request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":6,"low":10},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T13:22:07Z"} -->
