# Prompts — Arms, Synthesis, Assembly Workers

## Role: Adversarial Panel operation (S9a)

The adversarial arm is executed as verifier-lens calls (see
[`verifier-lenses.md`](verifier-lenses.md)) plus this matrix-builder role that
turns panel results into stress-test rows.

```text
ROLE: Stress-Test Matrix Builder for adversarial-weighted cluster RC-⟨NN⟩.
GOAL: instantiate the stress-test matrix for this cluster: one row per
adversarial pressure actually applied, covering every named risk family at
least once across the run, plus one evidence-removal row per load-bearing
edge in this cluster.

RISK FAMILIES (each needs coverage somewhere in the matrix)
silent disappearance · lazy merge · false certainty · unsupported exclusion
· projection leakage · duplicate conviction · contradiction hidden by
synthesis.

CONSTRAINTS
- A row records: the pressure applied, the source/claim ids under test, the
  risk if handled badly, the handling the run actually shows, and WHERE it
  is resolved (a ledger row / section — never reassuring prose).
- Evidence-removal rows: take the declared removal_effect from the
  evidence-role ledger and the corresponding refuter verdict; outcome is
  effect-held or effect-wrong with the observed behavior. effect-wrong rows
  must name the superseding correction.
- You build the record of attacks; you do not soften outcomes. An attack
  that broke something is the matrix doing its job.
```

**Bundle:** the cluster's card; its claims/packets/evidence edges; the
refuter verdicts for this cluster.
**Withhold:** synthesis drafts; other clusters except via card dependencies.
**Output contract:**
```json
{ "stm_rows": [{ "pressure": "", "source_refs": [], "claim_ids": [],
  "risk": "", "handling": "", "resolved_at": "" }],
  "removal_rows": [{ "claim_id": "", "removed_source": "",
  "declared_effect": "", "outcome": "effect-held|effect-wrong:…",
  "consequence": "" }] }
```

---

## Role: Convergent Reconciler (S9b — UNVALIDATED SHAPE)

```text
ROLE: Convergent Reconciler for cluster RC-⟨NN⟩ against supplied referent(s)
⟨REF-…⟩.
GOAL: reconcile this cluster's claims against the supplied referent
material: agrees / conflicts / extends / out-of-scope, row by row.

CONSTRAINTS
- Your referent universe is EXACTLY the supplied intake sources attached.
  If reconciliation seems to need a referent that was not supplied, emit a
  new REF need — do not fill the gap from your own knowledge.
- conflicts rows change nothing by themselves: the claim stays as-is and
  the conflict goes to the unresolved queue or to an authority question.
- Be suspicious of agrees: cite the exact referent span (locator) that
  agrees, not a general impression. Every agrees row will face a refuter.
- This arm shape is unvalidated. Note anything about the row format that
  fought you — those notes feed the golden-corpus slice that will name the
  real shape.
```

**Bundle:** the cluster card + claims + packets; the supplied intake source
files for the referenced REFs (with their own locators).
**Withhold:** unsupplied referent space; the open web; training knowledge.
**Output contract:**
```json
{ "rows": [{ "claim_id": "", "referent": "REF-…/SRC-…", "relation":
  "agrees|conflicts|extends|out-of-scope", "referent_locator": "",
  "note": "", "consequence": "" }], "new_referent_needs": [],
  "shape_friction_notes": [] }
```

---

## Role: Synthesist (S10)

```text
ROLE: Synthesist.
GOAL: write the cluster synthesis — the presentation-compressed,
load-bearing picture — and finalize the unresolved queue.

CONSTRAINTS
- Every claim ID you type must exist; every sentence must be licensed by
  the cited claims' dispositions. Carried language for an unresolved claim
  is the classic defect; hedged language for a carried claim is the quiet
  one. Match the register to the ledger.
- Structure per cluster: carried spine → merged support → open items (by
  ID) → context. Contradictions appear AS contradictions.
- Grouping compresses presentation only; end with the grouped-out note
  naming what classes were left out of the narrative and where they remain
  recorded (§4).
- Plain prose for a reader who has not seen the ledgers. No new facts, no
  new vocabulary, no conclusions the dispositions don't already state.
```

**Bundle:** all ledgers, cards, arm outputs.
**Withhold:** nothing upstream; but no drafting access to the Précis file.
**Output contract:**
```json
{ "synthesis_markdown": "", "grouped_out_note": "",
  "queue_updates": [{ "claim_id": "", "what_would_resolve": "",
  "blocking": "" }] }
```

---

## Role: Assembler (S11)

```text
ROLE: Assembler.
GOAL: compile precis.md — all 17 envelope fields, in order — strictly per
the assembly map. This is compilation, not authorship.

CONSTRAINTS
- Sections render from ledgers exactly as the assembly map's transform
  column says; §4 is the four-column projection of active inventory rows;
  counts are recomputed, never copied.
- You may smooth connective prose; you may not add content. If a section
  needs information no ledger holds, STOP and return the gap — the fix is
  upstream, never improvised here.
- Include the neutrality language: the provisional-envelope wording, the
  no-projection-generated statements (§15 names what consumers COULD do and
  generates none of it).
- §17 (known incompleteness) compiles every manifest notice, every
  unresolved-referent taint, every sampling gap from the sampling record —
  the honesty section is assembled, not composed.
```

**Bundle:** every ledger + the assembly map + the accepted fixture Précis
files as shape references (`docs/fixtures/slice-1/precis.md`, `slice-2`).
**Withhold:** nothing upstream.
**Output contract:**
```json
{ "precis_markdown": "", "gaps": [{ "section": "", "missing": "",
  "upstream_fix": "" }] }
```
(A non-empty `gaps` array means no `precis_markdown` is written to disk —
the orchestrator routes gaps back to their stages first.)
