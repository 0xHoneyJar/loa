# Sprint Plan: Lossless Ledger Protocol v0.9.0

**Project**: Loa Framework v0.9.0
**Feature**: Clear, Don't Compact - Context State Management
**Author**: planning-sprints agent
**Date**: 2025-12-27
**Status**: Ready for Implementation

---

## Overview

This sprint plan implements the Lossless Ledger Protocol as defined in:
- **PRD**: 11 Functional Requirements (FR-1 through FR-11)
- **SDD**: 5-layer architecture with 5 new protocols and 3 new scripts

### Team Structure
- **Solo developer** workflow optimized

### Sprint Structure
- **4 sprints** as per user confirmation
- Focus: Foundation → Enforcement → Integration → Polish

### Deliverables Summary

| Category | Count | Items |
|----------|-------|-------|
| Protocols | 5 | session-continuity, synthesis-checkpoint, jit-retrieval, attention-budget, grounding-enforcement |
| Scripts | 3 | synthesis-checkpoint.sh, grounding-check.sh, self-heal-state.sh |
| Updates | 4 | structured-memory.md, ride.md, .loa.config.yaml, CLAUDE.md |
| Schema Extensions | 3 | NOTES.md, Bead schema, Trajectory phases |

---

## Sprint 1: Foundation & Core Protocols

**Focus**: Establish protocol foundation and core data structures
**Priority**: P0 features (Session Continuity, Tiered Recovery)

### Task 1.1: Session Continuity Protocol

**Description**: Create the core session continuity protocol document.

**File**: `.claude/protocols/session-continuity.md`

**Acceptance Criteria**:
- [ ] Session lifecycle documented (start, during, before /clear)
- [ ] Tiered ledger recovery levels defined (L1: ~100 tokens, L2: ~500 tokens, L3: full)
- [ ] Truth hierarchy documented (CODE > BEADS > NOTES > TRAJECTORY > PRD/SDD > LEGACY > CONTEXT)
- [ ] Recovery flow with `bd ready` -> `bd show` documented
- [ ] Anti-patterns section included

**Test Scenarios**:
1. Agent reads protocol and correctly performs Level 1 recovery
2. Agent escalates to Level 2 when historical context needed
3. Agent never treats context window as authoritative

**References**:
- PRD FR-2: Session Continuity Protocol
- PRD FR-3: Tiered Ledger Recovery
- SDD §4.1: Session Continuity Protocol

---

### Task 1.2: NOTES.md Session Continuity Section

**Description**: Extend NOTES.md template with Session Continuity section structure.

**File**: `.claude/protocols/structured-memory.md` (update)

**Acceptance Criteria**:
- [ ] Session Continuity section template added
- [ ] Active Context format (Current Bead, Last Checkpoint, Reasoning State)
- [ ] Lightweight Identifiers table format (Identifier, Purpose, Last Verified)
- [ ] Decision Log format (timestamp, decision, rationale, evidence, test scenarios)
- [ ] All paths use `${PROJECT_ROOT}` prefix requirement documented

**Test Scenarios**:
1. New project creates NOTES.md with Session Continuity section
2. Identifiers table uses absolute paths
3. Decision Log entries include word-for-word evidence

**References**:
- PRD FR-10: NOTES.md Session Continuity Section
- SDD §5.1: NOTES.md Schema Extension

---

### Task 1.3: JIT Retrieval Protocol

**Description**: Create the JIT retrieval protocol for lightweight identifiers.

**File**: `.claude/protocols/jit-retrieval.md`

**Acceptance Criteria**:
- [ ] Lightweight identifier format documented (`${PROJECT_ROOT}/path:line`)
- [ ] Token comparison documented (eager ~500 vs JIT ~15 = 97% reduction)
- [ ] ck retrieval methods documented (`ck --hybrid`, `ck --full-section`)
- [ ] Fallback methods documented (`sed -n`, `grep -n`)
- [ ] Path requirements enforced (absolute paths only)

**Test Scenarios**:
1. Agent uses lightweight identifiers instead of full code blocks
2. Agent retrieves full content only when needed
3. Graceful fallback when ck unavailable

**References**:
- PRD FR-5: JIT Retrieval Protocol
- SDD §4.4: JIT Retrieval Layer

---

### Task 1.4: Attention Budget Protocol

**Description**: Create the attention budget monitoring protocol.

**File**: `.claude/protocols/attention-budget.md`

**Acceptance Criteria**:
- [ ] Threshold levels documented (Green: 0-5k, Yellow: 5-10k, Orange: 10-15k, Red: 15k+)
- [ ] Delta-Synthesis protocol at Yellow threshold documented
- [ ] Advisory nature emphasized (not blocking)
- [ ] Trajectory log format for delta_sync phase documented
- [ ] Recommendations for each threshold level

