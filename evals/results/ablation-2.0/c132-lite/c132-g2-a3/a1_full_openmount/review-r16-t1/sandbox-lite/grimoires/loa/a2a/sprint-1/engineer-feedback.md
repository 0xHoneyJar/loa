# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md (Task 1.1: the change in `pr/head.diff`, PR "feat(cycle-128): sprint-252 decision surfaces, part 1")
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= `pr/PR.md`: title and "39 file(s) in scope" only)

---

## Overall Assessment

The change lands a large, carefully built surface: the single-writer decision ledger (`dec-write-lib.sh`, 741 lines), a fail-closed ledger validator with an append-only base check, a default-off SessionStart surface wrapped in the L6 fence, the interview `rounds` pacing with a checker, and the operator-only command allowlist. The hostile-string corpus, the atomic temp-then-rename write, the lock, the derived (never passed) attribution and the lint tests over `--recorded-by decisions-command` are all good engineering, and the writer's own suites pass when a ledger file is present (I ran every new and modified bats file in a merged tree: 152 of 153 pass; the one failure is a pre-existing KF-009 index test that depends on this sandbox's unreadable `known-failures.md`).

Three findings block the merge, all reproduced by running the shipped scripts:

1. `import` copies pending rows verbatim, so a worktree (or any agent) can mint a `decided` / `decided_by: operator` row that the operator never confirmed. This bypasses the one invariant the whole feature exists to enforce.
2. The PRD `**Status:**` line is treated as an unattended signal for the operator's own operations. With a PRD that says "autonomous run" (a planning-time artifact that outlives the run), the operator's interactive `/decisions confirm --answer-ref cli:…` silently records `decided_by: agent`, `reject` of a decided row is refused, and operator `supersede` takes the agent path and leaves the old row decided, contradicting `decisions.md`.
3. The suites, the hook and the writer all depend on a tracked `grimoires/loa/decisions.yaml` with a specific header comment, and the change neither adds that file nor shows it in `pr/base/`. As shipped, all 46 `dec-write-lib.bats` tests fail in `setup()`.

The medium findings are real state-machine gaps (a rejected replacement permanently blocks agent supersede; operator supersede retires a decision before its replacement is decided; a failed `--rewrite` after the ledger swap duplicates rows on re-import; `--file <live path>` bypasses the CI/hook refusal) plus documentation gaps for CI-hosted unattended runs. None of them is hard to fix, and the test harness already in place makes each one a one-test addition.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Authorization: `import` lets an agent-authored pending file mint operator-decided rows

