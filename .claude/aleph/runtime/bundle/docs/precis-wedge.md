# Aleph Précis Wedge (Phase 0/1)

This document defines Aleph's first wedge: the single narrow claim Phase 0/1
must prove, the completeness contract it rests on, the disposition ledger, the
completeness trail, and the v0 acceptance envelope. It deliberately proves one
thing and defers everything else.

## Wedge statement

> Aleph Phase 0/1 proves that a bounded corpus can be transformed into one
> projection-neutral, portable Research Précis file with a complete
> claim-disposition trail. The artifact is complete by disposition coverage,
> compact by normalization, and neutral because final-form projection is deferred
> to a separate projection stage (Aleph's own — see
> `docs/decisions/0001-projection-as-separate-downstream-stage.md` — or a
> consuming repo's), never decided by the Précis itself.

This mirrors the Loa-Straylight Recall Wedge: Straylight did not begin by solving
live memory admission, durable storage, ingestion, consent, revocation UI, or
production rollout. It first proved governed recall over already-admitted
stand-in material. Aleph does the same — it proves the artifact over a bounded
stand-in corpus before any live machinery is built.

The 333 ChatGPT conversations curated into ~20 business threads are a good first
stand-in corpus. They are **instance #1, not Aleph's scope or boundary.**

## Completeness contract (canonical: option A)

> Aleph does not allow "non-load-bearing" to function as an invisible
> pre-extraction discard. Once a source unit is elevated into a candidate claim,
> load-bearing-ness is resolved by disposition. The disposition ledger must record
> whether the claim is carried, merged, deferred, excluded-with-reason,
> backgrounded, judged-non-load-bearing, or unresolved. This closes the
> silent-disappearance gap while allowing raw conversational noise to remain
> outside the candidate-claim inventory under recorded extraction criteria.

This is the Aleph analogue of Straylight's governed-transition rule. In
Straylight, a diary entry / raw event / recalled note has no standing simply
because it was written or remembered; it gains standing only through an
authorized transition. In Aleph, **a source claim has no standing in the Précis
unless its disposition is recorded.**

The Précis is trusted because its compression trail is inspectable, not because
it sounds coherent.

### Completeness, defined narrowly

Completeness is **not** omniscience. A Précis cannot prove it captured every
possible interpretation of a corpus. The defensible definition is:

> Completeness means every candidate claim extracted from the declared corpus
> scope has a recorded disposition; and the extraction method / inclusion
> criteria are recorded so the boundary between raw noise and candidate claim is
> auditable.

So the Précis does not claim "I captured everything imaginable." It claims
"nothing load-bearing that entered the extraction pass silently vanished."

### Two-level boundary (avoids bloat)

`judged-non-load-bearing` is recorded at the **candidate-claim level**, not at the
raw-token / every-sentence / every-chat-line level. Greetings, typos, repeated
instructions, tool noise, and conversational filler do not each need a
disposition — they stay outside the candidate-claim inventory under recorded
extraction criteria. But once a source unit has been recognized as a candidate
claim, it cannot disappear silently; it must receive a disposition, including
`judged-non-load-bearing`.

### Disposition ledger — valid disposition set

```
carried
merged
deferred
excluded-with-reason
backgrounded
judged-non-load-bearing
unresolved
```

### A vs B

```
A = canonical completeness contract.
B = presentation compression only, never inventory compression.
```

- **A is the doctrine.** Every candidate claim gets a disposition.
- **B may exist only as a v0 presentation-compression shortcut for clearly
  non-load-bearing material.** It may group how such material is summarized in the
  human-readable Précis, but it does not replace the candidate-claim inventory.
  Every candidate claim must still remain individually represented in the
  candidate-claim inventory / packet index with its recorded disposition. Grouping
  compresses presentation; it does not create an off-ledger discard path.

## Completeness trail (order of operations)

```
source inventory
  → extraction pass
    → packet index
      → classification / disposition pass
        → duplicate / merge map
          → do-not-use negative boundaries
            → stress-test matrix
              → cluster synthesis
                → unresolved / deferred queue
                  → projection-neutral Research Précis
```

## Wedge acceptance criteria

The wedge succeeds only if all of the following hold:

1. Source inventory exists.
2. Extraction method / inclusion criteria are recorded.
3. Candidate claim inventory exists.
4. Every candidate claim has a disposition.
5. `judged-non-load-bearing` is an explicit disposition.
6. Duplicate claims are merged with provenance retained.
7. Excluded claims carry reasons.
8. Deferred / unresolved claims remain visible.
9. No projection is generated *by the Précis itself*; the Précis stays
   projection-neutral. (Projection happens in the separate downstream stage —
   see `docs/decisions/0001-projection-as-separate-downstream-stage.md` — now
   implemented separately, never inside this wedge.)
10. Final output of *this wedge* is a portable, projection-neutral Research
    Précis file.

## v0 acceptance envelope (provisional — not a schema freeze)

The final internal schema is **not** frozen. Per the Straylight precedent, the
packets are run first and the matrices name the structure second. But the wedge
needs an acceptance envelope so it does not become vibes. A valid v0 Research
Précis must minimally carry:

- corpus scope
- source inventory
- extraction method / inclusion criteria
- candidate-claim inventory / packet index containing every candidate claim and
  its recorded disposition
- classification / disposition ledger summary covering all seven dispositions,
  including judged-non-load-bearing
- carried claims
- merged claims
- deferred claims
- excluded-with-reason claims
- backgrounded claims
- duplicate / merge map
- do-not-use / negative boundaries
- cluster synthesis
- unresolved claims / questions
- consumer-deferred projection notes
- verification summary
- known incompleteness / limits

The envelope is built so the portable artifact carries enough evidence to verify
every candidate claim's disposition: the candidate-claim inventory / packet index
lists every candidate claim, and the disposition ledger summary accounts for all
seven dispositions, so no claim's fate is asserted without recorded evidence.

The `known incompleteness / limits` field is where corpus-scope honesty lives:
it lets a Précis declare its own gaps as a first-class section, so "complete"
never has to mean "omniscient."

## Out of scope for this wedge

This wedge proves the neutral Précis only. The projection stage (which *does*
produce PRDs, doctrines, specs, etc.) is real, Aleph-owned, and implemented
separately — see
`docs/decisions/0001-projection-as-separate-downstream-stage.md`. So, for *this
wedge*:

- No projection generated by the Précis itself (the Précis stays neutral).
- No PRD, product-doctrine, or spec produced *in this wedge*.
- No endpoint.
- No serving dependency.
- No pitch deck.
- No live automation.
- No final schema freeze.
