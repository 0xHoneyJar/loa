# Analysis Checklists

> Extracted from `.claude/skills/riding-codebase/SKILL.md` (Phases 4, 5, and 9).
> These are the detailed report templates used during the /ride workflow.

---

## Phase 4: Three-Way Drift Analysis Report Template

Output file: `grimoires/loa/drift-report.md`

```markdown
# Three-Way Drift Report

> Generated: [timestamp]
> Target: [repo path]

## Truth Hierarchy Reminder

```
CODE wins every conflict. Always.
```

## Summary

| Category | Code Reality | Legacy Docs | User Context | Aligned |
|----------|--------------|-------------|--------------|---------|
| API Endpoints | X | Y | Z | W% |
| Data Models | X | Y | Z | W% |
| Features | X | Y | Z | W% |

## Drift Score: X% (lower is better)

## Drift Breakdown by Type

| Type | Count | Impact Level |
|------|-------|--------------|
| Missing (code exists, no docs) | N | Medium |
| Stale (docs outdated) | N | High |
| Hallucinated (docs claim non-existent) | N | Critical |
| Ghost (feature never existed) | N | Critical |
| Shadow (undocumented code) | N | Medium |

## Critical Drift Items

### Hallucinated Documentation (CRITICAL)

**These claims in legacy docs are NOT supported by code:**

| Claim | Source Doc | Verification Attempt | Verdict |
|-------|------------|---------------------|---------|
| "OAuth2 authentication" | legacy/auth.md:L15 | `grep -r "oauth\|OAuth" --include="*.ts"` = 0 results | HALLUCINATED |
| "Batch rebate processing" | legacy/rebates.md:L23 | Code shows individual processing only | HALLUCINATED |
| "CubQuest badge tiers" | legacy/rebates.md:L45 | Badge logic differs from documentation | STALE (partially wrong) |

### Stale Documentation (HIGH)

**These docs exist but code has changed:**

| Doc Claim | Source | Code Reality | Drift Type |
|-----------|--------|--------------|------------|
| "Uses Redis for caching" | legacy/arch.md:L30 | Now uses in-memory Map | STALE |
| "Rate limit: 100 req/min" | legacy/api.md:L12 | Rate limit is 60 req/min | STALE |

### Missing Documentation (MEDIUM)

**Code features without documentation:**

| Feature | Location | Needs Docs |
|---------|----------|------------|
| RateLimiter middleware | src/middleware/rate.ts:45 | Yes - critical |
| BatchProcessor | src/services/batch.ts:1-200 | Yes - core business logic |

### Ghosts (Documented/Claimed but Missing in Code)
| Item | Claimed By | Evidence Searched | Verdict |
|------|------------|-------------------|---------|
| "Feature X" | legacy/api.md | `grep -r "FeatureX"` found nothing | GHOST |

### Shadows (In Code but Undocumented)
| Item | Location | Needs Documentation |
|------|----------|---------------------|
| RateLimiter | src/middleware/rate.ts:45 | Yes - critical infrastructure |

### Conflicts (Context + Docs disagree with Code)
| Claim | Sources | Code Reality | Confidence |
|-------|---------|--------------|------------|
| "Uses PostgreSQL" | context + legacy | MySQL in DATABASE_URL | HIGH |

## Verification Evidence

### Search Commands Executed

| Claim Searched | Command | Result |
|----------------|---------|--------|
| OAuth | `grep -ri "oauth" --include="*.ts" --include="*.js"` | 0 matches |
| BadgeTier | `grep -ri "badgetier\|badge.*tier" --include="*.sol"` | 3 matches (different implementation) |

## Recommendations

### Immediate Actions (Hallucinated/Stale)
1. **Remove** hallucinated claims from legacy docs
2. **Update** stale documentation OR deprecate entirely
3. **Flag** for product team: Features promised but not delivered

### Documentation Actions (Missing/Shadow)
1. Document critical middleware: RateLimiter
2. Add architecture docs for undocumented services
```

---

## Phase 5: Consistency Analysis Report Template

Output file: `grimoires/loa/consistency-report.md`

