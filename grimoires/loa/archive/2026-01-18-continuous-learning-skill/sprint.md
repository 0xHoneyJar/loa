# Sprint Plan: Continuous Learning Skill

**Version:** 1.0
**Date:** 2026-01-18
**Author:** Sprint Planner Agent
**Cycle:** cycle-004 (Continuous Learning Skill)
**Target Version:** v0.17.0
**PRD Reference:** grimoires/loa/prd.md
**SDD Reference:** grimoires/loa/sdd.md

---

## Executive Summary

Implement autonomous skill extraction and continuous learning capability for Loa Framework. This cycle adds the ability for agents to detect non-obvious discoveries during implementation phases and extract them into reusable skills that persist across sessions.

> From prd.md: "Loa agents currently lose discovered knowledge when sessions end... Future sessions encountering the same issue must rediscover the solution from scratch." (prd.md:L21-23)

**Total Sprints:** 4
**Sprint Duration:** 2.5 days each
**Target Delivery:** v0.17.0

---

## Sprint Overview

| Sprint | Theme | Key Deliverables | Dependencies |
|--------|-------|------------------|--------------|
| 1 | Core Infrastructure | Directory structure, protocol document, index.yaml | None |
| 2 | Skill Definition | SKILL.md, skill-template.md, example skill | Sprint 1 |
| 3 | Commands | /retrospective, /skill-audit, trajectory logging | Sprint 2 |
| 4 | Integration & Polish | Configuration, documentation, tests | Sprint 3 |

---

## Sprint 1: Core Infrastructure

**Duration:** 2.5 days
**Global Sprint ID:** 18

### Sprint Goal

Establish the foundational directory structure and protocol documentation that enables skill extraction to the State Zone while maintaining Three-Zone Model compliance.

### Deliverables

- [ ] State Zone skill directories created (`grimoires/loa/skills/`, `skills-pending/`, `skills-archived/`)
- [ ] Continuous Learning Protocol document complete (`.claude/protocols/continuous-learning.md`)
- [ ] Skill index.yaml with valid schema (`.claude/skills/continuous-learning/index.yaml`)

### Acceptance Criteria

> From prd.md FR-1: "`.claude/skills/continuous-learning/` directory exists with index.yaml, SKILL.md, resources/" (prd.md:L83)

- [ ] `grimoires/loa/skills/` directory exists with `.gitkeep`
- [ ] `grimoires/loa/skills-pending/` directory exists with `.gitkeep`
- [ ] `grimoires/loa/skills-archived/` directory exists with `.gitkeep`
- [ ] `.claude/skills/continuous-learning/` directory created
- [ ] Protocol document contains all four quality gates (Discovery Depth, Reusability, Trigger Clarity, Verification)
- [ ] Protocol contains phase gating table per prd.md:L121-130
- [ ] Protocol contains zone compliance section
- [ ] index.yaml passes YAML validation
- [ ] index.yaml contains all required fields per sdd.md Section 3.1.2

### Technical Tasks

- [ ] Create `grimoires/loa/skills/.gitkeep`
- [ ] Create `grimoires/loa/skills-pending/.gitkeep`
- [ ] Create `grimoires/loa/skills-archived/.gitkeep`
- [ ] Create `.claude/skills/continuous-learning/` directory structure
- [ ] Create `.claude/protocols/continuous-learning.md` with:
  - Evaluation flow diagram (ASCII)
  - Four quality gates with pass/fail criteria
  - Phase restrictions table
  - Zone compliance rules
  - Trajectory logging format
  - Configuration reference
- [ ] Create `.claude/skills/continuous-learning/index.yaml` with:
  - name, version, model, color fields
  - description, triggers, examples
  - outputs paths
  - phase_activation enabled/disabled lists
  - protocols required/recommended lists

### Dependencies

- None (first sprint)

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Zone boundary confusion | Low | High | Clear documentation in protocol, explicit path references |
| Invalid YAML schema | Low | Med | Validate against existing skill index.yaml patterns |

### Success Metrics

- All 3 State Zone directories exist
- Protocol document complete with all sections
- index.yaml validates without errors

---

## Sprint 2: Skill Definition

**Duration:** 2.5 days
**Global Sprint ID:** 19

### Sprint Goal

Create the core SKILL.md instructions and skill extraction template that enable agents to detect discoveries and format them consistently for extraction.

### Deliverables

- [ ] SKILL.md complete with activation triggers and quality gate instructions (`.claude/skills/continuous-learning/SKILL.md`)
- [ ] Skill template for extracted skills (`.claude/skills/continuous-learning/resources/skill-template.md`)
- [ ] Example extracted skill demonstrating format (`.claude/skills/continuous-learning/resources/examples/nats-jetstream-consumer-durable.md`)
- [ ] resources/ directory structure

