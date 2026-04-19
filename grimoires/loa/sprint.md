# Sprint Plan — Cycle-092: Spiral Harness Live-Visibility Seam

**Version:** 1.0
**Date:** 2026-04-19
**Author:** Sprint Planner Agent
**Scope:** Issues [#600](https://github.com/0xHoneyJar/loa/issues/600), [#599](https://github.com/0xHoneyJar/loa/issues/599), [#598](https://github.com/0xHoneyJar/loa/issues/598)
**Reporter:** @zkSoju (all three filed 2026-04-19 during cycle-091)
**Prior cycle context:**
- `grimoires/loa/proposals/rfc-062-seed-seam-autopoiesis.md` — RFC-062 (sibling doctrine; landed via PR #596)
- `.claude/scripts/spiral-evidence.sh:387` — `_pre_check_seed` (landed via PR #594 for issue #575 item 3)
- `.claude/scripts/spiral-evidence.sh:653` — `_emit_dashboard_snapshot` (the freezing bug site)
- `.claude/scripts/spiral-harness.sh:1109-1173` — main pipeline where phase transitions are logged

---

## Executive Summary

All three issues extend the cycle-088 observability + hardening surface that shipped in PR #589 (dashboard default-on), PR #592 (fold prior-cycle failure events into SEED), and PR #594 (`_pre_check_seed`). They share two cross-cutting concerns — **dispatch-log vocabulary** and **cycle state-file conventions** — which means the cheapest path ships a **shared-infrastructure sprint first**, then one sprint per issue consuming that infra.

This sprint-split avoids the alternative (three parallel issue-sprints each redefining the grammar) which is how cycle-091 burned $60 and 3 REVIEW passes: the same vocabulary getting reimplemented inconsistently across sibling features.

**Doctrinal framing**: RFC-062 is the **seed seam** (operator edits intent at cycle N→N+1 boundary). #598 is the **in-flight seam** (operator reads intent during cycle N). Same doctrine (editor-of-intent), two seams, shared infrastructure (cycle state files + log-line grammar).

**Total Sprints:** 4
**Sprint Sizing:** Sprint 1 = MEDIUM (6 tasks, shared infra); Sprints 2–4 = one per issue, MEDIUM each
**Total Tasks:** 22
**Estimated Completion:** One cycle (landable as single PR; sprints sequenced so each builds on the prior)

### Non-Goals (explicit)

Per the task framing:
- **Not** building full RFC-062 seed-seam autopoiesis (PR #596 opened that thread, still in progress)
- **Not** refactoring the underlying spiral state machine
- **Not** expanding #598 to JSON-only format (Sprint 4 keeps the 3-line `editor` format primary; `compact` and `json` are S5 stretch scope per issue body)
- **Not** expanding PRD/SDD — issue bodies contain the proposals; this is bug/enhancement work against the existing harness

---

## Sprint Overview

| Sprint | Theme | Size | Key Deliverables | Primary Issue | Dependencies |
|--------|-------|------|------------------|---------------|--------------|
| 1 | Shared observability infrastructure | MEDIUM (6) | Log-line grammar spec, `.phase-current` state file, dispatch-log path convention, grammar test fixtures | Cross-cutting | None (foundation) |
| 2 | Pre-review artifact-coverage evidence gate | MEDIUM (5) | `_pre_check_implementation_evidence`, sprint.md path parser, targeted IMPL fix-loop on `IMPL_EVIDENCE_MISSING` | #600 | Sprint 1 (grammar for new verdict) |
| 3 | Dashboard mid-phase writes + `.phase-current` consumer | MEDIUM (5) | Dashboard writer emits phase-start rows, mid-phase heartbeat from flight-recorder tail, phase-current integration | #599 | Sprint 1 (`.phase-current` state file) |
| 4 | SIMSTIM heartbeat (editor-of-intent in-flight) | MEDIUM (6) | Heartbeat emitter daemon, intent extractor, confidence-cue parser, `SpiralPhaseComplete` hook, `.loa.config.yaml` schema | #598 | Sprint 1 (grammar); Sprint 2 verdict (`IMPL_EVIDENCE_MISSING` surfaces as phase verb); Sprint 3 (`.phase-current` is heartbeat's truth source) |

**Critical path**: Sprint 1 → Sprint 2 → Sprint 3 → Sprint 4. Sprint 1 is the foundation; everything downstream depends on its grammar + state file.

---

## Goals (extracted from issue bodies)

Since no PRD exists for this cycle (bug/enhancement track), goals are extracted directly from issue bodies and enumerated here as first-class G-IDs:

| ID | Goal | Source | Measurement |
|----|------|--------|-------------|
| G-1 | IMPL subprocess cannot ship "all N sprints" while omitting SEED-named visible artifacts; failures surface pre-review, not post-review | #600 | Synthetic repro of cycle-091 (backend-only commit against sprint.md with named `.svelte` deliverables) exits with `IMPL_EVIDENCE_MISSING` before REVIEW dispatches |
| G-2 | `dashboard-latest.json` reflects in-flight phase state within 60s of a mid-phase event, not frozen at the prior phase-EXIT write | #599 | During a simulated 10-min IMPL, polling dashboard-latest.json every 60s shows monotonically increasing `last_action_ts` and `cost_usd` |
| G-3 | Operator reading Claude Code ambient UI during a spiral cycle receives a `[HEARTBEAT]` line every 60s with phase verb, intent, confidence cue, kaironic/chronic clocks, budget, diff, pace — makes operator an editor-of-intent not a spectator | #598 | Hermetic dispatch emits ≥30 heartbeats during a 30-min synthetic cycle; each carries all 11 required keys; intent changes on phase boundary |
| G-4 | Log-line grammar + path convention is consistent across #598 parser, #599 monitor, and #600 gate output; adding a new phase verdict ripples to all three without divergence | Cross-cutting | Grammar test fixtures in Sprint 1 exercised by Sprints 2/3/4; no sprint adds a regex that isn't declared in the shared grammar table |

---

## Sprint 1: Shared Observability Infrastructure

**Size:** MEDIUM (6 tasks)
**Duration:** 2.5 days
**Dates:** Day 1–3 of cycle

### Sprint Goal
Formalize the dispatch-log line grammar, `.phase-current` state file, and path convention that all three downstream issues depend on — so Sprints 2/3/4 consume a stable shared surface instead of re-inventing it.

### Deliverables
- [ ] `grimoires/loa/proposals/dispatch-log-grammar.md` — canonical grammar spec documenting every current `[harness]`-emitted line shape plus the three new verdicts (`IMPL_EVIDENCE_MISSING`, phase-start, heartbeat)
- [ ] `.claude/scripts/spiral-evidence.sh` — new helpers `_phase_current_write <cycle_dir> <phase_label> <attempt_num> <fix_iter>`, `_phase_current_touch <cycle_dir>`, `_phase_current_clear <cycle_dir>`, `_phase_current_read <cycle_dir>`
- [ ] `.claude/scripts/spiral-harness.sh` — calls to `_phase_current_write` at every `log "Phase N: …"` / `log "Gate: …"` / `log "Pre-check: …"` site; `_phase_current_clear` at `main()` exit (success AND failure paths via trap)
- [ ] Path convention decision documented in the grammar spec: `${CYCLE_DIR}/dispatch.log` (migrating from current `harness-stderr.log` sibling pattern, per @zkSoju's comment on #598)
- [ ] `tests/unit/dispatch-log-grammar.bats` — fixture-based tests asserting the grammar table: given line X, parser Y should extract field Z
- [ ] `tests/unit/phase-current-state.bats` — state file lifecycle tests (written at phase-START, mtime updated on sub-events, deleted at phase-EXIT, deleted on crash via trap)

### Acceptance Criteria
- [ ] Grammar spec enumerates every current `log()` line in `spiral-harness.sh` with a named shape (e.g., `phase-transition`, `gate-attempt`, `pre-check-start`, `review-fix-iteration`, `circuit-breaker-trip`)
- [ ] Spec reserves three new shapes for downstream sprints: `impl-evidence-missing` (Sprint 2), `phase-heartbeat-emitted` (Sprint 4), `phase-current-cleared` (Sprint 3 dashboard writer hook)
- [ ] `.phase-current` file format: single line `<phase_label>\t<start_ts>\t<attempt_num>\t<fix_iter>` (tab-separated, fields default to `-` when not applicable) — per #599 issue body spec
- [ ] Harness `main()` sets up `trap 'rm -f "$CYCLE_DIR/.phase-current"' EXIT` so abnormal exits clear the state file (no stale "in-flight" signal)
- [ ] Path migration: `harness-stderr.log` is renamed to `dispatch.log`; `spiral-simstim-dispatch.sh:175` redirection updated; no other scripts reference the old path
- [ ] grammar test fixtures cover: phase transitions 1–6, Gate REVIEW/AUDIT attempts 1/3–3/3, Review fix loop iterations 1/2–2/2, Circuit breaker trip, Pre-check start/pass/fail
- [ ] Grammar spec explicitly marks which fields are stable API (consumed by #598/#599/#600 parsers) vs. which are informational-only

### Technical Tasks

- [ ] **Task 1.1**: Audit current `log()` call-sites in `spiral-harness.sh` and `spiral-evidence.sh`; enumerate line shapes and emit an inventory table (line number, shape name, regex, example) → **[G-4]**
- [ ] **Task 1.2**: Draft `grimoires/loa/proposals/dispatch-log-grammar.md` with: (a) stability API marker per shape, (b) the three reserved shapes for downstream sprints, (c) deprecation note on the old `harness-stderr.log` path → **[G-4]**
- [ ] **Task 1.3**: Implement `_phase_current_write`/`_touch`/`_clear`/`_read` in `.claude/scripts/spiral-evidence.sh`, following the `_pre_check_seed` style (fail-safe, traps jq errors, never breaks the pipeline) → **[G-2, G-3]**
- [ ] **Task 1.4**: Wire `_phase_current_*` calls into `spiral-harness.sh` at every phase transition site (1109–1239); add EXIT trap in `main()` → **[G-2, G-3]**
- [ ] **Task 1.5**: Migrate dispatch-log path from `$cycle_dir/harness-stderr.log` to `$cycle_dir/dispatch.log` in `spiral-simstim-dispatch.sh:175`; grep repo for other consumers of `harness-stderr.log` and update → **[G-4]**
- [ ] **Task 1.6**: Write `tests/unit/dispatch-log-grammar.bats` (grammar fixtures) and `tests/unit/phase-current-state.bats` (state-file lifecycle incl. crash-trap) → **[G-4]**

### Dependencies
- None (foundation sprint)

### Security Considerations
- **Trust boundaries**: `.phase-current` is internal state — not consumed across process boundaries except by monitors reading via filesystem mtime. No untrusted input touches the grammar parser.
- **External dependencies**: None added. Grammar spec is a markdown doc; state file is plain text.
- **Sensitive data**: None. Phase labels, timestamps, attempt numbers are all internal.

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Existing scripts reference `harness-stderr.log` beyond `spiral-simstim-dispatch.sh` and break on rename | Med | Med | Grep is cheap and deterministic — do it in Task 1.5 before committing rename; also keep a symlink for one cycle as compat layer |
| `.phase-current` state file races with harness crash leaving stale "in-flight" signal | Med | Low | EXIT trap in Task 1.4; belt-and-suspenders: monitors treat `.phase-current` older than 2× `baseline_sec` as stale |
| Grammar spec freezes premature — downstream sprints find they need a shape not yet declared | Med | Low | Spec explicitly reserves three shapes for downstream sprints; extension requires grammar spec amendment PR before consumer lands |

### Success Metrics
- Grammar spec merged to `grimoires/loa/proposals/`
- `.phase-current` state file present during every `[harness] Phase N:` log and absent at harness exit (validated by `phase-current-state.bats`)
- Zero references to `harness-stderr.log` remain outside compat symlink
- 100% of current `log()` lines have a named grammar shape

---

## Sprint 2: Pre-Review Artifact-Coverage Evidence Gate (#600)

**Size:** MEDIUM (5 tasks)
**Duration:** 2 days
**Dates:** Day 3–5 of cycle

### Sprint Goal
Catch "IMPL subprocess committed all-N-sprints but omitted SEED-named visible surfaces" failures *before* REVIEW/AUDIT dispatches, via a deterministic `test -s` gate that runs against sprint.md-enumerated paths.

> From #600: *"A sprint-plan-aware audit would have flagged Sprint 8's `TheReliquaryScene.svelte` + Sprint 9's visible reveal beat as missing deliverables. Running the dev server shows all existing scenes but nothing new for cycle-091."*

### Deliverables
- [ ] `.claude/scripts/spiral-evidence.sh` — new `_pre_check_implementation_evidence` function following the `_pre_check_review` pattern
- [ ] `.claude/scripts/spiral-evidence.sh` — new helper `_parse_sprint_paths <sprint_md>` that extracts enumerated paths from `grimoires/loa/sprint.md` (globs + explicit files)
- [ ] `.claude/scripts/spiral-harness.sh` — `main()` calls `_pre_check_implementation_evidence` after `_phase_implement` and before `_pre_check_review`; on failure emits `IMPL_EVIDENCE_MISSING` per Sprint 1 grammar
- [ ] `.claude/scripts/spiral-harness.sh` — targeted IMPL fix-loop on `IMPL_EVIDENCE_MISSING`: dispatches a narrower prompt than semantic review ("these N paths from sprint.md are missing; produce them"), reusing `_phase_implement_with_feedback` plumbing with a new feedback type
- [ ] `tests/unit/spiral-pre-check-implementation-evidence.bats` — covers: (a) happy path (all paths present), (b) missing-path emits `IMPL_EVIDENCE_MISSING`, (c) empty-stub detection (`test -s` fails on zero-byte), (d) path-parser handles globs + explicit files + code-block listings

### Acceptance Criteria
- [ ] `_pre_check_implementation_evidence` returns 0 when all sprint.md-enumerated paths exist and are non-empty (`test -s`), returns 1 otherwise with a diagnostic listing the missing paths
- [ ] On failure, harness records a flight-recorder event `{verdict: "IMPL_EVIDENCE_MISSING", missing_paths: [...]}` — consumable by Sprint 4 heartbeat's phase-verb extractor
- [ ] Targeted fix-loop runs max 2 iterations (narrower than Review fix-loop's 3 — the surface is smaller, and failure after 2 is unlikely to succeed on 3); if still failing, circuit-break with operator intervention requested per issue-body §Suggested fix item 4
- [ ] Hermetic regression test: reproduce cycle-091 scenario (sprint.md names `src/lib/scenes/Reliquary.svelte`, IMPL subprocess commits only backend/tests) → `_pre_check_implementation_evidence` returns 1 with `Reliquary.svelte` in diagnostic output
- [ ] Does NOT replace `/review-sprint`'s own enumeration — it runs first, catches the gross case, saves review budget. Issue body §Suggested fix item 1 note: "Extend /review-sprint … same artifact coverage check" is explicitly deferred to a future cycle.
- [ ] Advisory for trivial-content detection: emit `IMPL_EVIDENCE_TRIVIAL` warning (not block) when a path exists but has <20 lines or matches known-stub regexes (`<script>\s*</script>`, `TODO`); issue body §Suggested fix item 2 defers hard-enforcement to the audit phase

### Technical Tasks

- [ ] **Task 2.1**: Implement `_parse_sprint_paths` — tolerates sprint.md formats observed in cycle-082/091: checkbox lists (`- [ ] ... path: src/...`), code-block file enumerations, inline `path:` mentions. Returns deduped path list → **[G-1]**
- [ ] **Task 2.2**: Implement `_pre_check_implementation_evidence` per `_pre_check_review` pattern — loops `_parse_sprint_paths` output, runs `test -s` on each, accumulates missing-path list, emits grammar-shaped log line on fail → **[G-1]**
- [ ] **Task 2.3**: Wire into `spiral-harness.sh:1174` (between `_phase_implement` and `_pre_check_review`) with conditional targeted fix-loop: on `IMPL_EVIDENCE_MISSING`, dispatch `_phase_implement_with_feedback` but with `FEEDBACK_TYPE=missing_artifacts` and the missing-path list as the prompt payload → **[G-1]**
- [ ] **Task 2.4**: Write `tests/unit/spiral-pre-check-implementation-evidence.bats` (4 scenarios above) + synthetic cycle-091 regression test fixture → **[G-1, G-4]**
- [ ] **Task 2.5**: Add `IMPL_EVIDENCE_MISSING` and `IMPL_EVIDENCE_TRIVIAL` to Sprint 1's grammar spec; confirm Sprint 4 heartbeat extractor can read them as phase-verb inputs → **[G-4]**

### Dependencies
- **Sprint 1**: grammar spec reserves `IMPL_EVIDENCE_MISSING`/`IMPL_EVIDENCE_TRIVIAL` shapes; Task 2.5 amends the spec concretely
- Existing `_phase_implement_with_feedback` plumbing — Task 2.3 reuses it

### Security Considerations
- **Trust boundaries**: `sprint.md` is treated as trusted input (it's written by planning agents, not external attackers). Path traversal is not a concern because paths are consumed only by `test -s`, which is a filesystem stat — no shell interpolation.
- **External dependencies**: None added.
- **Sensitive data**: None. sprint.md is grimoire state, readable by all agents in the cycle.

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| `_parse_sprint_paths` false-negatives (misses a listed artifact, so gate passes even though IMPL shipped gap) | High | Med | Tests cover all observed sprint.md formats; when a new format is added, parser must extend before the cycle lands |
| Targeted fix-loop dispatches twice and still fails → cycle stalls with operator intervention needed | Med | High | Circuit-break is intentional per issue-body §Suggested fix item 4 (operator context is required — retries won't invent the missing artifact). Halt emits a clear actionable verdict line. |
| Glob patterns in sprint.md (`src/**/*.svelte`) expand to nothing on a fresh branch — false-positive `IMPL_EVIDENCE_MISSING` | Med | Low | Parser distinguishes glob from explicit path: globs that expand to zero files emit `IMPL_EVIDENCE_GLOB_UNMATCHED` warning, not a hard fail |

### Success Metrics
- Synthetic cycle-091 scenario emits `IMPL_EVIDENCE_MISSING` before REVIEW, verdict logged to flight-recorder
- Gate runtime <5 seconds for typical sprint.md with 10–30 enumerated paths
- Zero false-negatives on the three sprint.md formats observed in cycles 082/091/092 (test fixtures)
- Fix-loop iteration reduces missing-path count monotonically (if it doesn't, circuit-break rather than retry)

---

## Sprint 3: Dashboard Mid-Phase Writes (#599)

**Size:** MEDIUM (5 tasks)
**Duration:** 2 days
**Dates:** Day 5–7 of cycle

### Sprint Goal
Un-freeze `dashboard-latest.json` during long phases (IMPL especially) by adding phase-start writes + mid-phase heartbeat writes, and consuming Sprint 1's `.phase-current` state file as the authoritative "phase is in-flight right now" signal for external monitors.

> From #599: *"dashboard-latest.json stayed frozen at ts=2026-04-19T04:39:50Z (the prior PRE_CHECK review_ready write). My 23 heartbeat pulses across 35 minutes all reported phase=IMPLEMENT cost=$15. A human watching the dashboard would have concluded the cycle stalled; in reality it finished successfully."*

### Deliverables
- [ ] `.claude/scripts/spiral-evidence.sh` — `_emit_dashboard_snapshot` accepts new event types: `PHASE_START`, `PHASE_HEARTBEAT`, `PHASE_EXIT` (explicit; current default is just phase-label flip)
- [ ] `.claude/scripts/spiral-evidence.sh` — new `_spawn_dashboard_heartbeat_daemon <cycle_dir> <interval_sec>` — background process that emits `PHASE_HEARTBEAT` dashboard snapshots every N sec by tailing flight-recorder
- [ ] `.claude/scripts/spiral-harness.sh` — spawns heartbeat daemon on `main()` entry, reaps it on EXIT trap
- [ ] `grimoires/loa/proposals/rfc-062-seed-seam-autopoiesis.md` — update §Observability section with phase-start-vs-exit semantic (minor docs update)
- [ ] `tests/unit/spiral-dashboard-mid-phase.bats` — simulates 5-min IMPL subprocess, asserts dashboard-latest.json `last_action_ts` advances at heartbeat cadence

### Acceptance Criteria
- [ ] Dashboard snapshot emitted at 3 distinct event types:
    1. **PHASE_START** — at every phase transition (matches `current_phase` flip); clears stale per-phase totals; sets `first_ts` for the new phase
    2. **PHASE_HEARTBEAT** — every 60s during long phases; updates `last_action_ts` + running `cost_usd` from flight-recorder tail
    3. **PHASE_EXIT** — at flight-recorder verdict emission; authoritative totals (this is the current behavior)
- [ ] `dashboard-latest.json` schema unchanged (still `spiral.dashboard.v1`); new `event_type` field is additive (existing consumers ignore it cleanly)
- [ ] Heartbeat daemon reads `.phase-current` from Sprint 1 — if file is absent, daemon exits cleanly (no stray snapshots during pre/post pipeline)
- [ ] Heartbeat interval configurable via `SPIRAL_DASHBOARD_HEARTBEAT_SEC` (default 60; clamp to [30, 300])
- [ ] Hermetic repro of #599 scenario: simulate 5-min IMPL phase; poll dashboard-latest.json at 61s, 121s, 181s, 241s, 301s — `last_action_ts` strictly increases across every poll
- [ ] Daemon does NOT call `_emit_dashboard_snapshot` if `.phase-current` mtime is older than `2 × baseline_sec` (phase is suspected stuck — let Sprint 4 heartbeat surface the `🔴 stuck` signal instead)
- [ ] Daemon reaped on EXIT trap in `main()` — no orphaned daemons after pipeline exits (success OR crash)

### Technical Tasks

- [ ] **Task 3.1**: Extend `_emit_dashboard_snapshot` signature: `_emit_dashboard_snapshot <current_phase> [event_type] [cycle_dir]` (new optional middle arg, default `PHASE_START` for backwards compat) → **[G-2]**
- [ ] **Task 3.2**: Implement `_spawn_dashboard_heartbeat_daemon` — backgrounded while-loop that reads `.phase-current`, computes running totals from flight-recorder tail, calls `_emit_dashboard_snapshot $phase PHASE_HEARTBEAT`, sleeps N sec → **[G-2]**
- [ ] **Task 3.3**: Wire daemon spawn into `spiral-harness.sh:main()` (line 1109 after `_record_action CONFIG`) + reap in EXIT trap (Sprint 1 already adds trap for `.phase-current`; extend to kill daemon PID) → **[G-2]**
- [ ] **Task 3.4**: Write `tests/unit/spiral-dashboard-mid-phase.bats` — uses `SPIRAL_DASHBOARD_HEARTBEAT_SEC=2` and a 10-second synthetic phase to exercise heartbeat cadence in bounded time → **[G-2, G-4]**
- [ ] **Task 3.5**: Update `grimoires/loa/proposals/rfc-062-seed-seam-autopoiesis.md` §Observability to document the 3-event dashboard semantic; note that dashboard-latest.json is now "live in-flight" not "phase-exit-only" → **[G-2]**

### Dependencies
- **Sprint 1**: `.phase-current` state file is the daemon's truth source; EXIT trap plumbing (Sprint 1 Task 1.4) extends to reap daemon PID
- Existing `_emit_dashboard_snapshot` infrastructure

### Security Considerations
- **Trust boundaries**: Background daemon reads only from `.phase-current`, flight-recorder, and cycle-dir — all internal state. No network, no untrusted input.
- **External dependencies**: None added. Daemon is pure bash + jq.
- **Sensitive data**: None. Dashboard snapshots contain cost/duration/phase — all internal telemetry.
- **Process hygiene**: Daemon PID is captured and reaped via EXIT trap. A crash during pipeline should not leak a daemon process (validated by test).

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Backgrounded daemon leaks into operator shell on crash | Med | Med | EXIT trap reaps by PID file; also `trap '...kill $DAEMON_PID 2>/dev/null' EXIT` — covers both clean and crash paths |
| Heartbeat daemon races with phase-exit snapshot → two concurrent jq writes on dashboard-latest.json | Med | Low | Existing `_emit_dashboard_snapshot` already uses `.tmp + mv` atomic pattern (spiral-evidence.sh:737); atomicity prevents torn writes. Last-write-wins is acceptable. |
| Heartbeat writes inflate `dashboard.jsonl` (append-only log) to disk-filling size for long cycles | Low | Med | Heartbeat at 60s × 3-hour cycle = 180 entries of ~1KB each = 180KB. Well within tolerance. No compaction needed. |
| Daemon CPU cost is non-trivial across 36-min IMPL | Low | Low | Per-heartbeat cost: one flight-recorder read + one jq. ~10ms. Over 36 minutes: 36 heartbeats × 10ms = 360ms total. Negligible. |

### Success Metrics
- During synthetic 10-min IMPL, dashboard-latest.json `ts` increments 10× (one per 60s heartbeat)
- `last_action_ts` gap between heartbeats ≤65s (60s interval + 5s scheduling slack)
- Zero leaked daemons after 10 back-to-back synthetic cycles (validated via `pgrep dashboard-heartbeat`)
- Issue #599 reproduction: poll dashboard during IMPL, see `cost_usd` advancing, not frozen at $15

---

## Sprint 4: SIMSTIM Heartbeat — Editor of Intent In-Flight (#598)

**Size:** MEDIUM (6 tasks)
**Duration:** 2.5 days
**Dates:** Day 7–9 of cycle

### Sprint Goal
Emit `[INTENT <ISO>]` and `[HEARTBEAT <ISO>]` lines to dispatch.log at 60s cadence during spiral cycles, sourced from harness's own live artifacts — converting the operator from spectator to editor-of-intent per RFC-062 sibling doctrine.

> From #598: *"Reading line 2 is what makes the operator an editor: 'ah, the reviewer caught §A3 — I can accept the fix direction or redirect.' Before line 2 existed, the operator had to reverse-engineer intent from mechanics."*

### Deliverables
- [ ] `.claude/scripts/spiral-heartbeat.sh` — new standalone emitter (daemon + library functions)
- [ ] `.claude/scripts/spiral-heartbeat.sh` — `_emit_heartbeat` function: reads `.phase-current` (Sprint 1) + flight-recorder tail + git diff vs main, emits 1-line structured `[HEARTBEAT <ISO>] key=value …` with 11 keys per issue body
- [ ] `.claude/scripts/spiral-heartbeat.sh` — `_emit_intent` function: maps phase label → source file (per-phase table), extracts one sentence of intent, emits `[INTENT <ISO>] phase=… intent="…" source=…`
- [ ] `.claude/scripts/spiral-heartbeat.sh` — `_confidence_cue` parser: reads dispatch.log tail for Gate attempt / fix iteration / circuit-break state; outputs cue string
- [ ] `.claude/hooks/` — new `SpiralPhaseComplete` hook registration in `.claude/hooks/hooks.yaml`; fires on `PHASE_EXIT` dashboard event with `$PHASE`, `$COST`, `$DURATION_SEC` env
- [ ] `.loa.config.yaml.example` — `spiral.harness.heartbeat.*` schema per issue body §Configuration section
- [ ] `tests/unit/spiral-heartbeat.bats` — covers emitter cadence, intent extraction per phase, confidence cue state machine, config-schema honoring

### Acceptance Criteria
- [ ] Heartbeat emits exactly 11 keys per issue body:
      `phase phase_verb phase_elapsed_sec total_elapsed_sec cost_usd budget_usd files ins del activity confidence pace`
- [ ] Intent extractor covers 4 sources per issue body §Proposal:
    - `IMPLEMENTATION` / IMPL-fix → `grimoires/loa/a2a/engineer-feedback.md` (first CRITICAL-Blocking finding's title, truncated to 90 chars)
    - `REVIEW` → static string `"checking amendment compliance against the implementation"` (engineer-feedback is from reviewer; phrasing is load-bearing)
    - `AUDIT` → `grimoires/loa/a2a/auditor-sprint-feedback.md` (first `## `-heading, truncated to 90 chars)
    - `FLATLINE`, `PLANNING`, `ARCHITECTURE`, `DISCOVERY` — static strings per issue body reference implementation
- [ ] Confidence cue state machine matches issue body table exactly:
    - `Gate attempt 1/3 or 2/3` → `· attempt N of 3`
    - `Gate attempt 3/3` → `· attempt 3 of 3 · last chance`
    - `Fix iteration 1/2` → `· iteration 1 of 2`
    - `Fix iteration 2/2` → `· iteration 2 of 2 · last fix`
- [ ] Pace baselines configurable per issue body §Configuration; default values honored (`implementation: 18`, `review: 4`, etc.)
- [ ] Pace color convention matches issue body §Ops-correct colors:
    - 🔵 on pace / advancing / 🟡 slow (2× baseline) / 🔴 stuck (3× baseline) / 🟢 writing
- [ ] Heartbeat reads `.phase-current` from Sprint 1 as truth source — does NOT grep dispatch.log for phase label (more reliable; no false "stuck at 'preparing'" as @zkSoju's comment observed during cycle-092)
- [ ] Path convention: dispatch.log is read from `${CYCLE_DIR}/dispatch.log` per Sprint 1's migration — not the old sibling path
- [ ] `SpiralPhaseComplete` hook fires exactly once per phase (not per Gate attempt within a phase); hook env includes `PHASE`, `COST`, `DURATION_SEC`, `CYCLE_ID`
- [ ] Sprint 2's `IMPL_EVIDENCE_MISSING` verdict surfaces in heartbeat as phase_verb=`🔧 fixing` with intent="missing artifacts: {first 2 paths}" — Sprint 2/4 grammar handshake validated by end-to-end test
- [ ] `format: editor` is default (3-line); `format: compact` and `format: json` are deferred to post-cycle-092 work (documented in `spiral-heartbeat.sh` as TODO; honored in config schema but returns `editor` with warning log for now — per issue body §Suggested sprint scope S5)

### Technical Tasks

- [ ] **Task 4.1**: Author `.claude/scripts/spiral-heartbeat.sh` skeleton: daemon entry point, argument parsing, signal handling (SIGTERM→clean exit); library mode (sourced by tests) vs daemon mode (backgrounded by harness) → **[G-3]**
- [ ] **Task 4.2**: Implement `_emit_heartbeat` (11 keys, reads `.phase-current` + flight-recorder tail + git diff) → **[G-3, G-4]**
- [ ] **Task 4.3**: Implement `_emit_intent` phase→source table + extractors (4 sources); fires only on phase change (compares against last-emitted phase in `.heartbeat-state`) → **[G-3]**
- [ ] **Task 4.4**: Implement `_confidence_cue` dispatch.log parser per state machine table → **[G-3, G-4]**
- [ ] **Task 4.5**: Register `SpiralPhaseComplete` hook in `.claude/hooks/hooks.yaml`; fire from `_emit_dashboard_snapshot` at `PHASE_EXIT` event type (Sprint 3 Task 3.1) → **[G-3]**
- [ ] **Task 4.6**: Add `.loa.config.yaml.example` schema block + write `tests/unit/spiral-heartbeat.bats` covering all 4 acceptance criterion clusters + the E2E cross-sprint test (Sprint 2 verdict → Sprint 4 heartbeat phase_verb handshake) → **[G-3, G-4]**

### Dependencies
- **Sprint 1**: grammar spec reserves `phase-heartbeat-emitted` + `phase-intent-change` shapes; `.phase-current` state file is heartbeat's truth source (not grep of dispatch.log); `dispatch.log` path convention
- **Sprint 2**: `IMPL_EVIDENCE_MISSING` verdict consumed as heartbeat phase_verb input
- **Sprint 3**: `PHASE_EXIT` dashboard event is the `SpiralPhaseComplete` hook trigger

### Security Considerations
- **Trust boundaries**: Heartbeat daemon reads only from cycle-internal state (flight-recorder, `.phase-current`, grimoires feedback files, git diff). No external input. Feedback files are written by LLMs — treat as semi-trusted: intent extractor truncates to 90 chars + strips newlines to prevent injection of fake `[HEARTBEAT]` lines that parsers could mis-attribute.
- **External dependencies**: None added. Pure bash + jq + git.
- **Sensitive data**: Feedback file content could contain credentials if a previous phase leaked them. Intent extractor's 90-char truncation + first-line-only rule bounds exposure; operators should treat dispatch.log as cycle-internal (not published). Documented as known limitation.
- **Hook command injection**: `SpiralPhaseComplete` hook env vars (`$PHASE`, `$COST`) are bash-interpolated into user-configured commands. Values are harness-internal strings (phase label enum, numeric cost) — not user input. Operators configure their own hook commands; responsibility matches Claude Code hooks pattern.

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Heartbeat daemon races with harness, emits stale phase when harness has already transitioned | Med | Low | `.phase-current` mtime check — if older than heartbeat interval × 2, emit `pace=unchanged` rather than stale phase label |
| Intent extractor injection (LLM-written feedback file contains `[HEARTBEAT …]` line that confuses monitors) | Low | Med | Strip newlines + truncate to 90 chars in `_emit_intent`; monitors should use structural parse (field prefix match) not blind regex |
| `SpiralPhaseComplete` hook fires multiple times per phase (once per Gate attempt) | Med | Low | Hook guard: only fires when `PHASE_EXIT` event_type (not `PHASE_HEARTBEAT`); event_type is authoritative (Sprint 3 Task 3.1) |
| Config schema changes break existing `.loa.config.yaml` (additive) | Low | High | Schema is additive only (`spiral.harness.heartbeat.*` is new subtree); missing config falls through to defaults; no existing key renamed |
| Operator enables `format: json` expecting JSON output, gets editor format with warning | Low | Low | S5 deferral is explicitly documented in issue body; config honors with warning is the right UX; post-cycle-092 work adds format dispatcher |

### Success Metrics
- During a 30-min synthetic cycle, heartbeat emits ≥30 lines (60s cadence)
- Each heartbeat carries all 11 keys; missing keys → test failure
- Intent line changes on phase boundary (1 intent per phase transition; not per heartbeat)
- Confidence cue correctly reflects dispatch.log state across 8 scenarios (attempt 1/2/3, fix iter 1/2, circuit-break, clean transition, pre-check)
- E2E: cycle-091 repro → heartbeat at the gate shows `phase_verb=🔧 fixing intent="missing artifacts: src/lib/scenes/Reliquary.svelte, src/routes/(rooms)/reliquary/+page.svelte"`
- `SpiralPhaseComplete` hook fires 6 times on a 6-phase cycle (once per PHASE_EXIT)

---

## Risk Register

| ID | Risk | Sprint | Probability | Impact | Mitigation | Owner |
|----|------|--------|-------------|--------|------------|-------|
| R1 | Path migration breaks external monitors still watching `harness-stderr.log` | 1 | Med | Med | Compat symlink for one cycle; document in CHANGELOG; grep all consumers before rename | Infra |
| R2 | Grammar spec is too narrow — downstream sprints need a shape not declared | 1 | Med | Low | Spec reserves 3 shapes for Sprints 2/3/4; extension requires amendment PR before consumer lands | Infra |
| R3 | `_pre_check_implementation_evidence` false-negative (misses listed artifact) | 2 | High | Med | Test fixtures cover all observed sprint.md formats; new format → parser must extend first | #600 |
| R4 | Heartbeat daemon leaks into operator shell after harness crash | 3, 4 | Med | Med | EXIT trap reaps PID; `trap` belt-and-suspenders; test validates no orphaned daemons after 10 cycles | Infra |
| R5 | Intent extractor injection from LLM-written feedback | 4 | Low | Med | 90-char truncation + newline strip; monitors use structural parse not regex | #598 |
| R6 | Cycle stalls at circuit-break on `IMPL_EVIDENCE_MISSING` → 2 failed fix iterations → operator intervention | 2 | Med | High | Intentional per issue #600 §Suggested fix item 4; circuit-break emits clear actionable verdict line, heartbeat shows `🚨 recovering` (Sprint 4) | Ops |
| R7 | Sprint 1 grammar lands but Sprint 2/3/4 each diverge in edge cases | Cross | Med | High | Shared grammar test fixtures (Sprint 1 Task 1.6); CI requires Sprints 2/3/4 exercise them; any new regex must be declared in grammar spec first | Infra |

---

## Success Metrics Summary

| Metric | Target | Measurement Method | Sprint |
|--------|--------|-------------------|--------|
| cycle-091 scenario repros with `IMPL_EVIDENCE_MISSING` before REVIEW | PASS | Synthetic test fixture | 2 |
| dashboard-latest.json `last_action_ts` advances during 10-min IMPL | +10 updates | Poll every 60s during synthetic cycle | 3 |
| Heartbeat line present in dispatch.log every 60s ±5s | ≥30 heartbeats in 30-min cycle | `grep -c '\[HEARTBEAT' dispatch.log` | 4 |
| Intent line changes on phase boundary | 1 per transition | Grammar test assertion | 4 |
| Grammar test fixtures exercised by all 3 downstream sprints | 100% | CI check: every Sprint 2/3/4 parser consumes fixtures from Sprint 1 | 1 |
| No orphaned background daemons after 10 back-to-back cycles | 0 | `pgrep dashboard-heartbeat\|spiral-heartbeat` after cycle exit | 3, 4 |
| Zero references to `harness-stderr.log` outside compat symlink | 0 | `grep -r harness-stderr.log .claude/` | 1 |

---

## Dependencies Map

```
Sprint 1: Shared infra (grammar + .phase-current + path)
    |
    +--------------> Sprint 2: Artifact-coverage gate (#600)
    |                        |
    |                        +-- IMPL_EVIDENCE_MISSING verdict --+
    |                        |                                   |
    +--------------> Sprint 3: Dashboard mid-phase (#599)        |
    |                        |                                   |
    |                        +-- PHASE_EXIT event -------------+  |
    |                        |                                |  |
    +--------------> Sprint 4: Heartbeat (#598) <-------------+--+
                             (consumes both upstream verdict
                              and PHASE_EXIT hook trigger)
```

---

## Appendix

### A. Issue Body Mapping (in lieu of PRD)

| Issue | Section | Sprint | Status |
|-------|---------|--------|--------|
| #600 §Expected behavior item 1 (parse sprint.md) | Sprint 2 Task 2.1 | 2 | Planned |
| #600 §Expected behavior item 2 (verify exists) | Sprint 2 Task 2.2 | 2 | Planned |
| #600 §Expected behavior item 3 (non-trivial content) | Sprint 2 AC (advisory `IMPL_EVIDENCE_TRIVIAL`) | 2 | Planned |
| #600 §Expected behavior item 4 (fail gate w/ path) | Sprint 2 Task 2.2 | 2 | Planned |
| #600 §Suggested fix item 3 (pre-review evidence gate) | Sprint 2 Task 2.3 | 2 | Planned |
| #600 §Suggested fix item 4 (circuit-break on evidence fail) | Sprint 2 AC + targeted fix-loop max 2 iter | 2 | Planned |
| #599 §Expected item 1 (phase-START write) | Sprint 3 Task 3.1 + Sprint 1 `.phase-current` | 1, 3 | Planned |
| #599 §Expected item 2 (mid-phase heartbeat) | Sprint 3 Task 3.2 | 3 | Planned |
| #599 §Expected item 3 (phase-EXIT authoritative) | Existing behavior preserved via Sprint 3 Task 3.1 | 3 | Planned |
| #599 §Suggested (`.phase-current` state file) | Sprint 1 Task 1.3–1.4 | 1 | Planned |
| #598 §Proposal (`[INTENT]` on change) | Sprint 4 Task 4.3 | 4 | Planned |
| #598 §Proposal (`[HEARTBEAT]` 60s) | Sprint 4 Task 4.2 | 4 | Planned |
| #598 §Confidence cues table | Sprint 4 Task 4.4 | 4 | Planned |
| #598 §Ops-color convention | Sprint 4 Task 4.2 `activity` + `pace` keys | 4 | Planned |
| #598 §Configuration schema | Sprint 4 Task 4.6 | 4 | Planned |
| #598 §Companion hook (`SpiralPhaseComplete`) | Sprint 4 Task 4.5 | 4 | Planned |
| #598 §Suggested sprint scope S1 (heartbeat emitter) | Sprint 4 Task 4.1–4.2 | 4 | Planned |
| #598 §Suggested sprint scope S2 (intent extractor) | Sprint 4 Task 4.3 | 4 | Planned |
| #598 §Suggested sprint scope S3 (confidence-cue parser) | Sprint 4 Task 4.4 | 4 | Planned |
| #598 §Suggested sprint scope S4 (hook + config schema) | Sprint 4 Task 4.5–4.6 | 4 | Planned |
| #598 §Suggested sprint scope S5 (`compact`/`json` formats) | **Deferred** to post-cycle-092 (honored in config schema w/ warning) | — | Deferred |
| #598 Comment (path correction: `${CYCLE_DIR}/dispatch.log`) | Sprint 1 Task 1.5 | 1 | Planned |

### B. SDD Component Mapping (in lieu of SDD — grounded in current harness)

| Existing Component | Sprint | Change |
|--------------------|--------|--------|
| `.claude/scripts/spiral-harness.sh:main()` (line 1099) | 1, 2, 3 | Add `.phase-current` writes, evidence gate, heartbeat daemon spawn |
| `.claude/scripts/spiral-evidence.sh::_pre_check_review` (line 287) | 2 | Sibling `_pre_check_implementation_evidence` function follows same pattern |
| `.claude/scripts/spiral-evidence.sh::_pre_check_seed` (line 387) | 1 | Sibling `_phase_current_write` helpers follow same pattern |
| `.claude/scripts/spiral-evidence.sh::_emit_dashboard_snapshot` (line 653) | 3 | Accept `event_type` arg; spawn daemon for `PHASE_HEARTBEAT` |
| `.claude/scripts/spiral-simstim-dispatch.sh:175` | 1 | `harness-stderr.log` → `dispatch.log` migration |
| `.claude/scripts/spiral-heartbeat.sh` (NEW) | 4 | Standalone emitter daemon + library |
| `.claude/hooks/hooks.yaml` | 4 | Register `SpiralPhaseComplete` hook |
| `.loa.config.yaml.example` | 4 | Add `spiral.harness.heartbeat.*` schema |
| `grimoires/loa/proposals/dispatch-log-grammar.md` (NEW) | 1 | Canonical grammar spec |

### C. Goal Mapping

| Goal ID | Goal Description | Contributing Tasks | Validation |
|---------|------------------|-------------------|------------|
| G-1 | IMPL cannot ship missing SEED-named artifacts | Sprint 2: 2.1, 2.2, 2.3, 2.4 | Sprint 2 synthetic cycle-091 repro test; targeted fix-loop E2E test |
| G-2 | `dashboard-latest.json` reflects in-flight state | Sprint 1: 1.3, 1.4 (`.phase-current`); Sprint 3: 3.1, 3.2, 3.3, 3.4 | Sprint 3 10-min synthetic cycle test: `last_action_ts` increments every 60s |
| G-3 | Operator becomes editor-of-intent via `[HEARTBEAT]` + `[INTENT]` | Sprint 4: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6 | Sprint 4 30-min synthetic cycle: ≥30 heartbeats with 11 keys each; intent changes on phase boundary |
| G-4 | Grammar + path + state-file conventions are shared across all three features | Sprint 1: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6; Sprint 2: 2.5; Sprint 3: 3.4 (fixture reuse); Sprint 4: 4.2, 4.4, 4.6 (fixture reuse) | Sprint 1 grammar test fixtures exercised by Sprints 2/3/4 in CI; no new regex outside grammar spec |

**Goal Coverage Check:**
- [x] All 4 goals have at least one contributing task
- [x] All goals have validation in their respective sprint (no single E2E sprint — validation is distributed per-goal, appropriate for bug/enhancement scope)
- [x] No orphan tasks — every task in Sprints 1–4 maps to ≥1 goal

**Per-Sprint Goal Contribution:**
- Sprint 1: G-2 (foundation), G-3 (foundation), G-4 (primary)
- Sprint 2: G-1 (primary), G-4 (fixture reuse)
- Sprint 3: G-2 (primary), G-4 (fixture reuse)
- Sprint 4: G-3 (primary), G-4 (fixture reuse)

**Cross-sprint E2E validation** (in lieu of a dedicated final E2E sprint, since this is bug/enhancement work against a pre-existing harness):
- Sprint 2's `IMPL_EVIDENCE_MISSING` verdict is consumed by Sprint 4's heartbeat phase_verb extractor; cross-sprint handshake validated by an E2E test in Sprint 4 Task 4.6
- Sprint 3's `PHASE_EXIT` event triggers Sprint 4's `SpiralPhaseComplete` hook; cross-sprint handshake validated by an E2E test in Sprint 4 Task 4.6

### D. Design Decisions (locked)

1. **Shared-infra sprint first, not parallel issue-sprints**: Alternative rejected because parallel sprints would each redefine log-line grammar inconsistently — exactly the class of defect cycle-091 exhibited.
2. **Path migration now, not later**: `harness-stderr.log` → `dispatch.log` is cheap (grep + rename + compat symlink), deferring it would leave the @zkSoju comment's cycle-092 confusion recurring.
3. **`.phase-current` state file over dispatch.log grep**: More reliable (no false "stuck at 'preparing'"), cheaper to parse (single-line stat vs multi-line grep), matches `_pre_check_seed` file-based pattern.
4. **`format: compact | json` deferred to post-cycle-092**: Issue body §Suggested sprint scope S5 explicitly flags these as stretch; keeping `editor` primary preserves the editor-of-intent doctrine, and the config schema honors compact/json with a warning so operators can opt in when it lands.
5. **No separate E2E sprint**: This is bug/enhancement work against an existing harness; E2E validation is distributed per-goal and happens in the sprint that owns each goal, with explicit cross-sprint handshake tests in Sprint 4 Task 4.6. A dedicated E2E sprint would add overhead without additional coverage.
6. **Targeted IMPL fix-loop has 2 iterations max, not 3**: Narrower surface than Review fix-loop → failure after 2 iterations signals operator-context is required (per #600 §Suggested fix item 4 rationale).

---

*Generated by Sprint Planner Agent · Grounded in issues #598, #599, #600 + cycle-088 CHANGELOG entries + current harness source at `.claude/scripts/spiral-harness.sh` and `.claude/scripts/spiral-evidence.sh`*
