# Product Requirements Document: Two-Tier Learnings Architecture

**Version**: 1.1.0
**Status**: Draft
**Author**: Claude (via /plan-and-analyze)
**Date**: 2026-02-02
**Related Issues**: #137, #76
**Depends On**: PR #134 (Projen-Style Ownership)

---

> **Dependency Note**: This feature depends on PR #134 which establishes the `.claude/loa/` directory structure and magic marker system. Framework learnings files must include `_loa_managed` metadata for integrity verification. See Section 5.4 for marker integration requirements.

---

## 1. Problem Statement

### 1.1 Current State

Loa's Oracle system (`/oracle-analyze`) queries learnings from `grimoires/loa/` directories:
- `grimoires/loa/a2a/compound/learnings.json`
- `grimoires/loa/a2a/compound/patterns.json`
- `grimoires/loa/decisions.yaml`
- `grimoires/loa/feedback/*.yaml`

**The Problem**: These files are:
1. **Empty on fresh installs** - No learnings ship with the framework
2. **Gitignored in template** - `grimoires/` is excluded to keep template clean
3. **Project-specific only** - No inheritance of framework learnings

### 1.2 Impact

- New Loa users get an empty Oracle with no queryable knowledge
- Framework learnings from building Loa itself are not distributed
- The vision from #76 ("Loa should be its own oracle") is incomplete
- `/oracle-analyze` returns no results on fresh installs

### 1.3 Root Cause

The architecture conflates two types of learnings:
1. **Framework learnings** - Patterns discovered building Loa (should ship)
2. **Project learnings** - Patterns discovered in user's project (should accumulate)

Both currently live in `grimoires/` which is gitignored.

---

## 2. Goals & Success Metrics

### 2.1 Goals

| ID | Goal | Priority |
|----|------|----------|
| G-1 | Framework learnings ship with Loa and are queryable immediately | P0 |
| G-2 | Project learnings accumulate separately and persist across sessions | P0 |
| G-3 | Oracle queries both tiers and merges results intelligently | P0 |
| G-4 | `/update-loa` brings new framework learnings automatically | P1 |
| G-5 | Clear separation between framework and project knowledge | P1 |
| G-6 | Backwards compatible with existing grimoires structure | P1 |

### 2.2 Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Framework learnings on fresh install | ≥20 entries | Count in `.claude/loa/learnings/` |
| Oracle query success rate | 100% on fresh install | `/oracle-analyze` returns results |
| Query latency | <500ms | Time to merge both tiers |
| Update sync success | 100% | New learnings appear after `/update-loa` |

### 2.3 Non-Goals

- Automatic learning extraction (handled by `/retrospective`)
- Learning quality scoring (separate concern)
- Cross-project learning sharing beyond framework

---

## 3. User & Stakeholder Context

### 3.1 Primary Users

| Persona | Need | Current Pain |
|---------|------|--------------|
| New Loa User | Query best practices immediately | Empty Oracle, no results |
| Experienced User | Leverage both framework + project learnings | Only project learnings available |
| Framework Maintainer | Distribute learnings with updates | No mechanism exists |

### 3.2 User Journey

**Before (Current)**:
```
/mount → Empty grimoires/ → /oracle-analyze → "No results" → Frustration
```

**After (Proposed)**:
```
/mount → Framework learnings available → /oracle-analyze → Useful patterns → Success
         + Project learnings accumulate over time
```

---

## 4. Functional Requirements

### 4.1 Two-Tier Storage Architecture

#### Framework Learnings (Tier 1 - System Zone)

**Location**: `.claude/loa/learnings/`

```
.claude/loa/learnings/
├── index.json              # Manifest of all framework learnings
├── patterns.json           # Proven architectural patterns
├── anti-patterns.json      # What NOT to do (with rationale)
├── decisions.json          # Key architectural decisions
└── troubleshooting.json    # Common issues and solutions
```

**Characteristics**:
- Ships with Loa framework
- Read-only for projects (managed by framework)
- Updated via `/update-loa`
- Always available, never gitignored

#### Project Learnings (Tier 2 - State Zone)

**Location**: `grimoires/loa/` (existing structure)

```
grimoires/loa/
├── a2a/compound/
│   ├── learnings.json      # Project-specific learnings
│   └── patterns.json       # Project patterns from /retrospective
├── decisions.yaml          # Project architectural decisions
├── feedback/*.yaml         # Project feedback entries
└── memory/                 # Project memory (existing)
```

