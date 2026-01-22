# PRD: Migrate Skills to ck-First Search

**Version**: 1.0.0
**Status**: Draft
**Created**: 2026-01-23
**Issue**: Internal discovery

---

## 1. Problem Statement

The Loa framework has semantic search infrastructure (`ck`) configured as the preferred search method (`prefer_ck: true`), but skills still use hardcoded `grep` commands. This creates:

1. **Inconsistency**: Config says prefer ck, skills use grep
2. **Missed capability**: Semantic search would improve code discovery accuracy
3. **Maintenance burden**: Grep patterns are scattered across 5+ skill files
4. **No abstraction**: Skills don't use `search-orchestrator.sh` which handles the routing

### Evidence

| Metric | Value |
|--------|-------|
| grep references in skills | 16 commands across 5 files |
| ck references in skills | 0 |
| search-orchestrator.sh usage in skills | 0 |
| Config `prefer_ck` setting | `true` (2 locations) |

### Affected Skills

| Skill | grep Count | Primary Use Case |
|-------|------------|------------------|
| `riding-codebase` | 11 | Route/model/env extraction |
| `reviewing-code` | 2 | Dependency tracking |
| `implementing-tasks` | 1 | Context retrieval |
| `deploying-infrastructure` | 1 | Secrets scanning |
| `translating-for-executives` | 1 | Ghost feature detection |

---

## 2. Goals & Success Metrics

### Primary Goal

Make `ck` the primary search tool in skills, with `grep` as automatic fallback when `ck` is unavailable.

### Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Skills using search abstraction | 100% | All grep calls replaced |
| Fallback works without ck | 100% | Tests pass without ck installed |
| Search accuracy (semantic) | +20% | Manual evaluation of riding-codebase results |
| Breaking changes | 0 | All existing workflows function |

---

## 3. User Context

### Primary User: Claude Agent

The agent executes skill instructions. Skills with semantic search can:
- Find related code even with different naming
- Understand intent ("authentication flow") vs exact match
- Produce more relevant results for code extraction

### Secondary User: Developer

Developers benefit from:
- Cleaner skill files (no grep pattern maintenance)
- Better `/ride` output with semantic understanding
- Consistent behavior across environments

---

## 4. Functional Requirements

### FR-1: Search Abstraction Layer

Skills MUST use `search-orchestrator.sh` or equivalent abstraction instead of direct grep calls.

**Acceptance Criteria**:
- [ ] No direct `grep -r` or `grep -n` calls in skill SKILL.md files
- [ ] All search calls route through abstraction layer
- [ ] Abstraction auto-detects ck availability

### FR-2: Semantic Search Integration

Skills SHOULD use semantic search for discovery queries.

**Acceptance Criteria**:
- [ ] Route extraction uses `hybrid` search type
- [ ] Model extraction uses `hybrid` search type
- [ ] Code analysis queries use `semantic` search type

### FR-3: Grep Fallback Preservation

Skills MUST work correctly when ck is not installed.

**Acceptance Criteria**:
- [ ] All skills pass tests without ck installed
- [ ] Fallback produces equivalent (if degraded) results
- [ ] Clear logging when using fallback mode

### FR-4: Pattern-Based Search Preservation

Skills that need exact regex matching MUST retain that capability.

**Acceptance Criteria**:
- [ ] Secrets scanning (`grep "password\|secret"`) uses `regex` type
- [ ] TODO/FIXME detection uses `regex` type
- [ ] Exact pattern matches don't use semantic search

---

## 5. Non-Functional Requirements

### NFR-1: Performance

- Search abstraction adds <100ms overhead
- Caching prevents redundant ck index builds

### NFR-2: Compatibility

- Works with ck versions 0.1.x and above
- Works without ck installed (grep fallback)
- No changes to user-facing command interfaces

---

## 6. Out of Scope

- Installing ck automatically
- Modifying ck behavior or options
- Changing search-orchestrator.sh implementation
- Adding new search capabilities beyond existing ck features

---

## 7. Risks & Dependencies

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| ck not installed on user systems | Medium | Low | Robust grep fallback |
| Semantic search returns different results | Medium | Medium | Test both modes, document differences |
| Performance regression | Low | Medium | Benchmark before/after |
| Breaking existing workflows | Low | High | Comprehensive testing |

### Dependencies

- `search-orchestrator.sh` exists and works (verified: yes)
- `ck` command API stable (verified: yes)
- Config `prefer_ck` respected (verified: yes)

---

## 8. Implementation Notes

### Recommended Approach

Replace grep calls in skills with calls to search-orchestrator.sh:

**Before**:
```bash
grep -rn "@Get\|@Post\|@Put\|@Delete" src/
```

**After**:
```bash
.claude/scripts/search-orchestrator.sh hybrid "@Get @Post @Put @Delete" src/
```

Or for regex patterns that must be exact:
```bash
.claude/scripts/search-orchestrator.sh regex "password\|secret\|key" src/
```

### Skills to Update

1. **riding-codebase/SKILL.md** - 11 grep calls (highest priority)
2. **reviewing-code/impact-analysis.md** - 2 grep calls
3. **implementing-tasks/context-retrieval.md** - 1 grep call
4. **deploying-infrastructure/SKILL.md** - 1 grep call
5. **translating-for-executives/SKILL.md** - 1 grep call

---

## 9. Acceptance Criteria Summary

- [ ] All 16 grep calls migrated to search-orchestrator.sh
- [ ] Skills pass tests with ck installed
- [ ] Skills pass tests without ck installed
- [ ] No breaking changes to existing workflows
- [ ] Documentation updated

---

**PRD Status**: Ready for `/architect`
