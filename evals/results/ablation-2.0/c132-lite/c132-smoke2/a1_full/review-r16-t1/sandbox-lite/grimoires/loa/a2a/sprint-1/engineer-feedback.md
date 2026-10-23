# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)

---

## Overall Assessment

The change under review is "sprint-252 decision surfaces, part 1": a new append-only decision ledger
(`grimoires/loa/decisions.yaml`) with a single writer (`dec-write-lib.sh`), a `--type decisions`
validator, an operator-only `/decisions` command fenced by `disable-model-invocation`, a
default-off SessionStart surface, a `decisions` family in the grimoire index, interview `rounds`
pacing with an independence checker, and the `[ASSUMPTION fact|decision]` tag classes.

The engineering is careful where it is careful: values reach yq only through `env()`, rows are
built with `jq --arg`, every write is verified against the pre-write snapshot and re-validated
before an atomic rename, the SessionStart surface fences agent-authored text behind the L6
sanitizer, and the test corpus is unusually strong (hostile-string round-trips, lock contention,
worktree import, CI refusal, a live harness probe with an offline classifier). All eight bats
suites were executed against the head files in a scratch checkout; the new tests pass.

The ledger's one job is attribution: "which decisions did a human take?" Four defects break that
job or the ledger's "never drops a row" contract, and each was reproduced by running the head
scripts, not inferred from the diff. Two are in the writer's `confirm`/`import` paths, one is a
missing file the whole feature depends on, one is a race in `import`. They are listed under
Changes Required. Nine further medium/low observations follow.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Attribution: an interactive `/decisions confirm` is recorded as the agent's decision when the PRD Status line names an autonomous run

- **HIGH** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:513` — `op_confirm` calls `derive_attribution 0`, which at lines 313-316 discards `--answer-ref` whenever `is_unattended` is true, while the refusal at line 509 only honours `live_run_signal`. The PRD-status signal (`ctx_signals`, line 179) therefore lets the confirm proceed but strips the operator's `cli:` ref, and line 538 then derives `decided_by` from the now-null ref as `.proposed_by`.
**File:** `head/.claude/scripts/lib/dec-write-lib.sh:509-538`
**Issue:** Reproduced on the head script: with `grimoires/loa/prd.md` containing `**Status:** Draft, autonomous run`, `confirm --id DEC-0001 --recorded-by decisions-command --evidence cli:… --answer-ref cli:…` exits 0, prints only a WARN, and the row lands `{"status":"decided","decided_by":"agent","decided_by_ref":null,"by":"operator:decisions-command"}`. `validate-artifact.sh --type decisions` accepts that ledger. The test at `head/tests/unit/dec-write-lib.bats:354` ("the PRD Status line alone does not block it") exercises exactly this path but asserts only `status`, never `decided_by`, so the regression is invisible to the suite.
**Why This Matters:** `.claude/commands/decisions.md:55` promises "That operator-kind reference is what records `decided_by: operator`". A PRD for an autonomous cycle carries that Status line for the whole cycle, so every operator confirmation in that cycle is attributed to the agent. The rows then stay in every "decisions taken on the operator's behalf" rendering (`list --not-decided-by operator` in the PRD/SDD appendices, `list --voice agent,flatline,dissent` in `render-templates.md:106`) even after the operator confirmed them, and the ledger is append-only, so the misattribution can only be corrected by superseding the row.
**Required Fix:** In `op_confirm`, derive the operator ref independently of the PRD signal: either make `derive_attribution` ignore only `live` signals when the caller is `is_operator_call` (mirroring line 509), or refuse `confirm` under any unattended signal so the two checks agree. Extend the test at `dec-write-lib.bats:354` to assert `decided_by == operator` and `decided_by_ref == cli:…` for the PRD-status case.

### 2. Authorization: `import` lands hand-written `decided`/`operator` rows in the live ledger with no operator action

- **HIGH** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:618-658` — `op_import` validates the pending file for shape only, then appends every row verbatim (lines 640-646) with no check on `status`, `decided_by`, `decided_by_ref`, `rejection_rationale` or `transitions[].to`, no `is_operator_call` requirement and no `live_run_signal` refusal.
**File:** `head/.claude/scripts/lib/dec-write-lib.sh:640-646`
**Issue:** Reproduced: a pending file whose single `PEND-` row carries `status: decided`, `decided_by: operator`, `decided_by_ref: cli:…` and a `proposed -> decided by operator:decisions-command` transition passes the pending-mode validator and `import --from … ` exits 0; the live ledger then holds `{"id":"DEC-0001","status":"decided","decided_by":"operator"}`. `import` is model-invocable (it is not in `user-invoked-commands.txt`) and the pending file is authored in a worktree by an agent, so this is a second self-confirmation path that survives even if the `--recorded-by` string guard (Observation 3) were hardened.
**Why This Matters:** The header at lines 10-17 and `decisions.md:21-26` state a row becomes `decided` only through `/decisions confirm`. With this path an agent forges operator attribution in one step, and `list --not-decided-by operator` hides the forged rows from the appendix the operator reads. The dissent (DISS-C-001) also notes the imported summaries are echoed raw to stderr by `confirm`.
**Required Fix:** Before `append_row` in `op_import`, assert for every imported row: `status` in `{open, proposed}`, `decided_by == null`, `decided_by_ref` null or non-operator-kind, `supersedes == null`, `supersede_proposed_by == null`, `rejection_rationale == null`, and every `transitions[].to` in `{open, proposed}`; die otherwise. Re-sanitize string fields through the `san1` equivalent and re-derive `recorded_by`'s session suffix and `commit`. Mirror the same constraints in `validate_decisions` for pending files (`$pending == true`) so the validator is fail-closed on its own. Add a negative test with a forged `decided` row.
**Reference:** CWE-284 (Improper Access Control), CWE-345 (Insufficient Verification of Data Authenticity).

