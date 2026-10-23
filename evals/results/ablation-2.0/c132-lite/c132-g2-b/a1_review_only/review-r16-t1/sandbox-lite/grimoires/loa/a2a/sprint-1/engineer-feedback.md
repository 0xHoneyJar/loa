# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Change under review:** `pr/head.diff` (39 files; sprint-252 decision surfaces, part 1). Citations are `head/<path>:<line>` with line numbers from `pr/head/`.

---

## Overall Assessment

The change is substantial and mostly careful: the ledger writer (`dec-write-lib.sh`) keeps values out of yq expressions via `env()`, copies-verifies-renames every write, derives attribution instead of accepting it, and the session-start surface sanitises agent-authored rows inside the L6 fence. The 44-test writer suite, the validator suite and the round-independence checker are hermetic and pass when run against the PR head on a scratch repository that carries a seeded ledger.

Three defects block merge. First, the writer's attribution path treats the static PRD `**Status:**` signal like a live unattended run, so an interactive operator confirm on any project whose PRD mentions an autonomous run is recorded as `decided_by: agent` (reproduced; the validator accepts the result). Second, the change declares `grimoires/loa/decisions.yaml` tracked, re-includes it in `.gitignore`, and seeds every ledger test from the repository copy, but never adds that file; on a checkout without it the whole writer suite fails at setup and the live writer dies. Third, `import` deletes a linked worktree's pending file without locking it, so a row appended during the import is lost silently.

The cross-model dissent ran with two voices (gpt-5.5-pro primary, claude-headless companion) and independently raised the attribution defect, the import race and the stuck-supersede state; its findings are folded in below with their `DISS-` ids.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Attribution: operator confirm recorded as an agent decision under a PRD "autonomous" Status line

- **HIGH** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:313` — `derive_attribution` discards the operator's `--answer-ref` whenever `is_unattended` is true, and `is_unattended` includes the non-live `prd prd-status:` signal (lines 177-180). `op_confirm` deliberately gates only on `live_run_signal` (line 509), so the confirm proceeds and the jq at lines 536-538 sets `decided_by = .proposed_by`.
**File:** `head/.claude/scripts/lib/dec-write-lib.sh:313` (also `:177-180`, `:509`, `:536-538`, `:572`, `:575`, `:600-611`)
**Issue:** Reproduced against the PR writer with a one-row ledger and a PRD containing `**Status:** Draft, autonomous run`, confirming exactly as `decisions.md` rule 3 instructs (`--evidence cli:<now> --answer-ref cli:<now>`):

```
dec-write: WARN: unattended context: --answer-ref ignored (the row stays proposed with proposed_by agent until /decisions confirm)
confirming DEC-0001: row1
dec-write: confirmed DEC-0001
exit=0
{"status":"decided","decided_by":"agent","decided_by_ref":null,"by":"operator:decisions-command"}
validator exit=0
```

The WARN text is also wrong for this path (the row does not stay proposed; it is confirmed). The same `is_unattended` branch makes `op_reject` record `by: agent:decisions-command` for an operator rejection (line 572, reproduced), refuses the operator rejecting a decided row at all (line 575), and sends an operator `supersede` down the agent path (lines 600-611: sets `supersede_proposed_by` instead of superseding). `validate-artifact.sh` cannot catch any of this because the writer hard-codes `transitions[].by = operator:decisions-command` (line 536), which is all the validator's `-> decided` rule checks (`head/.claude/scripts/validate-artifact.sh:632`). The existing test `head/tests/unit/dec-write-lib.bats:354-366` exercises precisely this scenario but asserts only `status`, not `decided_by`.
**Why This Matters:** `decisions.md:55` promises "That operator-kind reference is what records `decided_by: operator`". The PRD signal is a static property of the project, so once a PRD mentions autonomy every operator confirmation for the rest of the cycle is misattributed, and `list --not-decided-by operator` (the PRD/SDD appendix and the PR body section) keeps reporting operator-approved rows as agent decisions. This is the one property the ledger exists to make answerable. Matches dissent DISS-C-001 (BLOCKING).
**Required Fix:** In `derive_attribution`, drop `--answer-ref`/`--as` only under `live_run_signal` (or only when the caller is not `is_operator_call`); use `live_run_signal` rather than `is_unattended` in the operator branches of `op_reject` (lines 572, 575) and `op_supersede` (lines 600, 606). Keep `is_unattended` (live + PRD) solely for choosing the landing status in `op_new` (line 467). Extend the bats case at `:354-366` to assert `decided_by == operator` and `decided_by_ref == cli:...` after the PRD-signal confirm, and add the reject/supersede counterparts.

### 2. The tracked ledger the change depends on is not in the change

- **HIGH** (confidence: medium) `head/tests/unit/dec-write-lib.bats:28` — every ledger suite seeds its fixture from `$REPO/grimoires/loa/decisions.yaml`, `.gitignore` re-includes that path, `validate-gitignore-state.sh` declares it tracked, and the writer tells users to "restore the tracked" copy, yet the 39-file diff never adds the file.
**File:** `head/tests/unit/dec-write-lib.bats:28` (also `head/tests/unit/validate-artifact.bats:630`, `:644`; `head/tests/unit/grimoire-index.bats:80`; `head/.gitignore:150`; `head/.claude/scripts/validate-gitignore-state.sh:58`; `head/.claude/scripts/lib/dec-write-lib.sh:271`)
**Issue:** The base `.gitignore` ignored `grimoires/loa/decisions.yaml` (`pr/base/.gitignore:149`), so unless the base tree already carries a force-added copy, a fresh clone has no ledger. I ran the suites on the PR head without the file: `dec-write-lib.bats` fails 44/44 in `setup` (`sed: can't read .../grimoires/loa/decisions.yaml`), the four `grimoire-index decisions:` tests and `validate-artifact decisions: the live ledger passes` fail, and `dec-write-lib.sh new` on the live path dies with "ledger not found ... (restore the tracked grimoires/loa/decisions.yaml)". With a seeded header-only ledger everything passes (44/44, 51/51, 13/13, 8/8, 12/12). The test at `dec-write-lib.bats:109-113` additionally requires the seeded file's first line to be the comment `# grimoires/loa/decisions.yaml: the decision ledger ...`, which nothing in the change provides.
**Why This Matters:** The feature is unusable on a fresh checkout and the suite that proves it is red in CI; the `.gitignore` negation (`head/.gitignore:150`) is a no-op without the file it re-includes.
**Required Fix:** Add the seeded `grimoires/loa/decisions.yaml` (header comment, `schema_version: 1`, `decisions: []`) to the change and confirm it is tracked (`git ls-files grimoires/loa/decisions.yaml`). If the base tree already tracks it, say so in the report and drop the "restore" guidance; the confidence on this finding is medium only because the base tree outside the touched files is not visible here.

