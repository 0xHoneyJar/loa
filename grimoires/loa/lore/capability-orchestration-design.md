# Capability-Driven Orchestration — Design Document

> **Status**: Design only (cycle-047 T4.5). Seeds SPEC-1 (capability markets).
> **Source**: Bridgebuilder deep review of PR #433, "Deliberative Council" pattern.

## Problem

The bridge orchestrator currently uses hardcoded signals (`PIPELINE_SELF_REVIEW`,
`RED_TEAM_CODE`, `BRIDGEBUILDER_REVIEW`, etc.) in a fixed sequence. Adding a new
review capability requires editing the orchestrator shell script — a change with
constitutional-level blast radius.

## Vision

Evolve from hardcoded signal dispatch to **capability-driven discovery**, where
the orchestrator queries available review capabilities and composes a deliberation
chain dynamically.

## Proposed Architecture

### Capability Registry

Each review capability declares itself via a manifest:

```yaml
# .claude/capabilities/security-compliance.yaml
capability:
  id: security-compliance
  type: review
  version: 1
  trigger:
    files: ["*.sh", "*.ts", "*.js"]    # File patterns this capability reviews
    tags: [security, authentication]     # Semantic tags for matching
  input:
    requires: [sdd, diff]               # Input channels needed
    optional: [prior_findings]           # Optional context
  output:
    format: findings-json               # Output schema
    severity_range: [0, 1000]
  budget:
    min_tokens: 4000                    # Minimum useful budget
    optimal_tokens: 50000               # Sweet spot for quality
    max_tokens: 150000                  # Upper bound
  dependencies:
    before: [bridgebuilder-review]      # Must run before these
    after: [pipeline-self-review]       # Must run after these
```

### Discovery Flow

```
bridge-orchestrator.sh
  ├── discover_capabilities()         # Scan .claude/capabilities/*.yaml
  ├── match_capabilities(changed_files) # Filter by trigger patterns
  ├── resolve_ordering(matches)       # Topological sort by dependencies
  ├── allocate_budgets(chain)         # Distribute token budget per capability
  └── execute_chain(ordered_caps)     # Sequential execution with context passing
```

### Budget Allocation

Token budget distributed across capabilities using the adaptive budget pattern
(T4.1). Each capability declares min/optimal/max, and the allocator:

1. Guarantees `min_tokens` to all matched capabilities
2. Distributes remaining budget proportionally by `optimal_tokens`
3. Caps each at `max_tokens`

### Context Passing

Capabilities form a pipeline where each stage's output enriches the next stage's
input. This implements the Deliberative Council pattern:

```
[Pipeline Self-Review] → findings → [Security Compliance] → findings
  → [Architecture Review] → findings → [Bridgebuilder] → synthesis
```

Each stage receives:
- Its own input channels (SDD sections, code diff)
- Accumulated findings from prior stages (Deliberative Council)
- Relevant lore entries (tag-matched)

## Parallels

### Kubernetes Admission Controllers

Kubernetes uses composable validation/mutation webhooks that:
- Register via `ValidatingWebhookConfiguration`
- Match on resource type and operation
- Execute in sequence with pass/fail semantics
- Can be added without modifying the API server

The bridge capability registry follows the same pattern: declare capabilities
externally, match by changed-file patterns, execute in dependency order.

### Chromium OWNERS

Chromium uses specification-based review routing where:
- Each directory declares its OWNERS
- Code reviews are auto-assigned based on changed files
- Multiple reviewers may be required for cross-cutting changes

The capability registry extends this: instead of routing to human reviewers,
it routes to review capabilities (AI agents with specific expertise).

### Google Tricorder (ISSTA 2018)

Tricorder composes analysis passes where:
- Each analyzer declares its scope and resource requirements
- Analyses run in parallel where independent
- Results cascade to later stages for enriched context
- New analyzers added by writing a plugin, not modifying the framework

This is exactly the architecture we're designing.

## Migration Path

1. **Current**: Hardcoded signals in `bridge-orchestrator.sh` (now)
2. **Phase 1**: Extract signal dispatch to config-driven table (cycle-048?)
3. **Phase 2**: Add capability manifest format and discovery
4. **Phase 3**: Dynamic chain composition with budget allocation
5. **Phase 4**: Cross-repo capability federation (repos advertise capabilities)

Phase 1 is achievable with minimal refactoring. Phase 2-3 requires the shared
library foundation from Sprint 3. Phase 4 depends on the cross-repo protocol
from T4.4.

## Configuration (future)

```yaml
capabilities:
  discovery:
    paths: [".claude/capabilities/"]    # Where to scan
    enabled: true
  orchestration:
    mode: "sequential"                  # sequential | parallel | hybrid
    max_capabilities: 10                # Cap on chain length
    budget_strategy: "proportional"     # equal | proportional | adaptive
```

## Open Questions

1. Should capabilities be able to veto the entire pipeline (BLOCKER)?
2. How to handle capability version incompatibilities?
3. Should the capability registry be cross-repo (federated)?
4. What happens when two capabilities have conflicting findings?
