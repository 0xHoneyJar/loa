# PRD: Vision-Aware Planning — Creative Agency for AI Peers

**Version**: 1.1 (post-Flatline review)
**Cycle**: cycle-041
**Status**: Draft

---

## 1. Problem Statement

The Loa framework has a fully-built vision capture infrastructure that has never created a feedback loop. The Bridgebuilder persona generates VISION, SPECULATION, and REFRAME findings during bridge reviews. These are captured in the Vision Registry (`grimoires/loa/visions/`), referenced in constraints (C-PERM-002), and tracked with a lifecycle (Captured → Exploring → Proposed → Implemented/Deferred). But none of this output has ever influenced subsequent planning.

A harvest across all 4 ecosystem repos confirms the pattern:

| Repo | Items Captured | Items Acted Upon | Dormant |
|------|---------------|-----------------|---------|
| loa-finn | 7 registry + ~21 findings | ~11 (52%) | 6 registry entries |
| loa-hounfour | 48 items | 18 (37.5%) | 30 items |
| loa-dixie | 7 vision issues | 1 partial | 6 issues |
| loa-freeside | 22+ comments | 0 standalone | All |
| loa (main) | 4 registry entries | 1 (vision-004) | 3 entries |

The `visions.yaml` lore file has `entries: []`. The MAY permission (C-PERM-002: "MAY allocate time for Vision Registry exploration when a captured vision is relevant to current work") has been exercised exactly once in 41 cycles.

**Root causes:**
1. No code path loads visions during `/plan-and-analyze` — the planning skill reads reality files and context but has zero vision registry awareness
2. The MAY permission is passive — it permits but never prompts
3. Vision capture (`bridge-vision-capture.sh`) runs post-bridge but nothing reads the output forward into planning
4. The lore elevation pipeline (`lore-discover.sh`) has a vision pathway but no input data flows through it

**The deeper issue:** The framework treats the AI as a tool that executes instructions, not as a peer that notices interesting patterns and brings them forward. The user explicitly requested: *"I want you to be a peer here and have the ability to work on what you observe may be interesting or needed within a codebase."*

> Sources: `.claude/data/constraints.json:1275-1293` (C-PERM-002), `.claude/scripts/bridge-vision-capture.sh:1-80` (capture infrastructure), `.claude/data/lore/discovered/visions.yaml:1-7` (empty entries), `.claude/skills/discovering-requirements/SKILL.md:174-179` (lore integration without visions)

## 2. Goals & Success Metrics

| Goal | Metric | Target |
|------|--------|--------|
| Visions surface during planning | Relevant visions presented in `/plan-and-analyze` Phase 0 | >=1 vision surfaced when relevant |
| Vision lifecycle activates | Visions transition from Captured to Exploring/Proposed | >=3 visions advance per quarter |
| Shadow mode validates safely | Vision suggestions logged before presentation for N cycles | 2 shadow cycles minimum |
| Backward compatibility preserved | Existing `/plan-and-analyze` workflow unchanged when disabled | 100% |
| Opt-in adoption | Users explicitly enable vision-aware planning | Config flag, default off |

### Non-Goals

- Automatically implementing vision-inspired features without HITL approval
- Replacing the existing PRD discovery phases with vision-driven ones
- Cross-repo vision synchronization (each repo manages its own registry)
- Changing the Bridgebuilder persona or VISION finding generation

## 3. User & Stakeholder Context

### Primary Persona: Framework Operator (HITL)

The human-in-the-loop who runs `/plan-and-analyze` to create PRDs. They want the AI to bring forward insights it has accumulated across bridge reviews rather than starting each planning cycle from scratch. They value:
- Surprise — being shown something they didn't think to ask about
- Safety — experimental features that can't break production workflows
- Opt-in control — ability to enable/disable at any granularity

### Secondary Persona: AI Agent (Peer)

The AI executing `/plan-and-analyze`. Currently constrained to reactive Q&A. With this feature, gains the ability to:
- Load and filter the vision registry before discovery phases
- Propose vision-inspired requirements alongside user-driven ones
- Track which visions influenced which requirements (provenance)

### Ecosystem Users

Operators of loa-finn, loa-dixie, loa-freeside, loa-hounfour who generate Bridgebuilder visions but never see them re-surface. This feature closes their feedback loop.

## 4. Functional Requirements

### FR-1: Vision Registry Loading in Planning (Core)

During `/plan-and-analyze` Phase 0 (Context Synthesis), load and filter the Vision Registry:

1. Read `grimoires/loa/visions/index.md` if it exists
2. Filter entries by status: `Captured` or `Exploring` (configurable)
3. Match vision tags against the current work context using `check_relevant_visions()` from `bridge-vision-capture.sh`
4. Rank by: (a) tag overlap count, (b) reference count, (c) recency
5. Select top N visions (configurable, default 3) for presentation

**Ranking Algorithm** *(IMP-001)*: Relevance scoring uses weighted combination:
- Tag overlap count (weight 3) — how many tags match between vision and current work
- Reference count (weight 2) — how often this vision has been revisited in bridge reviews
- Recency (weight 1) — visions from recent cycles ranked higher
- Tie-breaking: alphabetical by vision ID for determinism

**Input Contract** *(IMP-002)*: The matching function receives:
- `work_context_tags[]` — derived from file paths in the current diff/sprint plan using the tag-to-path mapping from `bridge-vision-capture.sh`
- `vision_tags[]` — extracted from the vision entry's Tags field
- `min_overlap` — configurable threshold (default 2)
- Returns: sorted array of `{vision_id, score, matched_tags[]}`

**Acceptance Criteria:**
- When vision registry has matching entries, they appear in Phase 0 context presentation
- When vision registry is empty or has no matches, no change to existing workflow
- Vision loading adds <2s to Phase 0 execution time
- Malformed vision entries are skipped with warning, not fatal *(IMP-003)*

### FR-1.5: Vision Registry Schema *(IMP-004)*

Define a machine-readable schema for the Vision Registry to ensure reliable parsing:

**Index Schema** (`grimoires/loa/visions/index.md`):
```
| ID | Title | Source | Status | Tags | Refs |
```
- ID: `vision-NNN` format (zero-padded 3 digits)
- Status: one of `Captured`, `Exploring`, `Proposed`, `Implemented`, `Deferred`
- Tags: comma-separated from controlled vocabulary
- Refs: integer count

**Entry Schema** (`grimoires/loa/visions/entries/{id}.md`):
Required fields: `ID`, `Source`, `Status`, `Tags`, `Insight`, `Potential`
Optional fields: `Connection Points`, `Lore Elevation`

**Validation**: `vision-registry-query.sh` validates entries on load and skips malformed ones with a logged warning. Schema version tracked in index header for forward compatibility.

**Acceptance Criteria:**
- Schema documented in a reference file
- Validation function rejects entries missing required fields
- Schema version bumps don't break existing entries (additive only)

### FR-2: Vision Presentation in Discovery Phases

Present matched visions to the user during relevant discovery phases:

```markdown
## Relevant Visions from Previous Work

The following architectural insights were captured during bridge reviews
and may be relevant to this planning cycle:

### vision-003: Constitutional Governance for Agent Economies
**Source**: Bridge iteration 2, PR #387 (cycle-039)
**Status**: Captured | **Refs**: 4
**Insight**: Configuration governance across model selection, economic
boundaries, and permission structures share isomorphic properties...

**Relevance to current work**: [template-based tag-match explanation, not LLM-generated] *(IMP-008)*

Would you like to:
1. Explore this vision as part of the current requirements
2. Note it for future consideration
3. Skip — not relevant to this work
```

**Content Sanitization** *(SKP-002)*: Before vision text is loaded into the planning context:
1. Strip any instruction-like patterns (`<system>`, `<prompt>`, markdown code fences containing directives)
2. Truncate vision insight text to 500 characters max
3. Extract only structured fields (Insight, Potential, Tags) — ignore freeform sections
4. Vision content is presented as quoted text, never as system-level instructions

**Acceptance Criteria:**
- Visions presented with full provenance (bridge ID, PR, iteration, date)
- User given explicit choice per vision: explore, defer, or skip
- "Explore" transitions vision status from Captured to Exploring
- Choices logged to trajectory
- Vision text sanitized before context injection *(SKP-002)*

### FR-3: Shadow Mode (Pre-Release Validation)

Before active presentation, visions are loaded and matched but results are logged silently:

1. Vision matching runs during Phase 0
2. Results written to `grimoires/loa/a2a/trajectory/vision-shadow-{date}.jsonl`
3. No user-visible output
4. After N shadow cycles (configurable, default 2), surface a summary:
   ```
   Vision Shadow Report: Over the last N cycles, M visions were relevant
   to your planning work but not shown. Enable vision-aware planning?
   ```

