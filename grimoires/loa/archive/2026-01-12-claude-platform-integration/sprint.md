# Sprint Plan: Claude Platform Integration

**Version:** 1.0.0
**Status:** Ready for Implementation
**Date:** 2026-01-11
**Author:** Sprint Planning Agent

---

## Sprint Overview

| Field | Value |
|-------|-------|
| PRD Reference | `grimoires/loa/claude-platform-integration-prd.md` |
| SDD Reference | `grimoires/loa/claude-platform-integration-sdd.md` |
| Total Sprints | 4 |
| Team Size | Solo developer |
| Strategy | 1 phase per sprint |
| Target Version | v0.11.0 |

---

## Sprint Summary

| Sprint | Phase | Focus | Priority | Key Deliverables |
|--------|-------|-------|----------|------------------|
| 1 | Phase 1 | Agent Skills Adapter | P0 | skills-adapter.sh, frontmatter generation |
| 2 | Phase 2 | Structured Outputs & Thinking | P0 | schemas/, schema-validator.sh, thinking-logger.sh |
| 3 | Phase 3 | Tool Search & MCP | P1 | tool-search-adapter.sh, cache system |
| 4 | Phase 4 | Context Management | P1 | context-manager.sh, simplified checkpoint |

---

## Sprint 1: Agent Skills Adapter

**Goal:** Enable Loa skills to be discovered and loaded as Claude Agent Skills through runtime format generation.

**Phase:** 1 (Agent Skills Refactoring)
**Priority:** P0 (Critical)

### Tasks

#### TASK-1.1: Create Skills Adapter Script Foundation

**Description:** Create the base `skills-adapter.sh` script with command structure and help documentation.

**File:** `.claude/scripts/skills-adapter.sh`

**Acceptance Criteria:**
- [ ] Script exists at `.claude/scripts/skills-adapter.sh`
- [ ] Script is executable (`chmod +x`)
- [ ] Implements `--help` with usage documentation
- [ ] Implements subcommands: `generate`, `list`, `upload`, `sync`
- [ ] Uses `set -euo pipefail` for safety
- [ ] Validates dependencies (`yq`, `jq`)

**Dependencies:** None

**Testing:**
- [ ] `skills-adapter.sh --help` shows usage
- [ ] `skills-adapter.sh list` lists all skills
- [ ] Script fails gracefully if `yq` not installed

---

#### TASK-1.2: Implement Frontmatter Generation

**Description:** Implement the `generate` command that transforms index.yaml to Claude Agent Skills frontmatter format.

**Acceptance Criteria:**
- [ ] `skills-adapter.sh generate <skill>` outputs YAML frontmatter + SKILL.md
- [ ] Extracts `name`, `description`, `version`, `triggers` from index.yaml
- [ ] Description uses first line only (single-line format)
- [ ] Triggers array preserved as YAML list
- [ ] Original SKILL.md content appended unchanged
- [ ] Handles all 10 existing skills without errors

**Dependencies:** TASK-1.1

**Testing:**
- [ ] Generate for `discovering-requirements` produces valid frontmatter
- [ ] Generate for all 10 skills succeeds
- [ ] Output is valid YAML (validate with `yq`)
- [ ] SKILL.md body unchanged in output

---

#### TASK-1.3: Implement List Command with Status

**Description:** Implement `list` command showing all skills with their Claude Agent Skills compatibility status.

**Acceptance Criteria:**
- [ ] Lists all skills from `.claude/skills/`
- [ ] Shows name, version, and status for each
- [ ] Status indicates if skill can be converted (has required fields)
- [ ] Formatted as table for readability
- [ ] Supports `--json` flag for machine-readable output

**Dependencies:** TASK-1.1

**Testing:**
- [ ] `skills-adapter.sh list` shows all 10 skills
- [ ] `skills-adapter.sh list --json` outputs valid JSON
- [ ] Skills missing required fields show warning status

---

#### TASK-1.4: Implement Upload Command (Stub)

**Description:** Implement `upload` command as a stub that validates prerequisites but logs "API upload not yet available."

**Acceptance Criteria:**
- [ ] `skills-adapter.sh upload <skill>` validates skill exists
- [ ] Checks for `CLAUDE_API_KEY` environment variable
- [ ] Generates frontmatter to verify it works
- [ ] Logs clear message: "API upload ready for future implementation"
- [ ] Returns exit code 0 (success) for validation-only mode

