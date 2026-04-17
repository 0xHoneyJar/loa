# Vision: Auto-Generate Bash Adapter Maps from model-config.yaml

**ID**: vision-011
**Source**: Bridgebuilder SDD review of Opus 4.7 migration (simstim-20260417-4a16c55f), finding REFRAME-001
**PR**: TBD (Opus 4.7 migration)
**Date**: 2026-04-17T00:00:00Z
**Status**: Captured (original_severity: REFRAME)
**Tags**: [tooling, adapters, model-migrations, fragility-reduction, code-generation]

## Insight

Three Opus migrations shipped in five months (4.5→4.6 PR #203, aliases PR #207, 4.6→4.7 current cycle). Each one hand-edits the same four associative arrays in `.claude/scripts/model-adapter.sh.legacy` (`MODEL_PROVIDERS`, `MODEL_IDS`, `COST_INPUT`, `COST_OUTPUT`) plus parallel alias maps in `model-adapter.sh` and `red-team-model-adapter.sh`. The `validate_model_registry()` function exists specifically because the author knew the hand-edit was fragile — cross-PR map inconsistencies (PR #202's lesson) are a recurring class of bug.

`.claude/defaults/model-config.yaml` is already the declarative source of truth for pricing, capabilities, context windows, and aliases. The bash maps are effectively a denormalized view of the same data, hand-maintained for performance and simplicity in shell scripts.

**Replace the hand-edits with a generator.** A `.claude/scripts/gen-adapter-maps.sh` script reads `model-config.yaml` at source time and emits the four bash maps as an included `.sh` file. The adapter `source`s the generated file. Changes to models become pure YAML diffs — no parallel bash hand-edits, no drift, no invariant check needed.

## Potential

- Eliminates the entire class of "forgot to update one of the four maps" bugs
- Model migrations become ~5-file diffs (YAML + fixtures) instead of ~20-file diffs
- Removes the need for `validate_model_registry()` (or reduces it to a no-op assertion that the generated file exists)
- Makes the "backward-compat alias retarget" pattern declarative: add a key under `aliases:`, done
- Sets up for future: bash, Python, TypeScript adapters all generated from the same YAML at install time

## Connection Points

- Bridgebuilder finding REFRAME-001 from design-review-simstim-20260417-4a16c55f
- Deferred from Opus 4.7 migration PRD per operator acceptance
- Relates to `validate_model_registry()` (`.claude/scripts/model-adapter.sh.legacy` L160-183)
- Related pattern: `constructs/pack-manifest-schema.json` validation — already uses YAML as source of truth for packs
- Could be combined with vision-012 (role-based alias naming) for a single "model registry v2" cycle

## Estimated Scope

- 1 generator script (`gen-adapter-maps.sh`) using `yq`
- 1 generated file checked in (or regenerated on `source` — tradeoff to decide)
- Migration: delete ~150 lines of hand-edited arrays from `.legacy`, replace with `source ./generated-model-maps.sh`
- Tests: adapter-aliases.bats passes unchanged (tests the resolved behavior, not the storage)
- Risk: `yq` dependency becomes stronger (already required since v1.27.0 per CLAUDE.md)
- Cycle cost: 1 small /simstim cycle (~2-3 sprints)