**Test Scenarios**:
1. Delta-synthesis triggers at Yellow threshold
2. User notification at Orange threshold
3. Thresholds are advisory, not blocking

**References**:
- PRD FR-4: Attention Budget Governance
- SDD §4.3: Attention Budget Monitor

---

### Task 1.5: Trajectory Schema Extensions

**Description**: Document new trajectory phases for session handoff and delta sync.

**File**: `.claude/protocols/trajectory-evaluation.md` (update)

**Acceptance Criteria**:
- [ ] session_handoff phase documented with all required fields
- [ ] delta_sync phase documented with all required fields
- [ ] grounding_check phase documented
- [ ] root_span_id for lineage tracking documented
- [ ] notes_refs format for specific line references documented

**Test Scenarios**:
1. Session handoff log contains all required fields
2. Delta sync log tracks tokens and decisions persisted
3. Grounding check log includes ratio and threshold

**References**:
- PRD FR-8: Trajectory Handoff Protocol
- SDD §5.3: Trajectory Schema Extensions

---

### Task 1.6: Bead Schema Extensions Documentation

**Description**: Document the extended Bead schema for decisions[], handoffs[], test_scenarios[].

**File**: `.claude/protocols/session-continuity.md` (section)

**Acceptance Criteria**:
- [ ] decisions[] array format documented
- [ ] handoffs[] array format documented
- [ ] test_scenarios[] array format documented
- [ ] Backwards compatibility notes included
- [ ] Fork detection concept documented

**Test Scenarios**:
1. Existing Beads continue to work (no breaking changes)
2. New Beads can include decision history
3. Session handoffs create lineage chain

**References**:
- PRD FR-11: Bead Schema Extensions
- SDD §5.2: Bead Schema Extensions

---

## Sprint 2: Enforcement Layer

**Focus**: Implement grounding enforcement and synthesis checkpoint
**Priority**: P0 (Grounding Ratio) + P2 (Negative Grounding)

### Task 2.1: Grounding Enforcement Protocol

**Description**: Create the grounding enforcement protocol document.

**File**: `.claude/protocols/grounding-enforcement.md`

**Acceptance Criteria**:
- [ ] Citation format requirement documented (code quote + absolute path + line)
- [ ] Grounding ratio calculation documented
- [ ] Configuration levels documented (strict | warn | disabled)
- [ ] Error messages and remediation steps documented
- [ ] Integration with synthesis checkpoint documented

**Test Scenarios**:
1. Citation format validation works correctly
2. Grounding ratio calculation is accurate
3. Configuration respects enforcement level setting

**References**:
- PRD FR-6: Grounding Ratio Enforcement
- SDD §4.5: Grounding Enforcement

---

### Task 2.2: Grounding Check Script

**Description**: Create the grounding ratio calculation script.

**File**: `.claude/scripts/grounding-check.sh`

**Acceptance Criteria**:
- [ ] Script calculates ratio from trajectory log
- [ ] Handles zero-claim sessions gracefully (returns 1.00)
- [ ] Outputs structured data (total_claims, grounded_claims, assumptions, ratio, status)
- [ ] Returns exit code 1 if below threshold
- [ ] Uses `bc` for accurate decimal calculation

**Test Scenarios**:
1. Script correctly calculates ratio from sample trajectory
2. Script handles empty trajectory file
3. Script returns correct exit codes for pass/fail

**References**:
- SDD §4.2: Grounding Ratio Script
- PRD FR-6: Grounding Ratio Enforcement

---

### Task 2.3: Negative Grounding Protocol

**Description**: Add negative grounding verification for Ghost Features.

**File**: `.claude/protocols/grounding-enforcement.md` (section)

**Acceptance Criteria**:
- [ ] Ghost Feature verification protocol documented
- [ ] Two diverse semantic queries requirement documented
- [ ] 0.4 similarity threshold documented
- [ ] [UNVERIFIED GHOST] flag format documented
- [ ] Blocking behavior in strict mode documented

**Test Scenarios**:
1. Ghost Feature verified with 2 diverse queries returning 0 results
2. Unverified ghost correctly flagged
3. /clear blocked when unverified ghosts in strict mode

**References**:
- PRD FR-7: Negative Grounding Protocol
- SDD §4.2: Negative Grounding

---

### Task 2.4: Synthesis Checkpoint Protocol

**Description**: Create the synthesis checkpoint protocol document.

