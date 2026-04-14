# Proposal: Spiral Cost Optimization + Off-Hours Scheduling

**Date**: 2026-04-15
**Author**: Cost analysis session
**Status**: Approved
**Depends on**: v1.88.0 (spiral harness shipped)

---

## Problem

A single spiral cycle costs ~$15-20 ($12 harness budget + $3-4 Flatline API). A 3-cycle spiral runs $45-60. Every cycle runs the full 9-phase pipeline regardless of task complexity. The user also has unused token allowance windows during AFK/sleep time.

## Solution: Four Tiers

### Tier 1: Pipeline Profiles

Three profiles that match pipeline intensity to task complexity:

| Profile | Phases | Flatline Gates | Advisor | Budget | Use For |
|---------|--------|----------------|---------|--------|---------|
| `full` | 9 | PRD + SDD + Sprint | Opus | $15 | Architecture, security-critical |
| `standard` | 7 | Sprint only | Opus | $12 | Feature work (default) |
| `light` | 6 | None | Sonnet | $8 | Bug fixes, flags, config |

**Evidence**: Benchmark data shows PRD/SDD Flatline gates generated 9-15 blockers across runs, but both implementations passed Review+Audit first try regardless. Sprint Flatline catches AC gaps — never skip.

### Tier 2: Deterministic Pre-Gates

Bash pre-checks before expensive LLM Review/Audit sessions:
- Git diff exists and is non-empty
- Sprint.md has acceptance criteria checkboxes
- Tests exist in the diff
- No secrets detected in diff

Fails fast at $0 cost instead of discovering these at $2-4 per LLM session.

### Tier 3: Flatline Prompt Caching

Structure Flatline API calls to use Claude's prompt caching (0.1x cost on cache reads, 5-minute TTL). Three gates fire within 8 minutes — second and third gates read from cache. Saves ~$1.15/cycle.

### Tier 4: Off-Hours Scheduling

Use Claude Code scheduling primitives (CronCreate / RemoteTrigger) to run spiral cycles during AFK/sleep windows. New `check_token_window()` stopping condition halts at window end. Spiral resumes next window via `--resume`.

## Projected Savings

| Profile | Before | After | Reduction |
|---------|--------|-------|-----------|
| `full` | $15-20 | $14-17 | 10-15% |
| `standard` | $15-20 | $10-13 | 30-35% |
| `light` | $15-20 | $6-8 | 55-60% |

With off-hours scheduling, token spend moves from paid overage to included allowance.