**Dependencies:** TASK-1.2

**Testing:**
- [ ] Upload without API key shows helpful error
- [ ] Upload with invalid skill name shows error
- [ ] Upload with valid skill completes validation

---

#### TASK-1.5: Add Configuration Support

**Description:** Add `agent_skills` configuration section to `.loa.config.yaml` schema.

**File:** `.loa.config.yaml` (documentation), CLAUDE.md (documentation)

**Acceptance Criteria:**
- [ ] Configuration schema documented in CLAUDE.md
- [ ] `agent_skills.enabled` (boolean, default: true)
- [ ] `agent_skills.load_mode` ("dynamic" | "eager", default: "dynamic")
- [ ] `agent_skills.api_upload` (boolean, default: false)
- [ ] Skills adapter reads config values
- [ ] Feature can be disabled via config

**Dependencies:** TASK-1.1

**Testing:**
- [ ] Config parsing works with valid YAML
- [ ] Default values applied when config missing
- [ ] `enabled: false` prevents skill generation

---

#### TASK-1.6: Write Unit Tests for Skills Adapter

**Description:** Create comprehensive unit tests using bats.

**File:** `tests/unit/skills-adapter.bats`

**Acceptance Criteria:**
- [ ] Test file exists at `tests/unit/skills-adapter.bats`
- [ ] Tests for `generate` command (valid/invalid input)
- [ ] Tests for `list` command (various skill counts)
- [ ] Tests for config parsing
- [ ] Tests for error handling
- [ ] All tests pass

**Dependencies:** TASK-1.1, TASK-1.2, TASK-1.3

**Testing:**
- [ ] `bats tests/unit/skills-adapter.bats` passes
- [ ] Coverage includes all major code paths

---

#### TASK-1.7: Update Documentation

**Description:** Update CLAUDE.md and create README for the skills adapter.

**Acceptance Criteria:**
- [ ] CLAUDE.md updated with Agent Skills section
- [ ] Documents hybrid approach (runtime generation)
- [ ] Documents configuration options
- [ ] Documents CLI usage
- [ ] Includes migration notes (none needed - backward compatible)

**Dependencies:** TASK-1.1 through TASK-1.5

**Testing:**
- [ ] Documentation matches implementation
- [ ] Examples in docs work as written

---

### Sprint 1 Completion Criteria

- [ ] All 7 tasks completed
- [ ] All unit tests passing
- [ ] `skills-adapter.sh generate` works for all 10 skills
- [ ] Documentation updated
- [ ] No breaking changes to existing functionality

---

## Sprint 2: Structured Outputs & Extended Thinking

**Goal:** Implement JSON schema validation for agent outputs and extended thinking logging for complex reasoning agents.

**Phase:** 2 (Structured Outputs & Extended Thinking)
**Priority:** P0 (Critical)

### Tasks

#### TASK-2.1: Create Schemas Directory Structure

**Description:** Create `.claude/schemas/` directory with initial schema files.

**Acceptance Criteria:**
- [ ] Directory `.claude/schemas/` created
- [ ] `README.md` with schema documentation
- [ ] Empty placeholder files for PRD, SDD, Sprint, Audit schemas
- [ ] `trajectory-entry.schema.json` placeholder
- [ ] Directory tracked in git (not in .gitignore)

**Dependencies:** None

**Testing:**
- [ ] Directory exists and is tracked
- [ ] README explains schema purpose

---

#### TASK-2.2: Define PRD JSON Schema

**Description:** Create comprehensive JSON Schema for PRD output validation.

**File:** `.claude/schemas/prd.schema.json`

**Acceptance Criteria:**
- [ ] Valid JSON Schema Draft-07 format
- [ ] Validates version field (semver pattern)
- [ ] Validates status field (enum)
- [ ] Validates problem_statement (minLength: 100)
- [ ] Validates goals array (minItems: 1)
- [ ] Validates functional_requirements array
- [ ] Validates user_stories array structure
- [ ] Validates risks array structure
- [ ] Schema is self-documenting with descriptions

**Dependencies:** TASK-2.1

**Testing:**
- [ ] Schema validates existing PRD successfully
- [ ] Schema rejects malformed PRD
- [ ] `ajv compile -s prd.schema.json` succeeds

---

#### TASK-2.3: Define SDD JSON Schema