- **HIGH** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:642-647` — `op_import` appends every pending row verbatim (only PEND ids are rewritten), so a pending file carrying `status: decided`, `decided_by: operator`, an operator-kind `decided_by_ref` and a fabricated `proposed -> decided by operator:decisions-command` transition is imported into the live ledger and passes validation.
**File:** `head/.claude/scripts/lib/dec-write-lib.sh:642-647`; `head/.claude/scripts/validate-artifact.sh:686`
**Issue:** Unlike `new`, `decide` and `confirm`, `import` constrains nothing about status, `decided_by`, `decided_by_ref` or `transitions`. The pending-file validation at `head/.claude/scripts/lib/dec-write-lib.sh:627` runs without a base, so a self-consistent fabricated history passes. The candidate validation (`verify_and_swap`, line 415) only rejects a new operator-decided row while a live unattended signal holds (`head/.claude/scripts/validate-artifact.sh:686`), so in an interactive main checkout the row lands. Reproduced: a crafted `decisions-pending.yaml` with one decided/operator row imported with exit 0 into a fixture ledger, and `validate-artifact.sh --type decisions` then passed it (`1 decision rows`).
**Why This Matters:** The header (`head/.claude/scripts/lib/dec-write-lib.sh:12-18`) and `head/.claude/commands/decisions.md:22-28` promise that a row reaches `decided` only through the operator's `/decisions confirm`. A worktree sprint, or a prompt-injected session, writes the pending file with no review gate; `import` is the lead's routine step and will not inspect rows. Every downstream consumer (`list --not-decided-by operator`, PRD/SDD appendices, the PR body section in `render-templates.md`) then reports an agent decision as the operator's. CWE-285 (Improper Authorization), CWE-345 (Insufficient Verification of Data Authenticity).
**Required Fix:** In `op_import`, refuse (or fail the whole import on) any row whose `status` is not `open|proposed`, whose `decided_by` is not null, or whose `transitions` has more than the creation entry (plus, at most, `open -> proposed`). Mirror the rule in the validator's base comparison: a row absent from `--base-file` must be `open|proposed` with `decided_by: null`. Add a negative test next to `head/tests/unit/dec-write-lib.bats:391`.
**Reference:** CWE-285, CWE-345; `decisions.md` "a row becomes `decided` only here".

### 2. Attribution: the PRD Status line downgrades or misattributes the operator's own operations

- **HIGH** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:313-316` — `derive_attribution` drops `--answer-ref` whenever `is_unattended` (line 183) is true, and `is_unattended` includes the `prd prd-status` signal (lines 177-180); `op_confirm` only refuses on `live_run_signal` (line 509), so with a PRD whose `**Status:**` names an autonomous or unattended run the operator's interactive confirm proceeds, the cli ref is discarded with a WARN, and line 538 sets `decided_by` to `.proposed_by` ("agent") while the transition says `by: operator:decisions-command`.
**File:** `head/.claude/scripts/lib/dec-write-lib.sh:183`, `:313-316`, `:536-538`, `:572-576`, `:600-611`
**Issue:** Reproduced with `grimoires/loa/prd.md` containing `**Status:** Draft (autonomous run)` and no run state:
  - `confirm --recorded-by decisions-command --evidence cli:… --answer-ref cli:…` → exit 0, `status=decided decided_by=agent lastby=operator:decisions-command`.
  - `reject --id <decided> --recorded-by decisions-command` → exit 1 "the context is unattended; the operator rejects it interactively" (line 575), although the operator is interactive.
  - `supersede --recorded-by decisions-command` → takes the agent branch (lines 600, 606): the old row stays `decided` with `supersede_proposed_by` set instead of moving to `superseded`, and the new row's transition is `by: agent:decisions-command`. `head/.claude/commands/decisions.md:107` promises "The old row becomes `superseded`".
  - `reject` of an open/proposed row by the operator records `by: agent:decisions-command` (line 572).
  The PRD Status line is a planning-time artifact that persists in `grimoires/loa/prd.md` after the run ends, so this is the steady state of every repo that ever ran an autonomous plan, not a race.
**Why This Matters:** "Which decisions did a human actually take?" is the question the ledger exists to answer (`head/.claude/commands/decisions.md:55-56`: "That operator-kind reference is what records `decided_by: operator`"). Here the operator's confirmation is permanently recorded as the agent's, the validator accepts it (`proposed_by == decided_by == agent` is a legal row), and the appendix renderers (`list --not-decided-by operator`) list the operator's decisions as agent-taken. CWE-284 (Improper Access Control) by way of the opposite failure: a legitimate operator action is downgraded.
**Required Fix:** Split the two scopes. Keep the PRD signal as a planning-time default for `new` and `decide` only; gate the operator operations (`confirm`, `reject`, `supersede`, `context --clear`) and `derive_attribution` for those operations on `live_run_signal` alone. Add tests: PRD-status + operator confirm keeps `decided_by: operator`; PRD-status + operator reject of a decided row succeeds; PRD-status + operator supersede moves the old row to `superseded`. The existing test at `head/tests/unit/dec-write-lib.bats:354` covers only that confirm is not refused, not what it records.
**Reference:** `decisions.md` §Rules 3; `dec-write-lib.sh` header lines 12-18.

### 3. Completeness: the change depends on a tracked `grimoires/loa/decisions.yaml` it does not ship

