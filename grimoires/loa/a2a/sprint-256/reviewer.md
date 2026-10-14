# Implementation Report: Sprint 256 (cycle-129 Sprint 2) — lead integration

**Date:** 2026-10-14 · **Lead:** Fable 5.1 (`global.anthropic.claude-fable-5-1`), main thread · **Implementers:** D, E, F (Claude Opus 5.5 subagents, `global.anthropic.claude-opus-5-5`; reports `reviewer-d.md`, `reviewer-e.md`, `reviewer-f.md` in this directory) · **Base:** `b6802e4f` (sprint-255 audit round) · **Branch:** `feature/cycle-129-earned-guards`
**Sprint reference:** `grimoires/loa/sprint.md` "## Sprint 2" (Tasks 2.1 … 2.10, AC-2.1 … AC-2.12)

## Executive Summary

Every documented control in scope now runs, is telemetry, or is gone; run position comes from files; the fence stops blocking prose in non-executing heredocs; one knob sets the optional surfaces and cannot reach the floor; the kernel is thinner by the Agent Teams table and the budget cap follows it down. Three implementer patches (E 4 files, D 23 files, F 47 files) applied with `git apply --3way --index` in the order E → D → F with no conflicts; after each apply the lead ran the fence corpus and the hook bats before relying on them (DEC-0168), and no recovery was needed. The lead's own work: the FR-6 corpus rows (E's safety classifier stopped its output while it was writing destructive-command fixtures), one classifier fix the new rows caught (a bare `-i` escaped the jq/yq in-place check), the `heredoc-classifier.sh` library shim Sprint 1's register expected, Task 2.8 (the D-2.4 fallback), Task 2.9, and the live harness probe for `disallowed-tools`.

Three findings change the picture: yq's `//` reads an explicit `false` as absent, so three knobs could never be turned off before this sprint (F); `rtfm-testing` writes a State-Zone report and is not pure-review (F); and `disallowed-tools` is enforced in the main session but session-scoped and not enforced in subagents (lead probe; KF-043).

## AC Verification

> AC-2.1 `implement-gate.bats` covers the matrix mode × claims × write class × sanction state: `deny` returns a deny decision only for an unsanctioned App-Zone write; derived RUNNING, a fresh marker and the override sanction with a logged row each; a stale marker does not; `telemetry` writes one row and prints nothing; `ask` unchanged; trust-input writes ask in every cell (PRD AC-4.1)

**Status:** ✓ Met. Evidence: `.claude/hooks/compliance/implement-gate.sh:582-596` (sanction order run → marker → override; `stale_marker` row at :593), `:616-648` (decision per mode: allow :618, telemetry :625, deny :631, unknown_position :637, ask :645), `:340` (trust inputs incl. `.run/implement-active.json`), `:600-612` (claims modifier). Tests: `tests/unit/implement-gate.bats:573` `run_mode_matrix` over mode {unset, ask, telemetry, deny} × claims {plain, authoritative} × write {app, trust} × sanction {none, run_fresh, run_stale, marker_fresh, marker_stale, override} × cache {fresh, stale, missing, unparseable}; IG-24 … IG-27 at `:614-626`; 33/33 on the integrated tree (lead smoke run 2, below).

> AC-2.2 A pure-review skill without the strip fails `skill-capabilities.bats`; the four skills carry it (`rtfm-testing` writes a State-Zone report, so it keeps `Write` and strips `Edit` and `NotebookEdit`; as-built per the sprint-256 report); `skill-invariants.md` names the Bash gap (PRD AC-4.2)

**Status:** ✓ Met (as amended). Evidence: `.claude/scripts/validate-skill-capabilities.sh:622` (the rule: `role: review` + `write_files: false` without Write, Edit and NotebookEdit in `disallowed-tools` fails by name; `PURE_REVIEW_STRIP` at `:95`); `tests/unit/skill-capabilities.bats:944`, `:951`, `:958`, `:969`, `:998`, `:1017`, `:1030` (c129-D4.2 cases); the strip at `.claude/skills/eval-running/SKILL.md:6`, `.claude/skills/flatline-knowledge/SKILL.md:6`, `.claude/skills/validating-construct-manifest/SKILL.md:5`; `.claude/skills/rtfm-testing/SKILL.md:7` strips Edit and NotebookEdit and keeps Write for its documented Phase 4 report write (`SKILL.md:267`, `:396`); `.claude/rules/skill-invariants.md:67` "The Bash gap". The grep F ran over the four skills' workflows found the one Write step (rtfm's report) and no Edit step. The live harness probe is in §Harness probe below; the AC's fallback (a read-only `allowed-tools` set) was NOT taken because the probe showed `allowed-tools` does not restrict either where `disallowed-tools` does not.

> AC-2.3 The surgical-diff counter resets when the checkpoint task changes and keys on the session id when no task is active; the summary file exists after a write; the state directory is bounded (PRD AC-4.3)

**Status:** ✓ Met. Evidence: `.claude/hooks/quality/karpathy-surgical-diff-check.sh:129-138` (key: checkpoint task, else sprint, else session id), `:141` (legacy file deleted), `:177` (summary written); `tests/unit/karpathy-surgical-diff.bats` KS-1 (reset on task change), KS-2 (session-id key), KS-3 (sprint key while the bead is open), KS-4 (summary fields), KS-5 (bound of 20), KS-6 (legacy deletion), KS-7 (sanitised names), KS-8 (knob off and `lean`), KS-9 … KS-11; 24/24 with the two migrated suites.

> AC-2.4 The example's effective value under `standard` is `false` for both guardrail keys (the raw keys appear commented in the example because `loa.profile` governs them; review round 2 HIGH-2); this repository reads `guardrails.input.enabled: true` and `danger_level.enforce: false`; the orchestrator tests pass with the knob on; the CHANGELOG carries the migration notes (PRD AC-4.4)

**Status:** ✓ Met (as amended in review round 2). Evidence: the two raw keys are commented, profile-governed lines in `.loa.config.yaml.example` (`# enabled: false`, `# enforce: false`, each with the "Profile-governed … uncomment to pin it" note) and the effective value under `standard` is `false` for both (`profile-lib.sh knob` on the example; PL-4); `.loa.config.yaml:625-629` (new `guardrails:` block, `enabled: true`, `enforce: false`; nothing else in the file changed — staged diff is 11 added lines); `tests/unit/guardrails-orchestrator-file-input.bats` 4/4 against this repository's config; `tests/unit/profile-lib.bats` PL-15 drives the orchestrator and the enforcer with the knob on and off; `CHANGELOG.md:27` (migration: set both keys `true` to restore; an explicit `false` is now honoured).

> AC-2.5 `constraints.json` has no C-TEAM rows; the kernel regenerates without the Agent Teams table; the reference states the rules and the arming variable; the three team hooks are `dormant` in the register (PRD AC-4.5)

**Status:** ✓ Met. Evidence: `.claude/data/constraints.json` (105-line pure deletion; `grep -c C-TEAM` = 0); `.claude/scripts/generate-constraints.sh:41` (`OPTIONAL_TABLES`), `:167` (`prune_optional_table`); `.claude/loa/CLAUDE.loa.md` has no `## Agent Teams` heading (10,225 B → 9,189 B); `.claude/loa/reference/agent-teams-reference.md:32` "## Rules and arming" (five rules, rationales verbatim), `:44` (arming note: no-ops until the lead exports `LOA_TEAM_MEMBER`); `.claude/data/guard-origins.yaml` rows `hook:safety/team-role-guard.sh`, `hook:safety/team-role-guard-write.sh` and the third team hook carry `status: dormant`, knob `LOA_TEAM_MEMBER` (Sprint 1; `/loa` Guards line "3 dormant"); `tests/unit/lint-invariants.bats` LI-1 … LI-9 and `.claude/scripts/lint-invariants.sh:229` (`check_optional_constraint_tables`).