### Acceptance Criteria

> From prd.md FR-3: "SKILL.md exists with YAML frontmatter... Activation triggers clearly defined... Phase gating table present" (prd.md:L133-137)

- [ ] SKILL.md contains YAML frontmatter with name, description, author, version, loa-agent-scope
- [ ] SKILL.md defines all four activation triggers per prd.md:L114-119
- [ ] SKILL.md includes phase gating table
- [ ] SKILL.md documents NOTES.md integration
- [ ] SKILL.md specifies agent tagging format
- [ ] skill-template.md contains all required sections per prd.md:L145-155
- [ ] skill-template.md YAML frontmatter includes: name, description, loa-agent, extracted-from, extraction-date, version, tags
- [ ] Example skill demonstrates correct format per prd.md Appendix B:L390-458

### Technical Tasks

- [ ] Create `.claude/skills/continuous-learning/resources/` directory
- [ ] Create `.claude/skills/continuous-learning/resources/examples/` directory
- [ ] Create `.claude/skills/continuous-learning/SKILL.md` with:
  - YAML frontmatter
  - Overview section with research foundation
  - Activation Triggers section (4 triggers)
  - Integration with Loa Architecture section
  - Quality Gates section (4 gates with criteria)
  - Workflow section (automatic + manual modes)
  - Skill Format section (template reference)
  - Phase Gating section (enabled/disabled table)
  - Skill Lifecycle section (pending/active/archived states)
  - Configuration section (.loa.config.yaml options)
  - Integration with Trajectory Evaluation section
- [ ] Create `.claude/skills/continuous-learning/resources/skill-template.md` with:
  - YAML frontmatter template
  - Problem section
  - Trigger Conditions section (error messages, symptoms, context)
  - Root Cause section
  - Solution section (step-by-step with code)
  - Verification section
  - Anti-Patterns section
  - Related Memory section (NOTES.md cross-refs)
  - Changelog section
- [ ] Create `.claude/skills/continuous-learning/resources/examples/nats-jetstream-consumer-durable.md` (copy from prd.md Appendix B)

### Dependencies

- Sprint 1: Protocol document must exist for SKILL.md to reference
- Sprint 1: index.yaml must exist for skill registration

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Template too complex | Med | Med | Start with minimal sections, expand if needed |
| Activation triggers unclear | Med | Med | Include concrete examples in SKILL.md |

### Success Metrics

- SKILL.md validates with complete YAML frontmatter
- Template covers all required sections
- Example skill passes template validation

---

## Sprint 3: Commands

**Duration:** 2.5 days
**Global Sprint ID:** 20

### Sprint Goal

Implement the /retrospective and /skill-audit commands that enable manual skill extraction and lifecycle management.

### Deliverables

- [ ] `/retrospective` command complete (`.claude/commands/retrospective.md`)
- [ ] `/skill-audit` command complete (`.claude/commands/skill-audit.md`)
- [ ] Trajectory logging integration for skill extraction events

### Acceptance Criteria

> From prd.md FR-5: "Command file exists at specified location... Five-step workflow documented... Options documented with usage examples" (prd.md:L180-185)

- [ ] `/retrospective` command exists at `.claude/commands/retrospective.md`
- [ ] `/retrospective` documents 5-step workflow (Session Analysis, Quality Gate Evaluation, Cross-Reference Check, Skill Extraction, Summary)
- [ ] `/retrospective` supports `--scope <agent>` option
- [ ] `/retrospective` supports `--force` option
- [ ] `/retrospective` includes example conversation flow
- [ ] `/retrospective` documents NOTES.md integration

> From prd.md FR-6: "Command file exists at specified location... All subcommands documented" (prd.md:L200-205)

- [ ] `/skill-audit` command exists at `.claude/commands/skill-audit.md`
- [ ] `/skill-audit --pending` lists skills awaiting approval
- [ ] `/skill-audit --approve <skill-name>` moves skill to active
- [ ] `/skill-audit --reject <skill-name>` archives skill with reason
- [ ] `/skill-audit --prune` reviews for low-value skills
- [ ] `/skill-audit --stats` shows skill statistics
- [ ] Pruning criteria documented (age > 90 days, < 2 matches)

> From prd.md FR-10: "JSONL format specified... All event types documented" (prd.md:L285-289)

- [ ] Trajectory logging format documented per sdd.md Section 3.5.3
- [ ] Event types: extraction, approval, rejection, prune, match

### Technical Tasks

