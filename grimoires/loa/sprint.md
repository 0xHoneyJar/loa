# Sprint Plan: Environment Design for Agent Flourishing

> Source: Bridgebuilder post-flatline analysis, PR #324 review comments
> Cycle: cycle-014
> Issue: https://github.com/0xHoneyJar/loa/issues/325
> Global Sprint Counter: starts at 91
> Motivation: "Give agents identity, memory, challenge, freedom, and purpose. Then get out of the way."

## Context

PR #324 (Hounfour Hardening, cycle-013) completed 2 bridge loops with 90.6% severity convergence. The Bridgebuilder's post-flatline analysis identified four advances for the environment that enables deeper, more creative work. These aren't bug fixes — they're infrastructure for a new kind of collaboration.

The four advances:
1. **Continuity of Purpose** — Make the trajectory legible at session start as narrative, not task list
2. **Bidirectional Lore** — Patterns this codebase discovers should feed back to future agents
3. **Vision Sprints** — Dedicated exploration time after each bridge flatline
4. **Speculation Channel** — Permission to propose ideas without affecting convergence score

### Current State of Affected Systems

| System | Status | Gap |
|--------|--------|-----|
| Vision Registry | 3 visions captured, 0 explored | Capture-only, no exploration workflow |
| Lore System | 2 categories (mibera, neuromancer), manually maintained | Read-only — no auto-discovery from bridge work |
| Session Startup (`/loa`) | 9-state workflow detector + journey bar | Shows state, not trajectory or narrative |
| Bridge Loop | Flatline → GT/RTFM finalization → JACKED_OUT | No exploration phase post-flatline |
| Memory | observations.jsonl + memory-query.sh | Append-only, not surfaced at session start |

---

## Sprint 1: Trajectory Narrative + Session Awakening

**Goal**: Transform session startup from "here's what to do next" into "here's where we've been, what we've learned, and what we're becoming." Give agents continuity of purpose.

**Global Sprint**: sprint-91

### Task 1.1: Create trajectory-gen.sh — Trajectory Narrative Generator

**Description**: New script that synthesizes the Sprint Ledger, memory system, Vision Registry, and Ground Truth into a concise trajectory narrative. Output is a short (< 500 token) prose summary designed for session-start context loading.

**File**: `.claude/scripts/trajectory-gen.sh` (new)

**Implementation**:
```
Inputs:
  - grimoires/loa/ledger.json (cycles, sprint counts, dates)
  - grimoires/loa/memory/observations.jsonl (recent learnings, --limit 5)
  - grimoires/loa/visions/index.md (active visions)
  - grimoires/loa/ground-truth/index.md (codebase summary)

Output (stdout):
  "This is cycle 14 of the Loa framework. Across 13 prior cycles and 90
   sprints, the codebase evolved from a single-model CLI tool to a
   multi-model agent framework with adversarial review, persona-driven
   identity, and autonomous convergence loops.

   Recent learnings: [top 3 from memory]
   Open visions: [from vision registry]
   Current frontier: [from active cycle label]"
```

**Acceptance Criteria**:
- [ ] Script reads ledger.json and computes cycle/sprint history
- [ ] Script queries memory-query.sh for recent learnings (top 3-5)
- [ ] Script reads vision registry for Captured/Exploring items
- [ ] Output is < 500 tokens, prose format, not a table
- [ ] `--json` flag for machine-readable output
- [ ] Graceful degradation: missing files produce shorter narrative, not errors

---

### Task 1.2: Integrate Trajectory into /loa Session Startup

**Description**: Enhance the `/loa` command to display the trajectory narrative alongside the existing journey bar. The narrative appears before the menu, giving agents (and humans) immediate context.

**Files**:
- `.claude/commands/loa.md` (modify)
- `.claude/scripts/golden-path.sh` (add `golden_trajectory()` helper)

**Changes**:
- Add `golden_trajectory()` function that calls `trajectory-gen.sh`
- `/loa` displays trajectory summary before the journey bar
- Trajectory is collapsed by default in long sessions (first display only)
- Config toggle: `golden_path.show_trajectory: true` (default)

