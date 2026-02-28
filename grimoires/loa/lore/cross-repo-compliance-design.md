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

## Economic Feedback for Review Depth (T4.3, cycle-047)

> **Status**: Design only. Seeds SPEC-5 (economic governance of review depth).

### Marginal Value Signal

After each bridge iteration, the orchestrator computes:

- **Marginal cost**: API spend this iteration (from `metrics.cost_estimates[]`)
- **Marginal value**: `findings_addressed / cost_estimate_usd`
- **Value ratio**: `marginal_value(N) / marginal_value(N-1)`

When the value ratio drops below a configurable threshold (default: 0.2), emit
a `DIMINISHING_RETURNS` signal. This signal indicates that the cost of another
iteration is unlikely to produce proportional value.

### Signal Actions

| Consumer | Action |
|----------|--------|
| Bridge orchestrator | Could trigger early flatline (additive to existing score-based flatline) |
| Simstim (HITL) | Present to user: "Continuing costs ~$X for ~Y expected findings. Continue?" |
| Autonomous mode | Hard stop — diminishing returns + flatline = definite termination |

### Data Flow

```
deliberation-metadata.json → bridge-state.json:cost_estimates[]
  → compute marginal_value per iteration
  → if value_ratio < threshold → SIGNAL:DIMINISHING_RETURNS
```

### Configuration (future)

```yaml
run_bridge:
  economic_feedback:
    enabled: false                    # Master toggle
    value_threshold: 0.2              # Marginal value ratio below which to signal
    min_iterations: 2                 # Don't signal before N iterations (need baseline)
```

### Relationship to Flatline

Economic feedback is **complementary** to flatline scoring:
- **Flatline**: "are findings converging?" (quality signal)
- **Economic**: "is continued investment worthwhile?" (value signal)

A system can flatline economically before quality-flatline, or vice versa.
The strongest termination signal is when both agree.

## Specification Change Notification (T4.4, cycle-047)

> **Status**: Design only. Prerequisite for cross-repo compliance checking.

### Problem

When repo A changes an SDD section that repo B depends on, repo B's compliance
may silently drift. Currently there is no mechanism to notify dependent repos.

### Event Format

```json
{
  "type": "sdd_change_notification",
  "version": 1,
  "source_repo": "0xHoneyJar/loa-hounfour",
  "source_pr": 42,
  "sdd_path": "grimoires/loa/sdd.md",
  "diff_summary": "Changed authentication middleware — JWT validation now requires aud claim",
  "changed_sections": ["authentication-middleware"],
  "affected_exports": ["AuthContext", "JWTValidator"],
  "timestamp": "2026-02-28T10:00:00Z"
}
```

### Transport Options

| Transport | Pros | Cons |
|-----------|------|------|
| **GitHub webhooks** | Native, low latency | Requires webhook setup per repo |
| **A2A protocol** | Already in Loa ecosystem | Not yet implemented cross-repo |
| **Shared event store** | Durable, auditable | Infrastructure dependency |
| **SDD index polling** | Simple, no infra | Latency, misses rapid changes |

### Recommended: GitHub Actions + SDD Index

1. Source repo's post-merge pipeline detects SDD changes
2. Generates `sdd_change_notification` event
3. Writes to a shared SDD index (GitHub Release asset or dedicated repo)
4. Dependent repos poll the index on their own bridge runs
5. If change affects their compliance profile → trigger review

### Prerequisite: Shared SDD Index

The SDD Index Hub (described above) must be standardized first. Each repo
publishes its `sdd-index.yaml`, and the notification system references
section IDs from this index.

### Reference

- loa-finn #31 ModelPort — capability discovery layer that could serve as
  transport for SDD change notifications
- Kubernetes Admission Webhooks — same pattern: specification changes trigger
  validation in dependent resources

## Open Questions

1. Should cross-repo SDDs be fetched live or cached locally?
2. Token budget allocation: how much context budget for cross-repo sections?
3. Should cross-repo findings be posted to source repo or consuming repo?
4. Should economic feedback be configurable per compliance gate profile?
5. What is the minimum iteration count before economic signals are meaningful?
