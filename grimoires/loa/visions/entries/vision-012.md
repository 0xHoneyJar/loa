# Vision: Role-Based Alias Naming (`top-review-anthropic` vs `opus`)

**ID**: vision-012
**Source**: Bridgebuilder SDD review of Opus 4.7 migration (simstim-20260417-4a16c55f), finding SPECULATION-001
**PR**: TBD (Opus 4.7 migration)
**Date**: 2026-04-17T00:00:00Z
**Status**: Captured (original_severity: SPECULATION)
**Tags**: [alias-design, semantic-stability, model-migrations, API-contracts]

## Insight

In Loa's Flatline protocol and bridgebuilder review, the `opus` alias effectively means **"the top Anthropic review model at any point in time"** — a role, not a product ID. Code paths that want "whatever the current best Anthropic reviewer is" write `opus`; code paths that want historical reproducibility write the full `anthropic:claude-opus-4-N` ID.

But the alias name `opus` still leaks product semantics: a user reading `primary: opus` in `.loa.config.yaml` would reasonably think it's naming a specific model family. A name like `top-review-anthropic` or `advisor-primary-anthropic` would make the role explicit, and future Opus-tier migrations (or a hypothetical switch to a different Anthropic model family) would be pure alias-table edits with zero user-facing config churn.

## Potential

- **Semantic stability**: a 5-year-old `.loa.config.yaml` would still resolve correctly if Anthropic renames their model family
- **Role clarity**: config readers understand `top-review-anthropic` is a role-slot, not a product name
- **Parallel naming for other providers**: `top-review-openai`, `top-review-google` — provider-specific role slots
- **Easier cross-provider comparisons**: "which provider's top review model is the best fit for this role?" becomes a first-class question
- **Legacy alias compatibility**: keep `opus` as a pointer to `top-review-anthropic` during transition

## Connection Points

- Bridgebuilder finding SPECULATION-001 from design-review-simstim-20260417-4a16c55f
- Deferred from Opus 4.7 migration PRD per operator acceptance
- Related vision: vision-011 (auto-generate bash maps from YAML) — could be combined into a "model registry v2" cycle
- Existing pattern: `reviewer`, `reasoning`, `cheap`, `researcher`, `deep-thinker`, `fast-thinker` in `model-config.yaml` ALREADY use role-based naming. `opus` and `cheap` are the outliers that still carry product-ish names.
- This vision generalizes the `reviewer` / `reasoning` precedent to the Anthropic slot

## Estimated Scope

- Add `top-review-anthropic: "anthropic:claude-opus-4-N"` alias to `model-config.yaml`
- Retarget internal Loa calls from `opus` → `top-review-anthropic` over a grace period
- Keep `opus` alias as backward-compat pointer to `top-review-anthropic`
- Update docs to recommend `top-review-anthropic` for new configs
- Cycle cost: 1 small /simstim cycle (mostly doc sweep; no code-breaking changes)

## Considerations

- Some Loa code/docs intentionally name "Opus" for user recognition (e.g., in cost estimates). Those should probably keep the product-name reference. Role-aliases are for routing, not marketing.
- Bikeshed risk: is `top-review-anthropic` the right name? Alternatives: `advisor-anthropic`, `reviewer-anthropic-primary`, `flatline-primary-anthropic`. Defer naming decision to the cycle that implements.