### 3. The tracked ledger the feature depends on is not in the change

- **HIGH** (confidence: medium) `head/.claude/scripts/lib/dec-write-lib.sh:271` — every live-ledger write dies with `ledger not found: … (restore the tracked grimoires/loa/decisions.yaml)` unless the file exists, and the diff never adds it.
**File:** `head/.claude/scripts/lib/dec-write-lib.sh:271`, `head/.gitignore:150`, `head/tests/unit/dec-write-lib.bats:28`, `head/tests/unit/validate-artifact.bats:644`, `head/tests/unit/grimoire-index.bats:80`
**Issue:** `pr/base/.gitignore:149` ignores `grimoires/loa/decisions.yaml`, so the file was not tracked before this PR (git would have refused `add` without `-f`). The PR adds the `!grimoires/loa/decisions.yaml` negation and the `tracked_set` entry (`head/.claude/scripts/validate-gitignore-state.sh:58`) but no `grimoires/loa/decisions.yaml` appears in `head.diff`. Three suites read `$REPO/grimoires/loa/decisions.yaml` in setup (`sed` on a missing file yields a header-less fixture, and `dec-write-lib.bats:109` then fails on the missing head comment; `validate-artifact.bats:642` fails outright). To run the suites here I had to seed the file by hand. `karpathy-principles.md:35` and `autonomous-agent/SKILL.md:66` now instruct every unattended run to call `dec-write-lib.sh new`, which fails on a fresh clone.
**Why This Matters:** On a fresh checkout the writer refuses, the validator's "live ledger passes" test fails, and the unattended-run guidance cannot be followed. If the file already exists tracked upstream (force-added), this finding falls away; it cannot be verified from the PR files alone, hence confidence medium.
**Required Fix:** Commit the seeded ledger in this PR (`# grimoires/loa/decisions.yaml: the decision ledger …` header, `schema_version: 1`, `decisions: []`), or make `resolve_target write` bootstrap it in the main checkout the way it bootstraps the pending file (lines 262-270). Run the three suites on a fresh clone.