**Description:** Create JSON Schema for SDD output validation.

**File:** `.claude/schemas/sdd.schema.json`

**Acceptance Criteria:**
- [ ] Valid JSON Schema Draft-07 format
- [ ] Validates version, status, date fields
- [ ] Validates system_architecture section
- [ ] Validates component_design array
- [ ] Validates data_architecture section
- [ ] Validates security_architecture section
- [ ] Schema is self-documenting

**Dependencies:** TASK-2.1

**Testing:**
- [ ] Schema validates existing SDD successfully
- [ ] Schema rejects malformed SDD

---

#### TASK-2.4: Define Sprint JSON Schema

**Description:** Create JSON Schema for sprint plan validation.

**File:** `.claude/schemas/sprint.schema.json`

**Acceptance Criteria:**
- [ ] Valid JSON Schema Draft-07 format
- [ ] Validates sprint_overview section
- [ ] Validates sprints array with nested tasks
- [ ] Validates task structure (id, description, acceptance_criteria)
- [ ] Validates dependencies between tasks
- [ ] Schema is self-documenting

**Dependencies:** TASK-2.1

**Testing:**
- [ ] Schema validates this sprint plan successfully
- [ ] Schema rejects malformed sprint plans

---

#### TASK-2.5: Define Trajectory Entry Schema

**Description:** Create JSON Schema for trajectory log entries including extended thinking.

**File:** `.claude/schemas/trajectory-entry.schema.json`

**Acceptance Criteria:**
- [ ] Valid JSON Schema Draft-07 format
- [ ] Validates ts (ISO 8601 format)
- [ ] Validates agent field (enum of 8 agents)
- [ ] Validates phase field (enum)
- [ ] Validates thinking_trace object (steps, duration, tokens)
- [ ] Validates grounding object (type, refs)
- [ ] Backward compatible with existing trajectory format

**Dependencies:** TASK-2.1

**Testing:**
- [ ] Schema validates existing trajectory entries
- [ ] Schema validates new thinking_trace entries

---

#### TASK-2.6: Create Schema Validator Script

**Description:** Create `schema-validator.sh` for validating outputs against schemas.

**File:** `.claude/scripts/schema-validator.sh`

**Acceptance Criteria:**
- [ ] Script exists at `.claude/scripts/schema-validator.sh`
- [ ] Implements `validate <file>` command
- [ ] Implements `list` command showing available schemas
- [ ] Supports `--schema <name>` to override auto-detection
- [ ] Supports `--mode strict|warn|disabled`
- [ ] Auto-detects schema based on file path
- [ ] Uses `ajv-cli` if available, falls back to `jq`
- [ ] Returns appropriate exit codes

**Dependencies:** TASK-2.1 through TASK-2.5

**Testing:**
- [ ] Validates valid PRD with exit code 0
- [ ] Rejects invalid PRD with exit code 1 (strict mode)
- [ ] Warns but passes in warn mode
- [ ] List shows all available schemas

---

#### TASK-2.7: Create Thinking Logger Script

**Description:** Create `thinking-logger.sh` for logging extended thinking traces to trajectory.

**File:** `.claude/scripts/thinking-logger.sh`

**Acceptance Criteria:**
- [ ] Script exists at `.claude/scripts/thinking-logger.sh`
- [ ] Implements `log <agent> <action> <trace>` command
- [ ] Implements `query --agent <agent> --since <timestamp>`
- [ ] Writes to `grimoires/loa/a2a/trajectory/<agent>-<date>.jsonl`
- [ ] Entry format matches trajectory-entry schema
- [ ] Handles multi-step thinking traces
- [ ] Validates against schema before writing

**Dependencies:** TASK-2.5, TASK-2.6

**Testing:**
- [ ] Log command creates valid trajectory entry
- [ ] Query command returns matching entries
- [ ] Invalid traces rejected

---

#### TASK-2.8: Add Extended Thinking Configuration

**Description:** Add `extended_thinking` configuration to `.loa.config.yaml` and skill index.yaml.

**Acceptance Criteria:**
- [ ] Config schema documented in CLAUDE.md
- [ ] `extended_thinking.enabled` (boolean, default: true)
- [ ] `extended_thinking.log_to_trajectory` (boolean, default: true)
- [ ] `extended_thinking.agents` (array, default: reviewing-code, auditing-security, designing-architecture)
- [ ] Skill index.yaml extended with `extended_thinking` section
- [ ] Update 3 skills (reviewing-code, auditing-security, designing-architecture)

