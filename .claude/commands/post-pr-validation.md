# Post-PR Validation Loop

**Version**: 1.25.0
**PRD**: `grimoires/loa/prd-post-pr-validation.md`
**SDD**: `grimoires/loa/sdd-post-pr-validation.md`

---

## Overview

The Post-PR Validation Loop automates post-PR quality assurance, ensuring your code is thoroughly reviewed before human review. It runs after PR creation and includes:

1. **Consolidated PR Audit** - Security and quality review of changes
2. **Context Clear** - Fresh context for unbiased testing
3. **E2E Testing** - Build and test verification
4. **Flatline PR Review** - Optional multi-model adversarial review

---

## Quick Start

### Enable in Configuration

```yaml
# .loa.config.yaml
post_pr_validation:
  enabled: true
  phases:
    audit:
      enabled: true
    context_clear:
      enabled: true
    e2e:
      enabled: true
    flatline:
      enabled: false  # Enable for ~$1.50 cost
```

### Manual Invocation

```bash
# Full validation loop
.claude/scripts/post-pr-orchestrator.sh --pr-url https://github.com/org/repo/pull/123

# Dry run (show planned phases)
.claude/scripts/post-pr-orchestrator.sh --dry-run --pr-url https://github.com/org/repo/pull/123

# Resume from checkpoint
.claude/scripts/post-pr-orchestrator.sh --resume --pr-url https://github.com/org/repo/pull/123
```

### Via Simstim

```bash
# Simstim automatically triggers post-PR validation
/simstim grimoires/loa/prd.md

# After context clear, resume with:
/clear
/simstim --resume
```

---

## Commands

### post-pr-orchestrator.sh

Main orchestrator that manages the validation workflow.

| Flag | Description | Default |
|------|-------------|---------|
| `--pr-url <url>` | PR URL (required) | - |
| `--mode <mode>` | `autonomous` or `hitl` | autonomous |
| `--skip-audit` | Skip audit phase | false |
| `--skip-e2e` | Skip E2E testing phase | false |
| `--skip-flatline` | Skip Flatline PR review | false |
| `--dry-run` | Show planned phases without executing | false |
| `--resume` | Continue from checkpoint | false |
| `--timeout <secs>` | Override all phase timeouts | varies |

**Exit Codes:**

| Code | Meaning |
|------|---------|
| 0 | Success (READY_FOR_HITL) |
| 1 | Invalid arguments |
| 2 | Phase timeout |
| 3 | Phase failure (audit/e2e) |
| 4 | Blocker found (Flatline) |
| 5 | Halted by user |

### post-pr-state.sh

State management for the validation loop.

```bash
# Initialize state
post-pr-state.sh init --pr-url https://github.com/org/repo/pull/123

# Get state field (dot notation supported)
post-pr-state.sh get state
post-pr-state.sh get phases.post_pr_audit

# Update phase status
post-pr-state.sh update-phase post_pr_audit completed

# Add marker file
post-pr-state.sh add-marker PR-AUDITED

# Cleanup all state
post-pr-state.sh cleanup
```

### post-pr-audit.sh

Consolidated PR audit with finding classification.

```bash
post-pr-audit.sh --pr-url https://github.com/org/repo/pull/123

# Exit codes:
# 0 = APPROVED
# 1 = CHANGES_REQUIRED (auto-fixable)
# 2 = ESCALATED (complex issues)
# 3 = ERROR
```

### post-pr-e2e.sh

E2E test runner with failure tracking.

```bash
post-pr-e2e.sh --pr-number 123

# With custom commands
post-pr-e2e.sh --pr-number 123 --build-cmd "npm run build" --test-cmd "npm test"

# Exit codes:
# 0 = PASSED
# 1 = FAILED
# 2 = BUILD_FAILED
# 3 = ERROR
```

### post-pr-context-clear.sh

Checkpoint writer for context clearing.

```bash
post-pr-context-clear.sh

# Custom paths
post-pr-context-clear.sh --notes-file grimoires/loa/NOTES.md
```

---

## Phases

### Phase 1: POST_PR_AUDIT

Runs consolidated security and quality audit on PR changes.

**Detects:**
- Hardcoded secrets (high severity)
- Console.log statements (auto-fixable)
- TODO/FIXME comments (auto-fixable)
- Empty catch blocks (medium severity)

**Circuit Breaker:**
- Same finding 3x → escalate to HALTED
- Max 5 iterations → escalate to HALTED

**Output:** `grimoires/loa/a2a/pr-{number}/audit-findings.json`

### Phase 2: CONTEXT_CLEAR

Saves checkpoint and prepares for fresh-eyes testing.

**Writes:**
- Checkpoint to NOTES.md Session Continuity
- Entry to trajectory JSONL
- Preserves state in `.run/post-pr-state.json`

**Instructions displayed:**
```
To continue with fresh-eyes E2E testing:
  1. Run: /clear
  2. Run: /simstim --resume
```