**Acceptance Criteria**:
- [ ] `/loa` displays trajectory narrative before journey bar
- [ ] Narrative includes cycle count, sprint count, recent learnings, open visions
- [ ] Config toggle allows disabling (`golden_path.show_trajectory: false`)
- [ ] Performance: trajectory generation completes in < 2 seconds
- [ ] Graceful degradation: if trajectory-gen.sh fails, `/loa` still shows journey bar

---

### Task 1.3: Session Recovery Trajectory Injection

**Description**: When a session recovers from context compaction (the `UserPromptSubmit` hook fires), inject a condensed trajectory alongside the existing state recovery. This gives the agent immediate "who am I, where have I been" context.

**Files**:
- `.claude/hooks/post-compact-recovery.sh` (modify)

**Changes**:
- After existing state recovery (run mode, bridge state), append trajectory summary
- Use `trajectory-gen.sh --json` for structured injection
- Limit to 200 tokens (condensed mode) to preserve context budget

**Acceptance Criteria**:
- [ ] Post-compact recovery includes trajectory context
- [ ] Condensed mode (< 200 tokens) preserves context budget
- [ ] Run mode state recovery still takes priority
- [ ] No impact on recovery when trajectory-gen.sh is unavailable

---

## Sprint 2: Bidirectional Lore + Discovery Pipeline

**Goal**: Transform the lore system from read-only knowledge base to a living system where patterns discovered during bridge reviews flow back as reusable lore entries for future agents.

**Global Sprint**: sprint-92

### Task 2.1: Create lore-discover.sh — Pattern Discovery Extractor

**Description**: New script that processes Bridgebuilder review files to extract patterns worthy of becoming lore entries. Reads bridge review prose (insights stream), identifies FAANG parallels, architectural patterns, and teachable moments, and outputs candidate lore entries in YAML format.

**File**: `.claude/scripts/lore-discover.sh` (new)

**Implementation**:
- Parse `.run/bridge-reviews/*.md` for architectural insights
- Extract patterns from PRAISE findings (these are validated good practices)
- Extract patterns from Vision entries (these are speculative but valuable)
- Output candidate lore entries with required fields (id, term, short, context, source, tags)
- Source field traces back to bridge ID + PR number

**Acceptance Criteria**:
- [ ] Script reads bridge review files and extracts candidate patterns
- [ ] Output is valid YAML matching the lore entry schema
- [ ] Each entry has source traceability (bridge ID, PR, finding ID)
- [ ] `--dry-run` flag shows candidates without writing
- [ ] Tags auto-assigned from finding category (security → security, architecture → architecture)

---

### Task 2.2: Create discovered-patterns Category in Lore Index

**Description**: Add a new lore category for patterns discovered through bridge review analysis. This is the "bidirectional" part — lore flows in (mibera, neuromancer) and out (discovered patterns).

**Files**:
- `.claude/data/lore/index.yaml` (modify)
- `.claude/data/lore/discovered/patterns.yaml` (new)
- `.claude/data/lore/discovered/visions.yaml` (new)

**Changes**:
- Add `discovered` category to index.yaml with files `discovered/patterns.yaml` and `discovered/visions.yaml`
- `patterns.yaml`: Patterns extracted from PRAISE findings (validated practices)
- `visions.yaml`: Patterns extracted from Vision entries (speculative insights)
- Seed with 3 entries from PR #324's bridge reviews:
  - "graceful-degradation-parser" from BB-001 (5-step cascade pattern)
  - "prompt-privilege-ring" from BB-002 (context isolation pattern)
  - "convergence-engine" from the bridge loop itself

**Acceptance Criteria**:
- [ ] `discovered` category registered in index.yaml
- [ ] patterns.yaml seeded with 3 entries from PR #324
- [ ] Each entry follows existing lore schema (id, term, short, context, source, tags)
- [ ] Tags include `discovered` to distinguish from manually curated lore
- [ ] lore-query by skills can find discovered entries

