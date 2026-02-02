# Software Design Document: Two-Tier Learnings Architecture

**Version**: 1.1.0
**Status**: Draft
**Author**: Claude (via /architect)
**Date**: 2026-02-02
**PRD Reference**: `docs/proposals/two-tier-learnings-prd.md`
**Related Issues**: #137, #76
**Depends On**: PR #134 (Projen-Style Ownership)

---

> **Dependency Note**: This design depends on PR #134 which establishes:
> - The `.claude/loa/` directory structure
> - Magic marker system with SHA-256 integrity verification
> - `marker-utils.sh` for hash generation
> - Checksum registration in `.claude/checksums.json`
>
> All framework learnings files must include `_loa_managed` metadata per PR #134's managed scaffolding model.

---

## 1. Executive Summary

This document describes the technical architecture for implementing a Two-Tier Learnings system that separates framework knowledge (shipped with Loa) from project knowledge (accumulated during development). The design leverages existing infrastructure while adding a new storage tier in the System Zone.

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Framework learnings location | `.claude/loa/learnings/` | Aligns with Three-Zone Model (System Zone) |
| File format | JSON with `_loa_managed` | PR #134 marker system for integrity |
| Query strategy | Parallel search + merge | <500ms latency target |
| Deduplication | SHA-256 content hash | Prevents duplicate results across tiers |
| Weight system | Framework=1.0, Project=0.9 | Framework knowledge is canonical |
| Integrity verification | PR #134 marker system | Hash verification on update |

---

## 2. System Architecture

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Oracle Query Layer                          │
│                    (anthropic-oracle.sh / /oracle-analyze)          │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      Learnings Index Layer                          │
│                      (loa-learnings-index.sh)                       │
│  ┌─────────────────────────┐   ┌─────────────────────────────────┐  │
│  │   Framework Index       │   │      Project Index              │  │
│  │   (read-only)           │   │      (read-write)               │  │
│  └─────────────────────────┘   └─────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
          │                                      │
          ▼                                      ▼
