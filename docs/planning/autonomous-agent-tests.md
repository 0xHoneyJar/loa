# Autonomous Agent Integration Tests

> **PR**: #82 - Autonomous Agent Orchestra Implementation
> **Sprint**: 3 (Documentation & Testing)
> **Date**: 2026-01-31

## Overview

This document defines integration tests and manual verification procedures for the autonomous-agent skill.

## Test Categories

### 1. Dry Run Tests

Validate skill structure without execution.

#### Test 1.1: Skill Discovery

**Command**: `/autonomous --detect-only`

**Expected**:
- Operator type detected and displayed
- No execution occurs
- Exit code 0

**Verification**:
```bash
# Check skill is registered
grep -l "autonomous-agent" .claude/skills/*/index.yaml

# Verify triggers work
# In Claude Code: type "/autonomous" and verify autocomplete
```

#### Test 1.2: Dry Run Validation

**Command**: `/autonomous --dry-run`

**Expected**:
- Phase checklist displayed
- Dependencies validated
- No files modified
- Exit code 0

**Verification**:
```bash
# Run dry run
# Should output:
# ✓ Phase 0: Preflight (would execute)
# ✓ Phase 1: Discovery (would execute)
# ... etc

# Verify no files changed
git status --porcelain  # Should be empty
```

---

### 2. Operator Detection Tests

Validate AI vs Human detection logic.

#### Test 2.1: Environment Variable Detection

**Setup**:
```bash
export LOA_OPERATOR=ai
```

**Command**: `/autonomous --detect-only`

**Expected**:
- Output: "Operator Type: AI_OPERATOR (detected via env_var)"
- Exit code 0

**Cleanup**:
```bash
unset LOA_OPERATOR
```

#### Test 2.2: TTY Detection

**Setup**: Run in non-interactive mode

**Command**:
```bash
echo "/autonomous --detect-only" | claude --no-tty
```

**Expected**:
- Detects as AI_OPERATOR (no TTY)
- Output shows detection method: "tty"

#### Test 2.3: Human Override

**Setup**:
```bash
export LOA_OPERATOR=human
```

**Command**: `/autonomous --detect-only`

**Expected**:
- Output: "Operator Type: HUMAN_OPERATOR (explicit override)"
- Exit code 0

---

### 3. Phase Transition Tests

Validate phase ordering and gate checks.

#### Test 3.1: Phase 0 → Phase 1 Transition

**Prerequisites**:
- No existing checkpoint
- No PRD

**Command**: Start `/autonomous`

**Expected**:
- Phase 0 completes (operator detected)
- Phase 1 starts (discovery)
- PRD creation begins
- Checkpoint written: `.loa-checkpoint/preflight.yaml`

**Verification**:
```bash
cat .loa-checkpoint/preflight.yaml
# Should contain:
# phase: preflight
# exit_code: 0
```

#### Test 3.2: Gate 1 Block (Missing Inputs)

**Prerequisites**:
- PRD exists
- SDD does NOT exist

**Command**: Force Phase 3 start

**Expected**:
- Gate 1 fails: "Missing input: grimoires/loa/sdd.md"
- Exit code 1
- Phase blocked until input created

**Verification**:
```bash
# Should see in output:
# GATE_1_FAILED: Missing inputs: sdd.md
```

#### Test 3.3: Gate 3 Block (Missing Outputs)

**Scenario**: Implement phase completes but reviewer.md not created

**Expected**:
- Gate 3 fails: "Missing output: reviewer.md"
- Exit code 1
- Remediation loop triggered

---

### 4. Checkpoint Persistence Tests

Validate checkpoint write/read operations.

#### Test 4.1: Checkpoint Write

**Command**: Complete Phase 1 (Discovery)

**Expected**:
- File created: `.loa-checkpoint/discovery.yaml`
- Contains required fields:
  - execution_id
  - phase: "discovery"
  - created_at
  - exit_code: 0
  - summary

**Verification**:
```bash
test -f .loa-checkpoint/discovery.yaml && echo "PASS"
cat .loa-checkpoint/discovery.yaml | grep -E "^(execution_id|phase|created_at|exit_code|summary):"
```

#### Test 4.2: Checkpoint Resume

**Setup**:
1. Complete Phase 1 and 2
2. Interrupt execution
3. Start new session

**Command**: `/autonomous`

**Expected**:
- Detects existing checkpoint
- Offers to resume from Phase 3
- Does NOT re-run Phase 1 and 2

**Verification**:
```bash
# Should see in output:
# Resuming from checkpoint: design (Phase 2)
# Skipping: preflight, discovery
```

