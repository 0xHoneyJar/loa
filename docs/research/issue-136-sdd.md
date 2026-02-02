# Software Design Document: CLAUDE.md Context Loading Optimization

**Version:** 1.0
**Date:** 2026-02-02
**Author:** Architecture Designer Agent
**Status:** Draft
**Research Reference:** docs/research/issue-136-claude-md-research.md
**Issue:** [#136](https://github.com/0xHoneyJar/loa/issues/136)

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Current State Analysis](#2-current-state-analysis)
3. [Target Architecture](#3-target-architecture)
4. [Component Design](#4-component-design)
5. [Migration Strategy](#5-migration-strategy)
6. [Content Classification](#6-content-classification)
7. [Testing Strategy](#7-testing-strategy)
8. [Implementation Phases](#8-implementation-phases)
9. [Risks and Mitigations](#9-risks-and-mitigations)
10. [Success Criteria](#10-success-criteria)

---

## 1. Executive Summary

### 1.1 Problem

Loa's CLAUDE.loa.md file currently contains **1169 lines / 43KB**, exceeding Claude Code's recommended **~500 lines**. This causes:

1. **Token waste**: ~11K tokens loaded every session regardless of task
2. **Instruction dilution**: Critical rules lost among reference documentation
3. **No JIT loading**: All content loaded eagerly, ignoring Claude Code's tiered architecture

### 1.2 Solution

Restructure CLAUDE.loa.md to follow Claude Code's official tiered loading model:

| Tier | Content | When Loaded | Target Size |
|------|---------|-------------|-------------|
| **Always** | Core rules, architecture, routing | Session start | ~150 lines |
| **On-Demand** | Skill-specific docs | Skill invocation | Already exists in SKILL.md |
| **Reference** | Config examples, version notes | Manual lookup | New reference/ dir |

### 1.3 Key Metrics

| Metric | Current | Phase 1 | Phase 2 |
|--------|---------|---------|---------|
| Lines | 1169 | ~400 | ~150 |
| Characters | 43KB | ~25KB | ~12KB |
| Est. tokens | ~11K | ~6K | ~3K |

---

## 2. Current State Analysis

### 2.1 File Structure

```
CLAUDE.md (project root, ~1.2KB)
└── @.claude/loa/CLAUDE.loa.md (43KB, 1169 lines)
    └── References protocols, schemas, scripts (not @imported)
```

### 2.2 Content Breakdown

Analysis of current CLAUDE.loa.md sections:

| Section | Lines | % | Session Relevance | Action |
|---------|-------|---|-------------------|--------|
| Header/Overview | ~30 | 3% | ✅ Always needed | Keep |
| Architecture (Three-Zone, Skills) | ~80 | 7% | ✅ Always needed | Keep |
| Command Architecture | ~30 | 3% | ✅ Always needed | Keep |
| Workflow Commands table | ~20 | 2% | ✅ Routing needed | Keep (condensed) |
| Codebase Grounding (v1.6.0) | ~40 | 3% | ⚠️ Only for /ride | Move to skill |
| Goal Traceability (v0.21.0) | ~50 | 4% | ⚠️ Only for sprints | Move to skill |
| Autonomous Agent (v1.11.0) | ~80 | 7% | ⚠️ Only for /autonomous | Move to skill |
| Intelligent Subagents | ~40 | 3% | ⚠️ Only for /validate | Move to skill |
| Key Protocols | ~150 | 13% | ⚠️ Reference only | Move to reference |
| Karpathy Principles | ~30 | 3% | ✅ Behavioral | Keep (condensed) |
| Claude Code Features | ~60 | 5% | ⚠️ Reference only | Move to reference |
| Effort Parameter | ~40 | 3% | ⚠️ Reference only | Move to reference |
| Context Editing | ~60 | 5% | ⚠️ Reference only | Move to reference |
| Memory Schema | ~80 | 7% | ⚠️ Reference only | Move to reference |
| Skill Best Practices | ~60 | 5% | ⚠️ Reference only | Move to reference |
| Git Safety | ~20 | 2% | ✅ Always needed | Keep |
| Run Mode | ~50 | 4% | ⚠️ Only for /run | Move to skill |
| Prompt Enhancement | ~40 | 3% | ⚠️ Only for /enhance | Move to skill |
| Compound Learning | ~50 | 4% | ⚠️ Only for /compound | Move to skill |
| Visual Communication | ~40 | 3% | ⚠️ Reference only | Move to reference |
| Oracle/Learnings | ~100 | 9% | ⚠️ Only for /oracle | Move to skill |
| Helper Scripts | ~60 | 5% | ⚠️ Reference only | Move to reference |
| Config examples (YAML) | ~200 | 17% | ❌ Never needed inline | Move to example file |

### 2.3 Content Classification Summary

| Category | Lines | Action |
|----------|-------|--------|
| **Essential (Keep)** | ~180 | Remains in CLAUDE.loa.md |
| **Skill-Specific** | ~450 | Move to respective SKILL.md files |
| **Reference Only** | ~340 | Move to .claude/loa/reference/ |
| **Config Examples** | ~200 | Move to .loa.config.yaml.example |

---

## 3. Target Architecture

### 3.1 Tiered Loading Model

```
┌─────────────────────────────────────────────────────────────────┐
│                     TIER 1: ALWAYS LOADED                        │
│                     (~150 lines, ~12KB)                          │
├─────────────────────────────────────────────────────────────────┤
│ CLAUDE.md (project root)                                         │
│ └── @.claude/loa/CLAUDE.loa.md (slimmed)                        │
│     ├── Project Overview (~20 lines)                             │
│     ├── Three-Zone Model (~30 lines)                             │
│     ├── Skills System overview (~20 lines)                       │
│     ├── Command routing table (~20 lines)                        │
│     ├── Core behavioral rules (~40 lines)                        │
│     │   ├── Karpathy Principles (condensed)                      │
│     │   ├── Git Safety                                           │
│     │   └── Feedback Loops summary                               │
│     └── Quick reference pointers (~20 lines)                     │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                   TIER 2: ON-DEMAND (Skills)                     │
│              (Loaded when skill invoked)                         │
├─────────────────────────────────────────────────────────────────┤
│ .claude/skills/                                                  │
│ ├── autonomous-agent/SKILL.md      + Autonomous Agent docs       │
│ ├── discovering-requirements/      + Codebase Grounding docs     │
│ ├── planning-sprints/              + Goal Traceability docs      │
│ ├── implementing-tasks/            + Implementation protocols    │
│ ├── run-mode/SKILL.md              + Run Mode docs               │
│ ├── enhancing-prompts/SKILL.md     + Prompt Enhancement docs     │
│ ├── continuous-learning/SKILL.md   + Compound Learning docs      │
│ └── ... (15 total skills)                                        │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                   TIER 3: REFERENCE (Manual)                     │
│              (Loaded only when explicitly needed)                │
├─────────────────────────────────────────────────────────────────┤
│ .claude/loa/reference/                                           │
│ ├── protocols-summary.md           All protocol documentation    │
│ ├── config-reference.md            Config options reference      │
│ ├── scripts-reference.md           Helper scripts documentation  │
│ ├── version-features.md            Version-specific features     │
│ └── context-engineering.md         Context editing, memory, etc. │
│                                                                  │
│ .loa.config.yaml.example           Full config examples          │
│ CHANGELOG.md                       Version history               │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Loading Behavior

| User Action | What Loads | Tokens |
|-------------|-----------|--------|
| Start session | CLAUDE.md + CLAUDE.loa.md (Tier 1) | ~3K |
| `/plan-and-analyze` | + discovering-requirements/SKILL.md | +~2K |
| `/implement sprint-1` | + implementing-tasks/SKILL.md | +~2K |
| `/run sprint-plan` | + run-mode/SKILL.md | +~2K |
| Read reference manually | + reference/*.md | +variable |

---

## 4. Component Design

### 4.1 Slimmed CLAUDE.loa.md Structure

```markdown
<!-- @loa-managed: true | version: 2.0.0 | hash: PLACEHOLDER -->

# Loa Framework Instructions

## Project Overview
[20 lines - unchanged]

## Architecture

### Three-Zone Model
[30 lines - unchanged]

### Skills System
[20 lines - condensed, removed per-skill detail]

## Command Routing
[20 lines - table only, no feature descriptions]

## Core Behavioral Rules

### Karpathy Principles
[10 lines - 4 bullet points only]

### Git Safety
[10 lines - unchanged]

### Feedback Loops
[10 lines - summary only]

## Quick Reference

For detailed documentation:
- Protocol details: `.claude/loa/reference/protocols-summary.md`
- Config options: `.claude/loa/reference/config-reference.md`
- Version features: `.claude/loa/reference/version-features.md`
- Helper scripts: Run `script-name.sh --help`

Skills load their own documentation automatically when invoked.
```

### 4.2 Skill Enhancement Pattern

Each skill's SKILL.md will be enhanced with content moved from CLAUDE.loa.md:

```markdown
# Skill: run-mode

## Purpose
[existing content]

## Detailed Documentation

### Run Mode Protocol
[moved from CLAUDE.loa.md "Run Mode" section]

### Safety Model
[moved from CLAUDE.loa.md]

### Circuit Breaker
[moved from CLAUDE.loa.md]

## Configuration
[moved YAML examples relevant to this skill]
```

### 4.3 Reference Directory Structure

```
.claude/loa/reference/
├── README.md                 # Index of reference docs
├── protocols-summary.md      # All protocol documentation
├── config-reference.md       # Config options (no examples)
├── scripts-reference.md      # Script documentation
├── version-features.md       # v1.x.0 feature descriptions
└── context-engineering.md    # Context editing, memory schema, etc.
```

### 4.4 Config Example File

New file: `.loa.config.yaml.example`

```yaml
# Loa Framework Configuration Example
# Copy to .loa.config.yaml and customize

# Full documentation: .claude/loa/reference/config-reference.md

# --- Core Settings ---
integrity:
  enforcement: warn  # strict | warn | disabled

# --- Feature Flags ---
# [All YAML examples moved here from CLAUDE.loa.md]
```

---

## 5. Migration Strategy

### 5.1 Phase 1: Low-Risk Extraction (Sprint 1)

Move content that is clearly reference-only:

| Content | From | To | Risk |
|---------|------|-----|------|
| All YAML config examples | CLAUDE.loa.md | .loa.config.yaml.example | Low |
| Version notes (v1.x.0) | CLAUDE.loa.md | CHANGELOG.md or reference/ | Low |
| Script documentation | CLAUDE.loa.md | scripts-reference.md | Low |
| Protocol details | CLAUDE.loa.md | protocols-summary.md | Low |

**Validation**: Run full test suite, verify all commands still work.

### 5.2 Phase 2: Skill Migration (Sprint 2-3)

Move skill-specific documentation to SKILL.md files:

| Content | Target Skill |
|---------|--------------|
| Autonomous Agent section | autonomous-agent/SKILL.md |
| Codebase Grounding section | discovering-requirements/SKILL.md |
| Goal Traceability section | planning-sprints/SKILL.md |
| Run Mode section | run-mode/SKILL.md |
| Prompt Enhancement section | enhancing-prompts/SKILL.md |
| Compound Learning section | continuous-learning/SKILL.md |
| Oracle/Learnings section | riding-codebase/SKILL.md (or new skill) |

**Validation**: Test each skill individually after migration.

### 5.3 Backward Compatibility

1. **No breaking changes**: All information preserved, just relocated
2. **Pointer comments**: CLAUDE.loa.md includes "See skill X for details"
3. **Gradual rollout**: Can be done incrementally per-skill

---

## 6. Content Classification

### 6.1 Essential Content (Keep in CLAUDE.loa.md)

Content that applies to **every session** regardless of task:

| Content | Justification |
|---------|---------------|
| Three-Zone Model | Fundamental architecture understanding |
| Skills System overview | Routing and command understanding |
| Command routing table | Navigation |
| Karpathy Principles | Universal behavioral guidance |
| Git Safety | Prevents destructive operations |
| Feedback Loops summary | Quality gate awareness |

### 6.2 Skill-Specific Content (Move to SKILL.md)

Content that only matters when a specific skill is active:

| Content | Target |
|---------|--------|
| Autonomous Agent orchestration | autonomous-agent/ |
| Attention Budget details | implementing-tasks/, auditing-security/ |
| Goal Traceability details | planning-sprints/ |
| Run Mode protocol | run-mode/ |
| Compound Learning protocol | continuous-learning/ |

### 6.3 Reference Content (Move to reference/)

Content that is looked up, not applied automatically:

| Content | Target |
|---------|--------|
| All YAML config examples | .loa.config.yaml.example |
| Protocol file documentation | protocols-summary.md |
| Version-specific features | version-features.md |
| Context editing details | context-engineering.md |
| Memory schema details | context-engineering.md |
| Helper script documentation | scripts-reference.md |

---

## 7. Testing Strategy

### 7.1 Pre-Migration Baseline

Before any changes:

```bash
# Capture current behavior
./test-suite.sh > baseline-results.txt

# Document current file sizes
wc -l .claude/loa/CLAUDE.loa.md > baseline-metrics.txt
wc -c .claude/loa/CLAUDE.loa.md >> baseline-metrics.txt
```

### 7.2 Per-Phase Validation

After each phase:

1. **Line count check**: Verify reduction target met
2. **Full test suite**: All existing tests pass
3. **Skill invocation test**: Each skill still loads correctly
4. **Manual smoke test**: Run common workflows

### 7.3 Regression Detection

| Test | Method |
|------|--------|
| Command routing works | Invoke each /command |
| Skills load their docs | Check skill output mentions moved content |
| Reference accessible | Manual read of reference files |
| No orphaned content | Grep for moved content in CLAUDE.loa.md |

---

## 8. Implementation Phases

### 8.1 Phase 1: Reference Extraction (Sprint 1)

**Goal**: Reduce to ~400 lines

| Task | Lines Removed | Deliverable |
|------|---------------|-------------|
| Extract YAML examples | ~200 | .loa.config.yaml.example |
| Extract version notes | ~60 | version-features.md |
| Extract script docs | ~60 | scripts-reference.md |
| Extract protocol details | ~100 | protocols-summary.md |
| Add reference pointers | +20 | Updated CLAUDE.loa.md |
| **Net reduction** | **~400** | **~750 lines remaining** |

### 8.2 Phase 2: Skill Migration (Sprint 2)

**Goal**: Reduce to ~250 lines

| Task | Lines Removed | Target Skill |
|------|---------------|--------------|
| Autonomous Agent section | ~80 | autonomous-agent/SKILL.md |
| Run Mode section | ~50 | run-mode/SKILL.md |
| Goal Traceability section | ~50 | planning-sprints/SKILL.md |
| Codebase Grounding section | ~40 | discovering-requirements/SKILL.md |
| **Net reduction** | **~220** | **~530 lines remaining** |

### 8.3 Phase 3: Final Optimization (Sprint 3)

**Goal**: Reduce to ~150 lines

| Task | Lines Removed | Method |
|------|---------------|--------|
| Condense remaining sections | ~200 | Rewrite for brevity |
| Remove redundant tables | ~100 | Single consolidated table |
| Final cleanup | ~80 | Remove verbose explanations |
| **Net reduction** | **~380** | **~150 lines remaining** |

---

## 9. Risks and Mitigations

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Skill auto-loading unreliable | High | Medium | Test extensively; document manual /skill invocation |
| Behavior regression | High | Low | Comprehensive test suite; incremental rollout |
| Information harder to find | Medium | Medium | Clear reference index; pointer comments |
| Migration complexity | Medium | Low | Phase-based approach; revert capability |

---

## 10. Success Criteria

### 10.1 Quantitative

| Metric | Current | Phase 1 | Phase 2 | Phase 3 |
|--------|---------|---------|---------|---------|
| Lines | 1169 | ≤750 | ≤530 | ≤150 |
| Characters | 43KB | ≤30KB | ≤20KB | ≤12KB |
| Below ~500 line recommendation | No | No | No | ✅ Yes |

### 10.2 Qualitative

- [ ] All existing tests pass
- [ ] All commands work as before
- [ ] Skills load their documentation correctly
- [ ] Reference docs are discoverable
- [ ] No user-reported regressions

---

## Appendix A: Files Modified

| File | Change Type |
|------|-------------|
| `.claude/loa/CLAUDE.loa.md` | Major reduction |
| `.loa.config.yaml.example` | New file |
| `.claude/loa/reference/README.md` | New file |
| `.claude/loa/reference/protocols-summary.md` | New file |
| `.claude/loa/reference/config-reference.md` | New file |
| `.claude/loa/reference/scripts-reference.md` | New file |
| `.claude/loa/reference/version-features.md` | New file |
| `.claude/loa/reference/context-engineering.md` | New file |
| `.claude/skills/*/SKILL.md` | Enhanced (15 files) |
| `CHANGELOG.md` | Version notes added |

## Appendix B: Verification Checklist

Before merge:

- [ ] Line count ≤ target for phase
- [ ] `wc -l .claude/loa/CLAUDE.loa.md` shows reduction
- [ ] All tests pass
- [ ] Each skill tested individually
- [ ] Reference docs created and indexed
- [ ] No orphaned content (grep verification)
- [ ] PR reviewed by maintainer
