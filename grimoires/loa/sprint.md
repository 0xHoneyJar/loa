# Sprint Plan: Bridge Inquiry Infrastructure — Active Discovery, Research Mode & Temporal Lore

> Cycle: cycle-030
> PRD: [grimoires/loa/prd.md](grimoires/loa/prd.md)
> SDD: [grimoires/loa/sdd.md](grimoires/loa/sdd.md)
> Sprints: 6 (3 original provenance + 3 inquiry infrastructure)
> Team: 1 agent (Claude)

---

## Sprint 1: Core Skills Manifest + Classification + Segmented Output [COMPLETED]

## Sprint 2: AGENT-CONTEXT Enrichment + Validation + Tests [COMPLETED]

## Sprint 3: Bridge Iteration 1 — Idempotent Cache + Test Harness Polish (BB-5ac44d) [COMPLETED]

---

## Sprint 4: Temporal Lore Depth + Vision Registry Activation (FR-5, FR-3)

**Goal**: Extend lore entries with lifecycle metadata and activate the vision registry during bridge cycles. These are the highest-value, lowest-risk enhancements — they enrich every future bridge review.

### Task 4.1: Lore lifecycle schema extension

**Description**: Extend the lore YAML schema in `.claude/data/lore/discovered/patterns.yaml` with an optional `lifecycle` block containing `created`, `references`, `last_seen`, `seen_in`, `repos`, and `significance` fields. Existing entries gain the block lazily on first reference.

**Acceptance Criteria**:
- `lifecycle` block defined per SDD 3.5.1 schema
- Missing `lifecycle` treated as defaults (references=0, significance=one-off)
- Existing entries remain valid YAML without modification
- `yq` can read and write lifecycle fields

**Estimated Effort**: Small

### Task 4.2: Reference tracking function in lore-discover.sh

**Description**: Implement `update_lore_reference()` function in `lore-discover.sh` per SDD 3.5.2. This function increments reference count, updates `last_seen`, appends to `seen_in`, and auto-classifies significance (one-off / recurring / foundational).

**Acceptance Criteria**:
- `update_lore_reference(entry_id, bridge_id, repo_name, lore_file)` implemented
- Idempotent: same bridge_id does not create duplicate `seen_in` entry
- Significance auto-classification: 1 ref = one-off, 2-5 = recurring, 6+ or 3+ repos = foundational
- All YAML writes use `yq -i` (no string concatenation)
- Bridge ID and repo name validated against `[a-zA-Z0-9._-]`

**Estimated Effort**: Medium
**Dependencies**: Task 4.1

### Task 4.3: Reference scanning during bridge reviews

**Description**: Implement `scan_for_lore_references()` per SDD 3.5.3. After each bridge review, scan findings and insights for lore term matches (by ID or term) and call `update_lore_reference()` for each match.

**Acceptance Criteria**:
- Scans both `discovered/patterns.yaml` and `discovered/visions.yaml`
- Matches by exact entry ID or case-insensitive term match
- Integrates into bridge orchestrator finalization (after `SIGNAL:LORE_DISCOVERY`)
- Non-blocking: failures logged but don't halt bridge

**Estimated Effort**: Medium
**Dependencies**: Task 4.2

### Task 4.4: Vision relevance checking

**Description**: Implement `check_relevant_visions()` function per SDD 3.3.1. Scans `grimoires/loa/visions/index.md` for visions with tags overlapping the PR change categories. Returns list of relevant vision IDs.

**Acceptance Criteria**:
- Reads vision index, filters by status (Captured or Exploring)
- Extracts PR tags from diff file paths (architecture, security, constraints, multi-model, testing)
- Minimum 2-tag overlap for relevance (configurable)
- Returns vision IDs as newline-separated list
- Empty index or no matches returns empty (graceful)

**Estimated Effort**: Medium

### Task 4.5: Vision activation in bridge orchestrator

**Description**: Integrate vision checking into bridge orchestrator pre-review phase. When relevant visions found: transition Captured → Exploring, increment reference count via `record_reference()`, include vision content in review context.

**Acceptance Criteria**:
- `SIGNAL:VISION_CHECK` emitted before each bridge review
- `update_vision_status()` called for Captured → Exploring transitions
- `record_reference()` called for each activated vision
- Vision IDs recorded in bridge state (`visions_referenced` array)
- Configurable via `run_bridge.vision_registry.activation_enabled` (default: true)

