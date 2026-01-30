# Validate Command

## Purpose

Run intelligent validation subagents to check implementation quality before review.

## Invocation

```
/validate                       # Run all subagents on sprint scope
/validate architecture          # Run architecture-validator only
/validate security              # Run security-scanner only
/validate tests                 # Run test-adequacy-reviewer only
/validate docs                  # Run documentation-coherence only
/validate docs --sprint         # Sprint-level documentation verification
/validate docs --task 2         # Specific task documentation check
/validate goals                 # Run goal-validator only
/validate goals sprint-3        # Run goal-validator for specific sprint
/validate architecture src/api/ # Run on specific scope
```

## Arguments

| Argument | Description | Required | Default |
|----------|-------------|----------|---------|
| `type` | Subagent to run: `architecture`, `security`, `tests`, `goals`, `all` | No | `all` |
| `scope` | Path or glob pattern to validate | No | Sprint context or git diff |
| `sprint` | Sprint to validate (for `goals` type) | No | Current sprint |

## Subagents

| Type | Subagent | Purpose |
|------|----------|---------|
| `architecture` | architecture-validator | Verify implementation matches SDD |
| `security` | security-scanner | Detect security vulnerabilities |
| `tests` | test-adequacy-reviewer | Assess test quality and coverage |
| `docs` | documentation-coherence | Validate documentation updated with task |
| `goals` | goal-validator | Verify PRD goals achieved through implementation |
| `all` | All of the above | Complete validation suite |

## Process

1. **Parse Arguments**: Determine which subagent(s) to run and scope
2. **Determine Scope**:
   - If explicit path provided, use it
   - Else, extract files from current sprint in `sprint.md`
   - Else, use `git diff HEAD~1 --name-only`
3. **Load Subagent**: Read from `.claude/subagents/{type}.md`
4. **Execute Checks**: Run validation checks on scoped files
5. **Generate Report**: Write to `grimoires/loa/a2a/subagent-reports/{type}-{date}.md`
6. **Summarize**: Display findings in response

## Output Location

Reports written to: `grimoires/loa/a2a/subagent-reports/`

Naming convention: `{subagent-name}-{YYYY-MM-DD}.md`

## Verdict Handling

### Blocking Verdicts

These verdicts stop the workflow and require fixes:

| Subagent | Blocking Verdict |
|----------|------------------|
| architecture-validator | CRITICAL_VIOLATION |
| security-scanner | CRITICAL, HIGH |
| test-adequacy-reviewer | INSUFFICIENT |
| documentation-coherence | ACTION_REQUIRED |
| goal-validator | GOAL_BLOCKED |

### Non-Blocking Verdicts

These verdicts are informational:

| Subagent | Non-Blocking Verdict |
|----------|----------------------|
| architecture-validator | DRIFT_DETECTED |
| security-scanner | MEDIUM, LOW |
| test-adequacy-reviewer | WEAK |
| documentation-coherence | NEEDS_UPDATE, COHERENT |
| goal-validator | GOAL_AT_RISK, GOAL_ACHIEVED |

## Examples

### Run All Validators

```
/validate
```

Output:
```
Running validation suite on sprint-2 scope...

Architecture Validation: COMPLIANT
  - Directory structure: PASS
  - Dependency flow: PASS
  - API compliance: PASS

Security Scan: No issues found
  - Input validation: PASS
  - Auth checks: PASS

Test Adequacy: ADEQUATE
  - Coverage: 85%
  - Edge cases: Present

Reports saved to grimoires/loa/a2a/subagent-reports/
```

### Run Single Validator

```
/validate architecture
```

### Run on Specific Path

```
/validate security src/auth/
```

### Run Goal Validation

```
/validate goals
```

Output:
```
Running goal validation on current sprint...

Goal G-1: Prevent silent goal failures
  Status: ACHIEVED
  Tasks: Sprint 1: 1.1, 1.2, 1.3 ✓
  Evidence: E2E validation passed

Goal G-2: Detect integration gaps
  Status: AT_RISK
  Tasks: Sprint 2: 2.1, 2.2 ✓
  Concern: No E2E validation task found

Overall Verdict: GOAL_AT_RISK

Report saved to grimoires/loa/a2a/subagent-reports/goal-validation-2026-01-23.md
```

## Error Messages

| Error | Cause | Resolution |
|-------|-------|------------|
| "Subagent not found" | Invalid type argument | Use: architecture, security, tests, goals, all |
| "SDD not found" | Missing sdd.md | Run `/architect` first |
| "PRD not found" | Missing prd.md (for goals) | Run `/plan-and-analyze` first |
| "Sprint plan not found" | Missing sprint.md (for goals) | Run `/sprint-plan` first |
| "No files in scope" | Empty scope | Specify path or make changes first |

## Integration

### With Quality Gates

`/validate` integrates with the Loa quality pipeline:

```
/implement sprint-N
      ↓
/validate (optional, recommended)
      ↓
/review-sprint sprint-N
      ↓
/audit-sprint sprint-N
```

### Automatic Execution

Validation can run automatically:
- After `/implement` (if configured)
- Before `/review-sprint` approval (recommended)

Configure in `.loa.config.yaml`:

```yaml
subagents:
  auto_run_pre_review: true
```

## Protocol Reference

See `.claude/protocols/subagent-invocation.md` for the full protocol.
