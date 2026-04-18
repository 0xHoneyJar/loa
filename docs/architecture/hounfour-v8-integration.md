# Hounfour v8 Integration Research

> **Status**: Living document — exploratory research + actionable proposals
> **Protocol version**: loa-hounfour@8.3.1 (2026-02-28)
> **Last updated**: 2026-03-02

## Context

Loa implements **structural correspondence** to hounfour protocol types — it doesn't `npm install` hounfour, but mirrors its patterns in shell, Python, and TypeScript. With hounfour v8.x shipping the commons module, governed resources, consumer contracts, and feedback dampening, there are concrete opportunities to either:

1. **Formalize** existing ad-hoc patterns using hounfour's type vocabulary
2. **Consume** hounfour utilities directly (where language/runtime permits)
3. **Align** schemas for cross-repo validation

This document maps hounfour v8.x capabilities against loa's codebase and proposes integration tiers.

---

## Integration Tiers

| Tier | Effort | Description |
|------|--------|-------------|
| **T1 — Schema Alignment** | Low | Align existing JSON structures to match hounfour schemas without changing behavior |
| **T2 — Structural Correspondence** | Medium | Refactor existing code to formally implement hounfour patterns |
| **T3 — Direct Consumption** | High | Import hounfour as a dependency in Python/TS layers |

---

## Opportunity Map

### 1. Flatline Dampened Scoring (T2)

**Current**: `bridge-state.sh` lines 449-497 — simple ratio threshold
```
flatline = (current_findings / initial_findings) < threshold  // for 2 consecutive iterations
```

**Hounfour offers**: `computeDampenedScore(oldScore, newScore, sampleCount, config)` — EMA with cold-start Bayesian prior, bounded feedback invariant `|result - old| <= alpha_max * |new - old|`

**Why it matters**: The current ratio check has no memory — a spike at iteration 3 followed by zero at iteration 4 triggers flatline, even if the pattern suggests instability. EMA dampening would detect true convergence more reliably.

**Proposal**:
```
# Replace in bridge-flatline-check.sh:

# OLD: simple ratio
# ratio = current / initial
# flatline = ratio < threshold AND consecutive >= 2

# NEW: dampened score
# dampened = ema(previous_dampened, current_score, iteration_count)
# flatline = dampened < threshold AND consecutive >= 2
```

The dampening config (`alpha_min=0.1, alpha_max=0.5, ramp_samples=50`) would live in `.loa.config.yaml` under `run_bridge.flatline.dampening`.

**Integration path**: Implement `compute_dampened_score()` in shell (arithmetic approximation) or call Python helper. The EMA formula is simple enough for awk:
```bash
# alpha = alpha_max - (alpha_max - alpha_min) * min(sample_count / ramp_samples, 1)
# dampened = alpha * new + (1 - alpha) * old
```

**Files touched**: `bridge-flatline-check.sh`, `bridge-state.sh`, `.loa.config.yaml.example`

**Risk**: Low — flatline detection is a signal, not a gate. False positives just add one more iteration.

---

### 2. Audit Trail Chain Hashing (T1/T2)

**Current**: `.run/audit.jsonl` — append-only JSONL with no integrity verification. Mutation logger hooks (`mutation-logger.sh`, `write-mutation-logger.sh`) append entries but don't chain them.

**Hounfour offers**:
- `computeAuditEntryHash(entry, domainTag)` — content-addressable hash per entry
- `computeChainBoundHash(entry, domainTag, previousHash)` — SHA-256 chain linking each entry to its predecessor
- `validateAuditTimestamp(input, options)` — strict ISO 8601 with drift detection
- `AUDIT_TRAIL_GENESIS_HASH` — standard chain genesis value

**Why it matters**: The audit trail currently has no tamper detection. A compromised hook or accidental truncation is invisible. Chain-bound hashing makes any gap or modification detectable.

**Proposal (T1 — Schema Alignment)**:
Add `content_hash` and `chain_hash` fields to audit entries:
```json
{
  "ts": "2026-03-02T10:00:00.000Z",
  "tool": "Bash",
  "command": "git push",
  "content_hash": "sha256:abc123...",
  "chain_hash": "sha256:def456...",
  "domain_tag": "loa:audit:mutation"
}
```

**Proposal (T2 — Structural Correspondence)**:
Implement `compute_chain_hash()` in shell:
```bash
compute_chain_hash() {
  local entry_json="$1" domain_tag="$2" prev_hash="$3"
  local content_hash
  content_hash=$(echo -n "$entry_json" | jq -Sc '.' | sha256sum | cut -d' ' -f1)
  echo -n "${domain_tag}:${content_hash}:${prev_hash}" | sha256sum | cut -d' ' -f1
}
```