**Estimated Effort**: Medium
**Dependencies**: Task 4.4

### Task 4.6: Memory query lore extension + tests

**Description**: Extend `memory-query.sh` with `--lore` flags for querying lore entries by references, significance, and repo. Write unit tests for all Task 4.x features.

**Acceptance Criteria**:
- `memory-query.sh --lore` lists all lore entries
- `memory-query.sh --lore --sort-by references` sorts by reference count desc
- `memory-query.sh --lore --significance foundational` filters by significance
- Unit test: reference tracking (increment, dedup, significance classification)
- Unit test: vision relevance checking (tag overlap, status filtering)
- All tests pass

**Estimated Effort**: Medium
**Dependencies**: Tasks 4.2, 4.4

---

## Sprint 5: Cross-Repository Pattern Query + Research Mode (FR-1, FR-2)

**Goal**: Enable the bridge to discover cross-repo structural parallels and support divergent exploration iterations.

### Task 5.1: Cross-repo pattern query script

**Description**: Create `.claude/scripts/cross-repo-query.sh` per SDD 3.1. Extracts patterns from PR diff, resolves ecosystem repos (sibling directory → config override → GitHub API fallback), queries reality files, and outputs structured JSON matches.

**Acceptance Criteria**:
- Script accepts `--diff`, `--ecosystem`, `--output`, `--budget`, `--max-repos` flags
- Repo resolution: sibling dir → config override → `REMOTE:` fallback
- Pattern extraction from diff: function names, architectural keywords, protocol refs
- Reality file queries via `qmd-context-query.sh` for local repos
- AGENT-CONTEXT extraction via `butterfreezone-mesh.sh` for remote repos
- JSON output per SDD 3.1.1 schema
- 5s per-repo timeout, 15s total timeout
- Graceful degradation: skip unreachable repos with warning

**Estimated Effort**: Large

### Task 5.2: Cross-repo integration in bridge orchestrator

**Description**: Add `SIGNAL:CROSS_REPO_QUERY` to bridge orchestrator pre-review phase. Cache results in `.run/cross-repo-context.json`. Inject matches into Bridgebuilder review prompt under `<!-- cross-repo-context -->` markers.

**Acceptance Criteria**:
- Signal emitted before each bridge review (after preflight)
- Results cached per bridge run (refreshed if bridge_id changes)
- Context injected into review prompt as markdown
- `cross_repo_query` metrics recorded in bridge state
- Configurable via `run_bridge.cross_repo_query.enabled` (default: true)

**Estimated Effort**: Medium
**Dependencies**: Task 5.1

### Task 5.3: Research mode state machine extension

**Description**: Add `RESEARCHING` state to bridge orchestrator per SDD 3.2.1. After iteration 1, if research mode enabled and not already used, transition to RESEARCHING. Research iterations produce SPECULATION-only findings with N/A score excluded from flatline.

**Acceptance Criteria**:
- `RESEARCHING` state in state machine (between ITERATING cycles)
- Guard: max 1 research iteration per run (configurable)
- Trigger: after iteration 1 (configurable via `trigger_after_iteration`)
- Score exclusion: research iterations not counted in flatline trajectory
- `SIGNAL:RESEARCH_ITERATION` emitted for skill layer
- `research_iterations_completed` tracked in bridge state
- State recovery: resume from RESEARCHING → skip to ITERATING

**Estimated Effort**: Large
**Dependencies**: Task 5.2

### Task 5.4: Research iteration prompt composition

**Description**: When `SIGNAL:RESEARCH_ITERATION` fires, compose a divergent exploration prompt including cross-repo context (FR-1), lore entries sorted by reference count (FR-5), and relevant visions (FR-3). Instruct the model to produce SPECULATION-only findings.

**Acceptance Criteria**:
- Prompt includes cross-repo context from `.run/cross-repo-context.json`
- Prompt includes top lore entries (sorted by `lifecycle.references` desc)
- Prompt includes relevant vision content from activated visions
- Model instructed to produce only `severity: SPECULATION` findings
- Output saved to `.run/bridge-reviews/{bridge_id}-research-{N}.md`
- Lore discovery runs on research output

