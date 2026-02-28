# Cross-Repo Compliance Checking — Design Document

> **Status**: Design only (cycle-046). Implementation deferred to future cycle.
> **Source**: Bridgebuilder deep review of PR #429, "Governance Isomorphism" insight.

## Problem

The Red Team code-vs-design gate currently operates within a single repository.
But the Loa ecosystem spans multiple repos (loa, loa-finn, loa-hounfour,
loa-freeside, loa-dixie) that share governance patterns. A security design
decision in loa-hounfour's router may have compliance implications for
loa-finn's runtime — and vice versa.

## Proposed Architecture

### SDD Index Hub

Each repo publishes a machine-readable SDD index at a well-known path:

```
grimoires/loa/sdd-index.yaml
```

Schema:

```yaml
repo: 0xHoneyJar/loa-finn
version: 1
sections:
  - id: auth-middleware
    path: grimoires/loa/sdd.md#authentication-middleware
    keywords: [Authentication, JWT, Authorization]
    exports: [ModelPort, AuthContext]
  - id: hounfour-router
    path: grimoires/loa/sdd.md#hounfour-router-integration
    keywords: [Routing, Models, Cost]
    exports: [RouterConfig, ProviderAdapter]
```

### Cross-Repo Resolution

When the Red Team gate runs in repo A and finds a divergence referencing
an interface from repo B, it can:

1. Fetch repo B's `sdd-index.yaml` via `gh api` or local clone
2. Resolve the relevant SDD section by keyword/export match
3. Include the cross-repo SDD context in the review prompt

### Compliance Gate Profiles

The parameterized `extract_sections_by_keywords()` function (cycle-046 FR-4)
enables this pattern. Each repo can define its own compliance profiles:

```yaml
red_team:
  compliance_gates:
    security:
      keywords: [Security, Authentication, ...]
    api_contract:
      keywords: [Interface, Export, Contract, Protocol]
    performance:
      keywords: [Performance, Latency, Throughput, Cache]
```

### Governance Isomorphism Application

This design applies the Governance Isomorphism pattern:
- **Multi-perspective**: Cross-repo SDD sections provide independent perspectives
- **Fail-closed**: Missing SDD index → skip cross-repo check (safe default)
- **Consensus**: Divergences from multiple repos weighted higher

## Dependencies

- `extract_sections_by_keywords()` parameterization (this cycle)
- SDD index schema standardization (future cycle)
- Cross-repo `gh api` access patterns (requires GitHub token scope)
- BUTTERFREEZONE ecosystem config for repo discovery

## Open Questions

1. Should cross-repo SDDs be fetched live or cached locally?
2. Token budget allocation: how much context budget for cross-repo sections?
3. Should cross-repo findings be posted to source repo or consuming repo?
