# PRD: Construct-Aware Constraint Yielding

> Cycle: cycle-029 | Author: janitooor + Claude
> Source: [#376](https://github.com/0xHoneyJar/loa/issues/376)
> Related: [loa-constructs#129](https://github.com/0xHoneyJar/loa-constructs/issues/129)
> Priority: P1 (framework architecture — enables construct ecosystem scaling)

---

## 1. Problem Statement

Loa's pipeline constraints (PRD → SDD → Sprint → Implement → Review → Audit) are enforced globally, forcing full-depth process on every task regardless of domain. A 26-line UI change (midi-interface #102) required PRD with 7 discovery phases, 2 GPT review rounds, sprint plan with 5 tasks, and 2 more review rounds — ~40% of the session was process, not code.

**The core issue**: Constructs already operate as self-contained expertise packages with their own workflows (Observer has 11 skills, Artisan has 14), but Loa's constraint system doesn't recognize this. When work touches the APP zone, constraints C-PROC-001/003/004 force the full pipeline regardless of whether a construct declares its own workflow.

> Sources: loa#376 body, loa#376 comment-1 (zkSoju), loa-constructs#129 body

---

## 2. Vision

**Loa's constraints yield when a construct declares workflow ownership.** The pipeline is a composable tool that constructs leverage for agentic backpressure, not a mandatory gate. Constructs compose the pipeline at their chosen depth via manifest declarations.

### Three-Layer Architecture

| Layer | What | Always? |
|-------|------|---------|
| **Loa Runtime** | Hooks, beads, events, memory, guardrails, git safety, three-zone model | Always available |
| **Loa Pipeline** | PRD → SDD → Sprint → Implement → Review → Audit | Opt-in at chosen depth |
| **Construct Workflow** | Domain-specific skills, verification, state | Defined by construct |

A construct doesn't choose "pipeline OR own workflow" — it **composes both**.

> Sources: loa#376 comment-3 (zkSoju architecture), loa-constructs#129 comment-2 (refined model)

---

## 3. Goals & Success Metrics

### G-1: Constraint System Reads Construct Workflow Declarations
- Constraint enforcement checks whether an active construct declares workflow ownership before applying pipeline constraints
- **Metric**: C-PROC-001/003/004/008 skip enforcement when construct with `workflow.gates` is active

### G-2: Review/Audit Skills Accept Generic Inputs
- Review and audit skills accept acceptance criteria from any source (issue body, manifest, inline), not just sprint.md
- **Metric**: `/review-sprint` and `/audit-sprint` work with construct-provided inputs, not only pipeline artifacts

### G-3: Construct Manifest Supports Workflow Declaration
- Pack manifests can declare `workflow` section with gates, depth, and verification method
- **Metric**: Existing packs (Observer, Artisan) can retroactively declare their workflow depth

### G-4: Pipeline Stages Become Composable
- The hard chain audit→review ("All good" magic string) is replaced with configurable gate contracts
- **Metric**: A construct can declare `audit: skip` and still reach COMPLETED state

---

## 4. User & Stakeholder Context

### Primary Persona: Construct Author
- Builds domain-specific expertise packages (FE/UI, BE/API, Data, Infra)
- Wants to define workflow depth appropriate to their domain
- Needs the Loa runtime (hooks, beads, guardrails) without the full pipeline overhead

### Secondary Persona: Framework User (Loa default)
- Uses Loa without constructs — the default pipeline applies
- No change to their experience
- The pipeline remains the default when no construct declares workflow ownership

### Stakeholder: Maintainer (@janitooor)
- Wants constructs to be peers, not subordinates to Loa's pipeline
- Pipeline is a backpressure mechanism, not a quality gate hierarchy
- Constructs that declare gates are trusted — they've earned trust by being installed, versioned, maintained

> Sources: loa#376 comment-2 (zkSoju), loa#376 comment-4 (refined model)

---

## 5. Functional Requirements

### FR-1: Manifest Workflow Schema (Loa-side reader)

**Note**: The manifest schema itself is defined in loa-constructs#129. This cycle implements the **Loa-side reader** that interprets the schema.

Loa must read and validate this manifest section:

```yaml
workflow:
  depth: light | standard | deep | full
  app_zone_access: true | false
  gates:
    prd: skip | condense | full
    sdd: skip | condense | full
    sprint: skip | condense | full
    implement: required
    review: skip | visual | textual | both
    audit: skip | lightweight | full
  verification:
    method: visual | tsc | build | test | manual
```

**Note on `condense`**: The reader accepts `condense` as a valid value for forward compatibility with loa-constructs#129, but treats it as `full` in this cycle with a logged advisory. Full condense behavior (auto-generating sprint from issue body) is a construct-side concern.

**Acceptance Criteria**:
- [ ] Loa can read `workflow` from pack manifest.json
- [ ] Missing `workflow` section means "use default pipeline" (backwards compatible)
- [ ] Invalid values produce clear validation errors
- [ ] `implement: required` is enforced — cannot be set to `skip`
- [ ] `condense` is accepted but treated as `full` with advisory log

### FR-2: Active Construct Detection

The system must determine whether a construct with declared workflow gates is currently handling work. Detection operates across three enforcement layers (see FR-3).

**Mechanism**: When a skill is invoked, the loader knows which pack it came from. If that pack's `manifest.json` contains a `workflow` section, the construct is considered "workflow-active." This is a property of the skill loading context, not runtime heuristics.

**State tracking**: A state marker (`.run/construct-workflow.json`) records the active construct and its gates during workflow execution. This enables pre-flight checks in command `.md` files to read the construct's declarations.

**Acceptance Criteria**:
- [ ] Skill loader writes `.run/construct-workflow.json` when invoking a skill from a pack with `workflow` declaration
- [ ] File contains: construct name, pack slug, gates, depth, timestamp
- [ ] File is cleared when construct workflow completes or on session end
- [ ] Missing file means "no construct active" (default pipeline applies)
- [ ] Detection uses skill loading context (which pack loaded the skill) — not runtime heuristics

### FR-3: Constraint Yielding Logic

Constraints are enforced through three layers. Yielding must occur at each:

**Layer 1 — Prompt-level (constraints.json → CLAUDE.md)**: Add `construct_yield` field to relevant constraints. The CLAUDE.md renderer includes the yield clause (e.g., "...OR when a construct with `workflow.gates` declares ownership").

**Layer 2 — Pre-flight (command .md files)**: Command pre-flight checks read `.run/construct-workflow.json`. If present and the construct declares a gate as `skip`, the pre-flight check passes without requiring the corresponding artifact.

**Layer 3 — Safety hooks**: No changes needed. Hooks protect System Zone and destructive operations, not pipeline flow.

| Constraint | Current | With Construct Active |
|-----------|---------|----------------------|
| C-PROC-001 | No code outside `/implement` | No code outside `/implement` **OR construct-owned workflow** |
| C-PROC-003 | No skip without `/run` or `/bug` | No skip without `/run`, `/bug`, **OR construct with `workflow.gates`** |
| C-PROC-004 | No skip review/audit | Yield when construct declares `review: skip` or `audit: skip` |
| C-PROC-008 | Always check sprint plan | Yield when construct declares `sprint: skip` |

**Acceptance Criteria**:
- [ ] constraints.json modified with `construct_yield` field on C-PROC-001/003/004/008
- [ ] CLAUDE.md rendering script includes yield clause in generated constraint tables
- [ ] Command pre-flight checks in review-sprint.md and audit-sprint.md read construct-workflow.json
- [ ] Yield only applies to the specific gate the construct skips — other constraints still enforced
- [ ] Yield is logged to `.run/audit.jsonl` (observable via audit trail)
- [ ] Default behavior unchanged when no construct is active

### FR-4: Configurable Gate Contracts for Review/Audit

Make the hard chain between review and audit configurable so constructs can compose at their declared depth. **This cycle focuses on gate configurability**, not full path generics (which require deeper refactoring deferred to a future cycle).

| Current (pipeline-coupled) | This Cycle (construct-aware) | Future (fully generic) |
|---------------------------|------------------------------|------------------------|
| Hard gate on "All good" in `engineer-feedback.md` | Gate bypassed when construct declares `review: skip` | Accepts criteria from any source |
| COMPLETED only via audit-sprint | COMPLETED available to construct workflows | Construct-declared completion signals |
| Reads `sprint.md` for acceptance criteria | Unchanged (default path) | Accepts criteria from any source |
| Output to `a2a/sprint-N/` | Unchanged (default path) | Configurable output paths |

**Acceptance Criteria**:
- [ ] Review/audit commands detect active construct via `.run/construct-workflow.json` and read criteria from construct's declared source
- [ ] Audit command's "All good" check is bypassed when construct declares `review: skip` (no engineer-feedback.md required)
- [ ] COMPLETED marker creation is available to construct workflows, not only audit-sprint
- [ ] Default behavior unchanged — without active construct, reads sprint.md as before

### FR-5: Construct Lifecycle Events

When a construct workflow begins and ends, emit events for observability.

**Acceptance Criteria**:
- [ ] `construct.workflow.started` event emitted with construct name, declared depth, gates
- [ ] `construct.workflow.completed` event emitted with outcome
- [ ] Events are logged to audit trail (`.run/audit.jsonl`)
- [ ] Other constructs can consume these events via the event bus

---

## 6. Technical & Non-Functional Requirements

### NF-1: Backwards Compatibility
- All existing workflows work unchanged when no construct is active
- The default pipeline is preserved — this is additive, not a replacement
- Existing constructs (Observer, Artisan) that don't declare `workflow` continue working as they do today

### NF-2: Security — Trust Boundary
- Only installed, versioned constructs can declare workflow gates
- Runtime code cannot dynamically claim construct status to bypass constraints
- Construct workflow declarations are validated at pack install time, not runtime
- System Zone (`.claude/`) modifications remain blocked regardless of construct declarations

### NF-3: Auditability
- Every constraint yield is logged with: constraint ID, construct name, gate declaration, timestamp
- Audit trail shows what was skipped and why
- No silent bypasses — yields are observable

### NF-4: Fail-Closed
- If construct detection fails (parse error, missing manifest), default to full pipeline
- Ambiguous workflow declarations default to the more conservative option
- This matches existing hook design (fail-open for hooks, fail-closed for constraints)

---

## 7. Scope & Prioritization

### In Scope (This Cycle)

| Priority | Feature | Why |
|----------|---------|-----|
| P0 | FR-1: Manifest workflow reader | Foundation — everything else depends on reading the schema |
| P0 | FR-2: Active construct detection | Foundation — constraint yielding needs this |
| P0 | FR-3: Constraint yielding logic | Core value — the actual yielding behavior |
| P1 | FR-4: Configurable gate contracts | Enables constructs to bypass review→audit chain |
| P2 | FR-5: Lifecycle events | Observability — important but not blocking |

### Out of Scope

| Item | Why | Where |
|------|-----|-------|
| Manifest schema definition | Construct-side concern | loa-constructs#129 |
| Visual verification (deploy preview, screenshots) | Requires browser/deployment infra | Future cycle |
| Cross-repo coordination layer | Multi-construct features | Future cycle |
| Creating new domain-specific constructs (FE/UI, BE/API) | Construct authors build these | loa-constructs registry |
| "condense" sprint generation from issue body | Requires construct-side implementation | loa-constructs#129 |
| Golden path routing through construct manifests | v3 in the construct roadmap | Future cycle |

---

## 8. Risks & Dependencies

### R-1: Schema Coordination (Medium)
- **Risk**: Loa-side reader and loa-constructs#129 schema must agree
- **Mitigation**: Define the reader to accept a superset; validate strictness can be added later

### R-2: Constraint Escape Escalation (Low)
- **Risk**: Construct workflow declarations could be abused to bypass all constraints
- **Mitigation**: `implement: required` cannot be set to skip; System Zone always protected; construct must be installed (not runtime-injected)

### R-3: Backwards Compatibility Regression (Low)
- **Risk**: Modifying constraint enforcement could break existing workflows
- **Mitigation**: All changes are additive — default behavior only changes when a construct with `workflow` section is detected; comprehensive test coverage

### D-1: Dependency — loa-constructs#129
- The manifest schema is defined in loa-constructs. This cycle implements the **reader**, not the schema.
- If schema changes, the reader adapts — we validate loosely and tighten later.

---

## 9. Domain Examples (Reference)

For construct authors building on this infrastructure. **Note**: These are illustrative examples for future constructs. "direct" in the Data/Lore row maps to `implement: required` with all other gates set to `skip` — the construct still goes through an implement phase, it just has no planning or review overhead.

| Construct Domain | PRD | SDD | Sprint | Implement | Review | Audit |
|-----------------|-----|-----|--------|-----------|--------|-------|
| **BE/API** | full | full | full | required | textual | full |
| **FE/UI** | skip | skip | condense | required | visual | skip |
| **FE/Data** | skip | skip | condense | required | tsc+build | lightweight |
| **Infra** | full | full | full | required | both | full |
| **Data/Lore** | skip | skip | skip | required | skip | skip |

> Source: loa-constructs#129 body (domain examples table)