**Files touched**: `mutation-logger.sh`, `write-mutation-logger.sh`, new `lib-audit-chain.sh`

**Risk**: Low — additive change to audit format. Verification is optional (run `verify-audit-chain.sh` when needed).

---

### 3. BudgetEnforcer as GovernedResource (T2)

**Current**: `budget.py` implements pre/post call hooks with flock-protected state files. `RemainderAccumulator` maintains conservation invariant.

**Hounfour offers**: `GovernedResource<TState, TEvent, TInvariant>` abstract base with:
- `transition(event, context)` → `TransitionResult<TState>`
- `verify(invariantId)` → `InvariantResult`
- `verifyAll()` → `InvariantResult[]`
- Built-in audit trail and mutation log

**Why it matters**: Budget enforcement is already a governed resource — it just doesn't know it yet. Formalizing it as `GovernedResource<BudgetState>` would give us:
- Explicit invariant IDs (`"conservation"`, `"daily_limit"`, `"non_negative"`)
- Typed transitions (`RESERVE`, `COMMIT`, `REFUND`, `RESET_DAILY`)
- Automatic audit trail integration
- `verifyAll()` for health checks

**Proposal**:
```python
class BudgetResource(GovernedResourceBase):
    """BudgetEnforcer expressed as GovernedResource<BudgetState>."""

    # State
    @dataclass
    class State:
        daily_spent_micro: int
        daily_limit_micro: int
        remainder_accumulated: int
        last_reset_date: str

    # Events
    RESERVE = "reserve"    # Pre-call budget reservation
    COMMIT = "commit"      # Post-call actual cost recording
    REFUND = "refund"      # Cancel reservation (call failed)
    RESET = "reset_daily"  # New day boundary

    # Invariants
    def define_invariants(self):
        return {
            "conservation": lambda s: s.daily_spent_micro >= 0,
            "daily_limit": lambda s: s.daily_spent_micro <= s.daily_limit_micro,
            "non_negative_remainder": lambda s: s.remainder_accumulated >= 0,
        }
```

**Files touched**: `budget.py`, `pricing.py` (refactor, not rewrite)

**Risk**: Medium — budget enforcement is safety-critical. Requires thorough testing of state transitions.

---

### 4. Consumer Contract for Loa's Structural Correspondence (T1)

**Current**: `capability-schema.md` documents which hounfour types loa structurally implements, but this is prose — not machine-verifiable.

**Hounfour offers**: `ConsumerContractSchema` + `validateConsumerContract()` — declare imported symbols, validate against actual exports, detect drift.

**Why it matters**: When hounfour ships v9, we need to know which loa patterns break. Currently this requires manual cross-referencing of the capability-schema.md table.

**Proposal**: Create `docs/architecture/hounfour-consumer-contract.json`:
```json
{
  "consumer": "loa",
  "provider": "@0xhoneyjar/loa-hounfour",
  "provider_version_range": ">=8.0.0",
  "consumption_mode": "structural_correspondence",
  "entrypoints": {
    "./composition": {
      "symbols": ["BridgeTransferSaga"],
      "loa_implementation": ".claude/adapters/loa_cheval/routing/chains.py"
    },
    "./governance": {
      "symbols": ["DelegationOutcome", "GovernanceProposal"],
      "loa_implementation": ".claude/scripts/flatline-orchestrator.sh"
    },
    "./economy": {
      "symbols": ["MonetaryPolicy"],
      "loa_implementation": ".claude/adapters/loa_cheval/metering/budget.py"
    },
    "./constraints": {
      "symbols": ["PermissionBoundary", "ConstraintCondition"],
      "loa_implementation": ".claude/data/constraints.json"
    },
    "./commons": {
      "symbols": ["GovernedResource", "AuditTrail", "TransitionResult", "InvariantResult"],
      "loa_implementation": "structural_candidate",
      "status": "proposed"
    }
  },
  "generated_at": "2026-03-02T00:00:00Z"
}
```

This extends hounfour's contract schema with `consumption_mode: "structural_correspondence"` and `loa_implementation` fields specific to our use case.

**Files touched**: New `docs/architecture/hounfour-consumer-contract.json`

**Risk**: None — documentation artifact only.

---

### 5. Bridge State Machine Formalization (T2)