┌─────────────────────────┐        ┌─────────────────────────────────┐
│   TIER 1: Framework     │        │     TIER 2: Project             │
│   (System Zone)         │        │     (State Zone)                │
│                         │        │                                 │
│ .claude/loa/learnings/  │        │ grimoires/loa/                  │
│ ├── index.json          │        │ ├── a2a/compound/               │
│ ├── patterns.json       │        │ │   ├── learnings.json          │
│ ├── anti-patterns.json  │        │ │   └── patterns.json           │
│ ├── decisions.json      │        │ ├── decisions.yaml              │
│ └── troubleshooting.json│        │ └── feedback/*.yaml             │
└─────────────────────────┘        └─────────────────────────────────┘
          │                                      │
          │         Ships with Loa               │      Gitignored
          │         Read-only                    │      Project-specific
          └──────────────────────────────────────┘
```

### 2.2 Data Flow

```
                    ┌─────────────┐
                    │  /oracle    │
                    │  -analyze   │
                    └──────┬──────┘
                           │
                           ▼
                    ┌─────────────┐
                    │   Query     │
                    │   Parser    │
                    └──────┬──────┘
                           │
              ┌────────────┴────────────┐
              │                         │
              ▼                         ▼
       ┌─────────────┐          ┌─────────────┐
       │  Search     │          │  Search     │
       │  Tier 1     │          │  Tier 2     │
       │  (parallel) │          │  (parallel) │
       └──────┬──────┘          └──────┬──────┘
              │                         │
              └────────────┬────────────┘
                           │
                           ▼
                    ┌─────────────┐
                    │   Merge &   │
                    │   Dedupe    │
                    └──────┬──────┘
                           │
                           ▼
                    ┌─────────────┐
                    │   Apply     │
                    │   Weights   │
                    └──────┬──────┘
                           │
                           ▼
                    ┌─────────────┐
                    │   Return    │
                    │   Results   │
                    └─────────────┘
```

---

## 3. Component Design

### 3.1 Framework Learnings Store

**Location**: `.claude/loa/learnings/`

#### 3.1.1 Directory Structure

```
.claude/loa/learnings/
├── index.json              # Manifest with metadata
├── patterns.json           # Proven architectural patterns
├── anti-patterns.json      # Things to avoid
├── decisions.json          # Architectural decision records
└── troubleshooting.json    # Common issues and solutions
```

#### 3.1.2 Index Manifest Schema

**Note**: All framework learnings files must include `_loa_managed` metadata per PR #134's marker system.

```json
{
  "_loa_managed": {
    "managed": true,
    "version": "1.15.1",
    "hash": "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  },
  "$schema": "../schemas/learnings.schema.json",
  "version": "1.0",
  "tier": "framework",
  "loa_version": "1.15.1",
  "last_updated": "2026-02-02T12:00:00Z",
  "counts": {
    "patterns": 10,
    "anti_patterns": 8,
    "decisions": 10,
    "troubleshooting": 12
  },
  "total": 40,
  "files": [
    "patterns.json",
    "anti-patterns.json",
    "decisions.json",
    "troubleshooting.json"
  ]
}
```

The `_loa_managed.hash` is computed using `marker-utils.sh compute_hash` from PR #134, excluding the `_loa_managed` block itself from the hash calculation.

#### 3.1.3 Learning Entry Schema Extension

Extend existing `learnings.schema.json` with tier information:

```json
{
  "tier": {
    "type": "string",
    "enum": ["framework", "project"],
    "description": "Which tier this learning belongs to"
  },
  "version_added": {
    "type": "string",
    "pattern": "^[0-9]+\\.[0-9]+\\.[0-9]+$",
    "description": "Loa version when this learning was added"
  },
  "source_origin": {
    "type": "string",
    "enum": ["loa-core", "community", "project-promoted"],
    "description": "Where this learning originated"
  }
}
```

### 3.2 Learnings Index Script Updates

**File**: `.claude/scripts/loa-learnings-index.sh`

#### 3.2.1 New Functions

```bash
# Constants for tier paths
FRAMEWORK_LEARNINGS_DIR="$PROJECT_ROOT/.claude/loa/learnings"
PROJECT_LEARNINGS_DIR="$PROJECT_ROOT/grimoires/loa"

# Index framework learnings (Tier 1)
index_framework_learnings() {
    local count=0
    local output="[]"
    
    if [[ ! -d "$FRAMEWORK_LEARNINGS_DIR" ]]; then
        echo "0"
        return
    fi
    
    for file in "$FRAMEWORK_LEARNINGS_DIR"/*.json; do
        [[ -f "$file" ]] || continue
        [[ "$(basename "$file")" == "index.json" ]] && continue
        
        # Extract learnings and tag with tier=framework
        local entries
        entries=$(jq --arg tier "framework" '
            .learnings // [] | 
            map(. + {tier: $tier, source_file: input_filename})
        ' "$file" 2>/dev/null)
        
        output=$(echo "$output" "$entries" | jq -s 'add')
        count=$((count + $(echo "$entries" | jq 'length')))
    done
    
    echo "$output" > "$INDEX_DIR/framework.idx"
    echo "$count"
}

# Query both tiers and merge results
query_both_tiers() {
    local terms="$1"
    local limit="${2:-10}"
    
    # Search Tier 1 (Framework) - always present
    local framework_results
    framework_results=$(search_index "$INDEX_DIR/framework.idx" "$terms")
    
    # Search Tier 2 (Project) - may be empty
    local project_results
    project_results=$(search_index "$INDEX_DIR/project.idx" "$terms")
    
    # Merge, dedupe, and apply weights
    merge_and_rank "$framework_results" "$project_results" "$limit"
}

# Merge results with deduplication and weighting
merge_and_rank() {
    local tier1_results="$1"
    local tier2_results="$2"
    local limit="$3"
    
    # Combine results
    local combined
    combined=$(echo "$tier1_results" "$tier2_results" | jq -s 'add // []')
    
    # Deduplicate by content hash (title + solution)
    # Apply weights: framework=1.0, project=0.9
    echo "$combined" | jq --argjson limit "$limit" '
        # Add content hash for deduplication
        map(. + {
            content_hash: ((.title // "") + (.solution // "")) | @base64,
            weight: (if .tier == "framework" then 1.0 else 0.9 end)
        }) |
        # Group by hash and take highest weighted
        group_by(.content_hash) |
        map(sort_by(-.weight) | first) |
        # Sort by relevance score * weight
        sort_by(-(.relevance_score // 1) * .weight) |
        # Limit results
        .[:$limit]
    '
}
```

#### 3.2.2 Updated Index Command

```bash
# Build index for both tiers
build_index() {
    init_index_dir
    
    echo -e "${BOLD}${CYAN}Building Learnings Index${NC}"
    echo "─────────────────────────────────────────"
    echo ""
    
    # Index Tier 1: Framework
    echo -n "  Indexing framework learnings... "
    local framework_count
    framework_count=$(index_framework_learnings)
    echo -e "${GREEN}$framework_count entries${NC}"
    
    # Index Tier 2: Project (existing function)
    echo -n "  Indexing project learnings... "
    local project_count
    project_count=$(index_project_learnings)
    echo -e "${GREEN}$project_count entries${NC}"
    
    # Index skills (existing)
    echo -n "  Indexing skills... "
    local skills_count
    skills_count=$(index_skills)
    echo -e "${GREEN}$skills_count entries${NC}"
    
    # Save metadata
    save_index_metadata "$framework_count" "$project_count" "$skills_count"
    
    echo ""
    echo -e "Total: ${GREEN}$((framework_count + project_count + skills_count))${NC} entries"
}
```

### 3.3 Oracle Script Updates

**File**: `.claude/scripts/anthropic-oracle.sh`

#### 3.3.1 Updated LOA_SOURCES

```bash
# Loa sources for compound learnings - TWO TIER ARCHITECTURE
declare -A LOA_SOURCES=(
    # Tier 1: Framework learnings (always present, ships with Loa)
    ["framework_patterns"]=".claude/loa/learnings/patterns.json"
    ["framework_antipatterns"]=".claude/loa/learnings/anti-patterns.json"
    ["framework_decisions"]=".claude/loa/learnings/decisions.json"
    ["framework_troubleshooting"]=".claude/loa/learnings/troubleshooting.json"
    
    # Tier 2: Project learnings (may be empty, gitignored)
    ["project_learnings"]="grimoires/loa/a2a/compound/learnings.json"
    ["project_patterns"]="grimoires/loa/a2a/compound/patterns.json"
    ["project_decisions"]="grimoires/loa/decisions.yaml"
    ["project_feedback"]="grimoires/loa/feedback/*.yaml"
    
    # Skills (always indexed)
    ["skills"]=".claude/skills/**/*.md"
)

