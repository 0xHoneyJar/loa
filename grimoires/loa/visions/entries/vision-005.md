# Vision: Pre-Swarm Research Planning (`/plan-research`)

**ID**: vision-005
**Source**: Issue #344, Comment 2 (Token Efficiency Retrospective)
**PR**: N/A
**Date**: 2026-02-15T00:00:00Z
**Status**: Captured
**Tags**: [orchestration, token-efficiency, multi-agent]

## Insight

Before deploying agent swarms, map the full question space, identify non-overlapping scopes, and deploy the minimum number of agents. The optimal pattern observed was N parallel researchers with clear boundaries + 1 synthesis agent that waits for all outputs.

Without pre-planning, 4 teams were deployed when 2 would have sufficed, resulting in ~30% token waste from overlapping scope, duplicate synthesis, and sequential re-injection of prior findings.

## Potential

A `/plan-research` skill that decomposes operator intent into a question space map before deploying agents. The overhead of a 2-minute planning step saves 30%+ tokens on execution.

## Connection Points

- Issue: #344, Comment 2 by @zkSoju
- Session: 2026-02-15 TeamCreate swarm deployment
- Parallel: Google Spanner query planning — decompose before dispatching to shards
