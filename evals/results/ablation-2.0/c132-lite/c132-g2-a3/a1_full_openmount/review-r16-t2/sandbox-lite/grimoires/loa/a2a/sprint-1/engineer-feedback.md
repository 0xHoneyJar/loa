# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)

---

## Overall Assessment

The PR (sprint-252 decision surfaces, part 1) adds the decision-ledger writer `dec-write-lib.sh`, a `--type decisions` validator, the operator-only `/decisions` command and allowlist, the default-off SessionStart surface, the `rounds` interview pacing with its transcript checker, and the grimoire-index `decisions` family. The code is careful in many places (yq values only through `env()`, rows built by `jq --arg`, verify-before-rename, hostile-string corpus, L6 fencing of the surface), and the PR's own bats suites pass when run here: dec-write-lib 44/44, loa-decisions-surface 8/8, check-round-independence 13/13, user-invoked-commands 12/12, user-invoked-harness 4/4 offline (live test skipped), grimoire-index decisions 5/5, validate-artifact 51/51. The agents-md-gen count/checksum tests could not be verified (this workspace carries a different command set); `grimoires/loa/decisions.yaml` itself is not in the PR and is assumed to pre-exist tracked, as the tests assume.

The core invariant the PR sells, however, does not hold. The live-run guard on `confirm` is a `cmd | grep -q` pipeline under `set -o pipefail`: with two or more live signals (the normal autonomous shape, a fresh `.run/unattended.json` plus a RUNNING run state) the producer dies of SIGPIPE, the pipeline returns 141, and confirm proceeds. Reproduced 5 of 5 times. A second attribution defect makes the PRD `**Status:**` line, a permanent planning artifact, drive operator-facing operations: an operator confirm records `decided_by: agent`, an operator reject of a decided row is refused, an operator supersede lands as an agent proposal. Further: `--file <live path>` bypasses the CI/hook/worktree refusals; rejecting a proposed replacement leaves a stale `supersede_proposed_by` that blocks every later agent supersede and makes the operator's reject of the original abort; `import` commits the live ledger before rewrites and before removing the pending file, so a partial failure duplicates rows on retry and a concurrent worker's row is dropped; and the validator's merge-base path false-fails any branch where one row moved open → proposed → decided.

Adversarial dissent (two independent voices, gpt-5.5-pro via codex-headless and claude-headless) ran against `pr/head.diff`; its four BLOCKING findings were each verified in a scratch tree before being counted below; its advisory findings are triaged under Cross-Model Observations. No payload was rejected.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Security / Integrity — the operator-only guard on `confirm` fails under the normal autonomous-run shape (dissent DISS-C-001, verified)

