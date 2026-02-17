# Vision Registry

Speculative insights captured during bridge loop iterations.
Each vision represents an architectural connection or paradigm insight
that transcends the current task — Google's 20% time, automated.

## Status Lifecycle

```
Captured → Exploring → Proposed → Implemented
                                → Deferred
```

| Status | Meaning |
|--------|---------|
| **Captured** | Raw insight from bridge review, not yet explored |
| **Exploring** | Under active investigation in a vision sprint |
| **Proposed** | Architectural proposal generated, awaiting cycle allocation |
| **Implemented** | Built into the codebase (with cycle reference) |
| **Deferred** | Reviewed but not prioritized for current roadmap |

## Active Visions

| ID | Title | Source | Status | Tags | Refs |
|----|-------|--------|--------|------|------|
| vision-001 | Pluggable credential provider registry | bridge-20260213-8d24fa / PR #306 | Captured | architecture | 0 |
| vision-002 | Bash Template Rendering Anti-Pattern | bridge-20260213-c012rt / PR #317 | Captured | security, bash | 0 |
| vision-003 | Context Isolation as Prompt Injection Defense | bridge-20260214-e8fa94 / PR #324 | Captured | security, prompt-engineering | 0 |
| vision-004 | Conditional Constraints for Feature-Flagged Behavior | bridge-20260216-c020te / PR #341 | Exploring | architecture, constraints | 1 |
| vision-005 | Pre-Swarm Research Planning (`/plan-research`) | #344 / soju+loa feedback | Captured | orchestration, token-efficiency | 0 |
| vision-006 | Symbiotic Layer — Convergence Detection & Intent Modeling | #344 / soju+loa feedback | Captured | orchestration, ux, philosophy | 0 |
| vision-007 | Operator Skill Curve & Progressive Orchestration Disclosure | #344 / soju+loa feedback | Captured | orchestration, ux | 0 |

## Statistics

- Total captured: 7
- Exploring: 1
- Proposed: 0
- Implemented: 0
- Deferred: 0

### vision-004 Exit Criteria

**Current Status**: Exploring (activated cycle-023)
**Exit to Proposed**: When the conditional constraint pattern (MAY as primary rule_type) has been implemented and validated through the pipeline
**Exit to Deferred**: If bridge review determines pattern is not generalizable
**Responsible**: Bridgebuilder during post-merge review of cycle-023 PR
