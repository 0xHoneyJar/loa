# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md
**Change under review:** `pr/head.diff` — feat(cycle-128): sprint-252 decision surfaces, part 1 (interview rounds, fact/decision attribution, the decision ledger, operator-only commands); 39 files.

---

## Overall Assessment

The ledger writer (`dec-write-lib.sh`), its validator (`validate-artifact.sh --type decisions`), the session-start surface, the round checker and the operator-only allowlist are carefully built: values reach yq only through `env()`, every write is verified against the pre-write copy and re-validated before an atomic rename, hostile strings are sanitised at the trust boundary, and the surface hook wraps agent-authored rows in the L6 fence. The test corpus is unusually thorough (hostile-string round-trips, lock contention, worktree pending files, negative validator fixtures). Verified by running every new suite against a scratch copy of the head tree with framework libraries from this checkout: 44/44 writer tests, 23/23 validator tests, 13/13 round-checker tests, 5/5 index tests, 8/8 hook tests, 12/12 allowlist tests, 4/4 offline harness tests pass **once a ledger file exists**.

Three defects block the merge:

1. The tracked ledger `grimoires/loa/decisions.yaml` that the writer, the hook, the index and three test suites depend on is not in the change, and the writer refuses to create it. As shipped, every live write exits 1 and the writer and validator suites error in `setup`.
2. An operator `confirm` records `decided_by: agent` whenever the PRD's `**Status:**` line mentions "autonomous" or "unattended", because `derive_attribution` discards the operator's `cli:` reference on any unattended signal, not only live ones. Reproduced.
3. Rejecting an agent's proposed replacement leaves the superseded row's `supersede_proposed_by` pointing at the rejected row, so every later agent `supersede` of that decision is refused forever, and the append-only validator offers no repair path. Reproduced.

Process: `reviewer.md` is the PR title only and carries no `## AC Verification` section, which is an automatic CHANGES_REQUIRED under this skill. The cross-model dissent (two voices, both completed) independently raised findings 1 to 3.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Functionality — the live ledger does not exist in the change

- **HIGH** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:271` — on the main checkout every `new`, `decide`, `reject`, `supersede` and `import` dies with "ledger not found: … (restore the tracked grimoires/loa/decisions.yaml)", because that file is neither in `pr/head.diff` nor created by the writer.
**File:** `head/.claude/scripts/lib/dec-write-lib.sh:262-271` (pending files are bootstrapped at 262-270; the live target is only tested at 271)
**Issue:** The PR re-includes `grimoires/loa/decisions.yaml` in git (`head/.gitignore:150-151`), adds it to the validator's `tracked_set` (`head/.claude/scripts/validate-gitignore-state.sh:58`), and makes the writer the only sanctioned way to touch it (`head/.claude/commands/decisions.md:30-32`: "Never edit the YAML by hand"), yet the file itself is absent from the 39-file change. The tests assume it is tracked with a header comment: `head/tests/unit/dec-write-lib.bats:13,28` runs `sed` on `$REPO/grimoires/loa/decisions.yaml` in `setup()` and `:111` expects the header line `# grimoires/loa/decisions.yaml: the decision ledger`; `head/tests/unit/validate-artifact.bats:630,644` and `head/tests/unit/grimoire-index.bats:80` do the same.
**Why This Matters:** Observed on a scratch head tree: all 44 writer tests fail in `setup` with `sed: can't read …/grimoires/loa/decisions.yaml`, and "the live ledger passes" fails. Every new instruction this PR adds to skills (`head/.claude/protocols/karpathy-principles.md:33-38`, `head/.claude/skills/autonomous-agent/SKILL.md:66`) tells unattended runs to call `dec-write-lib.sh new`, which cannot succeed. With `decisions.surface_at_session_start: true` the hook prints the "unreadable" WARNING on every session (`head/.claude/hooks/session-start/loa-decisions-surface.sh:57-59`).
**Required Fix:** Commit the seeded `grimoires/loa/decisions.yaml` (header comment, `schema_version: 1`, `decisions: []`) in this PR, or make `resolve_target write` bootstrap the live file the same way it bootstraps a pending file. If the file is meant to land in part 2, the tests and the skill prose must not depend on it until then.

