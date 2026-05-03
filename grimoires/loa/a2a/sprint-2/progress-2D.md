# Sub-sprint 2D Progress Report — L2 skill + integration

**Cycle**: cycle-098-agent-network
**Sprint**: 2 (L2 cost-budget-enforcer + reconciliation cron + daily snapshot)
**Sub-sprint**: 2D (4 of 4)
**Branch**: `feat/cycle-098-sprint-2`
**Status**: COMPLETED

## Outcome

L2 is operator-facing. The skill (`/cost-budget-enforcer`) advertises the
verdict gate to autonomous workflows; the CLI wrapper makes the same API
available from any shell context; the lore entry "fail-closed cost gate"
captures the architectural pattern for future cycle-098 sprints + cycle-099
candidates; and the config example documents every knob with environment-
variable overrides.

The full Sprint 2 surface is now:
- 6 per-event-type schemas
- 1 lib (`cost-budget-enforcer-lib.sh`)
- 1 SKILL.md
- 5 operator-facing scripts (`budget-cli.sh`, 2 reconcile-cron scripts,
  2 snapshot-cron scripts)
- 1 operator runbook
- 1 lore entry
- 4 BATS test files (67 tests cumulative)

## Files added

### Skill + CLI

| File | Purpose |
|------|---------|
| `.claude/skills/cost-budget-enforcer/SKILL.md` | Skill manifest — agent: general-purpose, allowed-tools Read+Bash; passes `validate-skill-capabilities.sh` |
| `.claude/scripts/budget/budget-cli.sh` | Thin CLI wrapper: `verdict`, `usage`, `record`, `reconcile` subcommands |

### Lore + config

| File | Purpose |
|------|---------|
| `grimoires/loa/lore/patterns.yaml` | New "fail-closed-cost-gate" entry; ~50 lines |
| `grimoires/loa/lore/index.yaml` | Index points at fail-closed-cost-gate (Active) |
| `.loa.config.yaml.example` | New `cost_budget_enforcer.*` + `audit_snapshot.cron_expression` blocks; ~70 lines |

### Schema example update

| File | Change |
|------|--------|
| `.claude/data/trajectory-schemas/agent-network-envelope.schema.json` | `event_type.examples` updated to include `budget.record_call` (the 6th L2 event type, per Sprint 2A) |

### Tests

| File | Type | Count | Status |
|------|------|-------|--------|
| `tests/integration/budget-cli.bats` | bats | 12 | 12 PASS / 0 FAIL |

## ACs satisfied — Sprint 2 final round-out

### CC-1..CC-11 (cross-cutting per sprint.md)

- CC-1 schema versioning: every envelope carries `schema_version: 1.1.0` (Sprint 1B major)
- CC-2 hash-chained: `prev_hash` chains L2 events; verified by `audit_verify_chain` (test #27)
- CC-3 flock atomicity: 3 concurrent cron firings serialize cleanly (Sprint 2B test #11)
- CC-4 envelope schema validation: ajv (R15 Python fallback) on every write
- CC-5 `/loa status` integration: not in 2D scope (Sprint 4.5 buffer task)
- CC-6 trust-store auto-verify: inherited from Sprint 1.5 #690
- CC-7 redaction allowlist: inherited (Sprint 1.5 #695 F8)
- CC-8 retention metadata: L2 retention_days=90, archive_after_days=90 (per
  `.claude/data/audit-retention-policy.yaml`)
- CC-9 compose-when-available: protected-class `budget.cap_increase` registered;
  L1 + L3 integration hooks documented (sprint plan deliverable for L1
  FR-L1-9 and L3 §3.3 task)
- CC-10 per-event schema registry: 6 schemas at
  `.claude/data/trajectory-schemas/budget-events/` (CC-10 + IMP-001 v1.1)
- CC-11 envelope schema additivity: examples extended with
  `budget.record_call` without breaking existing consumers

### Sprint plan deliverables (sprint.md)

- `.claude/skills/cost-budget-enforcer/SKILL.md` — DONE
- `lib/cost-budget-enforcer-lib.sh` — DONE (Sprint 2A)
- 10 ACs FR-L2-1..FR-L2-10 — DONE (with comprehensive test coverage)
- State machine: 5 verdicts × 5 uncertainty modes — DONE
- UTC-windowed daily cap, ±60s clock validation — DONE
- Per-provider counter + aggregate cap + sub-caps — DONE
- Reconciliation cron — DONE (Sprint 2B)
- BLOCKER on drift >5%, configurable threshold — DONE
- Audit-envelope event types — DONE (6 types)
- **Daily snapshot job for L1/L2 untracked logs** — DONE (Sprint 2C)
- Lore entry "fail-closed cost gate" — DONE
- Integration tests for billing API outage, counter drift, sudden cap
  change, clock drift, provider lag — DONE (cumulative across 2A/2B)

## Composition surface (compose-when-available)

L2 is callable from autonomous workflows via 4 entry points:

```
┌─────────────────────────────────────────────────────────────────┐
│  Caller flow                                                    │
│                                                                 │
│  (1) Pre-call gate                                              │
│      verdict = budget_verdict <est_usd> --provider <id>         │
│      if exit 1: HALT (do not make the paid call)                │
│                                                                 │
│  (2) Make the paid call                                         │
│                                                                 │
│  (3) Post-call accounting                                       │
│      budget_record_call <actual_usd> --provider <id>            │
│      [optional --verdict-ref <prev_hash>]                       │
│                                                                 │
│  (4) Background (cron-driven)                                   │
│      budget_reconcile every 6h                                  │
│      audit-snapshot.sh every 24h                                │
└─────────────────────────────────────────────────────────────────┘
```

Sprint 3 (L3 scheduled-cycle-template) consumes (1) in its pre-read phase
per FR-L3-6. Sprint 1's L1 FR-L1-9 also calls (1) for cost estimation when
L2 is enabled (compose-when-available stub already in L1 lib).

## Skill validation

`.claude/scripts/validate-skill-capabilities.sh`:
- `[cost-budget-enforcer] PASS` (frontmatter + capabilities + zone declarations)

## Outcome stats

- Files added: 7 (1 SKILL.md + 1 CLI script + 1 BATS + 1 lore entry +
  1 lore-index entry + 1 config-example block + 1 schema-examples update)
- Tests: 12 (12 PASS / 0 FAIL); cumulative Sprint 2 (2A+2B+2C+2D) = **67 / 67**
- Lore entries: +1 (fail-closed-cost-gate, Active)
- Skills: +1 (cost-budget-enforcer)
- CLI surface: 4 subcommands (verdict, usage, record, reconcile) + 4
  install/uninstall helpers across 2 cron families

## Sprint 2 ready for review

The sub-sprint 2D delivery completes Sprint 2's scope. The branch is ready
for the consolidated quality-gate chain:

1. `/review-sprint sprint-2` — expected iter-1 with 1-2 minor findings
2. Cross-model adversarial (gpt-5.3-codex)
3. `/audit-sprint sprint-2` — paranoid cypherpunk review
4. Bridgebuilder kaironic (inline `entry.sh --pr <N>`)
5. Admin-squash merge after convergence