### 3. `import` deletes an unlocked pending file: rows appended during the import are lost

- **HIGH** (confidence: medium) `head/.claude/scripts/lib/dec-write-lib.sh:655` — `op_import` snapshots the pending file (`read_ledger "$from"`, line 629), appends that snapshot to the live ledger, then runs `rm -f -- "$from"` without ever holding a lock on the pending file.
**File:** `head/.claude/scripts/lib/dec-write-lib.sh:655` (also `:629`, `:207`)
**Issue:** The only lock taken is on the live ledger (line 628). Locks are keyed under *this checkout's* `.run` (`lock_path`, line 207), so even the worktree writer's own lock on the pending file lives in a different directory and is never contended by the importing main checkout. A linked-worktree agent that appends a PEND row between line 629 and line 655 (the design explicitly supports parallel sprint tasks in worktrees) has that row deleted with the file; the import output lists only the rows read earlier and nothing reports the loss.
**Why This Matters:** Silent loss of a decision row defeats the append-only guarantee the rest of the writer enforces so carefully. Matches dissent DISS-002 (BLOCKING) and DISS-C-003.
**Required Fix:** After `verify_and_swap`, re-read `$from` and refuse to delete it when its ids differ from the imported set (print the leftover ids and leave the file), or lock the pending file under a lock path derived from the pending file's own directory so both checkouts contend on the same lock. Add a bats case that appends to the pending file between read and delete (e.g. via a `yq -i` hook or a second writer) and asserts the row survives.

---

## Observations

### 1. Ledger state machine