**Dependencies:** TASK-2.7

**Testing:**
- [ ] Config parsing works
- [ ] Skills correctly inherit thinking settings

---

#### TASK-2.9: Add --validate-schema and --enable-thinking Flags

**Description:** Add command flags to relevant commands (stub implementation - actual command integration in skill updates).

**Acceptance Criteria:**
- [ ] Document flag format in CLAUDE.md
- [ ] `/plan-and-analyze --validate-schema` documented
- [ ] `/architect --validate-schema --enable-thinking` documented
- [ ] `/sprint-plan --validate-schema` documented
- [ ] `/review-sprint --enable-thinking` documented
- [ ] `/audit-sprint --validate-schema --enable-thinking` documented
- [ ] Commands pass flags to appropriate scripts

**Dependencies:** TASK-2.6, TASK-2.7

**Testing:**
- [ ] Documentation updated
- [ ] Flag parsing works in commands

---

#### TASK-2.10: Write Unit Tests for Schema Validator and Thinking Logger

**Description:** Create unit tests for Phase 2 scripts.

**Files:** `tests/unit/schema-validator.bats`, `tests/unit/thinking-logger.bats`

**Acceptance Criteria:**
- [ ] Tests for schema validation (valid/invalid inputs)
- [ ] Tests for schema auto-detection
- [ ] Tests for validation modes
- [ ] Tests for thinking logger
- [ ] Tests for trajectory entry format
- [ ] All tests pass

**Dependencies:** TASK-2.6, TASK-2.7

**Testing:**
- [ ] `bats tests/unit/schema-validator.bats` passes
- [ ] `bats tests/unit/thinking-logger.bats` passes

---

### Sprint 2 Completion Criteria

- [ ] All 10 tasks completed
- [ ] All schemas defined and valid
- [ ] Schema validator working with all modes
- [ ] Thinking logger integrated with trajectory
- [ ] All unit tests passing
- [ ] Documentation updated

---

## Sprint 3: Tool Search & MCP Enhancement

**Goal:** Integrate Claude's tool search capability with Loa's MCP registry for dynamic tool discovery.

**Phase:** 3 (Tool Search & MCP Enhancement)
**Priority:** P1 (High)

### Tasks

#### TASK-3.1: Create Tool Search Adapter Script Foundation

**Description:** Create the base `tool-search-adapter.sh` script with command structure.

**File:** `.claude/scripts/tool-search-adapter.sh`

**Acceptance Criteria:**
- [ ] Script exists at `.claude/scripts/tool-search-adapter.sh`
- [ ] Implements `--help` with usage documentation
- [ ] Implements subcommands: `search`, `discover`, `cache`
- [ ] Uses `set -euo pipefail` for safety
- [ ] Integrates with existing `mcp-registry.sh`

**Dependencies:** None

**Testing:**
- [ ] `tool-search-adapter.sh --help` shows usage
- [ ] Script fails gracefully if dependencies missing

---

#### TASK-3.2: Implement Search Command

**Description:** Implement `search <query>` command that searches MCP registry by name, description, and scopes.

**Acceptance Criteria:**
- [ ] Searches `.claude/mcp-registry.yaml` for matching servers
- [ ] Matches by server name (fuzzy)
- [ ] Matches by description keywords
- [ ] Matches by scope tags
- [ ] Returns ranked results (name match > description > scope)
- [ ] Supports `--json` flag for machine output
- [ ] Supports `--limit N` flag

**Dependencies:** TASK-3.1

**Testing:**
- [ ] Search "github" finds github server
- [ ] Search "issue" finds linear, github servers
- [ ] Empty query returns all servers
- [ ] JSON output is valid

---

#### TASK-3.3: Implement Discover Command

**Description:** Implement `discover` command that auto-discovers available MCP servers and their capabilities.

**Acceptance Criteria:**
- [ ] Reads all servers from MCP registry
- [ ] Checks if each server is configured (via `mcp-registry.sh check`)
- [ ] Returns list of available (configured) tools
- [ ] Includes tool capabilities/scopes
- [ ] Caches discovery results

**Dependencies:** TASK-3.1

**Testing:**
- [ ] Discover shows configured servers
- [ ] Discover excludes unconfigured servers
- [ ] Results include capabilities

---