- [ ] Create `.claude/commands/retrospective.md` with:
  - Purpose and invocation
  - 5-step workflow diagram per sdd.md Section 3.4.1
  - Options table (--scope, --force)
  - NOTES.md integration documentation
  - Example conversation flow
  - Error handling
- [ ] Create `.claude/commands/skill-audit.md` with:
  - Purpose and invocation
  - Subcommands table (--pending, --approve, --reject, --prune, --stats)
  - Approval workflow diagram per sdd.md Section 3.4.2
  - Rejection workflow diagram
  - Pruning criteria table
  - Example usage for each subcommand
- [ ] Document trajectory logging format in protocol:
  - File path: `grimoires/loa/a2a/trajectory/continuous-learning-{date}.jsonl`
  - JSONL schema per sdd.md Section 3.5.3
  - Event types and required fields

### Dependencies

- Sprint 2: SKILL.md must exist for command integration
- Sprint 2: skill-template.md must exist for extraction output

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Command complexity | Med | Med | Keep workflows simple, defer automation |
| Trajectory file conflicts | Low | Low | Use date-based file naming |

### Success Metrics

- Both commands parse without YAML errors
- All subcommands documented with examples
- Trajectory JSONL schema matches sdd.md specification

---

## Sprint 4: Integration & Polish

**Duration:** 2.5 days
**Global Sprint ID:** 21

### Sprint Goal

Complete configuration schema, update framework documentation, and verify end-to-end functionality with tests.

### Deliverables

- [ ] Configuration schema added to `.loa.config.yaml`
- [ ] CLAUDE.md updated with new commands and configuration
- [ ] CHANGELOG.md entry for v0.17.0
- [ ] Unit tests for quality gates and zone compliance
- [ ] Integration tests for /retrospective and /skill-audit flows

### Acceptance Criteria

> From prd.md FR-8: "Configuration schema documented... Default values specified... Each option has description... CLAUDE.md updated" (prd.md:L244-248)

- [ ] `.loa.config.yaml` contains `continuous_learning` section per prd.md:L228-242
- [ ] All configuration options have default values
- [ ] CLAUDE.md documents `/retrospective` command
- [ ] CLAUDE.md documents `/skill-audit` command
- [ ] CLAUDE.md documents `continuous_learning` configuration section
- [ ] CHANGELOG.md contains v0.17.0 entry with all changes

> From prd.md NFR-4: "MUST update CLAUDE.md with new commands and configuration... MUST update CHANGELOG.md for v0.17.0" (prd.md:L315-316)

- [ ] Unit tests pass for quality gate logic
- [ ] Unit tests pass for zone compliance (no System Zone writes)
- [ ] Integration tests pass for retrospective flow
- [ ] Integration tests pass for skill-audit flows
- [ ] All existing tests still pass (no regressions)

### Technical Tasks

- [ ] Update `.loa.config.yaml` with continuous_learning section:
  - enabled, auto_extract, require_approval
  - skills_dir, pending_dir, archive_dir
  - min_discovery_depth, require_verification
  - check_notes_md, deduplicate
  - prune_after_days, prune_min_matches
- [ ] Update `CLAUDE.md`:
  - Add /retrospective to command table
  - Add /skill-audit to command table
  - Add continuous_learning configuration section
  - Add extracted skills to document flow diagram
- [ ] Create `CHANGELOG.md` entry for v0.17.0:
  - List all new files created
  - Document new commands
  - Document configuration options
  - Reference PRD/SDD
- [ ] Create `tests/unit/quality-gates.bats`:
  - Test Discovery Depth gate logic
  - Test Reusability gate logic
  - Test Trigger Clarity gate logic
  - Test Verification gate logic
- [ ] Create `tests/unit/zone-compliance.bats`:
  - Test extracted skills cannot write to .claude/
  - Test skills write to grimoires/loa/skills-pending/
- [ ] Create `tests/integration/retrospective.bats`:
  - Test end-to-end extraction flow
  - Test --scope option
  - Test --force option
- [ ] Create `tests/integration/skill-audit.bats`:
  - Test --pending subcommand
  - Test --approve workflow
  - Test --reject workflow
  - Test --prune criteria

### Dependencies

- Sprint 3: All commands must exist for documentation and testing
- Sprint 2: SKILL.md must exist for quality gate references
- Sprint 1: Protocol must exist for test assertions

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Test complexity | Med | Med | Focus on critical paths first |
| Documentation drift | Low | Med | Generate docs from source where possible |
| Regression in existing features | Low | High | Run full test suite before merge |

### Success Metrics

- Configuration validates without errors
- All 4 test files created and passing
- CLAUDE.md includes all new content
- CHANGELOG.md entry complete

