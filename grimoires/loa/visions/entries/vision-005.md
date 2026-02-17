# Vision 005: Pre-Swarm Research Planning (`/plan-research`)

## Source
- Issue: #344, Comment 2 (Token Efficiency Retrospective)
- Author: @zkSoju (soju+loa operator)
- Session: 2026-02-15 TeamCreate swarm deployment

## Insight

Before deploying agent swarms, map the full question space, identify non-overlapping scopes, and deploy the minimum number of agents. The optimal pattern observed was `constructs-sync-research`: N parallel researchers with clear boundaries + 1 synthesis agent that waits for all outputs.

Without pre-planning, 4 teams were deployed when 2 would have sufficed, resulting in ~30% token waste from overlapping scope, duplicate synthesis, and sequential re-injection of prior findings.

## Pattern

```
Operator intent → /plan-research → Question space map → Agent deployment plan → Deploy
```

Instead of:
```
Operator intent → Deploy team 1 → Results → Deploy team 2 → Re-inject results → Deploy team 3 → ...
```

## Applicability

Any multi-agent research session where:
- The question space has multiple dimensions
- Agents could overlap in scope without explicit boundaries
- The operator's clarity about what they need is still forming

## Connection

This is the "measure twice, cut once" principle applied to agent orchestration. The overhead of a 2-minute planning step saves 30%+ tokens on execution. Parallels Google's query planning in Spanner: decompose the query before dispatching to shards, not after.
