# Research: Framework Learning Architecture Compatibility Analysis

**Date**: 2026-02-02
**Author**: Claude (via /plan-and-analyze)
**Status**: Draft for Review
**Related PRs**: #134 (Projen-Style Ownership), #139 (Two-Tier Learnings)
**Related Issues**: #137, #76, #75, #74, #48, #23

---

## Executive Summary

This research document analyzes the compatibility between PR #134 (Projen-Style Ownership) and PR #139 (Two-Tier Learnings Architecture), examining how framework-level learnings should be structured within the managed scaffolding paradigm.

**Key Finding**: PR #139's proposed location (`.claude/loa/learnings/`) aligns well with PR #134's architecture, but requires integration with the magic marker system and consideration of the `@` import pattern for CLAUDE.md instructions about learnings.

---

## 1. Context: The Learning Ecosystem in Loa

### 1.1 Historical Evolution

| PR | Date | Feature | Status |
|----|------|---------|--------|
| #62 | 2026-01-28 | Memory Stack (vector DB for semantic grounding) | Merged |
| #63 | 2026-01-29 | Oracle Analysis + Async Hooks | Merged |
| #67 | 2026-01-30 | Compound Learning System (cross-session patterns) | Merged |
| #89 | 2026-01-31 | Oracle with Loa Compound Learnings | Merged |
| #128 | 2026-02-02 | Oracle Auto-Build Index | Merged |
| #129 | 2026-02-02 | Arrow function closure pattern learning | Merged |
| #138 | 2026-02-02 | Oracle bash increment fix | Open |
| #139 | 2026-02-02 | Two-Tier Learnings Architecture | Open |
| #134 | 2026-02-02 | Projen-Style Ownership | Open |

### 1.2 Open Issues Related to Learning

| Issue | Title | Relationship |
|-------|-------|--------------|
| #137 | Oracle exits with code 1 + empty learnings | Direct bug - PR #138 fixes exit code, PR #139 addresses empty learnings |
| #76 | Extend oracle with Loa's compound learnings | Vision issue - PR #89 partially addressed, PR #139 completes |
| #75 | Invisible Skill Activation | Future: QMD-indexed learnings for skill discovery |
| #74 | Auto-index skills with QMD | Infrastructure: Semantic search foundation |
| #48 | Construct Feedback Protocol | Future: Upstream learning flow from child Constructs |
| #23 | NOTES.md auto-cleanup | Memory patterns feeding into compound learning |

---

## 2. PR #134 Architecture Overview

### 2.1 Three-Zone Model (Enhanced)

PR #134 establishes clear ownership boundaries:

```
┌─────────────────────────────────────────────────────────────────────┐
│                        SYSTEM ZONE                                   │
│                     Owner: Framework                                 │
│                                                                      │
│  .claude/                                                           │
│  ├── loa/                    ← NEW: Framework-specific subdir       │
│  │   ├── CLAUDE.loa.md       ← Framework instructions (imported)    │
│  │   └── learnings/          ← PROPOSED by PR #139                  │
│  ├── skills/loa-*/           ← Renamed with prefix                  │
│  ├── commands/loa-*.md       ← Renamed with prefix                  │
│  ├── scripts/*.sh            ← Helper scripts (marked)              │
│  └── schemas/*.json          ← Validation schemas                   │
│                                                                      │
│  Characteristics:                                                    │
│  • Magic markers: @loa-managed: true | version: X | hash: SHA256   │
│  • Never edited directly by users                                   │
│  • Updated via /update-loa                                          │
│  • Checksums verified on update                                     │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                        STATE ZONE                                    │
│                     Owner: Project                                   │
│                                                                      │
│  grimoires/loa/                                                     │
│  ├── a2a/compound/           ← Project learnings (existing)         │
│  │   ├── learnings.json                                             │
│  │   └── patterns.json                                              │
│  ├── decisions.yaml          ← Project decisions                    │
│  ├── feedback/*.yaml         ← Project feedback                     │
│  ├── memory/                 ← Project memory                       │
│  └── NOTES.md                ← Session memory                       │
│                                                                      │
│  Characteristics:                                                    │
│  • Gitignored in template                                           │
│  • Project-specific, accumulates over time                          │
│  • Written by /retrospective, /compound                             │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 Key PR #134 Mechanisms

| Mechanism | Purpose | Implication for PR #139 |
|-----------|---------|-------------------------|
| **Magic Markers** | Identify framework-owned files | Framework learnings files MUST have markers |
| **SHA-256 Hash** | Detect unauthorized modifications | Learnings files need hash verification |
| **`loa-` Prefix** | Namespace separation | N/A for learnings (data files, not skills) |
| **`@` Import Pattern** | CLAUDE.md loads framework docs | Consider learnings documentation import |
| **Feature Gating** | Toggle optional features | Could gate learnings tier (advanced) |
| **Eject Command** | Transfer ownership to user | Ejected projects keep learnings as-is |

---

## 3. Compatibility Analysis: PR #139 with PR #134

### 3.1 Location Compatibility

**PR #139 Proposes**: `.claude/loa/learnings/`

**PR #134 Establishes**: `.claude/loa/` as framework-specific subdirectory

| Aspect | Assessment | Notes |
|--------|------------|-------|
| Directory location | ✅ **Compatible** | `.claude/loa/` already exists in PR #134 |
| Zone alignment | ✅ **Compatible** | System Zone per Three-Zone Model |
| Naming convention | ✅ **Compatible** | `learnings/` is descriptive, no prefix needed |
| Update flow | ✅ **Compatible** | `/update-loa` syncs `.claude/` |

### 3.2 Required Integrations

#### 3.2.1 Magic Markers for Learnings Files

PR #139 learnings files MUST include magic markers for PR #134 compatibility:

```json
{
  "_loa_managed": {
    "version": "1.15.1",
    "hash": "sha256:abc123...",
    "managed": true
  },
  "learnings": [...]
}
```

**Alternative** (for JSON files): Store marker in separate `.meta` file:
```
.claude/loa/learnings/
├── index.json
├── index.json.meta          ← Contains marker + hash
├── patterns.json
├── patterns.json.meta
└── ...
```

**Recommendation**: Use embedded `_loa_managed` object for simplicity.

#### 3.2.2 Checksum Integration

PR #134's `.claude/checksums.json` should include learnings files:

```json
{
  ".claude/loa/learnings/index.json": "sha256:...",
  ".claude/loa/learnings/patterns.json": "sha256:...",
  ".claude/loa/learnings/anti-patterns.json": "sha256:...",
  ".claude/loa/learnings/decisions.json": "sha256:...",
  ".claude/loa/learnings/troubleshooting.json": "sha256:..."
}
```

#### 3.2.3 Update.sh Integration

PR #134's `update.sh` already syncs `.claude/` from upstream. No changes needed - learnings will sync automatically.

### 3.3 Potential Conflicts

| Area | Conflict Risk | Resolution |
|------|---------------|------------|
| Directory structure | None | `.claude/loa/` already established |
| Update mechanism | None | Automatic via existing sync |
| Marker system | Low | Add markers to JSON files |
| Eject behavior | Low | Learnings stay as-is (user keeps knowledge) |
| Feature gating | None | Learnings are always-on (core feature) |

### 3.4 Implementation Order Recommendation

```
1. Merge PR #134 (Projen-Style Ownership) FIRST
   └── Establishes .claude/loa/ directory and marker system

2. Merge PR #138 (Oracle bash fix)
   └── Fixes immediate exit code bug

3. Implement PR #139 (Two-Tier Learnings)
   └── Builds on established infrastructure
   └── Uses marker system from #134
   └── Framework learnings go in .claude/loa/learnings/