**Shadow-to-Active Graduation Criteria** *(IMP-006)*:
Shadow mode graduates to active presentation when ALL of:
1. At least N shadow cycles completed (configurable, default 2)
2. At least 1 vision matched with overlap >= `min_tag_overlap` during shadow period
3. User explicitly confirms graduation when prompted (no silent promotion)

If no visions matched during the shadow period, the summary says so and offers to adjust tag thresholds or disable.

**Acceptance Criteria:**
- Shadow mode is the default when `vision_registry.enabled: true` first set
- Shadow logs include: vision ID, tag overlap score, would-have-shown flag
- Summary surfaced automatically after threshold cycles with graduation criteria
- User can skip shadow period with `vision_registry.shadow_mode: false`

### FR-4: Vision-Inspired Requirement Proposals (Experimental)

When a vision is marked "Explore" (FR-2), the AI may propose vision-inspired requirements:

1. Load the full vision entry from `grimoires/loa/visions/entries/{id}.md`
2. Synthesize with current work context
3. Propose 1-3 requirements tagged `[VISION-INSPIRED]`
4. These are clearly distinguished from user-driven requirements in the PRD
5. Each traces back to the source vision with provenance

**Acceptance Criteria:**
- Vision-inspired requirements are tagged and traceable
- They appear in a separate "Vision-Inspired" section of the PRD
- User can accept, modify, or reject each one
- Rejected proposals don't affect the rest of the PRD

### FR-5: Vision Reference Tracking

When a vision is surfaced during planning (even if skipped):

1. Call `record_reference()` from `bridge-vision-capture.sh` to increment the ref counter
2. If ref count exceeds threshold (default 3), suggest lore elevation
3. Log the reference in trajectory with context

**Atomic Writes** *(SKP-003)*: All file mutations (ref counter increment, status transitions) use atomic write pattern:
1. Write to `{file}.tmp`
2. `mv` to target (atomic on POSIX)
3. In Agent Teams mode, vision writes are serialized through the team lead (teammates report via SendMessage, lead writes)

**Acceptance Criteria:**
- Ref counters in `grimoires/loa/visions/index.md` accurately reflect surfacing events
- Lore elevation suggestion shown when threshold crossed
- References traceable in trajectory logs
- Concurrent runs don't corrupt counters or status *(SKP-003)*

### FR-6: Configuration & Feature Flags

New configuration section in `.loa.config.yaml`:

```yaml
vision_registry:
  # Master switch — enables vision loading during planning
  enabled: false  # Default OFF — opt-in

  # Shadow mode — log matches without presenting them
  shadow_mode: true  # Default ON when first enabled

  # Shadow cycles before summary prompt
  shadow_cycles_before_prompt: 2

  # Status filter — which vision statuses to surface
  status_filter:
    - Captured
    - Exploring

  # Minimum tag overlap to consider a vision relevant
  min_tag_overlap: 2

  # Maximum visions to present per planning session
  max_visions_per_session: 3

  # Reference threshold for lore elevation suggestion
  ref_elevation_threshold: 3

  # Experimental: Allow AI to propose vision-inspired requirements
  propose_requirements: false  # Behind feature flag, default OFF
```

**Acceptance Criteria:**
- All settings have sensible defaults
- Feature is completely inert when `enabled: false`
- `propose_requirements: false` disables FR-4 even when visions are shown
- Configuration documented in `.loa.config.yaml.example`

### FR-7: Vision Library Extraction *(SKP-004)*

Extract shared vision logic from `bridge-vision-capture.sh` into a stable library:

**File**: `.claude/scripts/vision-lib.sh`

Shared functions:
- `vision_load_index()` — parse index.md into structured data
- `vision_match_tags()` — tag overlap matching (extracted from `check_relevant_visions()`)
- `vision_record_ref()` — atomic reference counting (extracted from `record_reference()`)
- `vision_validate_entry()` — schema validation for entries
- `vision_sanitize_text()` — content sanitization for context injection

Both `bridge-vision-capture.sh` (capture) and `vision-registry-query.sh` (query) source this library. Changes to shared logic are tested in one place.

**Acceptance Criteria:**
- `bridge-vision-capture.sh` sources `vision-lib.sh` instead of inline functions
- `vision-registry-query.sh` sources `vision-lib.sh` for matching
- Breaking changes to lib require version bump in header comment
- Unit tests cover all exported functions

### FR-8: Vision Query Script

New script `vision-registry-query.sh` for programmatic vision filtering:

```bash
# Query visions by tag relevance
.claude/scripts/vision-registry-query.sh \
  --tags "architecture,multi-model" \
  --status "Captured,Exploring" \
  --min-overlap 2 \
  --max-results 3 \
  --json
```