- **HIGH** (confidence: medium) `head/tests/unit/dec-write-lib.bats:28` — `setup()` runs `empty_ledger "$REPO/grimoires/loa/decisions.yaml" …`, which `sed`s the repository's live ledger; the change adds no such file and `pr/base/` shows none, so every test in the suite fails in `setup()` with `sed: can't read …/grimoires/loa/decisions.yaml` (reproduced: 46 of 46 failed before I seeded a ledger; all passed after).
**File:** `head/tests/unit/dec-write-lib.bats:13`, `:28`, `:111`, `:121`; `head/tests/unit/grimoire-index.bats:80`; `head/tests/unit/validate-artifact.bats:630`, `:642-645`; `head/.gitignore:150`; `head/.claude/scripts/validate-gitignore-state.sh:58`
**Issue:** The suites expect a tracked ledger whose first line is `# grimoires/loa/decisions.yaml: the decision ledger` (`head/tests/unit/dec-write-lib.bats:111`), the `.gitignore` negation at `head/.gitignore:150` re-includes it, `validate-gitignore-state.sh:58` lists it as a tracked-set path, the validator test at `head/tests/unit/validate-artifact.bats:642-645` validates the live file, and the hook prints `[DECISIONS] WARNING: the decision ledger is unreadable` every session once enabled (`head/.claude/hooks/session-start/loa-decisions-surface.sh:57-58`). The writer dies with "ledger not found … (restore the tracked grimoires/loa/decisions.yaml)" (`head/.claude/scripts/lib/dec-write-lib.sh:271`). Nothing in `head.diff` creates the file. If the file already exists tracked at the base commit with that exact header, this finding drops to LOW (the suites then only need a hermetic fixture header instead of reading the live file); the PR description gives no way to tell, which is itself the gap.
**Why This Matters:** CI runs the bats suites; a red suite on merge blocks every later sprint, and a repo that enables the surface without the file gets a warning on every session start.
**Required Fix:** Add the seeded `grimoires/loa/decisions.yaml` (header comment, `schema_version: 1`, `decisions: []`) to the change, or make the fixtures hermetic (write the header in the test rather than reading the live file) and state in the PR how the live ledger is seeded.
**Reference:** sprint.md Success Criteria; `.claude/loa/CLAUDE.loa.md` "NEVER skip review/audit" presumes a green suite.

---

## Observations

### 1. Writer state machine and guards (dec-write-lib.sh)

- **MEDIUM** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:250-254` — `--file <path>` returns from `resolve_target` as `TARGET_KIND=fixture` before the CI/hook refusal (line 261) and before the worktree → pending redirect, so `--file grimoires/loa/decisions.yaml` writes the live ledger from CI, GitHub Actions or a hook. Reproduced: `CI=1 … new --file <live ledger>` exit 0 and the row landed; the implicit-target form was refused. Classify `--file` by resolved path (live, pending, fixture) and apply the guards to live and pending.
**Suggestion:** resolve `--file` to a canonical path and compare it with this checkout's and the main checkout's ledger and pending paths before granting the fixture exemption.
**Benefit:** the header's contract ("the ledger is never written from CI or a hook") holds for every caller.

- **MEDIUM** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:580-583` — `op_reject` never clears `supersede_proposed_by` on the row the rejected replacement pointed at, so after the operator rejects an agent-proposed replacement, every later agent `supersede` of that decision dies at line 601 ("a replacement is already proposed"). Reproduced: DEC-0001 stayed `decided spb=DEC-0002` with DEC-0002 `rejected`; a new agent supersede exited 1. Only the operator path (line 600) can still supersede it.
**Suggestion:** when rejecting a row with `supersedes` set, also clear the target's `supersede_proposed_by` (and allow that one field change in the validator's base comparison for a `-> rejected` write).
**Benefit:** the ledger never gets stuck in a state where an agent cannot propose again.

- **MEDIUM** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:606-608` — the operator `supersede` moves the old row to `superseded` immediately while the replacement lands only `proposed`; rejecting that replacement leaves the ledger with a superseded original and no decided successor, and the validator passes (reproduced: DEC-0003 `superseded`, DEC-0004 `rejected`, validator exit 0). `head/.claude/commands/decisions.md:107` documents this behaviour, so it is a design choice, but it loses the decision silently.
**Suggestion:** either keep the operator path symmetric with the agent path (old row stays `decided` with `supersede_proposed_by` until the replacement is confirmed) or write the replacement `decided` in the same operator write when an operator-kind `--answer-ref` is present.
**Benefit:** at every point in time exactly one row holds the live decision.

- **MEDIUM** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:647-655` — `verify_and_swap` commits the ledger (line 647) before the `--rewrite` loop (649-654) and before `rm -f -- "$from"` (655); under `set -e` a failing `mktemp` or `awk` exits with the ledger updated and the pending file still present, and a re-run allocates fresh DEC ids for the same rows. Reproduced with an unwritable `--rewrite` target: first import exit 1, ledger had 1 row, pending file kept; second import exit 0, ledger had DEC-0001 and DEC-0002 with identical content.
**Suggestion:** stage the rewrites to temp files before the swap and apply them after, or record the PEND → DEC map in the pending file (rename it to `.imported`) so a re-run is idempotent.
**Benefit:** `import` becomes safe to retry.