#### TASK-3.4: Implement Cache System

**Description:** Implement caching for tool search results to improve performance.

**Cache Location:** `~/.loa/cache/tool-search/`

**Acceptance Criteria:**
- [ ] Cache directory created at `~/.loa/cache/tool-search/`
- [ ] Cache index tracks query -> result mappings
- [ ] Cache entries have TTL (default 24 hours)
- [ ] `cache list` shows cached entries
- [ ] `cache clear` removes all cached entries
- [ ] `cache clear <query>` removes specific entry
- [ ] Cache respects `tool_search.cache_ttl_hours` config

**Dependencies:** TASK-3.2

**Testing:**
- [ ] First search creates cache entry
- [ ] Second search returns cached result
- [ ] Expired cache triggers refresh
- [ ] Clear removes entries

---

#### TASK-3.5: Add Constructs Registry Connection (Optional)

**Description:** Extend tool search to include skills from Loa Constructs registry.

**Acceptance Criteria:**
- [ ] If `.claude/constructs/` exists, include in search
- [ ] Search constructs skills by name/description
- [ ] Constructs results marked with source
- [ ] Respects `tool_search.include_constructs` config
- [ ] Graceful handling if constructs not installed

**Dependencies:** TASK-3.2

**Testing:**
- [ ] Search includes constructs when present
- [ ] Search works without constructs
- [ ] Config toggle works

---

#### TASK-3.6: Add Tool Search Configuration

**Description:** Add `tool_search` configuration section to `.loa.config.yaml`.

**Acceptance Criteria:**
- [ ] `tool_search.enabled` (boolean, default: true)
- [ ] `tool_search.auto_discover` (boolean, default: true)
- [ ] `tool_search.cache_ttl_hours` (number, default: 24)
- [ ] `tool_search.include_constructs` (boolean, default: true)
- [ ] Configuration documented in CLAUDE.md

**Dependencies:** TASK-3.1

**Testing:**
- [ ] Config parsing works
- [ ] Disabled tool search returns empty
- [ ] TTL configurable

---

#### TASK-3.7: Enhance MCP Registry Script

**Description:** Enhance existing `mcp-registry.sh` with search capabilities.

**File:** `.claude/scripts/mcp-registry.sh`

**Acceptance Criteria:**
- [ ] Add `search <query>` command to mcp-registry.sh
- [ ] Reuse search logic from tool-search-adapter
- [ ] Maintain backward compatibility
- [ ] Update help documentation

**Dependencies:** TASK-3.2

**Testing:**
- [ ] Existing commands still work
- [ ] New search command works
- [ ] Help shows search command

---

#### TASK-3.8: Write Unit Tests for Tool Search

**Description:** Create unit tests for tool search adapter.

**File:** `tests/unit/tool-search-adapter.bats`

**Acceptance Criteria:**
- [ ] Tests for search command
- [ ] Tests for discover command
- [ ] Tests for cache operations
- [ ] Tests for constructs integration
- [ ] All tests pass

**Dependencies:** TASK-3.1 through TASK-3.5

**Testing:**
- [ ] `bats tests/unit/tool-search-adapter.bats` passes

---

### Sprint 3 Completion Criteria

- [ ] All 8 tasks completed
- [ ] Tool search working with MCP registry
- [ ] Cache system operational
- [ ] Constructs integration (if present)
- [ ] All unit tests passing
- [ ] Documentation updated

---

## Sprint 4: Context Management Optimization

**Goal:** Integrate client-side compaction with Lossless Ledger Protocol and simplify the checkpoint process.

**Phase:** 4 (Context Management)
**Priority:** P1 (High)

### Tasks

#### TASK-4.1: Create Context Manager Script Foundation

**Description:** Create the base `context-manager.sh` script for managing context compaction.

**File:** `.claude/scripts/context-manager.sh`

**Acceptance Criteria:**
- [ ] Script exists at `.claude/scripts/context-manager.sh`
- [ ] Implements `--help` with usage documentation
- [ ] Implements subcommands: `status`, `preserve`, `compact`, `checkpoint`
- [ ] Integrates with existing session-continuity protocol

**Dependencies:** None

**Testing:**
- [ ] `context-manager.sh --help` shows usage
- [ ] Status command shows current context state

---

#### TASK-4.2: Define Preservation Rules

**Description:** Define and implement rules for what content should be preserved during compaction.

