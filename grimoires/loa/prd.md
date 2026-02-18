# PRD: Broader QMD Integration Across Core Skills

> Cycle: cycle-027 | Author: janitooor + Claude
> Source: [#364](https://github.com/0xHoneyJar/loa/issues/364)
> Priority: P2 (developer experience — expands existing infrastructure to more skills)
> Flatline: Reviewed (4 HIGH_CONSENSUS integrated, 5 BLOCKERS addressed)

## 1. Problem Statement

QMD ([tobi/qmd](https://github.com/tobi/qmd)) semantic search is currently scoped almost exclusively to `/oracle` and the memory search utility. The infrastructure is fully built — `qmd-sync.sh` (614 lines), collections config, query API, grep fallback — but day-to-day skills don't consume it.

Code-focused search (CK via `ck --hybrid`) covers `src/`, `lib/`, app code. But grimoires, NOTES.md, reality files, sprint plans, and documentation are markdown documents that benefit from semantic search, not code search. QMD fills this documentation gap.

**Current integration points** (only 3):
- `qmd-sync.sh` → manages collections (`qmd search`, `qmd update`)
- `search.sh` → merges vector DB + QMD results in memory pipeline
- `anthropic-oracle.sh` → routes queries via `loa-learnings-index.sh`

**Skills that should use QMD but don't**: `/implement`, `/review-sprint`, `/ride`, `/run-bridge` (Bridgebuilder), Gate 0 pre-flight.

> Sources: #364 (developer feedback survey, rating 5/5)

## 2. Goals & Success Metrics

### Goals

1. **Create a unified context query interface** that wraps QMD, CK, and grep behind a single script with three-tier fallback: QMD → CK → grep.
2. **Integrate context queries into 5 core skills**: `/implement`, `/review-sprint`, `/ride`, `/run-bridge`, Gate 0 pre-flight.
3. **Respect token budgets**: Each skill invocation gets a configurable token budget (default 2000 tokens) to prevent context bloat.
4. **Make collection mapping configurable**: Skills map to QMD collections, CK directories, and grep paths via `.loa.config.yaml`.
5. **Maintain graceful degradation**: If QMD is unavailable, fall through to CK; if CK is unavailable, fall through to grep. No skill should break if all semantic tools are missing.

### Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Skills using QMD context | 5 (from 1) | Count of skill integrations |
| Fallback coverage | 100% | All skills work with grep-only |
| Token budget compliance | 100% | No context injection exceeds configured budget |
| Query latency (QMD tier) | < 5s | Timeout enforcement |
| Zero breaking changes | 0 regressions | Existing test suite passes |

## 3. User & Stakeholder Context

### Primary Persona: Loa Developer

Developers using Loa skills benefit from contextual grounding — when `/implement` knows about relevant NOTES.md entries or past sprint decisions, it produces better code. Currently, this context is loaded manually or not at all.

### Secondary Persona: Loa Framework Maintainer

The framework maintainer needs the integration to be:
- Configurable (opt-in per skill, adjustable token budgets)
- Observable (logs which tier served each query)
- Non-breaking (existing workflows unchanged if QMD is not installed)

## 4. Functional Requirements

### FR-1: Unified Context Query Script (`qmd-context-query.sh`)

Create `.claude/scripts/qmd-context-query.sh` that accepts:
- `--query "search text"` — the search query
- `--scope grimoires|skills|notes|reality|all` — maps to directories
- `--budget N` — token budget (default 2000)
- `--format json|text` — output format
- `--timeout N` — per-tier timeout in seconds (default 5)

Three-tier fallback: QMD → CK → grep. Returns JSON array of results with `source`, `score`, `content`, `tier` fields.

### FR-2: `/implement` Integration

Before task execution, query context for:
- Relevant NOTES.md entries (scope: notes)
- Past sprint feedback for same area (scope: grimoires)
- Reality file references for modified modules (scope: reality)

Inject results into implementation context.

### FR-3: `/review-sprint` Integration

Before code review, query context for:
- Prior review feedback patterns (scope: grimoires)
- NOTES.md blockers and observations (scope: notes)
- SDD architecture decisions relevant to changed files (scope: grimoires)

### FR-4: `/ride` Integration

During codebase analysis, query context for:
- Existing documentation that may overlap (scope: grimoires)
- Prior reality files for drift comparison (scope: reality)

### FR-5: `/run-bridge` (Bridgebuilder) Integration

Before Bridgebuilder review, query context for:
- Lore entries relevant to current changes (scope: grimoires)
- Vision Registry entries (scope: grimoires)
- Past bridge findings for pattern detection (scope: grimoires)

### FR-6: Gate 0 Pre-flight Integration

During Gate 0 pre-flight checks, query context for:
- Configuration precedents (scope: skills)
- Known issues from NOTES.md (scope: notes)

### FR-7: Collection Configuration

Configurable in `.loa.config.yaml`:

```yaml
qmd_context:
  enabled: true
  default_budget: 2000
  timeout_seconds: 5
  scopes:
    grimoires:
      qmd_collection: "loa-grimoire"
      ck_path: ".ck/loa-grimoire/"
      grep_paths: ["grimoires/loa/"]
    skills:
      qmd_collection: "loa-skills"
      ck_path: ".ck/skills/"
      grep_paths: [".claude/skills/"]
    notes:
      qmd_collection: "loa-grimoire"
      ck_path: ".ck/loa-grimoire/"
      grep_paths: ["grimoires/loa/NOTES.md"]
    reality:
      qmd_collection: "loa-reality"
      ck_path: ".ck/reality/"
      grep_paths: ["grimoires/loa/reality/"]
```

## 5. Non-Functional Requirements

### NFR-1: Graceful Fallback
Every query MUST succeed even if all semantic tools are unavailable. Grep is the terminal fallback and always available.

### NFR-2: Token Efficiency
Context injection MUST NOT exceed the configured token budget per skill invocation. Default: 2000 tokens. Estimation: `word_count × 1.3`.

### NFR-3: Timeout Enforcement
Each tier gets a configurable timeout (default 5s). If a tier times out, fall through to the next tier.

### NFR-4: No Breaking Changes
Existing skill behavior MUST be unchanged when `qmd_context.enabled: false` or when QMD is not installed. All existing tests MUST continue to pass.

### NFR-5: Incremental Adoption
Each skill integration MUST be independently toggleable. A skill can opt out without affecting others.

## 6. Scope & Prioritization

### In Scope (MVP)
- Unified query script with three-tier fallback
- 5 skill integrations (implement, review-sprint, ride, run-bridge, gate-0)
- Token budget enforcement
- Configuration in `.loa.config.yaml`
- Unit and integration tests

### Out of Scope
- New QMD collections (use existing)
- QMD binary installation or upgrade
- Memory stack integration changes
- UI/UX changes
- Performance optimization of QMD itself

## 7. Risks & Dependencies

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| QMD binary not installed | Medium | Low | Three-tier fallback ensures grep works |
| CK index stale | Low | Low | Grep fallback covers |
| Token budget exceeded | Medium | Medium | Hard truncation at budget limit |
| Query latency spikes | Low | Medium | Per-tier timeout with fallback |
| Skill SKILL.md changes break existing behavior | Low | High | Integration is additive, not modifying existing logic |

### Dependencies
- `qmd-sync.sh` (existing, stable)
- `detect-semantic-tools.sh` (existing, stable)
- `context-manager.sh` (existing, reference patterns)
- `.loa.config.yaml` (existing configuration mechanism)