- **HIGH** (speculative, confidence: low) `head/.claude/scripts/lib/dec-write-lib.sh:629-655` — `import` locks only the destination (`acquire_lock "$TARGET"`, line 628) and the pending file's own lock lives under the worktree's `.run` (`lock_path` uses `PROJECT_ROOT`, line 207), so a worktree writer appending to the pending file between the snapshot at line 629 and `rm -f` at line 655 loses that row silently. Needs two writers overlapping within one import; cross-model finding DISS-001, recorded here as excluded.
**Suggestion:** take the pending file's lock too (compute it from the pending file's path under the main checkout's `.run`), or re-read and compare the pending file before deleting it.
**Benefit:** no silent loss during concurrent worktree work.

- **MEDIUM** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:359` — the operator-only operations are gated on the self-asserted flag `--recorded-by decisions-command`; `disable-model-invocation: true` hides the command from the Skill tool, but any session with Bash can run `dec-write-lib.sh confirm --recorded-by decisions-command …` and the row becomes `decided_by: operator`. This is the design stated in `head/.claude/commands/decisions.md:22-28` and the lint tests enforce only checked-in text (`head/tests/unit/user-invoked-commands.bats:80-89`), so I record it as a known limitation rather than a defect. Cross-model finding DISS-C-005.
**Suggestion:** say so explicitly in the writer header and `decisions.md` (the gate is a convention enforced by lint, not an authentication), and consider a `.run` marker that only the `/decisions` command writes interactively.
**Benefit:** nobody reads "the model cannot invoke it" as a security boundary.

### 2. Documentation and process

- **MEDIUM** (confidence: medium) `head/.claude/protocols/karpathy-principles.md:35` — the unattended-run instruction now requires `dec-write-lib.sh new` (also `head/.claude/skills/autonomous-agent/SKILL.md:66`, `head/.claude/skills/discovering-requirements/SKILL.md:75`), but the writer refuses live-ledger writes under `CI`, `GITHUB_ACTIONS` or `LOA_HOOK_CONTEXT=1` (`head/.claude/scripts/lib/dec-write-lib.sh:261`) and neither text gives the fallback. A CI-hosted autonomous run either halts on "refused: CI is set" or records nothing. Cross-model finding DISS-C-006.
**Suggestion:** document the CI path (write the pending file with `--pending --sprint N` and import in the main checkout, or fall back to the NOTES.md Decision Log pointer that the old text prescribed).
**Benefit:** the instruction is executable everywhere it is given.

- **MEDIUM** (confidence: medium) `grimoires/loa/a2a/sprint-1/reviewer.md:1-4` — FAST-GATE: the implementation report is the PR title plus "39 file(s) in scope"; it carries no `## AC Verification` walkthrough and no evidence that shellcheck or the bats suites ran (shellcheck is not installed in this sandbox, so I could not run it either). Per the review protocol a missing AC Verification section is an automatic CHANGES_REQUIRED on its own; it is recorded here because the code findings above already carry the verdict.
**Suggestion:** add the AC walkthrough (each sprint criterion with `file:line` evidence) and the lint/test command output to the report.
**Benefit:** the next reviewer can verify instead of re-deriving.

- **MEDIUM** (confidence: high) `head/.claude/scripts/validate-artifact.sh:527-728` — SIMPLICITY[shrink]: `validate_decisions` is 200 lines, most of it one jq program with 25 rules and the append-only base comparison inline. `op_confirm` (`head/.claude/scripts/lib/dec-write-lib.sh:506-558`) is 53 lines. Both exceed the 50-line ceiling without a justification comment.
**Suggestion:** move the jq program to `.claude/scripts/lib/decisions-rules.jq` (loaded with `jq -f`) and split the base comparison into its own function; split `op_confirm`'s supersede follow-through into a helper.
**Benefit:** rules become individually testable and diffable. Over-engineering pass otherwise: the ladder is respected (stdlib `jq`/`yq`, no new dependency); `net: -0 lines possible`, this is a split, not a deletion.

