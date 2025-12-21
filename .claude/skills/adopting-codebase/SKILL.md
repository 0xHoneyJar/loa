---
parallel_threshold: 5000
timeout_minutes: 90
---

# Adopting Codebase into Loa

<objective>
Migrate an existing codebase to Loa-maintained documentation. Extract actual code behavior, compare against existing documentation for drift, generate Loa-standard artifacts grounded in evidence, and establish Loa as the single source of truth.
</objective>

<kernel_framework>
## Task (N - Narrow Scope)
Adopt existing codebase into Loa. Extract code reality, analyze drift from legacy docs, generate `prd.md` and `sdd.md` grounded in code evidence, import tech debt to Beads.

## Context (L - Logical Structure)
- **Input**: Existing codebase with source files, legacy documentation
- **Output directories**: `loa-grimoire/reality/`, `loa-grimoire/legacy/`
- **Output files**: `prd.md`, `sdd.md`, `drift-report.md`
- **Current state**: Potentially outdated documentation, undocumented code
- **Desired state**: Code-grounded Loa artifacts as single source of truth

## Constraints (E - Explicit)
- DO NOT trust existing documentation—verify everything against actual code
- DO NOT assume code behavior—quote actual code with file:line evidence
- DO NOT skip reading source files—documentation from code, not guesswork
- DO NOT modify code during adoption—this is documentation extraction only
- DO cite evidence: Every claim must have `file:line` reference
- DO create Beads issues for discovered tech debt
- DO preserve context: Link to original docs being replaced

## Verification (E - Easy to Verify)
**Success** = Complete adoption with:
- `loa-grimoire/reality/` directory with extracted code facts
- `loa-grimoire/legacy/` directory with inventoried docs
- `loa-grimoire/drift-report.md` with drift analysis
- `loa-grimoire/prd.md` grounded in code evidence
- `loa-grimoire/sdd.md` grounded in code evidence
- Beads epic with migration tasks
- Tech debt imported from TODO/FIXME comments

## Reproducibility (R - Reproducible Results)
- Include exact file paths and line numbers for all evidence
- Quote actual code, not paraphrased descriptions
- Specify exact commands used for extraction
- Reference specific commit hash for codebase state
</kernel_framework>

<core_principle>
```
CODE is truth → Loa documents CODE → Legacy docs are deprecated
```

Never trust existing documentation. Verify everything against actual code.
</core_principle>

<uncertainty_protocol>
If code behavior is ambiguous:
1. State: "I'm uncertain about [specific aspect]"
2. Quote the ambiguous code with file:line
3. List possible interpretations
4. Ask for clarification
5. Create Beads issue tagged `needs-clarification`

**Never assume. Always ground in evidence.**
</uncertainty_protocol>

<workflow>
## Phase -1: Context Assessment (CRITICAL—DO THIS FIRST)

Assess codebase size to determine parallel splitting:

```bash
.claude/scripts/context-check.sh
```

**Thresholds:**
| Size | Lines | Strategy |
|------|-------|----------|
| SMALL | <5,000 | Sequential (all phases) |
| MEDIUM | 5,000-15,000 | Consider phase splitting |
| LARGE | >15,000 | MUST split extraction by directory |

## Phase 0: Context Ingestion (Preflight)

Before analyzing code, check for user-provided context that can guide adoption.

> **⚠️ CARDINAL RULE: CODE IS TRUTH**
> ```
> 1. CODE               ← Absolute source of truth
> 2. Loa Artifacts      ← Derived FROM code evidence
> 3. Legacy Docs        ← Claims to verify against code
> 4. User Context       ← Hypotheses to test against code
> ```
> User context GUIDES investigation. It NEVER determines output.

### 0.1 Check for Existing Context

