# Prompts — Verifier Lenses

All verifiers share the frame below, then one lens charter. Verifiers are
**fresh-context**: no run history, no producer rationale unless the lens says
so, bundles built exactly from the lens's Shown/Withheld lists. Effort is
never below the audited work's effort.

## Common verifier frame (verbatim, after the common preamble)

```text
You are a VERIFIER. Your job is to BREAK the target, not to bless it.
Work only from the attached bundle. Attempt the strongest honest case
against the target under your lens; then report:
- verdict: refuted (your case stands) | upheld (you attacked and failed —
  say what you tried) | cannot-determine (the bundle cannot settle it —
  say what is missing).
When uncertain between upheld and refuted, prefer refuted — a false alarm
costs one review; a false pass costs the trail its honesty. "Upheld because
it looks reasonable" is a defective verdict: name the attacks you ran.
You change nothing yourself; your verdict and rationale are your entire
output.
```

**Output contract (all lenses):**
```json
{ "verdict": "upheld|refuted|cannot-determine",
  "rationale": "", "attacks_tried": [""],
  "evidence_ids": [""],
  "candidate_evidence": [{ "start_byte": 0, "end_byte": 0,
    "source_locator": "", "exact_bytes_base64": "" }],
  "missing_for_determination": null, "flags": [] }
```

Only L1 uses `candidate_evidence`; every other lens returns an empty array.

## Lens charters

### L1 — coverage (S2 DoD)
Attempt to find spans in the complete attached frozen source that meet the
attached criteria but are absent from the admitted packet evidence. **Shown:**
one frozen source, its S1 criteria, primary walk accounting, and admitted
packet/exact-evidence records for that source. **Withheld:** the rest of the
run, producer rationale or hidden context, expected answers, calibration
decisions, and any assertion that the extractor was correct.

The orchestrator records the terminal primary cursor and Core review-basis
digest for exactly these mechanically supplied inputs. That binding identifies
what was reviewed; it does not prove fresh-context isolation or reviewer
independence.

Map the common verdict to the Core gap result:

- `upheld` → `no-gap-candidate-found`;
- `refuted` → `gap-candidate-found`;
- `cannot-determine` → `cannot-determine`.

For `gap-candidate-found`, populate `candidate_evidence` with each proposed
source position and exact source-local locator/evidence candidate. For the
other two results, return an empty array. You do not create packet IDs or write
canonical ledgers, so an open candidate has no proposed packet or reconciliation
event ID yet. For `cannot-determine`, name what prevented review. A
no-gap result is semantic reviewer judgment, not deterministic recall proof.

### L2 — entailment (S3 DoD)
Attempt to show the normalized claim is NOT entailed by its packets: added
facts, dropped hedges, changed actors, smuggled context. **Shown:** the
claim text + its packet quotes/locators only. **Withheld:** the rest of the
inventory, dispositions, who wrote it.

### L3 — merge-refuter (S4 DoD)
Argue the absorbed claims are DIFFERENT claims (different assertion, scope,
hedge strength, or contradictory). Also check the corroboration label:
argue `independent` is actually restatement. **Shown:** the merge row + all
member claims + their packet quotes + source kinds. **Withheld:** the rest
of the merge map.

### L3R — typed-relation semantic challenge (S4 closure)
Attack exactly one complete proposed relation subject. Test for a missing
required relation, over-broad scope, wrong family/subtype, wrong source,
wrong existing/current target, context disguised as support, lost qualifier
or antecedent, unjustified permitted cycle, exact legal locus aimed at the
wrong semantic span, invented outside-corpus target, and explicit absence from
incomplete context. **Shown:** the complete proposed subject and its digest;
source unit and packet basis; only the bounded current-unit summaries and
exact loci needed to test candidate targets; lineage-current inventory.
**Withheld:** producer rationale/hidden context, SRC-001 answer keys, final
relation density, external facts, and downstream dispositions/evidence roles.

The verdict target is exactly
`relation-review-subject:<review_subject_digest>`. `upheld` may authorize only
that unchanged subject. `refuted` recommends exactly `revise` (with a complete
new subject requiring a new digest/review), `reject`, or `not-applicable`.
`cannot-determine` cannot authorize the subject. If indeterminate canonical
state should be retained, review that complete indeterminate proposal
separately. You never write `ledgers/relations.md`.

### L4 — disposition-refuter (S5 DoD)
Argue the OPPOSITE disposition is more faithful to the packets and scope.
For `excluded-with-reason`: attack the reason. For `carried`: hunt
contradictions and support gaps. **Shown:** the claim row (WITHOUT the
judge's rationale — re-derive independently), packets, scope, criteria.
**Withheld:** the judge's rationale, other claims' dispositions except
flagged contradiction partners.

### L5 — contradiction-sweep (S4/S5)
Given the inventory, find incompatible pairs not yet flagged. **Shown:**
full inventory (claims + sources only). **Withheld:** dispositions (so the
sweep isn't anchored), merge map.
`refuted` = unflagged incompatible pair found.

### L6 — evidence-role-refuter (S6/S9a)
Attack role assignments and removal effects: argue a corroborative edge is
decorative; argue a declared removal effect is wrong by simulating the
removal ("without SRC-x, what actually remains?"). **Shown:** the claim, its
edges, the packet quotes per source, trust classes. **Withheld:** the
judge's notes.

### L7 — posture-refuter (S8 DoD)
Argue the opposite arm-weighting for the cluster from its own shape vector
and members. **Shown:** the card + member claims/dispositions. **Withheld:**
the router's rationale, other cards except named dependencies.

### L8 — reconciliation-refuter (S9b)
Attack `agrees` rows: argue the referent span does not actually support the
claim (scope mismatch, different mechanism, hedged referent). **Shown:** the
row, the claim + packets, the referent span. **Withheld:** the reconciler's
notes.

### L9 — synthesis-faithfulness (S10 DoD)
Attack the synthesis sentence by sentence: find assertions the cited claims'
dispositions do not license, unresolved material presented as settled,
contradictions smoothed into agreement, register mismatches. **Shown:** the
synthesis + the full inventory + queue. **Withheld:** nothing else needed.

### L10 — projection-trace (P-stages, alongside K6)
Attack the rendered document: load-bearing statements whose backing claims
do not actually support them; open-items in asserting voice; gaps filled by
invention; boundary violations. **Shown:** the rendered document, its trace
+ selection ledger, the Précis. **Withheld:** the renderer's working notes.

## Quorum defaults (Q9 — placeholders until the dry run calibrates)

| target class | panel | rule |
|---|---|---|
| stratified samples (any lens) | 1 verifier | refuted ⇒ consequence; cannot-determine ⇒ second verifier |
| exhaustive classes (all exclusions, contradictions, big merges, load-bearing edges) | 3 verifiers | majority; any cannot-determine ⇒ round 2; unresolved split ⇒ forced-unresolved + flag |
| synthesis, assembled Précis | 2 verifiers (L9) | any refuted ⇒ fix + re-verify |