**Estimated Effort**: Medium
**Dependencies**: Tasks 5.2, 5.3

### Task 5.5: Config schema + tests

**Description**: Add `cross_repo_query` and `research_mode` config keys per SDD 4.1. Write unit tests for cross-repo query (pattern extraction, repo resolution) and research mode (state transitions, score exclusion).

**Acceptance Criteria**:
- Config keys added to `.loa.config.yaml.example`
- Config validation: all new keys have documented defaults
- Unit test: cross-repo pattern extraction from sample diff
- Unit test: repo resolution (sibling, override, remote fallback)
- Unit test: research mode state transitions (ITERATING → RESEARCHING → ITERATING)
- Unit test: flatline score trajectory excludes research iterations
- All tests pass

**Estimated Effort**: Medium
**Dependencies**: Tasks 5.1, 5.3

---

## Sprint 6: Multi-Model Inquiry Mode + Integration (FR-4)

**Goal**: Extend Flatline Protocol with collaborative inquiry mode and integrate all features end-to-end.

### Task 6.1: Inquiry mode in flatline-orchestrator.sh

**Description**: Add `inquiry` mode to flatline-orchestrator.sh per SDD 3.4. Runs 3 parallel collaborative queries (structural, historical, governance) and synthesizes results instead of cross-scoring.

**Acceptance Criteria**:
- `--mode inquiry` flag accepted alongside existing `adversarial` mode
- 3 parallel queries with distinct prompts per SDD 3.4.2
- Uses configured primary/secondary models (alternating assignment)
- Results synthesized into unified JSON per SDD 3.4.3 schema
- Output saved to `grimoires/loa/a2a/flatline/{phase}-inquiry.json`
- Existing content redaction applied to all inquiry outputs
- Graceful fallback: 2 queries if only 2 models available
- Budget bounded by `flatline_protocol.inquiry.budget_cents`

**Estimated Effort**: Large

### Task 6.2: Inquiry integration with research mode

**Description**: When `run_bridge.research_mode.inquiry_enabled` is true and a research iteration fires, trigger inquiry mode via `SIGNAL:INQUIRY_MODE`. Feed cross-repo context and lore into inquiry prompts.

**Acceptance Criteria**:
- `SIGNAL:INQUIRY_MODE` triggers `flatline-orchestrator.sh --mode inquiry`
- Cross-repo context injected as system context for all 3 queries
- Inquiry results appended to research iteration output
- Configurable via `run_bridge.research_mode.inquiry_enabled` (default: false)

**Estimated Effort**: Medium
**Dependencies**: Tasks 5.3, 6.1

### Task 6.3: Manual inquiry via /flatline-review

**Description**: Extend `/flatline-review` skill to accept `--inquiry` flag for manual invocation of inquiry mode on any document.

**Acceptance Criteria**:
- `/flatline-review --inquiry grimoires/loa/sdd.md` triggers inquiry mode
- Argument parsing handles `--inquiry` alongside existing flags
- Results displayed in same format as adversarial review (perspectives + synthesis)
- Output saved to standard flatline output directory

**Estimated Effort**: Small
**Dependencies**: Task 6.1

### Task 6.4: End-to-end integration test

**Description**: Run a simulated bridge iteration that exercises all 5 features: cross-repo query → vision check → convergent review → research iteration → lore reference tracking.

**Acceptance Criteria**:
- Bridge state shows cross_repo_query metrics populated
- Vision reference count incremented for relevant visions
- Research iteration produces SPECULATION findings (score: N/A)
- Lore entries gain lifecycle metadata after bridge review
- Flatline trajectory only counts convergent iterations
- All existing tests continue to pass

**Estimated Effort**: Medium
**Dependencies**: Tasks 6.2, 6.3

### Task 6.5: Config documentation + validation

**Description**: Update `.loa.config.yaml.example` with all new config keys, add validation in config loader, and document the feature enablement order.

**Acceptance Criteria**:
- All new config keys documented in `.loa.config.yaml.example` with comments
- Config validation warns on invalid values (not fails — graceful)
- Feature enablement order documented (FR-5 → FR-3 → FR-1 → FR-2 → FR-4)
- NOTES.md updated with implementation summary

**Estimated Effort**: Small
**Dependencies**: Task 6.4