### 2. Data integrity — operator confirms are misattributed under a PRD-status signal

- **HIGH** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:313-317` — when the PRD `**Status:**` line contains "autonomous" or "unattended", `derive_attribution` discards the operator's `--answer-ref cli:…` with a WARN, so `op_confirm` at `:538` sets `decided_by` to the proposing voice (`agent`) instead of `operator`, while the row still becomes `decided`.
**File:** `head/.claude/scripts/lib/dec-write-lib.sh:313-317`, `:536-540`, `:177-180` (the `prd` signal), `:509` (confirm refuses only on *live* signals)
**Issue:** `op_confirm` correctly refuses only when a live signal holds (`live_run_signal`, `:509`), but then calls `derive_attribution`, whose short-circuit uses `is_unattended` (`:183`), which also fires on the non-live `prd` signal. Reproduced on a scratch tree: a PRD with `**Status:** Draft, autonomous run`, then `confirm --id DEC-0001 --recorded-by decisions-command --evidence cli:… --answer-ref cli:…` exits 0, prints `WARN: unattended context: --answer-ref ignored (the row stays proposed … until /decisions confirm)` (wrong: this *is* the confirm), and the row reads `status: decided, decided_by: agent, decided_by_ref: null`. `head/.claude/commands/decisions.md:54-56` promises the opposite ("That operator-kind reference is what records `decided_by: operator`"). The same `is_unattended` check makes the operator's `reject` of a decided row die (`:575`) and downgrades the operator path of `supersede` to the agent path (`:600`, `:606`) while the operator is typing interactively.
**Why This Matters:** A PRD status line is a cycle-long persistent state. In that state every `/decisions confirm` permanently writes `decided_by: agent` into an append-only ledger, the PR body and SDD appendix (`list --not-decided-by operator`) keep listing operator-confirmed rows as agent-taken, and the operator cannot reject any decided row at all. The existing test `head/tests/unit/dec-write-lib.bats:362-365` exercises exactly this path but asserts only `status`, not `decided_by`, so it did not catch it.
**Required Fix:** Treat an operator call as interactive unless a *live* signal holds: in `derive_attribution`, skip the unattended short-circuit when `is_operator_call && ! live_run_signal` (or have `op_confirm` die when `is_unattended` is true for a prd-only signal rather than silently misattributing); apply the same rule to the operator branches of `op_reject` and `op_supersede`. Extend the test at `:362-365` to assert `decided_by == operator`.

### 3. State machine — rejecting a proposed replacement leaves a dangling `supersede_proposed_by`

- **HIGH** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:580-585` — `op_reject` rewrites only the rejected row; when that row `supersedes` a decided row, the old row's `supersede_proposed_by` keeps pointing at the now-`rejected` id, so the guard at `:600-602` refuses every later agent `supersede` of that decision with "a replacement is already proposed".
**File:** `head/.claude/scripts/lib/dec-write-lib.sh:580-585` (reject), `:600-602` (guard), `:610` (where the pointer is set)
**Issue:** Reproduced: `new … --status proposed` → operator `confirm` (DEC-0004) → agent `supersede` (DEC-0005, `DEC-0004.supersede_proposed_by = DEC-0005`) → operator `reject --id DEC-0005` exits 0 → `DEC-0004` still carries `supersede_proposed_by: DEC-0005` → agent `supersede --id DEC-0004` exits 1 "a replacement is already proposed for DEC-0004: DEC-0005". `validate-artifact.sh --type decisions` passes the resulting ledger (the validator at `head/.claude/scripts/validate-artifact.sh:654-656` only checks that the named row has `supersedes == id`, not its status), and the append-only rule rejects a later null-ing of the field as a content edit, so the writer has no repair path.
**Why This Matters:** "Operator rejects the agent's proposed correction, agent proposes a better one" is the normal correction flow the command documents (`head/.claude/commands/decisions.md:85-93`). After one rejection, agents are locked out of that decision permanently; only an operator-attributed `supersede` can touch it again. In `op_confirm` the stale pointer also means a later confirm of a different replacement skips the `decided -> superseded` transition (`:547`).
**Required Fix:** In `op_reject`, when the rejected row has `.supersedes` set and the old row's `.supersede_proposed_by == id`, null that field (and bump `updated_at`) on the old row in the same write, include the old id in the touched list passed to `verify_and_swap`, and allow that specific transition in the validator's append-only check (`validate-artifact.sh:669-680`). Add a test for reject-then-supersede.