**Acceptance Criteria:**
- [ ] NOTES.md Session Continuity section ALWAYS preserved
- [ ] Decision Log ALWAYS preserved
- [ ] Trajectory entries ALWAYS preserved (in external file)
- [ ] Tool results COMPACTABLE after use
- [ ] Thinking blocks COMPACTABLE after logged to trajectory
- [ ] Rules configurable via `.loa.config.yaml`

**Dependencies:** TASK-4.1

**Testing:**
- [ ] Preservation rules correctly identify content
- [ ] Config overrides work

---

#### TASK-4.3: Create Context Compaction Protocol

**Description:** Create protocol document defining compaction behavior.

**File:** `.claude/protocols/context-compaction.md`

**Acceptance Criteria:**
- [ ] Protocol document exists
- [ ] Defines preservation rules
- [ ] Defines compaction triggers
- [ ] Defines integration with Lossless Ledger
- [ ] Defines fallback behavior
- [ ] Consistent with existing protocol format

**Dependencies:** TASK-4.2

**Testing:**
- [ ] Protocol document valid markdown
- [ ] Rules match implementation

---

#### TASK-4.4: Implement Simplified Checkpoint

**Description:** Reduce synthesis checkpoint from 7 steps to 3 manual steps.

**Current (7 steps):**
1. Grounding verification
2. Negative grounding
3. Update Decision Log
4. Update Bead
5. Log trajectory
6. Decay to identifiers
7. Verify EDD

**Target (3 manual steps):**
1. Verify Decision Log updated
2. Verify Bead updated
3. Verify EDD test scenarios

**Acceptance Criteria:**
- [ ] Steps 1, 2, 5, 6 automated via context-manager
- [ ] `checkpoint` command runs automated checks
- [ ] Manual steps clearly documented
- [ ] Checkpoint command reports what's automated vs manual
- [ ] Update `synthesis-checkpoint.md` protocol

**Dependencies:** TASK-4.1, TASK-4.2

**Testing:**
- [ ] Automated checks run correctly
- [ ] Manual steps clearly reported
- [ ] Checkpoint integrates with existing protocol

---

#### TASK-4.5: Add Context Management Configuration

**Description:** Add `context_management` configuration section.

**Acceptance Criteria:**
- [ ] `context_management.client_compaction` (boolean, default: true)
- [ ] `context_management.preserve_notes_md` (boolean, default: true)
- [ ] `context_management.simplified_checkpoint` (boolean, default: true)
- [ ] Configuration documented in CLAUDE.md

**Dependencies:** TASK-4.1

**Testing:**
- [ ] Config parsing works
- [ ] Feature toggles work correctly

---

#### TASK-4.6: Integrate with Session Continuity Protocol

**Description:** Update session-continuity.md to reference context compaction.

**File:** `.claude/protocols/session-continuity.md`

**Acceptance Criteria:**
- [ ] Add section on context compaction integration
- [ ] Document how compaction interacts with tiered recovery
- [ ] Document simplified checkpoint process
- [ ] Update protocol dependency diagram

**Dependencies:** TASK-4.3, TASK-4.4

**Testing:**
- [ ] Protocol consistent with implementation
- [ ] No conflicts with existing behavior

---

#### TASK-4.7: Create Performance Benchmarks

**Description:** Create benchmarks to measure context efficiency improvements.

**File:** `.claude/scripts/context-benchmark.sh`

**Acceptance Criteria:**
- [ ] Script measures token usage before/after compaction
- [ ] Script measures checkpoint time
- [ ] Reports comparison to baseline
- [ ] Supports `--baseline` to set baseline
- [ ] Supports `--compare` to compare against baseline
- [ ] Results logged to `grimoires/loa/analytics/` (if THJ)

**Dependencies:** TASK-4.1

**Testing:**
- [ ] Benchmark runs without errors
- [ ] Results are reproducible

---

#### TASK-4.8: Write Unit Tests for Context Manager

**Description:** Create unit tests for context management.

**File:** `tests/unit/context-manager.bats`

**Acceptance Criteria:**
- [ ] Tests for preservation rules
- [ ] Tests for checkpoint automation
- [ ] Tests for config integration
- [ ] All tests pass

**Dependencies:** TASK-4.1 through TASK-4.5

**Testing:**
- [ ] `bats tests/unit/context-manager.bats` passes

---

