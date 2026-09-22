# Extended Grounding Markers — riding-codebase

Read at Phase 6 when enrichment phases (12-14) produce evidence that warrants richer attribution than the standard [GROUNDED]/[INFERRED]/[ASSUMPTION] markers.

**Extended Markers** (available when enrichment phases run):

| Marker | When to Use | Example |
|--------|-------------|---------|
| `[CLAIMED: source]` | Single-source evidence with attribution | `[CLAIMED: ADR-003 — Dynamic over Privy]` |
| `[DISPUTED: A vs B]` | Conflicting signals between sources | `[DISPUTED: README says Redis, code uses in-memory]` |
| `[UNKNOWN: GAP-NNN]` | Linked to gap tracker entry | `[UNKNOWN: GAP-007 — auth session TTL]` |

These extended markers complement (not replace) the standard markers and the BUTTERFREEZONE provenance tags (`CODE-FACTUAL`, `DERIVED`, `OPERATIONAL`). Use them in reality files (`grimoires/loa/reality/*.md`) and the gap tracker when enrichment phases produce evidence that warrants richer attribution.
