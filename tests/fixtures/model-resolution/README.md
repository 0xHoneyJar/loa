# Model-Resolution Golden Fixtures (cycle-099 Sprint 2D)

Golden-test fixture corpus for the FR-3.9 6-stage model resolver, per SDD §7.6.3.

## Sprint 2D scope (T2.6)

Sprint 2D ships the canonical Python resolver (`.claude/scripts/lib/model-resolver.py`)
plus a bash twin (`tests/bash/golden_resolution.sh`) that independently re-implements
the 6 stages for cross-runtime byte-equality verification. The runners consume each
fixture's `expected.resolutions[]` block (one (skill, role) tuple per entry) and emit
canonical JSON output that the cross-runtime-diff CI gate
(`.github/workflows/cross-runtime-diff.yml`) byte-compares.

Sprint 2D shipped Python + bash. Sprint 2D.c will add the TypeScript runner via
Python+Jinja2 codegen (mirroring sprint-1E.c.1's pattern). Sprint 2D.d will add
the SC-14 property suite (6 invariants × ~100 random configs).

## Sprint 1D legacy block

Each fixture preserves a `sprint_1d_query.alias` block — Sprint 1D's alias-lookup-only
subset. The TypeScript golden runner (`tests/typescript/golden_resolution.ts`) still
consumes this block until Sprint 2D.c lands. Bash and Python now consume
`expected.resolutions[]` instead.

## Fixture schema

```yaml
description: "human-readable scenario summary"

# Sprint 1D legacy — still consumed by tests/typescript/golden_resolution.ts.
sprint_1d_query:
  alias: "<alias-or-canonical-id>"

# Sprint 2D scope — full SDD §7.6.1 spec.
input:
  schema_version: 2
  framework_defaults:        # mock framework SoT subset
    providers:
      <provider>:
        models:
          <model_id>: { capabilities, context_window, ... }
    aliases:
      <alias>: { provider, model_id }    # dict form (cycle-099 fixture corpus)
        # OR string form (cycle-095 production back-compat shape):
      <alias>: "provider:model_id"
    tier_groups:
      mappings:
        <tier>: { <provider>: <alias> }
    agents:
      <skill_name>: { default_tier: <tier>  OR  model: <alias> }
  operator_config:           # mock .loa.config.yaml subset
    skill_models:
      <skill>:
        <role>: <tier-tag>  OR  <alias>  OR  "provider:model_id"
    model_aliases_extra:
      <id>: { provider, model_id, capabilities, ... }
    model_aliases_override: { ... }
    prefer_pro_models: <bool>
    respect_prefer_pro: <bool>           # FR-3.4 legacy-shape gate
  runtime_state:                          # optional — Sprint 2B degraded-mode marker
    overlay_state: degraded
    overlay_reason: "..."

expected:
  resolutions:
    - skill: <skill>
      role: <role>
      # Success shape:
      resolved_provider: <provider>
      resolved_model_id: <model_id>
      resolution_path:
        - { stage: <int>, outcome: <hit|miss|applied|skipped|error>, label: <stage_label>, details: { ... } }
      # OR error shape:
      error:
        code: "[<ERROR-CODE>]"
        stage_failed: <int>
        detail: "..."
  cross_runtime_byte_identical: true
```

## Output schema (Sprint 2D)

Each runner emits one canonical JSON line per `expected.resolutions[]` entry.
The line conforms to `.claude/data/trajectory-schemas/model-resolver-output.schema.json`:

```json
{"fixture":"01-happy-path-tier-tag","skill":"flatline_protocol","role":"primary","resolved_provider":"anthropic","resolved_model_id":"claude-opus-4-7","resolution_path":[{"stage":2,"outcome":"hit","label":"stage2_skill_models","details":{"alias":"max"}},{"stage":3,"outcome":"hit","label":"stage3_tier_groups","details":{"resolved_alias":"opus"}}]}
{"error":{"code":"[TIER-NO-MAPPING]","detail":"...","stage_failed":3},"fixture":"03-missing-tier-fail-closed","role":"primary","skill":"flatline_protocol"}
```

Lines are sorted by `(fixture, skill, role)` ascending. Output is canonical JSON
(sort_keys=True, ensure_ascii=False, no whitespace). The CI cross-runtime-diff job
byte-compares Python and bash runners; mismatch fails the build.

## Stage label enum (per `model-resolver-output.schema.json`)

| Stage | Label | When it fires |
|-------|-------|---------------|
| 1 | `stage1_pin_check` | `skill_models.<skill>.<role>` is `provider:model_id` form |
| 2 | `stage2_skill_models` | `skill_models.<skill>.<role>` has any non-pin string |
| 3 | `stage3_tier_groups` | S2 cascaded — tier-tag → operator/framework `tier_groups.mappings` |
| 4 | `stage4_legacy_shape` | `<skill>.models.<role>` legacy form (with deprecation warning) |
| 5 | `stage5_framework_default` | `framework_defaults.agents.<skill>.{model, default_tier}` |
| 6 | `stage6_prefer_pro_overlay` | POST-resolution overlay; gated per FR-3.4 for legacy shapes |

## Error code enum

| Code | When it fires |
|------|---------------|
| `[TIER-NO-MAPPING]` | S3 — tier referenced but no provider mapping in tier_groups (FR-3.8 fail-closed) |
| `[OVERRIDE-UNKNOWN-MODEL]` | S0 — `model_aliases_override` targets unknown framework id (IMP-004) |
| `[MODEL-EXTRA-OVERRIDE-CONFLICT]` | S0 — same id in both `extra` and `override` (IMP-004) |
| `[NO-RESOLUTION]` | All 6 stages exhausted without a hit |
| `[CONFLICT-PIN-AND-TIER]` | Schema-level reject — explicit pin and tier in same skill_models entry |
| `[ALIAS-COLLIDES-WITH-TIER]` | IMP-007 informational — tier-tag wins; collision reported |

## Refs

- SDD §1.5 (FR-3.9 state diagram), §1.5.1 (cross-runtime canonicalization invariants), §1.5.2 (build-time vs runtime authority), §7.6 (golden corpus schema)
- PRD FR-3.9 (deterministic 6-stage resolution algorithm)
- Sprint plan T2.6 (canonical Python + bash twin + parity gate)
- AC-S2.x (byte-equal cross-runtime), AC-S2.y (CI gate fails on divergence), AC-S2.z (SC-14 property suite — 2D.d)
- `feedback_cross_runtime_parity_traps.md` — 6 known classes of bash/python/TS silent divergence
