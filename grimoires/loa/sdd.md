# SDD: Bridgebuilder Large PR Support — Token Budget & Progressive Review

**Version**: 1.0.0
**Status**: Draft
**Author**: Architecture Phase (architect)
**Date**: 2026-02-09
**PRD**: grimoires/loa/prd.md
**Issue**: #260

---

## 1. Executive Summary

Fix the Bridgebuilder skill's inability to review large PRs by raising default token/size budgets, adding CLI flags for runtime configuration, scaling API timeouts for large payloads, and improving error messaging. All changes are confined to 3 TypeScript source files + recompile.

## 2. Affected Components

Files to modify: 3 (config.ts, reviewer.ts, adapters/index.ts)

## 3. Design

### 3.1 config.ts: Raise defaults, add CLI flags, update resolution

### 3.2 reviewer.ts: Pre-flight logging, graceful skip messaging

### 3.3 adapters/index.ts: Scaled timeout based on config.maxInputTokens

See full SDD in conversation context for detailed design.

## 4. References

- Config: `.claude/skills/bridgebuilder-review/resources/config.ts`
- Reviewer: `.claude/skills/bridgebuilder-review/resources/core/reviewer.ts`
- Adapters: `.claude/skills/bridgebuilder-review/resources/adapters/index.ts`
