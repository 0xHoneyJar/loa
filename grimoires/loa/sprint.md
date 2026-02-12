# Sprint Plan: Run Bridge — Autonomous Excellence Loops with Grounded Truth

**PRD**: grimoires/loa/prd.md (v1.0.0)
**SDD**: grimoires/loa/sdd.md (v1.0.0)
**Issue**: [loa #292](https://github.com/0xHoneyJar/loa/issues/292)
**Version**: 1.0.0
**Date**: 2026-02-12
**Cycle**: cycle-005

---

## Overview

| Aspect | Value |
|--------|-------|
| Total Sprints | 3 |
| Team | 1 AI agent (Claude Code via `/run sprint-plan`) |
| Sprint Duration | Autonomous execution (~2-4 hours each) |
| Global Sprint IDs | sprint-8, sprint-9, sprint-10 |
| Dependencies | `/run sprint-plan` (stable), `/ride` (stable), RTFM (stable), Bridgebuilder (stable) |

## Sprint Sequencing Rationale

Sprint 1 builds the foundation layers (lore + vision + GT) that have no dependencies on the bridge loop itself. Sprint 2 builds the core orchestrator that depends on the foundation. Sprint 3 wires everything together with GitHub trail, Bridgebuilder integration, RTFM gate, and the `/run-bridge` command. Each sprint produces independently testable artifacts.

---

## Sprint 1: Foundation — Lore Knowledge Base, Vision Registry, Grounded Truth

### Sprint Goal

Build the three data infrastructure layers that support the bridge loop: the Mibera lore knowledge base at `.claude/data/lore/`, the vision registry at `grimoires/loa/visions/`, and the Grounded Truth generator extending `/ride` with `--ground-truth`. Each layer is independently useful and testable.

### Deliverables

- [ ] Mibera lore knowledge base with core + neuromancer entries
- [ ] Lore README with integration instructions for skill authors
- [ ] Vision registry directory with index template
- [ ] Grounded Truth generator script (checksums, token validation)
- [ ] `/ride` SKILL.md extension with Phase 11 (GT generation)
- [ ] `/ride` command extension with `--ground-truth` and `--non-interactive` flags
- [ ] BATS tests for lore validation and GT generation
- [ ] Framework eval tasks for lore schema and GT structure

### Technical Tasks

#### Task 1.1: Mibera Lore Knowledge Base — Core Entries **[FR-3, SDD §3.6]**

Create the lore directory structure and populate core Mibera entries.

**Files to create:**
- `.claude/data/lore/index.yaml` — registry with categories and tags
- `.claude/data/lore/mibera/core.yaml` — kaironic time, cheval, network mysticism, techno-animism
- `.claude/data/lore/mibera/cosmology.yaml` — Milady/Mibera duality, BGT triskelion, Honey/Bera
- `.claude/data/lore/mibera/rituals.yaml` — bridge loop as refinement ceremony, sprint as ritual, review as invocation
- `.claude/data/lore/mibera/glossary.yaml` — 15+ term definitions for agent consumption
- `.claude/data/lore/README.md` — how to reference lore in skills

**Acceptance Criteria:**
- [ ] `index.yaml` follows schema from SDD §3.6.2 with `version`, `categories`, `tags`
- [ ] Every entry has `id`, `term`, `short` (<20 tokens), `context` (<200 tokens), `source`, `tags`
- [ ] Core entries include: `kaironic-time`, `cheval`, `network-mysticism`, `milady-mibera-duality`, `triskelion`, `techno-animism`, `hounfour`, `flatline`, `loa-rides`
- [ ] `glossary.yaml` contains ≥15 term definitions
- [ ] `source` fields cite actual issues, lore articles, or RFCs (e.g., "Issue #292, Comment 3")
- [ ] `related` fields cross-reference other entries correctly
- [ ] All YAML parses cleanly with `yq`

#### Task 1.2: Neuromancer Lore Entries **[FR-3, SDD §3.6]**

Create the Neuromancer/Sprawl Trilogy lore entries and Loa feature mappings.

**Files to create:**
- `.claude/data/lore/neuromancer/concepts.yaml` — ICE, jacking in, cyberspace, the matrix, simstim, flatline
- `.claude/data/lore/neuromancer/mappings.yaml` — concept → Loa feature mappings

**Acceptance Criteria:**
- [ ] Neuromancer concepts include: `ice`, `jacking-in`, `cyberspace`, `the-matrix`, `simstim`, `flatline`, `wintermute`, `neuromancer-ai`
- [ ] Each mapping has `concept`, `loa_feature`, `description` fields
- [ ] Mappings include: ICE→`run-mode-ice.sh`, jacking in→`/run jack-in`, simstim→`/simstim`, flatline→flatline detection
- [ ] All entries follow the same schema as Mibera entries
- [ ] `index.yaml` updated with neuromancer category

#### Task 1.3: Vision Registry Directory **[FR-4, SDD §3.7]**

Create the vision registry structure at `grimoires/loa/visions/`.

**Files to create:**
- `grimoires/loa/visions/index.md` — overview template
- `grimoires/loa/visions/entries/.gitkeep` — entries directory

**Acceptance Criteria:**
- [ ] `index.md` follows format from SDD §3.7.2 with table headers and statistics section
- [ ] Table headers: ID, Title, Source, Status, Tags
- [ ] Statistics section: Total captured, Exploring, Implemented, Deferred (all 0 initially)
- [ ] `entries/` directory created with `.gitkeep`
- [ ] Template is valid markdown that renders cleanly

#### Task 1.4: Grounded Truth Generator Script **[FR-2, SDD §3.5]**

Create the helper script for GT mechanical operations (checksums, token validation).

**File to create:**
- `.claude/scripts/ground-truth-gen.sh`

**Acceptance Criteria:**
- [ ] Accepts `--reality-dir`, `--output-dir`, `--max-tokens-per-section` flags
- [ ] Computes SHA-256 checksums for all source files referenced in reality/ extraction
- [ ] Writes `checksums.json` with `generated_at`, `git_sha`, `algorithm`, `files` fields
- [ ] Validates token budget via `wc -w` approximation (1 token ≈ 0.75 words)
- [ ] Reports validation results: section name, word count, estimated tokens, PASS/WARN
- [ ] Creates output directory structure: `index.md`, `api-surface.md`, `architecture.md`, `contracts.md`, `behaviors.md` (content generated by skill, not this script)
- [ ] Sources `bootstrap.sh` for path resolution
- [ ] Cross-platform compatible (`set -euo pipefail`, BSD/GNU `stat`)
- [ ] Exit codes: 0 (success), 1 (validation failure), 2 (missing dependencies)

#### Task 1.5: Extend `/ride` with Ground Truth Phase **[FR-2, SDD §3.5.1]**

Extend the riding-codebase SKILL.md and ride command to support GT generation.

**Files to modify:**
- `.claude/skills/riding-codebase/SKILL.md` — add Phase 11
- `.claude/commands/ride.md` — add `--ground-truth` and `--non-interactive` arguments

**Acceptance Criteria:**
- [ ] SKILL.md Phase 11 documents: read reality/ results → synthesize GT files → generate checksums → validate tokens
- [ ] `--ground-truth` flag added to ride command arguments list
- [ ] `--non-interactive` flag added to ride command arguments list
- [ ] When `--ground-truth --non-interactive`: phases 1 (context), 3 (legacy), 8 (deprecation) are skipped
- [ ] GT outputs added to ride command `outputs:` list
- [ ] Phase 11 skipped when `--ground-truth` is NOT passed (existing behavior unchanged)
- [ ] Phase 11 invokes `ground-truth-gen.sh` for checksums and validation

#### Task 1.6: Lore and GT Tests **[SDD §9]**

Create BATS tests and framework eval tasks for the new infrastructure.

**Files to create:**
- `evals/tests/lore-validation.bats` — YAML schema validation, cross-references
- `evals/tests/ground-truth-gen.bats` — checksum generation, token validation
- `evals/tasks/framework/lore-index-valid.yaml` — eval task
- `evals/tasks/framework/lore-entries-schema.yaml` — eval task
- `evals/tasks/framework/gt-checksums-match.yaml` — eval task

**Acceptance Criteria:**
- [ ] Lore BATS: validates index.yaml has version and categories, all referenced files exist, all entries have required fields, glossary has ≥15 entries
- [ ] GT BATS: validates checksum generation produces valid JSON, token budget check reports correctly, missing reality-dir returns exit code 2
- [ ] Eval tasks validate same properties as BATS tests but through eval harness
- [ ] All tests pass on first run

#### Task 1.7: Version Bump and Changelog **[Standard]**

Bump version for Sprint 1 completion.

**Files to modify:**
- `.loa-version.json` — bump to next appropriate version
- `.claude/loa/CLAUDE.loa.md` — version header
- `README.md` — version badge
- `CHANGELOG.md` — new entry

**Acceptance Criteria:**
- [ ] Version bumped consistently across all files
- [ ] CHANGELOG entry documents: lore KB, vision registry, GT generator, /ride extension
- [ ] No stale version references

---

## Sprint 2: Bridge Core — Orchestrator, Findings Parser, State Management

### Sprint Goal

Build the bridge loop orchestrator with state management, findings parser, flatline detection, and findings-to-sprint-plan generation. The orchestrator can run a complete bridge loop locally without GitHub trail or Bridgebuilder integration (using mock findings for testing).

### Deliverables

- [ ] Bridge orchestrator script with full state machine
- [ ] Bridge findings parser (markdown → structured JSON)
- [ ] Bridge state file schema and management
- [ ] Flatline detection algorithm
- [ ] Findings-to-sprint-plan generation
- [ ] Resume and context recovery logic
- [ ] Vision capture script
- [ ] BATS tests and eval tasks

### Technical Tasks

#### Task 2.1: Bridge State Schema and Management **[SDD §3.2, §4]**

Define and implement the bridge state file management.

**Files to create:**
- `.claude/scripts/bridge-state.sh` — state management helper functions

**Acceptance Criteria:**
- [ ] `init_bridge_state()` creates `.run/bridge-state.json` with schema version 1
- [ ] `update_bridge_state()` transitions state: PREFLIGHT → JACK_IN → ITERATING → FINALIZING → JACKED_OUT
- [ ] `update_iteration()` appends iteration data to iterations array
- [ ] `read_bridge_state()` reads and validates state file
- [ ] State transitions validate legal moves (reject JACKED_OUT → ITERATING, etc.)
- [ ] `update_flatline()` tracks consecutive flatline count
- [ ] `update_metrics()` accumulates total sprints, files, findings, visions
- [ ] All state operations use atomic writes (write to .tmp, mv)
- [ ] Sources `bootstrap.sh`

#### Task 2.2: Bridge Findings Parser **[SDD §3.3]**

Create the script that extracts structured findings from Bridgebuilder review markdown.

**File to create:**
- `.claude/scripts/bridge-findings-parser.sh`

**Acceptance Criteria:**
- [ ] Accepts `--input` (markdown file) and `--output` (JSON file) flags
- [ ] Extracts findings between `<!-- bridge-findings-start -->` and `<!-- bridge-findings-end -->` markers
- [ ] Parses each finding: severity (CRITICAL/HIGH/MEDIUM/LOW/VISION), category, file reference, description, suggestion
- [ ] Computes severity-weighted score: CRITICAL=10, HIGH=5, MEDIUM=2, LOW=1, VISION=0
- [ ] Output JSON: `{"findings": [...], "total": N, "by_severity": {...}, "severity_weighted_score": N}`
- [ ] Handles malformed findings gracefully (logs warning, skips)
- [ ] Handles empty input (0 findings, score 0)
- [ ] Uses `jq` for JSON output assembly
- [ ] Exit codes: 0 (success), 1 (parse error), 2 (missing input)

#### Task 2.3: Flatline Detection **[SDD §3.3, NFR-1]**

Implement the flatline detection algorithm within the bridge state management.

**Integration into bridge-state.sh:**

**Acceptance Criteria:**
- [ ] `is_flatlined()` compares current_score to initial_score: `(current / initial) < threshold`
- [ ] Returns true only when flatline persists for `consecutive_flatline` iterations (default: 2)
- [ ] Handles edge cases: initial_score=0 (no findings → immediate flatline), threshold=0 (never flatline)
- [ ] Configurable threshold from `.loa.config.yaml` (`run_bridge.defaults.flatline_threshold`, default: 0.05)
- [ ] Configurable consecutive count from config (`run_bridge.defaults.consecutive_flatline`, default: 2)
- [ ] Logs flatline detection events to bridge state

#### Task 2.4: Bridge Orchestrator Script **[SDD §3.1]**

Create the main orchestrator that runs the bridge loop.

**File to create:**
- `.claude/scripts/bridge-orchestrator.sh`

**Acceptance Criteria:**
- [ ] Sources `bootstrap.sh`, `bridge-state.sh`
- [ ] Accepts `--depth`, `--per-sprint`, `--resume`, `--from` flags
- [ ] Preflight: validates `run_bridge.enabled: true`, checks beads health, validates branch via ICE
- [ ] Creates feature branch `feature/bridge-{bridge_id}` via ICE
- [ ] Iteration loop: sprint plan → execute → review → flatline check → (generate new plan if not flatlined)
- [ ] Delegates sprint execution to `/run sprint-plan` (reuses existing infrastructure)
- [ ] Calls findings parser after each Bridgebuilder review
- [ ] Calls flatline detection after each iteration
- [ ] Updates bridge state at each step
- [ ] Finalization: delegates GT update and RTFM pass
- [ ] Circuit breaker: max depth (default 5), per-iteration timeout (4h), total timeout (24h)
- [ ] On HALT: saves state, creates INCOMPLETE PR, logs resume instructions
- [ ] `--resume` reads state file, validates, continues from last completed iteration
- [ ] Cross-platform compatible (`set -euo pipefail`)
- [ ] Exit codes: 0 (complete), 1 (halted), 2 (config error)

#### Task 2.5: Vision Capture Script **[SDD §3.7.4]**

Create the script that extracts VISION-type findings into the vision registry.

**File to create:**
- `.claude/scripts/bridge-vision-capture.sh`

**Acceptance Criteria:**
- [ ] Accepts `--findings` (JSON), `--bridge-id`, `--iteration`, `--pr`, `--output-dir` flags
- [ ] Filters findings JSON for `severity: "VISION"` entries
- [ ] For each vision: creates `grimoires/loa/visions/entries/vision-NNN.md` using SDD §3.7.3 format
- [ ] Updates `grimoires/loa/visions/index.md` with new entries
- [ ] Vision numbering: reads existing entries to determine next number
- [ ] Sets status to "Captured" for all new visions
- [ ] Returns count of visions captured (echo to stdout)
- [ ] Handles 0 visions gracefully (no-op, returns 0)

#### Task 2.6: Per-Sprint Mode **[SDD §5]**

Implement the `--per-sprint` execution mode in the bridge orchestrator.

**Integration into bridge-orchestrator.sh:**

**Acceptance Criteria:**
- [ ] When `--per-sprint`: calls `/run sprint-{N}` instead of `/run sprint-plan`
- [ ] Bridgebuilder review runs after each individual sprint
- [ ] Next sprint's tasks generated from single-sprint findings
- [ ] Max sprints per iteration capped at 3 (from SDD §3.4)
- [ ] State file tracks per-sprint vs full-plan mode in `config.per_sprint`
- [ ] Flatline detection still operates on severity-weighted scores

#### Task 2.7: Bridge Core Tests **[SDD §9]**

Create BATS tests and eval tasks for bridge core infrastructure.

**Files to create:**
- `evals/tests/bridge-orchestrator.bats` — state transitions, flatline, resume
- `evals/tests/bridge-findings-parser.bats` — markdown parsing, severity weighting
- `evals/tests/bridge-vision-capture.bats` — vision extraction, index update
- `evals/tasks/framework/bridge-state-schema-valid.yaml`
- `evals/tasks/framework/bridge-findings-parser-works.yaml`

**Acceptance Criteria:**
- [ ] State management BATS: init, transitions, illegal transitions rejected, atomic writes
- [ ] Findings parser BATS: known-good markdown → expected JSON, empty input, malformed input, severity weighting
- [ ] Vision capture BATS: creates entries, updates index, handles 0 visions, numbering
- [ ] Eval tasks validate same properties through eval harness
- [ ] All tests pass on first run

---

## Sprint 3: Integration — GitHub Trail, Bridgebuilder, RTFM Gate, Command Registration

### Sprint Goal

Wire all components together: GitHub trail enforcement, lore-aware Bridgebuilder integration, RTFM final gate, `/run-bridge` command and skill registration, golden path state detection, configuration, constraints, and end-to-end testing. This sprint produces the shippable `/run-bridge` command.

### Deliverables

- [ ] GitHub trail script (comments, PR updates, vision links)
- [ ] Bridgebuilder BEAUVOIR.md extension for lore-aware reviews
- [ ] Structured findings format in Bridgebuilder output
- [ ] RTFM integration as post-loop gate
- [ ] `/run-bridge` command and skill registration
- [ ] Golden path bridge state detection
- [ ] Configuration section in `.loa.config.yaml`
- [ ] Constraint amendments in `constraints.json`
- [ ] End-to-end integration tests
- [ ] CLAUDE.loa.md documentation update
- [ ] Version bump and final CHANGELOG

### Technical Tasks

#### Task 3.1: GitHub Trail Script **[FR-6, SDD §3.8]**

Create the script that handles all GitHub interactions for the bridge loop.

**File to create:**
- `.claude/scripts/bridge-github-trail.sh`

**Acceptance Criteria:**
- [ ] `comment` subcommand: posts Bridgebuilder review as PR comment via `gh pr comment`
- [ ] Comment includes `<!-- bridge-iteration: {bridge_id}:{iteration} -->` marker for dedup
- [ ] `update-pr` subcommand: updates PR body with iteration summary table via `gh pr edit`
- [ ] `vision` subcommand: posts vision link as PR comment
- [ ] All subcommands accept `--pr` and `--bridge-id` flags
- [ ] Graceful degradation when `gh` not available (logs warning, returns 0)
- [ ] Comment format matches SDD §3.8.2
- [ ] PR body table format matches SDD §3.8.3
- [ ] Sources `bootstrap.sh`

#### Task 3.2: Bridgebuilder Lore-Aware Persona Extension **[FR-3, SDD §3.6.4]**

Extend the Bridgebuilder BEAUVOIR.md to reference lore entries.

**File to modify:**
- `.claude/skills/bridgebuilder-review/resources/BEAUVOIR.md`

**Acceptance Criteria:**
- [ ] New "Lore Integration" section added to persona
- [ ] Instructions to load relevant lore from `.claude/data/lore/` at review time
- [ ] Use `short` field for inline references, `context` field for teaching moments
- [ ] Example mappings provided: circuit breaker → kaironic-time, multi-model → hounfour
- [ ] Structured findings format documented: `<!-- bridge-findings-start/end -->` markers
- [ ] Finding template with severity, category, file, description, suggestion fields
- [ ] VISION finding type documented for speculative insights
- [ ] Existing persona content preserved unchanged

#### Task 3.3: RTFM Integration **[FR-5, SDD §3.9]**

Integrate RTFM testing as the final gate of the bridge loop.

**Integration into bridge-orchestrator.sh:**

**Acceptance Criteria:**
- [ ] After loop termination, RTFM runs on: GT `index.md`, `README.md`, any new protocol docs
- [ ] RTFM invoked via existing `/rtfm` skill mechanism
- [ ] On all PASS → continue to PR finalization
- [ ] On FAILURE → generate single documentation fix sprint, execute, re-test (1 retry max)
- [ ] On second FAILURE → log warning, continue anyway (not a blocker)
- [ ] RTFM results recorded in bridge state (`finalization.rtfm_passed`)
- [ ] RTFM report path included in PR summary

#### Task 3.4: `/run-bridge` Command and Skill Registration **[SDD §3.10]**

Create the command file and skill registration.

**Files to create:**
- `.claude/commands/run-bridge.md` — command routing
- `.claude/skills/run-bridge/index.yaml` — skill registration per SDD §3.10
- `.claude/skills/run-bridge/SKILL.md` — skill workflow

**Acceptance Criteria:**
- [ ] Command file routes `/run-bridge` to the run-bridge skill
- [ ] `index.yaml` matches SDD §3.10 spec: name, version, danger_level (high), triggers, inputs, outputs
- [ ] SKILL.md documents: input guardrails check, argument parsing, orchestrator invocation, progress reporting
- [ ] SKILL.md references bridge-orchestrator.sh as the execution engine
- [ ] Danger level set to `high` (autonomous execution)
- [ ] Triggers include: `/run-bridge`, `bridge loop`, `excellence loop`, `iterative review`

#### Task 3.5: Golden Path Bridge State Detection **[SDD §6.2]**

Extend `golden-path.sh` to detect and report bridge loop state.

**File to modify:**
- `.claude/scripts/golden-path.sh`

**Acceptance Criteria:**
- [ ] `golden_detect_bridge_state()` reads `.run/bridge-state.json`, returns state or "none"
- [ ] When state is ITERATING: `/loa` reports iteration progress (N/depth, score, initial)
- [ ] When state is HALTED: `/loa` reports halt reason and resume instructions
- [ ] When state is FINALIZING: `/loa` reports finalization progress
- [ ] Function returns empty string when no bridge state file exists
- [ ] Does not break existing golden path detection (all 33 BATS tests still pass)

#### Task 3.6: Configuration and Constraints **[SDD §6.1, §7]**

Add configuration section and constraint amendments.

**Files to modify:**
- `.loa.config.yaml.example` — add `run_bridge:` section per SDD §6.1
- `.claude/data/constraints.json` — add C-BRIDGE-001 through C-BRIDGE-005
- `.claude/loa/CLAUDE.loa.md` — add Run Bridge section documenting the feature

**Acceptance Criteria:**
- [ ] `run_bridge:` config section added with all fields from SDD §6.1
- [ ] Config includes: enabled, defaults (depth, per_sprint, flatline_threshold, consecutive_flatline), timeouts, github_trail, ground_truth, vision_registry, rtfm, lore
- [ ] 5 new constraints added per SDD §7.1
- [ ] Constraints have unique IDs: C-BRIDGE-001 through C-BRIDGE-005
- [ ] CLAUDE.loa.md updated with Run Bridge section documenting `/run-bridge` command and bridge state recovery
- [ ] Process compliance table updated with bridge-specific rules

#### Task 3.7: Lore Integration in Discovering-Requirements and Golden Path **[FR-3, SDD §3.6.4]**

Add lore references to at least 2 more skills (beyond Bridgebuilder) to meet the "3 skills reference lore" acceptance criterion.

**Files to modify:**
- `.claude/skills/discovering-requirements/SKILL.md` — add lore reference for archetypes
- `.claude/commands/loa.md` (or golden path script) — add lore reference for naming context

**Acceptance Criteria:**
- [ ] discovering-requirements SKILL.md references lore for philosophical framing during PRD creation
- [ ] `/loa` command references lore glossary for naming explanations (e.g., "Why 'Loa'?")
- [ ] References use `short` field for inline, `context` for detail when asked
- [ ] No forced or unnatural lore injection — references are contextually appropriate
- [ ] At least 3 skills total reference `.claude/data/lore/`: bridgebuilder, discovering-requirements, golden path

#### Task 3.8: End-to-End Integration Tests **[SDD §9.3]**

Create integration tests and final BATS tests.

**Files to create:**
- `evals/tests/bridge-github-trail.bats` — comment format, PR body update
- `evals/tests/bridge-integration.bats` — state detection in golden path
- `evals/tasks/framework/golden-path-bridge-detection.yaml`
- `evals/tasks/framework/vision-entries-traceability.yaml`

**Acceptance Criteria:**
- [ ] GitHub trail BATS: validates comment format, marker presence, graceful `gh` degradation
- [ ] Integration BATS: golden path detects bridge state, reports progress, handles missing state
- [ ] Eval tasks validate: bridge state detection, vision entry traceability
- [ ] All existing BATS tests still pass (regression: 33+ tests from golden-path.bats)
- [ ] All existing eval tasks still pass (regression: 32+ tasks)

#### Task 3.9: Version Bump and Final Changelog **[Standard]**

Final version bump and comprehensive CHANGELOG.

**Files to modify:**
- `.loa-version.json` — bump version
- `.claude/loa/CLAUDE.loa.md` — version header
- `README.md` — version badge and feature list
- `CHANGELOG.md` — comprehensive entry

**Acceptance Criteria:**
- [ ] Version bumped consistently
- [ ] CHANGELOG entry covers all 6 functional requirements
- [ ] README updated with `/run-bridge` in command table
- [ ] README feature table includes: Run Bridge, Grounded Truth, Lore KB, Vision Registry
- [ ] Release name set (e.g., "Bridge Release")

---

## Risk Assessment

| Risk | Sprint | Mitigation |
|------|--------|------------|
| Bridge orchestrator complexity | 2 | Build on proven `/run sprint-plan` patterns, shell scripts with JSON state |
| Findings parser fragility | 2 | Strict marker-delimited format, graceful degradation on parse errors |
| Lore entries feel artificial | 1 | Curated entries from actual issue discussions, optional integration |
| GT token budget exceeded | 1 | Validation in `ground-truth-gen.sh`, configurable limits |
| Existing tests break | 3 | Run full regression (BATS + evals) at every task boundary |
| GitHub trail rate limiting | 3 | Graceful degradation, batch comments where possible |

## Success Metrics

| Metric | Target | Sprint |
|--------|--------|--------|
| Lore entries created | ≥25 (Mibera) + ≥10 (Neuromancer) | 1 |
| GT generator validates token budgets | 100% sections checked | 1 |
| Bridge state transitions tested | All valid + illegal transitions | 2 |
| Findings parser accuracy | 100% on known-good input | 2 |
| Skills referencing lore | ≥3 | 3 |
| BATS tests passing | All existing + all new | 3 |
| Eval tasks passing | All existing + all new | 3 |

## Dependencies

| Dependency | Required By | Status |
|-----------|------------|--------|
| `/run sprint-plan` | Sprint 2 (bridge orchestrator) | Stable (v1.15.1+) |
| `/ride` skill | Sprint 1 (GT extension) | Stable |
| RTFM skill | Sprint 3 (final gate) | Stable |
| Bridgebuilder skill | Sprint 3 (persona extension) | Stable |
| `jq` | All sprints | Required dependency |
| `yq` | Sprint 1 (lore YAML) | Recommended dependency |
| `gh` CLI | Sprint 3 (GitHub trail) | Required for trail, graceful degradation |
