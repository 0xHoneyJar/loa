# Drift Detection Checklist

Reference checklist for three-way drift analysis during `/ride`.

---

## Drift Categories

| Category | Symbol | Definition |
|----------|--------|------------|
| **Aligned** | ✅ | Code, docs, and context all agree |
| **Ghost** | 👻 | Documented/claimed but NOT in code |
| **Shadow** | 🌑 | In code but NOT documented |
| **Conflict** | ⚠️ | Docs AND context disagree with code |
| **Stale** | 🕸️ | Documentation exists but significantly outdated |

---

## API Endpoints Checklist

### Source: Legacy Documentation
- [ ] Extract all documented endpoints
- [ ] Record HTTP method, path, description

### Source: User Context
- [ ] Extract claimed endpoints from interview
- [ ] Note any "important" or "critical" endpoints mentioned

### Source: Code Reality
- [ ] Grep for route definitions
- [ ] Check framework-specific patterns (Express, FastAPI, etc.)
- [ ] Include middleware-only routes

### Comparison
| Documented | In Context | In Code | Status | Action |
|------------|------------|---------|--------|--------|
| GET /api/users | ✓ mentioned | ✓ exists | ✅ | None |
| POST /api/admin | ✓ documented | - | ❌ missing | 👻 Ghost |
| - | - | DELETE /api/internal | - | 🌑 Shadow |

---

## Data Models Checklist

### Source: Legacy Documentation
- [ ] Extract documented entities/models
- [ ] Note relationships and field types

### Source: User Context
- [ ] Extract mentioned domain entities
- [ ] Note "core" entities emphasized by user

### Source: Code Reality
- [ ] Prisma/TypeORM/Sequelize models
- [ ] GraphQL types
- [ ] Database migrations
- [ ] Interface/Type definitions

### Comparison
| Documented | In Context | In Code | Status | Notes |
|------------|------------|---------|--------|-------|
| User | "main entity" | User model | ✅ | |
| HenloProfile | mentioned | HenloHolder | ⚠️ | Name changed? |
| AdminRole | documented | ❌ | 👻 | Removed? |

---

## Features Checklist

### Source: Legacy Documentation
- [ ] README feature lists
- [ ] API documentation descriptions
- [ ] User guides

### Source: User Context
- [ ] Features mentioned in interview
- [ ] "Critical" or "core" features emphasized
- [ ] Planned but not implemented features

### Source: Code Reality
- [ ] Feature flag checks
- [ ] Route handlers with business logic
- [ ] UI components (if applicable)

### Comparison
| Feature | Documented | Claimed | In Code | Status |
|---------|------------|---------|---------|--------|
| User auth | ✓ | ✓ | ✓ | ✅ |
| Admin panel | ✓ | "planned" | ❌ | 👻 |
| Rate limiting | ❌ | ❌ | ✓ | 🌑 |

---

## Environment Variables Checklist

### Source: Legacy Documentation
- [ ] .env.example if exists
- [ ] README setup instructions
- [ ] Deployment documentation

### Source: User Context
- [ ] Services mentioned requiring API keys
- [ ] Database connections mentioned

### Source: Code Reality
- [ ] process.env.* references
- [ ] Config file parsing
- [ ] Docker/k8s env definitions

### Comparison
| Env Var | Documented | In Code | Status |
|---------|------------|---------|--------|
| DATABASE_URL | ✓ | ✓ | ✅ |
| STRIPE_KEY | ✓ | ❌ | 👻 |
| REDIS_URL | ❌ | ✓ | 🌑 |

---

## Configuration Checklist

### Source: Legacy Documentation
- [ ] Config file documentation
- [ ] Deployment configs

### Source: User Context
- [ ] Configuration patterns mentioned
- [ ] Environment-specific behaviors

### Source: Code Reality
- [ ] Config file parsing
- [ ] Default values
- [ ] Feature flags

---

## Drift Severity Scoring

### Critical (Must Address)
- 👻 **Ghost feature documented as "critical"** - Users may expect it
- 🌑 **Shadow security feature** - Undocumented security controls
- ⚠️ **Conflict in authentication/authorization** - Security risk

### High (Should Address)
- 👻 **Ghost API endpoints** - May cause 404s
- 🌑 **Shadow data models** - Schema drift
- ⚠️ **Conflict in tech stack** - Integration confusion

### Medium (Address When Able)
- 👻 **Ghost features (non-critical)** - Documentation cleanup
- 🌑 **Shadow utilities/helpers** - Add to docs
- 🕸️ **Stale documentation** - Update or remove

### Low (Track)
- Minor naming differences
- Ordering differences
- Formatting inconsistencies

---

## Drift Resolution Strategies

### For Ghosts (👻)
1. **Verify removal was intentional**
   - Check git history for deletion
   - Ask user about feature status
2. **Options**:
   - Remove from documentation
   - Re-implement if needed
   - Document as deprecated

### For Shadows (🌑)
1. **Assess importance**
   - Is it user-facing?
   - Is it security-relevant?
2. **Options**:
   - Add to documentation
   - If internal-only, add code comments
   - If deprecated, add @deprecated annotation

### For Conflicts (⚠️)
1. **Verify code is correct** (Code is truth!)
2. **Options**:
   - Update documentation to match code
   - Update context understanding
   - If code is wrong, create fix task

### For Stale (🕸️)
1. **Assess staleness degree**
   - Minor outdated vs. completely wrong
2. **Options**:
   - Update documentation
   - Add deprecation notice
   - Remove if obsolete

---

## Drift Report Template

```markdown
# Three-Way Drift Report

Generated: [timestamp]
Repository: [path]

## Executive Summary
- Total items analyzed: X
- Aligned: Y (Z%)
- Ghosts: A
- Shadows: B
- Conflicts: C

## Drift Score: X% (lower is better)

## Critical Items (Address Immediately)
| Item | Category | Description | Action |
|------|----------|-------------|--------|

## High Priority Items
| Item | Category | Description | Action |
|------|----------|-------------|--------|

## Full Drift Details
[Detailed breakdown by category]

## Recommendations
1.
2.
3.
```
