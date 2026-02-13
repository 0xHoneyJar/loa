# Sprint Plan: Harness Engineering Adaptations

> Source: SDD cycle-011, Issue [#297](https://github.com/0xHoneyJar/loa/issues/297)
> Cycle: cycle-011
> Sprints: 4 (3 original + 1 bridge iteration)

## Sprint 1: Safety Hooks + Deny Rules (P1, P2)

**Goal**: Ship the core safety infrastructure — destructive command blocking and credential deny rules.
**Status**: COMPLETED (sprint-74)

---

## Sprint 2: Stop Hook + Audit Logger + CLAUDE.md Optimization (P3, P4, P5)

**Goal**: Ship the stop guard, audit logging, and reduce CLAUDE.md token footprint by ~50%.
**Status**: COMPLETED (sprint-75)

---

## Sprint 3: Invariant Linter + Integration (P6)

**Goal**: Ship mechanical invariant enforcement and wire everything together.
**Status**: COMPLETED (sprint-76)

---

## Sprint 4: Bridge Iteration 1 — Findings Remediation

**Goal**: Address actionable findings from Bridgebuilder review iteration 1 (bridge-20260213-c011he).
**Source**: [PR #315 Comment](https://github.com/0xHoneyJar/loa/pull/315#issuecomment-3895904553)

### Task 4.1: Fix PCRE Dependency in Safety Hook (HIGH-1)

**File**: `.claude/hooks/safety/block-destructive-bash.sh`

Replace `set -euo pipefail` + `grep -qP` with defensive error handling:
- Remove `set -euo pipefail` (hook must never fail closed)
- Replace PCRE patterns (`-P`) with extended regex (`-E`) for universal compatibility
- Add PCRE availability check OR use ERE equivalents throughout
- Ensure hook always exits 0 on parse/pattern errors (fail open, not closed)

**Acceptance Criteria**:
- No `set -euo pipefail` in hook
- All patterns use `grep -qE` (extended regex) instead of `grep -qP` (PCRE)
- Grep failures caught and result in exit 0 (allow)
- All 12 test patterns still pass
- Works on Alpine Linux / busybox grep

### Task 4.2: Fix JSON Output in Invariant Linter (HIGH-2)

**File**: `.claude/scripts/lint-invariants.sh`

Replace bash string interpolation in `report()` function with proper jq JSON construction:
- Use `jq -cn --arg` to build JSON objects
- Handle messages containing double quotes, backslashes, newlines
- Verify `--json` output is parseable by jq

**Acceptance Criteria**:
- `lint-invariants.sh --json | jq .` succeeds
- Messages with special characters produce valid JSON
- No manual JSON string escaping in bash

### Task 4.3: Simplify install-deny-rules.sh Merge Logic (MEDIUM-1)

**File**: `.claude/scripts/install-deny-rules.sh`

Consolidate triple jq invocation into single pass:
- Merge and count in one jq call
- Eliminate TOCTOU window between count and write
- Use temp file for atomic write

**Acceptance Criteria**:
- Single jq invocation for merge + count
- Same behavior: additive merge, correct count reported
- Dry-run mode still works

### Task 4.4: Expand Mutation Logger Command Detection (MEDIUM-2)

**File**: `.claude/hooks/audit/mutation-logger.sh`

Improve grep pattern to catch prefixed commands:
- Handle `sudo git push`, `env VAR=val rm -rf`, `command git push`
- Detect commands after `&&`, `;`, `|` chain operators
- Keep the filter focused (don't log non-mutating commands)

**Acceptance Criteria**:
- `sudo git push` is logged
- `echo hello && git push` is logged
- Non-mutating commands still skipped

### Task 4.5: Fix Hooks README Consistency (MEDIUM-3)

**File**: `.claude/hooks/README.md`

Resolve inconsistency between Files table and Hook Registry:
- Add status indicator to Files table distinguishing active vs dormant hooks
- memory-writer.sh and memory-inject.sh are not in settings.hooks.json — mark as "Optional/Separate install"

**Acceptance Criteria**:
- Files table has Status column or clear grouping
- No confusion about which hooks are active by default

### Task 4.6: Add Path-Qualified Command Handling (LOW-1)

**File**: `.claude/hooks/safety/block-destructive-bash.sh`

Add optional path prefix matching to destructive command patterns:
- `/usr/bin/rm -rf` should be caught
- `/usr/bin/git push --force` should be caught
- Extract command basename before pattern matching

**Acceptance Criteria**:
- Path-qualified commands detected
- Non-path-qualified commands still detected
- No false positives
