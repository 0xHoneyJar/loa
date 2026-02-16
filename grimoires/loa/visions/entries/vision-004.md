# Vision 004: Conditional Constraints for Feature-Flagged Behavior

## Source
- Bridge: bridge-20260216-c020te, Iteration 1
- PR: #341
- Finding Severity: PRAISE (architectural insight)

## Insight

When a constraint system needs to express "NEVER do X... unless runtime condition Y is active, in which case MAY do X with caveats," the cleanest approach is a `condition` field on the constraint itself rather than forking into parallel constraint registries or mode-specific files.

The pattern: a single constraint exists unconditionally, but an optional `condition` object with `when` (feature flag name), `override_text` (alternative constraint text), and `override_rule_type` (alternative severity) modifies its interpretation at runtime. This is additive, backward-compatible, and composable — the same mechanism absorbs future feature flags without schema changes.

## Pattern

```json
{
  "id": "C-PROC-002",
  "rule_type": "NEVER",
  "text": "use TaskCreate for sprint tracking when beads is available",
  "condition": {
    "when": "agent_teams_active",
    "override_text": "TaskCreate serves dual purpose: team coordination + session display. Sprint lifecycle STILL uses beads exclusively.",
    "override_rule_type": "MAY"
  }
}
```

## Applicability

Any constraint-driven system that needs to express mode-dependent behavior:
- Feature flags that relax safety constraints
- Multi-tenant configurations with different rule sets
- Progressive rollouts where constraints loosen as confidence grows

## Connection

This mirrors Google Zanzibar's conditional authorization tuples and Netflix Archaius's feature-flagged configuration. The key insight is that the constraint exists as a single source of truth — the condition modifies interpretation, not existence. This prevents the "shadow registry" problem where mode-specific constraints drift from the canonical set.

## Exploration

**Cycle**: cycle-023 (The Permission Amendment)
**PRD**: `grimoires/loa/prd.md`
**Branch**: `feat/cycle-023-permission-amendment`

The Permission Amendment is the active exploration of this vision. It promotes MAY from its existing presence in `condition.override_rule_type` to a first-class primary `rule_type`, validating the conditional constraint pattern by extending it to define positive rights (permissions) alongside existing obligations and prohibitions.

Key implementation decisions:
- MAY added to primary `rule_type` enum (was already in `condition.override_rule_type`)
- 4 C-PERM-* constraints created as the first MAY-type constraints
- `permission_grants` section added to CLAUDE.loa.md via the existing generation pipeline
- No template changes needed — existing jq templates are rule_type-agnostic
- Precedence hierarchy: `NEVER > MUST > ALWAYS > SHOULD > MAY`
