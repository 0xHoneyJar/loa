# PRD: Bridge Inquiry Infrastructure — Active Discovery, Research Mode & Temporal Lore

> Cycle: cycle-030 | Author: zkSoju + Claude
> Source: [PR #392 Post-Bridge Inquiry](https://github.com/0xHoneyJar/loa/pull/392) (Bridgebuilder architectural review)
> Priority: P1 (infrastructure — enables ecosystem-scale insight production across bridge reviews)

---

## 1. Problem Statement

The Bridgebuilder review system produces its deepest insights when operating at the architectural timescale — connecting patterns across repositories, surfacing Ostrom-style governance parallels, and discovering structural isomorphisms between disparate systems. But today, these connections depend on **human memory or serendipity**. Five specific gaps limit the system's capacity for architectural inquiry:

1. **No cross-repository pattern matching**: Before each bridge review, no automated step queries "what patterns in the other repos resemble the changes in this PR?" Connections that require holding loa, loa-hounfour, loa-freeside, and loa-finn in mind simultaneously are invisible to the agent.

2. **No research mode for bridge iterations**: The bridge loop is convergent by design (score must decrease). Architectural inquiry is divergent (understanding must increase). There is no iteration mode that explores connections without generating convergence-scored findings.

3. **Vision Registry is passive**: 7 visions captured, 0 explored. The MAY permission exists ("MAY allocate time for Vision Registry exploration") but no automated mechanism surfaces relevant visions during bridge cycles.

4. **Multi-model review is QA-only**: The Flatline Protocol uses multi-model adversarial review for quality assurance. The same multi-model approach is not available for architectural inquiry — asking different models to find different kinds of connections (structural, historical, mathematical).

5. **Lore entries are static**: 3 discovered patterns exist as YAML, but no metadata tracks how often or recently they're referenced. Patterns with lasting architectural significance are indistinguishable from one-off observations.

### Evidence

- `bridge-orchestrator.sh`: EXPLORING state exists (v1.39.0) but is unused — the vision sprint pathway is stubbed but no cross-repo query runs pre-review
- `grimoires/loa/visions/index.md`: 7 visions, 1 Exploring, 0 Proposed, 0 Implemented — the registry accumulates but never activates
- `.claude/data/lore/discovered/patterns.yaml`: 3 entries, all from PR #324 — no lifecycle metadata, no reference tracking
- `flatline-orchestrator.sh`: 4 parallel reviews (Primary/Secondary x review/skeptic) — no "inquiry" mode
- `.loa.config.yaml` `butterfreezone.ecosystem`: 3 repos configured, but no pre-review cross-repo query exists

---

## 2. Goals & Success Metrics

### Goals

| # | Goal | Measurable Outcome |
|---|------|---------------------|
| G1 | Surface cross-repo patterns before each bridge review | Pre-review query returns >=1 structural connection for PRs touching shared patterns |
| G2 | Enable divergent exploration within bridge loops | Research iterations generate SPECULATION findings without affecting convergence score |
| G3 | Activate vision registry during bridge cycles | Relevant visions surfaced and explored when bridge review references captured themes |
| G4 | Support multi-model architectural inquiry | Inquiry mode runs alongside or instead of adversarial QA, producing ensemble insights |
| G5 | Track lore pattern lifecycle with temporal depth | Each lore entry accumulates reference count, recency, and cross-repo spread metadata |

### Success Metrics

- Pre-review cross-repo query returns results for >=50% of bridge iterations on multi-repo ecosystems
- At least 1 research iteration is exercised during a 3+ depth bridge run
- Vision registry transitions at least 1 vision from Captured → Exploring → Proposed across 2 bridge cycles
- Lore entries gain `references` and `last_seen` fields populated by bridge reviews
- No regression in bridge convergence speed (research mode is additive, not replacing)

---

## 3. User & Stakeholder Context

### Primary Persona: Bridgebuilder Agent

The Bridgebuilder reviewing a PR. Currently limited to the diff + immediate context. With cross-repo queries, research mode, and vision activation, the Bridgebuilder can:
- See structural parallels across the ecosystem before starting review
- Spend one iteration exploring connections without convergence pressure
- Check if captured visions are relevant to the current changes
- Request multi-model ensemble for architectural (not just QA) analysis

### Secondary Persona: Human Architect

A developer reading bridge review comments on PRs. Currently sees findings + insights from a single model's perspective. With these enhancements:
- Pre-review context section shows cross-repo connections discovered automatically
- Research iteration insights are clearly labeled as exploratory (non-convergent)
- Vision references link to the registry for deeper exploration
- Multi-model inquiry produces richer, more diverse architectural analysis

---

## 4. Functional Requirements

### FR-1: Cross-Repository Pattern Query

Add a pre-review phase to the bridge orchestrator that queries ecosystem repos for structural parallels.

**Algorithm:**
1. Extract key patterns from the current PR diff (function signatures, module names, architectural patterns)
2. For each configured ecosystem repo in `.loa.config.yaml` `butterfreezone.ecosystem`:
   - Query that repo's reality files (`grimoires/loa/reality/`) via the existing QMD interface
   - Search for structural matches (shared types, similar function signatures, parallel architecture)
3. Compile matches into a structured context block injected into the Bridgebuilder prompt

**Acceptance Criteria:**
- New function `cross_repo_pattern_query()` in bridge orchestrator
- Reads ecosystem config from `.loa.config.yaml`
- Queries reality files (checksums.json, index.md) for each configured repo
- Returns structured JSON with: `repo`, `pattern`, `similarity_type`, `file_path`
- Graceful degradation: if a repo is unreachable or has no reality files, skip with warning
- Results injected into Bridgebuilder review prompt under `<!-- cross-repo-context -->` markers
- Configurable via `run_bridge.cross_repo_query.enabled` (default: true)

### FR-2: Research Mode for Bridge Iterations

Add an optional "research iteration" to the bridge loop that generates SPECULATION findings without affecting the convergence score.

**Behavior:**
1. After the first convergent iteration (not before — need baseline context), the orchestrator MAY insert a research iteration
2. Research iterations:
   - Generate findings with severity `SPECULATION` only (score weight: 0)
   - Explore connections to lore, visions, and cross-repo patterns
   - Expand the lore index with discovered patterns
   - Are NOT counted toward flatline detection
3. Research iteration output is saved to `.run/bridge-reviews/{bridge_id}-research-{N}.md`
4. Maximum 1 research iteration per bridge run (configurable)

**Acceptance Criteria:**
- New state `RESEARCHING` in bridge orchestrator state machine (between ITERATING cycles)
- Research iterations produce only SPECULATION-severity findings
- Research iteration score is `N/A` — excluded from flatline trajectory
- Bridge state file tracks `research_iterations_completed` count
- Configurable via `run_bridge.research_mode.enabled` (default: false, opt-in)
- Configurable via `run_bridge.research_mode.max_per_run` (default: 1)
- Research iteration prompt includes cross-repo context (FR-1) and lore context

### FR-3: Vision Registry Activation

Add a "vision check" phase to bridge iterations that scans captured visions for relevance to the current PR.

**Behavior:**
1. Before each bridge review (after cross-repo query), scan `grimoires/loa/visions/index.md`
2. For each vision with status `Captured` or `Exploring`:
   - Compare vision tags against PR change categories
   - Check if any vision themes appear in the diff or recent findings
3. If a relevant vision is found:
   - Include vision content in the research iteration prompt (FR-2)
   - Update vision status to `Exploring` if currently `Captured`
   - Record the reference in the vision entry (`Refs` count increment)
4. After bridge cycle completes, if a vision was explored with substantive findings:
   - Offer to promote vision to `Proposed` status

**Acceptance Criteria:**
- New function `check_relevant_visions()` in bridge orchestrator
- Reads vision index and individual vision entries
- Tag-based relevance matching (vision tags vs PR labels, file paths, finding categories)
- Vision status transitions logged in bridge state file
- Reference count incremented for each bridge cycle that references the vision
- `update_vision_status()` in `bridge-vision-capture.sh` handles Captured → Exploring transition
- Configurable via `run_bridge.vision_registry.activation_enabled` (default: true)

### FR-4: Multi-Model Architectural Inquiry

Extend the Flatline Protocol with an "inquiry" mode alongside the existing adversarial QA mode.

**Behavior:**
1. Inquiry mode runs 3 parallel queries (not adversarial — collaborative):
   - **Structural model**: "What patterns in this change are isomorphic to patterns in [cross-repo context]?"
   - **Historical model**: "What precedents in blue-chip open source projects parallel this approach?"
   - **Governance model**: "What governance or economic implications does this architectural choice have?"
2. Results are synthesized (not cross-scored) into an ensemble insight document
3. Inquiry mode is triggered during research iterations (FR-2) or manually via `/flatline-review --inquiry`

**Acceptance Criteria:**
- New mode `inquiry` in flatline-orchestrator.sh (alongside existing `adversarial`)
- 3 parallel queries with distinct prompts (structural, historical, governance)
- Results synthesized into unified document (not scored/ranked like adversarial)
- Output saved to `grimoires/loa/a2a/flatline/{phase}-inquiry.json`
- Integrated into bridge research iterations when `run_bridge.research_mode.inquiry_enabled` is true
- Manual trigger: `/flatline-review --inquiry [document]`
- Uses configured models from `flatline_protocol.models` (primary + secondary)
- Graceful fallback to 2 queries if only 2 models available

### FR-5: Temporal Depth in Lore System

Add lifecycle metadata to lore entries that tracks reference frequency, recency, and cross-repo spread.

**Schema Extension:**
```yaml
entries:
  - id: graceful-degradation-cascade
    term: "Graceful Degradation Cascade"
    short: "..."
    context: "..."
    source: "..."
    tags: [discovered, architecture]
    # NEW: Temporal metadata
    lifecycle:
      created: "2026-02-14"
      references: 3
      last_seen: "2026-02-20"
      seen_in:
        - "bridge-20260214-e8fa94 / PR #324"
        - "bridge-20260219-16e623 / PR #368"
        - "bridge-20260220-5ac44d / PR #392"
      repos: ["loa", "loa-hounfour"]
      significance: "recurring"  # one-off | recurring | foundational
```

**Behavior:**
1. During each bridge review, `lore-discover.sh` scans findings for lore term references
2. When a lore term is referenced (by ID or term match in findings/insights):
   - Increment `references` count
   - Update `last_seen` to current date
   - Append bridge reference to `seen_in` array
   - Add repo to `repos` set if cross-repo reference
3. Auto-classify significance:
   - `one-off`: 1 reference
   - `recurring`: 2-5 references
   - `foundational`: 6+ references OR referenced in 3+ repos

**Acceptance Criteria:**
- Lore YAML schema extended with `lifecycle` block (backward-compatible: missing = defaults)
- `lore-discover.sh` updated to record references during bridge reviews
- New function `update_lore_reference()` handles increment logic
- Significance auto-classification based on reference count and repo spread
- Existing entries migrated lazily (lifecycle block added on first reference)
- Query support: `memory-query.sh --lore --sort-by references` (top referenced patterns)
- No breaking changes to existing lore consumers

---

## 5. Technical & Non-Functional Requirements

### NF-1: Performance

- Cross-repo query (FR-1) adds no more than 5s per configured repo (filesystem-based, no API calls)
- Research iteration (FR-2) adds 1 iteration's worth of time (bounded by `per_iteration_hours`)
- Vision check (FR-3) adds <1s (index scan + tag match)
- Inquiry mode (FR-4) runs in parallel, bounded by existing flatline timeouts
- Lore reference tracking (FR-5) adds <500ms per bridge review

### NF-2: Backward Compatibility

- All features are opt-in or defaulted to non-breaking behavior
- Cross-repo query and vision activation default to true (low cost, high value)
- Research mode defaults to false (additive iteration, user must opt in)
- Inquiry mode is manual-only unless explicitly enabled for research iterations
- Existing lore entries work unchanged (lifecycle block is optional, added lazily)

### NF-3: Determinism

- Cross-repo query results are deterministic given same filesystem state
- Research mode trigger is deterministic (after iteration 1, if enabled, if not already used)
- Vision relevance matching is tag-based (deterministic for same tags)
- Lore reference tracking is append-only and idempotent (same bridge ID = no duplicate)

### NF-4: Graceful Degradation

- If ecosystem repos are unreachable: skip cross-repo query, log warning
- If no reality files exist for a repo: skip that repo
- If vision registry is empty: skip vision check silently
- If Flatline models are unavailable: skip inquiry mode, log warning
- If lore files are corrupt: skip reference tracking, don't fail the bridge

---

## 6. Scope & Prioritization

### In Scope (MVP)

| Priority | Feature | Rationale |
|----------|---------|-----------|
| P1 | FR-5: Temporal lore depth | Lowest risk, highest immediate value — enriches every future bridge review |
| P1 | FR-3: Vision registry activation | Leverages existing infrastructure (70% done), enables vision lifecycle |
| P2 | FR-1: Cross-repo pattern query | Core enabler for architectural insight, depends on ecosystem config |
| P2 | FR-2: Research mode | New state machine state, depends on FR-1 and FR-3 for full value |
| P3 | FR-4: Multi-model inquiry | Most complex, depends on FR-2 for integration point |

### Out of Scope

- Cross-repo code analysis (reading actual source from other repos — only reality files)
- Automatic lore entry creation from inquiry results (manual curation preserved)
- Vision auto-promotion without human review (Proposed → Implemented requires human)
- Flatline Protocol schema changes (inquiry mode uses same output format)
- Changes to the convergent bridge loop mechanics (research mode is additive only)

---

## 7. Risks & Dependencies

| Risk | Impact | Mitigation |
|------|--------|------------|
| Cross-repo reality files out of date | Stale pattern matches | Warn if reality file age >7 days |
| Research mode overused | Slows bridge convergence | Default to off, max 1 per run |
| Vision relevance matching too loose | Noisy vision activations | Tag-based matching with minimum 2-tag overlap |
| Inquiry mode models disagree | Conflicting architectural insights | Synthesis (not scoring) — present all perspectives |
| Lore reference tracking inflates counts | False significance classification | Deduplicate by bridge ID, require term match not substring |

### Dependencies

- `bridge-orchestrator.sh` (state machine extension for RESEARCHING)
- `bridge-vision-capture.sh` (vision activation + reference counting)
- `lore-discover.sh` (temporal metadata recording)
- `flatline-orchestrator.sh` (inquiry mode addition)
- `.loa.config.yaml` schema (new config keys for all features)
- QMD interface / reality files (cross-repo query source)
