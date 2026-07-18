# Templates 05 — Clustering and Routing

## T5.1 Pre-cluster tags → `runs/<run-id>/clusters/pre-cluster-tags.md`

```markdown
# Structural Pre-Cluster Tags — ⟨RUN-slug⟩
<!-- Tags, not documents. One row per tag assignment. No prose analysis. -->
| tag | member ids (PKT/CC) | structural basis (one phrase) |
|-----|---------------------|-------------------------------|
```

Rules: `structural basis` names only stance-free features (contradiction
density, reference density, claim-type mix) — a basis phrase containing
doctrine-relative reasoning ("core access thesis") is a defect; a tag never
promoted to a route cluster simply remains here, zero further overhead.

<!-- example -->
| PC-2 | CC-104, CC-105, CC-106, CC-113, CC-114, PKT-0007, PKT-0031 | high contradiction density around retention/growth claims |

## T5.2 Route-cluster card → `runs/<run-id>/clusters/route-cards/RC-⟨NN⟩.md`

```markdown
# Route Cluster RC-⟨NN⟩ — ⟨working name⟩

| field | value |
|-------|-------|
| Routing posture | ⟨adversarial-weighted \| convergent-weighted \| hybrid \| unrouted-pending-external-referent⟩ |
| Posture history | ⟨date: posture — trigger⟩; ⟨…⟩ |
| Structural pre-cluster tags used | ⟨PC-…⟩ |
| Packet/source IDs | ⟨PKT-…; SRC-… derivable⟩ |
| Candidate claim IDs | ⟨CC-…⟩ |
| Key dispositions | ⟨e.g. 3 carried, 2 unresolved (contradiction)⟩ |
| Unresolved external referents | ⟨REF-… \| none⟩ |
| Depends on | ⟨RC-… \| none⟩ |
| Blocks/finalization impact | ⟨what this cluster taints if unresolved⟩ |

## Internal-shape vector  <!-- coarse values: low / med / high -->
| signal | value |
|--------|-------|
| contradiction density | ⟨…⟩ |
| reference density | ⟨…⟩ |
| invariant-bearing strength | ⟨…⟩ |
| implementation-constraint density | ⟨…⟩ |
| open-question density | ⟨…⟩ |
| external-referent need | ⟨…⟩ |
| doctrine-spine strength | ⟨…⟩ |
```

Rules: every card lists ≥1 packet ID (the smallest manual-mode invariant);
`external-referent need` records the *need signal read from the corpus* —
never the external fact itself; `unrouted-pending-external-referent` posture
requires a matching `REF` row; posture changes append to `Posture history`
(manual mode's entire routing log).

## T5.3 Routing log (tool mode only) → `runs/<run-id>/clusters/routing-log.md`

```markdown
# Routing Log — ⟨RUN-slug⟩
<!-- Tool-mode materialization of routing propagation. Manual mode skips
     this file entirely (card posture-history lines suffice). -->
| # | date | event | cluster(s) | from → to | trigger |
|---|------|-------|-----------|-----------|---------|
```

`event`: `posture-assigned` | `posture-changed` | `dependency-added` |
`referent-recorded` | `referent-resolved` | `demoted-to-background` |
`re-route-after-arm`. `trigger` cites the artifact that caused it (an STM
row, a REF resolution, a verifier verdict).

<!-- example -->
| 7 | 2026-07-16 | posture-changed | RC-04 | adversarial-weighted → hybrid | STM-3 upheld the invariant; convergent reconciliation now load-bearing for RC-04 via REF-02 |
