# Drift Analysis Checklist

Use this checklist to systematically verify documentation accuracy against actual code.

## API Drift

- [ ] All documented endpoints exist in code
- [ ] All code endpoints are documented
- [ ] HTTP methods match (GET/POST/PUT/DELETE/PATCH)
- [ ] URL paths match exactly (including version prefixes)
- [ ] Request body types match documentation
- [ ] Response types match documentation
- [ ] Query parameters match documentation
- [ ] Authentication requirements match
- [ ] Rate limiting documented correctly

## Data Model Drift

- [ ] All documented entities exist in schema
- [ ] All schema entities are documented
- [ ] Field names match exactly
- [ ] Field types match (string, number, boolean, etc.)
- [ ] Required/optional status matches
- [ ] Default values documented correctly
- [ ] Relationships (foreign keys, joins) match
- [ ] Indexes documented if relevant
- [ ] Constraints (unique, nullable) match

## Feature Drift

- [ ] All documented features have implementing code
- [ ] All code features are documented
- [ ] Feature flags documented and match code
- [ ] Feature toggle states documented
- [ ] User permissions per feature match documentation
- [ ] Feature dependencies documented
- [ ] Deprecated features marked in both code and docs

## Architecture Drift

- [ ] Documented services exist in codebase
- [ ] All deployed services are documented
- [ ] Service communication patterns match (REST/gRPC/events)
- [ ] External dependencies match env vars
- [ ] Database technology matches documentation
- [ ] Cache layer documented correctly
- [ ] Message queue configuration matches
- [ ] Third-party integrations documented

## Environment Drift

- [ ] All env vars in code are documented
- [ ] All documented env vars are used
- [ ] Default values match
- [ ] Required/optional status correct
- [ ] Sensitive vars marked appropriately
- [ ] Environment-specific values documented (dev/staging/prod)

## Security Drift

- [ ] Authentication methods match documentation
- [ ] Authorization model (RBAC/ABAC) documented correctly
- [ ] API key requirements match
- [ ] OAuth scopes documented
- [ ] Rate limiting documented
- [ ] CORS configuration documented
- [ ] Security headers documented

---

## Severity Classification

| Severity | Definition | Action | Timeline |
|----------|------------|--------|----------|
| **Critical** | Core feature ghost/shadow, security misconfiguration | P0 - Block release | Immediate |
| **High** | Important feature ghost/shadow, auth drift | P1 - Must fix | This sprint |
| **Medium** | Supporting feature drift, minor inaccuracies | P2 - Should fix | Next sprint |
| **Low** | Documentation wording, style issues | P3 - Nice to have | Backlog |
| **Info** | Outdated examples, cosmetic issues | Note only | Optional |

---

## Drift Scoring Formula

```
Drift Score = (Ghosts + Shadows) / Total Documented Items × 100
```

| Score | Rating | Interpretation |
|-------|--------|----------------|
| 0-10% | Excellent | Documentation is current |
| 11-25% | Good | Minor updates needed |
| 26-50% | Fair | Significant updates required |
| 51-75% | Poor | Major documentation effort needed |
| 76-100% | Critical | Documentation unreliable |

---

## Evidence Requirements

Every drift finding must include:

### For Ghosts (documented but missing)
```markdown
- **Item**: [Feature/endpoint/model name]
- **Documented at**: [file:line in legacy docs]
- **Documentation claim**: "[exact quote]"
- **Code search performed**: `grep -rn "[search term]" --include="*.ts"`
- **Result**: Not found in codebase
- **Verdict**: GHOST - Remove from documentation
```

### For Shadows (exist but undocumented)
```markdown
- **Item**: [Feature/endpoint/model name]
- **Found at**: [file:line in code]
- **Code excerpt**:
  ```typescript
  // Actual code snippet
  ```
- **Legacy doc search**: [files checked]
- **Result**: Not documented
- **Verdict**: SHADOW - Add to documentation
```

### For Stale (partially matches)
```markdown
- **Item**: [Feature/endpoint/model name]
- **Documented at**: [file:line in legacy docs]
- **Documentation says**: "[exact quote]"
- **Code at**: [file:line]
- **Code shows**: "[actual behavior]"
- **Discrepancy**: [specific difference]
- **Verdict**: STALE - Update documentation
```

---

## Verification Commands

### Find all API routes
```bash
# TypeScript/JavaScript (Express, NestJS)
grep -rn "@Get\|@Post\|@Put\|@Delete\|router\." --include="*.ts" --include="*.js"

# Python (Flask, FastAPI)
grep -rn "@app\.route\|@router\." --include="*.py"

# Go (Gin, Echo)
grep -rn "\.GET\|\.POST\|\.PUT\|\.DELETE" --include="*.go"
```

### Find all data models
```bash
# Prisma
grep -rn "^model " --include="*.prisma"

# TypeORM
grep -rn "@Entity\|@Column" --include="*.ts"

# SQLAlchemy
grep -rn "class.*Model\|Column(" --include="*.py"
```

### Find all env var usage
```bash
# JavaScript/TypeScript
grep -roh 'process\.env\.\w\+' --include="*.ts" --include="*.js" | sort -u

# Python
grep -roh "os\.environ\['\w\+'\]\|os\.getenv('\w\+')" --include="*.py" | sort -u

# Go
grep -roh 'os\.Getenv("\w\+")' --include="*.go" | sort -u
```

### Find all TODOs/FIXMEs
```bash
grep -rn "TODO\|FIXME\|HACK\|XXX\|BUG" --include="*.ts" --include="*.js" --include="*.py" --include="*.go"
```

---

## Post-Analysis Actions

1. **Create Beads issues** for all Critical and High severity drift
2. **Update drift-report.md** with findings
3. **Generate PRD/SDD** with correct code evidence
4. **Schedule review** with stakeholders for validation
5. **Set up drift monitoring** via `.claude/scripts/detect-drift.sh`
