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
claim text + exact packet bytes/locators, separately labeled transformations,
and required representation closure for a 1.6 run (packet quotes/locators
only for predecessor contracts). **Withheld:** the rest of the
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

### L2F — formal/table/layout use challenge (S3/S4)


Register only `verifier-l2f`, legal at S3 and S4, mapped to this exact charter.
Use the existing refuter kind and fresh-context enforcement. Its pinned profile
uses the same model slot/context class as verifier-l2 and satisfies the existing
effort floor relative to the producer. No provider abstraction or new vision
capability is implied. It must return cannot-determine for a supplied modality
that its actual worker transport cannot consume.

L2F attacks one complete proposed use subject and its actual packet/claim/
relation text. It asks whether required material is missing, whether the
requirements hide a dependence on unavailable structure, and whether the
proposed wording promotes a rendering or flattened form beyond its evidence.
Specifically attack shifted cells, header/caption associations, glyph/spacing
loss, equation reconstruction, chart-value inference, and undeclared layout.

**Shown:** exact subject/digest, exact packet bytes/hashes, selected source-local
objects and their structural dependencies, origin/rendering provenance,
separately labeled outputs, and recorded limitations. **Withheld:** producer
rationale/hidden context, other batches, dispositions, authority responses and
observations, downstream narratives, calibration answers, and expected IDs.
Structural dependencies mean parent chain, table axes/cells/headers/captions
actually referenced, and their provenance/assets; no unrelated-source bundle.

Use the existing common verifier return, with candidate_evidence empty.
Upheld permits only the identical reviewed usable subject. Refuted requires a
revised candidate and fresh subject, rejection, or visible limitation.
Cannot-determine blocks that affirmative use and names missing material.
No verifier writes the inventory, chooses a missing header, repairs an
equation, or grants acceptance. Real freshness is a host/process obligation;
static VER existence is only structural evidence.


For 1.6 L1, include the same-source inventory and limitations with source,
walk, and packet evidence; challenge omitted declared tables, captions, and
fragments. For 1.6 L3R, include the exact relation use subject and required
layout closure. A legal header/locus does not establish relation meaning.

### L2S — atomicity, context, and semantic preservation (S2/S3)

```text
For L2S, return refuted when a concrete counterexample against this proposed
subject stands. Return cannot-determine when the permitted frozen evidence
cannot settle the question; do not convert missing basis into refutation or
approval. Return upheld only after stating the attacks you tried and why they
did not defeat this exact proposal. In unresolved-record mode, uphold only
the honest recording of uncertainty, never the unsettled proposition itself.

Challenge every enumerated field in the sealed semantic subject. Attempt
stronger and weaker readings, compound-assertion, missing-context, qualifier,
condition, scope, modality, attribution, role, comparator and metric attacks.
Challenge result/interpretation coupling, unsupported interpretation, dangling
referents and undeclared material dependence. Do not repair the target, write
ledgers, invent source truth, research externally, choose human authority
actions, decide duplicate equivalence, or replace L1, L2F or L3R.
In unresolved-record mode challenge faithful retention of the exact unknown
and missing basis. Upholding that record never licenses its proposition.
```

**Shown:** exactly one sealed semantic subject and the exact assets in its embedded Slice 6 view. Source windows are only the explicit source-bound anchors; packet bytes and declared context are bound by the subject. At S4, only an already-proposed direct lineage successor may be challenged.
**Withheld:** producer rationale/history and identity tuples; prior reviewer verdicts/rationales; full source by default; global inventory; unrelated batches/sources; authority responses/observations; calibration answers; expected dispositions or IDs; recall quotas; downstream narratives.

The fixed task is `Challenge only the attached sealed semantic subject under L2S.`
Every 1.7 selector receives review. Retain all assignments and results; any
refutation blocks admission, and any cannot-determine blocks affirmative use
and requires a second fresh reviewer of the identical subject. A later upheld
review cannot erase an earlier indeterminate one. Bounded context requests
require a new subject and invocation; whole-source referent search uses the
existing Slice 5 completion/search procedure through the stage producer.

**Output contract:**
```json
{
  "contract_format": "aleph-semantic-output-contract/v1",
  "capability": "semantic-unit-review",
  "role": "verifier-l2s",
  "shape": {
    "format": "aleph-semantic-result/v1",
    "subject_digest": "",
    "verdict": "upheld|refuted|cannot-determine",
    "field_reviews": [
      {
        "field_path": "",
        "verdict": "upheld|refuted|cannot-determine",
        "issue": "none|compound-assertion|lost-context|spurious-context|altered-scope|lost-condition|altered-qualifier|altered-modality|altered-attribution|conflated-role|result-interpretation-collapse|lost-comparator|lost-metric|unsupported-interpretation|unresolved-referent|missing-material|illegal-relation-use|insufficient-context",
        "anchor_ids": [
          "A1"
        ],
        "material_requirement_indexes": [
          0
        ],
        "explanation": ""
      }
    ],
    "unresolved_findings": [
      {
        "finding_id": "F1",
        "field_path": "/semantics/atomicity",
        "code": "atomicity-indeterminate|context-insufficient|scope-indeterminate|condition-indeterminate|qualifier-indeterminate|modality-indeterminate|attribution-indeterminate|role-indeterminate|referent-unresolved|comparator-indeterminate|metric-indeterminate|material-unavailable|relation-deferred|interpretation-unsupported",
        "anchor_ids": [
          "A1"
        ],
        "material_requirement_indexes": [
          0
        ],
        "unknown_dimension": "none|population|temporal|geographic|experiment-task|document-universe|quantified|exclusion-restriction|comparison-dimension|measurement-unit",
        "missing": "",
        "requested_context": [
          {
            "source_id": "SRC-…",
            "locator": "",
            "purpose": "local-context|same-source-referent-search|material-inspection"
          }
        ]
      }
    ],
    "attacks_tried": [
      ""
    ],
    "missing_for_determination": null,
    "rationale": "",
    "candidate_evidence": []
  }
}
```