```markdown
# Consistency Analysis

> Generated: [DATE]
> Target: [repo]

## Naming Patterns Detected

### Entity/Contract Naming
| Pattern | Count | Examples | Consistency |
|---------|-------|----------|-------------|
| `{Domain}{Type}` | N | `SFPosition`, `SFVaultStats` | Consistent |
| `{Type}` only | N | `Transfer`, `Mint` | Mixed |
| `I{Name}` interfaces | N | `IVault`, `IStrategy` | Consistent |

### Function Naming
| Pattern | Count | Examples |
|---------|-------|----------|
| `camelCase` | N | `getBalance`, `setOwner` |
| `snake_case` | N | `get_balance` |

### File Naming
| Pattern | Count | Examples |
|---------|-------|----------|
| `PascalCase.sol` | N | `SFVault.sol` |
| `kebab-case.ts` | N | `vault-manager.ts` |

## Consistency Score: X/10

**Scoring Criteria:**
- 10: Single consistent pattern throughout
- 7-9: Minor deviations, clear dominant pattern
- 4-6: Mixed patterns, no clear standard
- 1-3: Inconsistent, multiple competing patterns

## Pattern Conflicts Detected

| Conflict | Examples | Impact |
|----------|----------|--------|
| Mixed naming | `UserProfile` vs `user_data` | Cognitive overhead |

## Improvement Opportunities (Non-Breaking)
| Change | Type | Impact |
|--------|------|--------|
| [Specific suggestion] | Additive | [Impact description] |

## Breaking Changes (Flag Only - DO NOT IMPLEMENT)
| Change | Why Breaking | Impact |
|--------|--------------|--------|
| [Specific change] | [Reason] | [Downstream impact] |
```

---

## Phase 9: Trajectory Self-Audit Report Template

Output file: `grimoires/loa/trajectory-audit.md`

```markdown
# Trajectory Self-Audit

> Generated: [DATE]
> Agent: riding-codebase
> Target: [repo]

## Execution Summary

| Phase | Status | Output File | Key Findings |
|-------|--------|-------------|--------------|
| 0 - Preflight | Complete | - | Loa v[X] mounted |
| 1 - Context Discovery | Complete | claims-to-verify.md | [N] claims captured |
| 2 - Code Extraction | Complete | reality/*.txt | [N] routes, [N] entities |
| 2b - Hygiene Audit | Complete | reality/hygiene-report.md | [N] items flagged |
| 3 - Legacy Inventory | Complete | legacy/INVENTORY.md | [N] docs found |
| 4 - Drift Analysis | Complete | drift-report.md | [X]% drift |
| 5 - Consistency | Complete | consistency-report.md | Score: [N]/10 |
| 6 - PRD/SDD Generation | Complete | prd.md, sdd.md | Evidence-grounded |
| 7 - Governance Audit | Complete | governance-report.md | [N] gaps |
| 8 - Legacy Deprecation | Complete | [N] files marked | - |
| 9 - Self-Audit | Complete | trajectory-audit.md | This file |

## Grounding Analysis

### PRD Grounding
| Metric | Count | Percentage |
|--------|-------|------------|
| **[GROUNDED]** claims (file:line citations) | N | X% |
| **[INFERRED]** claims (logical deduction) | N | X% |
| **[ASSUMPTION]** claims (needs validation) | N | X% |
| Total claims | N | 100% |

### SDD Grounding
| Metric | Count | Percentage |
|--------|-------|------------|
| **[GROUNDED]** claims (file:line citations) | N | X% |
| **[INFERRED]** claims (logical deduction) | N | X% |
| **[ASSUMPTION]** claims (needs validation) | N | X% |
| Total claims | N | 100% |

## Claims Requiring Validation

| # | Claim | Location | Type | Validator Needed |
|---|-------|----------|------|------------------|
| 1 | [Claim text] | prd.md:L[N] | ASSUMPTION | [Role] |
| 2 | [Claim text] | sdd.md:L[N] | INFERRED | [Role] |

## Potential Hallucination Check

Review these areas for accuracy:
- [ ] Entity names match actual code (grep verified)
- [ ] Feature descriptions match implementations
- [ ] API endpoints exist as documented
- [ ] Dependencies listed are actually imported

## Reasoning Quality Score: X/10

**Scoring Criteria:**
- 10: 100% grounded, zero assumptions
- 8-9: >90% grounded, assumptions flagged
- 6-7: >75% grounded, some gaps
- 4-5: >50% grounded, significant gaps
- 1-3: <50% grounded, needs re-ride

## Trajectory Log Reference

Full trajectory logged to: `grimoires/loa/a2a/trajectory/riding-[DATE].jsonl`

## Self-Certification

- [ ] All phases completed and outputs generated
- [ ] All claims in PRD/SDD have grounding markers
- [ ] Assumptions explicitly flagged with [ASSUMPTION]
- [ ] Drift report reflects actual code state
- [ ] No hallucinated features or entities
```
