# Proposal: Spiral Cost Optimization + Off-Hours Scheduling

**Date**: 2026-04-15
**Author**: Cost analysis session
**Status**: Implemented (cycle-072)
**PRD**: `grimoires/loa/prd.md`
**SDD**: `grimoires/loa/sdd.md`

---

## Problem

A single spiral cycle costs ~$15-20 ($12 harness budget + $3-4 Flatline API). Every cycle runs the full 9-phase pipeline regardless of task complexity. Dead token-allowance windows go unused during AFK/sleep time.

## Solution

1. **Pipeline profiles** (full/standard/light) — match intensity to task complexity
2. **Deterministic pre-checks** — fail fast at $0 before expensive LLM sessions
3. **Off-hours scheduling** — run spiral cycles during AFK/sleep windows
4. **Auto-escalation** — security paths auto-trigger full profile
5. **Benchmark framework** — data-driven comparison tool for flight recorders

## Projected Savings

| Profile | Before | After | Reduction |
|---------|--------|-------|-----------|
| `full` | $15-20 | $14-17 | 10-15% |
| `standard` | $15-20 | $10-13 | 30-35% |
| `light` | $15-20 | $6-8 | 55-60% |