---

## Observations

### 1. Security — the operator gate is a caller-supplied flag

- **MEDIUM** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:359` — `is_operator_call` is `--recorded-by decisions-command`; `disable-model-invocation` hides the slash command from the Skill tool, but nothing stops an agent's Bash tool from running `dec-write-lib.sh confirm --recorded-by decisions-command …` directly and recording `decided_by: operator` with a fabricated `cli:` ref.
**File:** `head/.claude/scripts/lib/dec-write-lib.sh:359`, `:508`, `:716`; `head/.claude/commands/decisions.md:24-28`
**Suggestion:** The allowlist tests (`head/tests/unit/dec-write-lib.bats:547-562`, `head/tests/unit/user-invoked-commands.bats:131-135`) scan checked-in prose only. Either document the gate as advisory (the command doc currently states it as a hard boundary: "an agent that could run them would confirm its own decisions"), or add a signal the model cannot forge from Bash (a settings.json deny rule on `dec-write-lib.sh confirm`, or a one-shot nonce the `/decisions` session writes under `.run/`). CWE-290 (authentication bypass by spoofing). Raised by both dissent voices (DISS-002, DISS-C-004).
**Benefit:** The ledger's central claim ("which decisions did a human take?") becomes enforceable rather than conventional.

### 2. Data loss — `import` does not lock the pending file it deletes

- **MEDIUM** (confidence: medium) `head/.claude/scripts/lib/dec-write-lib.sh:628-629,655` — `import` locks only the live ledger, reads the pending file once, and unconditionally `rm -f`s it at the end; a worktree writer appending between the snapshot and the `rm` (its lock lives under the *worktree's* `.run`, `:207`) loses that row permanently.
**Suggestion:** Hold a lock keyed on the pending file (shared across main checkout and worktrees, e.g. under `MAIN_ROOT/.run`) through snapshot, swap and removal, or rename the pending file to `<name>.importing` first and import from the renamed copy. Dissent DISS-003.
**Benefit:** No decision row silently disappears when the lead imports while a teammate is still writing.

### 3. Functionality — `context --clear` clears only this checkout's marker

- **MEDIUM** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:717-718` — `ctx_signals` reads `unattended.json` from both this `.run` and the main checkout's (`:135`, `:166-168`), but `--clear` removes only `${PROJECT_ROOT}/.run/unattended.json`; from a linked worktree `/decisions clear-unattended` logs "unattended marker cleared" while the main-checkout marker keeps `confirm` refusing.
**Suggestion:** Iterate `run_dirs` in the `--clear` branch, or refuse with a message naming the main-checkout path. Dissent DISS-C-007.
**Benefit:** The repair text the hook prints actually repairs the state.

### 4. Testing — a live LLM call inside the unit suite

- **MEDIUM** (confidence: high) `head/tests/unit/user-invoked-harness.bats:134-153` — the "live harness" test runs `claude -p` (network, tokens, up to 180 s) by default whenever a `claude` binary is on PATH; it is skipped only on `LOA_HARNESS_CHECK=0` or when the CLI is absent.
**Suggestion:** Default the live test to off (`LOA_HARNESS_CHECK=1` to opt in) or move it out of `tests/unit/`. The offline classifier tests already pin the logic.
**Benefit:** `bats tests/unit` stays hermetic and deterministic on developer machines.

### 5. Documentation — the new command is not catalogued

- **MEDIUM** (confidence: medium) `head/.claude/commands/decisions.md:1` — the change adds the `/decisions` command and bumps the command count to 50 in `head/AGENTS.md:14,32` and `head/README.md:5,125`, but touches no CHANGELOG entry and no command catalogue (`PROCESS.md`, which both files point to as "the full list", and `CLAUDE.loa.md`).
**Suggestion:** Add the CHANGELOG entry for the sprint and the `/decisions` row in the catalogue the README references.
**Benefit:** Required by this skill's documentation gate (a CLAUDE.md entry per new command, a CHANGELOG entry per task).

