# Structured Notes Protocol

## Overview

The Structured Notes Protocol defines how the autonomous-agent skill manages notes in `grimoires/loa/NOTES.md`. Notes use YAML frontmatter for machine-parseable metadata while maintaining human-readable markdown content.

Reference: Issue #23 - Structured Agentic Memory

## Note Schema

Each note section in NOTES.md follows this structure:

```markdown
---
type: synthesis | observation | decision | blocker | question
created: 2026-01-31T14:00:00Z
expires: 2026-02-07T14:00:00Z  # Optional, based on type
status: active | resolved | expired | superseded
tags: [phase-3, authentication, gate-2]
related: [D-001, B-002]  # Related decisions/blockers
---

## Note Title

Note content in markdown...
```

## Five Note Types

### 1. Synthesis

**Purpose**: Consolidated understanding from multiple sources.

**Expiry**: 7 days (to encourage refresh)

```markdown
---
type: synthesis
created: 2026-01-31T14:00:00Z
expires: 2026-02-07T14:00:00Z
status: active
tags: [authentication, api-design]
---

## Authentication Flow Synthesis

Based on analysis of `src/auth/`, `docs/api.md`, and user context:

1. JWT-based authentication with refresh tokens
2. OAuth2 for third-party integrations
3. API keys for service-to-service calls

**Sources**:
- `src/auth/jwt.ts:45-67`
- `docs/api.md#authentication`
- User context: "prefer OAuth2 for external"
```

### 2. Observation

**Purpose**: Notable finding during execution.

**Expiry**: 14 days

```markdown
---
type: observation
created: 2026-01-31T14:00:00Z
expires: 2026-02-14T14:00:00Z
status: active
tags: [performance, database]
---

## Database Query Performance

Observed during Phase 3 implementation:

- Query at `src/db/users.ts:123` takes 200ms+ on large datasets
- No index on `created_at` column
- Consider adding index in next sprint

**Evidence**: Trajectory log entry #47
```

### 3. Decision

**Purpose**: Architectural or implementation choice made.

**Expiry**: Never (permanent record)

```markdown
---
type: decision
created: 2026-01-31T14:00:00Z
status: active
tags: [architecture, security]
id: D-003
---

## Use Argon2 for Password Hashing

**Decision**: Use Argon2id instead of bcrypt for password hashing.

**Context**: Implementing user authentication in Sprint 1.

**Reasoning**:
1. Argon2 is memory-hard (resistant to GPU attacks)
2. Winner of Password Hashing Competition
3. Recommended by OWASP

**Alternatives Considered**:
- bcrypt: Widely used but older
- scrypt: Good but less adoption

**Consequences**:
- Need to install `argon2` npm package
- Existing passwords need migration plan
```

### 4. Blocker

**Purpose**: Issue preventing progress.

**Expiry**: Until resolved

```markdown
---
type: blocker
created: 2026-01-31T14:00:00Z
status: active  # or resolved
tags: [dependency, external]
id: B-002
resolution_date: null  # Set when resolved
---

## Missing API Credentials

**Blocker**: Cannot test OAuth integration without client credentials.

**Impact**: Phase 3 task 3.4 blocked.

**Attempted**:
- [x] Checked `.env.example` for template
- [x] Asked user in session (no response)
- [ ] Waiting for credentials

**Resolution**: [To be filled when resolved]
```

### 5. Question

**Purpose**: Open question requiring human input.

**Expiry**: 14 days

```markdown
---
type: question
created: 2026-01-31T14:00:00Z
expires: 2026-02-14T14:00:00Z
status: active  # or answered
tags: [requirements, ux]
id: Q-001
---

## Rate Limiting Strategy?

**Question**: What rate limiting approach should we use for the API?

**Options**:
1. **Token bucket**: Smooth traffic, allows bursts
2. **Fixed window**: Simple but can have edge spikes
3. **Sliding window**: Most accurate but more complex

**Recommendation**: Token bucket (option 1) for user-facing API.

**Awaiting**: User confirmation or alternative preference.

**Answer**: [To be filled when answered]
```

## Status Lifecycle

```
active ──┬──▶ resolved    (Blocker fixed, Question answered)
         │
         ├──▶ expired     (TTL exceeded)
         │
         └──▶ superseded  (Replaced by newer note)
```

### Status Transitions

| From | To | Trigger |
|------|-----|---------|
| active | resolved | Blocker cleared, question answered |
| active | expired | Current time > expires date |
| active | superseded | New note replaces old |
| resolved | - | Terminal state |
| expired | - | Terminal state |
| superseded | - | Terminal state |

## Expiry Rules by Type

| Type | Default TTL | Rationale |
|------|-------------|-----------|
| synthesis | 7 days | Encourage fresh analysis |
| observation | 14 days | May become stale |
| decision | never | Permanent record |
| blocker | until resolved | Clear when fixed |
| question | 14 days | Escalate if unanswered |

## Integration with NOTES.md Sections

The structured notes integrate with existing NOTES.md sections:

```markdown
# Agent Working Memory

## Current Focus
<!-- Standard section -->

## Session Log
<!-- Standard section -->

## Decisions
<!-- Populated from type: decision notes -->

| ID | Decision | Reasoning | Date |
|----|----------|-----------|------|
| D-001 | Use JWT | Industry standard | 2026-01-31 |
| D-002 | PostgreSQL | ACID compliance | 2026-01-31 |
| D-003 | Argon2 | Memory-hard hashing | 2026-01-31 |

## Blockers
<!-- Populated from type: blocker notes -->

- [ ] B-001: Missing API credentials [ACTIVE]
- [x] B-002: Docker not installed [RESOLVED 2026-01-30]

## Technical Debt
<!-- From type: observation with tag: tech-debt -->

## Goal Status
<!-- Standard section -->

## Learnings
<!-- From type: synthesis + observation -->

## Session Continuity
<!-- Standard section -->
```

## Programmatic Access

### Query Notes by Type

```bash
# Extract all active decisions
grep -A 20 "^type: decision" grimoires/loa/NOTES.md | grep -B 1 "status: active"
```

### Check for Expired Notes

```bash
# Find expired notes (pseudo-code)
current_time=$(date -Iseconds)
grep -E "^expires:" grimoires/loa/NOTES.md | while read line; do
    expires=$(echo "$line" | cut -d' ' -f2)
    if [[ "$current_time" > "$expires" ]]; then
        echo "EXPIRED: $line"
    fi
done
```

### Note Management in Phase 0

During Preflight:
1. Load NOTES.md
2. Mark expired notes as `status: expired`
3. Surface active blockers
4. Load recovery anchor from Session Continuity

## Configuration

In `.loa.config.yaml`:

```yaml
autonomous_agent:
  structured_notes:
    # Enable structured note management
    enabled: true
    # Notes file location
    notes_file: grimoires/loa/NOTES.md
    # Expiry settings (days)
    expiry:
      synthesis: 7
      observation: 14
      decision: null  # Never expires
      blocker: null   # Until resolved
      question: 14
    # Auto-cleanup expired notes
    auto_cleanup: false
    # Archive location for cleaned notes
    archive_dir: grimoires/loa/archive/notes/
```

## Best Practices

1. **One Note per Topic**: Don't combine unrelated items
2. **Link Related Notes**: Use `related:` field
3. **Tag Consistently**: Use phase/feature tags
4. **Update Status**: Don't leave blockers active when resolved
5. **Cite Sources**: Always include evidence for decisions
6. **Refresh Syntheses**: Re-analyze when synthesis expires