#### Test 4.3: Checkpoint Integrity

**Setup**: Corrupt checkpoint file

```bash
echo "invalid: yaml: content" > .loa-checkpoint/discovery.yaml
```

**Command**: `/autonomous`

**Expected**:
- Detects corrupted checkpoint
- Warns user
- Offers fresh start or manual fix

---

### 5. Feedback Capture Tests

Validate Phase 7 learning capture.

#### Test 5.1: Feedback File Creation

**Setup**: Complete full execution

**Expected**:
- File created: `grimoires/loa/feedback/{date}.yaml`
- Contains at least one entry
- Version field = 1

**Verification**:
```bash
ls grimoires/loa/feedback/*.yaml
cat grimoires/loa/feedback/*.yaml | grep "version: 1"
```

#### Test 5.2: Gap Detection

**Setup**: PRD goal that wasn't fully implemented

**Expected**:
- Gap entry in feedback file
- gap.yaml created with major/minor classification
- Recommendation for /refine-prd if major

**Verification**:
```bash
cat grimoires/loa/gaps.yaml
# Should contain goal classification
```

---

### 6. Escalation Tests

Validate escalation trigger and report generation.

#### Test 6.1: Max Loops Escalation

**Setup**: Configure `max_remediation_loops: 1` in config

**Scenario**: Audit fails twice

**Expected**:
- First failure: Remediation attempt
- Second failure: Escalation triggered
- Report generated with suggested actions

**Verification**:
- Escalation report in output
- Execution halted
- Checkpoint preserved

#### Test 6.2: Escalation Report Content

**Expected Fields**:
- [ ] Execution ID
- [ ] Session ID
- [ ] Phase where blocked
- [ ] Remaining findings
- [ ] Remediation attempts
- [ ] Suggested actions

---

## Manual Verification Procedures

### Pre-Flight Checklist

Before running E2E tests:

- [ ] Clean state: `rm -rf .loa-checkpoint/ grimoires/loa/feedback/`
- [ ] No existing PRD/SDD: `rm grimoires/loa/prd.md grimoires/loa/sdd.md` (if testing fresh)
- [ ] Config valid: `cat .loa.config.yaml | grep autonomous_agent`
- [ ] Skills loaded: `ls .claude/skills/autonomous-agent/`

### E2E Test Procedure

1. **Start Fresh**
   ```bash
   git stash  # Save any work
   rm -rf .loa-checkpoint/
   ```

2. **Run Autonomous**
   ```
   /autonomous
   ```

3. **Observe Phase Transitions**
   - [ ] Preflight completes
   - [ ] Discovery runs (or skips if PRD exists)
   - [ ] Design runs (or skips if SDD exists)
   - [ ] Implementation executes
   - [ ] Audit validates
   - [ ] Submit creates PR (draft)
   - [ ] Learning captures feedback

4. **Verify Artifacts**
   ```bash
   # Checkpoints
   ls .loa-checkpoint/

   # Feedback
   ls grimoires/loa/feedback/

   # Gaps (if any)
   cat grimoires/loa/gaps.yaml

   # Trajectory
   ls grimoires/loa/a2a/trajectory/
   ```

5. **Check PR**
   ```bash
   gh pr list --state open --draft
   ```

### Known Issues

Document any issues found during testing:

| Issue | Severity | Status | Notes |
|-------|----------|--------|-------|
| - | - | - | - |

---

## Test Results

### Test Run: 2026-01-31

| Test | Result | Notes |
|------|--------|-------|
| 1.1 Skill Discovery | PENDING | |
| 1.2 Dry Run | PENDING | |
| 2.1 Env Var Detection | PENDING | |
| 2.2 TTY Detection | PENDING | |
| 2.3 Human Override | PENDING | |
| 3.1 Phase Transition | PENDING | |
| 3.2 Gate 1 Block | PENDING | |
| 3.3 Gate 3 Block | PENDING | |
| 4.1 Checkpoint Write | PENDING | |
| 4.2 Checkpoint Resume | PENDING | |
| 4.3 Checkpoint Integrity | PENDING | |
| 5.1 Feedback Creation | PENDING | |
| 5.2 Gap Detection | PENDING | |
| 6.1 Max Loops Escalation | PENDING | |
| 6.2 Report Content | PENDING | |

---

## Related Documents

- [Quality Gates](../../.claude/skills/autonomous-agent/resources/quality-gates.md)
- [Phase Checklist](../../.claude/skills/autonomous-agent/resources/phase-checklist.md)
- [Operator Detection](../../.claude/skills/autonomous-agent/resources/operator-detection.md)
