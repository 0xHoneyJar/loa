---
name: graduated-trust
description: L4 graduated-trust ledger — per-(scope, capability, actor) trust tier with hash-chained immutable history, configurable transitions, auto-drop on operator override + cooldown enforcement, and force-grant audit-logged exceptions
agent: general-purpose
context: scoped
parallel_threshold: 3000
timeout_minutes: 5
zones:
  system:
    path: .claude
    permission: read
  state:
    paths: [grimoires/loa, .run]
    permission: read-write
  app:
    paths: [src, lib, app]
    permission: read
allowed-tools: Read, Bash
capabilities:
  schema_version: 1
  read_files: true
  search_code: false
  write_files: false
  execute_commands: true
  web_access: false
  user_interaction: false
  agent_spawn: false
  task_management: false
cost-profile: lightweight
---

# graduated-trust — L4 Per-(scope,capability,actor) Trust Ledger (cycle-098 Sprint 4)

## Purpose

The L4 primitive maintains a per-(scope, capability, actor) trust ledger
where trust **ratchets up** by demonstrated alignment (operator-driven
grants) and **ratchets down automatically** on observed override (record-
override → auto-drop + cooldown). The ledger is hash-chained for tamper
detection and TRACKED in git for reconstructability if the working-tree
file is lost.

This is the **relational trust model** for the agent network: it answers
"how much autonomy may actor A exercise in capability C of scope S?" with
an evidence-grounded tier rather than a hardcoded permission.

## Source