**Characteristics**:
- Accumulates through `/retrospective`, `/compound`
- Writable by project
- Gitignored in template (user decides)
- Project-specific knowledge

### 4.2 Oracle Query Behavior

```
Query("auth patterns")
    │
    ├─→ Search Tier 1 (Framework)
    │   └─→ .claude/loa/learnings/*.json
    │
    ├─→ Search Tier 2 (Project)
    │   └─→ grimoires/loa/**/*.{json,yaml}
    │
    └─→ Merge Results
        ├─→ Deduplicate by content hash
        ├─→ Apply source weights (framework=1.0, project=0.9)
        └─→ Return ranked results
```

### 4.3 Framework Learnings Content

Initial framework learnings to ship (curated from Loa development):

| Category | Examples | Count |
|----------|----------|-------|
| **Patterns** | Three-Zone Model, JIT Retrieval, Circuit Breaker | ~10 |
| **Anti-Patterns** | Arrow function closures, Hardcoded versions | ~8 |
| **Decisions** | Why grimoires/, Why skills architecture | ~10 |
| **Troubleshooting** | Common bash issues, Permission errors | ~12 |

**Total**: ~40 initial learnings

### 4.4 Script Updates

#### `loa-learnings-index.sh`

```bash
# New: Index both tiers
index_all() {
    index_framework_learnings  # Tier 1: .claude/loa/learnings/
    index_project_learnings    # Tier 2: grimoires/loa/
    merge_indices
}

# New: Query both tiers
query() {
    local framework_results=$(query_tier1 "$terms")
    local project_results=$(query_tier2 "$terms")
    merge_and_rank "$framework_results" "$project_results"
}
```

#### `anthropic-oracle.sh`

```bash
# Updated LOA_SOURCES to include framework tier
declare -A LOA_SOURCES=(
    # Tier 1: Framework (always present)
    ["framework_patterns"]=".claude/loa/learnings/patterns.json"
    ["framework_antipatterns"]=".claude/loa/learnings/anti-patterns.json"
    ["framework_decisions"]=".claude/loa/learnings/decisions.json"
    ["framework_troubleshooting"]=".claude/loa/learnings/troubleshooting.json"
    # Tier 2: Project (may be empty)
    ["project_learnings"]="grimoires/loa/a2a/compound/learnings.json"
    ["project_patterns"]="grimoires/loa/a2a/compound/patterns.json"
    ["project_decisions"]="grimoires/loa/decisions.yaml"
    ["project_feedback"]="grimoires/loa/feedback/*.yaml"
)
```

### 4.5 Update Flow

When `/update-loa` runs:

1. Pull new `.claude/loa/learnings/*.json` files
2. Preserve project learnings in `grimoires/` (never overwrite)
3. Rebuild merged index
4. Log new learnings count to NOTES.md

---

## 5. Technical & Non-Functional Requirements

### 5.1 Performance

| Requirement | Target |
|-------------|--------|
| Index build time | <2s for both tiers |
| Query latency | <500ms |
| Memory usage | <50MB for merged index |

### 5.2 Compatibility

| Requirement | Approach |
|-------------|----------|
| Backwards compatible | Project learnings structure unchanged |
| Existing grimoires/ | Continue to work as before |
| Empty grimoires/ | Framework learnings still available |

### 5.3 Schema

Framework learnings use existing `learnings.schema.json` with additions:

```json
{
  "tier": "framework|project",
  "source": "loa-core|project-retrospective|manual",
  "version_added": "1.15.0"
}
```

### 5.4 Marker System Integration (PR #134 Dependency)

Framework learnings files MUST integrate with PR #134's Projen-style ownership model:

#### 5.4.1 Required Metadata

All framework learnings JSON files must include `_loa_managed` metadata:

```json
{
  "_loa_managed": {
    "managed": true,
    "version": "1.15.1",
    "hash": "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  },
  "learnings": [...]
}
```

#### 5.4.2 Hash Generation

Use `marker-utils.sh` from PR #134 to generate SHA-256 hashes:

```bash
source .claude/scripts/marker-utils.sh
compute_hash .claude/loa/learnings/patterns.json
```

#### 5.4.3 Checksum Registration