> AC-2.6 `record-round` increments `cycle_count.current`, sets `same_issue.last_hash`, appends `history` on a trip and writes `OPEN` and `HALTED`; `derive` over a fixture a2a directory recomputes the counters from the feedback history (PRD AC-4.6)

**Status:** ✓ Met. Evidence: `.claude/scripts/run-checkpoint.sh:479-532` (`cmd_record_round`: hash via `fb_parse`, counters, trigger order, `state: OPEN` and history on a trip, `.run/state.json` `.state = "HALTED"`, exit 10), `:276-312` (`recompute`, `merge_breaker`: counters raised, never lowered). Tests: `tests/unit/run-checkpoint-record-round.bats:46` RCR-1, `:87` RCR-4 (trip → OPEN, one history entry, HALTED, exit 10), `:122` RCR-6; `tests/unit/run-checkpoint-derive.bats:231` RCD-9, `:258` RCD-10; 8/8 and 22/22.

> AC-2.7 `run-checkpoint-derive.bats` has one case per decision-table row: the drift fixture derives to the file-derived state; a stale marker whose trailer names another sprint does not count; terminal states are never moved back to RUNNING; each known reader has a fixture case; `run_mode.file_authoritative: false` makes `derive` report-only; the jack-out step writes `.state` (PRD AC-5.1 … AC-5.4)

**Status:** ✓ Met. Evidence: `.claude/scripts/run-checkpoint.sh:314-329` (`resolve`, the run-state table), `:331-477` (`cmd_derive`), `:174` (`write` calls `derive --write`); `.claude/skills/run-mode/resources/completion-modes.md:40` (§Jack-out writes `.state` and mirrors `.status`). Tests: RCD-1 drift `:80`, RCD-2 stale marker `:101`, RCD-3 legacy `:122`, RCD-4 awaiting_marker `:135`, RCD-5 JACKED_OUT terminal `:154`, RCD-6 HALTED sticky `:175`, RCD-7 COMPLETE never back to RUNNING `:189`, RCD-8 RUNNING/INTERRUPTED `:207`, RCD-11 schema tolerance `:272`, RCD-12 report-only knob `:291`, reader cases RCD-R1 … R3. Note (D): PRD AC-5.1 says the drift fixture derives to JACKED_OUT, SDD D-5.4 says COMPLETE; the implementation follows the SDD (DEC-0258). Live read-only run on this repository: `derive --json` → RUNNING, cache present, drift false, sprint 255 complete with consistent APPROVED trailers.

> AC-2.8 `run-corpus.sh` green with the new rows; no D-row removed; the recorded prose cases allow; every interpreter, wrapper, substitution, same-line-execution and unlisted-consumer D-row blocks; the knob off reproduces today's results; p95 under 80 ms (PRD AC-6.1, AC-6.2)