- RFC: [#656](https://github.com/0xHoneyJar/loa/issues/656)
- PRD: `grimoires/loa/cycles/cycle-098-agent-network/prd.md` §FR-L4
- SDD: `grimoires/loa/cycles/cycle-098-agent-network/sdd.md` §1.4.2 + §5.6
- Sprint plan: `grimoires/loa/sprint.md` (cycle-098 Sprint 4 row at the time of cycle-098; also reproduced in this cycle's grimoire)

## Public API

All functions are sourced from `.claude/scripts/lib/graduated-trust-lib.sh`.

| Function | Purpose | Exit | FR |
|----------|---------|------|-----|
| `trust_query <scope> <capability> <actor>` | Read TrustResponse JSON | 0/2 | FR-L4-1 |
| `trust_grant <scope> <capability> <actor> <new_tier> --reason <r> [--operator <o>]` | Operator-driven raise (subject to transition_rules + cooldown) | 0/1/2/3 | FR-L4-2 |
| `trust_grant ... --force --reason <r>` | Force-grant exception (cooldown bypass; audit-logged with cooldown_remaining) | 0/1/2/3 | FR-L4-8 |
| `trust_record_override <scope> <capability> <actor> <decision_id> <reason>` | Auto-drop on observed override; starts cooldown | 0/1/2/3 | FR-L4-3 |
| `trust_verify_chain` | Hash-chain integrity walk | 0/1/2 | FR-L4-5 |
| `trust_recover_chain` | Reconstruct from git history | 0/1/2 | FR-L4-7 |
| `trust_auto_raise_check <scope> <capability> <actor> <next_tier>` | Auto-raise eligibility stub (FU-3 deferral) | 0/1/2 | FR-L4-4 |
| `trust_disable --reason <r> --operator <o>` | Seal ledger (immutable; reads still work) | 0/1/2/3 | PRD §849 |

## Configuration

```yaml
# .loa.config.yaml
graduated_trust:
  enabled: true
  default_tier: T0
  tier_definitions:
    T0:
      description: "No autonomous action permitted; operator-bound for all decisions"
    T1:
      description: "Routine read-only operations permitted; mutations require operator confirmation"
    T2:
      description: "Routine mutations permitted; production / destructive operations operator-bound"
    T3:
      description: "Full autonomous action; only protected-class decisions operator-bound"
  transition_rules:
    - { from: T0, to: T1, requires: operator_grant, id: T0_to_T1 }
    - { from: T1, to: T2, requires: operator_grant, id: T1_to_T2 }
    - { from: T2, to: T3, requires: operator_grant, id: T2_to_T3 }
    # Auto-drop rules (per from_tier explicit, OR any/to_lower:true to default_tier)
    - { from: T2, to: T1, via: auto_drop_on_override }
    - { from: T3, to: T1, via: auto_drop_on_override }
    - { from: any, to_lower: true, via: auto_drop_on_override }
  cooldown_seconds: 604800   # 7 days
```

## TrustResponse shape (SDD §5.6.2)

```json
{
  "scope": "flatline",
  "capability": "merge_main",
  "actor": "deep-name",
  "tier": "T2",
  "transition_history": [
    { "from_tier": null, "to_tier": "T1", "transition_type": "initial",
      "ts_utc": "...", "decision_id": null, "reason": "alignment-validated" },
    { "from_tier": "T1", "to_tier": "T2", "transition_type": "operator_grant",
      "ts_utc": "...", "decision_id": null, "reason": "after sprint-N pass" }
  ],
  "in_cooldown_until": null,
  "auto_raise_eligible": false
}
```

Schema: `.claude/data/trajectory-schemas/trust-events/trust-response.schema.json`

## Semantics

### Default tier (FR-L4-1)

The first query for any (scope, capability, actor) triple returns the configured `default_tier` (default `T0` when unset). No ledger writes happen on read.

### Transition validation (FR-L4-2)

Only `operator_grant` rules permit raises. Arbitrary jumps (T0→T3) reject with exit 3 unless a rule explicitly allows them. Re-granting the current tier is rejected as no-op.

### Auto-drop + cooldown (FR-L4-3)

`trust_record_override` looks up the `auto_drop_on_override` rule for the current tier (explicit `from: <tier>` preferred; `from: any, to_lower: true` falls through to `default_tier`). The auto-drop event captures **frozen** `cooldown_until = ts_utc + cooldown_seconds` in the payload — operators can change `cooldown_seconds` later without retroactively shifting past windows (audit-immutability).

Rolling cooldown: every override re-arms the timer. Each override is a distinct ledger entry (same hash chain).

### Force-grant exception (FR-L4-8)

`trust_grant --force --reason <r>` overrides cooldown. The event records `cooldown_remaining_seconds_at_grant` (0 when force fires outside cooldown) and `cooldown_until_at_grant` for auditor evidence. `trust.force_grant` is registered in `protected-classes.yaml` — callers using it are operator-bound by definition.

### Hash-chain (FR-L4-5)

The ledger is a JSONL chain via `audit-envelope.sh::audit_emit`: each entry's `prev_hash` references the SHA-256 of the prior entry's canonical (RFC 8785 JCS) form. Tampering with any byte breaks the chain — `trust_verify_chain` walks it and returns non-zero on first break.

### Reconstruction from git (FR-L4-7)

`.run/trust-ledger.jsonl` is **TRACKED** in git per SDD §3.7. `trust_recover_chain` walks `git log` newest-to-oldest; the first commit whose file content validates becomes the recovery base. `[CHAIN-GAP-RECOVERED-FROM-GIT commit=<sha>]` and `[CHAIN-RECOVERED source=git_history]` markers are appended.

### Auto-raise stub (FR-L4-4 / FU-3)

`trust_auto_raise_check` always returns `eligibility_required` in cycle-098. The auto-raise *eligibility detector* (e.g., 7-consecutive-aligned alignment-tracking) is deferred to FU-3. The lib emits a `trust.auto_raise_eligible` audit event so consultations are visible.

### Disable / seal (PRD §849)

`trust_disable --reason <r> --operator <o>` writes `trust.disable` as the final event. After sealing, reads still return last-known-tier; further grants/overrides reject. Re-disable is a no-op (idempotent).

## Concurrency model (FR-L4-6)

The lib uses TWO distinct lock files to avoid deadlock:

| File | Purpose | Holder |
|------|---------|--------|
| `<ledger>.txn.lock` | Read-modify-write transaction (cooldown check vs concurrent writer) | trust_grant / trust_record_override / trust_disable |
| `<ledger>.lock` | Chain-append exclusion | audit_emit (1A library) |

Per FR-L4-6, concurrent writes from runtime + cron + CLI are flock-based-serialized. Tests:
- `tests/integration/trust-concurrent-writes.bats` — 10+ parallel writers across 3 simulated entry points (runtime, cron, CLI) all converge to a valid chain

## Composition

| Layer | Used for |
|-------|----------|
| 1A audit envelope | hash-chain + signing + chain recovery |
| 1B signing | Ed25519 sigs honored when LOA_AUDIT_SIGNING_KEY_ID is set |
| 1B protected-class-router | trust.force_grant pre-classified protected |
| 1B operator-identity | LOA_TRUST_REQUIRE_KNOWN_ACTOR=1 enforces OPERATORS.md |

## Environment overrides

| Var | Effect |
|-----|--------|
| `LOA_TRUST_LEDGER_FILE` | override `.run/trust-ledger.jsonl` path |
| `LOA_TRUST_CONFIG_FILE` | override `.loa.config.yaml` path |
| `LOA_TRUST_TEST_NOW` | test-only "now" override (ISO-8601) |
| `LOA_TRUST_EMIT_QUERY_EVENTS=1` | emit `trust.query` events on read (default off) |
| `LOA_TRUST_REQUIRE_KNOWN_ACTOR=1` | reject unknown actor/operator (OPERATORS.md gate) |
| `LOA_TRUST_DEFAULT_TIER` | env override of `graduated_trust.default_tier` |
| `LOA_TRUST_COOLDOWN_SECONDS` | env override of `graduated_trust.cooldown_seconds` |

## Operator quickstart

```bash
# Read current tier
.claude/scripts/lib/graduated-trust-lib.sh   # source it from your own script
trust_query flatline merge_main deep-name

# Grant T0 -> T1 (assuming a configured T0_to_T1 rule)
trust_grant flatline merge_main deep-name T1 --reason "validated initial alignment"

# Record a panel override -> auto-drop + cooldown
trust_record_override flatline merge_main deep-name "panel-decision-2026-05-07" "operator overrode panel"

# Emergency force-grant during cooldown
trust_grant flatline merge_main deep-name T2 --force --reason "incident response"

# Verify the chain
trust_verify_chain && echo "intact"

# Reconstruct from git history if local file lost
trust_recover_chain
```

## Failure modes

| Mode | Symptom | Recovery |
|------|---------|----------|
| `[L4-DISABLED]` ledger | grants/overrides exit 3 with "ledger is sealed" | Operator re-init: rotate ledger file path; previous file kept as immutable archive |
| `[CHAIN-BROKEN]` after recovery failure | trust_verify_chain non-zero; trust_recover_chain returns 1 | Operator inspects `git log` manually; restores from offline backup |
| no `auto_drop_on_override` rule configured | trust_record_override exits 3 | Operator MUST add a rule (the lib refuses to invent drop semantics) |
| trust-store INVALID | audit_emit refuses; grants exit 1 | Per `audit-keys-bootstrap` runbook |

## Tests

| Suite | Location | Tests |
|-------|----------|-------|
| schemas | `tests/unit/trust-events-schemas.bats` | 10 |
| validators + config getters | `tests/unit/graduated-trust-lib-defaults.bats` | 21 |
| trust_query (FR-L4-1) | `tests/integration/trust-query-default-tier.bats` | 17 |
| trust_grant + trust_record_override (FR-L4-2 + FR-L4-3) | `tests/integration/trust-grant-and-override.bats` | 21 |
| chain integrity + reconstruction + force-grant + auto-raise (FR-L4-4 + FR-L4-5 + FR-L4-7 + FR-L4-8) | `tests/integration/trust-chain-and-force-grant.bats` | 16 |
| concurrent writes (FR-L4-6) + disable seal | `tests/integration/trust-concurrent-and-disable.bats` | (Sprint 4D) |

Total: 100+ tests across the four sub-sprints.