### 6. Data integrity — `import` retry after a failed `--rewrite` duplicates rows

- **LOW** (confidence: medium) `head/.claude/scripts/lib/dec-write-lib.sh:647-655` — the ledger swap happens at `:647`; if a `--rewrite` step then fails under `set -e` (`:651-653`), the pending file survives and a retry allocates fresh DEC ids for rows already imported; `verify_and_swap` cannot see the duplication because the ids differ.
**Suggestion:** Rename or mark the pending file immediately after the swap, before any rewrite work. Dissent DISS-C-005.

### 7. Trust — `import` appends rows without re-deriving their status

- **LOW** (confidence: medium) `head/.claude/scripts/lib/dec-write-lib.sh:642-646` — imported rows keep whatever `status`, `decided_by` and `transitions` the pending file carries; a hand-edited pending row with a well-formed `proposed -> decided` transition and `by: operator:…` passes the validator and lands `decided` without `confirm`.
**Suggestion:** Assert in `op_import` that each row is `open` or `proposed` with `decided_by == null` and `supersedes == null`. Dissent DISS-C-006 (noted that a hand edit of the live ledger is already outside the trust model, so this is hardening).

### 8. Parsing — two round blocks on one line merge into one malformed block

- **LOW** (confidence: high) `head/tools/check-round-independence.sh:55,59` — `BLOCK_RE` uses a greedy `\[.*\]` and `grep -oE` is line-oriented, so `<!-- round: 1; … --> text <!-- round: 2; … -->` on one line is read as a single round whose array is malformed; the checker then reports "malformed questions array" and "0 new questions" rather than parsing both rounds. The documented format is one block per line, so this is an input-contract edge, not a false PASS.
**Suggestion:** Use a non-greedy or `[^]]`-bounded array match, or split on `-->` before matching.

### 9. Usability — `--help` after a subcommand is a usage error; help prints a code line

- **LOW** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:98,739` — `dec-write-lib.sh new --help` exits 2 with "unknown flag --help (see --help)" because `help` is not in `KNOWN_KEYS`; and `sed -n '2,45p'` at `:739` prints line 45 (`export LC_ALL=C`) as the last line of the help text.
**Suggestion:** Accept `--help` in the flag loop and change the range to `2,44p`.

### 10. Usability — the empty-table message assumes one filter

- **LOW** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:694` — `list --format md` prints "_None: every decision in this run was the operator's._" for *any* empty result, including `--status open` or `--cycle X`, where the sentence is false.
**Suggestion:** Emit the operator sentence only when the filter is `--not-decided-by operator` / `--voice agent,…`; otherwise "_No matching rows._".

### 11. Testing — the PRD-signal confirm test asserts too little

- **LOW** (confidence: high) `head/tests/unit/dec-write-lib.bats:362-365` — the test that confirms under a PRD `**Status:** … autonomous run` checks only `status == decided`; asserting `decided_by == operator` would have caught Changes Required 2.

### 12. FAST-GATE — no self-check evidence in the report

- **LOW** (confidence: medium) `head/tests/unit/dec-write-lib.bats:1` — `reviewer.md` records no `bats`, `shellcheck` or formatter run. The reviewer ran all seven new suites on a scratch head tree (results in Overall Assessment); shellcheck was not run here. Record the fast-gate commands and results in the report on resubmission.

---

## Cross-Model Observations

Adversarial review: `grimoires/loa/a2a/sprint-1/adversarial-review.json`, primary `gpt-5.5-pro` (answered by `codex-headless`), companion `claude-headless`, both completed (`voices_succeeded: 2/2`, `consensus_outcome: consensus`). Triage of the 11 findings:

| Dissent id | Severity | Triage |
|---|---|---|
| DISS-001, DISS-C-001 | BLOCKING | Confirmed — Changes Required 1 (missing ledger) |
| DISS-C-002 | BLOCKING | Confirmed by reproduction — Changes Required 2 (PRD-signal misattribution) |
| DISS-004, DISS-C-003 | BLOCKING | Confirmed by reproduction — Changes Required 3 (dangling `supersede_proposed_by`) |
| DISS-002, DISS-C-004 | BLOCKING / ADVISORY | Accepted as design limitation, recorded as Observation 1 (MEDIUM): the PR's own lint tests show the author treats prose scanning as the enforcement; the doc overclaims |
| DISS-003 | BLOCKING | Downgraded to Observation 2 (MEDIUM): real race, narrow window, needs concurrent worktree writer during import |
| DISS-C-005 | ADVISORY | Observation 6 (LOW) |
| DISS-C-006 | ADVISORY | Observation 7 (LOW): hand-edited input is outside the trust model |
| DISS-C-007 | ADVISORY | Confirmed in code — Observation 3 (MEDIUM) |

## Rejected dissent payloads

- None: `metadata.rejected_summary` is empty and the sidecar `adversarial-rejected-review.jsonl` holds zero rows.

---

## Previous Feedback Status

No previous `engineer-feedback.md` existed for this sprint.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | The tracked ledger file; attribution fix for operator confirms; reject/supersede pointer repair; an `## AC Verification` section in `reviewer.md` |

---

## Acceptance Criteria Check

### Task 1.1: review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict

| Criterion | Status | Notes |
|-----------|--------|-------|
| `reviewer.md` carries `## AC Verification` | Fail | Report is the PR title only; automatic CHANGES_REQUIRED |
| Writer works on a fresh main checkout | Fail | Changes Required 1 |
| `/decisions confirm` records `decided_by: operator` | Fail | Changes Required 2 (PRD-status signal) |
| Reject-then-supersede correction flow | Fail | Changes Required 3 |
| Append-only, verified, atomic ledger writes | Pass | `verify_and_swap` + validator; byte-identical-on-failure test passes |
| Hostile strings sanitised; L6 fence on the surface | Pass | Corpus and negative hook tests pass |
| Operator-only commands flagged and listed | Pass | 12/12 allowlist tests; enforcement caveat in Observation 1 |
| Rounds pacing documented and checkable | Pass | 13/13 round-checker tests; fixtures valid |
| New suites green | Pass with caveat | All green only with a seeded ledger |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [x] Input validation and sanitization present (san1, jq `--arg`, yq `env()`, L6 fence)
- [ ] Authentication/authorization correct — operator gate is a spoofable flag (Observation 1); attribution wrong under PRD signal (Changes Required 2)
- [x] No injection vulnerabilities found (values never interpolated into yq/jq programs; artifact paths confined to the project)
- [x] Dependencies secure (jq, Mike Farah yq v4, flock; preflight fails closed)
- [x] Error messages don't leak sensitive data

---

## Code Quality Summary

**Strengths:**
- Verified, atomic, append-only writes with a byte-identical-on-failure guarantee and a validator that re-checks every candidate.
- Consistent trust-boundary handling: control-byte stripping, 160-code-point cap, fence-safe id/summary reduction, no hand-assembled YAML.
- Test seams gated on both a test-mode env var and a bats marker; hermetic temp projects; a hostile-string corpus.

**Areas for Improvement:**
- The `is_unattended` predicate is used for two different questions (should a write land `proposed`? / is the operator really here?) and conflates them in the operator paths.
- `op_reject` and `op_supersede` each know half of the `supersede_proposed_by` invariant.
- Complexity: `dec-write-lib.sh` is 741 lines with several 50-plus-line functions (`op_confirm` 53, `op_import` 41, `build_row` 32); acceptable for a single-purpose CLI, but `verify_and_swap`'s jq program and the validator's jq program duplicate the schema in two places. SIMPLICITY: Lean already apart from that duplication; `net: -0 lines possible` without a shared schema module. Ship after the fixes.

---

## Next Steps

1. Add the seeded `grimoires/loa/decisions.yaml` (or bootstrap it in `resolve_target`).
2. Make operator paths ignore non-live unattended signals; assert `decided_by` in the PRD-signal test.
3. Clear `supersede_proposed_by` on reject; allow that transition in the validator; add the reject-then-supersede test.
4. Write `## AC Verification` in `reviewer.md` with `file:line` evidence and the fast-gate commands run.
5. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":5,"low":7},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T06:48:25Z"} -->