#### TASK-4.9: Final Documentation Update

**Description:** Comprehensive documentation update for v0.11.0.

**Acceptance Criteria:**
- [ ] CLAUDE.md updated with all new features
- [ ] All new configuration options documented
- [ ] All new scripts documented
- [ ] All new protocols documented
- [ ] Migration notes (if any) included
- [ ] CHANGELOG.md updated

**Dependencies:** All previous tasks

**Testing:**
- [ ] Documentation complete and accurate
- [ ] No broken links

---

### Sprint 4 Completion Criteria

- [ ] All 9 tasks completed
- [ ] Context manager operational
- [ ] Simplified checkpoint working
- [ ] Performance benchmarks established
- [ ] All unit tests passing
- [ ] Complete documentation

---

## Integration Testing

After all sprints complete, run integration tests:

### Integration Test Suite

**File:** `tests/integration/claude-platform.bats`

**Test Cases:**

1. **Skills Adapter + Schema Validator Integration**
   - Generate skill frontmatter
   - Validate generated output against schema

2. **Thinking Logger + Trajectory Integration**
   - Log thinking trace
   - Verify trajectory entry valid

3. **Tool Search + MCP Registry Integration**
   - Search returns configured tools
   - Cache works across searches

4. **Context Manager + Session Continuity Integration**
   - Checkpoint preserves required content
   - Recovery works after checkpoint

5. **End-to-End Workflow**
   - Run `/plan-and-analyze --validate-schema`
   - Verify PRD validates
   - Verify thinking logged (if enabled)

---

## Risk Mitigation

| Risk | Mitigation | Sprint |
|------|------------|--------|
| Claude API changes | Feature flags, version pins | All |
| Schema too strict | Start with "warn" mode | 2 |
| Extended thinking costs | Opt-in per agent | 2 |
| Tool search conflicts | Fallback to manual MCP | 3 |
| Compaction data loss | Preserve critical sections | 4 |

---

## Success Metrics

### Per-Sprint Metrics

| Sprint | Metric | Target |
|--------|--------|--------|
| 1 | Skills adapter coverage | 10/10 skills |
| 2 | Schema validation | Zero violations |
| 3 | Tool search latency | <100ms cached |
| 4 | Checkpoint reduction | 7 → 3 manual steps |

### Overall v0.11.0 Metrics

| Metric | Target | Type |
|--------|--------|------|
| Token usage | -15% | Soft |
| Tool discovery | -80% latency | Soft |
| Context efficiency | +20% | Soft |
| Test coverage | 95%+ | Required |

---

## Appendix: File Inventory

### New Files (by Sprint)

**Sprint 1:**
- `.claude/scripts/skills-adapter.sh`
- `tests/unit/skills-adapter.bats`

**Sprint 2:**
- `.claude/schemas/prd.schema.json`
- `.claude/schemas/sdd.schema.json`
- `.claude/schemas/sprint.schema.json`
- `.claude/schemas/trajectory-entry.schema.json`
- `.claude/schemas/README.md`
- `.claude/scripts/schema-validator.sh`
- `.claude/scripts/thinking-logger.sh`
- `tests/unit/schema-validator.bats`
- `tests/unit/thinking-logger.bats`

**Sprint 3:**
- `.claude/scripts/tool-search-adapter.sh`
- `tests/unit/tool-search-adapter.bats`

**Sprint 4:**
- `.claude/scripts/context-manager.sh`
- `.claude/scripts/context-benchmark.sh`
- `.claude/protocols/context-compaction.md`
- `tests/unit/context-manager.bats`
- `tests/integration/claude-platform.bats`

### Modified Files

- `CLAUDE.md` (all sprints)
- `.claude/scripts/mcp-registry.sh` (Sprint 3)
- `.claude/protocols/session-continuity.md` (Sprint 4)
- `.claude/protocols/synthesis-checkpoint.md` (Sprint 4)
- `.claude/skills/reviewing-code/index.yaml` (Sprint 2)
- `.claude/skills/auditing-security/index.yaml` (Sprint 2)
- `.claude/skills/designing-architecture/index.yaml` (Sprint 2)

---

## Sign-Off

| Role | Name | Date | Status |
|------|------|------|--------|
| Sprint Planning | AI Agent | 2026-01-11 | Complete |
| Framework Maintainer | | | Pending |

---

**Next Step:** `/implement sprint-1` to begin implementation
