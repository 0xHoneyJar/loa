# Sprint Plan: Two-Tier Learnings Architecture

**PRD**: [two-tier-learnings-prd.md](two-tier-learnings-prd.md) (v1.1.0)
**SDD**: [two-tier-learnings-sdd.md](two-tier-learnings-sdd.md) (v1.1.0)
**Issues**: [#137](https://github.com/0xHoneyJar/loa/issues/137), [#76](https://github.com/0xHoneyJar/loa/issues/76)
**Depends On**: [PR #134](https://github.com/0xHoneyJar/loa/pull/134) (Projen-Style Ownership)
**Cycle**: cycle-009
**Date**: 2026-02-02
**Status**: In Progress

---

> **Dependency Note**: This sprint plan requires PR #134 to be merged first. PR #134 provides:
> - `.claude/loa/` directory structure
> - `marker-utils.sh` for hash generation
> - Magic marker system (`_loa_managed` metadata)
> - Checksum registration infrastructure
>
> **Merge Order**: PR #134 → PR #138 → This implementation

---

## Overview

| Attribute | Value |
|-----------|-------|
| Total Sprints | 2 |
| Total Tasks | 8 |
| MVP Scope | Sprint 1 (5 tasks) |
| Phase 2 Scope | Sprint 2 (3 tasks) |
| Target Version | v1.15.1 |
| Global Sprint IDs | 26-27 |

### Priority Breakdown

| Priority | Sprints | Tasks | Goal Coverage |
|----------|---------|-------|---------------|
| **P0 (MVP)** | 1 | 5 | G-1, G-3, G-5, G-6 |
| **P1** | 2 | 3 | G-4 |

### Key Architectural Decisions (from SDD)

1. **Framework learnings in `.claude/loa/learnings/`** - System Zone location for shipped knowledge
2. **JSON format with `_loa_managed`** - PR #134 marker system for integrity verification
3. **Parallel search + merge** - Query both tiers concurrently, <500ms target
4. **SHA-256 content hash** - Deduplication across tiers
5. **Weight system** - Framework=1.0, Project=0.9 for ranking
6. **Checksum registration** - Files registered in `.claude/checksums.json` per PR #134

---

## Sprint 1: Core Infrastructure (MVP)

**Global ID**: sprint-26
**Goal**: Create framework learnings storage, seed initial content, and update scripts to query both tiers
**Priority**: P0 (MVP)
**Tasks**: 5

### T1.1: Create framework learnings directory structure

**Description**: Create `.claude/loa/learnings/` directory with index.json manifest and empty JSON files for each category. All files must include `_loa_managed` metadata per PR #134's marker system.

**Acceptance Criteria**:
- [ ] `.claude/loa/learnings/` directory created
- [ ] `index.json` manifest created with metadata (version, tier, loa_version, counts)
- [ ] `patterns.json` created with empty learnings array
- [ ] `anti-patterns.json` created with empty learnings array
- [ ] `decisions.json` created with empty learnings array
- [ ] `troubleshooting.json` created with empty learnings array
- [ ] **All files include `_loa_managed` metadata block** (PR #134 requirement)
- [ ] **Hash values generated using `marker-utils.sh compute_hash`** (PR #134)
- [ ] **All files registered in `.claude/checksums.json`** (PR #134)
- [ ] All files validate against extended learnings schema
- [ ] Directory structure matches SDD Section 3.1

**`_loa_managed` Format** (required for each file):
```json
{
  "_loa_managed": {
    "managed": true,
    "version": "1.15.1",
    "hash": "sha256:..."
  },
  "learnings": [...]
}
```

**Files**:
- Create: `.claude/loa/learnings/index.json`
- Create: `.claude/loa/learnings/patterns.json`
- Create: `.claude/loa/learnings/anti-patterns.json`
- Create: `.claude/loa/learnings/decisions.json`
- Create: `.claude/loa/learnings/troubleshooting.json`
- Modify: `.claude/checksums.json` (register new files)

**Testing**:
```bash
# Verify directory structure
ls -la .claude/loa/learnings/

# Validate JSON files
for f in .claude/loa/learnings/*.json; do jq '.' "$f" > /dev/null && echo "OK: $f"; done

# Verify _loa_managed metadata present (PR #134)
for f in .claude/loa/learnings/*.json; do
  jq -e '._loa_managed.managed == true' "$f" > /dev/null && echo "OK: $f has marker"
done

# Verify hash integrity (PR #134)
source .claude/scripts/marker-utils.sh
for f in .claude/loa/learnings/*.json; do
  verify_hash "$f" && echo "OK: $f hash valid"
done
```

**Dependencies**: PR #134 (marker-utils.sh, checksums.json infrastructure)

---

### T1.2: Extend learnings.schema.json with tier fields

**Description**: Add tier, version_added, and source_origin fields to the learnings schema.

**Acceptance Criteria**:
- [ ] `tier` field added: enum ["framework", "project"]
- [ ] `version_added` field added: semver pattern string
- [ ] `source_origin` field added: enum ["loa-core", "community", "project-retrospective", "manual"]
- [ ] All fields optional for backwards compatibility
- [ ] Schema validates existing project learnings (no breaking changes)
- [ ] Schema documentation updated

**File**: `.claude/schemas/learnings.schema.json`

**Testing**:
```bash
# Validate existing learnings still pass
.claude/scripts/schema-validator.sh grimoires/loa/a2a/compound/learnings.json learnings
# Validate new framework learnings
.claude/scripts/schema-validator.sh .claude/loa/learnings/patterns.json learnings
```

**Dependencies**: T1.1

---

### T1.3: Seed initial framework learnings (~40 entries)

**Description**: Curate and populate initial framework learnings from Loa development experience. Content derived from PRD Appendix A.

**Acceptance Criteria**:
- [ ] `patterns.json` populated with ~10 proven architectural patterns
- [ ] `anti-patterns.json` populated with ~8 things to avoid
- [ ] `decisions.json` populated with ~10 architectural decision records
- [ ] `troubleshooting.json` populated with ~12 common issues and solutions
- [ ] Total count ≥40 entries
- [ ] All entries have: id, tier="framework", version_added, type, title, trigger, solution
- [ ] All entries have quality_gates with scores ≥7 in all categories
- [ ] `index.json` counts updated to reflect actual content

**Content Sources** (from PRD Appendix A):

**Patterns**:
- Three-Zone Model (System/State/App)
- JIT Retrieval for context efficiency
- Circuit Breaker for autonomous execution
- Managed Scaffolding (Projen-style)
- Two-Phase Review (Tech Lead + Security)
- Goal Traceability (G-IDs through sprints)
- Lossless Ledger Protocol
- Attention Budget enforcement
- Skill 3-level architecture
- Two-Tier Learnings Architecture

**Anti-Patterns**:
- Arrow function closures causing memory leaks
- Hardcoded version fallbacks
- `((var++))` with `set -e` in bash
- Unbounded tool result accumulation
- Silent failure without status messages
- Mixing framework and project files
- Skipping security audit phase
- Improper gitignore patterns for grimoires

**Decisions**:
- Why grimoires/ for state (separation of concerns)
- Why skills use 3-level architecture (token efficiency)
- Why draft PRs only in Run Mode (safety)
- Why NOTES.md over database (portability)
- Why Sprint Ledger for global numbering
- Why ICE layer for git safety
- Why `.claude/` not `.loa/` for System Zone
- Why JSON for learnings (not YAML)
- Why SHA-256 for content hashing
- Why weight system for multi-tier search

**Troubleshooting**:
- Bash 4+ requirement for associative arrays
- macOS default bash is 3.x
- yq vs jq output format differences
- Permission errors on scripts
- Git remote configuration issues
- Cache staleness symptoms
- `((var++))` exit code 1 with set -e
- Empty grimoires on fresh install
- Oracle returns no results on new project
- Symlink issues on Windows
- Checksum verification failures
- Skill not discovered by Claude Code

**Files**:
- Modify: `.claude/loa/learnings/patterns.json`
- Modify: `.claude/loa/learnings/anti-patterns.json`
- Modify: `.claude/loa/learnings/decisions.json`
- Modify: `.claude/loa/learnings/troubleshooting.json`
- Modify: `.claude/loa/learnings/index.json`

**Dependencies**: T1.1, T1.2

---

### T1.4: Update loa-learnings-index.sh for two-tier indexing

**Description**: Modify the learnings index script to index both framework (Tier 1) and project (Tier 2) learnings with proper merge and deduplication.

**Acceptance Criteria**:
- [ ] `FRAMEWORK_LEARNINGS_DIR` constant defined pointing to `.claude/loa/learnings`
- [ ] `index_framework_learnings()` function implemented
- [ ] `index_project_learnings()` function updated (existing)
- [ ] `query_both_tiers()` function implemented with parallel search
- [ ] `merge_and_rank()` function implemented with:
  - SHA-256 content hash for deduplication
  - Weight application (framework=1.0, project=0.9)
  - Sorted by relevance_score * weight
- [ ] `build_index()` indexes both tiers and reports counts
- [ ] `show_status()` shows tier breakdown (Framework: X, Project: Y)
- [ ] `--tier` flag added: framework|project|all (default: all)
- [ ] Graceful handling when project tier is empty
- [ ] Performance target: <500ms for query operations

**File**: `.claude/scripts/loa-learnings-index.sh`

**Testing**:
```bash
# Build index for both tiers
.claude/scripts/loa-learnings-index.sh index
# Query with tier filter
.claude/scripts/loa-learnings-index.sh query "zone model" --tier framework
.claude/scripts/loa-learnings-index.sh query "auth" --tier all
# Check status shows both tiers
.claude/scripts/loa-learnings-index.sh status
```

**Dependencies**: T1.1, T1.3

---

### T1.5: Update anthropic-oracle.sh with framework sources

**Description**: Add framework learnings paths to LOA_SOURCES and implement source weights.

**Acceptance Criteria**:
- [ ] `LOA_SOURCES` array includes Tier 1 framework paths:
  - `framework_patterns` → `.claude/loa/learnings/patterns.json`
  - `framework_antipatterns` → `.claude/loa/learnings/anti-patterns.json`
  - `framework_decisions` → `.claude/loa/learnings/decisions.json`
  - `framework_troubleshooting` → `.claude/loa/learnings/troubleshooting.json`
- [ ] `LOA_SOURCES` retains Tier 2 project paths (existing)
- [ ] `LOA_SOURCE_WEIGHTS` array added with weights per source
- [ ] `query_loa_sources()` applies weights to results
- [ ] `/oracle-analyze --scope loa` queries both tiers
- [ ] Graceful handling when Tier 2 paths don't exist
- [ ] Framework sources always present (never fail)

**File**: `.claude/scripts/anthropic-oracle.sh`

**Testing**:
```bash
# Query should return framework results even on fresh install
.claude/scripts/anthropic-oracle.sh query "circuit breaker" --scope loa
# Verify both tiers searched
.claude/scripts/anthropic-oracle.sh query "zone" --scope all --verbose
```

**Dependencies**: T1.1, T1.3

---

## Sprint 2: Integration & Polish

**Global ID**: sprint-27
**Goal**: Integrate with update flow, add configuration options, and document the architecture
**Priority**: P1
**Tasks**: 3

### T2.1: Integrate framework learnings with update.sh

**Description**: Ensure `/update-loa` brings new framework learnings and rebuilds the merged index.

**Acceptance Criteria**:
- [ ] Framework learnings synced as part of `.claude/` zone sync
- [ ] `post_update_learnings()` function added to rebuild index after update
- [ ] New learnings count logged to user
- [ ] Project learnings in `grimoires/` never touched by update
- [ ] Index rebuilt automatically after sync
- [ ] Works with both standard and submodule modes

**File**: `.claude/scripts/update.sh`

**Testing**:
```bash
# Simulate update and verify learnings synced
.claude/scripts/update.sh --dry-run
# After actual update, check index
.claude/scripts/loa-learnings-index.sh status
```

**Dependencies**: T1.4

---

### T2.2: Add configuration options to .loa.config.yaml

**Description**: Add learnings tier configuration options for weights and filtering.

**Acceptance Criteria**:
- [ ] `learnings.tiers.framework.weight` configurable (default: 1.0)
- [ ] `learnings.tiers.project.weight` configurable (default: 0.9)
- [ ] `learnings.tiers.framework.enabled` configurable (default: true)
- [ ] `learnings.tiers.project.enabled` configurable (default: true)
- [ ] `learnings.query.default_tier` configurable (default: "all")
- [ ] `learnings.query.max_results` configurable (default: 10)
- [ ] Config validated against schema
- [ ] Example config documented in comments

**Files**:
- Update: `.loa.config.yaml` template
- Update: `.claude/scripts/loa-learnings-index.sh` to read config

**Config Schema**:
```yaml
learnings:
  tiers:
    framework:
      enabled: true
      weight: 1.0
    project:
      enabled: true
      weight: 0.9
  query:
    default_tier: all  # framework | project | all
    max_results: 10
```

**Dependencies**: T1.4

---

### T2.3: Update documentation

**Description**: Document the Two-Tier Learnings Architecture in CLAUDE.md and related files.

**Acceptance Criteria**:
- [ ] CLAUDE.md Oracle section updated with two-tier architecture
- [ ] Framework learnings location documented
- [ ] Query tier options documented
- [ ] Weight system explained
- [ ] `.loa.config.yaml` learnings options documented
- [ ] Migration notes for existing projects
- [ ] Troubleshooting section updated with "empty learnings" resolution

**Files**:
- Update: `CLAUDE.md`

**Dependencies**: T1.5, T2.2

---

## Appendix A: Sprint Summary

| Sprint | ID | Tasks | Priority | Goal |
|--------|-----|-------|----------|------|
| Sprint 1: Core Infrastructure | 26 | 5 | P0 | Framework storage + seeding + script updates |
| Sprint 2: Integration & Polish | 27 | 3 | P1 | Update flow + config + documentation |

**Total**: 8 tasks

---

## Appendix B: Task Dependencies

```
EXTERNAL DEPENDENCIES (must be merged first)
├── PR #134 (Projen-Style Ownership) ──────────────────┐
│   └── Provides: marker-utils.sh, checksums.json,     │
│       .claude/loa/ directory, _loa_managed system    │
└── PR #138 (Oracle bash fix) ─────────────────────────┤
    └── Provides: Fixed exit code behavior             │
                                                       │
Sprint 1 (Core Infrastructure)                         │
├── T1.1 (directory structure) ◄── PR #134 ────────────┤
├── T1.2 (schema extension) ◄── T1.1                   │
├── T1.3 (seed learnings) ◄── T1.1, T1.2               │
├── T1.4 (loa-learnings-index.sh) ◄── T1.1, T1.3       │
└── T1.5 (anthropic-oracle.sh) ◄── T1.1, T1.3          │
                                                        │
Sprint 2 (Integration & Polish)                         │
├── T2.1 (update.sh integration) ◄── T1.4              │
├── T2.2 (config options) ◄── T1.4                     │
└── T2.3 (documentation) ◄── T1.5, T2.2 ◄──────────────┘
```

---

## Appendix C: Goal Traceability

| Goal | Description | Contributing Tasks |
|------|-------------|-------------------|
| G-1 | Framework learnings ship with Loa | T1.1, T1.2, T1.3 |
| G-2 | Project learnings accumulate separately | Already exists (grimoires/) |
| G-3 | Oracle queries both tiers | T1.4, T1.5 |
| G-4 | `/update-loa` brings new learnings | T2.1 |
| G-5 | Clear separation between tiers | T1.1, T1.4, T2.3 |
| G-6 | Backwards compatible | T1.2, T1.4, T1.5 |

---

## Appendix D: E2E Validation (Final Sprint Checklist)

**Task**: Validate all PRD goals achieved

| Goal | Validation Method | Pass Criteria |
|------|------------------|---------------|
| G-1 | Count framework learnings | ≥40 entries in `.claude/loa/learnings/` |
| G-2 | Check project tier | `grimoires/loa/` structure unchanged |
| G-3 | Query on fresh install | `/oracle-analyze` returns framework results |
| G-3 | Query performance | <500ms for merged query |
| G-4 | Update sync test | New learnings appear after `/update-loa` |
| G-5 | Tier inspection | Clear tier labels in index status |
| G-6 | Backwards compat | Existing project learnings still queryable |

---

## Appendix E: Risk Mitigation

| Risk | Mitigation | Owner |
|------|------------|-------|
| Framework learnings become stale | Version tagging, regular curation | T1.3 |
| Large index performance | Lazy loading, caching, parallel search | T1.4 |
| Schema breaking changes | All new fields optional | T1.2 |
| Weight confusion | Clear documentation, sensible defaults | T2.3 |

---

*Sprint plan created via /sprint-plan for Two-Tier Learnings Architecture*