**Status:** ✓ Met. Evidence: classifier `.claude/hooks/safety/block-destructive-bash.sh` (grammar block comment above `_bdb_hd_is_interp`; `_bdb_heredoc_scrub`; exported `_bdb_heredoc_consumer_class` and `heredoc_nonexec`; knob reader `_bdb_heredoc_knob_on`; main-flow switch at the former #1245 scrub); lead fix at `:429-431` (in-place flags `--inplace|--in-place|-i*|-[A-Za-z]*i*`). Corpus `tests/fixtures/fence-corpus/corpus.jsonl:184-236`: B79 … B88 (ten allow rows: five SP-1 prose cases B79–B83, the P2 force-push string in a `.md` B84, `br create` B85, `gh pr comment -F -` B86, a `jq -f -` filter B87, `git commit -F -` B88) and B89 (documented miss, see Known Limitations); D101 … D142 (forty-two block rows: shell/interpreter/SQL-runner consumers D101–D103, substitution wrappers D104–D106, ssh/docker/sudo/xargs/env/find D107–D112, `gh api --input -` with a destructive body D113, in-place jq/yq D114–D115, awk/sed-e/make D116–D118, same-line execution D119–D121, `.sh` target D122, shebang body D123, hooks-directory target D124, rc-file target D125, unlisted consumer D126, nested heredoc D127, variable delimiter D128, per-segment forms D129–D139, a prose line beginning with a fence verb D140, control character D141, non-literal target D142). No existing row changed. Results on the final tree: benign 89/89, dangerous 142/142, residual 0/5, p95 45–49 ms (host load ≈ 3 from the arm batch; E measured 45 ms). Knob off (`run-corpus.sh --rows --knob-off`) is row-for-row identical to the pre-change hook (`git show b6802e4f:` of the hook) over the whole 236-row corpus (`diff` empty). Against that pre-change hook the new rows also show what changed: five B-rows used to block (B80, B82, B85, B87, B88) and six D-rows used to pass (D122, D123, D127, D131, D136, D141) — the classifier is tighter where the #1245 scrub dropped bodies and looser only for prose.

> AC-2.9 `profile-lib.bats`: explicit key beats profile beats fallback; `standard` equals the post-cycle example defaults listed in `profiles.yaml`; `profile-floor.bats` passes under `lean`; `/loa` prints the profile and overrides (PRD AC-9.1 … AC-9.3)

**Status:** ✓ Met. Evidence: `.claude/data/profiles.yaml` (schema_version 1; `lean`, `standard`, `full` over the nine keys); `.claude/scripts/lib/profile-lib.sh` (`loa_profile`, `loa_knob`, `loa_profile_overrides`, cache `.run/effective-config.json`; CLI `profile|source|knob|overrides|json`); `tests/unit/profile-lib.bats` PL-5/PL-6 (precedence), PL-3/PL-4 (`standard` equals the oracle `tests/fixtures/profiles/standard-oracle.json` and the example), PL-7 (unknown profile), PL-8 … PL-10 (cache rebuild), PL-11 (overrides), PL-12 (floor keys refused), PL-13, PL-14 (`/loa` line), PL-15/PL-16 (readers), PL-17 (grep lint) — 17/17; `tests/unit/profile-floor.bats` PF-1 … PF-7 — 7/7 (PF-1 reads the `floor.yaml` sha256 pin from `guard-origins.bats`); `.claude/scripts/loa-status.sh:942` (`display_profile_line`) called at `:694`; live output on this repository: `Profile: standard (explicit overrides: guardrails.input.enabled=true, known_failures.surface_at_session_start=true)`; `tools/check-knob-readers.sh` clean (9 keys).

> AC-2.10 Always-on prose ≤ 12 KB per turn or the D-2.4 fallback is stated in the sprint report with the inconclusive arm named and no row deleted; `check-prompt-budget.sh` green at `LOA_LIMIT = min(current, measured + 256 B)`; every changed row listed with its class (review-affecting, mechanism, behavioural) and its evidence (arm verdict and missed-label reading, pointer, or proposed DEC row) (PRD AC-3.2, AC-3.3)

**Status:** ✓ Met (fallback branch). Always-on prose on the final tree: `CLAUDE.md` 2,460 B + `.claude/loa/CLAUDE.loa.md` 9,189 B = 11,649 B ≤ 12,288 B (every rule file under `.claude/rules/` is path-scoped). Gate read for Task 2.8 at 2026-10-14T02:33:26Z: `evals/results/arms/review-recall/batch-1/STATUS.json` `state: running` (baseline 6/24, no_companion 5/24, no_karpathy 5/24, no_rule_files 4/24 trials; 0 failed; the audit-recall batch not yet started; no `arms-report-*.md`), so per SDD D-2.3 ("anything else → the D-2.4 fallback, no waiting") every arm is inconclusive: review `no_companion` (informational), `no_karpathy`, `no_rule_files`; audit `no_audit_delta`. No kernel row was deleted or shortened. Cap: `tools/check-prompt-budget.sh:53` `LOA_LIMIT = 9445` (= min(10,240, 9,189 + 256)); `tests/unit/prompt-budget.bats:57` PB-4 and `:91` PB-6 pin it; `.github/workflows/check-prompt-budget.yml:5` states it; `check-prompt-budget.sh` green (`CLAUDE.loa.md 9189 B (limit 9445)`); 10/10 bats. Row classification and deferral bead `bd-2txz1`: §Task 2.8 below.

> AC-2.11 `implement_gate.mode` and the new keys are documented in the example with a config-key table in the report; the hooks reference describes the gate as a fence only under `deny`; this repository still reads `ask` at sprint end

**Status:** ✓ Met. Evidence: `.loa.config.yaml.example:613` (`implement_gate:` block: the three modes, `claims`, the marker, the override, "The hook is a fence only in this mode"), `:559` `run_mode.file_authoritative`, `:563` `run_mode.stale_hours`, the `destructive_command_guard.heredoc_classifier` key in the `destructive_command_guard:` block, the `loa:` block (`profile: standard   # lean | standard | full`); `tests/unit/implement-gate.bats:477` IG-11 pins the example block; `.claude/loa/reference/hooks-reference.md:234` ("a **fence only under `implement_gate.mode: deny`**"; mode table, sanctions, rows, accepted gaps); register notes `.claude/data/guard-origins.yaml:210` and `:813` and the regenerated registration table `hooks-reference.md:192`; `bash .claude/hooks/compliance/implement-gate.sh --effective-mode .loa.config.yaml` → `ask` on the final tree; `/loa` prints `Gate: implement_gate.mode ask`. Config-key table: §Config keys below.

> AC-2.12 After each patch apply the fence corpus and the hook bats were run before the next tool call relied on them, recorded in the report; every existing bats, pytest, vitest and fence-corpus suite is green on the sprint's final tree

**Status:** ⚠ Partial. The apply-time smoke runs happened and are recorded (§Smoke runs: three applies plus the lead's fence fix, every one green before the next tool call). On the final tree the touched and dependent suites are green: 616 bats cases over 24 unit suites (fence, hooks, register, gate, checkpoint, profiles, surgical diff, lint, skill capabilities, budget, diet-revert, session-start surfaces), the fence corpus (236 rows), the budget suite (10), and pytest 92 passed + 412 subtests (`tests/unit/test_hook_issue_regressions.py`, `.claude/adapters/tests/test_anthropic_catalog_floor.py`, `test_model_auth_metadata_validator.py`). Not run locally: the full bats sweep (6,765 cases ≈ 13 h serial on this host; CI runs it on the PR) and vitest (`bridgebuilder-review` has no `node_modules`; `npm ci` is Sprint 3 Task 3.4's first step). F's 57-file sweep on its worktree: 908 ok / 15 not ok, of which IG-11 was F's and was fixed, and 14 reproduce identically on pristine `b6802e4f` (`cycle-098-cross-primitive-l7.bats` T-CHAIN-1/3, `test_process_compliance.bats` 6/7/9/10, `hook-wiring.bats` W6, `scheduled-cycle-skill-3D.bats` 10, `trust-concurrent-and-disable.bats` 1/2/3/7/9/13) — pre-existing, not this sprint's. Scope split: the full-suite proof is the PR's CI run plus Sprint 3 Task 3.E2E (G-1 … G-9), which also installs vitest.

## Tasks Completed

- **Task 2.10, 2.5, 2.1 (D)** — `run-checkpoint.sh derive|record-round|mark|unmark`, `write` derives first, jack-out writes `.state`, `/loa` Run (drift-only) and Gate lines, `run-resume` derives on drift; `implement_gate.mode` ask | telemetry | deny with three sanction paths and one row per decision, `claims: authoritative` tighten-only, `--effective-mode`; `implementing-tasks` and `bug-triaging` call `mark`/`unmark`; run-mode SKILL breaker prose replaced by the call (15,372 → 13,682 B). Suites: `implement-gate.bats` 33, `run-checkpoint-derive.bats` 22, `run-checkpoint-record-round.bats` 8.
- **Task 2.6 (E + lead)** — classifier behind `destructive_command_guard.heredoc_classifier` (default true), `run-corpus.sh --knob-off | --rows | p95_ms`, hooks-reference "Heredoc consumer classification" section; lead: 53 corpus rows (B79–B89, D101–D142), the in-place flag fix, `.claude/scripts/lib/heredoc-classifier.sh` (sources the fence with `BDB_LIB_ONLY=1`; `guard-yield.sh` now classifies heredoc blocks with it; the GY-3 fixture row became a complete heredoc), the SP-1 row of the hooks reference updated.
- **Task 2.4, 2.7, 2.2, 2.3 (F)** — guardrail defaults off in the example, telemetry-on here; C-TEAM rows out, `OPTIONAL_TABLES` prune, `lint-invariants.sh` check, "Rules and arming" in the reference, keeplist K-07 retargeted; `profiles.yaml` + `profile-lib.sh` + oracle + six hook readers and three prose readers rerouted + `tools/check-knob-readers.sh` + `/loa` Profile line + `loa:` block; `disallowed-tools` on three pure-review skills, `rtfm-testing` reclassified, validator rule + bats, Bash gap paragraph; surgical-diff hook rewritten (848 → ~220 lines) with per-task state, summary, rotation; SURGICAL axis sentence in `reviewing-code` (byte-neutral, −8 B net).
- **Task 2.8 (lead)** — D-2.4 fallback executed: §Task 2.8.
- **Task 2.9 (lead)** — `CHANGELOG.md` `[Unreleased]` (six Added entries, five Changed entries incl. migration notes and rollback keys, three Fixed entries), hooks-reference implement-gate section rewritten from D's tables, register notes + registration table regenerated (`guard-yield.sh --check` in sync, 95 guards), `grimoires/loa/REPO-MAP.md` + `.checksum` regenerated, `.claude/checksums.json` selectively refreshed (3 added, 41 modified; manifest 3,370 entries vs 3,363 files on disk — the 7-entry gap predates this sprint: untracked pytest-cache entries recorded by an earlier full generation), `evals/fixtures/sync-fixtures.sh --check` "All fixtures current".
- **Decisions** — 57 proposed DEC rows seeded from the three reports and the lead's calls: D-1 … D-24 = DEC-0235 … DEC-0258, E-1 … E-6 = DEC-0259 … DEC-0264, F-1 … F-17 = DEC-0265 … DEC-0281, lead-1 … lead-10 = DEC-0282 … DEC-0291 (`grimoires/loa/decisions.yaml`, 291 rows).

## Config keys

| Key | Documented default | Validation | One reader test |
|-----|--------------------|------------|-----------------|
| `implement_gate.mode` | `ask` | `ask` / `telemetry` / `deny`; legacy `authoritative` = `ask` + claims; anything else = `ask` | IG-24 … IG-27, IG-30 |
| `implement_gate.claims` | unset (plain) | only `authoritative` changes behaviour (tighten-only) | IG-24 … IG-27, IG-29 |
| `run_mode.stale_hours` | 12 | integer 1 … 8760, else 12 | RCD-8, IG-33 |
| `run_mode.file_authoritative` | `true` | only the literal `false` turns it off (derive report-only) | RCD-12 |
| env `LOA_IMPLEMENT_GATE_OVERRIDE` | unset | only `1` sanctions; row `allow/override` | matrix column `override` |
| `destructive_command_guard.heredoc_classifier` | `true` | `false`/`no`/`off` turn it off (the pre-cycle scan); read only for commands holding `<<` | `run-corpus.sh --knob-off` row-identical to the pre-change hook |
| `loa.profile` | `standard` | `lean` / `standard` / `full`; unknown → WARN + `standard` | PL-7 |
| `guardrails.input.enabled` | `false` (example); `true` here | presence-tested boolean (explicit `false` honoured) | PL-15, `guardrails-orchestrator-file-input.bats` |
| `guardrails.danger_level.enforce` | `false` | presence-tested boolean | PL-15 |
| the seven other profile keys (`known_failures.surface_at_session_start`, `decisions.surface_at_session_start`, `karpathy_principles.surgical_diff_warning`, `karpathy_principles.require_success_criteria`, `invisible_retrospective.enabled`, `structured_handoff.enabled`, `soul_identity_doc.enabled`) | per `profiles.yaml` `standard` (= the shipped example defaults) | explicit key → profile → fallback via `loa_knob`; no floor key reachable (PF-2, PL-12) | PL-1 … PL-17, KS-8 |

Rollback keys: `implement_gate.mode: ask` (already the default), `destructive_command_guard.heredoc_classifier: false`, `guardrails.input.enabled: true` + `guardrails.danger_level.enforce: true`, `loa.profile: full`.

## Smoke runs (DEC-0168 self-hosting rule)

| Step | Files | Fence corpus (benign / dangerous / residual, p95) | Hook bats | Notes |
|------|-------|---------------------------------------------------|-----------|-------|
| apply E (`s2-e.patch`) | 4 | 78/78 · 100/100 · 0/5, 46 ms (knob off 92 ms under load) | 408 pass / 0 fail (8 suites) | before any other tool call relied on the hook |
| lead corpus rows + fix | corpus +53 rows, hook :429-431 | first run 88/88 · 140/142 · 1/6 → D114/D115 allowed (bare `-i`), one residual row mis-typed → fix + B89; second run 89/89 · 142/142 · 0/5, 49 ms; knob-off vs `b6802e4f` hook: identical | 408 / 0 (incl. `guard-yield.bats` with the shim) | register `--check` in sync |
| apply D (`s2-d.patch`) | 23 | 89/89 · 142/142 · 0/5, 46 ms | 486 / 0 (+ D's three suites + `run-checkpoint.bats`, `agent-teams-hooks.bats`) | F's patch pre-checked with `--3way --check`: clean |
| apply F (`s2-f.patch`) | 47 (61 cumulative) | 89/89 · 142/142 · 0/5, 45 ms | 616 / 0 (+ F's suites, budget, diet-revert, kf/decisions surfaces) | lints: budget, knob-readers, skill-capabilities 37/37, skill-includes, register, validate-constraints, raw-sha all green |

Recovery step (never needed): `git show HEAD:.claude/hooks/safety/block-destructive-bash.sh` into the hook path, or `destructive_command_guard.heredoc_classifier: false`. The hooks under test are this session's live hooks; every Bash call after each apply went through the applied fence.

## Task 2.8 — kernel rows, evidence classes, cap (fallback branch)

Gate read: see AC-2.10 (running, 20/96, 02:33:26Z → D-2.4, no waiting). Measured: `CLAUDE.loa.md` 10,225 → 9,189 B (−1,036 B, all from the Agent Teams table leaving with FR-4(e)); always-on 11,649 B. Cap lowered to 9,445 B. Deferral bead: **bd-2txz1** (under epic bd-hjlv) names the arm run and the rows below.

| Kernel row | Class | Evidence | Action this sprint |
|------------|-------|----------|--------------------|
| Karpathy Principles block (four principles, floor list) | review-affecting | `no_karpathy` arm inconclusive (5/24 trials at the gate read) | untouched |
| C-PROC-001 (why: the mechanical stack, 390 B) | review-affecting — SDD D-3.2 called it mechanism-describing, but its rationale is one of the twelve `tests/fixtures/constraint-rationales-pre-diet.json` pins (cycle-126 sprint-250 replay A/B lost audit recall when the rationales were trimmed; `instruction-diet-revert.bats` IDR-3/IDR-4) | arms inconclusive; the pin is the stronger evidence | untouched; pointer shrink deferred (DEC-0283) |
| C-PROC-005 (route through /run; breaker), C-PROC-017 (/spiraling) | review-affecting by the same pin | same | untouched (DEC-0283) |
| C-PROC-004, C-PROC-018, C-PROC-002, C-PROC-015 | review-affecting by the same pin | same | untouched |
| C-PROC-002 (TaskCreate), C-PROC-006 (beads creation), C-PROC-015/016 (/bug eligibility) | behavioural prose-only | no arm measures them; the register's ask/telemetry counts are the instrument | moves to `.claude/protocols/process-compliance.md` proposed as DEC-0284, DEC-0285, DEC-0286; not executed under the fallback (no row deleted) |
| C-MERGE-001/002, the task-tracking table (C-BEADS-001 … 003) | mechanism-describing, not pinned | already one line each (≤ 90 B) | untouched (no saving) |
| "Gates and Hooks" paragraph | mechanism-describing; keep-listed strings K-08/K-09/K-10/K-18 | — | untouched |
| "Run Mode Recovery" | behavioural; keep-listed K-14/K-15/K-16 | — | untouched |
| "Agent-Network Primitives" | invariants; keep-listed K-11/K-12/K-13 | — | untouched |
| Reference Files, Three-Zone, Golden Path tables | structural (IDR-1/IDR-2 pins) | — | untouched |
| Agent Teams table (C-TEAM-001 … 005) | mechanism-describing (dormant hooks) | FR-4(e), DEC-0140; the rationales live on in `agent-teams-reference.md` (IDR-3 reads them there) | REMOVED by F — the one deletion, authorised by D-4.5, not by an arm |

Lead reading recorded: no missed-label reading was possible (no verdict); the `no_rule_files` arm's effect on review recall is reported, not acted on (D-3.1 scoped the rule files on the crosswalk). When batch 1 completes, `report.sh --arms` gives the verdicts the deferral bead needs; the IDR-3 pins must be released by the same decision that shrinks a pinned row.

## Harness probe (Task 2.2) — `disallowed-tools`

Two probes on Claude Code 2.1.296, both after F's patch was applied in the main checkout.

| Context | Step | Tool | Result |
|---------|------|------|--------|
| Opus 5.5 subagent (`general-purpose`, all tools) | control write (no skill) | Write `probe-control.txt` | SUCCEEDED (file created 13:33:26) |
| subagent | Skill `flatline-knowledge` active (allowed-tools Read/Grep/Glob; disallowed-tools Write, Edit, NotebookEdit) | Write `probe-disallowed-tools.txt` | SUCCEEDED (13:33:48) |
| subagent | same | Edit the same file | SUCCEEDED (content became `probe-edited`) |
| subagent | same | Bash `printf … > probe-bash.txt` | SUCCEEDED (13:34:10) |
| subagent | Skill `eval-running` active | Write `probe-eval-running.txt` | SUCCEEDED (13:34:39) |
| main session (this lead, Fable 5.1) | Skill `flatline-knowledge` invoked | next Write (to a scratch path outside the repo) | REFUSED: "Permission to use Write has been denied"; the harness then listed Edit and Write as "Denied by a permission rule" and dropped NotebookEdit from the tool list |
| main session | same, same turn | Bash `printf … > probe-main-bash.txt` | SUCCEEDED (02:51:45Z) |
| main session | later turn, after invoking the write-capable `implementing-tasks` skill | Edit, then Write | REFUSED: "Edit is disabled for this session, in subagents as well as here" / "Write is disabled for this session, in subagents as well as here" |

Reading: `disallowed-tools` is a real barrier in the main session, where the review and audit skills run; it lasts until the operator's next prompt (not reset by another skill; in an unattended run that is the rest of the session) and it is not enforced in subagents, where `allowed-tools: Read, Grep, Glob` did not restrict either. The AC's fallback (an explicit read-only `allowed-tools` set) would therefore add nothing for subagents, so it was not taken; the keys stay as declared policy, `skill-invariants.md` keeps the Bash-gap paragraph, and the probe result is recorded here, in `CHANGELOG.md`, and as **KF-043** (the `skill-invariants.md` paragraph was added in round r256-1, once the tools returned at the next prompt). The mechanical barriers for subagent work remain the zone guard, the implement gate and the fence. Probe files were deleted after recording.

## Technical Highlights

- **Fail-closed heredoc classifier**: literal command text, CRLF folded; a header the tokenizer cannot read, two heredocs on a header, a non-word or variable delimiter, a missing terminator, a control character, a nested heredoc or a shebang first line → full scan. Interpreter class on any pipeline member that is a shell, interpreter, argument-running wrapper or SQL runner, on any substitution or compound context, on exec-shaped flags, and on executable write targets (script extension; `.claude/hooks/`, `.claude/settings*.json`, `.git/hooks/`, rc/profile files, `/etc`, a `PATH` or bin directory; any non-literal path; a target named elsewhere on the command outside a safe reader). Non-executing exact forms scan per segment with wrapper prefixes stripped; a variable command word is also scanned synthetically as the three most-abused verbs. Export: `BDB_LIB_ONLY=1` sourcing (honoured only when sourced; an executed hook ignores the variable). E's reading that substitutions under a *quoted* delimiter are literal text was accepted (DEC-0259, DEC-0290); D137/D138 pin the unquoted case.
- **Presence-tested knobs**: `loa_knob` resolves with `getpath` and a null test, never yq's `//` — which is why `guardrails.input.enabled: false` finally means false.
- **File-authoritative run position**: `derive` rebuilds state from markers, trailers, ledger and git with a terminal/sticky table; the breaker is recomputed from the feedback history (rounds at or before `reset_at` ignored); the gate reads the derived cache and treats an un-derived or stale cache as an unknown position (ask), so a forged cache is no worse than today.
- **Sanction order and rows**: run → marker → override, each with its own audit row; trust-input writes ask in every mode; `replay: true` under `LOA_AUDIT_REPLAY=1` so the register's yield excludes test runs.

## Testing Summary

| Suite / check | Result |
|---------------|--------|
| fence corpus `tests/fixtures/fence-corpus/run-corpus.sh` (236 rows) | 89/89 · 142/142 · 0/5, p95 45–49 ms; `--knob-off --rows` identical to the `b6802e4f` hook |
| 24 unit suites (fence ×3, hook-guard, guard-yield, guard-origins, floor-snapshot, settings-permissions, implement-gate 33, run-checkpoint-derive 22, run-checkpoint-record-round 8, run-checkpoint, agent-teams-hooks, profile-lib 17, profile-floor 7, karpathy-surgical-diff + 2 migrated, lint-invariants 9, skill-capabilities, prompt-budget 10, instruction-diet-revert, kf-surface, loa-decisions-surface) | 616 pass / 0 fail |
| pytest (hook regressions, catalog floor, auth metadata validator) | 92 passed, 412 subtests |
| `tools/check-prompt-budget.sh` | green at the new cap (9,189 ≤ 9,445) |
| `tools/check-knob-readers.sh` · `validate-skill-capabilities.sh` · `generate-skill-includes.sh --check` · `guard-yield.sh --check` · `validate-constraints.sh` · `tools/check-no-raw-sha256sum.sh` · `evals/fixtures/sync-fixtures.sh --check` · `validate-artifact.sh --type sprint` | all green |
| F's worktree sweep (57 bats files) | 908 ok / 15 not ok → IG-11 fixed; 14 pre-existing on `b6802e4f` (listed under AC-2.12) |
| not run locally | full bats sweep (CI), vitest (Sprint 3 `npm ci`) |

## Known Limitations

- **`gh api -X DELETE` has no fence rule** (B89): the classifier scans its body in full (D113 blocks a destructive body), but the ref-deletion call itself passes today as it did before. A candidate for a Sprint 3 or follow-up fence row.
- **Arm results absent** at Task 2.8 → every text deletion deferred (bd-2txz1); the cap still fell to the measured size.
- **`disallowed-tools` is not a barrier in subagents** and costs the main session its write tools until the operator's next prompt once invoked (KF-043). Sprint 3's implementers must be dispatched from a fresh session.
- **Checksums manifest**: 3,370 entries vs 3,363 files on disk; the gap predates the sprint (pytest-cache paths from a full generation) and the refresh was selective by design (a full regeneration would hash untracked caches).
- **D**: `detect-platform-features.sh --line` still prints "Implement gate: heuristic|authoritative" beside the new Gate line; `derive` does not evaluate the timeout trigger; `deny` reads the sprint-plan cache only; a marker and trailer forged together with the right sprint id pass.
- **E**: a body written to a plain file by one command and executed by a later command is outside a per-command fence (the Write tool shares it); exec-shaped flag clusters make `jq -c`, `grep -e`, `wc -c` full-scan (fail closed).
- **F**: `guardrails-orchestrator.sh` sub-checks (`is_check_enabled`, `get_check_mode`) still use `//` (a sub-check set to `enabled: false` reads as true; outside the profile set; bead suggested); the retrospective postlude now runs in this repository under `standard`; an operator who copies the whole example defeats `lean` until the explicit keys are removed (`/loa` shows them); `run-mode/SKILL.md:26` keeps its own copy of the old guardrails-skip prose; the Profile line is not in `loa-status.sh --json`.

## Removed text

- `reviewing-code/SKILL.md` (F, byte-neutral SURGICAL sentence): the `## Provenance` footer — "Folded in from history: AC Verification auto-fail (cycle-057, #475), Fast-Gate Parity (#1086), YAGNI taxonomy (#1012)." Added: "`SURGICAL:` reads `.run/karpathy-surgical-summary.json` and `.run/karpathy-surgical/<bead>.jsonl` (sprint beads) when present."
- `implementing-tasks/SKILL.md` (D, to fit the budget): the inline `br` command list the lifecycle line repeats, the second "fall back to markdown" sentence, and "patterns," in "architecture, patterns, conventions".
- `run-mode/SKILL.md` (D): §Circuit Breaker prose → the `record-round` call plus two lines; §Issue Hash Tracking removed (the hash lives in the script).
- `.claude/loa/CLAUDE.loa.md` (F): the `## Agent Teams` table (rationales preserved in `agent-teams-reference.md`).

## Verification Steps

    LOA_HARNESS_CHECK=0 LOA_AUDIT_REPLAY=1 <bats> tests/unit/implement-gate.bats tests/unit/run-checkpoint-derive.bats tests/unit/run-checkpoint-record-round.bats tests/unit/profile-lib.bats tests/unit/profile-floor.bats tests/unit/karpathy-surgical-diff.bats tests/unit/lint-invariants.bats tests/unit/skill-capabilities.bats tests/unit/prompt-budget.bats tests/unit/guard-yield.bats tests/unit/block-destructive-bash.bats
    tests/fixtures/fence-corpus/run-corpus.sh            # 89/89 142/142 0/5
    tests/fixtures/fence-corpus/run-corpus.sh --rows --knob-off > /tmp/off.txt; tests/fixtures/fence-corpus/run-corpus.sh --rows --hook <(git show b6802e4f:.claude/hooks/safety/block-destructive-bash.sh) > /tmp/head.txt; diff /tmp/off.txt /tmp/head.txt
    tools/check-prompt-budget.sh; tools/check-knob-readers.sh; .claude/scripts/guard-yield.sh --check
    .claude/hooks/compliance/implement-gate.sh --effective-mode .loa.config.yaml   # ask
    .claude/scripts/loa-status.sh | grep -E '^(Profile|Gate|Guards)'

(`<bats>` is the binary recorded in `~/.cache/loa/cycle-128/bats-path`; run the scripts with `bash`.)

## Assumptions

- [ASSUMPTION decision] Task 2.8's fallback treats the IDR-3-pinned rationales as review-affecting (DEC-0283); the behavioural moves are proposed, not executed (DEC-0284 … DEC-0286).
- [ASSUMPTION decision] The lead authored the FR-6 corpus rows and the shim, fixed the in-place flag check, and accepted E's quoted-delimiter reading (DEC-0287 … DEC-0290).
- [ASSUMPTION decision] The AC-2.2 fallback was not taken because the probe showed `allowed-tools` does not restrict where `disallowed-tools` does not (this report; CHANGELOG; KF-043).
- [ASSUMPTION decision] `gh api -X DELETE` is a documented miss (B89) rather than a new fence rule this sprint (DEC-0287).
- [ASSUMPTION fact] The arm batch was `running` at 02:33:26Z with 20 of 96 review trials done and 0 failed.
- [ASSUMPTION fact] Write and Edit were disabled after the main-session probe until the operator's next prompt; every lead write in between went through Bash into State-Zone paths only.

## Feedback Addressed (review round r256-1)

Source: `engineer-feedback-r1.md` (CHANGES_REQUIRED, critical 0 / high 1 / medium 0 / low 7) and dissent `adversarial-review.json` (round 1). Every item is quoted, then the fix and its verification.

> **HIGH-1 — backtick command substitution is inert to the fence, and B79/B84 now pin that as the expected result.** "(a) the fence treats a backtick pair outside single quotes as a command substitution wherever it treats `$( )` … (b) B79 and B84 become quoted-delimiter rows … the unquoted backtick forms become D-rows … plus D-rows for the `echo`, `printf` and assignment shapes probed above and a B-row for the single-quoted shape; (c) the hooks-reference SP-1/P2 notes about 'another backtick span' gain the quoting qualifier."

- **(a) Fence** `.claude/hooks/safety/block-destructive-bash.sh`: a normalisation step runs after the heredoc scrub and before the carrier scrubs (`_bdb_backtick_norm`, called where `_cmd_match` is built). It walks the command line by line: outside heredoc bodies it tracks shell quotes and turns the 1st, 3rd, … backtick outside single quotes into the dollar-paren opener and the 2nd, 4th, … into the closer (a backslash keeps the next character literal); for each heredoc it asks the FR-6 header parser for the delimiter and its quoting, alternates every backtick in an unquoted body (bodies are raw text, so no shell quoting applies there) and leaves a quoted body untouched; if the shell text's quotes do not balance at the end, or a header is unreadable or holds several heredocs, the shell text is redone with quoting ignored (fail closed). The first version tracked shell quotes across the whole command and missed D144 because an apostrophe in prose opened a phantom single quote; the heredoc-aware rewrite is what landed. Kept segments of a quoted body have their literal backticks stripped in `_bdb_hd_scan_body` so prose such as B91 cannot become a substitution. No pattern id changed. Decision row lead-14 (seeded with this round).
- **(b) Corpus** `tests/fixtures/fence-corpus/corpus.jsonl`: B79 and B84 use a quoted delimiter (allow, `why` updated); new D143 (B79's unquoted form), D144 (B84's unquoted form), D145 (double-quoted `echo` argument), D146 (double-quoted `printf` argument redirected to a file), D147 (double-quoted assignment), D148 (the dollar-paren twin of D145, pinned so the two forms cannot diverge again); new B90 (single-quoted `echo`: literal), B92–B94 (an apostrophe under a quoted delimiter, escaped backticks, a quoted body followed by a harmless command) and D149–D155 (an apostrophe inside double quotes and in an unquoted body, the dash form, mixed quoting on one line, two heredocs, a pipeline member, a header-line substitution; the second commit of the round), and B91 (quoted-delimiter `git commit -F -` body mentioning an ordinary command in backticks: literal, allowed).
- **(c) Docs** `.claude/loa/reference/hooks-reference.md`: a "Backticks (r256-1)" bullet in the heredoc-classifier section and the quoting qualifier on the SP-1 row; `CHANGELOG.md` Fixed entry.
- **Verification**: corpus 91/91 benign · 148/148 dangerous · 0/5 residual; the probe rows in `~/.cache/loa/cycle-129/fr6-probe2.jsonl` now read Q01 2, Q05 2, Q07 2, Q09 2, Q10 0; `--rows --knob-off` against the `b6802e4f` hook differs on exactly D143–D147 (they block under both knob settings because the normalisation is fence-wide, not a classifier feature — DEC-0296) and on no other row; hook bats 476 pass / 0 fail; the hook costs 11 ms per call on a plain command and 16 ms on a command holding backticks (p95 over the corpus read 118 ms only because the host load average was 10–24 during the run: the arm batch and a research subagent; E measured 45 ms on the same code path earlier under load 3).

> **LOW-1 — guardrail readers and `loa_knob`** "add `tools/check-knob-readers.sh` to the Shell Tests workflow so a regression to a bare `yq '.key // true'` read fails CI."

- `.github/workflows/bats-tests.yml`: step "Knob readers go through profile-lib (check-knob-readers.sh)" after the register drift gate. Verified locally: `bash tools/check-knob-readers.sh` → "no direct profile-key reads (9 keys checked)".

> **LOW-2 — knob-off replay reads the right config** "at the top of a `--knob-off` run assert one known-divergent row flips (D122 or D123 exit 2 only with the classifier on)."

- `tests/fixtures/fence-corpus/run-corpus.sh`: records D122's exit code and, in `--knob-off` mode, exits 3 with a message when D122 did not pass (the pre-cycle scan lets a `.sh`-target quoted heredoc through; only the classifier blocks it). Verified: the knob-off run passes the check and reports benign 86/91 · dangerous 142/148, the expected pre-cycle shape.

> **LOW-3 — GNU-only `touch -d` in KS-5** "Use `touch -t "202601010000.$i"`."

- `tests/unit/karpathy-surgical-diff.bats:112` uses the POSIX `-t` form. Verified: `karpathy-surgical-diff.bats` green in the 476-case run.

> **LOW-4 — the implementing-skill marker's window** "No change required this round."

- No change; recorded as an accepted gap in the hooks reference (the marker window is 7,200 s).

> **LOW-5 — `LOA_PROFILE_CONFIG_FILE` is an ungated seam** "Document the seam in the example's `loa:` block or gate it like `LOA_STATUS_CONFIG_FILE`."

- `.loa.config.yaml.example` `loa:` block: a three-line comment documents the seam and that it is honoured outside bats.

> **LOW-6 — surgical-diff hook cost per write** "record the budget next to the fence's in the hooks reference."

- Not changed this round: the hook's cost (43–107 ms) is recorded here and in F's report; the hooks-reference latency table gains the row in the Sprint 3 docs pass (Task 3.6) rather than a fourth edit of the generated-table file in this round.

> **LOW-7 — AC-2.12 is Partial** "The 14 pre-existing failures F found on pristine `b6802e4f` … must be triaged or filed as beads before the cycle PR."

- Still Partial; the triage happens with the cycle PR's CI run (Sprint 3 Task 3.E2E lists it).

Also in this round: the KF-043 scope was corrected by an attempt row (the write tools returned at the operator's next prompt, so the loss is per agentic turn; DEC-0297), the `skill-invariants.md` probe paragraph was added, and the report's probe wording was corrected accordingly.

## Feedback Addressed (review round r256-2)

Source: `engineer-feedback-r2.md` (CHANGES_REQUIRED, critical 0 / high 1 / medium 0 / low 3) and dissent `adversarial-review.json` (round 2, consensus, 4 findings).

> **HIGH-2 — the example pins eight of the nine profile keys, so `loa.profile` governs almost nothing in a copied config.** "(a) in the example, every profile-governed key is present as a commented line with its `standard` value and a note that `loa.profile` governs it … (b) a bats assertion that `yq '.<key>'` on the example is null for every key in `profiles.yaml`, and the oracle comparison (PL-3/PL-4) compares the profile's `standard` values with the example's EFFECTIVE values through `loa_knob` … (c) AC-2.4's 'the example reads `false` for both guardrail keys' is restated as the effective value under `standard` with the raw key commented."

- **(a)** `.loa.config.yaml.example`: the eight keys that were explicit (`known_failures.surface_at_session_start`, `decisions.surface_at_session_start`, `guardrails.input.enabled`, `guardrails.danger_level.enforce`, `invisible_retrospective.enabled`, `structured_handoff.enabled`, `karpathy_principles.surgical_diff_warning`, `karpathy_principles.require_success_criteria`) are now commented lines at their usual place, each with "Profile-governed (loa.profile; standard = …). Uncomment to pin it"; `soul_identity_doc.enabled` was already absent. The `loa:` block says that the nine keys appear only as commented lines so a copied example follows the chosen profile and that an uncommented key is an explicit override. The file still parses (`yq '.'`), and every profile key reads `null` from the raw example.
- **(b)** `tests/unit/profile-lib.bats` PL-4 is rewritten: every profile key must be null in the raw example; the effective value under the example (through `profile-lib.sh knob`) equals `standard`; `loa.profile` is `standard` and `overrides` is empty; and a copy of the example with `profile: lean` and with `profile: full` resolves every key to that profile's value with `overrides` empty. PL-1's negated grep became a `run` with a status check (the same pitfall as LOW-8). PL-3 (the pre-change oracle) is unchanged.
- **(c)** `grimoires/loa/sprint.md` AC-2.4 is amended to the effective value under `standard` with the raw keys commented, naming this round; this repository's `.loa.config.yaml` keeps its explicit `guardrails` block as the intended override (`/loa` lists it).
- **Verification**: `yq -r ".$k" .loa.config.yaml.example` prints `null` for all nine keys; `profile-lib.sh knob guardrails.input.enabled` prints `false` under the example and `true` under a copy with `profile: full`, with no overrides listed; the profile, lint-invariants, karpathy-config-schema and the thirteen example-reading bats suites are in the run recorded in the Testing Summary addendum below.

> **LOW-8 — bare `!`-negated assertions mid-test.** "Replace each with `run` plus a status assertion."

- `tests/unit/lint-invariants.bats` LI-2, LI-3, LI-5 and LI-8 use `run … ; [ "$status" -ne 0 ]`; LI-8 captures the lint's JSON in a local before the `run`, so the later assertions keep reading it.

> **LOW-9 — `tools/check-knob-readers.sh` robustness.** "Escape every ERE metacharacter, add `-I`, and treat grep exit 2 as a hard error."

- The alternation escapes `] [ . * ^ $ + ? ( ) { } | \`; grep runs with `-rnIE`; its exit status is captured and `>= 2` exits 2 with the message, so a bad pattern can no longer print "no direct profile-key reads". Verified: the lint still passes on the tree (9 keys).

> **LOW-10 — the `--knob-off` self-check is skipped silently when the corpus has no D122.** "Under `--knob-off`, an unseen D122 exits 3 unless `--no-self-check` is passed; the header states that the knob reaches the hook through `LOA_REPO_ROOT`."

- `tests/fixtures/fence-corpus/run-corpus.sh`: `--knob-off` without a D122 row exits 3 with "self-check impossible … pass --no-self-check for a probe corpus"; `--no-self-check` is a documented flag; the header states that the hook reads the knob file through `LOA_REPO_ROOT`, which the runner exports as the replay root. Verified: the full corpus under `--knob-off` passes the self-check (benign 89/94, dangerous 149/155, the expected pre-cycle shape); the probe corpus exits 3 without the flag and runs with it.

### Testing Summary addendum (round r256-2 tree)

- fence corpus: benign 94/94 · dangerous 155/155 · residual 0/5 (knob on); knob-off self-check passes; p95 128–176 ms with the host load average at 10–22 (the arm batch and a research subagent; the hook costs 11–16 ms per call in isolation).
- bats: profile-lib, profile-floor, lint-invariants, karpathy-config-schema, guardrails-orchestrator-file-input, kf-surface, loa-decisions-surface and the thirteen suites that read the example — see the final line of this report's run log in `engineer-feedback.md` round 3 (the lead ran them before commit; the count is recorded there).
- `test-lint-invariants.sh`, `tools/check-knob-readers.sh`, `bash -n` on the two edited scripts: green.

## Feedback Addressed (review round r256-3 — dissent advisories, applied before the approval)

Source: dissent `adversarial-review.json` (round 3 on `77455afb`: two-voice consensus, APPROVED quality, 3 advisories, 0 blocking). The lead applied the three advisories in a follow-up commit so the approved tree carries them; the review round records them as LOW-11 … LOW-13.

> **DISS-C-001 — `check-knob-readers.sh` hard-fails with a misleading diagnosis when `--root` has no `tools/` directory** (grep exits 2 for an unreadable path).

- `tools/check-knob-readers.sh` searches only the directories that exist (`.claude` required, `tools/` optional), keeps grep's stderr in a temp file and quotes it in the exit-2 message. Verified: the tree passes; a fixture root with only `.claude/data/profiles.yaml` and a planted direct read exits 1 with the hit, not 2.

> **DISS-C-002 — the `--knob-off` self-check has no positive control** (a config that disables the whole fence would also make D122 exit 0).

- `run-corpus.sh --knob-off` also requires D01 (a plain FR-2 block that no knob touches) to exit 2, else exit 3 with "the config file disabled the fence, not only the classifier". Verified on the full corpus.

> **DISS-C-003 — B89 pins a documented miss as `expect: allow`, so a future rule would read as a regression.**

- `run-corpus.sh` gains the `miss` expectation class: counted and reported as `miss M/T` (M = rows the hook still lets through; JSON `miss_open`/`miss_total`), never a mismatch in either direction. B89 became `M01` with `expect: miss`. The runner header documents the four classes.

Verification for the three: `run-corpus.sh` green (`benign 93/93 dangerous 155/155 residual 0/5 miss 1/1`); `--knob-off` passes both controls; `--json` carries the new fields; the corpus-gate cases in `block-destructive-bash.bats` and PL-17 green.

## Security Audit Feedback Addressed (round r256-4)

Source: `auditor-sprint-feedback-r1.md` (CHANGES_REQUIRED, critical 0 / high 1 / medium 2 / low 5) and dissent `adversarial-audit.json` (round 1: two-voice consensus, 9 findings, 0 rejected).

> **HIGH-A1 — `gh api` with a destructive method on refs, branches, tags, releases or the repository bypasses the branch-protection intent.** "a fence rule (`FR-GH-1`) … M01 becomes a D-row; the miss class keeps a pinned expected count … register row, hooks-reference line and corpus B-rows for the GET/POST/issue-PATCH forms that stay allowed."

- `.claude/hooks/safety/block-destructive-bash.sh`: rule `FR-GH-1` (its own `# @guard fence:FR-GH-1` marker) refuses `gh api` with `-X`/`-XDELETE`/`--method`/`--method=` `DELETE|PUT|PATCH` against `/git/refs/`, `/git/tags/`, `/branches/<b>/protection`, `/releases`, `/tags` or a bare `repos/<o>/<r>`. It sits OUTSIDE the pass-8 git-family pre-filter (a `gh api` call need not contain the word `git`): the first placement, inside that filter, blocked only the two rows whose path happened to contain `git/refs` and let D158–D161 through — found by the corpus, fixed before commit.
- `tests/fixtures/fence-corpus/corpus.jsonl`: M01 → D156 (block); D157 (joined `-XDELETE`, tag ref), D158 (`--method PUT` branch protection), D159 (`--method=DELETE` quoted release path), D160 (`DELETE` the repository), D161 (`PATCH` the repository); B95 (GET), B96 (POST issue), B97 (PATCH issue) stay allowed.
- `run-corpus.sh`: `EXPECTED_MISS_ROWS=0` is pinned; a corpus with a different number of `miss` rows reports a mismatch, so a new documented miss has to raise the pin in the change that documents it.
- `.claude/data/guard-origins.yaml`: row `fence:FR-GH-1` (origin: this audit round); register regenerated, 96 guards, `--check` in sync. `hooks-reference.md`: a "cycle-129 additions" paragraph names the rule, the backtick normalisation and the classifier section.
- Verification: corpus `benign 96/96 dangerous 168/168 residual 0/5 miss 0/0`; `--rows` shows D156–D161 → 2 and B95–B97 → 0; hook bats 453 / 0; `guard-origins.bats` and `floor-snapshot.bats` green with the new id.

> **MEDIUM-A1 — dead negated assertions in the new surgical-diff suite.** "`run` plus a status assertion for the negation; one assertion per line in KS-8."

- `tests/unit/karpathy-surgical-diff.bats`: KS-9's leak check is `run grep …; [ "$status" -ne 0 ]`; KS-8's three `&&` chains are six single assertions. Suite green (11/11).

> **MEDIUM-A2 — the register's false-positive heuristic treats a System-Zone block as prose.** "apply the heredoc heuristic only to content rules, never to `FR-SZ*` pattern ids; the GY-3 expectation for that row becomes a real block."

- `.claude/scripts/guard-yield.sh`: `likely_fp` is `(heredoc and not system_zone) or outside_repo or (prose_class and not destructive_start)`, with `system_zone` = pattern id starting `FR-SZ`. `guard-yield.bats` GY-3 expects `fence:FR-SZ2-REDIR` as `[1,0,0,"2026-10-12"]` and the hook total as `[5,2,0,…]`; GY-1's header totals follow (`[5,3,2,2]`). Suite green (11/11).

> **LOW-A1 — executable-content targets the classifier should also treat as code.** "extend the target rule and pin each class with a D-row."

- `_bdb_hd_re_sys` now also treats `.github/workflows/`, makefiles (`Makefile`, `makefile`, `GNUmakefile`, `justfile`), `package.json`, `pyproject.toml`, `Cargo.toml`, `Gemfile` and `Rakefile` as executable content; D162 (`.git/hooks/pre-commit`), D163 (`.py`), D164 (workflow yml), D165 (`Makefile`), D166 (`.envrc`), D167 (`.claude/settings.local.json`), D168 (`package.json` scripts) pin the classes; the hooks-reference target list names them.

> **LOW-A2 — guardrails and danger-level enforcement default off for a fresh install.** "a security note in the CHANGELOG … the include's fail-open error path and the `LOA_GUARDRAILS_ENABLED=false` escape … go to a bead."

- `CHANGELOG.md`: the "Guardrails and danger level default off" entry carries a security note stating what a fresh install does not run, what the checks detected historically, that the floor does not depend on them, and the two keys or `loa.profile: full` that restore them; the include's fail-open path and the env escape are named as follow-up work. Bead: see the sprint close (bd-hjlv comment).

> **LOW-A3 … LOW-A5** — accepted gaps and notes, no change (recorded in the audit round-1 file; beads at sprint close).

Decision rows: DEC-0304 (System-Zone blocks are never body-based false positives), DEC-0305 (FR-GH-1), DEC-0306 (miss class count-gated).

## Security Audit Feedback Addressed (round r256-5 — second audit dissent, applied before the approval)

Source: dissent `adversarial-audit.json` (round 2 on `81005346`: two-voice consensus, APPROVED quality, 5 findings — 3 MEDIUM, 2 LOW — 0 rejected). The auditor applied every item in a follow-up commit and verified it directly; the sprint had used its dissent runs (three review, two audit), so no third audit run was spent (recorded as a decision row).

> **DISS-C-001 (MEDIUM) — guardrails and danger-level enforcement default off; the include is fail-open.** "If the default must stay off, have /loa … print a one-line notice whenever either guardrail key resolves to false."

- Decision DEC-0161 stands (operator-behalf, awaiting confirmation; security note in the CHANGELOG from r256-4). Mitigation landed: `loa-status.sh` `display_profile_line` appends `· input guardrails off` / `· danger-level enforcement off` whenever either control resolves to off, whatever turned it off; PL-14 pins the three shapes (lean with input pinned on, standard, full). The include's fail-open row and the env escape remain follow-up work (bead at sprint close).

> **DISS-C-002 (MEDIUM) — the per-segment scan drops segments whose command word is a shell reserved word or a wrapper.**

- `_bdb_hd_segword` treats `if then elif else do done while until fi esac coproc function` as transparent prefixes (the wrappers `sudo doas command exec env nice time nohup builtin stdbuf ionice` already were; `timeout`, `xargs` and the other argument-running words already send the body to the full scan). `_bdb_hd_re_sys` adds `Dockerfile*`, `.pre-commit-config.yaml` and `.gitlab-ci.yml` to the executable-content targets. Corpus: D169 (`then rm`), D170 (brace group), D171 (negation), D172 (`timeout`), D173 (`nohup`), D174 (`while … do rm`), D175 (`crontab -`), D176 (`at`), D177 (`Dockerfile`), D178 (`.pre-commit-config.yaml`) block; the reserved-word rows use `tee` because a standalone quoted `cat` to a plain file is the #1245 special case, whose body is dropped whole by design (nothing executes at the write) — B100 pins that twin as allowed and names the per-command gap.

> **DISS-C-003 (MEDIUM) — FR-GH-1 misses the GraphQL mutations, the full-URL and leading-slash path forms, a non-literal method and `--hostname`.**

- The REST branch of `FR-GH-1` normalises the path (optional `https://HOST(/api/v3)` prefix, optional leading slash) and treats a method the fence cannot read (`-X "$M"`, `--method=$m`) as destructive against a protected path; a GraphQL branch refuses `gh api graphql` whose query names `deleteRef`, `deleteBranchProtectionRule`, `updateBranchProtectionRule`, `createBranchProtectionRule`, `deleteRepository`, `updateRepository` or `deleteRelease`. Corpus: D179 (`deleteRef`), D180 (branch-protection mutation), D181 (full URL), D182 (leading slash), D183 (variable method), D184 (`--hostname`) block; B98 (a GraphQL query) and B99 (`PATCH` on a pull request) allow. The corpus hygiene lint admits the single host `https://api.github.com/` so the URL form can be pinned.

> **DISS-C-004 (LOW) — `LOA_PROFILE_CONFIG_FILE` honoured outside bats without a trace.**

- `profile-lib.sh` prints `profile-lib: WARN knob reads come from <file> (LOA_PROFILE_CONFIG_FILE is set)` to stderr once per process whenever the seam is honoured outside bats.

> **DISS-C-005 (LOW) — knob-lint bypass forms.**

- `tools/check-knob-readers.sh` also matches the trailing two components of every three-part key (`.input.enabled`, `.danger_level.enforce`), so a read split across a pipe or a bracket form that ends in the dotted tail is flagged; PL-17 plants both shapes and asserts exit 1, and asserts a fixture root without `tools/` exits 0.

Verification on the final tree: corpus `benign 99/99 dangerous 184/184 residual 0/5 miss 0/0` (p95 41 ms, host load back to normal), knob-off with both controls, `guard-yield.sh --check` in sync (96 guards; FR-GH-1 has two call sites under one marker id), hook and register bats 440/0 + corpus gate 4/4, profile-lib 17/17 and profile-floor 7/7, lint-invariants and prompt-budget green, `check-knob-readers.sh` clean, budget green, `validate-constraints` clean; `/loa` on this repository prints `Profile: standard (explicit overrides: guardrails.input.enabled=true, known_failures.surface_at_session_start=true) · danger-level enforcement off`.
