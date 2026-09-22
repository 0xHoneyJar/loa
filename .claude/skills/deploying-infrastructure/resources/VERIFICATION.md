# Pre-Deployment Verification Reference

Full checklist, exact commands, and staging test matrix for `deploying-infrastructure`. See SKILL.md § Pre-Deployment Verification for the blocking-gate summary.

## Documentation Checklist

| Document | Verification | Blocking? |
|----------|--------------|-----------|
| CHANGELOG.md | Version set (not [Unreleased]) | **YES** |
| CHANGELOG.md | All sprint tasks documented | **YES** |
| CHANGELOG.md | Breaking changes section if applicable | **YES** |
| README.md | Features match release | **YES** |
| README.md | Quick start still valid | No |
| README.md | All links working | No |
| INSTALLATION.md | Dependencies current | **YES** |
| INSTALLATION.md | Setup instructions valid | No |

```bash
# Check version is set
head -20 CHANGELOG.md | grep -E "^\[?[0-9]+\.[0-9]+\.[0-9]+\]?"

# Verify not still [Unreleased]
! grep -q "^\## \[Unreleased\]$" CHANGELOG.md || echo "WARNING: Version not finalized"
```

Required CHANGELOG sections: version number with date; Added; Changed; Fixed; Security (if applicable); Breaking Changes (if applicable).

```bash
# Check features mentioned match implementation
grep -c "## Features\|### Features" README.md
```

Deployment documentation locations:

| Document | Location | Purpose |
|----------|----------|---------|
| Environment vars | `grimoires/loa/deployment/` | Required env vars listed |
| Rollback procedure | `grimoires/loa/deployment/runbooks/` | Step-by-step rollback |
| Health checks | `grimoires/loa/deployment/` | Endpoints to verify |
| Breaking changes | CHANGELOG.md | Migration steps if needed |

## Code and Infrastructure Checklist

| Check | Command | Pass Criteria | Blocking? |
|-------|---------|---------------|-----------|
| Full test suite | `npm test` / `pytest` / equivalent | All tests pass | **YES** |
| Build succeeds | `npm run build` / `make build` | Exit code 0, no errors | **YES** |
| Type check | `npm run typecheck` / `mypy` | No type errors | **YES** |
| Lint | `npm run lint` / `flake8` | No errors (warnings OK) | No |
| Security scan | `npm audit` / `safety check` | No critical/high vulns | **YES** |
| E2E tests | `npm run test:e2e` / `pytest e2e/` | All scenarios pass | **YES** |
| Staging deploy | Deploy to staging | Successful deployment | **YES** |
| Smoke tests | Hit key endpoints | 200 responses | **YES** |

| Check | Method | Pass Criteria |
|-------|--------|---------------|
| IaC validation | `terraform validate` | No errors |
| Plan preview | `terraform plan` | No unexpected changes |
| Security groups | Review inbound rules | Minimum necessary ports |
| Secrets | `.claude/scripts/search-orchestrator.sh regex "password\|secret\|key\|token\|api_key" src/` | No hardcoded secrets |
| Resource limits | Review container specs | Memory/CPU limits set |
| Health checks | Review k8s/ECS configs | Liveness/readiness defined |

## Staging Verification Checklist

```markdown
### Application Health
- [ ] App starts without errors
- [ ] Health endpoint returns 200
- [ ] Database connection works
- [ ] Cache connection works
- [ ] External API connections work

### Core Flows
- [ ] User registration/login works
- [ ] Primary feature X works end-to-end
- [ ] Payment flow works (if applicable)
- [ ] Error pages render correctly

### Performance
- [ ] Response time <500ms for key endpoints
- [ ] No memory leaks observed over 10 minutes
- [ ] Database queries <100ms

### Security
- [ ] HTTPS enforced
- [ ] CORS configured correctly
- [ ] Auth tokens validated
- [ ] Rate limiting active
```

## E2E Test Categories

| Category | What to Test | Example |
|----------|--------------|---------|
| Happy Path | Core user journey works | User signup → login → feature use |
| Error Handling | Graceful degradation | Invalid input → proper error message |
| Auth Boundaries | Protected routes secure | Unauthenticated → 401 response |
| Data Integrity | CRUD operations complete | Create → Read → Update → Delete |
| Integration Points | External services work | API call → response processed |

## Deployment Report Template

Fill every field from the actual run's tool output — an unfilled placeholder is more honest than an invented number.

```markdown
## E2E Verification Results

### Test Suite
- **Total tests:** <count>
- **Passed:** <count>
- **Failed:** <count>
- **Skipped:** <count, with tracking ticket if any>

### E2E Scenarios
| Scenario | Status | Duration |
|----------|--------|----------|
| <scenario> | <PASS/FAIL> | <duration> |

### Staging Smoke Tests
- <endpoint>: <status> (<latency>)

### Infrastructure Validation
- terraform validate: <result>
- terraform plan: <result>
- Security scan: <result>
```

## Manual Verification (for what automated tests don't cover)

```markdown
1. Visual regression: homepage, mobile layout, dark mode (if applicable)
2. Edge cases: empty state, large-dataset pagination, concurrent users
3. Integration: webhooks fire, email notifications send, push notifications work
```

## Blocking Conditions

Do not deploy if: any test fails without a documented known-issue ticket; the security scan shows CRITICAL or HIGH vulnerabilities; staging smoke tests fail; infrastructure validation errors; type check or build fails; the CHANGELOG still shows `[Unreleased]` or is missing sprint-task entries; breaking changes lack a migration path; README features don't match the release; INSTALLATION.md dependencies are outdated; required environment variables are undocumented.

May proceed with caution if: only LOW security warnings; skipped tests have documented reasons and tracking tickets; lint warnings (not errors).
