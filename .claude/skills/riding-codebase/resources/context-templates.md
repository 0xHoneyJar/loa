# Context Templates

Templates for user-provided context files in `grimoires/loa/context/`.

---

## architecture-*.md Template

```markdown
# Architecture Context

> Add architectural beliefs, decisions, and system design knowledge here.
> The Loa will verify these claims against actual code.

## Tech Stack
- **Language**:
- **Framework**:
- **Database**:
- **Key Libraries**:

## Module Boundaries

### Core Modules
| Module | Purpose | Entry Point |
|--------|---------|-------------|
| | | |

### Data Flow
```
[Describe how data flows through the system]
```

## Key Decisions

### ADR-001: [Decision Title]
- **Status**: Accepted
- **Context**:
- **Decision**:
- **Consequences**:

## External Dependencies
| Service | Purpose | Credentials Required |
|---------|---------|---------------------|
| | | |
```

---

## stakeholder-*.md Template

```markdown
# Stakeholder Context

> Business priorities and requirements from stakeholder discussions.
> These become features to verify in code.

## Primary Stakeholders
| Name/Role | Priority | Key Concern |
|-----------|----------|-------------|
| | | |

## Business Priorities (Ranked)
1.
2.
3.

## Critical Features
| Feature | Priority | Stakeholder | Status |
|---------|----------|-------------|--------|
| | | | |

## Known Pain Points
-
-

## Success Metrics
| Metric | Current | Target |
|--------|---------|--------|
| | | |
```

---

## tribal-*.md Template

```markdown
# Tribal Knowledge

> Unwritten rules, gotchas, and institutional knowledge.
> CRITICAL: The Loa will look for evidence of these in code.

## ⚠️ Don't Touch These
| Area | Reason | Evidence in Code |
|------|--------|-----------------|
| | | |

## Known Gotchas
| Gotcha | Why It Happens | Workaround |
|--------|----------------|------------|
| | | |

## Historical Context
| Pattern/Code | Why It Exists | Can It Be Changed? |
|--------------|---------------|-------------------|
| | | |

## Onboarding Warnings
> What would you tell a new developer on day one?

1.
2.
3.

## The Scary Parts
| Area | Why Scary | Risk Level |
|------|-----------|------------|
| | | |
```

---

## roadmap-*.md Template

```markdown
# Roadmap Context

> Planned features, deprecations, and migration paths.
> Helps distinguish WIP code from abandoned code.

## Planned Features
| Feature | Timeline | Dependencies | Status |
|---------|----------|--------------|--------|
| | | | |

## Work in Progress
| WIP Area | Owner | Expected Completion | Notes |
|----------|-------|---------------------|-------|
| | | | |

## Planned Deprecations
| Item | Deprecation Date | Replacement | Migration Path |
|------|-----------------|-------------|----------------|
| | | | |

## Technical Debt Backlog
| Item | Priority | Effort | Blocked By |
|------|----------|--------|------------|
| | | | |
```

---

## constraints-*.md Template

```markdown
# Constraints Context

> Technical and business limitations that affect design decisions.

## Technical Constraints
| Constraint | Reason | Impact |
|------------|--------|--------|
| | | |

## Business Constraints
| Constraint | Reason | Impact |
|------------|--------|--------|
| | | |

## Compliance Requirements
| Requirement | Standard | Evidence Needed |
|-------------|----------|-----------------|
| | | |

## Performance Requirements
| Metric | Threshold | Current | Critical? |
|--------|-----------|---------|-----------|
| | | | |

## Resource Constraints
| Resource | Limit | Current Usage |
|----------|-------|---------------|
| | | |
```

---

## integration-*.md Template

```markdown
# Integration Context

> External services, APIs, and system integrations.

## External Services
| Service | Purpose | Auth Method | Env Var |
|---------|---------|-------------|---------|
| | | | |

## API Integrations
| API | Version | Rate Limit | Critical? |
|-----|---------|------------|-----------|
| | | | |

## Webhooks
| Source | Endpoint | Payload Type |
|--------|----------|--------------|
| | | |

## Event Queues
| Queue | Purpose | Consumer |
|-------|---------|----------|
| | | |
```

---

## File Naming Conventions

| Prefix | Purpose | Example |
|--------|---------|---------|
| `architecture-` | System design beliefs | `architecture-data-flow.md` |
| `stakeholder-` | Business priorities | `stakeholder-q4-priorities.md` |
| `tribal-` | Unwritten rules, gotchas | `tribal-dont-touch.md` |
| `roadmap-` | Planned features, deprecations | `roadmap-2024.md` |
| `constraints-` | Technical/business limits | `constraints-compliance.md` |
| `integration-` | External services | `integration-stripe.md` |

---

## Context Coverage Analysis

After adding context files, the Loa will generate `context-coverage.md`:

```markdown
# Context Coverage Analysis

## Files Analyzed
| File | Topics Covered | Claims Extracted |
|------|----------------|------------------|
| | | |

## Interview Topics Covered (will skip)
- ✅ [topic]

## Gaps to Explore (will ask)
- ❓ [topic]

## Claims to Verify
| Claim | Source | Verification Strategy |
|-------|--------|----------------------|
| | | |
```