---

## Risk Register

| ID | Risk | Sprint | Probability | Impact | Mitigation | Owner |
|----|------|--------|-------------|--------|------------|-------|
| R1 | Zone boundary violation | 1-4 | Low | High | Pre-commit hooks, clear documentation, tests | Framework |
| R2 | Over-extraction of low-value skills | 3-4 | Med | Med | Quality gates, manual approval workflow | Framework |
| R3 | Template complexity causing extraction failures | 2 | Med | Med | Start simple, iterate based on feedback | Framework |
| R4 | Command parsing issues | 3 | Low | Med | Follow existing command patterns | Framework |
| R5 | Test coverage gaps | 4 | Med | Med | Prioritize critical path tests | Framework |

---

## Success Metrics Summary

| Metric | Target | Measurement Method | Sprint |
|--------|--------|-------------------|--------|
| Directory structure complete | 100% | File existence checks | 1 |
| Protocol sections complete | 7/7 | Manual review | 1 |
| SKILL.md sections complete | 10/10 | Manual review | 2 |
| Template sections complete | 9/9 | Manual review | 2 |
| Command workflows documented | 2/2 | Manual review | 3 |
| Configuration options | 11/11 | YAML validation | 4 |
| Test files created | 4/4 | File count | 4 |
| All tests passing | 100% | bats test runner | 4 |

---

## Dependencies Map

```
Sprint 1 ──────────────▶ Sprint 2 ──────────────▶ Sprint 3 ──────────────▶ Sprint 4
   │                        │                        │                        │
   └─ Infrastructure        └─ Skill Definition      └─ Commands              └─ Integration

   Directories              SKILL.md                 /retrospective           Configuration
   Protocol                 Template                 /skill-audit             Documentation
   index.yaml               Example                  Trajectory               Tests
```

---

## Appendix A: PRD Feature Mapping

| PRD Feature | Description | Sprint | Status |
|-------------|-------------|--------|--------|
| FR-1 | Skill Directory Structure | 1 | Planned |
| FR-2 | Continuous Learning Protocol | 1 | Planned |
| FR-3 | Continuous Learning Skill Definition | 2 | Planned |
| FR-4 | Skill Template | 2 | Planned |
| FR-5 | /retrospective Command | 3 | Planned |
| FR-6 | /skill-audit Command | 3 | Planned |
| FR-7 | Quality Gates | 1, 2 | Planned |
| FR-8 | Configuration Schema | 4 | Planned |
| FR-9 | Structured Memory Integration | 2, 3 | Planned |
| FR-10 | Trajectory Logging | 3 | Planned |

---

## Appendix B: SDD Component Mapping

| SDD Component | Section | Sprint | Status |
|---------------|---------|--------|--------|
| Directory Structure | 3.1.1 | 1 | Planned |
| index.yaml Schema | 3.1.2 | 1 | Planned |
| SKILL.md Structure | 3.1.3 | 2 | Planned |
| Quality Gates System | 3.2 | 1, 2 | Planned |
| Skill Template | 3.3 | 2 | Planned |
| /retrospective Command | 3.4.1 | 3 | Planned |
| /skill-audit Command | 3.4.2 | 3 | Planned |
| Trajectory Logging | 3.5 | 3 | Planned |
| Configuration Schema | 3.6 | 4 | Planned |
| NOTES.md Integration | 4.1 | 2, 3 | Planned |
| Trajectory Integration | 4.2 | 3 | Planned |
| Testing Strategy | 7 | 4 | Planned |

---

## Appendix C: Files to Create

### Sprint 1 Files
```
grimoires/loa/skills/.gitkeep
grimoires/loa/skills-pending/.gitkeep
grimoires/loa/skills-archived/.gitkeep
.claude/skills/continuous-learning/index.yaml
.claude/protocols/continuous-learning.md
```

### Sprint 2 Files
```
.claude/skills/continuous-learning/SKILL.md
.claude/skills/continuous-learning/resources/skill-template.md
.claude/skills/continuous-learning/resources/examples/nats-jetstream-consumer-durable.md
```

### Sprint 3 Files
```
.claude/commands/retrospective.md
.claude/commands/skill-audit.md
```

### Sprint 4 Files
```
tests/unit/quality-gates.bats
tests/unit/zone-compliance.bats
tests/integration/retrospective.bats
tests/integration/skill-audit.bats
```

### Sprint 4 Modified Files
```
.loa.config.yaml
CLAUDE.md
CHANGELOG.md
```

---

*Generated by Sprint Planner Agent*
*Cycle: cycle-004 (Continuous Learning Skill)*
*Target Version: v0.17.0*
