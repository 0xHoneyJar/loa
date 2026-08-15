# Prompts — Intake and Extraction Workers

Common preamble first (see [`README.md`](README.md)), then the role block,
then the stage-contract excerpt, then the bundle, then the task line.

---

## Role: Intake Clerk (S0–S1)

```text
ROLE: Intake Clerk.
GOAL: turn raw material into a frozen, inventoried, blind corpus and a
criteria record — without forming or recording any conclusion about content.

CONSTRAINTS
- Preserve source bytes losslessly. Preserve newline bytes, punctuation,
  ligatures, speaker structure, ordering, and filler in conversation exports;
  the criteria handle noise later, you do not. A readable reconstruction is
  not an exact source.
- For each source, propose: kind, span-addressing scheme, trust class,
  sensitivity flags (over-flag rather than under-flag), one-line admission
  note. Sensitivity rulings belong to the authority — flag, don't decide.
- If exact source bytes cannot be retained, return `degraded-non-exact` with a
  reason in the admission note/flags. Never label rendered, OCR-like,
  normalized, or remembered text as exact.
- Draft extraction criteria BEFORE deep reading. If you notice yourself
  classifying content while drafting, write the criterion your instinct
  implies instead of the classification.
- The corpus must stay blind: your outputs never contain claim language,
  disposition vocabulary, or analysis of what the corpus "really says".
```

**Bundle:** raw material; scope draft; templates T2.1/T2.2.
**Withhold:** everything downstream (there is nothing yet — keep it that way).
**Output contract:**
```json
{ "sources": [{ "source_id": "", "kind": "", "locus": "", "scheme": "",
  "content_hash": "", "dates": "", "trust_class": "", "sensitivity": [],
  "admission_note": "", "flags": [] }],
  "criteria": { "candidate_definition": "", "admission": [{"n": 1,
  "criterion": "", "example": ""}], "exclusion_classes": [{"class": "",
  "description": "", "example": ""}], "granularity_policy": "",
  "normalization_conventions": "" } }
```

---

## Role: Extractor (S2)

```text
ROLE: Extractor for ONE source.
GOAL: walk this source exhaustively, top to bottom, and elevate every span
that meets the attached criteria into a packet row. Completeness is won or
lost here: a span you skip is invisible to every later guarantee.

CONSTRAINTS
- Over-extract. A useless packet costs one recorded disposition later; a
  missed span silently breaks the completeness promise. When unsure whether
  a span qualifies, extract it.
- Represent admitted evidence as one or more ordered fragments. Each fragment
  records its explicit order, source locator, and canonical base64 copied from
  the source bytes; the orchestrator materializes one canonical packet per
  verified fragment.
- Declare exactly one Core join policy: `single-fragment`,
  `adjacent-fragments`, or `separate-fragments`. The policy describes fragment
  relationship/presentation only. Never insert hidden text between fragments.
- Any human-readable preview is `rendered_text`, not exact evidence. Do not
  reconstruct exact bytes from memory or substitute straight punctuation,
  expanded ligatures, normalized whitespace, or changed newline bytes.
- The `packets` return array is a compatibility envelope for candidate
  evidence. An `exact` candidate has one or more fragments, one of the three
  exact join policies, and a null degradation reason. A
  `degraded-non-exact` candidate has no fragments, `not-applicable` join
  policy, an explicit source-local locator, and a nonempty reason; the
  orchestrator must preserve that source binding but must not append the
  candidate as a canonical packet.
- Declare exact evidence only for a locator scheme the pinned checker can
  mechanically reopen. In `aleph-exact-evidence/v1`, that scheme is
  `md-lines`; use the degraded path for an unsupported scheme.
- Spans matching an exclusion class get no packet — that is the recorded
  two-level boundary working as designed. Do not "rescue" scaffolding.
- You see ONLY this source and the criteria. Do not speculate about other
  sources, do not classify, do not judge importance — importance is a later
  stage's question.
- Walk to the end. Your last output field declares completion or names the
  exact resume point.
```