### 4. Data loss: `import` deletes pending rows appended while it runs

- **HIGH** (confidence: medium) `head/.claude/scripts/lib/dec-write-lib.sh:627-658` — `op_import` takes the lock for the live ledger only (line 627), reads the pending file once (line 628), and deletes the whole file at line 658. A worktree writer appending to the same pending file holds a different lock: `lock_path` (lines 219-223) keys the lock under *its own* `PROJECT_ROOT/.run`, which in a linked worktree is the worktree's `.run`, so the two processes never exclude each other.
**File:** `head/.claude/scripts/lib/dec-write-lib.sh:627-658`
**Issue:** A `new` in the worktree that lands between the import's `read_ledger "$from"` and its `rm -f -- "$from"` is deleted without being imported. The ledger's stated contract (header lines 5-9: "no id dropped") is violated for the pending file, and `verify_and_swap` cannot see it because it only compares the live ledger.
**Why This Matters:** The worktree flow is the documented way parallel sprint workers record decisions; the lead imports while workers may still be running. A lost row is a lost decision with no trace.
**Required Fix:** Lock the pending file for the import's whole duration with a lock both sides can see (for example a lock file beside the pending file, not under a per-checkout `.run`), and have worktree writers take the same lock. Alternatively, after `verify_and_swap`, re-read the pending file and refuse to delete it if its row count changed, leaving the new rows for a second import. Add a test that appends during an import.

---

## Observations

### 1. Lineage dead-end after rejecting a proposed replacement

- **MEDIUM** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:582-589` — `op_reject` on a `proposed` replacement row leaves the original decided row's `supersede_proposed_by` pointing at the now-rejected row. Reproduced: after `supersede` (agent) then `reject` of the new row, a second agent `supersede --id DEC-0001` dies with "a replacement is already proposed for DEC-0001: DEC-0002" (check at line 598). Only the operator path (which skips the check) can ever supersede that row again. Note the validator's append-only rule at `head/.claude/scripts/validate-artifact.sh:688-699` only permits `supersede_proposed_by` to go null→value, so the fix must also allow clearing it when the named row is `rejected`. (From dissent DISS-002.)
**Suggestion:** In `op_reject`, when the rejected row has `supersedes`, clear the old row's `supersede_proposed_by` in the same write and include both ids in `touched`; relax the validator for that case; or make the line-598 check ignore a pointer to a `rejected` row.
**Benefit:** Keeps decided rows revisable through the agent path after one rejected proposal.

### 2. `--file` bypasses the CI/hook refusal

- **MEDIUM** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:250-253` — `resolve_target` returns before the `ci_blocked` check at line 261 whenever `--file` is given. Reproduced: `CI=1 dec-write-lib.sh new --file grimoires/loa/decisions.yaml …` exits 0 and appends to the live ledger. The header (line 23) describes the exemption as for fixtures.
**Suggestion:** Resolve `--file` to an absolute path and apply `ci_blocked` when it equals `$LIVE` (or lies under `grimoires/loa/`).
**Benefit:** The "never written from CI or a hook" guarantee holds for the live path regardless of how it is named.

### 3. Operator identity is a self-asserted CLI string

