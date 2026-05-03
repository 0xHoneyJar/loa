# Decision: `tier_enforcement_mode` default for cycle-098 release

**Status**: PROPOSED — operator sign-off pending
**Date proposed**: 2026-05-03
**Source**: SDD §6 Sprint 1 ACs (held from v1.4); SOLO_GPT SKP-007 re-flag in Flatline pass #4 (HIGH 730)

## The decision

Default value of `.loa.config.yaml::tier_enforcement_mode` for cycle-098 ship.

Three options:

| Option | Behavior on unsupported config tier at boot | Pros | Cons |
|--------|---------------------------------------------|------|------|
| `warn` | Print warning, continue | Lowest friction; backward-compatible with operators running unsupported combos today | Risky — production deployment with unsupported combo just emits a log line; operator may miss it |
| `refuse` | Print error, halt boot | Fail-closed; matches G-2 fail-closed safety goal | Operators running unsupported combo today will hit a hard block on first cycle-098 install |
| `warn`-then-`refuse` migration | `warn` for cycle-098 (one cycle); `refuse` from cycle-099 onward | Migration window for operators to fix configs before hard block | Adds a 2-cycle commitment to the migration |

## Recommendation

**Option C: `warn`-then-`refuse` migration**.

### Why

1. **Operators running unsupported combos exist today.** The 5 supported tiers (Tier 0-4) are a deliberate narrowing of the 2⁷=128 combinatorial space. Pre-cycle-098 operators may have enabled arbitrary subsets that aren't in the supported list. A hard `refuse` on first cycle-098 install would surprise them.
2. **Fail-closed is still the destination.** Per G-2 ("Fail-closed safety for cost, trust, protected-class"), the long-term default should be `refuse`. The `warn`-only forever path defers the safety property indefinitely.
3. **One-cycle migration window is enough.** cycle-098 ships with 5 supported tiers documented; operators have one cycle to migrate to a supported tier before cycle-099's hard block. The warning message MUST include a link to the tier definitions and `/loa diag config-tier` command for self-service inspection.

### Implementation

- cycle-098 ships `tier_enforcement_mode: warn` as default
- Warning message: `"WARNING: Configuration tier <X> is unsupported. Only tiers 0-4 are tested. Run '/loa diag config-tier' for details. Cycle-099 will refuse boot on unsupported tiers (planned migration)."`
- cycle-099 PRD/SDD includes the flip to `refuse` as a deliberate AC + migration notice
- `--allow-unsupported-tier` opt-out flag exists in both modes (audit-logged when used)

### Alternative: `refuse` from day 1 (rejected)

Rejected because:
- Surprises existing operators with hard block on `git pull` + cycle-098 install
- No grace window for self-service migration
- Operator escalation cost outweighs the marginal safety benefit during the migration cycle

## Sign-off

- [ ] Operator (deep-name) approves Option C
- [ ] Sprint 1 implementation uses `warn` default; `--allow-unsupported-tier` opt-out is supported
- [ ] cycle-099 carries the `refuse` flip as a migration AC

## Audit trail

This decision is logged in the cycle-098 audit envelope (Sprint 1 onwards) with `decision_class: tier_enforcement_default`, `tier_from: deferred`, `tier_to: warn-with-migration`, `reason: "Operator-approved decision per cycles/cycle-098-agent-network/decisions/tier-enforcement-default.md"`.
