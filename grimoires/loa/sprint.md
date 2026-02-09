# Sprint Plan: Bridgebuilder Large PR Support

**Version**: 1.0.0
**Date**: 2026-02-09
**PRD**: grimoires/loa/prd.md
**SDD**: grimoires/loa/sdd.md
**Issue**: #260

---

## Overview

| Field | Value |
|-------|-------|
| Total Sprints | 1 |
| Sprint Duration | Single session |
| Developer | Claude (AI agent) |
| Scope | Raise defaults, add CLI flags, scale timeout, improve error messaging |

---

## Sprint 1: Token Budget Fix & CLI Flags

**Goal**: Make Bridgebuilder reliably review large PRs by raising default budgets, adding CLI configuration flags, scaling API timeouts, and improving error messaging.

### Task 1: Raise Default Budgets
**File**: config.ts — maxInputTokens: 8K→128K, maxOutputTokens: 4K→16K, maxDiffBytes: 100K→512K

### Task 2: Add CLI Flags
**File**: config.ts — --max-input-tokens, --max-output-tokens, --max-diff-bytes, --model

### Task 3: Pre-flight Logging & Graceful Skip
**File**: reviewer.ts — Log prompt estimates, actionable error messages

### Task 4: Scaled API Timeout
**File**: adapters/index.ts — 120s for <=50K tokens, 300s for >50K tokens

### Task 5: Update Tests
**File**: config.test.ts — Tests for new CLI flags, precedence, validation

### Task 6: Recompile & Verify
Compile TypeScript and run all tests.