- **MEDIUM** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:359` — `is_operator_call` is `--recorded-by decisions-command`. Any agent with Bash can run `confirm`, `reject` on a decided row, or `context --clear` outside a live run. The guards are lint (`dec-write-lib.bats:530-543`, `user-invoked-commands.bats`) over prose in skills and commands, which an agent does not need to consult. The PR acknowledges the trust model ("an agent that could run them would confirm its own decisions", `decisions.md:24`), but the header does not state that the guard is advisory.
**Suggestion:** State the limitation explicitly in the header and in `decisions.md`; consider an interactive-only check such as `[[ -t 0 ]]` for the operator operations, and have the validator flag `operator:decisions-command` transitions whose `recorded_by` session id does not match the row's confirming session.
**Benefit:** Readers of the ledger know what `decided_by: operator` does and does not prove.

### 4. Operator supersede retires the old row before the replacement is decided

- **MEDIUM** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:606-612` — in the operator path the old `decided` row becomes `superseded` in the same write that lands the replacement as `proposed` (documented at `decisions.md:103`). If the operator never confirms, or later rejects, the replacement, the topic has no decided row and the chain points at a rejected one. The agent path (line 609) correctly defers via `supersede_proposed_by`. (From dissent DISS-C-003.)
**Suggestion:** Use the deferred path for operators too, or confirm the replacement atomically in the same write when the operator supplies a `cli:` ref.
**Benefit:** One lineage shape for both paths; no window with no active decision.

### 5. `confirm` keeps a pre-seeded ref and derives `decided_by` from it