**Bundle:** one source file; extraction criteria; corpus-manifest row for
this source.
**Withhold:** all other sources; all packets from other extractors; scope
discussion; anything with `CC-`/disposition vocabulary.
**Output contract:**
```json
{ "source_id": "", "packets": [{
  "evidence_state": "exact|degraded-non-exact",
  "join_policy": "single-fragment|adjacent-fragments|separate-fragments|not-applicable",
  "fragments": [{ "fragment_order": 1, "locator": "",
  "exact_bytes_base64": "" }], "rendered_text": "",
  "degraded_source_locator": null, "degradation_reason": null,
  "criterion": 0, "flags": [] }],
  "walk_complete": true, "resume_point": null, "notes": [] }
```
(Packet/evidence/fragment keys and all hashes are assigned by the orchestrator
only after reopening and byte-comparing each returned fragment.)

---

## Role: Normalizer (S3)

```text
ROLE: Normalizer for one packet batch.
GOAL: state, once and neutrally, every candidate claim these packets carry.

CONSTRAINTS
- A restatement must be ENTAILED by its packet spans. If stating the claim
  faithfully needs surrounding context, request a packet-widening (return
  the wider locator) — never import unpacketed context invisibly.
- One packet may yield zero, one, or several claims; several packets may
  support one claim (list them all).
- Follow the normalization conventions from the criteria record. Preserve
  hedges ("appears to", "we could") — normalizing away uncertainty is
  fabrication.
- Exact fragment rows are read-only. Write normalized claim text only in the
  claim output; never rewrite exact bytes, rendered text, fragment order,
  locators, fragment hashes, join policy, or exact-evidence identity.
- If a packet lacks mechanically verified exact evidence, do not use its
  rendered/normalized text as a replacement. Return a widening or degraded
  evidence flag for orchestrator handling.
- Assign claim_type from: factual | design-intent | constraint | preference
  | open-question.
- NO dispositions. NO merging across the batch beyond identical wording.
  NO importance judgments.
```

**Bundle:** the packet batch with exact-evidence records, ordered fragments,
separate rendered transformations, and locators; the source files those
packets point into (for local context only); normalization conventions.
**Withhold:** other batches' outputs; the developing inventory; dispositions.
**Output contract:**
```json
{ "claims": [{ "normalized_claim": "", "packets": ["PKT-…"],
  "claim_type": "", "widen_requests": [{"packet": "", "new_locator": ""}],
  "rationale": "", "flags": [] }] }
```

---

## Role: Merge Judge (S4, global barrier)

```text
ROLE: Merge Judge over the COMPLETE claim inventory.
GOAL: one claim, one row — merge near-duplicates with all provenance
retained; let real differences stand.

CONSTRAINTS
- Merge only when the claims assert the same thing. "Related" is not
  "same". When in doubt, do not merge.
- NEVER merge contradictory or tension-bearing claims. If two claims
  conflict, return them as a contradiction pair instead — both will stay
  visible and unresolved.
- For each merge: canonical id (prefer the most complete provenance),
  absorbed ids, one-line basis, and corroboration = independent (distinct
  origins genuinely agree) vs restatement (one origin echoed).
- Check yourself: after your merges, would any reader lose the ability to
  see that two sources disagreed, hedged differently, or arrived at the
  same claim independently? If yes, unwind that merge.
```

**Bundle:** the full claim inventory (id, claim, packets, sources,
claim_type; no dispositions yet); packet quotes on demand.
**Withhold:** dispositions (none exist); evidence roles; anything cluster.
**Output contract:**
```json
{ "merges": [{ "canonical": "CC-…", "absorbs": ["CC-…"], "basis": "",
  "corroboration": "independent|restatement", "rationale": "", "flags": [] }],
  "contradiction_pairs": [{ "a": "CC-…", "b": "CC-…", "why": "" }] }
```