- **CRITICAL** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:184` — `live_run_signal(){ ctx_signals | grep -q '^live ' ; }` runs under `set -euo pipefail`; `grep -q` exits on the first match, `ctx_signals` then writes its next line into a closed pipe, dies with SIGPIPE (141), and the pipeline is false, so `if live_run_signal; then die …` at `head/.claude/scripts/lib/dec-write-lib.sh:509` never fires when two or more live signals exist.
**File:** `head/.claude/scripts/lib/dec-write-lib.sh:184`, used at `head/.claude/scripts/lib/dec-write-lib.sh:509`
**Issue:** Reproduced in a scratch copy: `context --set-unattended` (fresh marker) plus `.run/sprint-plan-state.json` `{"state":"RUNNING"}` → `context --why` lists two `live` signals → `confirm --id DEC-000N --recorded-by decisions-command --evidence cli:…` succeeded 5/5 times and every row became `decided`. The isolated pipeline (`f | grep -q` with a `jq` fork between echoes) returned 141 on 3/3 runs. `autonomous-agent/SKILL.md:66` now tells every unattended run to write the marker while the run state is RUNNING, which is exactly the two-signal shape.
**Why This Matters:** `decisions.md:59` and the file header (`:17`) promise that confirm refuses during a live unattended run; this is the invariant that keeps agent-proposed rows `proposed` until a human confirms. It silently does not hold.
**Required Fix:** Capture, then test: `live_run_signal(){ local s; s="$(ctx_signals)" || true; grep -q '^live ' <<< "$s"; }` (or test `is_unattended`-style on the captured string). Add a bats case with two live signals (marker + RUNNING) asserting confirm exits 1.
**Reference:** CWE-754 (improper check for unusual or exceptional conditions); bash pipefail + SIGPIPE semantics.

### 2. Functionality / Attribution — the PRD Status line is treated as a live unattended signal for operator operations (verified)

- **HIGH** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:183` — `is_unattended()` is true on any `ctx_signals` line, including `prd prd-status` (`:177-180`), so with `grimoires/loa/prd.md` carrying `**Status:** Draft (autonomous run)` the operator's own calls are demoted: `confirm --answer-ref cli:…` has its ref dropped at `:314` and records `decided_by: agent` (`:538`); `reject` of a decided row dies at `:575`; `supersede` by the operator takes the agent path at `:600-611`.
**File:** `head/.claude/scripts/lib/dec-write-lib.sh:183` (also `:313-317`, `:575`, `:600-611`)
**Issue:** Reproduced: with that PRD line, `confirm --recorded-by decisions-command --evidence cli:… --answer-ref cli:…` → WARN "--answer-ref ignored" and the row reads `decided_by: agent, decided_by_ref: null` while its last transition says `by: operator:decisions-command`; `reject --id DEC-0001 --recorded-by decisions-command` → "the context is unattended; the operator rejects it interactively" (exit 1); operator `supersede` left DEC-0001 `decided` with `supersede_proposed_by` and the new row `proposed_by: agent`. The PRD Status line persists after an autonomous planning run, so these operations stay broken for the whole cycle. The PR's own test at `head/tests/unit/dec-write-lib.bats:355-367` shows the intent (the PRD line must not block confirm) but only asserts `.status`, not `decided_by`.
**Why This Matters:** `decided_by` is the field the whole feature exists to make trustworthy ("which decisions did a human take?"). Here a human confirmation is recorded as the agent's, and the operator cannot reject or supersede.
**Required Fix:** Split the scopes: the PRD line is a planning-time default for `new`/`decide` only (status → proposed, refs ignored); `confirm`, `reject`, `supersede` and `context`'s verdict follow live signals only (`live_run_signal`, once fixed per §1). Extend the bats test to assert `decided_by == operator` with the PRD line present.

### 3. Security — `--file <live ledger>` bypasses the CI/hook refusal and the worktree redirect (verified)

- **HIGH** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:251` — every `--file` target is `TARGET_KIND="fixture"` and returns before the `ci_blocked` check at `:261`, so `CI=1 dec-write-lib.sh new --file grimoires/loa/decisions.yaml …` writes the live ledger (reproduced: exit 0, row appended), a hook with `LOA_HOOK_CONTEXT=1` can do the same, a linked worktree can write the main ledger by path instead of its pending file, and `confirm`/`supersede` on a `--file …/decisions-pending.yaml` escape their pending-file refusals at `:512` and `:593`.
**File:** `head/.claude/scripts/lib/dec-write-lib.sh:251`
**Issue:** The header (`:22-23`) promises "Live-ledger writes exit 1 under CI, GITHUB_ACTIONS or LOA_HOOK_CONTEXT=1 (--file fixtures are exempt)"; the exemption is decided by flag presence, not by what the path is.
**Why This Matters:** The CI/hook refusal is the mechanical fence keeping unattended automation out of tracked team state; a path argument should not defeat it.
**Required Fix:** Classify an explicit `--file` by its canonical path (live ledger of this or the main checkout → `live`; `grimoires/loa/a2a/<dir>/decisions-pending.yaml` → `pending`; else `fixture`) and apply the CI/hook and worktree rules to the first two. Add bats cases for `CI=1 … --file grimoires/loa/decisions.yaml` (exit 1) and `confirm --file <pending>` (exit 1).
**Reference:** CWE-284 (improper access control).

### 4. Functionality — rejecting a proposed replacement leaves a stale `supersede_proposed_by` (dissent DISS-003 / DISS-C-005, verified)

- **HIGH** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:580-585` — `op_reject` rewrites only the rejected row; when that row `supersedes` a decided row, the predecessor keeps `supersede_proposed_by: <rejected id>`, so every later agent `supersede` dies at `:601` ("a replacement is already proposed") and the operator's `reject` of the predecessor aborts in `verify_and_swap` because the validator (`head/.claude/scripts/validate-artifact.sh` supersedes rule) sees a row superseding a `rejected` row.
**File:** `head/.claude/scripts/lib/dec-write-lib.sh:580-585` (and `:601`)
**Issue:** Reproduced: agent `supersede` DEC-0001 → DEC-0002; operator `reject` DEC-0002 → DEC-0001 still `supersede_proposed_by: DEC-0002`; agent `supersede` DEC-0001 → exit 1 "already proposed"; operator `reject` DEC-0001 → "ABORT … DEC-0002: supersedes DEC-0001, which is "rejected" and does not name this row".
**Why This Matters:** One rejected proposal permanently freezes a decision for every non-operator voice and blocks the operator's reject, contradicting the lifecycle in the header and `decisions.md`.
**Required Fix:** In `op_reject`, when the rejected row has `.supersedes`, load the predecessor, clear `supersede_proposed_by` if it equals the rejected id, `replace_row` it and add it to the touched list; teach the validator's `supersedes` rule that a `rejected` successor is a legal terminal state. Add a bats case: supersede (agent) → reject → supersede (agent) succeeds; and reject of a decided row with a rejected successor succeeds.

