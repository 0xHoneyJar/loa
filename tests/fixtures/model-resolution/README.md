# Model-Resolution Golden Fixtures (cycle-099 Sprint 1D)

Golden-test fixture corpus for the FR-3.9 6-stage model resolver, per SDD §7.6.3.

## Sprint 1D scope (THIS sprint)

Sprint 1D ships the **infrastructure**: 12 fixtures × 3 cross-runtime runners (bash + python + TypeScript) × cross-runtime-diff CI gate. The runners assert byte-identical output across runtimes for the **subset of FR-3.9 currently implemented** — the alias→provider+model_id lookup exposed by `model-resolver.sh::resolve_alias` / `resolve_provider_id` (bash) and `GENERATED_MODEL_REGISTRY` (TypeScript).

Each fixture has a `sprint_1d_query` block that all three runners consume identically. The full SDD §7.6.3 `input` + `expected` blocks are present for Sprint 2 extension when the full FR-3.9 resolver lands (T2.6).

## Sprint 2+ extension

When Sprint 2 lands the canonical Python `model-resolver.py` + bash overlay generator + TS codegen of the resolver, the runners are extended to consume the full `input.framework_defaults` + `input.operator_config` blocks and produce real `expected.resolutions` arrays per SDD §7.6.1. Tier-tag resolution, `model_aliases_extra`, `prefer_pro_models` overlay all become asserted.

Until then, fixtures whose scenarios depend on stages 4-6 (legacy shape, framework default, prefer_pro) emit a uniform `deferred_to: "sprint-2-T2.6"` marker — same marker across all 3 runtimes preserves byte-equality.

## Fixture schema

```yaml
description: "human-readable scenario summary"

# Sprint 1D query — simple alias lookup. Runners consume this.
sprint_1d_query:
  alias: "<alias-or-canonical-id>"   # input to resolve_alias()
  # subset_supported is computed dynamically by the runner from MODEL_IDS:
  #   true  → emit {resolved_provider, resolved_model_id}
  #   false → emit {deferred_to: "sprint-2-T2.6", input_alias}

# Sprint 2+ full SDD §7.6.3 spec (preserved for resolver extension).
input:
  schema_version: 2
  framework_defaults: { ... }   # mock SoT subset
  operator_config: { ... }      # mock .loa.config.yaml subset

expected:                       # full resolution per SDD §7.6.1
  resolutions:
    - skill: <skill>
      role: <role>
      resolved_provider: <provider>
      resolved_model_id: <model_id>
      resolution_path: [ ... ]
  cross_runtime_byte_identical: true
```

## Runner output schema

Each runner emits JSON Lines (one fixture per line) sorted by fixture filename:

```json
{"fixture":"01-happy-path-tier-tag","input_alias":"max","subset_supported":false,"deferred_to":"sprint-2-T2.6"}
{"fixture":"06-extra-only-model","input_alias":"opus","subset_supported":true,"resolved_provider":"anthropic","resolved_model_id":"claude-opus-4-7"}
```

Each line is canonical-JSON (sorted keys, no whitespace). The CI cross-runtime-diff job byte-compares the full output across runtimes.

## Refs

- SDD §7.6.3 (12-fixture corpus)
- Sprint plan T1.11/T1.12 (this delivery)
- AC-S1.9 (byte-equal across runtimes)