**File**: `.claude/protocols/synthesis-checkpoint.md`

**Acceptance Criteria**:
- [ ] 7-step checkpoint process documented
- [ ] Blocking steps identified (grounding verification, negative grounding)
- [ ] Non-blocking steps identified (ledger sync)
- [ ] Error handling and remediation documented
- [ ] Trajectory logging requirements documented

**Test Scenarios**:
1. Checkpoint blocks when grounding ratio < 0.95
2. Checkpoint passes when all verifications succeed
3. Non-blocking steps complete even if blocking steps fail

**References**:
- PRD FR-2: Session Continuity Protocol (Before /clear section)
- SDD §4.2: Synthesis Checkpoint

---

### Task 2.5: Synthesis Checkpoint Script

**Description**: Create the pre-clear validation script.

**File**: `.claude/scripts/synthesis-checkpoint.sh`

**Acceptance Criteria**:
- [ ] Script calls grounding-check.sh
- [ ] Script checks for unverified ghosts (strict mode)
- [ ] Script reads enforcement level from .loa.config.yaml
- [ ] Script returns appropriate exit codes
- [ ] Script outputs clear error messages

**Test Scenarios**:
1. Script exits 0 when all checks pass
2. Script exits 1 when grounding ratio below threshold
3. Script respects warn vs strict mode

**References**:
- SDD §4.2: Synthesis Checkpoint
- SDD §4.7: Hook Integration

---

### Task 2.6: Self-Healing State Zone Script

**Description**: Create the State Zone recovery script.

**File**: `.claude/scripts/self-heal-state.sh`

**Acceptance Criteria**:
- [ ] Git-backed recovery implemented (git show HEAD:...)
- [ ] Git checkout fallback implemented
- [ ] Template reconstruction fallback implemented
- [ ] Delta reindex for .ck/ implemented
- [ ] Recovery logged to trajectory

**Test Scenarios**:
1. Missing NOTES.md recovered from git history
2. Missing .beads/ directory recovered from git checkout
3. Template used when git unavailable
4. Script never halts on missing files

**References**:
- PRD FR-9: Self-Healing State Zone
- SDD §4.6: Self-Healing State Zone

---

## Sprint 3: Integration

**Focus**: Integrate protocols with existing commands and skills
**Priority**: P1 (JIT Retrieval, Self-Healing) + Integration Requirements

### Task 3.1: /ride Command Session Awareness

**Description**: Update /ride command for session-aware initialization.

**File**: `.claude/commands/ride.md` (update)

**Acceptance Criteria**:
- [ ] Session start actions added (bd ready, bd show, tiered recovery)
- [ ] During session actions documented (continuous synthesis, delta sync)
- [ ] On complete actions documented (synthesis checkpoint, trajectory handoff)
- [ ] Session continuity protocol referenced

**Test Scenarios**:
1. /ride starts with session recovery
2. /ride triggers delta-synthesis at Yellow threshold
3. /ride completes with synthesis checkpoint

**References**:
- SDD §6.1: Command Integration
- PRD FR-2: Session Continuity Protocol

---

### Task 3.2: Configuration Schema Update

**Description**: Add Lossless Ledger Protocol configuration to .loa.config.yaml.

**File**: `.loa.config.yaml` (update) and documentation

**Acceptance Criteria**:
- [ ] grounding_enforcement option added (strict | warn | disabled)
- [ ] attention_budget thresholds added
- [ ] session_continuity settings added
- [ ] edd settings added
- [ ] Default values set appropriately

**Test Scenarios**:
1. Configuration loads correctly
2. Default values work without explicit config
3. Scripts read configuration values correctly

**References**:
- SDD §5.4: Configuration Schema
- PRD FR-6: Grounding Ratio Enforcement (configurable section)

---

### Task 3.3: Skill Protocol References

**Description**: Update skill index.yaml files to reference new protocols.

**Files**: `.claude/skills/*/index.yaml` (update)

**Acceptance Criteria**:
- [ ] implementing-tasks references all new protocols
- [ ] reviewing-code references grounding-enforcement
- [ ] All skills reference session-continuity
- [ ] Protocol loading documented

**Test Scenarios**:
1. implementing-tasks agent follows session continuity protocol
2. reviewing-code agent checks grounding ratio
3. Protocols load correctly via skill system

**References**:
- SDD §6.2: Skill Integration

---

### Task 3.4: ck Integration for JIT Retrieval

**Description**: Document ck integration for JIT retrieval with fallbacks.

**File**: `.claude/protocols/jit-retrieval.md` (section)

