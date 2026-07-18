# Templates 04 — Evidence, Boundaries, Queues, Referents

## T4.1 Evidence-role ledger → `runs/<run-id>/ledgers/evidence-roles.md`

```markdown
# Evidence-Role Ledger — ⟨RUN-slug⟩

## Claim–source edges
| claim_id | source_id | role | verification | removal_effect | note | status |
|----------|-----------|------|--------------|----------------|------|--------|

## Synthesis/inference markers  <!-- carried claims with no direct support -->
| claim_id | inference basis (claim/packet ids) | uncertainty note |
|----------|-------------------------------------|------------------|

## Coverage accounting  <!-- recomputed after any edge change -->
- carried+merged claims: ⟨n⟩
- with ≥1 load-bearing or corroborative edge: ⟨n⟩
- explicitly marked synthesis/inference: ⟨n⟩
- NEITHER (must be 0 to pass): ⟨n⟩
```

Column rules:

- `role` (closed set): `load-bearing` | `corroborative` | `contradictory` |
  `contextual` | `decorative` | `unresolved-source`.
- `verification` (of the source *for this claim*): `verified-primary` |
  `verified-secondary` | `unverifiable`.
- `removal_effect` — mandatory iff `role = load-bearing`, else blank:
  `downgrades-to-unresolved` | `confidence-decreases` |
  `survives-independent-support` | `must-be-excluded`.
- Hard rules: `decorative` never counts toward coverage; a claim whose only
  edges are `unresolved-source` cannot be `carried` as confirmed;
  `contradictory` edges survive merges (copied to the canonical claim).
- Manual-mode sparsity (doc 09): edges mandatory for carried+merged claims
  and contradiction-adjacent material only.

<!-- example -->
| CC-104 | SRC-104 | load-bearing | verified-primary | confidence-decreases | longitudinal observation carries the claim | active |
| CC-104 | SRC-102 | corroborative | verified-secondary | | conversational echo, independent speaker | active |

## T4.2 Negative boundaries → `runs/<run-id>/ledgers/negative-boundaries.md`

```markdown
# Do-Not-Use / Negative Boundaries — ⟨RUN-slug⟩
| boundary_id | type | statement | governs (claim/source ids) | basis | status |
|-------------|------|-----------|----------------------------|-------|--------|
```

`type`: `out-of-scope` | `not-evidence` | `do-not-use-harm` |
`no-fabricated-referents`. Every scope-based `excluded-with-reason` claim maps
to a boundary row; every `do-not-use-harm` boundary cites the excluded claim
that records it. Projections consume this table mechanically (K6).

<!-- example -->
| NB-3 | do-not-use-harm | Wallet holdings of identifiable members must not be displayed or cited as a design lever | CC-110 | privacy harm; excluded-with-reason in inventory | active |

## T4.3 Unresolved / deferred queue → `runs/<run-id>/ledgers/unresolved-queue.md`

```markdown
# Unresolved / Deferred Queue — ⟨RUN-slug⟩
| claim_id | disposition | what would resolve it | blocking (REF/decision/evidence) | surfaced-in-precis |
|----------|-------------|------------------------|----------------------------------|--------------------|
```

Rule: every `deferred` and `unresolved` inventory claim has exactly one row;
`surfaced-in-precis` is filled at S11 with the section anchor — the queue is
how "remains visible" is made checkable.

## T4.4 External-referent records → `runs/<run-id>/ledgers/external-referents.md`

```markdown
# External Referents — ⟨RUN-slug⟩
| ref_id | need (as a question) | depends (RC/CC ids) | status | supplied_by | intake (SRC id or sign-off ref) | date | taint note |
|--------|----------------------|---------------------|--------|-------------|--------------------------------|------|------------|
```

Rules:

- `status`: `unresolved` | `supplied` | `declined`. Rows are appended by the
  Router (needs) and resolved **only** by authority action: `supplied_by` is
  the authority or a named intake; pipeline workers never fill it.
- Research material received after freeze does not resolve this run's row.
  Leave it unresolved and tainted; start a successor run whose manifest names
  this run, admit the material there at S0 as `external-research-intake` source
  rows (T2.1), and carry the referent forward for resolution there.
- An authority ruling with no new material may resolve the current run's row
  through a manifest sign-off that records the statement verbatim. Do not add a
  post-freeze `authority-statement` source row to the frozen corpus.
- `taint note`: one line naming what stays marked `external-referent
  unresolved` while this row is `unresolved` (the cone; K5 computes the full
  set — this note is the human-readable anchor).

<!-- example -->
| REF-02 | Do comparable token-gated membership products already solve tiered access, and how? | RC-03; CC-101, CC-102 | unresolved | | | | access-model cluster and both PRD-bound claims tainted |