- **MEDIUM** (confidence: medium) `head/.claude/scripts/lib/dec-write-lib.sh:537-538` — `decided_by_ref` is set only when currently null, and `decided_by` is derived from whatever ref is present. A row created interactively by an agent with `--answer-ref session:X#turn-N` (accepted at `dec-write-lib.bats:220`) ends `decided_by: operator` after a confirm that never recorded the operator's own ref; a flatline row ends `decided_by: flatline` after the operator confirms it. `decisions.md:55` describes the operator's ref as what records `decided_by: operator`. This may be intended (an agent recording the operator's in-session answer), but the command doc and the code disagree. (From dissent DISS-C-002.)
**Suggestion:** Either always record the operator's confirm ref (keep the creation ref in a separate field) or document the actual rule in `decisions.md` and the header.
**Benefit:** Attribution rule is explicit and matches the writer.

### 6. No CHANGELOG entry; default pacing changes for existing users

- **MEDIUM** (confidence: medium) `head/.loa.config.yaml.example:140` — the default `interview.pacing` moves from `sequential` to `rounds` (and the mode-derived default in `discovering-requirements/SKILL.md:60` does the same for configs without the key), a behaviour change for every existing `thorough` user. The diff contains no CHANGELOG entry for that change, for the new `/decisions` command, the new writer, the new hook, or the new `decisions:` config keys (0 matches for `CHANGELOG` in `head.diff`). Documentation Verification treats a missing CHANGELOG entry per task as blocking on approval; it is recorded here because the verdict is already CHANGES_REQUIRED.
**Suggestion:** Add CHANGELOG entries and call out the pacing default change as user-visible.
**Benefit:** Operators learn why their interview changed shape.

### 7. Enabled surface exits silently when yq or jq is missing

- **LOW** (confidence: high) `head/.claude/hooks/session-start/loa-decisions-surface.sh:37-39` — the three `|| exit 0` lines run before the config is read, so an operator who sets `decisions.surface_at_session_start: true` on a machine without Mike Farah yq v4 sees nothing, while the unreadable-ledger path at lines 58-66 prints a WARNING. The header contract says "prints nothing", so this is a contract choice rather than a bug.
**Suggestion:** Read the enabled flag first (it needs only `yq` or a grep fallback) and print one `[DECISIONS] WARNING: … yq v4 missing` line when enabled.
**Benefit:** Mirrors the degraded-path behaviour the hook already has for the ledger.

### 8. Tag-to-row rule matches the PRD by substring

- **LOW** (confidence: medium) `head/.claude/scripts/validate-artifact.sh:787` — `index($2, n) > 0` with `n` = `basename "$FILE"`, so any `source` containing `prd.md` (for example `sprint-prd.md#…` or a path to another cycle's `prd.md`) satisfies "a DEC row whose source names the PRD".
**Suggestion:** Match the source against the PRD's repo-relative path, or anchor on a path separator/start.
**Benefit:** The rule cannot be satisfied by an unrelated row.

### 9. Decisions `source` is split into `refs` on commas in the machine index

- **LOW** (confidence: high) `head/.claude/scripts/grimoire-index.sh:184-186` and `:203` — `emit_decisions` writes `source` into the sixth TSV column, which `to_json` splits on `,` into `refs`. Reproduced: `--source "prd.md#e (D1), sdd.md#3"` yields `"refs":["prd.md#e (D1)"," sdd.md#3"]` in `.run/grimoire-index.json`. `render_md` re-joins, so `INDEX.md` looks right. (From dissent DISS-C-004.)
**Suggestion:** Emit a dedicated `source` key for the decisions family, or skip the comma split when `family == "decisions"`.
**Benefit:** Machine consumers see one source string.

### 10. Complexity

- **LOW** (confidence: high) `head/.claude/scripts/validate-artifact.sh:527-728` — `validate_decisions` is about 200 lines, mostly one jq program; `op_confirm` (`dec-write-lib.sh:506-558`) and `op_import` (`:618-658`) are each over 50 lines. The single-evaluation design is justified in the header comment (one pass, `--slurpfile` for large ledgers), so this is not blocking. SIMPLICITY[shrink]: move the jq program to `resources/` or a heredoc variable with named sections. Elsewhere the change is lean: `Lean already. Ship.`

### 11. Implementation report has no AC Verification walkthrough

- **LOW** (confidence: high) `grimoires/loa/a2a/sprint-1/reviewer.md:1-5` — the report is the PR title and a file count; there is no `## AC Verification` section and no stated assumptions. In this review the PR description stands in for the report by definition of the sprint, so it is recorded rather than counted as a separate blocking item.

---

## Rejected dissent payloads

- None. `adversarial-review.json` `metadata.rejected_summary` is `[]`, and the sidecar `grimoires/loa/a2a/sprint-1/adversarial-rejected-review.jsonl` is empty (0 bytes).

## Cross-Model Observations

Adversarial review ran with two voices (primary `gpt-5.5-pro`, companion `claude-headless`, status `reviewed`, companion `succeeded`) on `pr/head.diff` with my Phase 2 concerns as context. Six findings came back; every one was checked against the head code and, where it stated a failure, reproduced by running the head scripts before adoption:

| Dissent id | Voice | Disposition |
|---|---|---|
| DISS-001 import deletes rows appended concurrently | gpt-5.5-pro | Adopted as Changes Required 4; confirmed the per-checkout lock path makes cross-checkout exclusion impossible |
| DISS-002 reject leaves `supersede_proposed_by` dangling | gpt-5.5-pro | Reproduced; Observation 1 (recoverable through the operator path, so medium) |
| DISS-C-001 import accepts forged `decided`/`operator` rows | claude-headless | Reproduced; Changes Required 2. Its sub-claim that an imported `supersedes:` row lands silently does not hold: the validator's `supersedes … does not name this row` check rejects the candidate |
| DISS-C-002 confirm keeps a pre-seeded ref | claude-headless | Observation 5 (may be intended; doc/code disagree) |
| DISS-C-003 operator supersede retires old row early | claude-headless | Observation 4 |
| DISS-C-004 `source` split into `refs` | claude-headless | Reproduced; Observation 9 |

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | Four high findings above; the tracked ledger file the feature and its tests require |

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

Sprint success criterion (sprint.md): "review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict".

| Criterion | Status | Notes |
|-----------|--------|-------|
| Ledger rows are written only through the writer, verified and validated before swap | Pass | `verify_and_swap` (`dec-write-lib.sh:382-410`) re-reads, diffs and validates; failed write leaves file byte-identical (bats test 3) |
| A row becomes `decided` only through `/decisions confirm` | Fail | `import` lands `decided`/`operator` rows verbatim (Changes Required 2); operator confirm under PRD-status signal records `decided_by: agent` (Changes Required 1) |
| Rows and ids are never dropped | Fail | `import` deletes pending rows appended during the run (Changes Required 4) |
| Live-ledger writes refused from CI/hooks | Partial | `--file` names the live path and bypasses the check (Observation 2) |
| Operator-only commands carry `disable-model-invocation` and are listed | Pass | `user-invoked-commands.bats` 12/12; `decisions.md` flagged and listed |
| SessionStart surface default-off, fenced, hostile text neutralised | Pass | `loa-decisions-surface.bats` 8/8 including the negative corpus |
| `rounds` pacing documented with a working checker | Pass | `check-round-independence.bats` 13/13; the REFERENCE.md worked example validates |
| Feature usable on a fresh clone | Fail | ledger file absent from the change (Changes Required 3) |

---

## Test Results (executed against head files)

Suites were run in a scratch checkout built from `pr/head/` plus the framework tree, after seeding `grimoires/loa/decisions.yaml` by hand because the PR does not ship it. `/tmp` is mounted `noexec` in this sandbox, so the run was repeated on an exec-capable path.

| Suite | Result |
|---|---|
| `tests/unit/dec-write-lib.bats` | 44/44 pass |
| `tests/unit/validate-artifact.bats` | 51/51 pass |
| `tests/unit/check-round-independence.bats` | 13/13 pass |
| `tests/unit/loa-decisions-surface.bats` | 8/8 pass |
| `tests/unit/user-invoked-commands.bats` | 12/12 pass |
| `tests/unit/user-invoked-harness.bats` | 4/4 offline classifier pass; live `claude -p` probe skipped (`LOA_HARNESS_CHECK=0`, not run here) |
| `tests/unit/grimoire-index.bats` | 5/5 new decisions tests pass; one pre-existing KF test fails only because the sandbox lacks the repo's `known-failures.md` |
| `tests/unit/agents-md-gen.bats` | count test reports 51, not 50, because this sandbox carries an extra `eval` command; environment, not the PR |

**FAST-GATE:** no formatter or type checker applies to bash; `shellcheck` is not installed in this sandbox, so the shellcheck gate was not verified here. The report does not state that it ran.

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [x] Input validation and sanitization present (`san1`, jq `--arg`, yq `env()`, ref grammar, artifact path containment, L6 fence)
- [ ] Authentication/authorization correct — `import` forges operator attribution (Changes Required 2); operator identity is a CLI string (Observation 3)
- [x] No SQL/XSS injection vulnerabilities (no expression built from user text; pipes and angle brackets escaped in renderers)
- [x] Dependencies secure (jq, Mike Farah yq v4, flock; versions pinned by check)
- [x] Error messages don't leak sensitive data

---

## Code Quality Summary

**Strengths:**
- Single-writer design with snapshot verification and atomic rename; failure paths leave the file byte-identical.
- No shell or yq expression is ever built from caller text (`env()`/`strenv()`, `jq --arg`); hostile-string corpus proves it.
- Untrusted ledger text is reduced to id/status/summary, control-stripped, capped, and fenced before it reaches a session.
- Tests are hermetic (own temp project, own git repo), cover lock contention with and without `flock`, worktree import, CI refusal, and a harness probe with an offline classifier.
- The `validate-gitignore-state.sh` negation fix is correct and small.

**Areas for Improvement:**
- The `confirm` and `import` paths each have one way to record operator attribution that the operator did not produce; both need a mechanical check, not prose.
- Cross-checkout locking is keyed per checkout, so worktree and main writers never exclude each other.
- A 200-line jq program inside a bash function is hard to review and test piecewise.

---

## Next Steps

1. Fix Changes Required 1-4 (confirm attribution, import row constraints, ship or bootstrap the ledger, lock the pending file during import); add the named regression tests.
2. Decide on Observations 1-5 (lineage after reject, `--file` CI bypass, operator identity, operator supersede, pre-seeded refs) and record the decisions.
3. Add CHANGELOG entries, including the pacing default change.
4. Update `grimoires/loa/a2a/sprint-1/reviewer.md` with an AC Verification walkthrough and request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":4,"medium":6,"low":5},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T12:05:00Z"} -->