# Source weights for ranking
declare -A LOA_SOURCE_WEIGHTS=(
    ["framework_patterns"]="1.0"
    ["framework_antipatterns"]="1.0"
    ["framework_decisions"]="1.0"
    ["framework_troubleshooting"]="1.0"
    ["project_learnings"]="0.9"
    ["project_patterns"]="0.9"
    ["project_decisions"]="0.9"
    ["project_feedback"]="0.8"
    ["skills"]="0.95"
)
```

### 3.4 Update Script Integration

**File**: `.claude/scripts/update.sh`

The existing update mechanism already syncs `.claude/` from upstream. Framework learnings in `.claude/loa/learnings/` will automatically sync with `/update-loa`.

#### 3.4.1 Post-Update Hook

Add to update completion:

```bash
# After sync_zones completes
post_update_learnings() {
    # Rebuild index to include new framework learnings
    if [[ -x "$SCRIPT_DIR/loa-learnings-index.sh" ]]; then
        log "Rebuilding learnings index..."
        "$SCRIPT_DIR/loa-learnings-index.sh" index --quiet
        
        # Report new learnings count
        local new_count
        new_count=$(jq '.counts.framework // 0' "$INDEX_DIR/index.json" 2>/dev/null)
        log "Framework learnings: $new_count entries"
    fi
}
```

---

## 4. Data Architecture

### 4.1 Learning Entry Format

All learnings follow the existing `learnings.schema.json` with tier extensions:

```json
{
  "id": "PAT-001",
  "tier": "framework",
  "version_added": "1.15.1",
  "type": "pattern",
  "title": "Three-Zone Model for File Organization",
  "trigger": "When organizing files in a Loa-managed project",
  "solution": "Separate files into System Zone (.claude/), State Zone (grimoires/), and App Zone (src/). System Zone is framework-managed and read-only. State Zone is project memory. App Zone is developer-owned code.",
  "context": "Discovered during Loa v1.1.0 managed scaffolding design",
  "verified": true,
  "quality_gates": {
    "discovery_depth": 9,
    "reusability": 10,
    "trigger_clarity": 9,
    "verification": 10
  },
  "tags": ["architecture", "file-organization", "zones"],
  "status": "active",
  "source_origin": "loa-core"
}
```

### 4.2 File Organization by Category

| File | Content Type | Estimated Count |
|------|--------------|-----------------|
| `patterns.json` | Proven architectural patterns | 10 |
| `anti-patterns.json` | Things to avoid with rationale | 8 |
| `decisions.json` | Architectural decision records | 10 |
| `troubleshooting.json` | Common issues and solutions | 12 |

### 4.3 Content Hash Algorithm

For deduplication across tiers:

```python
import hashlib
import json