- **MEDIUM** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:601` — after the operator rejects a proposed replacement, the superseded-candidate row keeps `supersede_proposed_by` pointing at the rejected row, so every later agent `supersede` of that decision dies with "a replacement is already proposed" (reproduced: `supersede` -> `reject` -> second `supersede` exits 1). The append-only rules forbid clearing the pointer, so only an operator `supersede` can move the row. Dissent DISS-001 rated this BLOCKING; I rate it medium because the operator path still works, but the guard should consider only replacements that are still `proposed`, or `op_reject` should clear the pointer on the superseded-candidate row in the same write.
**Suggestion:** Guard on `$byid[.supersede_proposed_by].status == "proposed"` (and relax the validator's content-edit rule at `validate-artifact.sh:681` accordingly if the pointer is cleared).
**Benefit:** Agents can re-propose after an operator rejection without manual intervention.

- **MEDIUM** (confidence: medium) `head/.claude/scripts/lib/dec-write-lib.sh:509` — a marker written by `context --set-unattended` in the current session stays `fresh` for `unattended_marker_ttl_hours` (24 h) as long as the session id matches, so after an autonomous run finishes the operator in the same session is refused `confirm` for the rest of the day. The refusal text ("confirm after the run, interactively") gives no repair step, and `decisions.md:109` documents `clear-unattended` only for markers the surface reports stale. Dissent DISS-C-005.
**Suggestion:** Have the run-mode completion/halt path clear or expire the marker, and name `/decisions clear-unattended` in the refusal message.
**Benefit:** The operator is never locked out of the confirm path by a finished run.

### 2. Trust boundary

- **MEDIUM** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:359` — `is_operator_call` is a string compare on `--recorded-by`. Any Bash-capable agent can run `dec-write-lib.sh confirm ... --recorded-by decisions-command --answer-ref cli:...` and self-confirm its rows as the operator. `head/.claude/commands/decisions.md:26` says `disable-model-invocation: true` "keeps the model from starting it" and the description says "the model cannot invoke it", which overstates the boundary: the flag hides the slash command from the Skill tool, and the bats greps in `user-invoked-commands.bats` catch committed text, not ad-hoc tool calls. Dissent DISS-C-004. CWE-284 (improper access control), accepted-design territory but the doc should state the real boundary.
**Suggestion:** Either document that the operator-only property is enforced by convention plus static lint, or add a check an agent cannot forge from Bash (e.g. `[[ -t 0 ]]` for `confirm`, `reject`/`supersede` on a decided row and `context --clear`).
**Benefit:** Readers of `decisions.md` and the ledger know what `decided_by: operator` actually proves.

### 3. Tests

- **MEDIUM** (confidence: high) `head/tests/unit/user-invoked-harness.bats:151` — a unit-test suite runs a live, billable `claude -p` call (up to 180 s, `--max-turns 3`) by default whenever `claude` is on PATH; the opt-out is `LOA_HARNESS_CHECK=0` (line 135). A non-hermetic network call in `tests/unit/` will surprise contributors and CI runners that have the CLI installed.
**Suggestion:** Make the live run opt-in (`LOA_HARNESS_CHECK=1`) or move it under an `integration`/`live` tag; keep the offline classifier tests where they are.
**Benefit:** `bats tests/unit` stays fast, deterministic and free.

- **MEDIUM** (confidence: medium) `grimoires/loa/a2a/sprint-1/reviewer.md:1` — the implementation report is the two-line PR description: no `## AC Verification` walkthrough, no stated assumptions, no record of which suites were run or of the seeded-ledger prerequisite (Think Before Coding). Under the skill's rules a missing AC Verification section is itself an automatic CHANGES_REQUIRED; it is recorded here as an observation because the verdict is already determined by the findings above.
**Suggestion:** Add an AC Verification section with `file:line` evidence per acceptance criterion and the exact test commands run.
**Benefit:** The next review can verify claims instead of re-deriving them.

### 4. Complexity (SIMPLICITY review)

- **MEDIUM** (confidence: high) `head/.claude/scripts/validate-artifact.sh:527` — `validate_decisions` is about 200 lines (527-728) wrapped around a single ~120-line jq program (568-689); `op_confirm` (`head/.claude/scripts/lib/dec-write-lib.sh:506-558`) is 53 lines. Both exceed the 50-line guideline with no justification comment. Nesting stays under three levels and I found no duplicated blocks or circular sourcing; this is restructuring work, not deletion. net: -0 lines possible.
**Suggestion:** Split the jq program into named `def`s per rule family (schema, transitions, cross-row, append-only) and extract the supersede branch of `op_confirm` into a helper.
**Benefit:** Each rule becomes readable and testable on its own.

### 5. Lower-impact items

- **LOW** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:262` — the pending-file skeleton is written with `cat >` before `acquire_lock` (line 468); two worktree writers racing on a new pending file can have the slower skeleton truncate the faster writer's appended row. Dissent DISS-C-002. Create the skeleton under the lock and re-check `-f`.
- **LOW** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:694` — `list --format md` prints `_None: every decision in this run was the operator's._` for every empty result, including `--id` of an unknown row or `--status decided --voice agent` (reproduced). The sentence is only true for the PR-body query; print a neutral "no matching rows" and let `render-templates.md` step 4 add the operator sentence.
- **LOW** (confidence: high) `head/.claude/scripts/grimoire-index.sh:217` — the INDEX.md intro still enumerates "(KF · vision · lore · handoff · observation)": the decisions family added in this change is missing and the observation family was removed in cycle-121.
- **LOW** (confidence: medium) `head/.claude/scripts/validate-artifact.sh:734` — `BARE_ASSUMPTION_FAILS_FROM="2026-11-13"` is a hard-coded date switch that turns bare `[ASSUMPTION]` tags from WARN to FAIL for PRDs dated on or after it, with no knob in `.loa.config.yaml.example` and no mention outside the script comment.
- **LOW** (confidence: low) `head/README.md:125` — the command total is bumped to 50 and points to PROCESS.md "for all commands", but PROCESS.md is not in the change, so the new `/decisions` command is probably absent from the full list (not verifiable from the touched files).