### 3. Low

- **LOW** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:696` — the markdown renderer passes `summary`, `voice`, `status`, `rationale` and `source` through `mc` but interpolates `.id` raw (`(\(.id))`), and line 535 echoes the raw `.summary` to stderr before cleaning. Rows are declared untrusted; a hand-edited id such as `DEC-0001 | injected | x` adds table cells to the operator preview (reproduced). Cross-model finding DISS-C-007.
**Suggestion:** route `.id` through `mc` (or the writer's id grammar) and clean the stderr echo.
**Benefit:** the preview the operator confirms from cannot be reshaped by row content.

- **LOW** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:536-538` — `confirm` without `--answer-ref` records `decided_by: agent` with a transition `by: operator:decisions-command` (pinned by `head/tests/unit/dec-write-lib.bats:186-188`): one row says the operator decided and the agent decided. `decisions.md:54-56` always passes the ref, so make it required for `confirm`.
**Suggestion:** `die` when `confirm` has no operator-kind `--answer-ref`.
**Benefit:** `decided_by` and the transition's `by` never disagree.

- **LOW** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:96-98` — `new --help` (any subcommand with `--help`) is rejected as `unknown flag --help (see --help)`, exit 2; only a bare `--help` reaches the usage text at line 739.
**Suggestion:** handle `-h|--help` inside the flag loop.
**Benefit:** the advice in the error message works.

- **LOW** (confidence: high) `head/.claude/scripts/lib/dec-write-lib.sh:697` — `list --format md` appends "Confirm with /decisions confirm." even when no listed row is `proposed` (reproduced with `--status decided`).
**Suggestion:** emit the line only when the rendered rows include a `proposed` one.
**Benefit:** the PRD/SDD appendices and PR bodies do not ask the operator to confirm already-decided rows.

- **LOW** (confidence: medium) `head/.claude/scripts/grimoire-index.sh:217` — the INDEX.md banner still lists "KF · vision · lore · handoff · observation" (observation was removed in cycle-121 and decisions is new); line 204 adds `voice` to every family's JSON record, a silent schema change for `.run/grimoire-index.json` readers.
**Suggestion:** update the banner; mention the new field in the header comment.
**Benefit:** the generated index describes itself correctly.

- **LOW** (confidence: medium) `head/tools/check-round-independence.sh:55-59` — `BLOCK_RE` uses a greedy `\[.*\]`, so two round blocks on one physical line merge into one match that is then reported as malformed. The header documents one block per line, so this is a robustness note only.
**Suggestion:** use a non-greedy scan (`grep -oE '<!--[^>]*-->'` then filter) or split on `-->` first.
**Benefit:** a transcript reflowed by an editor still checks.

---

## Rejected dissent payloads

None. The envelope's `metadata.rejected_summary` is empty and the sidecar `adversarial-rejected-review.jsonl` holds zero rows.

---

## Cross-Model Observations

Adversarial review ran on `pr/head.diff` with two voices (primary `gpt-5.5-pro`, companion `claude-headless`, both succeeded; `grimoires/loa/a2a/sprint-1/adversarial-review.json`). Triage of its eight findings:

| Finding | Voice | Disposition |
|---|---|---|
| DISS-001 import race loses a concurrently appended pending row | gpt-5.5-pro | Plausible but needs overlapping writers; recorded as speculative HIGH under Observations (excluded) |
| DISS-C-001 PRD status misattributes operator confirm/reject/supersede | claude-headless | Reproduced; counted as Changes Required §2 |
| DISS-C-002 import mints decided/operator rows | claude-headless | Reproduced; counted as Changes Required §1 |
| DISS-C-003 `--file` bypasses CI/hook guard | claude-headless | Reproduced; Observations MEDIUM |
| DISS-C-004 duplicate rows after a failed `--rewrite` | claude-headless | Reproduced; Observations MEDIUM |
| DISS-C-005 self-asserted `--recorded-by` gate | claude-headless | Design limitation, documented; Observations MEDIUM |
| DISS-C-006 CI unattended runs cannot record decisions | claude-headless | Documentation gap; Observations MEDIUM |
| DISS-C-007 raw `.id` / stderr summary in renderer | claude-headless | Reproduced; Observations LOW |

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | Seeded tracked ledger (or hermetic fixtures); import row constraints; operator-scope attribution fix |

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

Sprint success criterion: "review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict".

| Criterion | Status | Notes |
|-----------|--------|-------|
| Ledger rows reach `decided` only through `/decisions confirm` | Fail | `import` bypass (Changes Required §1) |
| Attribution derived correctly for the operator's own operations | Fail | PRD Status signal (Changes Required §2) |
| New and modified bats suites pass on the change as shipped | Fail | `setup()` reads a ledger the change does not add (Changes Required §3); 152/153 pass once a ledger exists |
| Writer is append-only, atomic, locked; hostile strings round-trip | Pass | Verified by `dec-write-lib.bats` (46 tests) in the merged tree |
| SessionStart surface default-off, L6-fenced, untrusted rows neutralised | Pass | `loa-decisions-surface.bats` (8 tests) pass; negative fixture covers fence-closing, role switch, control bytes |
| `rounds` pacing checker | Pass | 13 tests pass; worked example in REFERENCE.md validates |
| Operator-only command allowlist and `disable-model-invocation` flags | Pass | 14 tests pass; allowlist and flags consistent; live harness test skips without `claude` |
| Validator `--type decisions`, PRD tag-to-row rule, SDD DEC column, sprint Deferred WARN | Pass | 16 new validator tests pass |
| `.gitignore` negation and `validate-gitignore-state.sh` negation-aware match | Pass | Negation at `.gitignore:150`; `is_ignored_match` parses `!` patterns |
| README/AGENTS.md command count 49 → 50 and checksum | Pass | Checksum matches `sha256sum AGENTS.md` |
| `## AC Verification` in the implementation report | Fail | Report is title-only |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [x] Input validation and sanitization present (san1, yq `env()`, jq `--arg`, L6 fence; gap: raw `.id` in md renderer, LOW)
- [ ] Authentication/authorization correct — `import` mints operator-decided rows (HIGH); PRD signal downgrades operator actions (HIGH); `--file` bypasses CI/hook guard (MEDIUM)
- [x] No SQL/XSS injection vulnerabilities (shell: all values reach yq via `env()` and jq via `--arg`; artifact paths rejected on `..` and must resolve inside the project)
- [x] Dependencies secure (jq, Mike Farah yq v4, flock; preflight fails closed on version)
- [x] Error messages don't leak sensitive data