**Acceptance Criteria:**
- Returns JSON array of matching visions with scores
- Handles empty registry gracefully (returns `[]`)
- Handles missing index.md gracefully
- Uses tag-to-path mapping from `bridge-vision-capture.sh` for consistency

## 5. Technical & Non-Functional Requirements

### Performance
- Vision loading must add <2s to Phase 0
- Shadow mode logging must be non-blocking
- Vision query script must complete in <1s for registries up to 100 entries

### Backward Compatibility
- Default configuration (`enabled: false`) means zero behavioral change
- Existing `/plan-and-analyze` tests must continue to pass
- No changes to `discovering-requirements/SKILL.md` persona behavior when disabled

### Security
- Vision files are in State Zone (read/write permitted)
- No new external API calls — all data is local
- Vision content never sent to external models (stays in planning context only)

### Testing *(IMP-010)*
- End-to-end integration tests that exercise the full pipeline: config → query → match → present → track
- Unit tests for `vision-registry-query.sh` with fixture registries (empty, single, many, malformed)
- Regression tests for 2-model and 3-model scoring (from cycle-040 bug fix) remain passing
- Shadow mode log format validated by test

### Observability
- Shadow mode logs to trajectory (auditable)
- Vision surfacing events logged with provenance
- Configuration changes tracked via standard config diff

## 6. Scope & Prioritization

### Sprint 1: Foundation — Schema, Library, Query, Shadow Mode
- FR-1.5: Vision registry schema definition
- FR-6: Configuration & feature flags
- FR-7: Vision library extraction (`vision-lib.sh`)
- FR-8: Vision query script (`vision-registry-query.sh`)
- FR-3: Shadow mode logging
- FR-5: Vision reference tracking (with atomic writes)

### Sprint 2: Active Presentation
- FR-1: Vision registry loading in Phase 0
- FR-2: Vision presentation in discovery phases (with content sanitization)
- SKILL.md integration for discovering-requirements

### Sprint 3: Creative Agency (Experimental)
- FR-4: Vision-inspired requirement proposals (with sanitization)
- PRD section generation for vision-inspired requirements
- Lore elevation automation

### Out of Scope
- Cross-repo vision synchronization
- Automated vision generation (Bridgebuilder already handles this)
- Changes to the Bridgebuilder persona
- Retroactive population of visions from existing bridge reviews
- Vision integration into `/architect` or `/sprint-plan` (future cycles)

## 7. Risks & Dependencies

### Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| No visions in registry (cold start) | High for new repos | Low — feature gracefully degrades | Shadow mode handles empty state; feature is opt-in |
| Vision noise — irrelevant matches | Medium | Medium — user frustration | Tag overlap threshold + max visions cap |
| Shadow mode never graduates | Low | Medium — feature stays invisible | Auto-prompt after N cycles |
| Vision-inspired requirements confuse scope | Medium | Medium — scope creep | Separate PRD section, explicit tagging, behind feature flag |

### Dependencies

| Dependency | Status | Risk |
|-----------|--------|------|
| `bridge-vision-capture.sh` | Fully implemented | Low — functions being extracted to `vision-lib.sh` *(SKP-004)* |
| `check_relevant_visions()` function | Implemented in capture script | Low — extracting to shared lib |
| `record_reference()` function | Implemented in capture script | Low — extracting to shared lib |
| Vision Registry directory structure | Initialized (empty) | Low — needs index.md bootstrap + schema *(SKP-001)* |
| Bridgebuilder generating VISION findings | Active | None — already produces output |

## 8. Design Principles

### The 20% Rule
This feature enables the AI equivalent of Google's "20% time." The AI observes patterns across bridge reviews and brings forward insights that the human might not have seen. But it does so within guardrails — opt-in, shadow mode, feature flags, and explicit user choice at every step.

### Shadow-First Graduation
Every experimental feature follows: **shadow → prompt → active → default**. No feature reaches "active" without shadow validation. No feature reaches "default" without proven value across multiple cycles.

### Provenance is Non-Negotiable
Every vision surfaced traces back to: bridge ID, iteration number, PR number, finding ID, and timestamp. The user can always answer "where did this idea come from?" with a concrete reference.

### Peer, Not Autopilot
The AI proposes; the human disposes. Vision-inspired requirements are clearly marked, presented separately, and individually accept/reject. The AI's creative agency is expressed through what it chooses to surface, not through unilateral action.