def content_hash(learning: dict) -> str:
    """Generate hash for deduplication."""
    content = json.dumps({
        "title": learning.get("title", ""),
        "solution": learning.get("solution", "")
    }, sort_keys=True)
    return hashlib.sha256(content.encode()).hexdigest()[:16]
```

---

## 5. API Design

### 5.1 CLI Interface

No new commands - extends existing scripts:

```bash
# Index both tiers (updated behavior)
loa-learnings-index.sh index

# Query with tier filtering
loa-learnings-index.sh query "circuit breaker" --tier framework
loa-learnings-index.sh query "auth" --tier project
loa-learnings-index.sh query "patterns" --tier all  # default

# Show status with tier breakdown
loa-learnings-index.sh status
# Output:
# Learnings Index Status
# ─────────────────────────────────────────
#   Framework (Tier 1): 40 entries
#   Project (Tier 2):   12 entries
#   Skills:             45 entries
#   Total:              97 entries
```

### 5.2 Query Options

| Option | Description | Default |
|--------|-------------|---------|
| `--tier <framework\|project\|all>` | Filter by tier | `all` |
| `--min-weight <0.0-1.0>` | Minimum source weight | `0.0` |
| `--include-skills` | Include skill content | `true` |

---

## 6. Security Architecture

### 6.1 File Permissions

| Path | Permission | Rationale |
|------|------------|-----------|
| `.claude/loa/learnings/` | 755 (dir), 644 (files) | Framework-managed, read-only for users |
| `grimoires/loa/` | 755 (dir), 644 (files) | User-writable project learnings |
| Index cache | 700 (dir), 600 (files) | Private to user |

### 6.2 Content Validation

All learnings validated against `learnings.schema.json`:
- On index build
- On query result return
- On `/update-loa` sync

---

## 7. Integration Points

### 7.1 Existing Scripts

| Script | Integration |
|--------|-------------|
| `loa-learnings-index.sh` | Primary implementation |
| `anthropic-oracle.sh` | Updated LOA_SOURCES paths |
| `update.sh` | Syncs framework learnings |
| `mount-loa.sh` | Framework learnings included automatically |

### 7.2 Commands

| Command | Behavior Change |
|---------|-----------------|
| `/oracle-analyze` | Queries both tiers |
| `/update-loa` | Brings new framework learnings |
| `/retrospective` | Only writes to project tier |
| `/compound` | Only writes to project tier |

---

## 8. Scalability & Performance

### 8.1 Performance Targets

| Operation | Target | Approach |
|-----------|--------|----------|
| Index build | <2s | Parallel file reading |
| Query | <500ms | Pre-built indices, parallel search |
| Memory | <50MB | Stream processing for large files |

### 8.2 Caching Strategy

```
~/.loa/cache/oracle/loa/
├── framework.idx           # Pre-built framework index
├── project.idx             # Pre-built project index
├── skills.idx              # Pre-built skills index
├── index.json              # Combined metadata
└── query-cache/            # Query result cache (5min TTL)
    └── <hash>.json