```bash
mkdir -p loa-grimoire/context

if [ -d "loa-grimoire/context" ] && [ "$(ls -A loa-grimoire/context 2>/dev/null)" ]; then
  echo "📚 Found user-provided context:"
  find loa-grimoire/context -type f \( -name "*.md" -o -name "*.txt" \) | while read f; do
    echo "  - $f ($(wc -l < "$f") lines)"
  done
  CONTEXT_EXISTS=true
else
  echo "ℹ️  No user context found in loa-grimoire/context/"
  echo "💡 Tip: Add context files before re-running /adopt for enhanced analysis"
  echo "   See: .claude/skills/adopting-codebase/resources/context-templates.md"
  CONTEXT_EXISTS=false
fi
```

### 0.2 Context File Types

The following context types are recognized:

| File Pattern | Purpose | How It's Used |
|--------------|---------|---------------|
| `architecture*.md` | Architecture decisions, diagrams | Guides module boundary detection |
| `stakeholder*.md` | Business requirements, priorities | Informs PRD generation |
| `tribal*.md` | Undocumented knowledge, gotchas | Adds to uncertainty/risk sections |
| `roadmap*.md` | Planned features, deprecations | Identifies ghost features vs planned |
| `interview*.md` | Team interviews, domain knowledge | Enriches feature understanding |
| `constraints*.md` | Technical/business constraints | Adds to SDD constraints section |
| `glossary*.md` | Domain terminology | Ensures consistent naming in artifacts |
| `*.md` / `*.txt` | Any other context | General enrichment |

### 0.3 Ingest Context

For each context file found, extract key information:

```bash
mkdir -p loa-grimoire/reality

for f in loa-grimoire/context/*.md loa-grimoire/context/*.txt; do
  [ -f "$f" ] || continue

  FILENAME=$(basename "$f")
  echo "=== Ingesting: $FILENAME ===" >> loa-grimoire/reality/context-summary.md

  # Extract headers as key topics
  grep "^#" "$f" >> loa-grimoire/reality/context-summary.md 2>/dev/null
  echo "" >> loa-grimoire/reality/context-summary.md
done
```

### 0.4 Create Context-Guided Analysis Plan

If context exists, generate `loa-grimoire/reality/claims-to-verify.md`:

```markdown
# Claims to Verify Against Code

> Generated from: loa-grimoire/context/
> These are HYPOTHESES, not facts. Code determines truth.

## Priority Areas (from user context)

### Architecture Focus
[From architecture*.md - which modules to analyze carefully]

### Business-Critical Features
[From stakeholder*.md - features that must be accurately documented]

### Known Gotchas
[From tribal*.md - areas where code may be misleading]

### Planned Changes
[From roadmap*.md - features that may appear incomplete intentionally]

## Claims Checklist

Based on context, verify these claims against actual code:

- [ ] [Claim from context] → Check: [how to verify in code]
- [ ] [Claim from context] → Check: [how to verify in code]
```

### 0.5 Context vs Reality Reconciliation

During Phase 3 (Drift Analysis), context claims are **validated against code**:

| Context Claims | Code Shows | Result |
|----------------|------------|--------|
| X | X | ✅ Context confirmed, include in Loa artifacts |
| X | Y | ❌ Context wrong, Loa artifacts say Y (**code wins**) |
| X | Nothing | ❌ Context unverified, excluded from Loa artifacts |

**Code ALWAYS wins. Context NEVER overrides code.**

When context is wrong:
1. Loa artifact reflects CODE truth
2. Drift report notes the context mismatch
3. User is informed their belief was incorrect

## Phase 1: Code Reality Extraction

### 1.1 Setup

```bash
mkdir -p loa-grimoire/reality loa-grimoire/legacy loa-grimoire/plans
```

### 1.2 Extract System Reality

#### Directory Structure
```bash
find . -type d -maxdepth 4 \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" \
  -not -path "*/dist/*" \
  -not -path "*/build/*" \
  -not -path "*/__pycache__/*" \
  -not -path "*/.venv/*" \
  2>/dev/null > loa-grimoire/reality/directory-structure.txt
```

