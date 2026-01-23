# SDD: Migrate Skills to ck-First Search

**Version**: 1.0.0
**Status**: Draft
**Created**: 2026-01-23
**PRD**: `grimoires/loa/prd-ck-migration.md`

---

## 1. Executive Summary

Migrate 16 hardcoded `grep` calls across 5 skills to use `search-orchestrator.sh`, enabling semantic search via `ck` while preserving `grep` fallback. No new infrastructure required - uses existing abstraction layer.

---

## 2. Architecture Overview

### Current State

```
┌─────────────────────┐
│   Skill Files       │
│   (SKILL.md)        │
│                     │
│  grep -rn "..."     │───────────────────────────────► grep
│  grep -rn "..."     │
│  grep -rn "..."     │
└─────────────────────┘

search-orchestrator.sh exists but unused by skills
```

### Target State

```
┌─────────────────────┐     ┌──────────────────────┐
│   Skill Files       │     │ search-orchestrator  │
│   (SKILL.md)        │     │                      │
│                     │     │  ck available?       │
│  search-orchestrator│────►│    YES → ck          │───► Results
│  search-orchestrator│     │    NO  → grep        │
│  search-orchestrator│     │                      │
└─────────────────────┘     └──────────────────────┘
```

---

## 3. Component Design

### 3.1 Search Orchestrator (Existing)

**Location**: `.claude/scripts/search-orchestrator.sh`

**Interface**:
```bash
search-orchestrator.sh <search_type> <query> [path] [top_k] [threshold]
```

**Search Types** (ck v0.7.0+ syntax):
| Type | ck Command | grep Fallback | Use Case |
|------|------------|---------------|----------|
| `semantic` | `ck --sem` | keyword OR | Conceptual queries |
| `hybrid` | `ck --hybrid` | keyword OR | Discovery + exact |
| `regex` | `ck --regex` | `grep -E` | Exact patterns |

**Note**: ck v0.7.0+ uses `--sem` (not `--semantic`), `--limit` (not `--top-k`), and path as positional argument (not `--path`).

**No changes needed** - existing implementation handles routing.

### 3.2 Skill Migration Patterns

#### Pattern A: Discovery Search (hybrid)

**Use for**: Finding routes, models, components by concept.

**Before**:
```bash
grep -rn "@Get\|@Post\|@Put\|@Delete\|@Patch\|router\.\|app\.\(get\|post\|put\|delete\|patch\)" src/
```

**After**:
```bash
.claude/scripts/search-orchestrator.sh hybrid "route handler @Get @Post @Put @Delete @Patch router app.get app.post" src/
```

#### Pattern B: Exact Pattern Search (regex)

**Use for**: Secrets, TODOs, exact string matching.

**Before**:
```bash
grep -rn "TODO\|FIXME\|HACK\|XXX" src/
```

**After**:
```bash
.claude/scripts/search-orchestrator.sh regex "TODO|FIXME|HACK|XXX" src/
```

#### Pattern C: Model/Entity Discovery (hybrid)

**Use for**: Finding data models, schemas, entities.

**Before**:
```bash
grep -rn "model \|@Entity\|class.*Entity\|CREATE TABLE" src/
```

**After**:
```bash
.claude/scripts/search-orchestrator.sh hybrid "model @Entity class Entity schema table struct interface" src/
```

---

## 4. Migration Mapping

### 4.1 riding-codebase/SKILL.md (11 calls)

| Line | Current grep | Migration | Search Type |
|------|--------------|-----------|-------------|
| 541 | `grep -n -B1 -A2 "$kw" "$file"` | Keep as-is (single file, context) | N/A |
| 566 | Route patterns | `search-orchestrator.sh hybrid` | hybrid |
| 577 | Model patterns | `search-orchestrator.sh hybrid` | hybrid |
| 585 | Env var extraction | `search-orchestrator.sh regex` | regex |
| 593 | TODO/FIXME detection | `search-orchestrator.sh regex` | regex |
| 827 | Ghost feature check | `search-orchestrator.sh hybrid` | hybrid |
| 852 | Feature X check | `search-orchestrator.sh hybrid` | hybrid |
| 870-871 | OAuth/BadgeTier check | `search-orchestrator.sh hybrid` | hybrid |
| 900 | Export extraction | `search-orchestrator.sh regex` | regex |
| 903 | Solidity extraction | `search-orchestrator.sh regex` | regex |

