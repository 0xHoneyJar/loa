# Decision Lineage

> **Source**: Team of Rivals pattern (arXiv:2601.14351)
> **Purpose**: Traceable decision history for auditability and learning

## Overview

Decision Lineage captures every significant decision made during Loa execution. This enables:

1. **Auditability** — Why was this built this way?
2. **Learning** — What worked? What didn't?
3. **Onboarding** — New team members understand context
4. **Reversal** — Safe to change if we know why it was chosen

## The Problem

Without decision tracking:
- Decisions are scattered in PRD/SDD prose
- Rationale is lost when people leave
- Alternatives considered are forgotten
- "Why did we do this?" has no answer

## Solution: decisions.yaml

Each project maintains `grimoires/loa/decisions.yaml` with structured entries:

```yaml
decisions:
  - id: DEC-0001
    timestamp: "2026-01-31T09:00:00Z"
    phase: architecture
    category: technology
    summary: "Use PostgreSQL with pgvector"
    decision: "PostgreSQL 15 with pgvector extension"
    rationale: "Mature, familiar, single database"
    alternatives_considered:
      - option: "Pinecone"
        rejected_because: "External dependency, cost"
    consequences:
      positive: ["Single DB", "Familiar ops"]
      negative: ["Performance ceiling at 1M vectors"]
```

## When to Record Decisions

### Always Record

| Phase | Decision Types |
|-------|----------------|
| **Discovery** | Scope cuts, feature prioritization, MVP definition |
| **Architecture** | Technology choices, patterns, integrations |
| **Sprint Planning** | Task sequencing, dependency resolution |
| **Implementation** | Algorithm choices, library selections |
| **Review** | Approved deviations, deferred improvements |

### Don't Record

- Routine implementation details
- Style/formatting choices
- Obvious decisions with no alternatives

### Rule of Thumb

> "Would someone ask 'why?' about this in 6 months?"
> 
> If yes → record it.

## Decision Structure

### Required Fields

| Field | Purpose |
|-------|---------|
| `id` | Unique identifier (DEC-0001) |
| `timestamp` | When decided |
| `phase` | Loa phase (discovery, architecture, etc.) |
| `category` | Type (architecture, technology, scope, etc.) |
| `summary` | One-line description |
| `decision` | What was decided |
| `rationale` | Why this option |
| `alternatives_considered` | What else was evaluated (minimum 1) |

### Optional Fields

| Field | Purpose |
|-------|---------|
| `consequences` | Expected positive/negative outcomes |
| `grounding` | Source files and external references |
| `status` | active, superseded, deprecated |
| `review_date` | When to revisit this decision |
| `tags` | Searchable categorization |

## Integration with Phases

### /plan-and-analyze

Records decisions about:
- Scope boundaries (what's in/out)
- User prioritization
- MVP feature set

### /architect

Records decisions about:
- Technology stack
- Architecture patterns
- Integration approaches
- Security model

### /sprint-plan

Records decisions about:
- Task sequencing
- Dependency resolution
- Parallel work splits

### /review-sprint

Records decisions about:
- Approved technical debt
- Deferred improvements
- Accepted tradeoffs

## Querying Decisions

### By Phase

```bash
yq '.decisions[] | select(.phase == "architecture")' grimoires/loa/decisions.yaml
```

### By Category

```bash
yq '.decisions[] | select(.category == "security")' grimoires/loa/decisions.yaml
```

### Active Only

```bash
yq '.decisions[] | select(.status == "active" or .status == null)' grimoires/loa/decisions.yaml
```

## Lifecycle

### During Development

- Decisions are append-only
- Status changes allowed (active → superseded)
- No deletions

### During /archive-cycle

- Review all decisions
- Mark obsolete as deprecated
- Extract learnings for compound system
- Optionally prune deprecated entries

## Relationship to ADRs

Decision Lineage is complementary to Architecture Decision Records (ADRs):

| Aspect | decisions.yaml | ADRs |
|--------|----------------|------|
| Format | Structured YAML | Prose Markdown |
| Scope | All phases | Architecture only |
| Detail | Compact | Verbose |
| Query | Machine-readable | Human-readable |

For major architectural decisions, create both:
1. Entry in decisions.yaml (structured)
2. ADR in docs/adr/ (detailed prose)

## Schema

Full schema at `.claude/schemas/decisions.schema.json`.

Validate with:

```bash
# Using ajv-cli
ajv validate -s .claude/schemas/decisions.schema.json -d grimoires/loa/decisions.yaml
```