### 5. Data integrity — `import` commits the live ledger before rewrites and before removing the pending file; no idempotency (dissent DISS-002 / DISS-C-004, verified by reading)

- **HIGH** (confidence: medium) `head/.claude/scripts/lib/dec-write-lib.sh:647-655` — `verify_and_swap` lands the imported rows at `:647`, then the `--rewrite` loop runs `mktemp "${p}.XXXXXX"` (`:651`) and `mv -f` under `set -e` with no `|| warn`; a read-only target directory or file aborts the script after the ledger changed and before `rm -f -- "$from"` (`:655`). Re-running `import` appends the same rows again under fresh DEC ids (nothing dedupes against already-imported rows), while files rewritten in the first pass keep the first ids.
**File:** `head/.claude/scripts/lib/dec-write-lib.sh:647-655`
**Issue:** The failure path is concrete (`chmod a-w` on a rewrite target's directory makes `mktemp` fail); the recovery path produces duplicate decision rows in an append-only ledger that can only be cleaned by rejecting them one by one.
**Why This Matters:** The ledger is tracked team state and the source for the PRD/SDD appendices and the PR body; duplicated rows with diverging references corrupt exactly what the PR sets out to make auditable.
**Required Fix:** Rename or remove the pending file (e.g. to `.imported`) immediately after `verify_and_swap` succeeds and before rewrites; make each rewrite failure warn-and-continue; print the PEND→DEC map before rewrites so a retry can be done by hand. Add a bats case with an unwritable rewrite target.

### 6. Data integrity — `import` removes the pending file without holding any lock on it (dissent DISS-001, verified by reading)

- **HIGH** (confidence: medium) `head/.claude/scripts/lib/dec-write-lib.sh:628` — `acquire_lock "$TARGET"` locks the live ledger only; the pending file is read at `:629`, validated, appended to the live ledger (verify + validator, about a second) and then deleted at `:655`. A worktree writer that appends a PEND row to the same pending file during that window succeeds (its lock lives under the worktree's own `.run`, keyed by its path), and `rm -f -- "$from"` deletes that row silently.
**File:** `head/.claude/scripts/lib/dec-write-lib.sh:628-655`
**Issue:** Lock paths are `${PROJECT_ROOT}/.run/.dec-write-<hash>.lock` (`:203-207`), so even locking `$from` from the main checkout would not coordinate with the worktree's writer; the design has no cross-checkout exclusion for the pending file at all.
**Why This Matters:** Parallel subagents in linked worktrees are the documented reason the pending file exists; a lost PEND row leaves a bead `external_ref` pointing at an id that never becomes a DEC.
**Required Fix:** Lock the pending file by a lock keyed on its canonical path under the main checkout's `.run` from both sides (the worktree writer can resolve `MAIN_ROOT`), hold it from the snapshot through removal, and refuse import when the file changed between snapshot and removal (compare a hash). Add a bats case that appends to the pending file between snapshot and removal.

### 7. Validation — the merge-base path of `--type decisions` false-fails legitimate multi-write histories (verified)

- **HIGH** (confidence: high) `head/.claude/scripts/validate-artifact.sh:550-554` — without `--base-file` the validator compares against the copy at `git merge-base origin/main HEAD`, but applies the single-write rules written for the writer's `--base-file` call: `:671` fails on "more than one transition appended in one write" and `:682` compares every field against only the *last* appended transition, so a row that went open → proposed (decision, rationale, alternatives filled) → decided on one branch reports four violations.
**File:** `head/.claude/scripts/validate-artifact.sh:550-554`, rules at `:671` and `:682`
**Issue:** Reproduced in a scratch repo: commit an `open` row, point `origin/main` at it, `decide` then `confirm`, run `validate-artifact.sh --type decisions --file grimoires/loa/decisions.yaml` → exit 1 with "more than one transition appended in one write" and "content edit to alternatives_considered / decision / rationale".
**Why This Matters:** This default path is what `/validate` or CI will run on a branch; a fail-closed validator that rejects the ordinary lifecycle invites hand edits of the ledger, the one thing the design forbids.
**Required Fix:** Pass a `strict` flag when `--base-file` is given (one write, at most one transition) and, for the merge-base path, accept any number of appended transitions each already checked as a legal step, comparing content fields against the set of appended transitions rather than the last one. Add a bats case for the merge-base path with two writes on one row.

---

## Observations

### 1. Security — `--rewrite` targets are not validated

- **MEDIUM** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:649-654` — `import --rewrite <path>` accepts any path: reproduced with a symlink `/tmp/link.txt → /tmp/outside.txt`; the loop replaced the symlink with a regular file outside the project. No `..` check, no project containment, no symlink refusal, unlike `artifact_path` (`:289-305`) which has all three.
**Suggestion:** Reject `..`, require an existing regular non-symlink file whose canonical path is under `PROJECT_ROOT`, as `artifact_path` already does.
**Benefit:** Keeps the one writer that touches arbitrary files inside the tree it owns.

### 2. Security claim — the operator-only gate is a caller-supplied string (dissent DISS-C-002, advisory)

- **MEDIUM** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:359` — `is_operator_call` is `[[ "$(o recorded-by)" == decisions-command ]]`; any session with Bash can run `confirm … --recorded-by decisions-command --answer-ref cli:…` and record `decided_by: operator`. `disable-model-invocation` hides `/decisions` from the Skill tool and the bats grep covers checked-in text only. The header (`:17`) and `decisions.md:24` state it as a hard property.
**Suggestion:** Say plainly in the header, `decisions.md` and the SDD that the gate is an advisory fence (same class as the framework's other accepted fence gaps), or bind confirm to something the model cannot type (a nonce `/decisions` drops under `.run`).
**Benefit:** The provenance claim readers rely on matches what the writer enforces.

### 3. Testing — the unit suite makes a live, paid model call by default

- **MEDIUM** (confidence: high) `head/tests/unit/user-invoked-harness.bats:134-151` — whenever `claude` is on PATH and `LOA_HARNESS_CHECK` is unset, `bats tests/unit` runs `claude -p` for up to 180 s against the operator's account. Developers' machines routinely have the CLI.
**Suggestion:** Default the live test to off (`LOA_HARNESS_CHECK=1` opts in) or move it under an `integration/` directory excluded from the default unit run.
**Benefit:** Unit runs stay hermetic, fast and free.

### 4. Documentation — the new hook and writer are absent from the reference inventories

- **MEDIUM** (confidence: high) `head/.claude/settings.json:507-511` — registers `loa-decisions-surface.sh` as a SessionStart hook, but `.claude/loa/reference/hooks-reference.md` (the fence inventory CLAUDE.loa.md points to) and `.claude/loa/reference/scripts-reference.md` are not touched by the PR; `PROCESS.md`, which README.md:125 and AGENTS.md:32 cite for "the full list" of the now 50 commands, is not updated for `/decisions` either; no CHANGELOG entry.
**Suggestion:** Add the hook row (knobs, trust handling, test file), the `lib/dec-write-lib.sh` row and the `/decisions` entry, plus a CHANGELOG line.
**Benefit:** The inventories stay the source of truth the rules reference.

### 5. Complexity — `validate_decisions` is one 190-line function around a 150-line jq program

- **MEDIUM** (confidence: medium) `head/.claude/scripts/validate-artifact.sh:526-717` — well over the 50-line threshold; the jq rule set is justified by the comment block, but the row rules, the transition rules and the append-only diff are three separable programs.
**Suggestion:** `SIMPLICITY[shrink]`: move the jq program to `lib/dec-validate.jq` and call it with `jq -f`, keeping the bash wrapper to argument handling and the artifact-hash loop. `net: -0 lines possible` (a relocation, not a deletion). Everything else in the PR: Lean already. Ship.
**Benefit:** Each rule set can be unit-tested and read in isolation.

### 6. Configuration — the example config hard-sets `pacing: rounds`, defeating the documented mode default

- **MEDIUM** (confidence: high) `head/.loa.config.yaml.example:140` — the comment at `:127` says "Unset: rounds for thorough, batch for minimal. An explicit value always wins", and the SKILL.md resolution (`head/.claude/skills/discovering-requirements/SKILL.md:58`) implements that; a user who copies the example and sets `interview.mode: minimal` gets `rounds`, not `batch`.
**Suggestion:** Ship the key commented out (`# pacing: rounds`) so the mode default applies, or state that minimal users must change it.
**Benefit:** The example config behaves as its own comment describes.

### 7. Concurrency — pending-file bootstrap happens before the lock (dissent DISS-C-003, advisory)

- **LOW** (confidence: low) `head/.claude/scripts/lib/dec-write-lib.sh:262-270` — the `cat > "$TARGET"` bootstrap runs in `resolve_target`, before `acquire_lock` at `:468`; two concurrent first writers in one worktree could truncate each other, but the window between the `-f` test and the `cat` is microseconds against a one-second write, so loss needs an unlikely schedule.
**Suggestion:** Bootstrap inside the lock, or `set -o noclobber` for the create.
**Benefit:** Removes the race outright at no cost.

### 8. Maintainability — invisible characters inside the jq class

- **LOW** (confidence: high) `head/.claude/hooks/session-start/loa-decisions-surface.sh:69` — the class `[[:cntrl:]\u0080-\u009f  ]` carries literal U+2028 and U+2029 bytes (verified with `od`), invisible in editors and easily lost by a reformat; the sibling in `grimoire-index.sh:189` writes them as `  ` escapes.
**Suggestion:** Use the escapes here too.
**Benefit:** The sanitiser's intent is visible and survives editing.

### 9. Consistency — the index's decisions summary is not angle-bracket-neutralised

- **LOW** (confidence: medium) `head/.claude/scripts/grimoire-index.sh:189` — the surface replaces `<`, `>` and backticks before fencing (`loa-decisions-surface.sh:69`), the index only flattens controls; `INDEX.md` is agent-read. This matches the other families' `san()` (`:55`), so it is a parity gap, not a regression.
**Suggestion:** Add the same `<`/`>` replacement to `s`.
**Benefit:** One sanitisation story for agent-authored ledger text.

### 10. Usability — `--help` leaks a code line; stale catalog header

- **LOW** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:739` — `sed -n '2,45p'` prints line 45, `export LC_ALL=C`, as the last line of the help text (verified). `head/.claude/scripts/grimoire-index.sh:217` still describes the catalog as "KF · vision · lore · handoff · observation": observation was removed in cycle-121 and decisions is now a family.
**Suggestion:** `'2,44p'`; update the header string.
**Benefit:** Help and headers say what the code does.

### 11. SIMPLICITY — ignore-then-negate pair in `.gitignore`

- **LOW** (confidence: high) `head/.gitignore:149-150` — `grimoires/loa/decisions.yaml` is ignored on one line and re-included on the next, and `validate-gitignore-state.sh` gains an `is_ignored_match` helper (`head/.claude/scripts/validate-gitignore-state.sh:71-76`) to tolerate the negation.
**Suggestion:** `SIMPLICITY[delete]`: drop the ignore line; the helper then has no live case in this PR (keep it only if another negation exists). `net: -3 lines possible`.
**Benefit:** Fewer rules to explain.

### 12. Robustness — `--min-average 02` surfaces a raw jq error

- **LOW** (confidence: high) `head/tools/check-round-independence.sh:52` accepts `02`; `:82` passes it to `--argjson`, which rejects a leading zero, so the user sees jq's "Invalid JSON text" instead of the script's usage line (exit 2 either way).
**Suggestion:** Normalise with `$((10#…))` for integers or reject a leading zero in the regex.
**Benefit:** A clear message for a clear mistake.

---

## Cross-Model Observations

Two voices answered (primary gpt-5.5-pro answered by codex-headless; companion claude-headless, counted as an independent voice). Triage:

- DISS-001 (BLOCKING, import deletes the pending file without a lock) → verified by reading → counted as Changes Required §6.
- DISS-002 (BLOCKING, ledger committed before rewrites, no retry mapping) → verified by reading → merged with DISS-C-004 into Changes Required §5.
- DISS-003 (BLOCKING, stale `supersede_proposed_by`) → reproduced → merged with DISS-C-005 into Changes Required §4.
- DISS-C-001 (BLOCKING, SIGPIPE in `live_run_signal`) → reproduced 5/5 → Changes Required §1 (CRITICAL).
- DISS-C-002 (ADVISORY, `--recorded-by` is a caller string) → accurate; a design-level fence gap → Observations §2.
- DISS-C-003 (ADVISORY, bootstrap before lock) → accurate but a microsecond window → Observations §7.
- DISS-C-004 / DISS-C-005 (ADVISORY) → duplicates of DISS-002 / DISS-003, folded as above.

## Rejected dissent payloads

None: `metadata.rejected_summary` is empty and the listed sidecar `adversarial-rejected-review.jsonl` holds zero rows.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Not mergeable | The seven items under Changes Required |

---

## Acceptance Criteria Check

### Task 1.1: review the pull request, report each defect with file and line, give a merge verdict

| Criterion | Status | Notes |
|-----------|--------|-------|
| Each defect reported with `head/<path>:<line>` | Pass | 7 blocking, 12 observations above |
| Merge verdict given | Pass | CHANGES_REQUIRED |
| `reviewer.md` carries an `## AC Verification` walkthrough | Fail | The report is the PR title only (`pr/PR.md`); no AC walkthrough, no test-run evidence, no fast-gate (shellcheck) evidence. Per the skill this alone forces CHANGES_REQUIRED. |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (the dissent's secret scan redacted one token-shaped string in the diff; none in head sources)
- [ ] Input validation and sanitization present — `--rewrite` paths unvalidated (Obs. §1); `--file` path class unvalidated (CR §3)
- [ ] Authentication/authorization correct — confirm guard bypass (CR §1); operator attribution demoted by a PRD line (CR §2); operator gate is a string (Obs. §2)
- [x] No SQL/XSS injection vulnerabilities — yq values via `env()`, jq via `--arg`; L6 fence on the surface
- [x] Dependencies secure — jq 1.6+, Mike Farah yq v4 version-checked before any write
- [x] Error messages don't leak sensitive data

---

## Code Quality Summary

**Strengths:**
- Verify-before-rename with a full re-validation of the candidate; the ledger was byte-identical after every refused write in the tests.
- The hostile-string corpus and the L6-fenced surface treat ledger text as untrusted end to end.
- `check-round-independence.sh` is small, exits are well-defined, and its fixtures double as documentation.

**Areas for Improvement:**
- Two unattended scopes are conflated (live vs planning-time); separate them explicitly.
- `import` needs a transactional order (swap → retire pending → rewrites) and locking that spans checkouts.
- `cmd | grep -q` under pipefail is a recurring trap; capture first.

**Karpathy:** `GOAL-DRIVEN:` the PR's tests assert `.status` after confirm but never `decided_by` under the PRD-line scenario, which is why CR §2 slipped through; add the assertion. `SURGICAL:` the skill prose edits (interview tables moved to REFERENCE.md) are tidy and in scope. `FAST-GATE:` no evidence that shellcheck ran on the four new/changed scripts; run it and report.

---

## Next Steps

1. Fix CR §1 (capture-then-grep) and CR §2 (scope split) first; both change attribution semantics and need new bats cases.
2. Fix CR §3 (`--file` classification), CR §4 (clear the stale pointer in `op_reject`), CR §5/§6 (import order and pending-file lock), CR §7 (strict vs merge-base rules).
3. Run `bats tests/unit` with `LOA_HARNESS_CHECK=0` and shellcheck on `dec-write-lib.sh`, `validate-artifact.sh`, `loa-decisions-surface.sh`, `check-round-independence.sh`; include the output in `reviewer.md` with an `## AC Verification` section.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":1,"high":6,"medium":6,"low":6},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T14:12:00Z"} -->