```

---

## 9. Deployment Architecture

### 9.1 Release Process

1. **Framework Learnings Curation**
   - Maintainers curate learnings in `.claude/loa/learnings/`
   - Each learning tagged with `version_added`
   - PR review required for new learnings

2. **Version Bundling**
   - Learnings included in Loa releases
   - `index.json` updated with counts and `loa_version`
   - Checksums added to `.claude/checksums.json`

3. **User Distribution**
   - `/mount` includes framework learnings automatically
   - `/update-loa` syncs new learnings

### 9.2 File Checksums

Framework learnings added to integrity verification:

```json
{
  ".claude/loa/learnings/index.json": "sha256:...",
  ".claude/loa/learnings/patterns.json": "sha256:...",
  ".claude/loa/learnings/anti-patterns.json": "sha256:...",
  ".claude/loa/learnings/decisions.json": "sha256:...",
  ".claude/loa/learnings/troubleshooting.json": "sha256:..."
}
```

---

## 10. Development Workflow

### 10.1 Adding Framework Learnings

```bash
# 1. Edit the appropriate file
vim .claude/loa/learnings/patterns.json

# 2. Validate against schema
.claude/scripts/schema-validator.sh .claude/loa/learnings/patterns.json

# 3. Update index.json counts
jq '.counts.patterns = (.counts.patterns + 1) | .total = (.total + 1)' \
  .claude/loa/learnings/index.json > tmp && mv tmp .claude/loa/learnings/index.json

# 4. Update checksums
.claude/scripts/update-checksums.sh

# 5. Commit with conventional format
git add .claude/loa/learnings/
git commit -m "feat(learnings): add three-zone model pattern"
```

### 10.2 Testing

```bash
# Test index build
.claude/scripts/loa-learnings-index.sh index

# Test query
.claude/scripts/loa-learnings-index.sh query "three zone"

# Verify tier separation
.claude/scripts/loa-learnings-index.sh query "pattern" --tier framework
.claude/scripts/loa-learnings-index.sh query "pattern" --tier project
```

---

## 11. Technical Risks & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Large index size | Low | Medium | Lazy loading, pagination |
| Schema evolution | Medium | Low | Backwards-compatible extensions only |
| Stale framework learnings | Medium | Medium | Version tagging, deprecation flags |
| Query performance degradation | Low | Medium | Index caching, parallel search |

---

## 12. Future Considerations

### 12.1 Potential Enhancements

1. **Learning Promotion**: Mechanism to promote project learnings to framework tier
2. **Learning Versioning**: Track learning changes across Loa versions
3. **Semantic Search**: QMD integration for better relevance ranking
4. **Learning Analytics**: Track which learnings are most queried/applied

### 12.2 Technical Debt

- Current grep-based search could be replaced with proper inverted index
- Consider SQLite for index storage if performance becomes issue
- Unified schema for both JSON and YAML formats

---

## 13. Appendix

### A. Initial Framework Learnings Categories

See PRD Appendix A for full list of learnings to seed.

### B. Schema Extensions

Full schema extension diff available in implementation PR.

### C. Migration Checklist

- [ ] Create `.claude/loa/learnings/` directory structure
- [ ] Seed initial ~40 learnings across 4 files
- [ ] Update `loa-learnings-index.sh` with tier support
- [ ] Update `anthropic-oracle.sh` LOA_SOURCES
- [ ] Add checksums for new files
- [ ] Update CLAUDE.md documentation
- [ ] Test on fresh `/mount`

---

*SDD created via /architect for Two-Tier Learnings Architecture*
