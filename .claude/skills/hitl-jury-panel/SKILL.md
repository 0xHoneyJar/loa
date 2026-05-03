---
name: hitl-jury-panel
description: L1 jury-panel adjudication primitive — convenes ≥3 panelists, logs reasoning, selects binding view via deterministic seed
agent: general-purpose
context: scoped
parallel_threshold: 3000
timeout_minutes: 30
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

# hitl-jury-panel — L1 Adjudication Skill (cycle-098 Sprint 1)

## Purpose

Replace `AskUserQuestion`-class decisions during operator absence with a panel of ≥3 deliberately-diverse panelists. Each panelist (model + persona) returns a view and reasoning; the skill logs all views BEFORE selection, then picks one binding view via a deterministic seed derived from `(decision_id, context_hash)`. Provides an autonomous adjudication primitive without compromising auditability.

## Source

- RFC: [#653](https://github.com/0xHoneyJar/loa/issues/653)
- PRD: `grimoires/loa/prd.md` §FR-L1
- SDD: `grimoires/loa/sdd.md` §1.4.2 (L1 component spec) + §5.3 (full API)
- Decision: cycle-098-agent-network active per `grimoires/loa/ledger.json`

## When to use

| Scenario | Use this skill? |
|----------|-----------------|
| Routine decision normally requiring `AskUserQuestion` during a sleep window | YES |
| Protected-class decision (deploy, credential rotation, schema migration) | NO — short-circuits to `QUEUED_PROTECTED` |
| Single-binding-actor decision (e.g., merge to main) | NO — operator-bound |
| Schema migration or destructive irreversible | NO — protected class |
| Ad-hoc ad-libitum question with no decision | NO — use a single panelist or `AskUserQuestion` |

## Configuration

`.loa.config.yaml::hitl_jury_panel.*` (opt-in; disabled by default per `enabled: false`):

```yaml
hitl_jury_panel:
  enabled: false
  default_panelists:
    - id: persona-a
      model: claude-opus-4-7
      persona_file: .claude/data/personas/persona-a.md
    - id: skeptic
      model: claude-opus-4-7
      persona_file: .claude/data/personas/skeptic.md
    - id: alternative-model
      model: gpt-5.3-codex
      persona_file: .claude/data/personas/alternative-model.md
  selection: random            # random | (future: weighted | round-robin)
  seed_source: decision_id+context_hash
  audit_log: .run/panel-decisions.jsonl
  default_disagreement_threshold: 0.5
```

## Library API

The skill is implemented as a library at `.claude/scripts/lib/hitl-jury-panel-lib.sh`. Source it and call:

```bash
source .claude/scripts/lib/hitl-jury-panel-lib.sh

# Top-level
panel_invoke <decision_id> <decision_class> <context_hash> <panelists_yaml> <context_path>
# Returns JSON: {outcome, binding_view, selected_panelist_id, selection_seed, minority_dissent, audit_log_entry_id, diagnostic}

# Sub-functions
panel_solicit <panelist_id> <model> <persona_path> <context_path> [--timeout <s>]
panel_select <panelists_json> <decision_id> <context_hash>
panel_log_views <decision_id> <panelists_with_views_json> <log_path>
panel_log_binding <decision_id> <selected_panelist_id> <seed> <minority_dissent_json> <log_path>
panel_log_queued_protected <decision_id> <decision_class> <log_path>
panel_log_fallback <decision_id> <fallback_path> <panelists_json> <log_path>
panel_check_disagreement <panelists_views_json> <threshold>
```

The CLI form:

```bash
.claude/scripts/lib/hitl-jury-panel-lib.sh invoke <decision_id> <decision_class> <context_hash> <panelists_yaml> <context_path>
```

## Composition (DOES NOT reinvent)

| Layer | Source | Used for |
|-------|--------|----------|
| Audit envelope (write/chain) | `.claude/scripts/audit-envelope.sh` (Sprint 1A) | All panel events emit JSONL envelopes via `audit_emit` |
| Ed25519 signing | `.claude/scripts/audit-envelope.sh` (Sprint 1B) | When `LOA_AUDIT_SIGNING_KEY_ID` is set, panel events are signed |
| Protected-class router | `.claude/scripts/lib/protected-class-router.sh` (Sprint 1B) | Pre-flight short-circuit on protected `decision_class` |
| Operator identity | `.claude/scripts/operator-identity.sh` (Sprint 1B) | NOT consumed here; caller's responsibility |
| Sanitize for session-start | `.claude/scripts/lib/context-isolation-lib.sh` (Sprint 1C) | Wraps panelist context as untrusted-content (`L7` source) before passing to `model-invoke` |
| Hash-chain recovery | `.claude/scripts/audit-envelope.sh::audit_recover_chain` (Sprint 1C) | Operator runbook recovers `.run/panel-decisions.jsonl` from snapshot archive after corruption |
| Tier validator | `.claude/scripts/tier-validator.sh` (Sprint 1C) | Boot-time check classifies enabled primitive set into Tier 0..4 |

## Decision flow

1. **Pre-flight protected check** — if `is_protected_class(decision_class)` matches, emit `panel.queued_protected`, append to `.run/protected-queue.jsonl`, return `outcome: QUEUED_PROTECTED`.
2. **Read panelist config** from the `panelists_yaml` argument (operator-supplied; defaults shipped at `.claude/data/personas/*.md`).
3. **Solicit panelists in parallel** — each panelist invokes `model-invoke --model <model> --prompt <sanitized-context>`. Per-panelist timeout via `LOA_PANEL_PER_PANELIST_TIMEOUT` (default 60s).
4. **Log views BEFORE selection** (FR-L1-2) — emit `panel.solicit` envelope to `.run/panel-decisions.jsonl`. If skill crashes after this point, all panelist views are auditable.
5. **Apply fallback matrix** (FR-L1-5):
   - All panelists fail → `panel.fallback` with `fallback_path: all_fail`; outcome `FALLBACK`.
   - Surviving < `LOA_PANEL_MIN_PANELISTS` (default 2) → `panel.fallback` with `fallback_path: tertiary_unavailable`; outcome `FALLBACK`.
   - Otherwise → continue with degraded set.
6. **Compute seed + select binding view** (FR-L1-3) — `seed = sha256(decision_id || context_hash)`; selected index = `seed % len(sorted-by-id panelists)`. Sorting by id ensures cross-process determinism.
7. **Disagreement check** (FR-L1-6) — caller-configurable via `LOA_PANEL_DISAGREEMENT_FN` env var pointing to a script. Default behavior: no-op pass.
8. **Bind + log** (FR-L1-7) — emit `panel.bind` envelope with full PanelDecision payload (panelists, seed, selected_panelist_id, binding_view, minority_dissent, fallback_path, cost_estimate_usd, trust_check_result).

## Audit log shape

Per-event types written to `.run/panel-decisions.jsonl`:

| `event_type` | When | Payload schema |
|--------------|------|----------------|
| `panel.solicit` | All panelist views logged BEFORE selection (FR-L1-2) | `{decision_id, panelists[]}` where each panelist has `{id, model, persona_path, view, reasoning_summary, error, timed_out, duration_seconds}` |
| `panel.bind` | Binding view selected (FR-L1-7) | Full PanelDecision per SDD §5.3.3 |
| `panel.queued_protected` | Pre-flight short-circuit (FR-L1-4) | `{decision_id, decision_class, route, queued_at}` |
| `panel.queued_disagree` | Caller-supplied disagreement fn flagged (FR-L1-6) | `{decision_id, panelists[], route, reason}` |
| `panel.fallback` | Surviving panel below min OR all-fail (FR-L1-5) | `{decision_id, fallback_path, panelists[], outcome: FALLBACK}` |

All envelopes inherit the Sprint 1A schema (`schema_version`, `primitive_id: "L1"`, `ts_utc`, `prev_hash`, `payload`, `redaction_applied`) and Sprint 1B signing fields when `LOA_AUDIT_SIGNING_KEY_ID` is set.

## Distribution audit (FR-L1-8)

Periodic post-ship telemetry script: `.claude/scripts/panel-distribution-audit.sh`

```bash
# Emit markdown report (default)
.claude/scripts/panel-distribution-audit.sh

# Emit JSON
.claude/scripts/panel-distribution-audit.sh --json

# Override window or log path
.claude/scripts/panel-distribution-audit.sh --log .run/panel-decisions.jsonl --window-days 30
```

Exits 1 when `N≥10` decisions in window AND any panelist exceeds 50% selection rate.

## Cost integration (FR-L1-9)

L2 (cost-budget-enforcer) is unimplemented in cycle-098 Sprint 1. The skill leaves `cost_estimate_usd: null` in the binding payload. When L2 lands (Sprint 2), the panel pre-flight will call `budget_verdict` and write the estimate into the envelope.

## Environment variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `LOA_PANEL_AUDIT_LOG` | Path for audit log | `.run/panel-decisions.jsonl` |
| `LOA_PANEL_PROTECTED_QUEUE` | Path for protected queue | `.run/protected-queue.jsonl` |
| `LOA_PANEL_PER_PANELIST_TIMEOUT` | Per-panelist timeout (seconds) | `60` |
| `LOA_PANEL_MIN_PANELISTS` | Minimum surviving panelists for `BOUND` | `2` |
| `LOA_PANEL_DISAGREEMENT_THRESHOLD` | Caller-supplied threshold | `0.5` |
| `LOA_PANEL_DISAGREEMENT_FN` | Path to caller-supplied disagreement fn (executable) | unset (no-op pass) |
| `LOA_AUDIT_SIGNING_KEY_ID` | Sprint 1B — when set, panel events are signed | unset |

## Tests

| File | Type | Count | Covers |
|------|------|-------|--------|
| `tests/integration/hitl-jury-panel-skill.bats` | bats | 7 | FR-L1-1, FR-L1-2, FR-L1-3, FR-L1-7 (full skill) |
| `tests/unit/panel-deterministic-seed.bats` | bats | 9 | FR-L1-3 (seed determinism) |
| `tests/integration/panel-protected-class.bats` | bats | 7 | FR-L1-4 (protected-class short-circuit) |
| `tests/integration/panel-fallback-matrix.bats` | bats | 4 | FR-L1-5 (4 fallback cases) |
| `tests/unit/panel-audit-envelope.bats` | bats | 6 | FR-L1-7 (envelope schema + signing) |
| `tests/unit/panel-disagreement-no-op-default.bats` | bats | 5 | FR-L1-6 (default no-op + caller pluggability) |
| `tests/unit/panel-distribution-audit.bats` | bats | 7 | FR-L1-8 (distribution audit) |

**Total: 45 tests across 7 files; all PASS.**

## Operator runbook

- **Disable**: set `hitl_jury_panel.enabled: false` (default). Skill becomes a no-op.
- **Add a panelist**: extend `default_panelists` in `.loa.config.yaml`; ensure the persona file exists.
- **Run distribution audit**: `.claude/scripts/panel-distribution-audit.sh` — review violations and rotate panelists if a panelist concentrates >50% of selections.
- **Recover from corrupted audit log**: see Sprint 1C handoff doc; `audit_recover_chain .run/panel-decisions.jsonl` will rebuild from snapshot archive.
- **Rotate signing key**: see Sprint 1B handoff doc; the trust-store at `grimoires/loa/trust-store.yaml` carries the key registry.
