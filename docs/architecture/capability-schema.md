# BUTTERFREEZONE Capability Schema v1.0

> **Defined in**: `0xHoneyJar/loa`
> **Consumed by**: loa-finn (pool routing), arrakis (billing), loa-hounfour (trust classification)
> **Related**: [RFC #31 §5.2](https://github.com/0xHoneyJar/loa-finn/issues/31), [arrakis #62](https://github.com/0xHoneyJar/arrakis/issues/62), [loa-hounfour PR #2](https://github.com/0xHoneyJar/loa-hounfour/pull/2), [loa #43](https://github.com/0xHoneyJar/loa/issues/43)

## Agent-API Interface Standard

BUTTERFREEZONE.md is the canonical agent-facing project interface for any Loa-managed codebase. It is the standard that addresses two long-standing needs:

- **Cross-repo agent legibility** ([#43](https://github.com/0xHoneyJar/loa/issues/43)): Agents traversing multi-repo ecosystems need a consistent interface to discover capabilities, trust levels, and relationships without reading entire codebases.
- **Human + agent readability** ([#316](https://github.com/0xHoneyJar/loa/issues/316)): The interface must be useful at a glance to both humans and agents — not just a list, but a structured narrative with provenance tags, architecture diagrams, and verification signals.

Every repository in the ecosystem SHOULD publish `BUTTERFREEZONE.md` at its root. The `AGENT-CONTEXT` YAML block is the structured data contract; the Markdown body provides human-readable context. The `butterfreezone-mesh.sh` script enables cross-repo capability discovery by fetching and aggregating AGENT-CONTEXT blocks across the ecosystem graph.

## Overview

This document defines the formal schema for BUTTERFREEZONE `capability_requirements` and `trust_level` fields. It serves as the interface contract between Loa (which generates BUTTERFREEZONE.md files) and downstream consumers that route, gate, and bill based on declared capabilities.

**Permission Scape flow**:
```
BUTTERFREEZONE declares needs → Hounfour provides trust-verified pools → arrakis maps pool usage to costs
```

## Capability Vocabulary

Each capability has actions, scopes, a Hounfour pool routing hint, and a billing weight for arrakis cost mapping.

```yaml
capability_vocabulary:
  filesystem:
    actions: [read, write]
    scopes: [system, state, app]
    scope_mapping:
      system: ".claude/"
      state: "grimoires/, .beads/, .ck/, .run/"
      app: "src/, lib/, app/"
    hounfour_pool_hint: null  # filesystem ops don't require specific model pools
    billing_weight: 0  # no API cost for local filesystem

  git:
    actions: [read, write, read_write]
    scopes: [local, remote]
    hounfour_pool_hint: null
    billing_weight: 0

  github_api:
    actions: [read, write, read_write]
    scopes: [external]
    hounfour_pool_hint: null
    billing_weight: 1  # GitHub API calls have rate limits

  shell:
    actions: [execute]
    scopes: [local]
    hounfour_pool_hint: null
    billing_weight: 0

  network:
    actions: [read, write]
    scopes: [external]
    hounfour_pool_hint: null
    billing_weight: 1  # external HTTP calls

  model:
    actions: [invoke]
    scopes: [cheap, fast_code, reviewer, reasoning, architect]
    hounfour_pool_hint: "{scope}"  # scope IS the pool name
    billing_weight: 3  # model invocations are the primary cost driver
```

### Scope-to-Zone Mapping

Scopes align with the Three-Zone Model defined in PROCESS.md:

| Scope | Zone | Path Pattern | Permission Level |
|-------|------|-------------|------------------|
| `system` | System | `.claude/` | NEVER write (framework-managed) |
| `state` | State | `grimoires/`, `.beads/`, `.ck/`, `.run/` | Read/Write |
| `app` | App | `src/`, `lib/`, `app/` | Read (write requires confirmation) |
| `external` | — | GitHub API, network, model APIs | Rate-limited |
| `local` | — | git, shell | No API cost |

### BUTTERFREEZONE Syntax

Capabilities appear in the AGENT-CONTEXT block with optional scope annotation:

```yaml
capability_requirements:
  - filesystem: read
  - filesystem: write (scope: state)
  - filesystem: write (scope: app)
  - git: read_write
  - shell: execute
  - github_api: read_write (scope: external)
```

**Backward compatibility**: Consumers that don't understand `(scope: ...)` can strip the parenthetical with a regex (`s/ \(scope:.*\)//`) and get the flat capability.

## Trust Gradient

Trust levels are monotonic (L1 → L2 → L3 → L4) and gate pool access in Hounfour.

```yaml
trust_gradient:
  L1:
    name: "Tests Present"
    criteria: "≥1 test file exists"
    hounfour_trust: "basic"
    min_pool_access: [cheap, fast_code]
    trust_scopes:  # v6+ CapabilityScopedTrust
      data_access: none
      financial: none
      delegation: none
      model_selection: none
      governance: none
      external_communication: none

  L2:
    name: "CI Verified"
    criteria: "Tests + CI pipeline configured"
    hounfour_trust: "verified"
    min_pool_access: [cheap, fast_code, reviewer]
    trust_scopes:
      data_access: medium
      financial: none
      delegation: none
      model_selection: medium
      governance: none
      external_communication: none

  L3:
    name: "Property-Based"
    criteria: "L2 + property-based/behavioral tests (fast-check, hypothesis, proptest, quickcheck)"
    hounfour_trust: "hardened"
    min_pool_access: [cheap, fast_code, reviewer, reasoning]
    trust_scopes:
      data_access: medium
      financial: medium
      delegation: medium
      model_selection: medium
      governance: none
      external_communication: medium

  L4:
    name: "Formal"
    criteria: "L3 + formal temporal properties or safety/liveness proofs"
    hounfour_trust: "proven"
    min_pool_access: [cheap, fast_code, reviewer, reasoning, architect]
    trust_scopes:
      data_access: high
      financial: high
      delegation: high
      model_selection: high
      governance: medium
      external_communication: high
```

### Trust Scopes (Hounfour v6+)

The `trust_scopes` field provides 6-dimensional trust classification per loa-hounfour v6.0.0 `CapabilityScopedTrust`. Each dimension independently controls a class of operations:

| Dimension | Controls | Example |
|-----------|----------|---------|
| `data_access` | Reading/writing persistent state | File I/O, database queries |
| `financial` | Cost-bearing operations | Model API calls, budget decisions |
| `delegation` | Spawning sub-agents or tasks | TeamCreate, Task delegation |
| `model_selection` | Choosing which model to invoke | Routing decisions, fallback chains |
| `governance` | Protocol-level rule changes | Constraint modification, policy updates |
| `external_communication` | Outbound network/messaging | GitHub API, Slack, email |

Values are `high`, `medium`, or `none`. The flat `trust_level` (L1-L4) is retained as a backward-compatible summary; `trust_scopes` provides the granular detail that downstream consumers (loa-finn pool routing, arrakis billing tiers) can use for fine-grained gating.

### BUTTERFREEZONE Trust Level Syntax

Trust level appears in the AGENT-CONTEXT block:

```yaml
trust_level: L2-verified
```

And in the `## Verification` section:

```markdown
## Verification
<!-- provenance: CODE-FACTUAL -->
- Trust Level: **L2 — CI Verified**
- 142 test files across 1 suite
- CI/CD: GitHub Actions (10 workflows)
```

## Cross-Repo Consumption Pattern

```
1. BUTTERFREEZONE.md (any Loa repo)
   ├── capability_requirements: [filesystem: write (scope: state), model: invoke (scope: reviewer)]
   └── trust_level: L2-verified

2. loa-finn (pool routing)
   ├── Reads capability_requirements from BUTTERFREEZONE.md
   ├── Extracts model scopes → required pools: [reviewer]
   └── Checks trust_level ≥ L2 → grants access to [cheap, fast_code, reviewer]

3. loa-hounfour (trust classification)
   ├── Reads trust_level from BUTTERFREEZONE.md
   ├── Maps L2 → hounfour_trust: "verified"
   └── Applies trust-appropriate safety constraints

4. arrakis (billing)
   ├── Reads capability_requirements from BUTTERFREEZONE.md
   ├── Sums billing_weight per capability used
   └── Maps to cost tiers: 0 (free), 1 (metered), 3 (premium)
```

## Schema Versioning

This schema follows the same forward-compatibility contract as the mesh schema:

- **Schema version**: `1.0`
- **Consumers MUST ignore unknown fields** (forward compatibility)
- Planned additions for v1.1: `model` capability scopes for fine-grained pool selection, `billing_tier` per-skill aggregation

## Hounfour v7 Type Mapping

Loa doesn't instantiate hounfour protocol types directly — it implements equivalent patterns that correspond to v7.0.0 types. This table documents the structural correspondence:

| Hounfour v7 Type | Loa Pattern | Loa File | Notes |
|------------------|-------------|----------|-------|
| `BridgeTransferSaga` | Retry chains with fallback/downgrade | `.claude/adapters/loa_cheval/routing/chains.py` | Garcia-Molina saga pattern: provider failure → fallback → compensating action |
| `DelegationOutcome` | Flatline consensus scoring | `.claude/scripts/flatline-orchestrator.sh` | Multi-model cross-scoring → HIGH_CONSENSUS / DISPUTED / BLOCKER |
| `MonetaryPolicy` | `RemainderAccumulator` + `BudgetEnforcer` | `.claude/adapters/loa_cheval/metering/budget.py` | Conservation invariant: total_in == total_distributed + remainder |
| `PermissionBoundary` | MAY/MUST/NEVER constraint grants | `.claude/data/constraints.json` | Permission scape rendered into CLAUDE.loa.md |
| `GovernanceProposal` | Flatline scoring with BLOCKER threshold | `.claude/scripts/flatline-orchestrator.sh` | BLOCKER (>700 skeptic score) halts autonomous workflows |

### Conservation Invariant

The `MonetaryPolicy` correspondence is the deepest structural match. The same conservation invariant appears in three codebases:

- **Loa**: `RemainderAccumulator` ensures `total_micro_usd == sum(distributed) + remainder`
- **loa-hounfour**: `MonetaryPolicy` enforces `total_budget == sum(allocations) + reserve`
- **arrakis**: `lot_invariant` CHECK constraint ensures `total_value == sum(lot_values)`

This is not coincidental — it's the same pattern (double-entry accounting / conservation law) applied at different scales. See [arrakis #62](https://github.com/0xHoneyJar/arrakis/issues/62) for the billing-side analysis.

## Hounfour Version Lineage

| Version | Codename | Key Additions | Loa Alignment |
|---------|----------|---------------|---------------|
| v3.0.0 | Constitutional | `AgentIdentity`, trust levels, basic routing | Original trust_level field |
| v4.6.0 | Agent Economy | `EconomicPolicy`, pool routing, billing hooks | First ecosystem declarations |
| v5.0.0 | Multi-Model | Provider registry, adapter pattern, thinking config | loa-finn runtime integration |
| v6.0.0 | Capability-Scoped Trust | `trust_scopes` (6-dimensional), `CapabilityScopedTrust` | model-permissions.yaml migration |
| v7.0.0 | Composition-Aware Economic Protocol | `BridgeTransferSaga`, `DelegationOutcome`, `MonetaryPolicy`, `PermissionBoundary`, `GovernanceProposal`, 8 new evaluator builtins (23→31) | Type mapping documented above |

## Related Documents

- [PROCESS.md](../../PROCESS.md) — BUTTERFREEZONE standard and Three-Zone Model
- [Separation of Concerns](separation-of-concerns.md) — Three-Layer Model
- [Decision Lineage](decision-lineage.md) — Architectural decision records
- [loa-hounfour MIGRATION.md](https://github.com/0xHoneyJar/loa-hounfour/blob/main/MIGRATION.md) — Protocol migration guide
- [loa-hounfour CHANGELOG.md](https://github.com/0xHoneyJar/loa-hounfour/blob/main/CHANGELOG.md) — Version history