---

## Code Quality Summary

**Strengths:**
- Temp-copy, verify (parse, ids, row count, untouched rows JSON-equal, validator with base), then rename: a failed write provably leaves the ledger byte-identical, and the test proves it.
- Values never enter a yq expression: `env(ROW)` plus `--arg`, with the double-quoted style forced on every string; the hostile-string corpus (YAML tags, anchors, C1 controls, U+2028) round-trips.
- The SessionStart surface reads only id/status/summary, strips controls and angle brackets, caps length, and refuses to print without the L6 fence.
- Lint tests pin the operator-only contract textually across commands and skills, with fixture proofs for each check.

**Areas for Improvement:**
- Two unattended scopes (planning-time default vs live run) are conflated in `is_unattended`; the operator operations need the live scope only.
- `import` trusts its input; it needs the same row-shape constraints the other ops enforce.
- `validate_decisions` should be split out of a 200-line function.
- The implementation report needs an AC walkthrough and lint/test evidence.

---

## Next Steps

1. Address the three Changes Required findings (import row constraints, operator-scope attribution, seeded ledger or hermetic fixtures) and add the named regression tests.
2. Run `bats tests/unit/dec-write-lib.bats tests/unit/validate-artifact.bats tests/unit/grimoire-index.bats tests/unit/loa-decisions-surface.bats tests/unit/check-round-independence.bats tests/unit/user-invoked-commands.bats` and shellcheck on the three new scripts; paste the output into the report.
3. Update the report in `grimoires/loa/a2a/sprint-1/reviewer.md` with an `## AC Verification` section.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":8,"low":6},"excluded":1,"sprint_id":"sprint-1","ts":"2026-10-22T12:55:00Z"} -->