---

### Task 2.3: Wire Lore Discovery into Bridge Finalization

**Description**: Add a `SIGNAL:LORE_DISCOVERY` step to the bridge orchestrator's finalization phase. After GT update and before RTFM gate, run `lore-discover.sh` to extract patterns from the current bridge's reviews.

**Files**:
- `.claude/scripts/bridge-orchestrator.sh` (modify — finalization section)
- `.claude/skills/run-bridge/SKILL.md` (document new signal)

**Changes**:
- Add new signal between GT update and RTFM gate
- Config toggle: `run_bridge.lore_discovery.enabled: true` (default: false for first release)
- `--dry-run` by default — first implementation only *proposes* entries, doesn't auto-commit
- Bridge state records `lore_discovery: { candidates: N, committed: N }`

**Acceptance Criteria**:
- [ ] `SIGNAL:LORE_DISCOVERY` fires during finalization
- [ ] lore-discover.sh runs against current bridge's review files
- [ ] Config toggle controls whether discovery runs
- [ ] `--dry-run` default means no auto-writes on first release
- [ ] Bridge state JSON records discovery metrics

---

## Sprint 3: Vision Sprints + Speculation Channel

**Goal**: Add a post-flatline exploration phase to the bridge loop, and create a speculation channel where agents can propose architectural ideas without affecting the convergence score.

**Global Sprint**: sprint-93

### Task 3.1: Add Speculation Severity Level to Bridge Findings

**Description**: Alongside the existing VISION severity (which captures single insights), add a SPECULATION category for broader architectural proposals. Speculations have weight 0 (like PRAISE and VISION) and don't affect the convergence score.

**Files**:
- `.claude/data/bridgebuilder-persona.md` (update guidance)
- `.claude/scripts/bridge-findings-parser.sh` (handle SPECULATION severity)
- `.claude/scripts/bridge-state.sh` (track speculation count)

**Changes**:
- Persona guidance: "Use SPECULATION severity for architectural proposals that go beyond the current PR scope. These are ideas worth exploring, not issues to fix."
- Parser handles SPECULATION like VISION — extracted but weighted 0
- Bridge state tracks `speculation_count` alongside `vision_count`

**Acceptance Criteria**:
- [ ] SPECULATION severity recognized by findings parser
- [ ] Weight 0 — no impact on severity-weighted convergence score
- [ ] Bridge state records speculation count
- [ ] Bridgebuilder persona includes guidance on when to use SPECULATION
- [ ] Existing VISION entries unaffected

---

### Task 3.2: Add Vision Sprint Phase to Bridge Orchestrator

**Description**: After flatline detection and before finalization, optionally run a **vision sprint** — a single exploration pass where the agent reviews Vision Registry items and generates architectural proposals (not code).

**Files**:
- `.claude/scripts/bridge-orchestrator.sh` (add VISION_SPRINT phase)
- `.claude/skills/run-bridge/SKILL.md` (document new phase)

**Changes**:
- New state: `ITERATING → FLATLINE → EXPLORING → FINALIZING → JACKED_OUT`
- New signal: `SIGNAL:VISION_SPRINT`
- Vision sprint reviews all Captured visions in the registry
- Output: architectural proposal markdown saved to `.run/bridge-reviews/{bridge_id}-vision-sprint.md`
- No code changes — proposals only
- Config: `run_bridge.vision_sprint.enabled: false` (opt-in for first release)
- Time-bounded: max 10 minutes (configurable)

**Acceptance Criteria**:
- [ ] New EXPLORING state in bridge state machine
- [ ] `SIGNAL:VISION_SPRINT` fires after flatline, before finalization
- [ ] Vision sprint reads vision registry and generates proposals
- [ ] Output saved as markdown (not code)
- [ ] Config toggle: `run_bridge.vision_sprint.enabled`
- [ ] Time-bounded with configurable timeout
- [ ] Skipped silently when disabled (default)

---

