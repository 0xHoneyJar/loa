# Sprint Plan: ck Semantic Search Integration

**Project**: Loa Framework - Enterprise-Grade Semantic Code Search Integration
**Version**: 1.0
**Status**: Sprint Plan Complete
**Date**: 2025-12-26
**Agent**: planning-sprints
**PRD Reference**: `/home/merlin/Documents/thj/code/loa/loa-grimoire/prd.md`
**SDD Reference**: `/home/merlin/Documents/thj/code/loa/loa-grimoire/sdd.md`

---

## Executive Summary

This sprint plan breaks down the ck semantic search integration into 6 sprints spanning 5 weeks. The plan assumes a **single developer** working full-time on this integration. Each sprint includes detailed tasks, acceptance criteria, testing requirements, and risk assessments.

**Updated for GitHub Issues #9, #10, #11**:
- **FR-8 (Issue #9)**: Agent chaining with automatic next-step suggestions (Sprint 4)
- **FR-9 (Issue #10)**: Context pollution prevention with filtering and watch paths (Sprint 4)
- **FR-10 (Issue #11)**: Command namespace protection - IMMEDIATE BLOCKER (Sprint 1)

**Key Milestones**:
- **Sprint 1 (Week 1)**: Foundation - Installation, integrity checks, **command namespace protection (P0)**
- **Sprint 2 (Week 2)**: Core Search - /ride integration, Ghost/Shadow detection
- **Sprint 3 (Week 3)**: Context Management - Tool Result Clearing, trajectory logging
- **Sprint 4 (Week 3-4)**: Skill Enhancements - implementing-tasks, reviewing-code, **agent chaining, context filtering**
- **Sprint 5 (Week 5)**: Quality & Polish - Testing, documentation, edge cases
- **Sprint 6 (Week 5)**: Validation & Handoff - E2E testing, user acceptance, deployment prep

**Success Metrics**:
- Search Speed: <500ms on 1M LOC (PRD NFR-1.1)
- Cache Hit Rate: 80-90% via delta indexing (PRD NFR-1.2)
- Grounding Ratio: ≥0.95 (95%+ claims backed by code) (PRD NFR-5.2)
- User Experience Parity: 100% (identical output with/without ck)

---

## Table of Contents

1. [Sprint Overview](#sprint-overview)
2. [Team Structure](#team-structure)
3. [Sprint 1: Foundation & Setup](#sprint-1-foundation--setup)
4. [Sprint 2: Core Search Integration](#sprint-2-core-search-integration)
5. [Sprint 3: Context Management](#sprint-3-context-management)
6. [Sprint 4: Skill Enhancements](#sprint-4-skill-enhancements)
7. [Sprint 5: Quality & Polish](#sprint-5-quality--polish)
8. [Sprint 6: Validation & Handoff](#sprint-6-validation--handoff)
9. [MVP Definition](#mvp-definition)
10. [Feature Prioritization](#feature-prioritization)
11. [Risk Assessment](#risk-assessment)
12. [Dependencies & Blockers](#dependencies--blockers)
13. [Testing Strategy](#testing-strategy)
14. [Success Criteria](#success-criteria)

---

## Sprint Overview

### Sprint Duration
- **Single Sprint Length**: 3-4 days (assuming solo developer)
- **Total Duration**: 4 weeks (6 sprints)
- **Work Pattern**: Focused implementation (6-8 hours/day)

### Sprint Cadence
- **Daily**: Self-check-ins via NOTES.md updates
- **Per Sprint**: Self-review via trajectory logs
- **Mid-Project**: Checkpoint after Sprint 3 (validate core functionality)
- **End of Project**: Full validation (Sprint 6)

---

## Team Structure

### Solo Developer
**Role**: Full-stack implementation + testing + documentation

**Responsibilities**:
- Implement all components from SDD
- Write unit + integration tests
- Update documentation (INSTALLATION.md, protocols, etc.)
- Perform self-reviews via trajectory logs
- Validate against PRD acceptance criteria

**Support** (assumed available):
- PRD + SDD documentation (comprehensive design reference)
- Existing Loa codebase (patterns, conventions, infrastructure)
- ck CLI tool (external dependency)

---

## Sprint 1: Foundation & Setup

**Duration**: 3-4 days
**Goal**: Establish installation infrastructure, integrity checks, and basic plumbing

### Sprint 1 Tasks

#### Task 1.1: Update Installation Documentation
**Priority**: P0 (Blocker)
**Estimated Effort**: 2 hours
**PRD Reference**: FR-1.1

**Description**:
Update INSTALLATION.md to list ck as an optional enhancement with clear installation instructions and benefits.

**Acceptance Criteria**:
- [ ] INSTALLATION.md has new "Optional Enhancements" section
- [ ] ck listed with installation: `cargo install ck-search`
- [ ] Benefits clearly stated: "Semantic code search, 80-90% faster context loading"
- [ ] Explicitly states: "Without ck: All commands work normally using grep fallbacks"
- [ ] Installation instructions include version check: `ck --version`

**Testing**:
- Manual validation: Read INSTALLATION.md, verify clarity
- Check that instructions are copy-paste ready

**Dependencies**: None

---

#### Task 1.2: Update /setup Command
**Priority**: P0 (Blocker)
**Estimated Effort**: 4 hours
**PRD Reference**: FR-1.2

**Description**:
Enhance /setup command to detect ck installation status and display appropriate messaging.

**Acceptance Criteria**:
- [ ] /setup checks `command -v ck`
- [ ] If installed: Display "✓ ck installed: <version>"
- [ ] If missing: Display "○ ck not installed (optional)"
- [ ] Show install command if missing: `cargo install ck-search`
- [ ] NEVER blocks setup if ck missing
- [ ] Completion message varies based on installed tools:
  - Both ck + bd: "Setup complete with full enhancement suite"
  - Only ck: "Setup complete with semantic search"
  - Only bd: "Setup complete with task tracking"
  - Neither: "Setup complete. For enhanced capabilities, see INSTALLATION.md"

**Testing**:
- Test with ck installed
- Test without ck installed
- Test with both ck + bd installed
- Verify setup completes in all scenarios

**Dependencies**: None

**Implementation Details**:
Location: `.claude/commands/setup.md`

Add detection logic:
```bash
# Check ck availability
if command -v ck >/dev/null 2>&1; then
    CK_VERSION=$(ck --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "unknown")
    echo "✓ ck installed: ${CK_VERSION}"
else
    echo "○ ck not installed (optional)"
    echo "  For semantic search: cargo install ck-search"
fi
```

---

#### Task 1.3: Update .gitignore
**Priority**: P0 (Blocker)
**Estimated Effort**: 30 minutes
**PRD Reference**: FR-1.3

**Description**:
Add .ck/ directory and trajectory logs to .gitignore to prevent committing large binary files.

**Acceptance Criteria**:
- [ ] .gitignore includes `.ck/` entry
- [ ] .gitignore includes `loa-grimoire/a2a/trajectory/*.jsonl` entry
- [ ] Verify .ck/ is never committed to git

**Testing**:
- Create dummy .ck/ directory with test files
- Run `git status`, verify .ck/ not shown
- Clean up dummy directory

**Dependencies**: None

**Implementation Details**:
Add to root `.gitignore`:
```gitignore
# Loa Framework
.beads/
.ck/
loa-grimoire/a2a/trajectory/*.jsonl
```

---

#### Task 1.4: Create Pre-Flight Integrity Protocol
**Priority**: P0 (Blocker)
**Estimated Effort**: 6 hours
**PRD Reference**: FR-2.1, SDD §3.1

**Description**:
Implement pre-flight integrity verification script that checks System Zone checksums before any ck operation.

**Acceptance Criteria**:
- [ ] Protocol file created: `.claude/protocols/preflight-integrity.md`
- [ ] Script created: `.claude/scripts/preflight.sh`
- [ ] Verifies `.claude/checksums.json` against actual file hashes
- [ ] Respects `integrity_enforcement` setting in `.loa.config.yaml`:
  - `strict`: HALT execution on drift, exit 1
  - `warn`: Log warning, proceed with exit 0
  - `disabled`: No integrity checks, exit 0
- [ ] Self-healing State Zone: If `.ck/` missing → trigger silent reindex
- [ ] Version pinning: Verify ck version matches `.loa-version.json` requirement
- [ ] Binary integrity: Verify ck SHA-256 fingerprint (if available)
- [ ] Never surfaces integrity status to user unless explicitly asked

**Testing**:
- Test with clean System Zone (all checksums valid)
- Test with modified .claude/ file:
  - strict mode: Should exit 1
  - warn mode: Should exit 0 with warning
  - disabled mode: Should exit 0 silently
- Test with missing .ck/ directory (should trigger reindex)
- Test ck version check (simulate old version)

**Dependencies**: None

**Implementation Details**:
See SDD §3.1 for full bash script implementation.

---

#### Task 1.5: Create Synthesis Protection Structure
**Priority**: P0 (Blocker)
**Estimated Effort**: 2 hours
**PRD Reference**: FR-2.2

**Description**:
Create .claude/overrides/ directory structure to allow user customizations without editing System Zone.

**Acceptance Criteria**:
- [ ] Directory created: `.claude/overrides/`
- [ ] README created: `.claude/overrides/README.md` explaining usage
- [ ] Example config: `.claude/overrides/ck-config.yaml.example`
- [ ] Configuration precedence documented:
  1. `.claude/overrides/ck-config.yaml` (highest priority)
  2. `.loa.config.yaml`
  3. `.claude/mcp-registry.yaml` (framework defaults)
- [ ] Documentation clearly states what can/cannot be overridden

**Testing**:
- Verify directory structure created
- Verify README is clear and actionable

**Dependencies**: None

**Implementation Details**:
Create `.claude/overrides/README.md`:
```markdown
# Loa Framework Overrides

This directory allows you to customize Loa behavior without editing System Zone files.

## Usage

Create `.claude/overrides/ck-config.yaml` to customize ck settings:

```yaml
ck:
  model: "jina-code"  # Override default nomic-v1.5
  thresholds:
    semantic: 0.5      # Stricter than default 0.4
    hybrid: 0.6
```

## Configuration Precedence

1. `.claude/overrides/*` (highest priority - your customizations)
2. `.loa.config.yaml` (project settings)
3. `.claude/*` (framework defaults - DO NOT EDIT)

## Important

- NEVER edit `.claude/` files directly (except this directory)
- Your overrides survive framework updates (`/update`)
- Framework files are synthesized and will be overwritten
```

---

#### Task 1.6: Update .loa-version.json
**Priority**: P1 (High)
**Estimated Effort**: 1 hour
**PRD Reference**: NFR-4.2

**Description**:
Add ck dependency to .loa-version.json with version requirement.

**Acceptance Criteria**:
- [ ] .loa-version.json includes ck entry under dependencies
- [ ] Version requirement: `"ck": ">=0.7.0"`
- [ ] Optional flag set: `"optional": true`
- [ ] Binary fingerprint placeholder added (to be filled post-install)

**Testing**:
- Validate JSON syntax
- Verify version requirement format

**Dependencies**: None

**Implementation Details**:
```json
{
  "dependencies": {
    "ck": {
      "version": ">=0.7.0",
      "optional": true,
      "install": "cargo install ck-search"
    }
  },
  "binary_fingerprints": {
    "ck": ""
  }
}
```

---

#### Task 1.7: Create Reserved Commands Registry (P0 BLOCKER)
**Priority**: P0 (Blocker)
**Estimated Effort**: 1 hour
**PRD Reference**: FR-10.1, GitHub Issue #11
**SDD Reference**: §3.9

**Description**:
Create `.claude/reserved-commands.yaml` with list of Claude Code built-in commands to prevent namespace conflicts.

**Acceptance Criteria**:
- [ ] File created: `.claude/reserved-commands.yaml`
- [ ] Includes all Claude Code built-in commands: config, help, clear, compact, cost, doctor, init, login, logout, memory, model, pr-comments, review, terminal-setup, vim
- [ ] Version and metadata fields included
- [ ] Last updated timestamp

**Testing**:
- Validate YAML syntax
- Verify completeness of reserved list

**Dependencies**: None

**Implementation Details**:
See SDD §3.9 for full YAML structure.

---

#### Task 1.8: Implement Command Validation Script (P0 BLOCKER)
**Priority**: P0 (Blocker)
**Estimated Effort**: 3 hours
**PRD Reference**: FR-10.1, GitHub Issue #11
**SDD Reference**: §3.9

**Description**:
Create validation script that checks all Loa commands against reserved command list and auto-renames conflicts.

**Acceptance Criteria**:
- [ ] Script created: `.claude/scripts/validate-commands.sh`
- [ ] Loads reserved commands from `.claude/reserved-commands.yaml`
- [ ] Scans all `.claude/commands/*.md` files
- [ ] Detects conflicts with reserved names
- [ ] Auto-renames with `-loa` suffix (e.g., `config` → `config-loa`)
- [ ] Updates internal frontmatter references
- [ ] Reports renamed commands to user

**Testing**:
- Create dummy command with reserved name
- Run validation script
- Verify auto-rename occurs
- Verify frontmatter updated

**Dependencies**: Task 1.7 (reserved commands registry)

**Implementation Details**:
See SDD §3.9 for bash script implementation.

---

#### Task 1.9: Rename /config to /mcp-config (P0 BLOCKER)
**Priority**: P0 (Blocker)
**Estimated Effort**: 2 hours
**PRD Reference**: FR-10.1, GitHub Issue #11
**SDD Reference**: §3.9

**Description**:
Rename existing `/config` command to `/mcp-config` to resolve conflict with Claude Code's built-in `/config`.

**Acceptance Criteria**:
- [ ] File renamed: `.claude/commands/config.md` → `.claude/commands/mcp-config.md`
- [ ] Frontmatter updated: `command: mcp-config`
- [ ] Command description clarified: "Configure MCP integrations"
- [ ] All documentation references updated
- [ ] CHANGELOG.md entry added for breaking change

**Testing**:
- Verify `/mcp-config` command works
- Verify `/config` invokes Claude Code built-in
- Verify no orphaned references to old command

**Dependencies**: Task 1.8 (validation script can automate this)

**Implementation Details**:
```bash
# Manual rename or use validation script
mv .claude/commands/config.md .claude/commands/mcp-config.md
sed -i 's/command: config/command: mcp-config/g' .claude/commands/mcp-config.md
```

---

#### Task 1.10: Integrate Command Validation into Pre-flight
**Priority**: P0 (Blocker)
**Estimated Effort**: 1 hour
**PRD Reference**: FR-10.1
**SDD Reference**: §3.9

**Description**:
Add command namespace validation to pre-flight checks so conflicts are detected before any operations.

**Acceptance Criteria**:
- [ ] `.claude/scripts/preflight.sh` updated
- [ ] Calls `validate-commands.sh` during pre-flight
- [ ] Validation runs during `/setup` and `/update`
- [ ] User notified of any renamed commands

**Testing**:
- Run `/setup` with conflicting command
- Verify validation catches conflict
- Verify auto-rename occurs

**Dependencies**: Task 1.8 (validation script)

**Implementation Details**:
Add to preflight.sh:
```bash
# Command namespace validation
if [[ -f "${PROJECT_ROOT}/.claude/scripts/validate-commands.sh" ]]; then
    echo "Validating command namespace..." >&2
    "${PROJECT_ROOT}/.claude/scripts/validate-commands.sh"
fi
```

---

### Sprint 1 Risk Assessment

**Risks**:
1. **Risk**: ck installation may fail on some systems (Rust toolchain issues)
   - **Likelihood**: Medium
   - **Impact**: Medium (blocks semantic search, but grep fallback works)
   - **Mitigation**: Clear error messaging, document alternative installation methods

2. **Risk**: Checksum verification may have false positives (legitimate file changes)
   - **Likelihood**: Low
   - **Impact**: Medium (user frustration)
   - **Mitigation**: Three enforcement levels (strict/warn/disabled), clear instructions

**Blockers**: None

---

### Sprint 1 Success Criteria

**Must Have**:
- [ ] /setup detects ck and displays appropriate status
- [ ] .gitignore excludes .ck/ directory
- [ ] Pre-flight integrity script functional (all 3 modes)
- [ ] .claude/overrides/ structure created
- [ ] **Reserved commands registry created**
- [ ] **Command validation script functional**
- [ ] **/config renamed to /mcp-config**
- [ ] **Command validation integrated into pre-flight**

**Nice to Have**:
- [ ] Installation documentation polished with screenshots
- [ ] Setup displays estimated index time for large codebases

**Definition of Done**:
- [ ] All P0 tasks complete and tested (including command namespace protection)
- [ ] Documentation updated (INSTALLATION.md, protocols)
- [ ] Manual testing passed (with/without ck installed)
- [ ] No command conflicts with Claude Code built-ins
- [ ] Ready for Sprint 2 (core search integration)

---

## Sprint 2: Core Search Integration

**Duration**: 4-5 days
**Goal**: Implement dual-path search orchestration and /ride integration with Ghost/Shadow detection

### Sprint 2 Tasks

#### Task 2.1: Implement Search Orchestrator
**Priority**: P0 (Blocker)
**Estimated Effort**: 8 hours
**PRD Reference**: FR-3.1, SDD §3.2

**Description**:
Create search orchestration layer that routes requests to ck or grep based on availability.

**Acceptance Criteria**:
- [ ] Script created: `.claude/scripts/search-orchestrator.sh`
- [ ] Pre-flight check called before every search
- [ ] Search mode detection: `command -v ck` (cached in LOA_SEARCH_MODE env var)
- [ ] Three search types supported:
  - `semantic`: ck --semantic or grep keyword extraction
  - `hybrid`: ck --hybrid or grep with keywords
  - `regex`: ck --regex or grep -E
- [ ] Output format: JSONL for ck, converted to JSONL for grep
- [ ] Trajectory logging: Intent phase BEFORE search, execute phase AFTER search
- [ ] Absolute paths enforced: All file paths use ${PROJECT_ROOT}/...

**Testing**:
- Test with ck installed (semantic mode)
- Test without ck installed (grep fallback)
- Verify JSONL output format consistency
- Verify trajectory logs written correctly
- Test all 3 search types (semantic, hybrid, regex)

**Dependencies**: Task 1.4 (pre-flight script)

**Implementation Details**:
See SDD §3.2 for full bash script implementation.

---

#### Task 2.2: Create Search API Functions
**Priority**: P0 (Blocker)
**Estimated Effort**: 4 hours
**PRD Reference**: SDD §5.1

**Description**:
Create bash function library for easy search invocation from agent skills.

**Acceptance Criteria**:
- [ ] Script created: `.claude/scripts/search-api.sh`
- [ ] Functions exported:
  - `semantic_search <query> [path] [top_k] [threshold]`
  - `hybrid_search <query> [path] [top_k] [threshold]`
  - `regex_search <pattern> [path]`
  - `grep_to_jsonl` (helper: convert grep output to JSONL)
  - `extract_snippet <file> <line> [context]` (helper: get code snippet)
  - `estimate_tokens <text>` (helper: rough token count)
- [ ] All functions callable from agent skills
- [ ] Absolute path enforcement in all functions

**Testing**:
- Source search-api.sh in test script
- Call each function with various inputs
- Verify JSONL output format
- Test edge cases (empty results, large results)

**Dependencies**: Task 2.1 (search orchestrator)

**Implementation Details**:
See SDD §5.1 for full bash script implementation.

---

#### Task 2.3: Update /ride Command for Dual-Path Search
**Priority**: P0 (Blocker)
**Estimated Effort**: 10 hours
**PRD Reference**: FR-3.1, SDD §7.1

**Description**:
Enhance /ride command to use semantic search when ck available, graceful grep fallback otherwise.

**Acceptance Criteria**:
- [ ] `.claude/commands/ride.md` updated with search strategy detection
- [ ] Phase A (Entry Points): ck hybrid vs grep for main/def/fn patterns
- [ ] Phase B (Abstractions): ck hybrid vs grep for class/interface/trait
- [ ] Phase C (Ghost Features): ck semantic (negative grounding) vs grep + manual review
- [ ] Phase D (Shadow Systems): ck regex vs grep for exports
- [ ] Output format IDENTICAL regardless of search mode
- [ ] Agent NEVER mentions which mode was used
- [ ] Tool Result Clearing applied after heavy searches (>20 results)
- [ ] Results synthesized to NOTES.md
- [ ] Drift report generated: `loa-grimoire/drift-report.md`

**Testing**:
- Run /ride with ck installed
- Run /ride without ck installed
- Compare outputs (should be semantically equivalent)
- Verify drift-report.md generated
- Verify NOTES.md updated

**Dependencies**: Task 2.1 (search orchestrator), Task 2.2 (search API)

**Implementation Details**:
Add to `.claude/commands/ride.md`:

```markdown
## Phase A: Entry Point Discovery

Source search API:
```bash
source "${PROJECT_ROOT}/.claude/scripts/search-api.sh"
```

Search for entry points (dual-path):
```bash
if [[ "${LOA_SEARCH_MODE}" == "ck" ]]; then
    # Semantic mode
    results=$(semantic_search "main entry point bootstrap initialize startup" "${PROJECT_ROOT}/src/" 10 0.5)
else
    # Grep fallback
    results=$(grep -rn "function main\|def main\|fn main" \
        --include="*.js" --include="*.ts" --include="*.py" \
        "${PROJECT_ROOT}/src/" 2>/dev/null | head -20 | grep_to_jsonl)
fi
```

Extract and synthesize (identical for both modes):
```bash
# Parse JSONL, extract top results
echo "${results}" | jq -r '.file + ":" + (.line | tostring) + " - " + .snippet' | while read -r entry; do
    # Write to NOTES.md
    echo "- ${entry}" >> loa-grimoire/NOTES.md
done
```
```

---

#### Task 2.4: Implement Ghost Feature Detection
**Priority**: P0 (Blocker)
**Estimated Effort**: 8 hours
**PRD Reference**: FR-3.2, SDD §3.5

**Description**:
Implement Negative Grounding protocol for detecting features documented but not implemented.

**Acceptance Criteria**:
- [ ] Protocol file created: `.claude/protocols/negative-grounding.md`
- [ ] Detection logic added to /ride (Phase C)
- [ ] Requires TWO diverse semantic queries, both returning 0 results
- [ ] Query 1: Functional description (e.g., "OAuth2 SSO login flow")
- [ ] Query 2: Architectural synonym (e.g., "single sign-on identity provider")
- [ ] Both queries use threshold 0.4
- [ ] Classification table implemented:
  - 0 code + 0-2 doc mentions: CONFIRMED GHOST
  - 0 code + 3+ doc mentions: HIGH AMBIGUITY (human audit)
  - 1+ code: NOT GHOST (feature exists)
- [ ] Track in Beads (if available): `bd create "GHOST: <feature>" --type liability --priority 2`
- [ ] Log to trajectory with classification and evidence
- [ ] Write to drift-report.md

**Testing**:
- Test with confirmed ghost feature (in PRD but not in code)
- Test with existing feature (should not flag as ghost)
- Test high ambiguity case (0 code + many doc mentions)
- Verify Beads task created (if bd installed)
- Verify trajectory log entry

**Dependencies**: Task 2.1 (search orchestrator), Task 2.2 (search API)

**Implementation Details**:
See SDD §3.5 for pseudocode implementation. Adapt to bash for /ride command.

---

#### Task 2.5: Implement Shadow System Classifier
**Priority**: P0 (Blocker)
**Estimated Effort**: 8 hours
**PRD Reference**: FR-3.3, SDD §3.6

**Description**:
Implement Shadow System detection and classification by risk level.

**Acceptance Criteria**:
- [ ] Detection logic added to /ride (Phase D)
- [ ] Use regex search to find all exports: `export|module.exports|pub fn`
- [ ] Cross-reference against PRD/SDD and `loa-grimoire/legacy/INVENTORY.md`
- [ ] For each undocumented export, classify by semantic similarity:
  - **Orphaned** (<0.3 similarity): HIGH risk, no doc match
  - **Drifted** (>0.5 similarity): MEDIUM risk, docs outdated
  - **Partial** (0.3-0.5 similarity): LOW risk, incomplete docs
- [ ] Generate Dependency Trace for Orphaned systems (import graph)
- [ ] Track in Beads with classification: `bd create "SHADOW (orphaned): <module>" --type debt --priority 1`
- [ ] Write to drift-report.md with classification table

**Testing**:
- Test with undocumented module (orphaned)
- Test with partially documented module (drifted)
- Verify dependency trace generation
- Verify Beads task created (if bd installed)
- Verify drift-report.md classification correct

**Dependencies**: Task 2.1 (search orchestrator), Task 2.2 (search API)

**Implementation Details**:
See SDD §3.6 for pseudocode implementation.

---

#### Task 2.6: Create Drift Report Template
**Priority**: P0 (Blocker)
**Estimated Effort**: 2 hours
**PRD Reference**: FR-3.4

**Description**:
Create drift-report.md template with sections for Ghost Features, Shadow Systems, Verified Features, and Resolved items.

**Acceptance Criteria**:
- [ ] Template created: `loa-grimoire/drift-report.md`
- [ ] Sections: Strategic Liabilities (Ghosts), Technical Debt (Shadows), Verified Features, Resolved
- [ ] Tables with appropriate columns for each section
- [ ] Auto-resolution logic documented (re-scan on /ride or /update)
- [ ] Last Updated timestamp field

**Testing**:
- Verify template renders correctly in markdown viewers
- Verify all required columns present

**Dependencies**: None

**Implementation Details**:
```markdown
# Code Reality Drift Report

**Last Updated**: 2025-12-26
**Project**: [Project Name]
**Generated By**: /ride command (discovering-requirements agent)

---

## Strategic Liabilities (Ghost Features)

Features documented in PRD/SDD but not implemented in code.

| Feature | Doc Source | Search Evidence | Ambiguity | Beads ID | Action |
|---------|-----------|-----------------|-----------|----------|--------|
| _No ghost features detected_ | - | - | - | - | - |

---

## Technical Debt (Shadow Systems)

Undocumented code discovered in the codebase.

| Module | Location | Classification | Risk | Dependents | Beads ID | Action |
|--------|----------|----------------|------|------------|----------|--------|
| _No shadow systems detected_ | - | - | - | - | - | - |

---

## Verified Features

Features with confirmed implementation and documentation alignment.

| Feature | Documentation | Code Location | Confidence |
|---------|--------------|---------------|------------|
| _To be populated by /ride_ | - | - | - |

---

## Resolved (Auto-Updated)

Previously flagged items that have been resolved.

| Item | Type | Resolution Date | Evidence |
|------|------|-----------------|----------|
| _No resolved items yet_ | - | - | - |
```

---

### Sprint 2 Risk Assessment

**Risks**:
1. **Risk**: Ghost detection false positives (feature exists but under different name)
   - **Likelihood**: Medium
   - **Impact**: Low (High Ambiguity flag catches these for human review)
   - **Mitigation**: Two-query protocol, ambiguity detection, user review

2. **Risk**: Shadow detection overwhelms user with undocumented code
   - **Likelihood**: High (legacy codebases have lots of undocumented code)
   - **Impact**: Medium (information overload)
   - **Mitigation**: Classification by risk, prioritize Orphaned systems only

**Blockers**:
- Sprint 1 must be complete (pre-flight checks, search orchestrator dependencies)

---

### Sprint 2 Success Criteria

**Must Have**:
- [ ] /ride works identically with/without ck installed
- [ ] Ghost Features detected and classified correctly
- [ ] Shadow Systems detected and classified correctly
- [ ] Drift report generated with all sections

**Nice to Have**:
- [ ] Beads integration tested (if bd installed)
- [ ] Dependency trace visualization for Orphaned systems

**Definition of Done**:
- [ ] All P0 tasks complete and tested
- [ ] /ride command enhanced and validated
- [ ] Drift report template populated with test data
- [ ] Manual testing passed (various codebase scenarios)
- [ ] Ready for Sprint 3 (context management)

---

## Sprint 3: Context Management

**Duration**: 3-4 days
**Goal**: Implement Tool Result Clearing, trajectory logging, and attention budget management

### Sprint 3 Tasks

#### Task 3.1: Create Tool Result Clearing Protocol
**Priority**: P0 (Blocker)
**Estimated Effort**: 6 hours
**PRD Reference**: FR-4.1, SDD §3.4

**Description**:
Implement Tool Result Clearing protocol to prevent context window exhaustion.

**Acceptance Criteria**:
- [ ] Protocol file created: `.claude/protocols/tool-result-clearing.md`
- [ ] After EVERY search returning >20 results:
  1. Extract high-signal findings (max 10 files, 20 words each)
  2. Synthesize to NOTES.md with file:line references
  3. Clear raw output from working memory
  4. Keep only single-line summary
- [ ] Enforce attention budgets:
  - Single search: 2,000 tokens max
  - Accumulated results: 5,000 tokens → mandatory clearing
  - Full file loads: 3,000 tokens → single file only
  - Session total: 15,000 tokens → stop and synthesize
- [ ] Token estimation helper: `estimate_tokens()` function
- [ ] Before/after comparison documented in protocol

**Testing**:
- Simulate search with >20 results
- Verify synthesis happens automatically
- Verify raw results cleared from memory
- Test token budget enforcement

**Dependencies**: Task 2.2 (search API - estimate_tokens function)

**Implementation Details**:
See PRD FR-4.1 and SDD §3.4 for detailed protocol specification.

Protocol should include:
- Token budget thresholds
- Synthesis format (file:line references only)
- NOTES.md structure for synthesis
- Clearing workflow (when to trigger)

---

#### Task 3.2: Implement Semantic Decay Protocol
**Priority**: P1 (High)
**Estimated Effort**: 4 hours
**PRD Reference**: FR-4.2

**Description**:
Implement progressive decay of search results to free attention budget in long sessions.

**Acceptance Criteria**:
- [ ] Three decay stages implemented:
  - **Active (0-5 min)**: Full synthesis with code snippets in NOTES.md
  - **Decayed (5-30 min)**: Absolute paths only as "lightweight identifiers"
  - **Archived (30+ min)**: Single-line summary in trajectory log
- [ ] Paths can be rehydrated via JIT retrieval if needed
- [ ] Decay workflow documented in tool-result-clearing.md protocol
- [ ] Example decay shown in protocol

**Testing**:
- Test decay stages with time simulation
- Verify Active → Decayed transition (5 min)
- Verify Decayed → Archived transition (30 min)
- Test JIT rehydration (load snippet on-demand)

**Dependencies**: Task 3.1 (tool result clearing protocol)

**Implementation Details**:
```markdown
## Example Decay

ACTIVE (0-5 min):
"JWT validation: `export async function validateToken()` [/abs/path/src/auth/jwt.ts:45]"

DECAYED (5-30 min):
"/abs/path/src/auth/jwt.ts:45"  (lightweight identifier, 12 tokens)

ARCHIVED (30+ min):
"Auth module analyzed: 3 files, 2 patterns found" (trajectory only)
```

---

#### Task 3.3: Create Trajectory Evaluation Protocol
**Priority**: P0 (Blocker)
**Estimated Effort**: 6 hours
**PRD Reference**: FR-5.1, FR-5.2, SDD §4.2

**Description**:
Implement Intent-First Search protocol with trajectory logging.

**Acceptance Criteria**:
- [ ] Protocol file created: `.claude/protocols/trajectory-evaluation.md`
- [ ] BEFORE every search, log three required elements:
  1. **Intent**: What are we looking for?
  2. **Rationale**: Why do we need this for the current task?
  3. **Expected Outcome**: What do we expect to find?
- [ ] HALT if expected_outcome cannot be articulated
- [ ] Log to trajectory BEFORE executing search
- [ ] Validate results against expected_outcome after search
- [ ] If unexpected results → log discrepancy and reassess rationale
- [ ] Anti-Fishing Expedition rules table documented
- [ ] Trajectory Pivot logging for >50 results

**Testing**:
- Test trajectory log written before search
- Test HALT on missing expected_outcome
- Test pivot logging for large result sets
- Verify trajectory log format (JSONL)

**Dependencies**: Task 2.1 (search orchestrator - already logs intent)

**Implementation Details**:
See PRD FR-5.1 and SDD §4.2 for trajectory log format.

XML format for agents:
```xml
<search_execution>
  <intent>Find JWT authentication entry points</intent>
  <rationale>Task requires extending auth; need patterns first</rationale>
  <expected_outcome>Should find 1-3 token validation functions</expected_outcome>
  <query>hybrid_search("JWT token validation authentication")</query>
  <path>${PROJECT_ROOT}/src/auth/</path>
</search_execution>
```

---

#### Task 3.4: Implement Word-for-Word Citation Protocol
**Priority**: P0 (Blocker)
**Estimated Effort**: 4 hours
**PRD Reference**: FR-5.3

**Description**:
Enforce word-for-word code citations in all agent outputs.

**Acceptance Criteria**:
- [ ] Citation format template documented: `"<claim>: <code_quote> [<absolute_path>:<line>]"`
- [ ] INSUFFICIENT examples documented (reference only)
- [ ] REQUIRED examples documented (word-for-word quote)
- [ ] All agent skills updated to follow citation format
- [ ] Trajectory logging includes code quotes in "cite" phase

**Testing**:
- Verify citation format in agent outputs
- Test with various claim types
- Validate absolute paths used

**Dependencies**: None

**Implementation Details**:
Add to `.claude/protocols/citations.md`:

```markdown
# Word-for-Word Citation Protocol

## Format

Every architectural claim must include exact code snippet:

**Template**:
```markdown
"<claim>: `<exact_code_snippet>` [<absolute_path>:<line>]"
```

## Examples

❌ INSUFFICIENT (reference only):
"The system uses JWT [src/auth/jwt.ts:45]"

✅ REQUIRED (word-for-word quote):
"The system uses JWT: `export async function validateToken(token: string): Promise<TokenPayload>` [/home/user/project/src/auth/jwt.ts:45]"

## Requirements

- Every claim requires code quote (not just file:line)
- All paths must be absolute (${PROJECT_ROOT}/...)
- Log citations to trajectory in "cite" phase
```

---

#### Task 3.5: Implement Self-Audit Checkpoint
**Priority**: P0 (Blocker)
**Estimated Effort**: 6 hours
**PRD Reference**: FR-5.4

**Description**:
Create self-audit checkpoint that agents execute before task completion.

**Acceptance Criteria**:
- [ ] Protocol file created: `.claude/protocols/self-audit-checkpoint.md`
- [ ] BEFORE completing ANY task, execute self-audit checklist:
  - [ ] Grounding ratio ≥ 0.95 (95%+ claims have evidence)
  - [ ] Zero unflagged [ASSUMPTION] claims
  - [ ] All citations have word-for-word quotes
  - [ ] All paths are absolute (${PROJECT_ROOT}/...)
  - [ ] Ghost Features tracked in Beads
  - [ ] Shadow Systems documented in drift-report.md
  - [ ] Evidence chain complete for all major conclusions
- [ ] If ANY checkbox fails → REMEDIATE before completion
- [ ] Calculate grounding ratio: `grounded_decisions / total_decisions`
- [ ] Load trajectory log to verify evidence chains
- [ ] DO NOT complete task if self-audit fails
- [ ] Claim classification documented (GROUNDED, ASSUMPTION, GHOST, SHADOW)

**Testing**:
- Test self-audit with high grounding ratio (should pass)
- Test self-audit with low grounding ratio (should fail)
- Test with unflagged assumptions (should fail)
- Test with relative paths (should fail)

**Dependencies**: Task 3.3 (trajectory logging), Task 3.4 (citations)

**Implementation Details**:
See PRD FR-5.4 for claim classification format and self-audit checklist.

---

#### Task 3.6: Implement EDD Verification
**Priority**: P0 (Blocker)
**Estimated Effort**: 4 hours
**PRD Reference**: FR-5.5

**Description**:
Require three test scenarios for every architectural decision.

**Acceptance Criteria**:
- [ ] EDD (Evaluation-Driven Development) protocol documented
- [ ] Every architectural decision informed by ck must have 3 test scenarios:
  1. **Happy Path**: Typical input and expected behavior
  2. **Edge Case**: Boundary condition handling
  3. **Error Handling**: Invalid input and error behavior
- [ ] Each scenario verified against found code
- [ ] Word-for-word evidence cited for each scenario
- [ ] No [ASSUMPTION] flags remaining before completion
- [ ] Example EDD structure documented

**Testing**:
- Test EDD verification with complete scenarios (should pass)
- Test with missing scenarios (should fail)
- Verify all scenarios have code evidence

**Dependencies**: Task 3.4 (citations)

**Implementation Details**:
Add to `.claude/protocols/edd-verification.md`:

```markdown
# EDD Verification Protocol

## Requirement

Every architectural decision informed by ck must have 3 test scenarios.

## Scenarios

1. **Happy Path**: Typical input and expected behavior
2. **Edge Case**: Boundary condition handling
3. **Error Handling**: Invalid input and error behavior

## Example

### Decision: Implement auth using existing JWT module

**Evidence Chain**:
- SEARCH: hybrid_search("JWT validation") @ 10:30:00
- RESULT: src/auth/jwt.ts:45 (score: 0.89)
- CITATION: `export async function validateToken()` [/abs/path/src/auth/jwt.ts:45]

**Scenario 1: Happy Path**
- Input: Valid JWT token
- Expected: Token validated, payload returned
- Verified: ✓

**Scenario 2: Edge Case**
- Input: Expired token
- Expected: ValidationError thrown
- Verified: ✓

**Scenario 3: Error Handling**
- Input: Malformed token
- Expected: ParseError thrown
- Verified: ✓
```

---

#### Task 3.7: Create JSONL Parser with Failure Awareness
**Priority**: P0 (Blocker)
**Estimated Effort**: 4 hours
**PRD Reference**: FR-6.2, SDD §3.3

**Description**:
Implement failure-aware JSONL parser that drops malformed lines without crashing.

**Acceptance Criteria**:
- [ ] Parser logic added to search-api.sh (inline function)
- [ ] Parse JSONL line-by-line
- [ ] If single line malformed → DROP that result, CONTINUE
- [ ] Log dropped lines to trajectory with:
  - `line`: Line number
  - `error`: Parse error message
  - `data_loss_ratio`: parse_errors / total_lines
- [ ] Never crash the entire turn on malformed JSONL
- [ ] Trajectory audit trail shows all data loss events
- [ ] Warn if data loss significant (>10%)

**Testing**:
- Test with valid JSONL (all lines parse)
- Test with single malformed line (should drop, continue)
- Test with multiple malformed lines (should drop all, continue)
- Test with 100% malformed (should return empty results, not crash)
- Verify trajectory log entry for dropped lines

**Dependencies**: Task 2.2 (search API), Task 3.3 (trajectory logging)

**Implementation Details**:
See SDD §3.3 for pseudocode. Implement in bash for search-api.sh.

---

#### Task 3.8: Create Trajectory Compaction Script
**Priority**: P1 (High)
**Estimated Effort**: 3 hours
**PRD Reference**: SDD §4.2

**Description**:
Implement trajectory log compression to save disk space.

**Acceptance Criteria**:
- [ ] Script created: `.claude/scripts/compact-trajectory.sh`
- [ ] Compress trajectories older than 30 days to .jsonl.gz
- [ ] Purge archives older than 365 days
- [ ] Compression format: gzip level 6
- [ ] Script can run manually or via cron
- [ ] Retention policy documented in .loa.config.yaml

**Testing**:
- Create dummy trajectory files with old timestamps
- Run compaction script
- Verify .jsonl.gz files created
- Verify original .jsonl files removed
- Verify old archives deleted

**Dependencies**: Task 3.3 (trajectory logging)

**Implementation Details**:
See SDD §4.2 for bash script implementation.

---

### Sprint 3 Risk Assessment

**Risks**:
1. **Risk**: Trajectory logs grow very large (disk space)
   - **Likelihood**: High (every search logged)
   - **Impact**: Medium (disk space usage)
   - **Mitigation**: Compaction script (Task 3.8), retention policy

2. **Risk**: Token budget enforcement too restrictive (blocks progress)
   - **Likelihood**: Medium
   - **Impact**: Medium (user frustration)
   - **Mitigation**: Tunable thresholds in .loa.config.yaml

**Blockers**:
- Sprint 2 must be complete (search orchestrator, trajectory logging foundation)

---

### Sprint 3 Success Criteria

**Must Have**:
- [ ] Tool Result Clearing protocol documented and enforced
- [ ] Trajectory logging fully implemented (intent, execute, cite phases)
- [ ] Self-audit checkpoint functional
- [ ] JSONL parser handles malformed input gracefully

**Nice to Have**:
- [ ] Semantic Decay protocol implemented
- [ ] Trajectory compaction script automated via cron

**Definition of Done**:
- [ ] All P0 tasks complete and tested
- [ ] Protocols documented (tool-result-clearing, trajectory-evaluation, self-audit, edd)
- [ ] Token budget enforcement validated
- [ ] Ready for Sprint 4 (skill enhancements)

---

## Sprint 4: Skill Enhancements

**Duration**: 3-4 days
**Goal**: Integrate ck search into implementing-tasks and reviewing-code agent skills

### Sprint 4 Tasks

#### Task 4.1: Enhance implementing-tasks Skill (Context Loading)
**Priority**: P1 (High)
**Estimated Effort**: 6 hours
**PRD Reference**: FR-7.1, SDD §7.2

**Description**:
Update implementing-tasks skill to use ck for context loading before writing code.

**Acceptance Criteria**:
- [ ] File created: `.claude/skills/implementing-tasks/context-retrieval.md`
- [ ] Before writing ANY code, load relevant context
- [ ] Search strategy:
  1. Find related code: semantic_search("<task_description>")
  2. Find similar patterns: hybrid_search("<pattern_to_find>")
- [ ] Apply Tool Result Clearing after heavy searches
- [ ] Log context load to NOTES.md with format:
  ```markdown
  ## Context Load: <timestamp>
  **Task**: <task_id>
  **Key Files**: <file:line references>
  **Patterns Found**: <brief description>
  **Ready to implement**: Yes/No
  ```

**Testing**:
- Run /implement sprint-N with ck installed
- Verify context loading happens before implementation
- Verify NOTES.md updated with context load
- Run /implement without ck (grep fallback)

**Dependencies**: Sprint 2 (search API), Sprint 3 (Tool Result Clearing)

**Implementation Details**:
See SDD §7.2 for context loading protocol.

---

#### Task 4.2: Enhance reviewing-code Skill (Impact Analysis)
**Priority**: P1 (High)
**Estimated Effort**: 6 hours
**PRD Reference**: FR-7.2, SDD §7.2

**Description**:
Update reviewing-code skill to use ck for impact analysis before reviewing.

**Acceptance Criteria**:
- [ ] File created: `.claude/skills/reviewing-code/impact-analysis.md`
- [ ] Before reviewing, find:
  1. **Dependents**: Search for imports of changed modules
  2. **Tests**: Find test files covering changed functions
- [ ] Review checklist:
  - [ ] Found related code (search completed)
  - [ ] Test coverage verified
  - [ ] Pattern consistency checked
  - [ ] Claims cite [file:line] sources
- [ ] Write impact analysis to loa-grimoire/a2a/sprint-N/engineer-feedback.md

**Testing**:
- Run /review-sprint sprint-N with ck installed
- Verify impact analysis section in feedback
- Verify dependents found correctly
- Run /review-sprint without ck (grep fallback)

**Dependencies**: Sprint 2 (search API), Sprint 3 (Tool Result Clearing)

**Implementation Details**:
See SDD §7.2 for impact analysis protocol.

---

#### Task 4.3: Create Search Fallback Protocol
**Priority**: P0 (Blocker)
**Estimated Effort**: 4 hours
**PRD Reference**: FR-8.1, SDD §3.2

**Description**:
Document graceful degradation strategy when ck not available.

**Acceptance Criteria**:
- [ ] Protocol file created: `.claude/protocols/search-fallback.md`
- [ ] Detection runs once per session: `command -v ck >/dev/null 2>&1`
- [ ] Tool Selection Matrix documented:
  | Task | ck Available | ck Unavailable |
  |------|--------------|----------------|
  | Find entry points | semantic_search("main") | grep "main\|bootstrap" |
  | Find patterns | semantic_search("<concept>") | grep "<keywords>" |
  | Ghost detection | Search + threshold | grep + manual review |
  | Shadow detection | regex_search(exports) | grep + cross-reference |
- [ ] Quality indicators logged to trajectory (internal only)
- [ ] Communication guidelines enforced:
  - ❌ NEVER SAY: "Using ck...", "Falling back to grep..."
  - ✅ ALWAYS SAY: "Analyzing codebase...", "Searching for patterns..."

**Testing**:
- Verify protocol documented clearly
- Test tool selection matrix (all scenarios)
- Verify communication guidelines followed

**Dependencies**: Task 2.1 (search orchestrator)

**Implementation Details**:
See PRD FR-8.1 for fallback strategy details.

---

#### Task 4.4: Integrate Beads Detection
**Priority**: P1 (High)
**Estimated Effort**: 3 hours
**PRD Reference**: NFR-7.1, SDD §7.3

**Description**:
Implement Beads (bd CLI) detection and Ghost/Shadow tracking.

**Acceptance Criteria**:
- [ ] Script created: `.claude/scripts/check-beads.sh`
- [ ] Check if bd CLI available: `command -v bd`
- [ ] If available: Set LOA_BEADS_AVAILABLE=1 env var
- [ ] If missing: Set LOA_BEADS_AVAILABLE=0, silent skip
- [ ] Ghost detection creates Beads task: `bd create "GHOST: <feature>" --type liability --priority 2`
- [ ] Shadow detection creates Beads task: `bd create "SHADOW (orphaned): <module>" --type debt --priority 1`
- [ ] Silent failure if Beads errors (never blocks workflow)
- [ ] Drift report includes Beads ID (or "N/A" if not available)

**Testing**:
- Test with bd installed (Beads tasks created)
- Test without bd installed (silent skip)
- Verify drift report includes Beads IDs
- Verify workflow never blocks on Beads failures

**Dependencies**: Task 2.4 (Ghost detection), Task 2.5 (Shadow detection)

**Implementation Details**:
See SDD §7.3 for Beads integration logic.

---

#### Task 4.5: Update Architect Command
**Priority**: P2 (Nice to Have)
**Estimated Effort**: 4 hours

**Description**:
Enhance /architect command to use semantic search for pattern discovery.

**Acceptance Criteria**:
- [ ] `.claude/commands/architect.md` updated
- [ ] Use semantic search for architectural pattern discovery
- [ ] Search for: class structures, interface definitions, design patterns
- [ ] Apply Tool Result Clearing after pattern searches
- [ ] Synthesize patterns to SDD

**Testing**:
- Run /architect with ck installed
- Verify pattern discovery works
- Run /architect without ck (grep fallback)

**Dependencies**: Sprint 2 (search API), Sprint 3 (Tool Result Clearing)

---

#### Task 4.6: Update Audit-Sprint Command
**Priority**: P2 (Nice to Have)
**Estimated Effort**: 4 hours

**Description**:
Enhance /audit-sprint command to use semantic search for security analysis.

**Acceptance Criteria**:
- [ ] `.claude/commands/audit-sprint.md` updated
- [ ] Use semantic search for security pattern discovery
- [ ] Search for: auth patterns, crypto usage, validation logic
- [ ] Apply Tool Result Clearing after security searches
- [ ] Include search evidence in audit report

**Testing**:
- Run /audit-sprint sprint-N with ck installed
- Verify security analysis enhanced
- Run /audit-sprint without ck (grep fallback)

**Dependencies**: Sprint 2 (search API), Sprint 3 (Tool Result Clearing)

---

#### Task 4.7: Create Agent Chaining Workflow Definition
**Priority**: P1 (High)
**Estimated Effort**: 3 hours
**PRD Reference**: FR-8.1, GitHub Issue #9
**SDD Reference**: §3.7

**Description**:
Create declarative workflow chain definition that maps each command to its logical next step with validation conditions.

**Acceptance Criteria**:
- [ ] File created: `.claude/workflow-chain.yaml`
- [ ] Define workflow chain: plan-and-analyze → architect → sprint-plan → implement → review-sprint → audit-sprint
- [ ] Conditional routing for review/audit (approval vs feedback)
- [ ] Variable substitution for sprint IDs {sprint}, {N+1}
- [ ] Validation conditions (file_exists, file_content_match)
- [ ] Custom messages for each transition

**Testing**:
- Validate YAML syntax with yq
- Test variable substitution logic
- Verify condition types supported

**Dependencies**: None

**Implementation Details**:
See SDD §3.7 for full YAML structure.

---

#### Task 4.8: Implement Next-Step Suggestion Engine
**Priority**: P1 (High)
**Estimated Effort**: 4 hours
**PRD Reference**: FR-8.1, GitHub Issue #9
**SDD Reference**: §3.7

**Description**:
Create script that reads workflow chain definition and suggests next command based on current phase completion.

**Acceptance Criteria**:
- [ ] Script created: `.claude/scripts/suggest-next-step.sh`
- [ ] Reads `.claude/workflow-chain.yaml`
- [ ] Accepts current phase and sprint ID as arguments
- [ ] Validates completion conditions before suggesting
- [ ] Handles conditional routing (approval vs feedback)
- [ ] Substitutes variables in next step and messages
- [ ] Returns formatted suggestion with call-to-action

**Testing**:
- Test with completed phase (prd.md exists)
- Test with incomplete phase (file missing)
- Test conditional routing (review with/without approval)
- Test sprint ID substitution

**Dependencies**: Task 4.7 (workflow chain definition)

**Implementation Details**:
See SDD §3.7 for bash script implementation.

---

#### Task 4.9: Integrate Agent Chaining into Agent Skills
**Priority**: P1 (High)
**Estimated Effort**: 3 hours
**PRD Reference**: FR-8.1, GitHub Issue #9
**SDD Reference**: §3.7

**Description**:
Update agent skill completion hooks to call suggestion engine and display next-step recommendations.

**Acceptance Criteria**:
- [ ] Update agent skills to call `suggest-next-step.sh` on successful completion
- [ ] Display formatted "Next Step" section at end of output
- [ ] Show recommended command with clear call-to-action
- [ ] Skills updated: discovering-requirements, designing-architecture, planning-sprints, implementing-tasks, reviewing-code, auditing-security
- [ ] Silent failure if suggestion engine unavailable

**Testing**:
- Complete /plan-and-analyze, verify suggests /architect
- Complete /implement sprint-1, verify suggests /review-sprint sprint-1
- Complete /review-sprint with approval, verify suggests /audit-sprint
- Complete /review-sprint with feedback, verify suggests /implement (retry)

**Dependencies**: Task 4.8 (suggestion engine)

**Implementation Details**:
Add to each agent skill completion:
```bash
# Suggest next step
if [[ -f "${PROJECT_ROOT}/.claude/scripts/suggest-next-step.sh" ]]; then
    NEXT_STEP=$("${PROJECT_ROOT}/.claude/scripts/suggest-next-step.sh" "${CURRENT_PHASE}" "${SPRINT_ID}" 2>/dev/null || true)
    if [[ -n "${NEXT_STEP}" ]]; then
        echo ""
        echo "## Next Step"
        echo ""
        echo "${NEXT_STEP}"
    fi
fi
```

---

#### Task 4.10: Create Context Filtering Configuration
**Priority**: P1 (High)
**Estimated Effort**: 2 hours
**PRD Reference**: FR-9.1, FR-9.2, GitHub Issue #10
**SDD Reference**: §3.8

**Description**:
Add context filtering configuration to `.loa.config.yaml` with watch paths, exclude patterns, signal thresholds, and archive zone.

**Acceptance Criteria**:
- [ ] `.loa.config.yaml` updated with `drift_detection` section
- [ ] `watch_paths` configurable (default: .claude/, loa-grimoire/)
- [ ] `exclude_patterns` for node_modules, logs, etc.
- [ ] `context_filtering` section added
- [ ] `archive_zone` path configurable (default: loa-grimoire/archive/)
- [ ] `default_excludes` for session artifacts
- [ ] `signal_threshold` (high/medium/low)
- [ ] `draft_ttl_days` for TTL automation

**Testing**:
- Validate YAML syntax
- Verify defaults are sensible
- Test with custom watch paths

**Dependencies**: None

**Implementation Details**:
```yaml
# .loa.config.yaml
drift_detection:
  watch_paths:
    - ".claude/"
    - "loa-grimoire/"
  exclude_patterns:
    - "**/node_modules/**"
    - "**/*.log"

context_filtering:
  enable_filtering: true
  archive_zone: "loa-grimoire/archive/"
  signal_threshold: "medium"
  default_excludes:
    - "**/brainstorm-*.md"
    - "**/session-notes-*.md"
    - "**/meeting-*.md"
    - "**/draft-*.md"
  draft_ttl_days: 30
```

---

#### Task 4.11: Implement Context Filtering Script
**Priority**: P1 (High)
**Estimated Effort**: 4 hours
**PRD Reference**: FR-9.2, GitHub Issue #10
**SDD Reference**: §3.8

**Description**:
Create script that filters search results based on signal markers, archive zone, and exclude patterns.

**Acceptance Criteria**:
- [ ] Script created: `.claude/scripts/filter-search-results.sh`
- [ ] Reads `.loa.config.yaml` for filtering configuration
- [ ] Builds exclude arguments for ck (--exclude)
- [ ] Builds exclude arguments for grep (--exclude-dir, --exclude)
- [ ] Filters by signal marker (frontmatter parsing)
- [ ] Excludes archive zone automatically
- [ ] Master toggle: `enable_filtering` can disable all filtering

**Testing**:
- Test with ck installed (verify --exclude arguments)
- Test with grep fallback (verify --exclude-dir arguments)
- Test signal marker filtering (frontmatter parsing)
- Test archive zone exclusion
- Test with filtering disabled

**Dependencies**: Task 4.10 (context filtering config)

**Implementation Details**:
See SDD §3.8 for bash script implementation.

---

#### Task 4.12: Update Drift Detection for Configurable Watch Paths
**Priority**: P1 (High)
**Estimated Effort**: 2 hours
**PRD Reference**: FR-9.1, GitHub Issue #10
**SDD Reference**: §3.8

**Description**:
Enhance drift detection script to use configurable watch paths from `.loa.config.yaml`.

**Acceptance Criteria**:
- [ ] `.claude/scripts/detect-drift.sh` updated
- [ ] Reads `drift_detection.watch_paths` from config
- [ ] Falls back to defaults if not configured
- [ ] Checks git status for each watch path
- [ ] Reports drift in all configured directories
- [ ] Respects exclude patterns

**Testing**:
- Test with default watch paths
- Test with custom watch paths (.meta/, docs/architecture/)
- Verify git status checked for each path
- Verify exclude patterns respected

**Dependencies**: Task 4.10 (context filtering config)

**Implementation Details**:
See SDD §3.8 for enhanced detect-drift.sh.

---

#### Task 4.13: Integrate Context Filtering into Search Orchestrator
**Priority**: P1 (High)
**Estimated Effort**: 2 hours
**PRD Reference**: FR-9.2, GitHub Issue #10
**SDD Reference**: §3.8

**Description**:
Update search orchestrator to apply context filtering before executing searches.

**Acceptance Criteria**:
- [ ] `.claude/scripts/search-orchestrator.sh` updated
- [ ] Sources `filter-search-results.sh`
- [ ] Builds exclude arguments from configuration
- [ ] Applies excludes to ck commands
- [ ] Applies excludes to grep commands
- [ ] Post-processes results with signal marker filtering
- [ ] Respects master toggle

**Testing**:
- Run semantic search with archive zone documents (should exclude)
- Run hybrid search with low signal documents (should exclude if threshold=medium)
- Test with filtering disabled (should include all)

**Dependencies**: Task 4.11 (filtering script), Sprint 2 (search orchestrator)

**Implementation Details**:
Add to search-orchestrator.sh:
```bash
# Build exclude arguments
source "${PROJECT_ROOT}/.claude/scripts/filter-search-results.sh"

if [[ "${LOA_SEARCH_MODE}" == "ck" ]]; then
    readarray -t CK_EXCLUDES < <(build_ck_excludes)
    ck --semantic "${QUERY}" "${CK_EXCLUDES[@]}" --jsonl
else
    readarray -t GREP_EXCLUDES < <(build_grep_excludes)
    grep -rn "${QUERY}" "${GREP_EXCLUDES[@]}" "${SEARCH_PATH}"
fi
```

---

### Sprint 4 Risk Assessment

**Risks**:
1. **Risk**: Skill integration breaks existing workflows
   - **Likelihood**: Medium
   - **Impact**: High (regression)
   - **Mitigation**: Thorough testing with/without ck, backward compatibility validation

2. **Risk**: Beads integration has unexpected side effects
   - **Likelihood**: Low
   - **Impact**: Low (silent failure mitigation)
   - **Mitigation**: Fail silently, never block workflow

**Blockers**:
- Sprint 3 must be complete (Tool Result Clearing, protocols)

---

### Sprint 4 Success Criteria

**Must Have**:
- [ ] implementing-tasks skill enhanced with context loading
- [ ] reviewing-code skill enhanced with impact analysis
- [ ] Search fallback protocol documented
- [ ] Beads integration functional (if bd installed)

**Nice to Have**:
- [ ] /architect command enhanced
- [ ] /audit-sprint command enhanced

**Definition of Done**:
- [ ] All P1 tasks complete and tested
- [ ] Skills enhanced and validated
- [ ] Backward compatibility verified (grep fallback works)
- [ ] Ready for Sprint 5 (quality & polish)

---

## Sprint 5: Quality & Polish

**Duration**: 4-5 days
**Goal**: Comprehensive testing, edge case handling, documentation polish

### Sprint 5 Tasks

#### Task 5.1: Unit Testing - Core Components
**Priority**: P0 (Blocker)
**Estimated Effort**: 8 hours

**Description**:
Write unit tests for core bash scripts using bats framework.

**Acceptance Criteria**:
- [ ] Test suite created: `tests/unit/`
- [ ] Tests for preflight.sh:
  - Checksum verification (valid, invalid, missing)
  - Enforcement levels (strict, warn, disabled)
  - ck version check
  - Binary fingerprint verification
  - Self-healing State Zone
- [ ] Tests for search-orchestrator.sh:
  - Mode detection (ck vs grep)
  - Search type routing (semantic, hybrid, regex)
  - JSONL output format
  - Trajectory logging
- [ ] Tests for search-api.sh:
  - Function exports
  - grep_to_jsonl conversion
  - Token estimation
  - Snippet extraction
- [ ] Test coverage: >80%

**Testing**:
- Run bats tests: `bats tests/unit/*.bats`
- Verify all tests pass
- Generate coverage report

**Dependencies**: Sprint 1-4 (all scripts implemented)

**Implementation Details**:
Use bats framework for bash testing:
```bash
# tests/unit/preflight.bats
@test "preflight exits 0 on clean System Zone" {
  run .claude/scripts/preflight.sh
  [ "$status" -eq 0 ]
}

@test "preflight exits 1 on strict mode with drift" {
  # Setup: modify .claude/ file
  # Set enforcement=strict
  run .claude/scripts/preflight.sh
  [ "$status" -eq 1 ]
}
```

---

#### Task 5.2: Integration Testing - /ride Command
**Priority**: P0 (Blocker)
**Estimated Effort**: 6 hours

**Description**:
Test /ride command end-to-end with various codebase scenarios.

**Acceptance Criteria**:
- [ ] Test suite created: `tests/integration/`
- [ ] Test scenarios:
  - Small codebase (<10K LOC)
  - Medium codebase (10K-100K LOC)
  - Large codebase (>100K LOC)
  - With ck installed
  - Without ck installed (grep fallback)
- [ ] Verify outputs:
  - drift-report.md generated
  - NOTES.md updated
  - Trajectory logs written
  - Beads tasks created (if bd installed)
- [ ] Performance validation:
  - Small: <30s total
  - Medium: <2min total
  - Large: <5min total

**Testing**:
- Run /ride on test codebases
- Verify outputs correct
- Measure execution time
- Compare ck vs grep results (should be semantically equivalent)

**Dependencies**: Sprint 2 (ride command implemented)

---

#### Task 5.3: Edge Case Testing
**Priority**: P0 (Blocker)
**Estimated Effort**: 6 hours

**Description**:
Test edge cases and error scenarios.

**Acceptance Criteria**:
- [ ] Test edge cases:
  - Empty search results (0 matches)
  - Very large search results (>1000 matches)
  - Malformed JSONL output
  - Missing .ck/ directory
  - Corrupted .ck/ index
  - ck binary missing mid-session
  - Git repository not initialized
  - Absolute path edge cases (symlinks, spaces, special chars)
- [ ] Verify graceful error handling:
  - Never crash agent
  - Log errors to trajectory
  - Fallback to grep when appropriate
  - Clear error messages (internal only)

**Testing**:
- Manually trigger each edge case
- Verify error handling
- Verify trajectory logs show errors
- Verify agent continues execution

**Dependencies**: Sprint 1-4 (all components implemented)

---

#### Task 5.4: Performance Benchmarking
**Priority**: P1 (High)
**Estimated Effort**: 4 hours

**Description**:
Benchmark ck search performance and cache hit rates.

**Acceptance Criteria**:
- [ ] Benchmark script created: `tests/performance/benchmark.sh`
- [ ] Test on various corpus sizes:
  - 10K LOC
  - 100K LOC
  - 1M LOC
- [ ] Measure metrics:
  - Search latency (cold cache)
  - Search latency (warm cache)
  - Cache hit rate
  - Index time (full)
  - Index time (delta)
- [ ] Verify targets met:
  - Search Speed: <500ms on 1M LOC (PRD NFR-1.1)
  - Cache Hit Rate: 80-90% (PRD NFR-1.2)

**Testing**:
- Run benchmark script on large codebases
- Generate performance report
- Compare against targets

**Dependencies**: Sprint 2 (search orchestrator)

---

#### Task 5.5: Documentation Polish - Protocols
**Priority**: P1 (High)
**Estimated Effort**: 4 hours

**Description**:
Polish all protocol documentation for clarity and completeness.

**Acceptance Criteria**:
- [ ] All protocols reviewed and polished:
  - preflight-integrity.md
  - tool-result-clearing.md
  - trajectory-evaluation.md
  - negative-grounding.md
  - search-fallback.md
  - citations.md
  - self-audit-checkpoint.md
  - edd-verification.md
- [ ] Each protocol includes:
  - Purpose and rationale
  - Step-by-step workflow
  - Examples (good and bad)
  - Testing instructions
  - Integration points
- [ ] Internal consistency verified (no contradictions)

**Testing**:
- Manual review of all protocols
- Cross-reference with PRD/SDD
- Verify examples are accurate

**Dependencies**: Sprint 3 (all protocols created)

---

#### Task 5.6: Documentation Polish - INSTALLATION.md
**Priority**: P1 (High)
**Estimated Effort**: 3 hours

**Description**:
Polish INSTALLATION.md with comprehensive ck installation instructions.

**Acceptance Criteria**:
- [ ] INSTALLATION.md includes:
  - Optional Enhancements section (ck + bd)
  - Platform-specific install instructions (Linux, macOS, Windows)
  - Troubleshooting section (common issues)
  - Version verification steps
  - Binary fingerprint recording (post-install)
- [ ] Screenshots or ASCII diagrams for clarity
- [ ] Links to external resources (ck repo, Rust installation)

**Testing**:
- Manual review for clarity
- Test install instructions on clean system
- Verify all links work

**Dependencies**: Task 1.1 (initial INSTALLATION.md update)

---

#### Task 5.7: Documentation Polish - README.md
**Priority**: P2 (Nice to Have)
**Estimated Effort**: 2 hours

**Description**:
Update README.md to mention ck integration as optional enhancement.

**Acceptance Criteria**:
- [ ] README.md includes ck in prerequisites table:
  | Tool | Required | Purpose |
  |------|----------|---------|
  | ck | Optional | Semantic code search (80-90% faster context loading) |
- [ ] Benefits section updated
- [ ] Quick start includes ck installation step (optional)

**Testing**:
- Manual review for clarity
- Verify prerequisites table accurate

**Dependencies**: None

---

#### Task 5.8: Create CI/CD Validation Script
**Priority**: P1 (High)
**Estimated Effort**: 4 hours

**Description**:
Create validation script for CI/CD pipelines to verify ck integration integrity.

**Acceptance Criteria**:
- [ ] Script created: `.claude/scripts/validate-ck-integration.sh`
- [ ] Checks:
  - All required scripts exist and are executable
  - All protocols documented
  - Checksum file up-to-date
  - Trajectory logs directory structure correct
  - Search API functions exported
- [ ] Exit codes:
  - 0: All checks passed
  - 1: Critical failure (missing required files)
  - 2: Warning (non-critical issues)
- [ ] Output format: GitHub Actions compatible

**Testing**:
- Run validation script on clean checkout
- Run validation script with missing files (should fail)
- Run validation script with warnings (should exit 2)

**Dependencies**: Sprint 1-4 (all components implemented)

---

### Sprint 5 Risk Assessment

**Risks**:
1. **Risk**: Testing reveals major bugs requiring significant rework
   - **Likelihood**: Medium
   - **Impact**: High (schedule delay)
   - **Mitigation**: Incremental testing throughout Sprints 1-4, not just at end

2. **Risk**: Performance benchmarks don't meet targets
   - **Likelihood**: Low
   - **Impact**: High (ck may not be viable)
   - **Mitigation**: Early performance validation in Sprint 2

**Blockers**:
- Sprint 1-4 must be complete (all components implemented)

---

### Sprint 5 Success Criteria

**Must Have**:
- [ ] Unit tests written and passing (>80% coverage)
- [ ] Integration tests passing (all scenarios)
- [ ] Edge case testing complete
- [ ] Performance benchmarks meet targets
- [ ] All protocols polished

**Nice to Have**:
- [ ] CI/CD validation script automated in GitHub Actions
- [ ] Performance report generated

**Definition of Done**:
- [ ] All P0 + P1 tasks complete
- [ ] Test suite comprehensive and passing
- [ ] Documentation polished and accurate
- [ ] Ready for Sprint 6 (validation & handoff)

---

## Sprint 6: Validation & Handoff

**Duration**: 2-3 days
**Goal**: End-to-end validation, user acceptance testing, deployment preparation

### Sprint 6 Tasks

#### Task 6.1: E2E Testing - Full Workflow
**Priority**: P0 (Blocker)
**Estimated Effort**: 6 hours

**Description**:
Test complete workflow from installation to sprint completion.

**Acceptance Criteria**:
- [ ] Test scenarios:
  1. **Fresh Install (with ck)**:
     - Run /setup (ck installed)
     - Run /plan-and-analyze (PRD generation)
     - Run /architect (SDD generation)
     - Run /sprint-plan (sprint plan generation)
     - Run /implement sprint-1 (implementation)
     - Run /review-sprint sprint-1 (review)
     - Run /ride (code reality extraction)
  2. **Fresh Install (without ck)**:
     - Same workflow, verify grep fallback works
  3. **Existing Project (with ck)**:
     - Run /mount (mount existing codebase)
     - Run /ride (extract code reality)
     - Verify drift report generated
- [ ] Verify outputs:
  - All grimoire files generated correctly
  - Trajectory logs complete
  - Drift report accurate
  - NOTES.md updated
- [ ] Verify user experience:
  - Identical output with/without ck
  - No ck mentioned to user
  - No errors when ck missing

**Testing**:
- Run full workflow on clean checkout
- Document any issues found
- Verify all acceptance criteria met

**Dependencies**: Sprint 1-5 (all components implemented and tested)

---

#### Task 6.2: User Acceptance Testing (Self-Validation)
**Priority**: P0 (Blocker)
**Estimated Effort**: 4 hours

**Description**:
Perform self-validation against PRD success criteria.

**Acceptance Criteria**:
- [ ] Validate PRD success criteria:
  - ✅ Fresh clone WITHOUT ck: /ride completes using grep fallbacks
  - ✅ Fresh clone WITH ck: /ride completes with enhanced precision
  - ✅ Users CANNOT tell which search mode was used
  - ✅ Agent never mentions "ck", "semantic search", "grep", or "fallback"
  - ✅ Word-for-word code quotes in all citations
  - ✅ Absolute paths (never relative)
  - ✅ Ghost Features tracked in Beads
  - ✅ Three test scenarios per architectural decision (EDD)
- [ ] Validate KPIs:
  - ✅ Search Speed: <500ms on 1M LOC
  - ✅ Cache Hit Rate: 80-90%
  - ✅ Grounding Ratio: ≥0.95
  - ✅ User Experience Parity: 100%
  - ✅ Zero User-Facing Errors: 100%
  - ✅ Attention Budget Compliance: 100%
- [ ] Document validation results

**Testing**:
- Run through PRD checklist
- Measure KPIs
- Generate validation report

**Dependencies**: Task 6.1 (E2E testing)

---

#### Task 6.3: Create Release Notes
**Priority**: P1 (High)
**Estimated Effort**: 3 hours

**Description**:
Document ck integration release notes for users and contributors.

**Acceptance Criteria**:
- [ ] Release notes created: `RELEASE_NOTES_CK_INTEGRATION.md`
- [ ] Sections:
  - What's New (ck integration summary)
  - Key Features (invisible enhancement, semantic search, Ghost/Shadow detection)
  - Installation Instructions (ck + bd)
  - Migration Guide (existing users)
  - Breaking Changes (none expected)
  - Known Limitations (single repo only, v1.0)
  - Future Roadmap (MCP migration, multi-repo support)
- [ ] Examples included (before/after screenshots)

**Testing**:
- Manual review for clarity
- Verify all links work

**Dependencies**: None

---

#### Task 6.4: Create Migration Guide
**Priority**: P1 (High)
**Estimated Effort**: 2 hours

**Description**:
Document migration path for existing Loa users.

**Acceptance Criteria**:
- [ ] Migration guide created: `MIGRATION_GUIDE_CK.md`
- [ ] Steps:
  1. Backup existing grimoire
  2. Run /update to get latest framework
  3. Optionally install ck: `cargo install ck-search`
  4. Run /setup to verify installation
  5. Re-run /ride to regenerate drift report (now with semantic search)
  6. Review drift report changes
- [ ] Rollback instructions (if issues)
- [ ] FAQ section (common questions)

**Testing**:
- Manual review for clarity
- Test migration on existing Loa project

**Dependencies**: None

---

#### Task 6.5: Update CHANGELOG.md
**Priority**: P1 (High)
**Estimated Effort**: 1 hour

**Description**:
Update CHANGELOG.md with ck integration release.

**Acceptance Criteria**:
- [ ] CHANGELOG.md includes new version entry (v0.8.0)
- [ ] Sections:
  - Added: ck semantic search integration
  - Changed: /ride enhanced with Ghost/Shadow detection
  - Fixed: (none for new feature)
  - Deprecated: (none)
  - Security: Pre-flight integrity checks
- [ ] Date and version tagged correctly

**Testing**:
- Manual review for accuracy

**Dependencies**: None

---

#### Task 6.6: Create Deployment Checklist
**Priority**: P0 (Blocker)
**Estimated Effort**: 2 hours

**Description**:
Create deployment checklist for release preparation.

**Acceptance Criteria**:
- [ ] Checklist created: `DEPLOYMENT_CHECKLIST_CK.md`
- [ ] Pre-deployment:
  - [ ] All tests passing (unit, integration, E2E)
  - [ ] Documentation complete (protocols, INSTALLATION.md, README.md)
  - [ ] Checksum file updated
  - [ ] Release notes written
  - [ ] CHANGELOG.md updated
- [ ] Deployment:
  - [ ] Tag release: `v0.8.0-ck-integration`
  - [ ] Push to main branch
  - [ ] Create GitHub release
  - [ ] Announce in community channels
- [ ] Post-deployment:
  - [ ] Monitor for issues
  - [ ] Update documentation links
  - [ ] Respond to user feedback

**Testing**:
- Manual review of checklist

**Dependencies**: Task 6.3 (release notes), Task 6.5 (CHANGELOG)

---

#### Task 6.7: Generate Checksums
**Priority**: P0 (Blocker)
**Estimated Effort**: 1 hour

**Description**:
Generate final checksums for System Zone files before deployment.

**Acceptance Criteria**:
- [ ] Run checksum generation script: `.claude/scripts/generate-checksums.sh`
- [ ] Verify .claude/checksums.json updated with all System Zone files
- [ ] No files excluded that should be included
- [ ] Commit checksums to git

**Testing**:
- Run preflight.sh after checksum generation (should pass)
- Modify a System Zone file, run preflight.sh (should fail in strict mode)

**Dependencies**: Sprint 1-5 (all System Zone files finalized)

**Implementation Details**:
See SDD §6.1 for checksum generation script.

---

#### Task 6.8: Final Validation - Self-Audit Checkpoint
**Priority**: P0 (Blocker)
**Estimated Effort**: 2 hours

**Description**:
Execute self-audit checkpoint on entire integration project.

**Acceptance Criteria**:
- [ ] Self-audit checklist:
  - [ ] Grounding ratio ≥ 0.95 (95%+ claims have evidence from PRD/SDD)
  - [ ] Zero unflagged [ASSUMPTION] claims
  - [ ] All citations have word-for-word quotes (from PRD/SDD)
  - [ ] All paths are absolute (in sprint plan and documentation)
  - [ ] Ghost Features tracked (in sprint plan)
  - [ ] Shadow Systems documented (in sprint plan)
  - [ ] Evidence chain complete for all major decisions
- [ ] Load trajectory from Sprints 1-6 (this planning session)
- [ ] Verify grounding ratio calculation
- [ ] Document self-audit results

**Testing**:
- Manual self-audit execution
- Verify all checkboxes pass

**Dependencies**: Sprint 3 (self-audit protocol), Task 6.1 (E2E testing)

---

### Sprint 6 Risk Assessment

**Risks**:
1. **Risk**: E2E testing reveals integration issues
   - **Likelihood**: Low (comprehensive testing in Sprint 5)
   - **Impact**: Medium (deployment delay)
   - **Mitigation**: Incremental testing throughout project

2. **Risk**: User acceptance reveals unexpected edge cases
   - **Likelihood**: Low
   - **Impact**: Low (can be addressed post-release)
   - **Mitigation**: Comprehensive edge case testing in Sprint 5

**Blockers**:
- Sprint 5 must be complete (all testing done, documentation polished)

---

### Sprint 6 Success Criteria

**Must Have**:
- [ ] E2E testing complete and passing
- [ ] PRD success criteria validated
- [ ] Deployment checklist complete
- [ ] Checksums generated
- [ ] Self-audit checkpoint passed

**Nice to Have**:
- [ ] Release notes polished with examples
- [ ] Migration guide tested on real project

**Definition of Done**:
- [ ] All P0 tasks complete
- [ ] Validation report generated
- [ ] Release ready for deployment
- [ ] Handoff complete (ready for merge to main)

---

## MVP Definition

### What's In Scope (v1.0)

**Foundation**:
- ✅ Installation surfacing (INSTALLATION.md, /setup, README.md)
- ✅ Pre-flight integrity checks (strict/warn/disabled modes)
- ✅ Synthesis Protection via .claude/overrides/

**Core Search**:
- ✅ Seamless /ride integration with dual-path (ck + grep)
- ✅ Search orchestration layer (semantic, hybrid, regex)
- ✅ JSONL output with failure-aware parsing
- ✅ Graceful fallback to grep

**Detection & Classification**:
- ✅ Ghost Feature detection (Negative Grounding protocol)
- ✅ Shadow System detection (Classification: Orphaned/Drifted/Partial)
- ✅ Drift report generation with auto-resolution

**Context Management**:
- ✅ Tool Result Clearing protocol (attention budget management)
- ✅ Semantic Decay protocol (Active→Decayed→Archived)
- ✅ Token budget enforcement (2K/5K/15K limits)

**Trajectory & Audit**:
- ✅ Trajectory logging (intent→execute→cite phases)
- ✅ Word-for-word citations with absolute paths
- ✅ Self-audit checkpoint (completion gate)
- ✅ EDD Verification (3 test scenarios per decision)

**Skill Integration**:
- ✅ implementing-tasks skill enhanced (context loading)
- ✅ reviewing-code skill enhanced (impact analysis)

**Optional Enhancements**:
- ✅ Beads integration (Ghost/Shadow tracking)
- ✅ Trajectory archival (gzip compression)

### What's Out of Scope (Future Versions)

**v1.0 Exclusions**:
- ❌ Custom MCP servers beyond ck
- ❌ Multi-model embedding strategies
- ❌ Real-time index updates (git hooks)
- ❌ Distributed search across multiple machines
- ❌ GUI for trajectory visualization
- ❌ Integration with other search tools (Sourcegraph, etc.)

**v2.0 Roadmap** (Post-MVP):
- ⏭️ MCP server migration (connection pooling, health checks)
- ⏭️ Multi-repository support (federated search)
- ⏭️ Advanced trajectory analytics (pattern detection)
- ⏭️ Automated Beads integration (beyond Ghost/Shadow)

---

## Feature Prioritization

### Priority Matrix

| Feature | Impact | Effort | Priority | Sprint |
|---------|--------|--------|----------|--------|
| **Command namespace protection** | **High** | **Low** | **P0** | **1** |
| Pre-flight integrity checks | High | Medium | P0 | 1 |
| Search orchestration layer | High | High | P0 | 2 |
| /ride dual-path integration | High | High | P0 | 2 |
| Ghost Feature detection | High | Medium | P0 | 2 |
| Shadow System detection | High | Medium | P0 | 2 |
| Tool Result Clearing | High | Medium | P0 | 3 |
| Trajectory logging | High | Medium | P0 | 3 |
| Self-audit checkpoint | High | Low | P0 | 3 |
| Word-for-word citations | High | Low | P0 | 3 |
| JSONL failure-aware parsing | High | Low | P0 | 3 |
| implementing-tasks enhancement | Medium | Medium | P1 | 4 |
| reviewing-code enhancement | Medium | Medium | P1 | 4 |
| Search fallback protocol | High | Low | P0 | 4 |
| Beads integration | Low | Low | P1 | 4 |
| **Agent chaining (next step)** | **High** | **Medium** | **P1** | **4** |
| **Context pollution prevention** | **High** | **Medium** | **P1** | **4** |
| **Configurable watch paths** | **Medium** | **Low** | **P1** | **4** |
| **Signal markers filtering** | **Medium** | **Medium** | **P1** | **4** |
| Unit testing | High | Medium | P0 | 5 |
| Integration testing | High | Medium | P0 | 5 |
| Performance benchmarking | Medium | Low | P1 | 5 |
| Documentation polish | Medium | Medium | P1 | 5 |
| E2E testing | High | Medium | P0 | 6 |
| Release preparation | Medium | Low | P1 | 6 |

### P0 Tasks (Blockers)
Must be completed for v1.0 release:
- All integrity and security features
- Core search functionality with dual-path
- Ghost/Shadow detection
- Context management (Tool Result Clearing, trajectory logging)
- Self-audit checkpoint
- Testing (unit, integration, E2E)

### P1 Tasks (High Priority)
Should be completed for v1.0 release:
- Skill enhancements (implementing-tasks, reviewing-code)
- Beads integration
- Performance benchmarking
- Documentation polish
- Release preparation

### P2 Tasks (Nice to Have)
Can be deferred to v1.1:
- /architect command enhancement
- /audit-sprint command enhancement
- Advanced trajectory analytics
- GUI visualization

---

## Risk Assessment

### Technical Risks

#### Risk 1: ck Binary Availability
- **Description**: ck requires Rust toolchain (cargo install)
- **Likelihood**: Medium
- **Impact**: High (blocks semantic search)
- **Mitigation**:
  - Graceful degradation to grep (PRD FR-8.1)
  - Clear installation documentation (Task 1.1)
  - Alternative installation methods documented (binaries, Docker)
- **Owner**: Sprint 1 (installation infrastructure)
- **Status**: Mitigated via grep fallback

#### Risk 2: Context Window Exhaustion
- **Description**: Large search results overwhelm agent attention budget
- **Likelihood**: High
- **Impact**: High (model hallucinations, poor reasoning)
- **Mitigation**:
  - Tool Result Clearing protocol (Task 3.1)
  - Semantic Decay protocol (Task 3.2)
  - Token budget enforcement (2K/5K/15K limits)
- **Owner**: Sprint 3 (context management)
- **Status**: Mitigated via protocols

#### Risk 3: JSONL Parse Failures
- **Description**: Malformed JSONL crashes entire search operation
- **Likelihood**: Medium
- **Impact**: High (agent failures mid-task)
- **Mitigation**:
  - Failure-Aware Parsing (Task 3.7)
  - Drop bad lines, continue processing
  - Log to trajectory for audit
- **Owner**: Sprint 3 (JSONL parser)
- **Status**: Mitigated via failure-aware parsing

#### Risk 4: Integrity Check False Positives
- **Description**: Legitimate file changes flagged as tampering
- **Likelihood**: Low
- **Impact**: Medium (user frustration)
- **Mitigation**:
  - Three enforcement levels (strict/warn/disabled)
  - Clear error messages
  - /update command to restore integrity
- **Owner**: Sprint 1 (pre-flight checks)
- **Status**: Mitigated via enforcement levels

#### Risk 5: Search Precision Degradation
- **Description**: grep fallback has higher false-positive rate than ck
- **Likelihood**: High (when ck not installed)
- **Impact**: Medium (lower quality results)
- **Mitigation**:
  - Document benefits of ck (INSTALLATION.md)
  - Make installation easy (cargo install)
  - Accept trade-off (grep still functional)
- **Owner**: Sprint 1 (documentation)
- **Status**: Accepted (trade-off documented)

### Business Risks

#### Risk 6: Increased Complexity
- **Description**: Adding ck integration increases framework complexity
- **Likelihood**: High
- **Impact**: Medium (harder maintenance, steeper learning curve)
- **Mitigation**:
  - Comprehensive documentation (protocols, guides)
  - Clear separation of concerns (three-zone model)
  - Synthesis protection (override mechanism)
- **Owner**: Sprint 5 (documentation polish)
- **Status**: Mitigated via documentation

#### Risk 7: User Confusion
- **Description**: Users don't understand when to install ck
- **Likelihood**: Medium
- **Impact**: Low (sub-optimal experience)
- **Mitigation**:
  - Clear INSTALLATION.md (Task 1.1)
  - /setup status display (Task 1.2)
  - README prerequisites table (Task 5.7)
- **Owner**: Sprint 1 (installation docs)
- **Status**: Mitigated via clear documentation

---

## Dependencies & Blockers

### External Dependencies

#### D-1: ck Binary (External)
- **Dependency**: ck-search Rust crate
- **Version**: ≥0.7.0
- **Owner**: BeaconBay (https://github.com/BeaconBay/ck)
- **Risk**: Upstream breaking changes
- **Mitigation**: Version pinning in .loa-version.json (Task 1.6)
- **Status**: Tracked

#### D-2: Beads (Optional External)
- **Dependency**: bd CLI for task tracking
- **Version**: Any recent
- **Owner**: steveyegge/beads
- **Risk**: Not available on user's system
- **Mitigation**: Optional, graceful degradation (no Beads → no structured tracking)
- **Status**: Optional, low risk

#### D-3: jq (System Tool)
- **Dependency**: Command-line JSON processor
- **Use Case**: Checksum verification, JSONL parsing in scripts
- **Risk**: Missing on minimal Linux distros
- **Mitigation**: Fallback to pure bash if jq missing
- **Status**: Required, documented in INSTALLATION.md

#### D-4: yq (System Tool)
- **Dependency**: YAML processor for reading mcp-registry.yaml
- **Use Case**: Loading MCP server configurations
- **Risk**: Not installed by default
- **Mitigation**: Document in INSTALLATION.md: `brew install yq` / `apt install yq`
- **Status**: Required, documented in INSTALLATION.md

### Internal Dependencies (Sprint Blockers)

**Sprint 1** → **Sprint 2**:
- Sprint 2 requires pre-flight checks (Task 1.4)
- Sprint 2 requires .gitignore updated (Task 1.3)

**Sprint 2** → **Sprint 3**:
- Sprint 3 requires search orchestrator (Task 2.1)
- Sprint 3 requires search API (Task 2.2)

**Sprint 3** → **Sprint 4**:
- Sprint 4 requires Tool Result Clearing protocol (Task 3.1)
- Sprint 4 requires trajectory logging (Task 3.3)

**Sprint 4** → **Sprint 5**:
- Sprint 5 requires all components implemented (Sprints 1-4)

**Sprint 5** → **Sprint 6**:
- Sprint 6 requires testing complete (Sprint 5)
- Sprint 6 requires documentation polished (Sprint 5)

---

## Testing Strategy

### Unit Testing
**Framework**: bats (Bash Automated Testing System)
**Coverage Target**: >80%
**Scope**: Core bash scripts (preflight, search-orchestrator, search-api)

**Test Categories**:
1. **Pre-flight Checks**:
   - Checksum verification (valid, invalid, missing)
   - Enforcement levels (strict, warn, disabled)
   - ck version check
   - Binary fingerprint verification
   - Self-healing State Zone

2. **Search Orchestration**:
   - Mode detection (ck vs grep)
   - Search type routing (semantic, hybrid, regex)
   - JSONL output format
   - Trajectory logging

3. **Search API**:
   - Function exports
   - grep_to_jsonl conversion
   - Token estimation
   - Snippet extraction

**Execution**: `bats tests/unit/*.bats`

---

### Integration Testing
**Framework**: Manual testing with test codebases
**Scope**: End-to-end command workflows

**Test Scenarios**:
1. **/ride Command**:
   - Small codebase (<10K LOC)
   - Medium codebase (10K-100K LOC)
   - Large codebase (>100K LOC)
   - With ck installed
   - Without ck installed (grep fallback)

2. **/implement + /review-sprint**:
   - Full sprint cycle (implement → review → iterate)
   - Context loading validation
   - Impact analysis validation

3. **Ghost/Shadow Detection**:
   - Confirmed ghost feature (in PRD, not in code)
   - Existing feature (should not flag)
   - High ambiguity case (0 code + many docs)
   - Orphaned shadow system (undocumented code)

**Execution**: Manual test runs with validation checklists

---

### E2E Testing
**Framework**: Full workflow simulation
**Scope**: Complete user journey from installation to sprint completion

**Test Scenarios**:
1. **Fresh Install (with ck)**:
   - /setup → /plan-and-analyze → /architect → /sprint-plan → /implement → /review → /ride

2. **Fresh Install (without ck)**:
   - Same workflow, verify grep fallback works

3. **Existing Project (with ck)**:
   - /mount → /ride → verify drift report

**Validation**:
- All grimoire files generated correctly
- Trajectory logs complete
- Drift report accurate
- NOTES.md updated
- User experience identical (with/without ck)

**Execution**: Sprint 6, Task 6.1

---

### Performance Testing
**Framework**: Custom benchmark script
**Scope**: Search latency, cache hit rates, index times

**Metrics**:
- Search latency (cold cache)
- Search latency (warm cache)
- Cache hit rate
- Index time (full)
- Index time (delta)

**Targets** (from PRD):
- Search Speed: <500ms on 1M LOC (PRD NFR-1.1)
- Cache Hit Rate: 80-90% (PRD NFR-1.2)

**Execution**: Sprint 5, Task 5.4

---

### Edge Case Testing
**Framework**: Manual simulation
**Scope**: Error scenarios and boundary conditions

**Test Cases**:
- Empty search results (0 matches)
- Very large search results (>1000 matches)
- Malformed JSONL output
- Missing .ck/ directory
- Corrupted .ck/ index
- ck binary missing mid-session
- Git repository not initialized
- Absolute path edge cases (symlinks, spaces, special chars)

**Validation**:
- Never crash agent
- Log errors to trajectory
- Fallback to grep when appropriate
- Clear error messages (internal only)

**Execution**: Sprint 5, Task 5.3

---

## Success Criteria

### PRD Success Criteria (Validation Checklist)

**Invisible Operation**:
- [ ] Fresh clone WITHOUT ck: /ride completes using grep fallbacks
- [ ] Fresh clone WITH ck: /ride completes with enhanced precision
- [ ] Users CANNOT tell which search mode was used
- [ ] Agent never mentions "ck", "semantic search", "grep", or "fallback"

**Grounding & Evidence**:
- [ ] Word-for-word code quotes in all citations
- [ ] Absolute paths (never relative)
- [ ] Ghost Features tracked in Beads (if available)
- [ ] Three test scenarios per architectural decision (EDD)

**Performance Targets**:
- [ ] Search Speed: <500ms on 1M LOC (PRD NFR-1.1)
- [ ] Cache Hit Rate: 80-90% (PRD NFR-1.2)
- [ ] Grounding Ratio: ≥0.95 (95%+ claims backed by code) (PRD NFR-5.2)
- [ ] User Experience Parity: 100% (identical output with/without ck)
- [ ] Zero User-Facing Errors: 100% (no errors when ck missing)
- [ ] Attention Budget Compliance: 100% (Tool Result Clearing after >20 results)

---

### Sprint Completion Criteria

**Sprint 1 (Foundation)**:
- [ ] /setup detects ck and displays status
- [ ] Pre-flight integrity checks functional (all 3 modes)
- [ ] .claude/overrides/ structure created
- [ ] Documentation updated (INSTALLATION.md)

**Sprint 2 (Core Search)**:
- [ ] /ride works identically with/without ck
- [ ] Ghost Features detected and classified
- [ ] Shadow Systems detected and classified
- [ ] Drift report generated

**Sprint 3 (Context Management)**:
- [ ] Tool Result Clearing protocol enforced
- [ ] Trajectory logging complete (intent, execute, cite)
- [ ] Self-audit checkpoint functional
- [ ] JSONL parser handles malformed input

**Sprint 4 (Skill Enhancements)**:
- [ ] implementing-tasks skill enhanced
- [ ] reviewing-code skill enhanced
- [ ] Search fallback protocol documented
- [ ] Beads integration functional

**Sprint 5 (Quality & Polish)**:
- [ ] Unit tests passing (>80% coverage)
- [ ] Integration tests passing
- [ ] Performance benchmarks meet targets
- [ ] Documentation polished

**Sprint 6 (Validation & Handoff)**:
- [ ] E2E testing complete
- [ ] PRD success criteria validated
- [ ] Release ready for deployment
- [ ] Self-audit checkpoint passed

---

### Definition of Done (Overall Project)

**Code Quality**:
- [ ] All P0 tasks complete and tested
- [ ] All P1 tasks complete and tested
- [ ] Unit tests passing (>80% coverage)
- [ ] Integration tests passing
- [ ] E2E tests passing
- [ ] Edge case testing complete
- [ ] Performance benchmarks meet targets

**Documentation**:
- [ ] All protocols documented (.claude/protocols/)
- [ ] INSTALLATION.md updated
- [ ] README.md updated
- [ ] Release notes written
- [ ] Migration guide written
- [ ] CHANGELOG.md updated

**Validation**:
- [ ] PRD success criteria validated
- [ ] KPIs measured and met
- [ ] Self-audit checkpoint passed
- [ ] User acceptance validation complete

**Deployment**:
- [ ] Checksums generated
- [ ] Deployment checklist complete
- [ ] CI/CD validation passing
- [ ] Ready for merge to main

---

## Sprint Notes

### Assumptions
1. **Solo Developer**: All tasks assume single developer (no team coordination overhead)
2. **Full-Time**: 6-8 hours/day focused implementation
3. **ck Available**: Developer has ck installed for testing (can simulate without for fallback tests)
4. **Existing Loa Knowledge**: Developer familiar with Loa codebase, patterns, conventions
5. **Rust Toolchain**: Developer has Rust installed for ck compilation

### Adjustments for Team (If Applicable)
If multiple developers available:
- **Parallel Sprints**: Run Sprints 1+2 in parallel (foundation + core search)
- **Parallel Tasks**: Within sprints, split P0 tasks across developers
- **Skill Specialization**: Assign bash scripting vs protocol documentation to different developers
- **Duration**: Could reduce total time from 4 weeks to 2-3 weeks with 2-3 developers

### Velocity Tracking
Self-track velocity via NOTES.md:
- Log hours spent per task
- Track actual vs estimated effort
- Adjust future estimates based on velocity

### Daily Workflow (Recommended)
1. **Start of Day**: Review NOTES.md, load session continuity
2. **During Work**: Log decisions, update trajectory
3. **End of Day**: Synthesize to NOTES.md, update todo list
4. **End of Sprint**: Self-review via trajectory logs, validate sprint completion criteria

---

## Appendix: Task Summary

### Sprint 1 (10 tasks, 23.5 hours)
1. Update Installation Documentation (2h)
2. Update /setup Command (4h)
3. Update .gitignore (0.5h)
4. Create Pre-Flight Integrity Protocol (6h)
5. Create Synthesis Protection Structure (2h)
6. Update .loa-version.json (1h)
7. Create Reserved Commands Registry (1h) - P0 BLOCKER
8. Implement Command Validation Script (3h) - P0 BLOCKER
9. Rename /config to /mcp-config (2h) - P0 BLOCKER
10. Integrate Command Validation into Pre-flight (1h) - P0 BLOCKER

### Sprint 2 (6 tasks, 40 hours)
1. Implement Search Orchestrator (8h)
2. Create Search API Functions (4h)
3. Update /ride Command (10h)
4. Implement Ghost Feature Detection (8h)
5. Implement Shadow System Classifier (8h)
6. Create Drift Report Template (2h)

### Sprint 3 (8 tasks, 37 hours)
1. Create Tool Result Clearing Protocol (6h)
2. Implement Semantic Decay Protocol (4h)
3. Create Trajectory Evaluation Protocol (6h)
4. Implement Word-for-Word Citation Protocol (4h)
5. Implement Self-Audit Checkpoint (6h)
6. Implement EDD Verification (4h)
7. Create JSONL Parser with Failure Awareness (4h)
8. Create Trajectory Compaction Script (3h)

### Sprint 4 (13 tasks, 49 hours)
1. Enhance implementing-tasks Skill (6h)
2. Enhance reviewing-code Skill (6h)
3. Create Search Fallback Protocol (4h)
4. Integrate Beads Detection (3h)
5. Update Architect Command (4h) - P2
6. Update Audit-Sprint Command (4h) - P2
7. Create Agent Chaining Workflow Definition (3h) - FR-8
8. Implement Next-Step Suggestion Engine (4h) - FR-8
9. Integrate Agent Chaining into Agent Skills (3h) - FR-8
10. Create Context Filtering Configuration (2h) - FR-9
11. Implement Context Filtering Script (4h) - FR-9
12. Update Drift Detection for Configurable Watch Paths (2h) - FR-9
13. Integrate Context Filtering into Search Orchestrator (2h) - FR-9

### Sprint 5 (8 tasks, 31 hours)
1. Unit Testing - Core Components (8h)
2. Integration Testing - /ride Command (6h)
3. Edge Case Testing (6h)
4. Performance Benchmarking (4h)
5. Documentation Polish - Protocols (4h)
6. Documentation Polish - INSTALLATION.md (3h)
7. Documentation Polish - README.md (2h) - P2
8. Create CI/CD Validation Script (4h)

### Sprint 6 (8 tasks, 21 hours)
1. E2E Testing - Full Workflow (6h)
2. User Acceptance Testing (4h)
3. Create Release Notes (3h)
4. Create Migration Guide (2h)
5. Update CHANGELOG.md (1h)
6. Create Deployment Checklist (2h)
7. Generate Checksums (1h)
8. Final Validation - Self-Audit (2h)

**Total Estimated Effort**: 201.5 hours (~5 weeks at 40h/week)

**Breakdown by New Features**:
- Command Namespace Protection (FR-10): +8 hours (Sprint 1)
- Agent Chaining (FR-8): +10 hours (Sprint 4)
- Context Filtering (FR-9): +12 hours (Sprint 4)

---

*Sprint Plan Generated by: planning-sprints agent*
*Date: 2025-12-26*
*PRD Reference: `/home/merlin/Documents/thj/code/loa/loa-grimoire/prd.md`*
*SDD Reference: `/home/merlin/Documents/thj/code/loa/loa-grimoire/sdd.md`*