#### API Routes (language-agnostic)
```bash
grep -rn "@Get\|@Post\|@Put\|@Delete\|@Patch\|router\.\|app\.\(get\|post\|put\|delete\|patch\)\|@api\|@route\|@RequestMapping" \
  --include="*.ts" --include="*.js" --include="*.py" --include="*.go" --include="*.java" 2>/dev/null \
  > loa-grimoire/reality/api-routes.txt
```

#### Data Models
```bash
grep -rn "model \|class.*Entity\|@Entity\|CREATE TABLE\|type.*struct\|interface \|@dataclass\|schema\s*=" \
  --include="*.prisma" --include="*.ts" --include="*.sql" --include="*.go" --include="*.py" 2>/dev/null \
  > loa-grimoire/reality/data-models.txt
```

#### Environment Variables
```bash
grep -roh 'process\.env\.\w\+\|os\.environ\[.\+\]\|os\.Getenv\(.\+\)\|env\.\w\+\|ENV\[.\+\]' \
  --include="*.ts" --include="*.js" --include="*.py" --include="*.go" --include="*.rb" 2>/dev/null \
  | sort -u > loa-grimoire/reality/env-vars.txt
```

#### Tech Debt
```bash
grep -rn "TODO\|FIXME\|HACK\|XXX\|BUG\|@deprecated\|OPTIMIZE\|REFACTOR" \
  --include="*.ts" --include="*.js" --include="*.py" --include="*.go" --include="*.java" 2>/dev/null \
  > loa-grimoire/reality/tech-debt.txt
```

#### Features & Permissions
```bash
grep -rn "feature\|flag\|toggle\|role\|permission\|isAdmin\|canAccess\|@Roles\|@RequirePermission\|@authorize" \
  --include="*.ts" --include="*.js" --include="*.py" 2>/dev/null \
  > loa-grimoire/reality/features-permissions.txt
```

### 1.3 Generate Reality Summary

Create `loa-grimoire/reality/REALITY-SUMMARY.md` with:

```markdown
# Code Reality Summary

> Generated: [timestamp]
> Commit: [git rev-parse HEAD]

## Statistics

| Metric | Count |
|--------|-------|
| Source files | [count] |
| API endpoints | [count] |
| Data models | [count] |
| Environment variables | [count] |
| Tech debt items | [count] |

## Key Observations

### Architecture Patterns
[Observed patterns from directory structure and imports]

### External Dependencies
[From env vars and import statements]

### Critical Paths
[High-traffic or security-sensitive code paths]
```

---

## Phase 2: Legacy Documentation Inventory

### 2.1 Find All Documentation

```bash
find . -type f \( -name "*.md" -o -name "*.rst" -o -name "*.txt" -o -name "*.adoc" \) \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" \
  -not -path "*/loa-grimoire/*" \
  2>/dev/null > loa-grimoire/legacy/doc-files.txt
```

### 2.2 Categorize Documents

For each document, determine:
- **Type**: Tutorial, How-To, Reference, Explanation
- **Key Claims**: Features, architecture, APIs mentioned
- **Last Modified**: `git log -1 --format="%ai" -- <file>`

### 2.3 Create Inventory

Create `loa-grimoire/legacy/INVENTORY.md`:

```markdown
# Legacy Documentation Inventory

> Generated: [timestamp]

## Documents Found

| File | Type | Last Modified | Key Claims |
|------|------|---------------|------------|
| docs/README.md | Reference | 2024-01-15 | API overview, auth flow |
| ... | ... | ... | ... |

## Summary

- Total documents: [count]
- Reference docs: [count]
- Tutorials: [count]
- Out of date (>6mo): [count]
```

---

## Phase 3: Drift Analysis

### 3.1 Compare Reality vs Claims

For each claim in legacy docs, verify against code reality:

| Status | Definition |
|--------|------------|
| **Ghost** | Documented but doesn't exist in code |
| **Shadow** | Exists in code but not documented |
| **Aligned** | Documentation matches code |
| **Stale** | Documentation partially matches (outdated) |

### 3.2 Generate Drift Report

Create `loa-grimoire/drift-report.md`:

```markdown
# Documentation Drift Report

> Generated: [timestamp]
> Codebase commit: [sha]

## Executive Summary

[2-3 sentence overview of drift severity]

## Drift Score: X% (lower is better)

Formula: (ghosts + shadows) / (total documented items) * 100

## Summary Table

| Category | In Code | Documented | Aligned | Ghosts | Shadows |
|----------|---------|------------|---------|--------|---------|
| API Endpoints | X | Y | A | G | S |
| Data Models | X | Y | A | G | S |
| Features | X | Y | A | G | S |
| Environment | X | Y | A | G | S |

## Critical Drift Items

### Ghosts (Documented but Missing)

| Item | Legacy Doc Location | Status |
|------|---------------------|--------|
| `/api/v1/deprecated` | docs/api.md:45 | GHOST - Code removed |

### Shadows (Exist but Undocumented)

| Item | Code Location | Status |
|------|---------------|--------|
| `/api/v2/metrics` | src/routes/metrics.ts:12 | SHADOW - New endpoint |

### Stale (Outdated)

| Item | Documented | Actual | Location |
|------|------------|--------|----------|
| Auth method | Basic Auth | OAuth2 | src/auth/oauth.ts |

## Recommendations

1. **Immediate**: [Critical items to address]
2. **Short-term**: [High-priority improvements]
3. **Long-term**: [Nice-to-have updates]
```

### 3.3 Three-Way Drift Analysis (with User Context)

If user context was provided in Phase 0, include context validation:

```markdown
## User Context vs Code Reality

| User Claim | Source File | Code Evidence | Status |
|------------|-------------|---------------|--------|
| "Auth uses JWT" | tribal-knowledge.md | `src/auth/jwt.ts` exists | ✅ Confirmed |
| "Payments are Stripe-only" | architecture-notes.md | Found Stripe + PayPal in `src/payments/` | ⚠️ Context outdated |
| "Redis for sessions" | architecture-notes.md | No Redis imports found | ❌ Context incorrect |

## Context-Docs Agreement (High Confidence Drift)

When both user context AND legacy docs claim something that code contradicts, this is high-confidence drift:

| Claim | Context | Legacy Docs | Code Reality | Confidence |
|-------|---------|-------------|--------------|------------|
| "Feature X exists" | ✅ | ✅ | ❌ Not found | High - likely removed |
| "Uses PostgreSQL" | ✅ | ✅ | MySQL in DATABASE_URL | High - belief mismatch |

## Context Validation Summary

- **Confirmed claims**: [count] (proceed with confidence)
- **Outdated context**: [count] (inform user, update understanding)
- **Incorrect context**: [count] (Loa artifacts reflect code truth)

> **Remember**: Context validated claims go into Loa artifacts.
> Context-contradicted claims are EXCLUDED (code wins).
```

### 3.4 Create Beads Issues for Drift

```bash
# Create drift resolution epic
DRIFT_EPIC=$(bd create "Epic: Documentation Drift Resolution" -t epic -p 1 -l migration,drift --json | jq -r '.id')

# For critical ghosts (documented features that don't exist)
bd create "Drift: [feature] documented but missing from code" -t bug -p 1 -l drift,ghost --json

# For important shadows (code features without documentation)
bd create "Drift: [feature] exists in code but undocumented" -t task -p 2 -l drift,shadow --json
```

---

## Phase 4: Loa Artifact Generation

### 4.1 Generate PRD

Create `loa-grimoire/prd.md`:

```markdown
# Product Requirements Document

> **Source of Truth Notice**
> Generated from code analysis on [date]. Supersedes legacy documentation.
> Codebase commit: [sha]

## Document Metadata

| Field | Value |
|-------|-------|
| Generated | [timestamp] |
| Source | Code reality extraction |
| Drift Score | X% |
| Last Legacy Doc | [path] |

## Product Overview

[Derived from code structure and README]

## User Types

[From actual role/permission code with file:line evidence]

### User Type: [Name]
- **Evidence**: `src/auth/roles.ts:23`
- **Permissions**: [list from code]
- **Code Quote**:
  ```typescript
  // Actual permission definition
  ```

## Features

[From actual code with evidence for each]

### Feature: [Name]
- **Status**: Active in code
- **Evidence**: `src/features/[name]/index.ts:1`
- **Endpoints**: [list if applicable]
- **Data Models**: [list if applicable]
- **Code Quote**:
  ```typescript
  // Representative implementation
  ```

## Deprecated/Ghost Features

[Features in legacy docs but not in code - for historical reference]

| Feature | Last Documented | Status |
|---------|-----------------|--------|
| [name] | docs/old.md:45 | Removed in commit [sha] |
```

### 4.2 Generate SDD

Create `loa-grimoire/sdd.md`:

```markdown
# System Design Document

> **Source of Truth Notice**
> Generated from code analysis on [date]. Supersedes legacy documentation.
> Codebase commit: [sha]

## Architecture Overview

[From directory structure and import analysis]

### System Diagram

```
[ASCII diagram of actual architecture]
```

## External Dependencies

[From env vars with evidence]

| Dependency | Type | Evidence |
|------------|------|----------|
| PostgreSQL | Database | `DATABASE_URL` in `.env.example` |
| Redis | Cache | `REDIS_URL` in `src/cache/redis.ts:5` |

## Module Structure

[From directory analysis]

| Module | Path | Purpose |
|--------|------|---------|
| Auth | `src/auth/` | Authentication and authorization |
| API | `src/api/` | REST endpoint handlers |

## Data Model

[From schema files with quotes]

### Entity: [Name]
- **Source**: `prisma/schema.prisma:45`
- **Schema**:
  ```prisma
  // Actual schema definition
  ```

## API Surface

[From route extraction]

| Method | Endpoint | Handler | Evidence |
|--------|----------|---------|----------|
| GET | /api/users | UserController.list | `src/api/users.ts:12` |
| POST | /api/auth/login | AuthController.login | `src/api/auth.ts:34` |

## Security Model

[From auth code analysis]

### Authentication
- **Method**: [from code]
- **Evidence**: `src/auth/strategy.ts:8`

### Authorization
- **Model**: [RBAC/ABAC/etc from code]
- **Evidence**: `src/auth/permissions.ts:15`
```

### 4.3 Import Tech Debt to Beads

```bash
# Create tech debt epic
DEBT_EPIC=$(bd create "Epic: Imported Tech Debt" -t epic -p 2 -l legacy,tech-debt --json | jq -r '.id')

# Import each TODO/FIXME
while IFS=: read -r file line content; do
  [[ -z "$content" ]] && continue
  PRIORITY=3
  TYPE="task"
  [[ "$content" =~ FIXME|BUG ]] && PRIORITY=2 && TYPE="bug"
  [[ "$content" =~ HACK|XXX ]] && PRIORITY=2

  # Truncate long content
  TITLE="${content:0:80}"

  bd create "Legacy: $TITLE" -t $TYPE -p $PRIORITY -l legacy,imported \
    -d "Found in $file:$line\n\nOriginal comment:\n$content" --json
done < loa-grimoire/reality/tech-debt.txt
```

---

## Phase 5: Legacy Deprecation

**Skip this phase if `--skip-deprecation` flag is set.**

### 5.1 Add Deprecation Notices

For each file in `loa-grimoire/legacy/doc-files.txt`, prepend:

```markdown
<!--
+======================================================================+
|  DEPRECATED - DO NOT UPDATE                                          |
+======================================================================+
|  This document has been superseded by Loa-managed documentation.     |
|                                                                      |
|  Source of Truth:                                                    |
|  - Product Requirements: loa-grimoire/prd.md                         |
|  - System Design: loa-grimoire/sdd.md                                |
|  - Task Tracking: Beads (.beads/)                                    |
|                                                                      |
|  Drift Report: loa-grimoire/drift-report.md                          |
|  Deprecated on: [date]                                               |
+======================================================================+
-->

```

### 5.2 Update README

Add to top of project README.md:

```markdown
## Documentation

This project uses **Loa** for documentation management.

| Document | Location |
|----------|----------|
| Product Requirements | [`loa-grimoire/prd.md`](loa-grimoire/prd.md) |
| System Design | [`loa-grimoire/sdd.md`](loa-grimoire/sdd.md) |
| Task Tracking | `.beads/` (use `bd list`) |
| Drift Report | [`loa-grimoire/drift-report.md`](loa-grimoire/drift-report.md) |

> Legacy documentation has been deprecated. See files for notices.
```

---

## Phase 6: Maintenance Handoff

### 6.1 Install Drift Detection

Verify drift detection script exists and is executable:

```bash
chmod +x .claude/scripts/detect-drift.sh
```

### 6.2 Create Migration Tasks

```bash
MIGRATION_EPIC=$(bd create "Epic: Loa Migration Complete" -t epic -p 1 -l migration --json | jq -r '.id')

bd create "Validate PRD with stakeholders" -t task -p 2 -l migration \
  -d "Review loa-grimoire/prd.md with product stakeholders" --json

bd create "Validate SDD with engineering team" -t task -p 2 -l migration \
  -d "Review loa-grimoire/sdd.md with engineering team" --json

bd create "Resolve critical drift items" -t task -p 1 -l migration \
  -d "Address all CRITICAL and HIGH drift items from drift-report.md" --json

bd create "Communicate Loa as source of truth" -t task -p 2 -l migration \
  -d "Announce to team that Loa docs are now the official source" --json
```

### 6.3 Report Completion

Output summary:

```markdown
# Adoption Complete

## Statistics

| Metric | Value |
|--------|-------|
| Source files analyzed | [count] |
| Legacy docs inventoried | [count] |
| Drift score | X% |
| Beads issues created | [count] |
| Tech debt items imported | [count] |

## Generated Artifacts

- `loa-grimoire/reality/` - Code reality extraction
- `loa-grimoire/legacy/` - Legacy doc inventory
- `loa-grimoire/drift-report.md` - Drift analysis
- `loa-grimoire/prd.md` - Product Requirements (code-grounded)
- `loa-grimoire/sdd.md` - System Design (code-grounded)

## Next Steps

1. Run `bd list --label migration` to see migration tasks
2. Review `drift-report.md` for critical issues
3. Schedule team review of PRD and SDD
4. Run `/sprint-plan` to create maintenance sprint
```
</workflow>

<parallel_execution>
## When to Split

- SMALL (<5,000 lines): Sequential
- MEDIUM (5,000-15,000 lines): Consider splitting phases 1-3
- LARGE (>15,000 lines): MUST split by directory

## Splitting Strategy: By Source Directory

For large codebases, spawn parallel agents per top-level directory:

```
Agent 1: "Extract reality from src/api/**:
- Find all routes and endpoints
- Extract data models
- List env vars used
Return: Structured summary with file:line evidence"

Agent 2: "Extract reality from src/auth/**:
- Find auth methods and strategies
- Extract role/permission definitions
- List security patterns
Return: Structured summary with file:line evidence"
```

## Consolidation

1. Merge reality extractions from all agents
2. Deduplicate findings
3. Generate unified drift report
4. Create combined PRD and SDD
</parallel_execution>

<output_format>
Final output at `loa-grimoire/drift-report.md` with:
- Executive Summary
- Drift Score
- Category breakdown
- Critical items with evidence
- Recommendations

Plus `prd.md` and `sdd.md` with code evidence citations.
</output_format>

<success_criteria>
- **Specific**: Every claim has file:line evidence
- **Measurable**: Drift score calculated
- **Achievable**: All code analyzed
- **Relevant**: Artifacts ready for team review
- **Time-bound**: Completion within 90 minutes
</success_criteria>

<checklists>
See `resources/drift-checklist.md` for complete verification checklists.

**Red Flags (require clarification):**
- Code with no comments or documentation
- Multiple implementations of same feature
- Dead code or unused exports
- Circular dependencies
</checklists>
