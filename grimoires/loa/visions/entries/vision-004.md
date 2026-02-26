# Vision: Conditional Constraints for Feature-Flagged Behavior

**ID**: vision-004
**Source**: Bridge iteration 1 of bridge-20260216-c020te
**PR**: #341
**Date**: 2026-02-16T00:00:00Z
**Status**: Implemented
**Implementation**: cycle-023 (The Permission Amendment)
**Tags**: [architecture, constraints, feature-flags]

## Insight

When a constraint system needs to express "NEVER do X... unless runtime condition Y is active, in which case MAY do X with caveats," the cleanest approach is a `condition` field on the constraint itself rather than forking into parallel constraint registries or mode-specific files.

The pattern: a single constraint exists unconditionally, but an optional `condition` object with `when` (feature flag name), `override_text` (alternative constraint text), and `override_rule_type` (alternative severity) modifies its interpretation at runtime. This is additive, backward-compatible, and composable.

## Potential

Any constraint-driven system that needs to express mode-dependent behavior: feature flags that relax safety constraints, multi-tenant configurations with different rule sets, progressive rollouts where constraints loosen as confidence grows.

## Connection Points

- Bridgebuilder finding: vision-004, severity PRAISE
- Bridge: bridge-20260216-c020te, iteration 1
- Implemented in cycle-023: MAY promoted to first-class rule_type, 4 C-PERM-* constraints created, precedence hierarchy NEVER > MUST > ALWAYS > SHOULD > MAY