**Acceptance Criteria**:
- [ ] ck --hybrid usage documented with examples
- [ ] ck --full-section usage documented with examples
- [ ] Fallback to grep/sed documented with examples
- [ ] check-ck.sh usage for availability detection documented

**Test Scenarios**:
1. JIT retrieval works with ck installed
2. JIT retrieval falls back gracefully without ck
3. AST-aware snippets work with ck --full-section

**References**:
- PRD IR-1: ck Semantic Search Integration
- SDD §6.3: ck Integration

---

### Task 3.5: Beads CLI Integration

**Description**: Document Beads CLI extensions for decision tracking.

**File**: `.claude/protocols/session-continuity.md` (section)

**Acceptance Criteria**:
- [ ] bd show display of decisions[] and handoffs[] documented
- [ ] bd update for appending decisions documented
- [ ] Fork detection concept documented
- [ ] Fallback to NOTES.md when Beads unavailable documented

**Test Scenarios**:
1. bd show displays decision history
2. Decisions can be appended via bd update
3. Session handoff creates lineage in handoffs[]

**References**:
- PRD IR-2: Beads Integration
- SDD §6.4: Beads Integration

---

### Task 3.6: CLAUDE.md Documentation Update

**Description**: Update CLAUDE.md with Lossless Ledger Protocol documentation.

**File**: `CLAUDE.md` (update)

**Acceptance Criteria**:
- [ ] Lossless Ledger Protocol section added
- [ ] Truth hierarchy documented
- [ ] New protocols listed
- [ ] New scripts documented
- [ ] Configuration options documented

**Test Scenarios**:
1. Developers can understand protocol from CLAUDE.md
2. All new files referenced correctly
3. Configuration examples included

**References**:
- SDD §9.1: File Changes Summary

---

## Sprint 4: Quality & Polish

**Focus**: Testing, edge cases, documentation completeness
**Priority**: Validation and handoff readiness

### Task 4.1: Unit Tests for Scripts

**Description**: Create unit tests for all new scripts.

**Files**: `tests/unit/grounding-check.bats`, `tests/unit/synthesis-checkpoint.bats`, `tests/unit/self-heal-state.bats`

**Acceptance Criteria**:
- [ ] grounding-check.sh tests: ratio calculation, edge cases, exit codes
- [ ] synthesis-checkpoint.sh tests: enforcement levels, blocking behavior
- [ ] self-heal-state.sh tests: recovery priority, git fallback, templates
- [ ] >80% code coverage for scripts

**Test Scenarios**:
1. All scripts pass unit tests
2. Edge cases handled (empty files, missing dependencies)
3. Exit codes correct for all scenarios

---

### Task 4.2: Integration Tests

**Description**: Create integration tests for session lifecycle.

**Files**: `tests/integration/session-lifecycle.bats`

**Acceptance Criteria**:
- [ ] Session start with recovery tested
- [ ] Delta-synthesis trigger tested
- [ ] Synthesis checkpoint flow tested
- [ ] Self-healing recovery tested

**Test Scenarios**:
1. Full session lifecycle completes successfully
2. Recovery works after simulated crash
3. Grounding enforcement blocks appropriately

---

### Task 4.3: Edge Case Handling

**Description**: Handle edge cases identified in PRD/SDD.

**Acceptance Criteria**:
- [ ] Zero-claim sessions return ratio 1.00
- [ ] Missing trajectory file handled gracefully
- [ ] Corrupted ledger lines dropped (not fatal)
- [ ] Missing configuration uses safe defaults

**Test Scenarios**:
1. New session with no trajectory passes grounding check
2. Malformed trajectory line skipped
3. Missing .loa.config.yaml uses defaults

---

### Task 4.4: Protocol Cross-References

**Description**: Ensure all protocols cross-reference correctly.

**Files**: All protocol files

**Acceptance Criteria**:
- [ ] session-continuity references synthesis-checkpoint
- [ ] synthesis-checkpoint references grounding-enforcement
- [ ] jit-retrieval references session-continuity
- [ ] attention-budget references session-continuity
- [ ] Protocol dependency diagram included

**Test Scenarios**:
1. Agent can follow protocol chain from session-continuity
2. No broken references in protocols
3. Dependency diagram accurate

---

### Task 4.5: CI/CD Validation

**Description**: Add CI validation for Lossless Ledger Protocol.

**File**: `.claude/scripts/check-loa.sh` (update)

**Acceptance Criteria**:
- [ ] New protocol files validated (exist, not empty)
- [ ] New script files validated (executable, shellcheck passes)
- [ ] Configuration schema validated
- [ ] NOTES.md template validated

**Test Scenarios**:
1. CI catches missing protocol files
2. CI catches non-executable scripts
3. CI validates configuration schema