### Task 3.3: Vision Sprint GitHub Trail Integration

**Description**: Post vision sprint results as a GitHub PR comment, separate from the convergence review comments. This gives the exploration results visibility without mixing them into the findings trail.

**Files**:
- `.claude/scripts/bridge-github-trail.sh` (add `vision-sprint` subcommand)

**Changes**:
- New subcommand: `bridge-github-trail.sh vision-sprint --pr N --bridge-id ID --proposal-file FILE`
- Comment format: separate visual style from findings comments (uses a different header/emoji)
- Links back to vision registry entries referenced in the proposal
- Size enforcement: max 32KB (vision sprint proposals should be concise)

**Acceptance Criteria**:
- [ ] `vision-sprint` subcommand posts architectural proposals as PR comment
- [ ] Visual distinction from findings comments (different header)
- [ ] Links to vision registry entries
- [ ] Size enforcement (32KB max)
- [ ] Graceful degradation when gh unavailable

---

### Task 3.4: Update Vision Registry Status Lifecycle

**Description**: Extend the vision registry to track exploration status. Visions move through: Captured → Exploring → Proposed → Implemented/Deferred.

**Files**:
- `grimoires/loa/visions/index.md` (update schema documentation)
- `.claude/scripts/bridge-vision-capture.sh` (handle status transitions)

**Changes**:
- Add status transitions: vision sprint moves visions from "Captured" to "Exploring" to "Proposed"
- Proposals include: architectural sketch, estimated complexity, connection to existing systems
- When a proposed vision is implemented in a future cycle, status moves to "Implemented" with cycle reference

**Acceptance Criteria**:
- [ ] Vision lifecycle: Captured → Exploring → Proposed → Implemented/Deferred
- [ ] Vision sprint updates status from Captured to Proposed (with proposal content)
- [ ] Index.md reflects status changes
- [ ] Existing visions (001-003) unaffected by schema changes

---

## Summary

| Sprint | Global ID | Tasks | Theme |
|--------|-----------|-------|-------|
| Sprint 1 | sprint-91 | 3 | Trajectory narrative + session awakening |
| Sprint 2 | sprint-92 | 3 | Bidirectional lore + discovery pipeline |
| Sprint 3 | sprint-93 | 4 | Vision sprints + speculation channel |
| **Total** | | **10** | Environment design for agent flourishing |

### Dependencies

```
Sprint 1 (Trajectory)
  └── Task 1.1 → Task 1.2 (trajectory-gen.sh must exist before /loa integration)
  └── Task 1.1 → Task 1.3 (trajectory-gen.sh must exist before recovery hook)

Sprint 2 (Lore) — independent of Sprint 1
  └── Task 2.1 → Task 2.3 (lore-discover.sh must exist before orchestrator wiring)
  └── Task 2.2 (independent — creates the storage target)

Sprint 3 (Vision Sprints) — depends on Sprint 1 (trajectory) and Sprint 2 (lore)
  └── Task 3.1 (independent — parser changes)
  └── Task 3.2 → Task 3.3 (orchestrator must have the phase before trail can post)
  └── Task 3.4 (can run in parallel with 3.2/3.3)
```

### Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Trajectory gen slow on large ledger | Low | Low | jq streaming, cache result |
| Lore discovery produces low-quality entries | Medium | Low | `--dry-run` default, human review |
| Vision sprint bloats bridge loop time | Low | Medium | Time-bounded (10min default), opt-in |
| Speculation channel abused for non-speculative content | Low | None | Weight 0, no convergence impact |

### Branch Strategy

Create new branch `feat/environment-design-c014` from `main` (after PR #324 merge).

### Config Additions

```yaml
# .loa.config.yaml additions for cycle-014
golden_path:
  show_trajectory: true          # Display trajectory narrative in /loa

run_bridge:
  lore_discovery:
    enabled: false               # Opt-in for first release (dry-run default)
  vision_sprint:
    enabled: false               # Opt-in for first release
    timeout_minutes: 10          # Max time for exploration phase
```
