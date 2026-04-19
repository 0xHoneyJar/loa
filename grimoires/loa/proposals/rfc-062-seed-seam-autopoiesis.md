# RFC-062: SEED Seam Autopoiesis — Auto-Drafting + Failure-Dependency Gating

**Status**: DRAFT (design phase)
**Authors**: Claude Opus 4.7 (drafting) on behalf of operator work plan
**Date**: 2026-04-19
**Cycle**: 089 (SEED-seam autopoiesis design)
**Related**:
- #575 (umbrella, 6-primitive RFC from three-lens audit)
- RFC-060 (spiral meta-orchestrator)
- Items 2, 3, 5, 6 shipped in v1.96.2 / v1.99.1 / v1.99.2 / v1.101.0
**Supersedes**: nothing — additive

---

## Problem Statement

After RFC-060 shipped `/spiral` and items 2, 3, 5, 6 from #575 closed the visible friction points, the autopoietic loop is now tight from **SEED-authored → HARVESTed → discovery context** but still **hand-authored at the SEED boundary itself**.

Concretely:

- HARVEST (`spiral-harvest-adapter.sh`) produces a typed `cycle-outcome.json` sidecar with review verdicts, audit verdicts, findings, flatline signatures, content hashes.
- The next cycle's discovery phase can now ingest the prior flight-recorder (#575 item 2) and runs behind a CWD/invariant gate (#575 item 3).
- But the **SEED itself** — the operator's statement of cycle-N+1 intent — is not informed by HARVEST output. Operator hand-composes intent; HARVEST outputs sit in typed queues; no bridge connects them.

The RFC quote:

> *"tool informs build informs tool. Entropy is drift toward one-shot linearity; iteration is the remedy."*

Today the arrow from **build back to tool** is load-bearing at the artifact seam (code + lore + visions + bugs all route back in) but **null at the intent seam**. The operator still carries the cognitive load of "what should cycle-N+1 actually pursue given cycle-N's outcomes." This RFC closes that gap.

Two primitives from #575 address it together:

### Item 1 — Auto-SEED-from-HARVEST

**K-hole's `--trail` as architectural precedent**: in the research-descent tool, each dig's `pull_threads` + `emergence` fields auto-seed the next dig. The operator edits a scaffolded query, doesn't compose one from scratch. Port this to `/spiral`:

- HARVEST emits `pull_threads` (open questions the cycle surfaced but didn't answer) and `emergence` (unexpected patterns / adjacent problems that showed up in review/audit).
- EVALUATE phase writes `.run/cycles/cycle-NNN/seed-draft.md` — a scaffolded successor SEED.
- Next cycle's start reads the draft as the operator's default task-seed (operator can accept / edit / discard).

### Item 4 — Failure-Typed Bead Escalation as SEED Hard-Dep

**"Membrane repair primitive"**: when cycle-N trips a circuit breaker, that failure needs to propagate to cycle-N+1 as a hard precondition — not a soft signal buried in flight-recorder.

- Circuit breaker trip autogenerates a typed beads task with classification (`scope-mismatch` / `cwd-mismatch` / `review-fix-exhausted` / `budget-exhausted` / `flatline-stuck`).
- Next spiral dispatch checks for unresolved failure beads. If any exist and `spiral.seed.skip_failure_deps` ≠ true, the dispatch is blocked with an actionable message.
- Operator must **resolve the bead** (fix or explicit defer-with-rationale) before cycle-N+1 starts. System cannot advance past its own wounds unacknowledged.

### Composition claim

The two primitives together shift operator role from *"composer of intent"* to *"reviewer of auto-drafted successor state with mandatory acknowledgment of prior failures"*. Semantically equivalent to HITL; mechanically autopoietic.

---

## Goals

- **G1** — Close the intent-seam loop: auto-draft cycle-N+1 SEED from cycle-N HARVEST so operator can default-accept instead of default-compose.
- **G2** — Make prior-cycle failures load-bearing on next-cycle dispatch: typed beads + hard dependency gate.
- **G3** — Preserve operator autonomy: every auto-drafted SEED is editable; every failure gate has an explicit defer-with-rationale escape hatch.
- **G4** — Backwards compatibility: existing operators who don't want auto-drafting or failure gating see no behavior change (both features default off).
- **G5** — Schema versioning: HARVEST sidecar extensions follow explicit semver + `$schema_version` bumps with validators accepting both old and new.

## Non-Goals

- **NG1** — Full agency: the system does not dispatch cycle-N+1 without operator trigger. Auto-drafting happens at EVALUATE; dispatching still requires `/spiral --start` or `--resume`.
- **NG2** — Failure auto-fix: the system diagnoses + classifies circuit breaks into beads but does not attempt fixes. Human work remains.
- **NG3** — Vision/lore promotion: already shipped via `post-merge-orchestrator.sh` + `vision-registry` — out of scope here.
- **NG4** — Beads replacement: this RFC extends existing beads patterns, doesn't propose a new tracker.
- **NG5** — Multi-operator coordination: single-operator semantics only. Team-mode considerations deferred.

---

## Design

### Part 1 — Auto-SEED-from-HARVEST (#575 item 1)

#### 1.1 HARVEST sidecar schema extension (`$schema_version: 2`)

Current `cycle-outcome.json` (schema v1):

```jsonc
{
  "$schema_version": 1,
  "cycle_id": "cycle-088",
  "review_verdict": "APPROVED",
  "audit_verdict": "APPROVED",
  "findings": { "blocker": 0, "high": 2, "medium": 5, "low": 3 },
  "artifacts": { "reviewer_md": "...", "auditor_md": "...", "pr_url": "..." },
  "flatline_signature": "...",
  "content_hash": "sha256:...",
  "elapsed_sec": 3421,
  "exit_status": "success"
}
```

Proposed schema v2 adds two optional fields:

```jsonc
{
  "$schema_version": 2,
  "cycle_id": "cycle-088",
  // ... all v1 fields unchanged ...

  "pull_threads": [
    {
      "id": "pt-001",
      "source": "review|audit|flatline|bridgebuilder|operator",
      "question": "string (50-500 chars)",
      "severity": "blocking|high|medium|low|curiosity",
      "cite": "file:line or artifact reference"
    }
  ],

  "emergence": [
    {
      "id": "em-001",
      "source": "review|audit|flatline|bridgebuilder",
      "pattern": "string (50-500 chars) — the unexpected thing",
      "adjacent_to": "string (what problem this is near)",
      "confidence": "speculative|observed|confirmed"
    }
  ]
}
```

Both arrays may be empty. Consumers MUST tolerate missing fields (schema v1 compat).

#### 1.2 Pull-thread + emergence source attribution

Three fields populate automatically at HARVEST time; all via existing infrastructure:

| Source | Signal | Extraction |
|--------|--------|------------|
| **review** | reviewer.md has sections like `## Open Questions` or lines starting with `? ` | Regex scan |
| **audit** | auditor-sprint-feedback.md `DEFERRED` rows | Existing parser extracts already |
| **flatline** | DISPUTED findings that didn't reach consensus | Read `flatline-*.json`, filter consensus !== HIGH_CONSENSUS |
| **bridgebuilder** | `SPECULATION` or `VISION` severity findings | Already classified by `post-pr-triage.sh` |
| **operator** | Operator CAN append `pull_threads` to the sidecar post-hoc via `spiral-harvest-adapter.sh --append-thread` | New CLI flag |

Emergence is narrower — only surfaces when the REVIEW or AUDIT agent explicitly uses a `**Emergence**:` or `**Unexpected**:` markdown label, OR when Bridgebuilder tagged `teachable_moment` on a finding. Conservative default: empty unless agents opt in.

#### 1.3 EVALUATE phase writes `seed-draft.md`

New function `_emit_seed_draft(cycle_dir)` in `spiral-harness.sh` (or a new `spiral-seed-drafter.sh` if scope grows):

```bash
_emit_seed_draft() {
    local cycle_dir="$1"
    local sidecar="$cycle_dir/cycle-outcome.json"

    # Feature gate
    local enabled
    enabled=$(_read_harness_config "spiral.seed.auto_draft" "false")
    [[ "$enabled" != "true" ]] && return 0

    [[ ! -f "$sidecar" ]] && return 0

    # Compose seed-draft.md via templated jq query over the sidecar
    local draft_path="$cycle_dir/seed-draft.md"
    _render_seed_draft "$sidecar" > "$draft_path"
    log "SEED draft written: $draft_path (editable — operator may accept or revise)"
}
```

Template (markdown with jq-produced bullets):

```markdown
# SEED draft — <cycle_id+1>

> Auto-drafted from cycle-<cycle_id> HARVEST output.
> Edit freely. Operator-authored sections override auto-drafted ones.

## Context from prior cycle

- Prior cycle: <cycle_id>, verdict: <review_verdict>/<audit_verdict>
- Elapsed: <elapsed_sec>s, findings: <blocker>B/<high>H/<medium>M/<low>L

## Open threads (from review + audit)

<!-- BEGIN_PULL_THREADS -->
<for each pull_thread:>
- **[<severity>]** <question>
  - Source: <source>, cite: `<cite>`
</for>
<!-- END_PULL_THREADS -->

## Emergence observed

<!-- BEGIN_EMERGENCE -->
<for each emergence:>
- **<pattern>** (adjacent to <adjacent_to>; confidence: <confidence>)
  - Source: <source>
</for>
<!-- END_EMERGENCE -->

## Proposed cycle-<cycle_id+1> intent

<!-- OPERATOR: replace this section with your authored intent, or accept the scaffold below -->

_Auto-scaffold: address blocking pull-threads (<count>) while observing emergence (<count>) for follow-up investigation._

---

## Provenance

- Source sidecar: `<sidecar_path>`
- Schema version: <schema_version>
- Drafted at: <ISO-8601>
```

#### 1.4 Next-cycle dispatch reads the draft

`spiral-orchestrator.sh cmd_start` accepts a new flag:

```bash
/spiral --start --seed-from-draft .run/cycles/cycle-088/seed-draft.md
```

When present, the harness uses the draft as `SEED_CONTEXT` (standard precedent). The operator can:
- `--seed-from-draft <path>` — explicit acceptance
- `--seed-from-draft <path> --edit` — opens `$EDITOR` for review-and-edit before dispatch
- No flag — existing behavior (operator hand-composes the task argument or uses their own SEED)

Operator role: **editor, not author**. They review the draft's `## Proposed cycle-NNN intent` section, edit if needed, dispatch.

#### 1.5 Vision-registry integration

If the vision registry has entries tagged with `[ACTIONABLE]` and created during cycle-N, the EVALUATE phase optionally includes them in the draft's `## Emergence observed` section. This closes one loop that was called out in #575:

> *"The vision registry captures speculative insights but none have ever been explored."*

Now auto-drafted SEEDs naturally surface actionable visions as emergence for next cycle's consideration.

Feature gate: `spiral.seed.include_visions: true` (distinct from `auto_draft`). Default off initially.

### Part 2 — Failure-Typed Bead Escalation (#575 item 4)

#### 2.1 Circuit-breaker → bead creation

`spiral-harness.sh _run_gate` currently logs `_record_failure "$gate_name" "CIRCUIT_BREAKER" "Failed after $MAX_RETRIES attempts"` and exits. Extend this path:

```bash
_handle_circuit_break() {
    local gate_name="$1"
    local classification="$2"  # scope-mismatch | cwd-mismatch | review-fix-exhausted | budget-exhausted | flatline-stuck | other
    local detail="$3"

    # Existing flight-recorder action (kept)
    _record_failure "$gate_name" "CIRCUIT_BREAKER" "$detail"

    # New: create typed bead if beads available + enabled
    local enabled
    enabled=$(_read_harness_config "spiral.failure_beads.enabled" "false")
    [[ "$enabled" != "true" ]] && return 0

    if command -v br &>/dev/null; then
        _create_failure_bead "$gate_name" "$classification" "$detail"
    else
        log "WARN: beads not available; failure not persisted as a dependency"
    fi
}

_create_failure_bead() {
    local gate_name="$1"
    local classification="$2"
    local detail="$3"

    local title="Spiral circuit break: $gate_name ($classification)"
    local body
    body=$(cat <<EOF
**Gate**: $gate_name
**Classification**: $classification
**Detail**: $detail
**Cycle**: $CYCLE_ID
**Flight recorder**: $CYCLE_DIR/flight-recorder.jsonl

This bead was auto-created by /spiral on circuit break. It MUST be resolved
or explicitly deferred before the next spiral dispatch.

## Resolution options

1. **Fix**: investigate + patch the root cause, then \`br close <id>\`
2. **Defer with rationale**: \`br update <id> --label spiral:deferred\` +
   comment explaining why this is safe to defer
EOF
)

    br create --type bug \
        --title "$title" \
        --priority high \
        --label "spiral:circuit-break,spiral:$classification" \
        --description "$body"
}
```

#### 2.2 Classification taxonomy

The classification field is a controlled vocabulary (extensible but stable):

| Classification | Trigger | Resolution pattern |
|---------------|---------|-------------------|
| `scope-mismatch` | REVIEW verdict `CHANGES_REQUIRED` persists >= MAX_RETRIES on scope-level critique (not implementation defect) | Split cycle into smaller scope OR escalate to RFC |
| `cwd-mismatch` | `_pre_check_seed` fails (from RFC-062 part 0) | Rerun from correct CWD |
| `review-fix-exhausted` | `_review_fix_loop` hits `REVIEW_MAX_ITERATIONS` without APPROVED | Manual code intervention OR scope-split |
| `budget-exhausted` | `cost_budget_exhausted` fires before phase completion | Increase budget OR reduce scope |
| `flatline-stuck` | Flatline DISPUTED findings don't resolve across iterations | Operator acceptance of disputed state OR RFC for structural fix |
| `other` | Catchall for circuit breaks that don't match above | Investigate, then retroactively add classification |

The controlled vocabulary lives in `.claude/data/spiral-failure-classifications.yaml` with a regex pattern per class used by `_classify_failure()` to auto-populate from flight-recorder verdict text.

#### 2.3 Dispatch-time gate

New `_pre_dispatch_failure_check()` function called at spiral `cmd_start`:

```bash
_pre_dispatch_failure_check() {
    # Feature gate
    local enabled
    enabled=$(_read_harness_config "spiral.failure_beads.enforce_on_dispatch" "false")
    [[ "$enabled" != "true" ]] && return 0

    # Escape hatch
    [[ "${SPIRAL_SKIP_FAILURE_DEPS:-false}" == "true" ]] && {
        log "SPIRAL_SKIP_FAILURE_DEPS=true — skipping failure-bead check (recorded in trajectory)"
        _record_action "DISPATCH" "spiral-orchestrator" "skip_failure_deps" "" "" "" 0 0 0 "operator_override"
        return 0
    }

    # Check for unresolved failure beads
    local unresolved
    if ! command -v br &>/dev/null; then
        log "WARN: beads not installed; cannot enforce failure dependencies (install with: cargo install beads_rust)"
        return 0
    fi

    unresolved=$(br list --label spiral:circuit-break --status "open,in-progress" --json 2>/dev/null || echo "[]")
    local count
    count=$(echo "$unresolved" | jq 'length')

    if [[ "$count" -gt 0 ]]; then
        error "Cannot start spiral: $count unresolved failure bead(s) from prior cycles"
        error ""
        echo "$unresolved" | jq -r '.[] | "  - \(.id) [\(.labels | join(","))]: \(.title)"' >&2
        error ""
        error "Resolution options:"
        error "  1. Fix each: investigate + \`br close <id>\`"
        error "  2. Defer: \`br update <id> --label spiral:deferred\` with rationale comment"
        error "  3. Operator override: SPIRAL_SKIP_FAILURE_DEPS=true (logged in trajectory)"
        return 1
    fi
    return 0
}
```

#### 2.4 Resolution semantics

A failure bead is considered "resolved" if any of:

1. **Closed** (`br close <id>`) — default expectation for fix path
2. **Labeled `spiral:deferred`** (`br update <id> --label spiral:deferred`) — explicit defer with operator-authored comment explaining why

A bead with `spiral:circuit-break` label but no resolution disposition is considered **blocking**.

#### 2.5 Trajectory + observability

All failure-bead interactions emit flight-recorder entries:

- `FAILURE_BEAD_CREATED` — when `_create_failure_bead` fires, records bead ID + classification
- `FAILURE_BEAD_GATE_CHECK` — when `_pre_dispatch_failure_check` runs, records check outcome (PASS / BLOCKED / OVERRIDE)

These surface in the #569 dashboard (`dashboard.jsonl` + `dashboard-latest.json`) under a new top-level `failure_beads` key:

```jsonc
{
  "totals": {
    "actions": 47,
    // ... existing fields ...
    "failure_beads_created": 1,
    "failure_beads_pending": 0
  }
}
```

Adds two integer fields to the existing `_emit_dashboard_snapshot` aggregator. Zero risk to existing consumers (additive only).

---

## Interactions + Dependencies

### Schema compatibility

- HARVEST sidecar schema v1 consumers MUST be tolerant of v2 (missing fields). Current consumers:
  - `spiral-orchestrator.sh EVALUATE phase` — already tolerant (uses `jq -r '... // null'`)
  - `post-merge-orchestrator.sh` — reads findings only, unaffected
  - `bridge-orchestrator.sh` — doesn't read the sidecar directly

- `validate_sidecar_schema` function in `spiral-harvest-adapter.sh` MUST be updated to accept both version 1 and version 2 without version-mismatch error.

### Beads integration

- Depends on beads-first architecture (v1.29.0+). If beads not installed, failure-bead features degrade gracefully (warnings; no hard block).
- Failure-bead labels use the `spiral:` namespace per existing beads label convention (e.g., `spiral:circuit-break`, `spiral:scope-mismatch`).
- New beads view: `br list --label spiral:circuit-break` surfaces all spiral-originated failures.

### CLI compatibility

- `spiral-orchestrator.sh --start` accepts new optional flag `--seed-from-draft <path>`. Existing invocations without the flag: unchanged behavior.
- `SPIRAL_SKIP_FAILURE_DEPS=true` env var is the escape hatch. Default: not set (respects failure gate).

---

## Migration + Backwards Compatibility

### Rollout phases

| Phase | Duration | What | Risk |
|-------|----------|------|------|
| **Phase 1 (shipping)** | 1 sprint | Schema v2 + extension writer/reader + feature gates (all default off) | Low — no behavior change until flags flip |
| **Phase 2 (dogfood)** | 2–4 cycles of operator use | Turn on `spiral.seed.auto_draft` in operator's own `.loa.config.yaml` | Medium — first observations of scaffolded SEED quality |
| **Phase 3 (optional default-on)** | Later cycle | Flip `auto_draft` default to `true` after dogfood validates | Medium — breaking UX change; gated by observation data |
| **Phase 4 (failure beads)** | Separate sprint | Ship failure-bead creation + dispatch gate (default off) | Low — opt-in |
| **Phase 5 (failure beads default-on)** | Later | Enable enforcement after dogfood | Medium — can block dispatches |

### Backwards compat invariants

1. Schema v1 sidecars MUST remain readable after v2 ships (current v1 format remains a valid v2 document with empty arrays).
2. `spiral-orchestrator.sh --start` without `--seed-from-draft` flag MUST work identically to today.
3. All new features are gated by config keys that default to false.
4. `validate_sidecar_schema` MUST accept both v1 and v2 sidecars (extend `SPIRAL_SUPPORTED_SCHEMA_VERSIONS` to `(1 2)`).

### Deprecation plan

None initially. Schema v1 remains supported indefinitely. If schema v3 is ever proposed, v1 deprecation would be a separate RFC with a minimum 6-month runway.

---

## Risks + Mitigations

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|-----------|
| Scaffolded SEED has low quality (operator ignores it) | Medium | Low | Observability: track `seed_draft_used` vs `seed_draft_discarded` in flight-recorder. If ignore rate > 80% after 10 cycles, revisit extraction logic. |
| Operator over-trusts scaffolding ("looks plausible, dispatch it") | Low | High | `--edit` flag opens `$EDITOR`; trajectory records whether operator edited or dispatched as-is; HITL warning in draft preamble |
| Failure-bead gate produces false blockers (circuit break was transient, now fixed) | Medium | Medium | Explicit `spiral:deferred` label with rationale is always available; escape hatch via env var; beads remain mutable post-creation |
| Classification vocabulary drifts (too many `other`s) | Medium | Low | Quarterly audit: if > 30% of beads classified `other`, extend vocabulary. Controlled vocab lives in YAML so updates are low-friction. |
| Schema v2 breaks an unknown third-party consumer | Low | Medium | Schema v1 remains valid. Version validator permits both. Bump signaled in CHANGELOG with migration notes. |
| Beads not installed degrades feature silently | Medium | Low | Log warning on first use; don't block (degradation is the intent for non-beads environments) |
| Scaffolded SEED leaks sensitive content from prior cycle review | Low | Medium | Existing sanitizer runs on reviewer.md + auditor-sprint-feedback.md already; reuse that path. Pull threads cite file:line, not content body. |
| EDITOR flag dispatch behavior unclear on headless systems | Medium | Low | `--edit` returns error if `$EDITOR` unset; operator can always skip flag |

---

## Open Questions

These need operator decision before implementation:

### OQ-1 — Classification vocabulary ownership

Should the `spiral-failure-classifications.yaml` be framework-owned (System Zone) or user-extensible (State Zone)?

- **Framework-owned**: stable contract, requires PR to extend
- **User-extensible**: flexibility, risk of divergence across operators

**Recommendation**: framework-owned, with PR process for new classifications. Rationale: the classification taxonomy is load-bearing for dispatch-gate semantics; divergence defeats the purpose.

### OQ-2 — Draft lifetime

How long does `seed-draft.md` live before being stale?

- Option A: forever (operator manages lifecycle)
- Option B: auto-delete after next cycle starts
- Option C: explicit TTL config (e.g., 30 days)

**Recommendation**: Option A initially (conservative). Drafts live in `.run/cycles/cycle-NNN/` which is already operator-managed. If cleanup churn becomes a problem, add TTL as a follow-up.

### OQ-3 — Failure bead priority

Should all failure beads be `high` priority (current proposal), or should classification drive priority?

| Classification | Suggested priority |
|---------------|-------------------|
| `scope-mismatch` | critical |
| `cwd-mismatch` | high |
| `review-fix-exhausted` | high |
| `budget-exhausted` | medium |
| `flatline-stuck` | high |
| `other` | medium |

**Recommendation**: use classification-driven priority per above table. Mapping lives in the same YAML as the classification vocab.

### OQ-4 — Emergence field conservatism

Initial design is conservative (only populate `emergence` when agents explicitly tag). Should we also run heuristic extraction (e.g., scan for "surprisingly", "unexpectedly", "pattern we didn't anticipate")?

**Recommendation**: start conservative. Heuristic extraction risks false positives ("the reviewer wrote 'surprisingly clean code'" → emergence event). Wait for real operator feedback on whether explicit-tag coverage is sufficient.

### OQ-5 — Dispatch gate granularity

If cycle-088 trips a circuit break on `REVIEW_FIX_LOOP_EXHAUSTED`, and operator starts a NEW spiral (different scope, different cycle), should the failure bead still block?

- Option A: all unresolved beads block all dispatches (safe, possibly annoying)
- Option B: beads scope by project/repo and only block dispatches in that scope
- Option C: beads have explicit "blocks" metadata (which future cycles they apply to)

**Recommendation**: Option A initially. Option B requires scope inference that's likely error-prone. Operator can always defer-with-rationale if a blocker is from a genuinely unrelated prior cycle.

---

## Rollout Plan + Validation

### Sprint breakdown

**Sprint 1** (~5 tasks) — Schema v2 + auto-draft scaffolding
1. Extend `cycle-outcome.json` schema: add `pull_threads` + `emergence` arrays (empty by default)
2. Update `validate_sidecar_schema` to accept v1 and v2
3. Extract `pull_threads` from reviewer.md + audit-sprint-feedback.md + flatline findings
4. Add `_emit_seed_draft` function writing `seed-draft.md` at EVALUATE
5. BATS tests for schema extension + extraction logic

**Sprint 2** (~3 tasks) — Dispatch integration
1. Add `--seed-from-draft <path>` flag to `spiral-orchestrator.sh cmd_start`
2. Add `--edit` sub-flag that opens `$EDITOR`
3. BATS tests for dispatch integration

**Sprint 3** (~4 tasks) — Failure beads
1. Add `_create_failure_bead` + classification function
2. Ship `spiral-failure-classifications.yaml` (framework-owned)
3. Wire `_handle_circuit_break` into existing `_run_gate` failure path
4. BATS tests

**Sprint 4** (~3 tasks) — Dispatch gate
1. Add `_pre_dispatch_failure_check` to `spiral-orchestrator.sh cmd_start`
2. Add dashboard `failure_beads_created` + `failure_beads_pending` metrics
3. BATS tests + integration test with mock beads

**Sprint 5** (~2 tasks) — Docs + rollout
1. CHANGELOG entry + README update
2. Skill doc updates in `spiraling/SKILL.md`

### Validation criteria

- **Schema backcompat**: all existing spiral BATS tests continue to pass after schema v2 ships (zero regression requirement).
- **Auto-draft correctness**: on 3 dogfood cycles, seed-draft.md surfaces ≥ 80% of the pull-threads a human operator would identify from the same source material.
- **Failure-bead gate safety**: in 10 consecutive dispatch attempts against a fixed state, gate produces identical decisions (deterministic).
- **Escape hatch works**: `SPIRAL_SKIP_FAILURE_DEPS=true` allows dispatch and records the override in trajectory.
- **No regression**: `bats tests/unit/spiral-*.bats` at ≥ 210 passing (current: 223).

### Observation plan

After Phase 2 dogfood:
- Count: % of cycles where operator accepted draft as-is vs edited vs discarded
- Quality: any drafted SEED that led to a circuit break in cycle-N+1 (signal of poor scaffolding)
- UX: time between `seed-draft.md` written and `--start` dispatched (proxy for operator comfort)

---

## Out of Scope

These are mentioned in #575 but deliberately excluded from this RFC:

- **K-hole's `--trail` mechanism itself** — referenced as architectural precedent only. Lives in `construct-k-hole`.
- **Cognition-layer persona** (from #310) — separate construct-level work.
- **Taste loop** (from #310) — requires construct-level integration.
- **Agent team persona inheritance** — distinct concern.
- **Heuristic emergence extraction** — conservative initial design; revisit based on operator feedback (OQ-4).

---

## Alternatives Considered

### Alt-1 — Keep SEED hand-authored, add a "suggestions" CLI

**Shape**: `spiral suggest-seed --from-cycle cycle-088` prints scaffolded content to stdout; operator copy/pastes.

**Rejected because**: doesn't close the loop mechanically. Operator effort per cycle stays the same. The whole point of #575 is the arrow from build back to tool — a print-only suggestion keeps the author role unchanged.

### Alt-2 — Auto-dispatch scaffolded SEED without operator edit

**Shape**: EVALUATE phase not only drafts the SEED but immediately starts cycle-N+1.

**Rejected because**: violates G3 (operator autonomy) and NG1 (full agency). Worse: small scaffolding errors compound across cycles without a human speed bump to catch them.

### Alt-3 — Failure beads as soft warnings, not hard dependencies

**Shape**: circuit breaker creates a bead, but dispatch proceeds with a warning banner. Operator can ignore.

**Rejected because**: contradicts the "membrane repair" framing from #575. If failures are ignorable, they'll be ignored, and the same failures recur. Hard-dep forces acknowledgment; explicit-defer gives the escape hatch.

### Alt-4 — Classify failures post-hoc via LLM rather than taxonomy

**Shape**: at circuit-break time, invoke `claude -p` to classify the failure into free-form text.

**Rejected because**: adds LLM cost to every circuit break; unbounded vocabulary defeats dispatch-gate semantics (can't query `br list --label spiral:scope-mismatch` reliably); classification quality varies with prompt. Controlled vocab is 10 lines of YAML + regex and deterministic.

---

## Effort Estimate

- **Total**: 5 sprints, ~17 tasks, estimated 2-3 cycles of operator time (spread across 2-3 weeks)
- **Biggest risk**: Sprint 1 (schema extension + extraction) — need to handle edge cases where reviewer.md or auditor-sprint-feedback.md are malformed
- **Smallest**: Sprint 5 (docs) — under 1 sprint

Ratio check against precedent:
- RFC-060 (spiral harness initial) took ~3 cycles
- RFC-061 (calibration pack) took ~3 RFC revisions before merge; implementation still pending
- This RFC has smaller scope than either — both touch existing infrastructure rather than inventing new patterns

---

## Appendix A — Worked Example

### Scenario

Cycle-088 runs. REVIEW verdict: APPROVED. AUDIT verdict: APPROVED. But:
- 2 DISPUTED Flatline findings (consensus wasn't reached)
- 1 auditor `[DEFERRED]` row: "Batch writes to JSONL: consider buffering but deferred — out of scope"
- Bridgebuilder flagged a `SPECULATION` finding: "consider migrating append-only logs to event sourcing pattern"
- 1 circuit break during REVIEW_FIX_LOOP (hit REVIEW_MAX_ITERATIONS before converging, but operator accepted partial fix)

### HARVEST sidecar v2 output

```jsonc
{
  "$schema_version": 2,
  "cycle_id": "cycle-088",
  "review_verdict": "APPROVED",
  "audit_verdict": "APPROVED",
  "findings": {"blocker": 0, "high": 2, "medium": 5, "low": 3},
  "artifacts": {...},
  "flatline_signature": "sha256:...",
  "content_hash": "sha256:...",
  "elapsed_sec": 3421,
  "exit_status": "success",
  "pull_threads": [
    {
      "id": "pt-001",
      "source": "audit",
      "question": "Batch writes to JSONL — buffer size and fsync cadence when to revisit?",
      "severity": "medium",
      "cite": "grimoires/loa/a2a/sprint-1/auditor-sprint-feedback.md:142"
    },
    {
      "id": "pt-002",
      "source": "flatline",
      "question": "DISPUTED: whether compute_grounding_stats should surface per-category breakdown (GPT:650, Opus:200, no consensus)",
      "severity": "low",
      "cite": "grimoires/loa/a2a/flatline/flatline-sprint.json#/disputed[0]"
    }
  ],
  "emergence": [
    {
      "id": "em-001",
      "source": "bridgebuilder",
      "pattern": "Append-only logs could become event sourcing substrate — flight-recorder + dashboard.jsonl both exhibit the pattern",
      "adjacent_to": "spiral observability infrastructure",
      "confidence": "speculative"
    }
  ]
}
```

### seed-draft.md output

```markdown
# SEED draft — cycle-089

> Auto-drafted from cycle-088 HARVEST output.
> Edit freely. Operator-authored sections override auto-drafted ones.

## Context from prior cycle

- Prior cycle: cycle-088, verdict: APPROVED/APPROVED
- Elapsed: 3421s, findings: 0B/2H/5M/3L

## Open threads (from review + audit)

- **[medium]** Batch writes to JSONL — buffer size and fsync cadence when to revisit?
  - Source: audit, cite: `grimoires/loa/a2a/sprint-1/auditor-sprint-feedback.md:142`
- **[low]** DISPUTED: whether compute_grounding_stats should surface per-category breakdown (GPT:650, Opus:200, no consensus)
  - Source: flatline, cite: `grimoires/loa/a2a/flatline/flatline-sprint.json#/disputed[0]`

## Emergence observed

- **Append-only logs could become event sourcing substrate — flight-recorder + dashboard.jsonl both exhibit the pattern** (adjacent to spiral observability infrastructure; confidence: speculative)
  - Source: bridgebuilder

## Proposed cycle-089 intent

<!-- OPERATOR: replace this section with your authored intent, or accept the scaffold below -->

_Auto-scaffold: address blocking pull-threads (0) while observing emergence (1) for follow-up investigation._

---

## Provenance

- Source sidecar: `.run/cycles/cycle-088/cycle-outcome.json`
- Schema version: 2
- Drafted at: 2026-04-19T15:22:31Z
```

### Operator workflow

```bash
# Option 1: accept the scaffold with light edits
$EDITOR .run/cycles/cycle-088/seed-draft.md  # edit "Proposed cycle-089 intent"
/spiral --start --seed-from-draft .run/cycles/cycle-088/seed-draft.md

# Option 2: combined flag
/spiral --start --seed-from-draft .run/cycles/cycle-088/seed-draft.md --edit

# Option 3: discard the draft entirely
/spiral --start "Author's own task statement"
```

---

## Appendix B — Interaction with #569 Dashboard

The observability dashboard schema gains two fields:

```jsonc
{
  "totals": {
    // ... existing ...
    "failure_beads_created": 1,        // NEW
    "failure_beads_pending": 0         // NEW
  }
}
```

And per-phase rollup gains no new fields (failure beads are cycle-level, not phase-level).

`/spiral --status` pretty mode gains one line in the Metrics block:

```
Metrics (as of 2026-04-19T15:22:31Z, dashboard current: COMPLETE):
  Actions:         47  (failures: 2)
  Cost (USD):      3.21  (cap: 12, remaining: 8.79)
  Duration:        185.4s
  Fix-loops:       3  (BB cycles: 2, circuit-breaks: 1)
  Failure beads:   1 created, 0 pending       ← NEW
```

---

## Appendix C — Failure-bead UX walkthrough

### Cycle-N trips circuit break

```
[spiral-harness] CIRCUIT_BREAKER: REVIEW_FIX_LOOP_EXHAUSTED
[spiral-harness] Classification: review-fix-exhausted
[spiral-harness] Creating failure bead...
[br] Created bead bug-042: "Spiral circuit break: REVIEW_FIX_LOOP (review-fix-exhausted)"
[spiral-harness] HALTED. Failure bead bug-042 must be resolved or deferred before next dispatch.
```

### Operator attempts cycle-N+1

```
$ /spiral --start "New feature"
ERROR: Cannot start spiral: 1 unresolved failure bead(s) from prior cycles

  - bug-042 [spiral:circuit-break,spiral:review-fix-exhausted]: Spiral circuit break: REVIEW_FIX_LOOP (review-fix-exhausted)

Resolution options:
  1. Fix each: investigate + `br close <id>`
  2. Defer: `br update <id> --label spiral:deferred` with rationale comment
  3. Operator override: SPIRAL_SKIP_FAILURE_DEPS=true (logged in trajectory)
```

### Resolution path A — operator fixes the root cause

```
$ br show bug-042
# ... reads the detail, traces root cause ...
$ # operator patches the implementation / scope
$ br close bug-042
$ /spiral --start "New feature"   # now succeeds
```

### Resolution path B — defer with rationale

```
$ br update bug-042 --label spiral:deferred
$ br comments add bug-042 "Deferring: this was scope-mismatch on cycle-088 for a DIFFERENT feature; unrelated to new cycle intent. Will revisit if cycle-090 touches same area."
$ /spiral --start "New feature"   # now succeeds (deferred bead does not block)
```

### Resolution path C — operator override

```
$ SPIRAL_SKIP_FAILURE_DEPS=true /spiral --start "New feature"
[spiral-orchestrator] SPIRAL_SKIP_FAILURE_DEPS=true — skipping failure-bead check (recorded in trajectory)
```

All three paths visible in flight-recorder + dashboard.

---

## Changelog (for this RFC)

- v1.0.0 — 2026-04-19 — Initial draft authored by Claude Opus 4.7 against #575 items 1 + 4, building on work shipped in v1.99.1 / v1.99.2 / v1.101.0

## Signoff

Awaiting operator (@janitooor) review. Ready to scope into sprints once direction confirmed.