**Note**: Line 541 grep with `-B1 -A2` context should remain grep (context output format).

### 4.2 reviewing-code/impact-analysis.md (2 calls)

| Line | Current grep | Migration | Search Type |
|------|--------------|-----------|-------------|
| 223 | Import tracking | `search-orchestrator.sh hybrid` | hybrid |
| 229 | Documentation search | `search-orchestrator.sh hybrid` | hybrid |

### 4.3 implementing-tasks/context-retrieval.md (1 call)

| Line | Current grep | Migration | Search Type |
|------|--------------|-----------|-------------|
| 156 | JWT/token/auth search | `search-orchestrator.sh hybrid` | hybrid |

### 4.4 deploying-infrastructure/SKILL.md (1 call)

| Line | Current grep | Migration | Search Type |
|------|--------------|-----------|-------------|
| 677 | Secrets scanning | `search-orchestrator.sh regex` | regex |

### 4.5 translating-for-executives/SKILL.md (1 call)

| Line | Current grep | Migration | Search Type |
|------|--------------|-----------|-------------|
| 497 | Ghost feature check | `search-orchestrator.sh hybrid` | hybrid |

---

## 5. Exception Handling

### 5.1 Keep as grep

Some patterns should NOT be migrated:

1. **Context output** (`-B`, `-A`, `-C` flags) - search-orchestrator doesn't support context lines
2. **Count only** (`-c` flag) - different output format
3. **Single file search** - grep is simpler and sufficient

### 5.2 Fallback Behavior

When ck unavailable, search-orchestrator.sh:
- Logs warning (not error)
- Converts semantic/hybrid to keyword OR pattern
- Produces equivalent results (degraded accuracy)

---

## 6. Testing Strategy

### 6.1 Unit Tests

For each migrated call:
1. Test with ck installed → verify semantic results
2. Test with ck unavailable → verify grep fallback works
3. Compare result sets for equivalence

### 6.2 Integration Tests

Run full workflows:
1. `/ride` on sample codebase with ck
2. `/ride` on sample codebase without ck
3. Compare output quality

### 6.3 Test Matrix

| Skill | With ck | Without ck | Both Pass |
|-------|---------|------------|-----------|
| riding-codebase | ⬜ | ⬜ | ⬜ |
| reviewing-code | ⬜ | ⬜ | ⬜ |
| implementing-tasks | ⬜ | ⬜ | ⬜ |
| deploying-infrastructure | ⬜ | ⬜ | ⬜ |
| translating-for-executives | ⬜ | ⬜ | ⬜ |

---

## 7. Documentation Updates

### 7.1 Files to Update

| File | Change |
|------|--------|
| `CLAUDE.md` | Add ck search preference note |
| `jit-retrieval.md` | Update examples to show skill usage |
| Skill SKILL.md files | Migration changes |

### 7.2 No Changes Required

- `search-orchestrator.sh` - works as-is
- `.loa.config.yaml` - already has `prefer_ck: true`

---

## 8. Rollback Plan

If issues discovered:
1. Revert skill file changes
2. grep behavior unchanged
3. No infrastructure changes to rollback

---

## 9. Implementation Order

1. **riding-codebase** (highest grep count, most impact)
2. **reviewing-code** (second highest)
3. **implementing-tasks**
4. **deploying-infrastructure**
5. **translating-for-executives**
6. **Documentation updates**
7. **Testing pass**

---

**SDD Status**: Ready for `/sprint-plan`
