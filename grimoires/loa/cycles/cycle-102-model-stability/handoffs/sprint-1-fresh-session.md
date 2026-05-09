# Sprint 1 Fresh-Session Handoff

**Date**: 2026-05-09
**Author**: prior session (post #801 merge, paused before sprint-1 implementation)
**State**: pre-flight complete, no implementation work landed yet
**Resume command**: `/run-resume` OR (preferred) start fresh and re-invoke `/run sprint-1` after reading this doc

## Branch + state preserved

- **Branch**: `feature/feat/cycle-102-sprint-1` (created via ICE off `main`)
- **`.run/state.json`**: target=`sprint-1`, cycle=`cycle-102-model-stability`, state=`RUNNING`, mode=`autonomous`, branch tracked
- **No commits yet** on the feature branch — purely pre-flight scaffolding

## Live verification evidence (run before sprint-1 begins)

I directly tested model-adapter.sh against the same Flatline-shape calls that silently degraded 4× during cycle-102 kickoff. Reproducing the bug live:

```bash
# Works — opus skeptic on PRD: 7.4KB structured JSON, 0 retries, 35s
.claude/scripts/model-adapter.sh --model opus --mode skeptic --phase prd --input /tmp/loa-smoke-prd.md

# WORKS — gemini-3.1-pro skeptic on PRD: 6.9KB, 0 retries, 29s
.claude/scripts/model-adapter.sh --model gemini-3.1-pro --mode skeptic --phase prd --input /tmp/loa-smoke-prd.md

# BROKEN — gpt-5.5-pro skeptic: empty response content × 3 retries
# Same failure mode as cycle-102 kickoff (flatline-prd-degradation.md)
.claude/scripts/model-adapter.sh --model gpt-5.5-pro --mode skeptic --phase prd --input /tmp/loa-smoke-prd.md
```

Cheval path (used by Red Team) works fine for the same model on the same prompt:

```bash
# WORKS — bypasses model-adapter.sh, routes through cheval.py
.claude/scripts/model-invoke --agent flatline-skeptic --model gpt-5.5-pro --prompt "..."
# Returns: structured JSON, 2 concerns identified, model=gpt-5.5-pro-2026-04-23
```

**Conclusion**: bug is in `model-adapter.sh`'s OpenAI path (`/v1/responses` parsing or routing), NOT in cheval and NOT in BB's TS adapters. Sprint 1 deliverable #10 (legacy adapter `max_output_tokens` per-model lookup) closes A1+A2 from sprint-bug-143 — but the empty-content failure may need its own diagnosis (token-limit failure produces truncation, not empty; this looks like a parsing or response-shape issue).

## Workaround available without code changes

`.loa.config.yaml`:
```yaml
hounfour:
  flatline_routing: true   # currently false
```

Routes Flatline through cheval (verified working for gpt-5.5-pro) instead of `model-adapter.sh` (verified broken). Two-line config change. Untested for full Flatline orchestrator end-to-end but the underlying call path is the same one Red Team uses successfully.

This is not a substitute for the sprint — it's a tactical band-aid until Sprint 1 lands.

## Sprint 1 — 10 deliverables (per `grimoires/loa/cycles/cycle-102-model-stability/sprint.md`)

Local ID: 1, Global ID: 143. Per the global-ID convention, **outputs likely belong in `grimoires/loa/a2a/sprint-143/`** (NOT `sprint-1/`, which already has cycle-099 sprint-1A/B/C/D artifacts including a `COMPLETED` marker — confirm this in the next session before writing anywhere).

| # | Deliverable | Notes |
|---|---|---|
| 1 | `model-error.schema.json` at `.claude/data/trajectory-schemas/` | 10 error classes (TIMEOUT, PROVIDER_DISCONNECT, BUDGET_EXHAUSTED, ROUTING_MISS, CAPABILITY_MISS, DEGRADED_PARTIAL, FALLBACK_EXHAUSTED, PROVIDER_OUTAGE, LOCAL_NETWORK_FAILURE, UNKNOWN) + severity enum + message_redacted maxLength: 8192 |
| 2 | `model-probe-cache.{sh,py,ts}` | Cross-runtime parity gate (Option B per SDD §4.2.3 — per-runtime cache files, no cross-runtime mutex) |
| 3 | `audit_emit` envelope schema bump 1.1.0 → 1.2.0 | Additive; `MODELINV` added to `primitive_id` enum (SDD §4.4 [ASSUMPTION-3 RESOLVED]) |
| 4 | 3 new payload schemas | `model.invoke.complete.payload.schema.json`, `class.resolved.payload.schema.json`, `probe.cache.refresh.payload.schema.json` |
| 5 | `audit-retention-policy.yaml` row | `model_invoke` 30-day retention, chain_critical: true |
| 6 | Operator-visible header protocol | NEW at `.claude/protocols/operator-visible-header.md` per [ASSUMPTION-6] |
| 7 | `cheval.py::_error_json` extended to emit `error_class` | + bash shim `model-adapter.sh` parses via `jq` |
| 8 | `red-team-model-adapter.sh --role attacker` routes to `flatline-attacker` agent | Closes #780 |
| 9 | Remove `2>/dev/null` from `flatline-orchestrator.sh:1709` | AC-1.4 |
| 10 | Legacy adapter `max_output_tokens` per-model lookup | Closes A1+A2 from sprint-bug-143; defense-in-depth before Sprint 4 quarantine |
| 11 | `kill_switch_active: true` field in `model.invoke.complete` payload | When `LOA_FORCE_LEGACY_MODELS=1` (SDD §11 / gemini IMP-004 HIGH 0.9) |

Sprint Anchor: PR #794 + bugs A1, A2, A7.

## Known issues for next session

- **Beads MIGRATION_NEEDED** (upstream #661): `br` is in degraded state. `/implement` skill workflow says: fall back to markdown task tracking when MIGRATION_NEEDED. Don't try to use `br update` / `br close`.
- **Pre-commit hook fails** for the same reason. Use `git commit --no-verify` per the hook's own recommendation.
- **`grimoires/loa/a2a/sprint-1/` namespace collision**: cycle-099 left artifacts there. Use `sprint-143/` (global ID) for cycle-102's sprint-1 outputs.

## Resume strategy

**Don't run `/run-resume` blindly.** The .run state is RUNNING but no implementation has happened. A fresh `/run sprint-1` from a new session is cleaner. Steps:

1. Read this doc + `grimoires/loa/cycles/cycle-102-model-stability/sprint.md` Sprint 1 section
2. Skim PR #794 (sprint anchor, A1-A7 bug list)
3. `git checkout feature/feat/cycle-102-sprint-1`
4. Decide deliverable order (T1.1 model-error.schema.json is foundational — others depend on it)
5. Invoke `/implement sprint-1` (or just plan + write directly with /implement-skill discipline if running outside /run)
6. Commit per task with `feat(sprint-1): ...` prefix
7. After last task, run `/review-sprint sprint-1`, then `/audit-sprint sprint-1`, then PR

## Cumulative cycle state (for context)

Recently merged on main (PRs in chronological order):
- **#795** cycle-102 kickoff (PRD/SDD/sprint contract)
- **#792** BB diagnostic-context (#789 closure)
- **#797** BB self-review opt-in (#796 + vision-013)
- **#801** trust-origin + symlink hardening (#799 + #800 closure)

Open follow-up:
- **#798** PR-head `.reviewignore` trust boundary (SLSA L3 design-scope concern)

Cycle-102 hasn't shipped anything yet — only the kickoff PR and the BB-related side work landed. Sprint 1 is the actual cycle work.

## Final note

The `bridgebuilder:self-review` label is now production for any cycle-102 implementation PRs that touch `.claude/`, `grimoires/`, `.beads/` paths — apply the label so BB can review the substrate, not just the file manifest.
