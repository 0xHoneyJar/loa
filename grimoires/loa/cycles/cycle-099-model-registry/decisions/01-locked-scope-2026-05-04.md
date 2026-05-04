# Cycle-099 Locked Scope Decisions (2026-05-04)

Decisions captured during `/plan-and-analyze` interview, 2026-05-04. These bind cycle-099 scope. Override only via explicit operator approval at `/architect` or `/sprint-plan` review.

## Decision 1 — Cycle scope: Narrow (#710 only)

**Locked**: Cycle-099 covers issue #710 ONLY (registry consolidation + per-skill granularity). No cycle-098 follow-ups.

**Rejected alternatives**:
- *Medium*: would have bundled cycle-098's L4 graduated-trust + beads recovery. **Rejected** because L4 is *agent* trust tiers (different problem domain than *model* tiers); operator caught the conflation risk during interview ("are we working on the model billing? or the phase 4? should we separate them?").
- *Wide (~3-month cycle)*: would have bundled cycle-098 L4-L7. Rejected for same reason at higher magnitude.

**Out-of-scope items** (deferred):
- Cycle-098 L4-L7 primitives → separate cycle (cycle-100+)
- #661 beads DB recovery → handle as `/bug` between cycles
- BB iter-2 polish (#714, #719) → T3 backlog

## Decision 2 — Migration ordering: Phased

**Locked**: 4 sprints, each independently shippable.

| Sprint | Scope |
|--------|-------|
| Sprint 1 | SoT extension foundation (Bridgebuilder TS codegen, Red Team migration, drift gate, lockfile) |
| Sprint 2 | Config extension + per-skill granularity (model_aliases_extra, skill_models, tier_groups mappings) |
| Sprint 3 | Persona + docs migration (tier-tag refs, model-permissions consolidation, BB dist regen) |
| Sprint 4 (gated) | Legacy adapter sunset (default flip, deprecation, sunset decision at gate) |

**Rejected alternatives**:
- *One-shot*: too large; harder rollback boundaries
- *P0-first, P1-deferred*: collapses Sprint 4 sunset into a follow-up cycle; left as Sprint 4 gate decision instead

## Decision 3 — Per-skill granularity shape: Tier-tag per skill

**Locked**: Operators express which tier each skill should use (`flatline_protocol.primary: max`, `red_team.primary: cheap`). Tier resolves via cycle-095's `tier_groups.mappings` schema.

**Rejected alternatives**:
- *Direct model per role per skill*: too verbose; doesn't compose with cycle-095 tier_groups
- *Both tier as default + per-role override*: more flexibility but more surface; supported as FR-3.6 mixed mode but not the canonical shape

**Composes with**:
- cycle-095 `tier_groups.mappings` (populated in Sprint 2)
- cycle-095 `prefer_pro_models` flag

## Decision 4 — Bridgebuilder TS migration: Build-time codegen

**Locked**: New `.claude/skills/bridgebuilder-review/scripts/gen-bb-registry.ts` reads `model-config.yaml` at build time, emits TS literal maps for `truncation.ts` defaults and `config.ts`. `bun run build` invokes the generator. CI drift gate verifies regenerated output matches committed `dist/`.

**Rejected alternatives**:
- *Runtime YAML reads*: more invasive; new runtime YAML parser dependency; loses type safety
- *Hybrid (codegen for truncation, runtime for aliases)*: more complexity with no clear win

**Preserves**: Current Bridgebuilder ship pattern (pre-compiled `dist/` shipped alongside source; downstream operators don't need to rebuild).

## Decision 5 (deferred to /architect) — model-permissions.yaml strategy

**Recommendation in PRD**: Option B (merge into SoT). `/architect` decides between:
- *Option A*: Codegen `model-permissions.yaml` from SoT; drift gate enforces match
- *Option B*: Merge permissions into `model-config.yaml::providers.<p>.models.<id>.permissions`; eliminate the separate file

PRD recommends B because permissions are a per-model attribute and merging eliminates a registry entirely.

## Sources

- `/plan-and-analyze` interview transcript (2026-05-04)
- AskUserQuestion responses: scope=narrow, ordering=phased, granularity=tier-tag, BB-TS=codegen
- Operator clarification on conflation risk (rejected medium scope)
- PRD §"Appendix C — Decision log"