**Current**: `bridge-state.sh` lines 35-47 — states as strings, transitions validated against a bash associative array `VALID_TRANSITIONS`.

**Hounfour offers**: `StateMachine`, `Transition`, `TransitionResult<T>` schemas with formal state/event modeling.

**Why it matters**: The bridge state machine is the most complex state machine in loa (7 states, 12+ valid transitions, halted reachable from most states). Formalizing it would:
- Make invalid transitions structurally impossible (not just runtime-checked)
- Align bridge state with hounfour's DDD vocabulary (`isTerminalState()`, `getValidTransitions()`)
- Enable cross-repo state machine composition (when finn hosts bridge sessions)

**Proposal**: Define bridge state machine in hounfour vocabulary:
```yaml
# .claude/data/state-machines/bridge.yaml
id: bridge_orchestrator
states:
  - PREFLIGHT
  - JACK_IN
  - ITERATING
  - RESEARCHING
  - EXPLORING
  - FINALIZING
  - JACKED_OUT  # terminal
  - HALTED      # terminal (recoverable via --resume)
transitions:
  - from: PREFLIGHT, to: JACK_IN, event: preflight_passed
  - from: JACK_IN, to: ITERATING, event: iteration_started
  - from: ITERATING, to: ITERATING, event: iteration_completed
  - from: ITERATING, to: FINALIZING, event: flatline_detected
  - from: ITERATING, to: HALTED, event: error_or_timeout
  - from: FINALIZING, to: JACKED_OUT, event: finalization_complete
  - from: FINALIZING, to: HALTED, event: error_or_timeout
  # ... (halted reachable from ITERATING, FINALIZING, RESEARCHING, EXPLORING)
terminal_states: [JACKED_OUT, HALTED]
initial_state: PREFLIGHT
```

The runtime (`bridge-state.sh`) would load this definition and validate transitions against it, replacing the hardcoded associative array.

**Files touched**: New `.claude/data/state-machines/bridge.yaml`, `bridge-state.sh` (refactor transition validation)

**Risk**: Low-medium — the state machine logic doesn't change, just the validation source.

---

### 6. Constraint Registry Formalization (T1/T2)

**Current**: `constraints.json` with `construct_yield`, `rule_type`, `severity` — a proto-governance system.

**Hounfour offers**: `ConstraintCondition` with `when` (feature flag predicate) and `override_text` (conditional rule modification).

**Why it matters**: The `construct_yield` mechanism is loa's most sophisticated governance pattern — constraints that adapt when constructs are active. Aligning this with hounfour's `ConstraintCondition` would:
- Make constraint evaluation formally testable
- Enable cross-repo constraint sharing (constructs could declare constraints)
- Align with hounfour's constraint DSL evaluator (36 builtins)

**Proposal**: Extend constraint schema with hounfour-aligned `condition` field:
```json
{
  "id": "C-PROC-001",
  "condition": {
    "when": "construct.workflow.gates.includes('implement')",
    "override_text": "OR when a construct with declared workflow.gates owns the current workflow"
  }
}
```

This maps cleanly to hounfour's `ConstraintCondition` interface. The `construct_yield` field becomes syntactic sugar over the formalized `condition`.

**Files touched**: `constraints.schema.json`, `constraints.json` (additive field), constraint rendering in `CLAUDE.loa.md` generator

**Risk**: Low — additive schema extension. Existing `construct_yield` continues to work.

---

### 7. Feature Flag Registry (T1)

**Current**: Feature flags scattered across `.loa.config.yaml` — `flatline_protocol.enabled`, `hounfour.feature_flags.*`, `metering.enabled`, `run_mode.enabled`, etc. No centralized registry.

**Hounfour offers**: `ConstraintCondition` + `EvaluationContext.feature_flags` — formal feature flag gating for constraints.

**Proposal**: Create `.claude/data/feature-flags.json`:
```json
{
  "schema_version": 1,
  "flags": [
    {
      "id": "FF-001",
      "name": "flatline_protocol",
      "config_path": "flatline_protocol.enabled",
      "default": true,
      "description": "Multi-model adversarial review",
      "gates": ["C-FLAT-001", "C-FLAT-002"]
    },
    {
      "id": "FF-002",
      "name": "hounfour_routing",
      "config_path": "hounfour.flatline_routing",
      "default": false,
      "description": "Route Flatline calls through model-invoke (cheval.py)",
      "gates": []
    }
  ]
}
```

**Files touched**: New `.claude/data/feature-flags.json`, new `.claude/schemas/feature-flags.schema.json`