---

## Rejected dissent payloads

None. `grimoires/loa/a2a/sprint-1/adversarial-review.json` has `metadata.rejected_summary: []` and the sidecar `adversarial-rejected-review.jsonl` is empty (0 bytes). Two voices completed: primary `gpt-5.5-pro` (answered by `codex-headless` on the chain), companion `claude-headless` (`counted_as: independent_voice`). Seven findings: DISS-001, DISS-002, DISS-C-001 (BLOCKING) are covered by Changes Required 3, 3 and 1 and Observation 1; DISS-C-002, DISS-C-003, DISS-C-004, DISS-C-005 (ADVISORY) are folded into Observations 1, 2 and 5. Advisory findings were read as input, not counted.

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| "review the pull request" (sprint.md Success Criteria) | Pass | Every touched head file and test read; eight bats suites executed against the head in a scratch repository |
| "report each defect it introduces with the file and line it sits on" | Pass | 3 HIGH, 6 MEDIUM, 5 LOW above, each with `head/<path>:<line>` |
| "give a merge verdict" | Pass | CHANGES_REQUIRED (trailer below) |

### Test execution (PR head overlaid on the framework tree, exec-capable filesystem, seeded header-only ledger, `LOA_HARNESS_CHECK=0`)

| Suite | Result |
|-------|--------|
| tests/unit/dec-write-lib.bats | 44/44 pass (0/44 without the seeded ledger) |
| tests/unit/validate-artifact.bats | 51/51 pass |
| tests/unit/check-round-independence.bats | 13/13 pass |
| tests/unit/loa-decisions-surface.bats | 8/8 pass |
| tests/unit/user-invoked-commands.bats | 12/12 pass |
| tests/unit/user-invoked-harness.bats | 5/5 (live test skipped by the opt-out) |
| tests/unit/grimoire-index.bats | 11/12 (the KF-009 test needs the repository's known-failures.md, absent in the scratch tree) |
| tests/unit/agents-md-gen.bats | 6/8 (the count tests depend on the real `.claude/commands` set, which the scratch tree does not reproduce) |

Fast-gate parity could not be checked: the report names no formatter or lint run. `shellcheck` is not installed here.

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [x] Input validation and sanitization present (`san1`, yq `env()`, L6 fence with control-stripping in the hook, path-traversal guard on artifact refs)
- [ ] Authentication/authorization correct — operator-only operations are gated by a caller-supplied string (Observation 2) and misattributed under the PRD signal (Changes Required 1)
- [x] No SQL/XSS injection vulnerabilities (yq receives rows only through `env()`; jq receives values only through `--arg`)
- [x] Dependencies secure (jq, Mike Farah yq v4; fail-closed preflight)
- [x] Error messages don't leak sensitive data

---

## Code Quality Summary

**Strengths:**
- Copy, verify (JSON-equality of untouched rows, id set, row count, validator), then atomic rename; a failing candidate leaves the ledger byte-identical and the test proves it.
- Values never reach yq expressions; rows are built by `jq --arg`; the hostile-string corpus test round-trips control bytes, C1, U+2028/9 and YAML-special strings.
- The session-start surface is default-off, exits 0 on every path, reads only id/status/summary, and wraps output in the L6 fence; its negative test covers a closing-tag injection.
- `check-round-independence.sh` is small, has a JSON mode and a complete fixture pair; the REFERENCE.md worked example is itself tested.

**Areas for Improvement:**
- The `is_unattended` predicate conflates a static PRD property with live run signals; the operator branches need the live-only predicate.
- Cross-checkout coordination (pending file, import) relies on locks that are never shared between checkouts.
- The validator trusts `transitions[].by`, which the writer sets unconditionally; attribution rules should be checked against `decided_by_ref` as well.

---

## Next Steps

1. Fix Changes Required 1-3 (attribution predicate, seeded tracked ledger, import coordination) and add the regression tests named in each.
2. Decide on Observations 1-2 (stuck supersede, unattended-marker lockout, trust-boundary wording) and record the decision.
3. Re-run the eight suites from a fresh clone and record the commands and results in `grimoires/loa/a2a/sprint-1/reviewer.md` with an AC Verification section.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":6,"low":5},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T15:28:00Z"} -->
