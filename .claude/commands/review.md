---
name: review
description: Review and audit your work
output: Review results and audit approval
command_type: workflow
---

# /review - Combined Review + Audit

## Purpose

Review and audit your work in one flow. Runs code review first, then automatically proceeds to security audit if the review passes. Zero arguments needed.

**This is a Golden Path command.** It routes to the existing truename commands (`/review-sprint` + `/audit-sprint`) with automatic target detection.

## Invocation

```
/review                 # Review current sprint (auto-detected)
/review sprint-2        # Override: review specific sprint
/review --skip-audit    # Code review only (skip security audit)
```

## Workflow

### 1. Detect Review Target

```bash
source .claude/scripts/golden-path.sh
target=$(golden_detect_review_target)
```

If user provided an override argument, use that instead.

### 2. Run Code Review

Execute `/review-sprint {target}`.

### 3. Check Review Result

After the review completes, check the feedback file:

```bash
feedback_file="grimoires/loa/a2a/${target}/engineer-feedback.md"
```

| Result | Action |
|--------|--------|
| Review approved ("All good") | Continue to audit (Step 4) |
| Review has findings | Show findings, stop. User fixes and re-runs `/review`. |
| `--skip-audit` flag | Stop after review regardless |

### 4. Run Security Audit

If review passed and `--skip-audit` not set:

Execute `/audit-sprint {target}`.

### 5. Report Combined Result

```
Review & Audit Results for sprint-2:

  Code Review:     ✓ Approved
  Security Audit:  ✓ APPROVED - LET'S FUCKING GO

All clear. Next: /build (if more sprints) or /ship
```

## Arguments

| Argument | Description |
|----------|-------------|
| `sprint-N` | Override: review a specific sprint |
| `--skip-audit` | Run code review only (truename: `/review-sprint`) |
| (none) | Auto-detect review target |

## Error Handling

| Error | Response |
|-------|----------|
| Nothing to review | "Nothing to review yet. Run /build first." |
| Review has findings | Show findings, suggest fixing and re-running `/review` |
| Audit has findings | Show findings, suggest fixing and re-running `/review` |

## Examples

### Full Flow (Pass)
```
/review

  Reviewing sprint-2 (auto-detected)

  Step 1: Code Review
  → Running /review-sprint sprint-2
  [... review executes ...]
  ✓ Code review approved

  Step 2: Security Audit
  → Running /audit-sprint sprint-2
  [... audit executes ...]
  ✓ Security audit approved

  All clear!
  Next: /build (sprint-3 remaining) or /ship (if all done)
```

### Review Has Findings
```
/review

  Reviewing sprint-2 (auto-detected)

  Step 1: Code Review
  → Running /review-sprint sprint-2
  [... review executes ...]

  ⚠ Code review found 3 issues.
  Fix the issues and run /review again.
```

### Skip Audit
```
/review --skip-audit

  Reviewing sprint-2 (auto-detected)
  → Running /review-sprint sprint-2
  [... review only, no audit ...]
```