### Phase 3: E2E_TESTING

Runs build and tests with fresh context.

**Auto-detects commands from:**
- `package.json` (npm run build, npm test)
- `Makefile` (make build, make test)
- `Cargo.toml` (cargo build, cargo test)
- `go.mod` (go build, go test)
- `pytest.ini` (pytest)

**Circuit Breaker:**
- Same failure 2x → escalate to HALTED
- Max 3 iterations → escalate to HALTED

**Output:** `grimoires/loa/a2a/pr-{number}/e2e-results.json`

### Phase 4: FLATLINE_PR (Optional)

Multi-model adversarial review of the PR.

**Cost:** ~$1.50
**Mode:** HITL (blockers prompt user, not auto-halt)

**Output:** `.flatline/runs/{run-id}/manifest.json`

---

## State Machine

```
PR_CREATED
    ↓
POST_PR_AUDIT ←→ FIX_AUDIT (fix loop)
    ↓
CONTEXT_CLEAR
    ↓ (user runs /clear + /simstim --resume)
E2E_TESTING ←→ FIX_E2E (fix loop)
    ↓
FLATLINE_PR (optional)
    ↓
READY_FOR_HITL
```

**Terminal States:**
- `READY_FOR_HITL` - All validations passed
- `HALTED` - Validation failed, check `halt_reason`

---

## Configuration Reference

```yaml
post_pr_validation:
  enabled: true

  phases:
    audit:
      enabled: true
      max_iterations: 5
      min_severity: "medium"

    context_clear:
      enabled: true
      write_checkpoint: true

    e2e:
      enabled: true
      max_iterations: 3
      # build_command: "npm run build"
      # test_command: "npm test"

    flatline:
      enabled: false
      mode: "hitl"

  timeouts:
    post_pr_audit: 600    # 10 min
    context_clear: 60     # 1 min
    e2e_testing: 1200     # 20 min
    flatline_pr: 300      # 5 min

  circuit_breaker:
    same_finding_threshold: 3
    same_failure_threshold: 2

  markers:
    audit_passed: ".PR-AUDITED"
    e2e_passed: ".PR-E2E-PASSED"
    validated: ".PR-VALIDATED"

  github_api:
    max_attempts: 3
    backoff: [1, 2, 4]
    timeout_per_attempt: 30

  auto_invoke:
    enabled: true
    mode: "autonomous"
```

---

## Troubleshooting

### State file not found

```bash
# Check if state exists
ls -la .run/post-pr-state.json

# Initialize manually
.claude/scripts/post-pr-state.sh init --pr-url <url>
```

### Lock acquisition timeout

```bash
# Check for stale lock
ls -la .run/.post-pr-lock/

# Force cleanup (if process crashed)
rm -rf .run/.post-pr-lock/
```

### Audit times out

Increase timeout in config:
```yaml
post_pr_validation:
  timeouts:
    post_pr_audit: 1200  # 20 min
```

### E2E tests fail repeatedly

Check circuit breaker status:
```bash
.claude/scripts/post-pr-state.sh get e2e.failure_identities
```

Same failure appearing multiple times triggers circuit breaker. Fix the underlying issue or escalate manually.

### Resume not working

Check current state:
```bash
.claude/scripts/post-pr-state.sh get state
.claude/scripts/post-pr-state.sh get phases
```

State must be `CONTEXT_CLEAR` for resume to continue at E2E_TESTING.

---

## Integration

### With Run Mode

Run mode automatically invokes post-PR validation after creating a PR:

```
/run sprint-plan
→ All sprints complete
→ Draft PR created
→ post-pr-orchestrator.sh invoked (if enabled)
→ READY_FOR_HITL or HALTED
```

### With Simstim

Simstim Phase 7.5 handles post-PR validation:

```
/simstim grimoires/loa/prd.md
→ PRD → SDD → Sprint → Implementation
→ Draft PR created
→ Post-PR validation runs
→ Context clear prompts: /clear then /simstim --resume
→ E2E testing with fresh context
→ READY_FOR_HITL
```

---

## Markers

Marker files indicate completed phases:

| Marker | Created After |
|--------|---------------|
| `.run/.PR-AUDITED` | Audit passes |
| `.run/.PR-E2E-PASSED` | E2E tests pass |
| `.run/.PR-VALIDATED` | Flatline review passes |

Check markers:
```bash
ls -la .run/.PR-*
cat .run/.PR-AUDITED
```

---

## Cost Analysis

| Phase | Token Cost | API Cost |
|-------|-----------|----------|
| Audit | ~50K tokens | ~$0.75 |
| E2E | ~20K tokens | ~$0.30 |
| Flatline | ~100K tokens | ~$1.50 |

**Total without Flatline:** ~$1.05
**Total with Flatline:** ~$2.55

---

*Documentation for Loa Framework v1.25.0 Post-PR Validation Loop*