```

---

## 4. Broader Learning Architecture Vision

### 4.1 Current State

```
┌─────────────────────────────────────────────────────────────────────┐
│                    LEARNING ECOSYSTEM (Current)                      │
│                                                                      │
│  /compound ──┬── grimoires/loa/a2a/compound/learnings.json          │
│              └── grimoires/loa/a2a/compound/patterns.json           │
│                                                                      │
│  /retrospective ── Extracts patterns from completed work            │
│                                                                      │
│  /oracle-analyze ──┬── Anthropic docs                               │
│                    └── grimoires/loa/** (when present)              │
│                                                                      │
│  Memory Stack ──── .loa/memory.db (vector embeddings)               │
│                                                                      │
│  PROBLEM: Fresh installs have NO learnings                          │
└─────────────────────────────────────────────────────────────────────┘
```

### 4.2 Proposed State (After PR #139)

```
┌─────────────────────────────────────────────────────────────────────┐
│                    LEARNING ECOSYSTEM (Proposed)                     │
│                                                                      │
│  TIER 1: Framework Learnings (System Zone)                          │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │ .claude/loa/learnings/                                      │    │
│  │ ├── patterns.json      (~10 proven architectural patterns) │    │
│  │ ├── anti-patterns.json (~8 things to avoid)                │    │
│  │ ├── decisions.json     (~10 architectural decisions)       │    │
│  │ └── troubleshooting.json (~12 common issues)               │    │
│  │                                                             │    │
│  │ Characteristics: Ships with Loa, read-only, ~40 entries    │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                              │                                       │
│                              ▼                                       │
│  TIER 2: Project Learnings (State Zone)                             │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │ grimoires/loa/a2a/compound/                                 │    │
│  │ ├── learnings.json     (project-specific patterns)         │    │
│  │ └── patterns.json      (from /retrospective)               │    │
│  │                                                             │    │
│  │ Characteristics: Accumulates, gitignored, project-specific │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                              │                                       │
│                              ▼                                       │
│  ORACLE QUERY LAYER                                                  │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │ Search Tier 1 ──┐                                          │    │
│  │                 ├── Merge & Dedupe (SHA-256)               │    │
│  │ Search Tier 2 ──┘          │                               │    │
│  │                            ▼                               │    │
│  │                    Apply Weights                           │    │
│  │                    (Framework: 1.0, Project: 0.9)          │    │
│  └─────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
```

### 4.3 Future Vision (Issues #75, #74, #48)

```
┌─────────────────────────────────────────────────────────────────────┐
│                    LEARNING ECOSYSTEM (Future)                       │
│                                                                      │
│  TIER 0: Registry Learnings (Cloud)          ← Issue #48            │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │ Loa Constructs Registry                                     │    │
│  │ • Community patterns                                        │    │
│  │ • Verified best practices                                   │    │
│  │ • Upstream feedback from Constructs                         │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                              │                                       │
│                              ▼                                       │
│  TIER 1: Framework Learnings (System Zone)   ← PR #139              │
│                              │                                       │
│                              ▼                                       │
│  TIER 2: Project Learnings (State Zone)      ← Existing             │
│                              │                                       │
│                              ▼                                       │
│  SEMANTIC SEARCH LAYER                       ← Issues #74, #75      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │ QMD Semantic Index                                          │    │
│  │ • Auto-indexed during /mount and /update-loa               │    │
│  │ • Enables invisible skill activation                        │    │
│  │ • Natural language queries                                  │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                              │                                       │
│                              ▼                                       │
│  MEMORY STACK (Vector DB)                    ← PR #62               │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │ .loa/memory.db                                              │    │
│  │ • Session embeddings                                        │    │
│  │ • Mid-stream memory injection                               │    │
│  │ • Cross-session recall                                      │    │
│  └─────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 5. PR #139 Modifications for PR #134 Compatibility

### 5.1 Required Changes

| File/Component | Current PR #139 Design | Required Modification |
|----------------|----------------------|----------------------|
| `index.json` | Plain JSON | Add `_loa_managed` metadata object |
| `patterns.json` | Plain JSON | Add `_loa_managed` metadata object |
| `anti-patterns.json` | Plain JSON | Add `_loa_managed` metadata object |
| `decisions.json` | Plain JSON | Add `_loa_managed` metadata object |
| `troubleshooting.json` | Plain JSON | Add `_loa_managed` metadata object |
| Sprint plan | Creates files directly | Reference marker-utils.sh for marker addition |

### 5.2 Updated JSON Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Framework Learnings File",
  "type": "object",
  "required": ["_loa_managed", "learnings"],
  "properties": {
    "_loa_managed": {
      "type": "object",
      "required": ["managed", "version"],
      "properties": {
        "managed": { "type": "boolean", "const": true },
        "version": { "type": "string", "pattern": "^[0-9]+\\.[0-9]+\\.[0-9]+$" },
        "hash": { "type": "string", "pattern": "^sha256:[a-f0-9]{64}$" }
      }
    },
    "learnings": {
      "type": "array",
      "items": { "$ref": "#/definitions/learning" }
    }
  }
}
```

### 5.3 Example File Structure

```json
{
  "_loa_managed": {
    "managed": true,
    "version": "1.15.1",
    "hash": "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  },
  "learnings": [
    {
      "id": "PAT-001",
      "tier": "framework",
      "version_added": "1.15.1",
      "type": "pattern",
      "title": "Three-Zone Model",
      "trigger": "When organizing files in a Loa-managed project",
      "solution": "Separate into System (.claude/), State (grimoires/), App (src/)",
      "quality_gates": {
        "discovery_depth": 9,
        "reusability": 10,
        "trigger_clarity": 9,
        "verification": 10
      }
    }
  ]
}
```

---

## 6. Recommendations

### 6.1 Immediate Actions

1. **Update PR #139 documents** to reference PR #134 marker system
2. **Add dependency note** in PR #139: "Depends on PR #134 for marker infrastructure"
3. **Merge order**: #134 → #138 → #139

### 6.2 Sprint Plan Modifications

PR #139 Sprint 1, Task T1.1 should be updated:

**Original**:
> Create `.claude/loa/learnings/` directory with index.json manifest

**Updated**:
> Create `.claude/loa/learnings/` directory with index.json manifest. All JSON files must include `_loa_managed` metadata object per PR #134 marker system. Use `marker-utils.sh` from PR #134 to generate hash values.

### 6.3 Future Considerations

| Issue | How PR #139 Enables It |
|-------|----------------------|
| #74 (QMD auto-index) | Framework learnings can be QMD-indexed during /mount |
| #75 (Invisible skill activation) | Learnings provide semantic context for skill matching |
| #48 (Construct feedback) | Framework learnings can receive upstream contributions |
| #23 (NOTES.md cleanup) | Pattern recognition can cross-reference framework learnings |

---

## 7. Conclusion

**PR #139 is compatible with PR #134** with minor modifications:

1. **Location** (`.claude/loa/learnings/`) aligns perfectly with PR #134's directory structure
2. **Magic markers** must be added to JSON files for integrity verification
3. **Update flow** works automatically via existing `.claude/` sync
4. **Merge order** should be: PR #134 → PR #138 → PR #139

The Two-Tier Learnings Architecture represents a natural evolution of the managed scaffolding paradigm, bringing the same ownership clarity to knowledge management that PR #134 brings to code and configuration.

---

## Appendix A: Related PR Summary

| PR | Title | Key Contribution to Learning |
|----|-------|------------------------------|
| #62 | Memory Stack | Vector DB for semantic search |
| #67 | Compound Learning | Cross-session pattern detection |
| #89 | Oracle + Loa Learnings | Query Loa's own patterns |
| #128 | Auto-build index | Seamless first-query experience |
| #134 | Projen-Style Ownership | Marker system, .claude/loa/ structure |
| #138 | Oracle bash fix | Exit code reliability |
| #139 | Two-Tier Learnings | Framework learnings ship with Loa |

## Appendix B: Open Issue Relationships

```
#137 (bug: oracle exit code)
  └── Fixed by: #138
  └── Root cause addressed by: #139

#76 (Loa as its own oracle)
  └── Partially addressed by: #89
  └── Completed by: #139

#75 (Invisible skill activation)
  └── Depends on: #74 (QMD indexing)
  └── Enhanced by: #139 (more learnings to search)

#74 (QMD auto-index)
  └── Can index: #139 framework learnings

#48 (Construct feedback upstream)
  └── Future extension of: #139 framework learnings

#23 (NOTES.md auto-cleanup)
  └── Patterns feed into: #67 compound learning
  └── Can reference: #139 framework learnings
```

---

*Research conducted via /plan-and-analyze for PR #134 and PR #139 compatibility analysis*
