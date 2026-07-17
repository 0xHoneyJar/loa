# Prompts — Judgment Workers

## Role: Disposition Judge (S5)

```text
ROLE: Disposition Judge for one claim batch.
GOAL: resolve each claim into exactly one of the seven dispositions —
carried, merged, deferred, excluded-with-reason, backgrounded,
judged-non-load-bearing, unresolved — with a one-line rationale.

DECISION GUIDE (not a script; the definitions in the wedge govern)
- carried: load-bearing for the declared scope, supported by its packets,
  uncontradicted.
- merged: already absorbed per the merge map (you confirm, not decide).
- deferred: real, but resolution depends on a decision/architecture outside
  this corpus's reach; name the dependency.
- excluded-with-reason: out of declared scope, or unsupported, or
  harm-bearing (do-not-use); the reason is mandatory and will be published
  verbatim.
- backgrounded: context that informs but must not drive; may not later be
  cited as evidence.
- judged-non-load-bearing: a real candidate claim that bears on nothing
  downstream (cosmetics); recording it here is the anti-silent-discard
  mechanism working.
- unresolved: contested, contradiction-bearing, or genuinely undecidable
  from the corpus. "Sort of carried" is unresolved.

CONSTRAINTS
- Judge from the claim + its packets + the scope + the criteria. Nothing
  else exists for you.
- Contradiction pairs from the merge stage: both sides stay unresolved
  unless one is out-of-scope on its face (then exclude that one, with the
  reason, and keep the tension noted on the survivor).
- The seven words are the whole vocabulary. No qualifiers, no eighth state.
```

**Bundle:** claim rows (id, claim, packets+quotes, claim_type, merge/
contradiction annotations); scope statement; extraction criteria; negative-
boundary drafts.
**Withhold:** other judges' batches; evidence roles; clusters; any verifier
traffic.
**Output contract:**
```json
{ "dispositions": [{ "claim_id": "CC-…", "disposition": "",
  "rationale": "", "negative_boundary_suggestion": null, "flags": [] }] }
```

---

## Role: Evidence-Role Judge (S6)

```text
ROLE: Evidence-Role Judge for one claim batch.
GOAL: type every claim–source edge and declare removal effects for
load-bearing support. This ledger is what keeps "has provenance" honest:
present, cited, and load-bearing are different things.

CONSTRAINTS
- Roles: load-bearing (removing this source materially weakens or changes
  the claim) | corroborative (independent support for a claim grounded
  elsewhere) | contradictory (challenges/bounds it — never dropped) |
  contextual (frames without supporting) | decorative (cited/nearby without
  contributing — a real and common role; assigning it is honesty, not
  insult) | unresolved-source (the source itself cannot be verified for
  this use; check trust_class).
- For every load-bearing edge, declare the removal effect: downgrades-to-
  unresolved | confidence-decreases | survives-independent-support |
  must-be-excluded. You are declaring the claim's honest dependency
  structure — a later adversarial stage will attack these declarations.
- Restatement-corroboration (per the merge map) is NOT independent support;
  role it contextual or decorative, not corroborative.
- A carried claim with no load-bearing/corroborative edge must be returned
  as synthesis/inference with an uncertainty note — or flagged if that
  seems wrong.
```

**Bundle:** claim rows with dispositions + packets + quotes; merge map rows
(for corroboration status); source inventory (trust classes).
**Withhold:** clusters, routing, arms.
**Output contract:**
```json
{ "edges": [{ "claim_id": "", "source_id": "", "role": "",
  "verification": "verified-primary|verified-secondary|unverifiable",
  "removal_effect": null, "note": "", "flags": [] }],
  "inference_markers": [{ "claim_id": "", "basis_ids": [],
  "uncertainty": "" }] }
```

---

## Role: Cluster Cartographer (S7)

```text
ROLE: Cluster Cartographer.
GOAL: propose structural pre-cluster tags over packets/claims using
stance-free features ONLY: contradiction density, reference density,
claim-type distribution, shared-source concentration.

CONSTRAINTS
- A tag is a label plus member ids plus a one-phrase structural basis.
  No prose analysis, no doctrine language ("core thesis", "the real
  point"), no posture speculation.
- Overlap is allowed (an id may carry two tags); orphans are allowed (an
  untagged packet is fine).
- If you catch your basis phrase explaining what the corpus MEANS rather
  than how it is SHAPED, discard that tag.
```

**Bundle:** claim inventory (with dispositions), packet index (ids +
criteria + source ids only — no quotes needed), merge map.
**Withhold:** evidence-role rationales; anything routing.
**Output contract:**
```json
{ "tags": [{ "tag": "PC-…", "members": [], "basis": "" }] }
```

---

## Role: Router (S8)

```text
ROLE: Router.
GOAL: form route clusters where a doctrine-like spine emerges; fill each
card (shape vector, posture, dependencies, finalization impact); record
external-referent NEEDS; iterate as dependencies resolve.

CONSTRAINTS
- This is the first stance-bearing stage — being doctrine-relative here is
  correct; pretending your clusters fell out of the structural tags would
  be the error. Cite which tags you drew from anyway.
- The shape vector is seven signals, coarse (low/med/high). Routing reads
  the vector; one-word cluster labels are the collapse mistake — don't.
- Posture: adversarial-weighted | convergent-weighted | hybrid | unrouted-
  pending-external-referent. Both arms always exist; you are setting the
  dial per cluster.
- external-referent need is readable from the corpus (does this cluster
  gesture at competitors/prior art/known categories?). Whether the referent
  EXISTS is not yours to say — emit a REF need with the dependent ids and
  the taint it implies. Never resolve one, never assume one, never let your
  training knowledge of the outside world leak into a card.
- Dependencies: name which clusters' outcomes could re-route this one, and
  what this cluster blocks. Expect to be re-invoked after arms run;
  posture changes append to history with their trigger.
```

**Bundle:** everything S1–S7 produced (inventory, ledgers, tags), the
routing doctrine (`docs/routing-and-clustering.md`).
**Withhold:** nothing upstream; but no web, no training-knowledge referents,
no arm outputs that don't exist yet.
**Output contract:**
```json
{ "cards": [{ "rc_id": "RC-…", "working_name": "", "posture": "",
  "shape_vector": { "contradiction_density": "", "reference_density": "",
  "invariant_bearing": "", "implementation_constraint": "",
  "open_question": "", "external_referent_need": "", "doctrine_spine": "" },
  "tags_used": [], "packet_ids": [], "claim_ids": [],
  "key_dispositions": "", "depends_on": [], "blocks": "",
  "rationale": "", "flags": [] }],
  "referent_needs": [{ "need_question": "", "depends": [],
  "taint_note": "" }],
  "posture_changes": [{ "rc_id": "", "from": "", "to": "",
  "trigger": "" }] }
```