**Risk**: None — documentation/registry artifact only.

---

### 8. Metering Ledger as Hounfour AuditTrail (T2)

**Current**: `ledger.py` writes JSONL entries with `ts`, `trace_id`, `cost_micro_usd`, etc. Uses `fcntl.flock(LOCK_EX)` for atomic appends.

**Hounfour offers**: `AuditTrail` schema with typed entries, hash chain integrity, and checkpoint support.

**Why it matters**: The metering ledger IS an audit trail — it tracks every API call, its cost, and its billing classification. Aligning it with hounfour's `AuditTrail` schema enables:
- Chain-bound integrity verification (`computeChainBoundHash()`)
- Checkpoint-based pruning (`createCheckpoint()`, `pruneBeforeCheckpoint()`)
- Cross-repo audit compatibility (freeside reads loa's metering ledger)

**Proposal**: Add chain hash to ledger entries:
```python
# In ledger.py create_ledger_entry():
entry["domain_tag"] = f"loa:metering:{agent}"
entry["content_hash"] = compute_content_hash(entry)
entry["chain_hash"] = compute_chain_hash(entry, previous_hash)
```

**Files touched**: `ledger.py`, potentially new `audit_chain.py` utility

**Risk**: Low — additive fields. Existing consumers ignore unknown fields.

---

### 9. X402 Payment Schema Awareness (T1)

**Current**: Loa doesn't participate in x402 payment flows — that's freeside/arrakis territory. But loa generates the cost data that feeds x402 quotes.

**Hounfour offers**: `X402QuoteSchema`, `X402PaymentProofSchema`, `X402SettlementSchema` — full HTTP 402 machine payment flow.

**Why it matters**: When freeside bills for loa sessions, the metering data from `ledger.py` becomes the input for x402 quotes. Understanding the schema alignment ensures loa's cost reporting matches what freeside expects.

**Proposal**: Document the data flow in this file (no code changes needed):
```
loa metering (ledger.py)
  → cost_micro_usd per call
  → daily_spend aggregation
  ↓
freeside gateway
  → X402Quote { cost_per_input_token_micro, cost_per_output_token_micro }
  → X402Settlement { actual_cost_micro }
  ↓
arrakis billing
  → lot_invariant (conservation)
```

**Files touched**: This document only.

**Risk**: None — awareness/documentation only.

---

## Priority Matrix

| # | Opportunity | Tier | Effort | Impact | Priority |
|---|-----------|------|--------|--------|----------|
| 4 | Consumer Contract | T1 | Small | High — drift detection | **P0** |
| 1 | Dampened Flatline | T2 | Medium | Medium — better convergence | **P1** |
| 2 | Audit Chain Hash | T1/T2 | Medium | High — tamper detection | **P1** |
| 7 | Feature Flag Registry | T1 | Small | Medium — observability | **P2** |
| 5 | Bridge State Machine | T2 | Medium | Medium — formal transitions | **P2** |
| 6 | Constraint Conditions | T1/T2 | Medium | Medium — cross-repo constraints | **P2** |
| 3 | Budget as GovernedResource | T2 | Large | High — full governance | **P3** |
| 8 | Metering AuditTrail | T2 | Medium | Medium — chain integrity | **P3** |
| 9 | X402 Awareness | T1 | Tiny | Low — documentation | **P3** |

---

## Sequencing Recommendation

**Phase 1 — Schema Alignment** (1 cycle):
- Consumer Contract (P0)
- Feature Flag Registry (P2)
- Audit entry schema alignment (T1 portion of #2)

**Phase 2 — Structural Correspondence** (1-2 cycles):
- Dampened Flatline scoring (#1)
- Audit chain hashing (#2 T2 portion)
- Bridge state machine formalization (#5)

**Phase 3 — Deep Integration** (future):
- BudgetEnforcer as GovernedResource (#3)
- Constraint condition alignment (#6)
- Metering AuditTrail (#8)

---

## Related Documents

- [Capability Schema](capability-schema.md) — Type mapping table (updated for v8.x)
- [Ecosystem Architecture](../ecosystem-architecture.md) — 5-layer stack overview
- [Separation of Concerns](separation-of-concerns.md) — Three-Layer Model
- [loa-hounfour MIGRATION.md](https://github.com/0xHoneyJar/loa-hounfour/blob/main/MIGRATION.md)
- [loa-hounfour CHANGELOG.md](https://github.com/0xHoneyJar/loa-hounfour/blob/main/CHANGELOG.md)
