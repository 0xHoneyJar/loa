# Dispatch-Log Grammar Specification

**Version:** 1.0
**Cycle:** cycle-092
**Status:** Shared infrastructure — consumed by #598 heartbeat, #599 dashboard writer, #600 evidence gate
**Related:** Sprint 1 of `grimoires/loa/sprint.md` (Tasks T1.1 + T1.2)

## Purpose

The spiral harness (`.claude/scripts/spiral-harness.sh`) emits structured log lines to `dispatch.log` (migrated from `harness-stderr.log`). External consumers — the native heartbeat emitter (#598), the dashboard mid-phase writer (#599), the pre-review evidence gate's verdict surface (#600), and operator monitoring scripts — parse these lines to infer harness state. This document is the canonical grammar spec: it names every line shape, marks stability, and reserves three shapes for downstream sprints.

**Rationale:** Cycle-091 burned $60 of review budget because sibling features (#598, #599, #600) each re-derived the log-line format inconsistently. Shipping the grammar spec first, shared-infra-style, prevents that repeat.

## Line prefix convention

All harness log output prefixes with `[harness] ` via the `log()` function at `.claude/scripts/spiral-harness.sh:176`:

```bash
log() { echo "[harness] $*" >&2; }
```

ERROR-class output uses the `error()` function which prefixes with `ERROR: ` (no `[harness]` prefix). The `[harness]` prefix is an informational hint — it identifies source but is not itself load-bearing; parsers should match on shape content, not the prefix alone.

## Stability API tiers

Each shape is classified by consumer-contract stability:

| Tier | Marker | Meaning | Change policy |
|------|--------|---------|---------------|
| **API** | `stability: API` | External consumers (monitors, dashboard, heartbeat) parse these | Breaking changes require grammar spec amendment PR + downstream updates |
| **Internal** | `stability: internal` | Harness-internal signaling; monitors MAY parse advisory-only | Free to rename/remove |
| **Reserved** | `stability: reserved` | Declared but not yet emitted; owned by a downstream sprint | Sprint that owns the shape lands the emit |

## Path convention

### Current state (pre-cycle-092)

The harness stderr is redirected to a **sibling** of the cycle directory:

```
.run/cycles/cycle-092-dispatch.log       ← sibling (old, harness-stderr.log)
.run/cycles/cycle-092/flight-recorder.jsonl  ← inside cycle dir
.run/cycles/cycle-092/dashboard-latest.json  ← inside cycle dir
```

**Source:** `.claude/scripts/spiral-simstim-dispatch.sh:175` — `2>"$cycle_dir/harness-stderr.log"`.

### Post-cycle-092 state (this spec)

Migrate to **inside-cycle-dir** for uniformity:

```
.run/cycles/cycle-092/dispatch.log          ← new, inside cycle dir
.run/cycles/cycle-092/flight-recorder.jsonl
.run/cycles/cycle-092/dashboard-latest.json
.run/cycles/cycle-092/.phase-current        ← new (Sprint 1 Task 1.3–1.4)
```

**Migration plan (Task 1.5):**

1. Change `spiral-simstim-dispatch.sh:175` redirection target to `$cycle_dir/dispatch.log`.
2. For one cycle (cycle-092 + cycle-093 transition window), create a compat symlink:
   ```bash
   ln -sf dispatch.log "$cycle_dir/harness-stderr.log"
   ```
3. After cycle-093 ships clean, drop the compat symlink.

**Why:** Per @zkSoju's cycle-092 comment on #598 — the reference-implementation monitor got stuck at `⚙️ preparing` for 5 pulses because its grep targeted the wrong path. One convention, one truth source, eliminates that class of defect.

## `.phase-current` state file

New state file written by Sprint 1 Task 1.3 helpers. Single truth source for monitors asking "what phase is the harness in right now?".

### Path

`$CYCLE_DIR/.phase-current` (e.g., `.run/cycles/cycle-092/.phase-current`)

### Format

Single line, tab-separated, 4 fields:

```
<phase_label>\t<start_ts>\t<attempt_num>\t<fix_iter>
```

Example:
```
REVIEW	2026-04-19T07:22:00Z	2	1
```

| Field | Type | Default | Meaning |
|-------|------|---------|---------|
| `phase_label` | enum | _(required)_ | One of: `PRE_CHECK_SEED`, `DISCOVERY`, `FLATLINE_PRD`, `ARCHITECTURE`, `FLATLINE_SDD`, `PLANNING`, `FLATLINE_SPRINT`, `PRE_CHECK_IMPL`, `IMPLEMENT`, `PRE_CHECK_IMPL_EVIDENCE`, `PRE_CHECK_REVIEW`, `REVIEW`, `AUDIT`, `PR_CREATION`, `BRIDGEBUILDER`, `BB_FIX_LOOP`, `IMPL_FIX` |
| `start_ts` | ISO-8601 | _(required)_ | UTC timestamp of phase entry. Source for kaironic-clock calculation |
| `attempt_num` | int\|`-` | `-` | For gated phases (REVIEW, AUDIT, FLATLINE_*): current attempt within `_run_gate` 1..`MAX_RETRIES`. `-` for non-gated |
| `fix_iter` | int\|`-` | `-` | For review fix loop: current iteration 1..`REVIEW_MAX_ITERATIONS`. `-` outside fix loop |

### Lifecycle

| Event | Action | Called by |
|-------|--------|-----------|
| Phase START | Write new line (overwrites previous state) | `_phase_current_write` from spiral-harness.sh main() |
| Phase sub-event (attempt/iter change) | Update attempt_num/fix_iter fields | `_phase_current_touch` from `_run_gate`, `_review_fix_loop` |
| Phase EXIT (success or failure) | Remove file | `_phase_current_clear` from EXIT trap + explicit exit paths |
| Harness crash / abnormal exit | Remove file | `trap '... _phase_current_clear ...' EXIT` in main() |

**Invariant:** The presence of `.phase-current` implies "a phase is in-flight right now." Monitors reading a missing file interpret as "harness idle or exited."

**Staleness tolerance:** Monitors MAY treat an mtime older than `2 × baseline_sec` for the phase as suspected-stuck and surface a `🔴 stuck` signal (Sprint 4 #598). The file itself is not a heartbeat — use `flight-recorder.jsonl` tail for heartbeat cost/progress.

## Current line shapes

The following table enumerates every line shape currently emitted by `.claude/scripts/spiral-harness.sh` at cycle-092.

### Harness lifecycle

| Shape | Line | Regex (anchors optional) | Stability | Example |
|-------|------|--------------------------|-----------|---------|
| `harness-start` | 230 | `^\[harness\] Harness starting: cycle=\S+ branch=\S+ budget=\$\S+ profile=\S+$` | API | `[harness] Harness starting: cycle=cycle-092 branch=feat/foo budget=$10 profile=standard` |
| `harness-config` | 231 | `^\[harness\] Flatline gates: \S+\s+Advisor: \S+$` | internal | `[harness] Flatline gates: sprint  Advisor: opus` |
| `harness-complete` | 1260 | `^\[harness\] Harness complete: cycle=\S+ profile=\S+ cost=\$\S+$` | API | `[harness] Harness complete: cycle=cycle-092 profile=standard cost=$24.50` |
| `harness-evidence-path` | 1261–1263 | `^\[harness\] (Flight recorder\|Evidence\|PR): ` | internal | `[harness] Flight recorder: .run/cycles/cycle-092/flight-recorder.jsonl` |

### Phase transitions

Every `_phase_*` function in main() is preceded by a `phase-transition` line. Phase labels map to the Sprint 4 heartbeat's `phase_verb`:

| Shape | Line | Regex | Stability | Example |
|-------|------|-------|-----------|---------|
| `phase-transition` | 1122, 1137, 1152, 1172, 1210 | `^\[harness\] Phase [1-6]: [A-Z_ ]+$` | API | `[harness] Phase 4: IMPLEMENTATION` |

Phase number → label mapping (fixed):

| N | Label | `_emit_dashboard_snapshot` arg |
|---|-------|--------------------------------|
| 1 | DISCOVERY | `DISCOVERY` |
| 2 | ARCHITECTURE | `ARCHITECTURE` |
| 3 | PLANNING | `PLANNING` |
| 4 | IMPLEMENTATION | `IMPLEMENT` |
| 5 | PR CREATION | — (not a dashboard event) |
| 6 | BB FIX LOOP | — (internal phase, no public transition) |

### Pre-checks

| Shape | Line | Regex | Stability | Example |
|-------|------|-------|-----------|---------|
| `pre-check-start` | 1115, 1165, 1187 | `^\[harness\] Pre-check: ` | API | `[harness] Pre-check: validating implementation before review` |

Current pre-check sites: SEED env (1115), planning artifacts (1165), implementation pre-review (1187). Sprint 2 Task 2.3 adds a 4th: `Pre-check: validating implementation artifact coverage` (see [Reserved shapes](#reserved-shapes)).

### Gates (via `_run_gate`)

| Shape | Line | Regex | Stability | Example |
|-------|------|-------|-----------|---------|
| `gate-attempt` | 524 | `^\[harness\] Gate: \S+ \(attempt \d+/\d+\)$` | API | `[harness] Gate: REVIEW (attempt 2/3)` |
| `gate-attempt-retry` | 531 | `^\[harness\] Gate \S+ failed \(attempt \d+\), will retry\.\.\.$` | API | `[harness] Gate REVIEW failed (attempt 1), will retry...` |
| `gate-flatline` | 427 | `^\[harness\] Gate: Flatline \S+ review on \S+$` | internal | `[harness] Gate: Flatline prd review on grimoires/loa/prd.md` |
| `gate-flatline-failed-invalid` | 440 | `^\[harness\] Gate FAILED: Flatline \S+ — invalid output$` | internal | `[harness] Gate FAILED: Flatline prd — invalid output` |
| `gate-flatline-passed` | 444 | `^\[harness\] Gate PASSED: Flatline \S+ \(\S+, \d+ms\)$` | internal | `[harness] Gate PASSED: Flatline prd (HIGH_CONSENSUS, 3200ms)` |
| `gate-independent-review` | 460 | `^\[harness\] Gate: Independent review \(fresh session, model=\S+\)$` | API | `[harness] Gate: Independent review (fresh session, model=opus)` |
| `gate-independent-audit` | 478 | `^\[harness\] Gate: Independent security audit \(fresh session, model=\S+\)$` | API | `[harness] Gate: Independent security audit (fresh session, model=opus)` |
| `gate-bridgebuilder` | 494 | `^\[harness\] Gate: Bridgebuilder PR review$` | internal | `[harness] Gate: Bridgebuilder PR review` |

### Review fix loop

| Shape | Line | Regex | Stability | Example |
|-------|------|-------|-----------|---------|
| `review-fix-iteration` | 390 | `^\[harness\] Review fix loop: iteration \d+/\d+$` | API | `[harness] Review fix loop: iteration 2/2` |
| `review-passed-iter` | 393 | `^\[harness\] Review PASSED on iteration \d+/\d+$` | API | `[harness] Review PASSED on iteration 2/2` |
| `review-fix-loop-exhausted` | 398 | `^\[harness\] Review FAILED: exhausted \d+ fix iterations$` | API | `[harness] Review FAILED: exhausted 2 fix iterations` |
| `review-changes-required-dispatch` | 404 | `^\[harness\] Review CHANGES_REQUIRED — dispatching implementation fix \(iteration \d+/\d+\)$` | API | `[harness] Review CHANGES_REQUIRED — dispatching implementation fix (iteration 2/2)` |
| `review-fix-implementation-failed` | 409 | `^\[harness\] Review fix loop: implementation-fix pass FAILED at iteration \d+$` | internal | `[harness] Review fix loop: implementation-fix pass FAILED at iteration 1` |

### Terminal verdicts

| Shape | Line | Regex | Stability | Example |
|-------|------|-------|-----------|---------|
| `review-changes-required-terminal` | 1199 | `^\[harness\] Review CHANGES_REQUIRED — implementation needs work \(fix loop exhausted\)$` | API | `[harness] Review CHANGES_REQUIRED — implementation needs work (fix loop exhausted)` |
| `audit-changes-required-terminal` | 1205 | `^\[harness\] Audit CHANGES_REQUIRED — security issues found$` | API | `[harness] Audit CHANGES_REQUIRED — security issues found` |
| `circuit-breaker-trip` | 537 (via `error`) | `^ERROR: Circuit breaker: \S+ failed after \d+ attempts$` | API | `ERROR: Circuit breaker: REVIEW failed after 3 attempts` |

**Note:** `circuit-breaker-trip` uses the `error()` function, not `log()`. Output prefix is `ERROR:` not `[harness]`. Monitors parsing terminal state must check both prefixes.

### PR creation

| Shape | Line | Regex | Stability | Example |
|-------|------|-------|-----------|---------|
| `pr-reused` | 1216 | `^\[harness\] Reusing existing PR: https://\S+$` | API | `[harness] Reusing existing PR: https://github.com/0xHoneyJar/loa/pull/597` |
| `pr-created` | 1230 | `^\[harness\] PR created: https://\S+$` | API | `[harness] PR created: https://github.com/0xHoneyJar/loa/pull/597` |
| `pr-create-failed` | 1232 | `^\[harness\] WARNING: PR creation failed, continuing$` | internal | `[harness] WARNING: PR creation failed, continuing` |

### Profile / skipping

| Shape | Line | Regex | Stability | Example |
|-------|------|-------|-----------|---------|
| `flatline-skipped` | 1132, 1147, 1160 | `^\[harness\] Skipping Flatline \S+ \(profile=\S+\)$` | internal | `[harness] Skipping Flatline prd (profile=light)` |
| `profile-auto-escalation` | 157, 167 | `^\[harness\] Auto-escalating profile:` | internal | `[harness] Auto-escalating profile: light → full (reason: security-sensitive-paths)` |
| `profile-unknown` | 120 | `^\[harness\] Unknown profile '\S+', falling back to standard$` | internal | `[harness] Unknown profile 'x', falling back to standard` |

### BB fix loop

| Shape | Line | Regex | Stability | Example |
|-------|------|-------|-----------|---------|
| `bb-loop-start` | 881 | `^\[harness\] BB Fix Loop starting: iter=\d+ spend=\$\S+ budget=\$\S+ max_iters=\d+$` | internal | `[harness] BB Fix Loop starting: iter=0 spend=$0 budget=$3 max_iters=3` |
| `bb-loop-complete` | 1067 | `^\[harness\] BB Fix Loop complete: reason=\S+ iters=\d+ spend=\$\S+$` | internal | `[harness] BB Fix Loop complete: reason=convergence iters=2 spend=$1.80` |
| `bb-loop-already-complete` | 844 | `^\[harness\] BB fix loop already complete` | internal | — |
| `bb-stuck-finding` | 650 | `^\[harness\] Stuck finding detected: \S+ \(severity=\d+, iter=\d+\)$` | internal | — |
| `bb-triage-summary` | 609 | `^\[harness\] Triage complete: \d+ actionable, \d+ non-actionable$` | internal | — |

### Informational passthrough

Catch-all shapes covering every `log()` line that isn't named above — including warnings, advisories, BB lifecycle edge cases, and edge-case logs whose exact text is not a consumer contract. Declared so the Sprint 1 AC ("grammar spec enumerates every current `log()` line") is satisfied in spirit and a grammar-coverage bats test can validate zero uncategorized lines.

| Shape | Line range | Regex | Stability | Example |
|-------|------------|-------|-----------|---------|
| `warning-passthrough` | various — any `log "WARNING: ..."` | `^\[harness\] WARNING:` | internal | `[harness] WARNING: Implementation touched security-sensitive paths but profile=light (not full)` |
| `error-passthrough` | various — any `log "ERROR: ..."` (see note) | `^\[harness\] ERROR:` | internal | `[harness] ERROR: Fix cycle changed branch (feat/foo != feat/bar), skipping push` |
| `informational` | any `log` line not matching a named shape | `^\[harness\] ` | internal | `[harness] Arbiter: 2 blockers to arbitrate` |

**Note on error prefixes:** `[harness] ERROR:` (emitted via `log()`) is distinct from the `ERROR:` prefix emitted by `error()` (the `circuit-breaker-trip` shape). Monitors checking for error-class signals should match both:

- `^\[harness\] ERROR:` — non-fatal error via `log()` (cycle continues, but with a warning)
- `^ERROR: ` — fatal error via `error()` (about to exit or circuit-break)

**Monitor contract:** Informational-tier lines are NOT a stability contract. Their exact text MAY change between harness releases without a grammar spec amendment. Monitors SHOULD NOT grep these lines for specific substrings; display-only consumption is fine.

### Evidence gates

Pre-review artifact-coverage gate declared by Sprint 2 (#600). Emitted by `_pre_check_implementation_evidence` in `.claude/scripts/spiral-evidence.sh` after the implementation phase commits — validates that every SEED-enumerated deliverable path from `grimoires/loa/sprint.md` exists non-empty on disk. On failure, `_impl_evidence_fix_loop` in `.claude/scripts/spiral-harness.sh` re-dispatches IMPL (max 2 iterations) before circuit-breaking.

| Shape | Line / site | Regex | Stability | Example |
|-------|-------------|-------|-----------|---------|
| `impl-evidence-missing` | `.claude/scripts/spiral-evidence.sh:_pre_check_implementation_evidence` | `^\[harness\] IMPL_EVIDENCE_MISSING — [0-9]+ sprint-plan paths not produced: \S+` | API | `[harness] IMPL_EVIDENCE_MISSING — 2 sprint-plan paths not produced: src/lib/scenes/Reliquary.svelte,src/routes/(rooms)/reliquary/+page.svelte` |
| `impl-evidence-trivial` | advisory emitted alongside `impl-evidence-missing` when paths exist but <20 lines or match known-stub regex | `^\[harness\] IMPL_EVIDENCE_TRIVIAL — [0-9]+ paths below content threshold: \S+` | API | `[harness] IMPL_EVIDENCE_TRIVIAL — 1 paths below content threshold: src/lib/stub.ts` |

**Stability contract**: Both shapes are API-stable. Heartbeat emitters (#598 Sprint 4) read `impl-evidence-missing` payload via flight-recorder `verdict` field (format `FAIL:N_missing:path1,path2,...`) to surface `phase_verb=🔧 fixing intent="missing artifacts: ..."`. Monitors parsing the log line may assume comma-separated path list and stable preamble.

## Reserved shapes

Two shapes reserved by Sprint 1 for Sprints 3/4. The downstream sprint owns the emit site; the grammar spec reserves the name + shape to prevent divergence.

| Shape | Sprint | Line (proposed) | Regex | Stability | Example |
|-------|--------|-----------------|-------|-----------|---------|
| `phase-heartbeat-emitted` | 4 (#598) | Sprint 4 `spiral-heartbeat.sh` | `^\[HEARTBEAT [^\]]+\] phase=\S+ phase_verb=\S+ .+$` | reserved → API | `[HEARTBEAT 2026-04-19T07:22:00Z] phase=REVIEW phase_verb=reviewing phase_elapsed_sec=180 total_elapsed_sec=3900 cost_usd=70.00 budget_usd=80 files=44 ins=7696 del=4882 activity=quiet confidence=attempt_2_of_3 pace=on_pace` |
| `phase-intent-change` | 4 (#598) | Sprint 4 `spiral-heartbeat.sh`, fires on phase boundary | `^\[INTENT [^\]]+\] phase=\S+ intent="[^"]+" source=\S+$` | reserved → API | `[INTENT 2026-04-19T07:22:00Z] phase=REVIEW intent="checking amendment compliance against the implementation" source=grimoires/loa/a2a/engineer-feedback.md` |
| `phase-current-cleared` | 3 (#599) | EXIT trap in spiral-harness.sh main() | `^\[harness\] .phase-current cleared$` | reserved → internal | `[harness] .phase-current cleared` |

## Grammar extension policy

Adding a new line shape requires a two-step PR:

1. **Grammar spec amendment** — add row to this document's shape table, pick a stability tier, document the emit site and example.
2. **Consumer update** (same PR or subsequent) — update any monitor, heartbeat, or dashboard consumer that parses log lines to recognize the new shape.

**Forbidden:** Emitting a line that looks structured (key=value pairs, `[harness]`/`[HEARTBEAT]` prefix) but is not declared here. Free-form warnings and errors are fine — those are informational and monitors ignore them unless they start with `ERROR:`.

## Field stability guarantees

For shapes marked `stability: API`, consumers can rely on these invariants:

- **Prefix:** `[harness] ` or `ERROR: ` is stable across patches
- **Ordering:** Keys in key=value payloads appear in the order declared above
- **Separator:** Tabs within `.phase-current`; single spaces between key=value pairs in heartbeat lines
- **Whitespace:** No leading/trailing whitespace on the line body; no mid-value whitespace

Breaking any of the above is a grammar spec amendment (major version bump of this document).

## Cross-consumer invariants

Monitors consuming this grammar MUST:

1. **Not rely on line number / file offset** — grep-and-line-number is brittle across harness edits. Match on shape regex only.
2. **Not interpolate user input into grep patterns** — phase labels, cycle IDs, PR URLs are untrusted. Use fixed regex + capture groups.
3. **Tolerate unknown shapes** — if a line matches `^\[harness\] ` but no known shape, log it as informational and continue. Do NOT halt on unknown shapes.
4. **Prefer `.phase-current` over dispatch.log grep for "current phase" queries** — more reliable, cheaper, matches Sprint 1 design decision D.3.

## Version history

| Version | Date | Change |
|---------|------|--------|
| 1.0 | 2026-04-19 | Initial grammar spec. Audit inventory of current shapes. 5 reserved shapes for Sprints 2–4. Path convention migration. Documented in `.claude/rules/...` references TBD when Sprint 1 lands. |

## See also

- **Sprint plan:** `grimoires/loa/sprint.md` Sprint 1 (lines 65–119)
- **Issues:** [#598 heartbeat](https://github.com/0xHoneyJar/loa/issues/598), [#599 dashboard](https://github.com/0xHoneyJar/loa/issues/599), [#600 evidence gate](https://github.com/0xHoneyJar/loa/issues/600)
- **Existing infrastructure:**
  - `.claude/scripts/spiral-harness.sh:176` — `log()` definition
  - `.claude/scripts/spiral-evidence.sh:387` — `_pre_check_seed` pattern that `.phase-current` helpers mirror
  - `.claude/scripts/spiral-evidence.sh:653` — `_emit_dashboard_snapshot` (Sprint 3 extends)
  - `.claude/scripts/spiral-simstim-dispatch.sh:175` — dispatch log redirection (Sprint 1 Task 1.5 migrates)
- **Prior art:** RFC-062 `grimoires/loa/proposals/rfc-062-seed-seam-autopoiesis.md` (sibling doctrine, seed-seam editor-of-intent)