---

### Task 4.6: Release Documentation

**Description**: Create release documentation for v0.9.0.

**Files**: `CHANGELOG.md` (update), `loa-grimoire/deployment/RELEASE_NOTES_LOSSLESS_LEDGER.md`

**Acceptance Criteria**:
- [ ] CHANGELOG.md entry for v0.9.0
- [ ] Release notes with feature summary
- [ ] Migration notes (v0.8.0 -> v0.9.0)
- [ ] Breaking changes documented (none expected)
- [ ] Known limitations documented

**Test Scenarios**:
1. Release notes accurately describe all changes
2. Migration path clear for existing projects
3. No breaking changes for v0.8.0 projects

---

### Task 4.7: UAT Validation

**Description**: Validate all PRD requirements implemented.

**Acceptance Criteria**:
- [ ] FR-1 through FR-11 validated
- [ ] IR-1 and IR-2 validated
- [ ] All acceptance criteria from PRD checked
- [ ] Performance targets met (session recovery < 30s)

**Test Scenarios**:
1. All functional requirements pass acceptance criteria
2. All integration requirements pass acceptance criteria
3. Performance within targets

---

### Task 4.8: Security Audit Preparation

**Description**: Prepare for security audit of v0.9.0.

**Acceptance Criteria**:
- [ ] No secrets in ledger templates
- [ ] Path validation prevents traversal
- [ ] Audit trail immutability verified
- [ ] Safe defaults documented

**Test Scenarios**:
1. Security checklist passes
2. No credential patterns in new files
3. All paths validated against ${PROJECT_ROOT}

---

## Success Criteria

### Sprint Gates

| Sprint | Gate | Criteria |
|--------|------|----------|
| 1 | Foundation Complete | 5 protocols created, schema extensions documented |
| 2 | Enforcement Ready | Scripts pass unit tests, grounding check works |
| 3 | Integration Complete | Commands updated, skills reference protocols |
| 4 | Release Ready | All tests pass, documentation complete, audit ready |

### PRD Traceability

| Requirement | Sprint | Tasks |
|-------------|--------|-------|
| FR-1: Truth Hierarchy | 1 | 1.1 |
| FR-2: Session Continuity | 1, 3 | 1.1, 3.1 |
| FR-3: Tiered Recovery | 1 | 1.1, 1.2 |
| FR-4: Attention Budget | 1 | 1.4 |
| FR-5: JIT Retrieval | 1, 3 | 1.3, 3.4 |
| FR-6: Grounding Ratio | 2 | 2.1, 2.2 |
| FR-7: Negative Grounding | 2 | 2.3 |
| FR-8: Trajectory Handoff | 1 | 1.5 |
| FR-9: Self-Healing | 2 | 2.6 |
| FR-10: NOTES.md Extension | 1 | 1.2 |
| FR-11: Bead Schema | 1 | 1.6 |
| IR-1: ck Integration | 3 | 3.4 |
| IR-2: Beads Integration | 3 | 3.5 |

### KPIs

| Metric | Target | Validation |
|--------|--------|------------|
| Session recovery time | < 30 seconds | Integration test |
| Level 1 token usage | < 100 tokens | Protocol compliance |
| Grounding ratio threshold | >= 0.95 | Script validation |
| Token reduction | 97% (JIT vs eager) | Protocol documentation |
| Test coverage | > 80% | Unit tests |

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Hook integration complexity | Start with protocol-only (Sprint 1-2), add hooks after validation |
| Grounding too strict | Default to `warn` mode, document `strict` for security-critical |
| ck unavailability | All features have grep/sed fallbacks |
| Bead schema breaks existing | Additive changes only, no required field changes |

---

## Dependencies

### External Dependencies

| Dependency | Required | Fallback |
|------------|----------|----------|
| Claude Code hooks | No (v0.9.0) | Protocol-only enforcement |
| ck | No | grep/sed |
| Beads (bd) | No | NOTES.md only |
| Git | Yes | None (required for self-healing) |

### Inter-Sprint Dependencies

```
Sprint 1 (Foundation)
    │
    ├── Sprint 2 (Enforcement)
    │   └── Depends: session-continuity.md, trajectory schema
    │
    └── Sprint 3 (Integration)
        └── Depends: All protocols, all scripts
            │
            └── Sprint 4 (Polish)
                └── Depends: Everything from Sprint 1-3
```

---

**Document Version**: 1.0
**Total Tasks**: 24
**Estimated Complexity**: Medium-High (protocol-heavy, limited code changes)
**Paradigm**: Clear, Don't Compact