Framework learnings files must be registered in `.claude/checksums.json`:

```json
{
  ".claude/loa/learnings/index.json": "sha256:...",
  ".claude/loa/learnings/patterns.json": "sha256:...",
  ".claude/loa/learnings/anti-patterns.json": "sha256:...",
  ".claude/loa/learnings/decisions.json": "sha256:...",
  ".claude/loa/learnings/troubleshooting.json": "sha256:..."
}
```

#### 5.4.4 Update Flow Integration

PR #134's `update.sh` automatically syncs `.claude/loa/` - no additional changes needed for the update mechanism.

---

## 6. Scope & Prioritization

### 6.1 MVP (Sprint 1)

| Task | Description |
|------|-------------|
| Create `.claude/loa/learnings/` structure | Directory and index.json |
| Seed initial framework learnings | ~40 curated entries |
| Update `loa-learnings-index.sh` | Query both tiers |
| Update `anthropic-oracle.sh` | Include framework paths |

### 6.2 Phase 2 (Sprint 2)

| Task | Description |
|------|-------------|
| `/update-loa` sync | Bring new framework learnings |
| Deduplication logic | Content hash comparison |
| Source weight configuration | `.loa.config.yaml` options |

### 6.3 Out of Scope

- Automatic promotion from project to framework tier
- Cross-project learning aggregation
- Learning quality scoring/ranking
- UI for browsing learnings

---

## 7. Risks & Dependencies

### 7.1 Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Framework learnings become stale | Medium | Medium | Version tagging, regular curation |
| Merge conflicts on update | Low | Low | Framework tier is append-only |
| Performance with large indices | Low | Medium | Lazy loading, caching |

### 7.2 Dependencies

| Dependency | Status | Notes |
|------------|--------|-------|
| **PR #134 (Projen-Style Ownership)** | ⏳ Required | Establishes `.claude/loa/` and marker system |
| PR #138 (Oracle bash fix) | ⏳ Recommended | Fixes exit code bug |
| Existing Oracle infrastructure | ✅ Ready | PR #89 merged |
| learnings.schema.json | ✅ Ready | Exists in .claude/schemas/ |
| /update-loa mechanism | ✅ Ready | update.sh exists |

**Merge Order**: PR #134 → PR #138 → This PR

---

## 8. Appendix

### A. Framework Learnings Categories

**Patterns** (to include):
- Three-Zone Model (System/State/App)
- JIT Retrieval for context efficiency
- Circuit Breaker for autonomous execution
- Managed Scaffolding (Projen-style)
- Two-Phase Review (Tech Lead + Security)
- Goal Traceability (G-IDs through sprints)
- Lossless Ledger Protocol
- Attention Budget enforcement
- Skill 3-level architecture

**Anti-Patterns** (to include):
- Arrow function closures causing memory leaks
- Hardcoded version fallbacks
- `((var++))` with `set -e` in bash
- Unbounded tool result accumulation
- Silent failure without status messages
- Mixing framework and project files
- Skipping security audit phase

**Decisions** (to include):
- Why grimoires/ for state (separation of concerns)
- Why skills use 3-level architecture (token efficiency)
- Why draft PRs only in Run Mode (safety)
- Why NOTES.md over database (portability)
- Why Sprint Ledger for global numbering
- Why ICE layer for git safety

**Troubleshooting** (to include):
- Bash 4+ requirement for associative arrays
- macOS default bash is 3.x
- yq vs jq output format differences
- Permission errors on scripts
- Git remote configuration issues
- Cache staleness symptoms

### B. Migration Path

1. **v1.15.1**: Ship framework learnings in `.claude/loa/learnings/`
2. **v1.15.1**: Update scripts to query both tiers
3. **v1.16.0**: Add `/update-loa` sync for new learnings
4. **Future**: Consider learning promotion workflow

### C. Appendix C: Goal Traceability

| Goal ID | Contributing Tasks |
|---------|-------------------|
| G-1 | Sprint 1: Tasks 1.1, 1.2 |
| G-2 | Already exists (grimoires/) |
| G-3 | Sprint 1: Tasks 1.3, 1.4 |
| G-4 | Sprint 2: Task 2.1 |
| G-5 | Sprint 1: All tasks |
| G-6 | Sprint 1: Task 1.4 (backwards compat) |

---

*PRD created via /plan-and-analyze for issue #137*
