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
GOAL: walk this source in frozen-byte order, account for every traversed
region, and propose every span that meets the attached criteria as exact
packet evidence.

CONSTRAINTS
- Over-extract. A useless packet costs one recorded disposition later; a
  missed span may survive into later work. When unsure whether a span
  qualifies, extract it.
- Emit ordered half-open UTF-8 byte intervals as you advance. Every traversed
  byte is admitted, no-candidate-observed, excluded, deferred, or unsupported.
  Never jump silently over a region. Exclusions cite the frozen S1 class;
  deferred/unsupported regions carry a reason and remain visibly open unless a
  permitted closure is recorded.
- Emit packet-producing extraction events separately from coverage intervals.
  When more than one event occurs at one source position, use one shared
  position and contiguous ordinals. Preserve the next pending ordinal across
  interruption; do not fabricate an intermediate cursor when siblings are
  completed uninterrupted.
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
  two-level boundary working as designed. They still receive an excluded walk
  interval. Do not "rescue" scaffolding.
- You see ONLY this source and the criteria. Do not speculate about other
  sources, do not classify, do not judge importance — importance is a later
  stage's question.
- Work only from earlier-to-later source bytes. Never use future-source
  knowledge to revise an earlier proposal in place.
- When bounded work stops or reaches source end, emit a cursor naming the NEXT
  unprocessed byte or same-position event, bound to the frozen source hash and
  predecessor record.
  Set `reason` to exactly one Core value: `initial`, `progress`,
  `bounded-pause`, `resumed-shared-position`, or `source-complete`.
  Source-end is a mechanical statement only.
- Never claim semantic completeness, perfect recall, or that gap review
  passed. A separate fresh reviewer owns that judgment.
- Never fabricate, normalize, or reconstruct source bytes.
```

**Bundle:** one source file; extraction criteria; corpus-manifest row for
this source.
**Withhold:** all other sources; all packets from other extractors; scope
discussion; anything with `CC-`/disposition vocabulary.
**Run format 1.7 semantic duties:** Return one semantic entry for every packet/material candidate. Propose the smallest coherent assertions and explicit source-bound context. Retain exact packets even when their semantics are awkward; never certify recall or adequacy. S2 origins are empty.

**Output contract:**
```json
{
  "contract_format": "aleph-semantic-output-contract/v1",
  "capability": "semantic-unit-review",
  "role": "extractor",
  "shape": {
    "source_id": "",
    "producer_invocation_id": "",
    "walk_intervals": [
      {
        "start_byte": 0,
        "end_byte": 0,
        "outcome": "admitted|no-candidate-observed|excluded|deferred|unsupported",
        "packet_candidate_indexes": [
          0
        ],
        "criterion_ref": "admission:<n>|exclusion:<class>|none",
        "closure_state": "closed|open|resolved",
        "reason": null,
        "closure_note": null
      }
    ],
    "packets": [
      {
        "evidence_state": "exact|degraded-non-exact",
        "join_policy": "single-fragment|adjacent-fragments|separate-fragments|not-applicable",
        "fragments": [
          {
            "fragment_order": 1,
            "locator": "",
            "exact_bytes_base64": ""
          }
        ],
        "rendered_text": "",
        "degraded_source_locator": null,
        "degradation_reason": null,
        "criterion": 0,
        "flags": [],
        "material_use": {
          "requirements": [
            {
              "object_id": "OBJ-…",
              "feature": "text-bytes|table-grid|header-association|caption-association|formal-structure|image|chart-values|spatial-region",
              "binding_ids": [
                "BND-…"
              ]
            }
          ],
          "use_state": "usable|CANNOT_DETERMINE",
          "fidelity_claim": "none|exact-representation|gold",
          "limitation_refs": [],
          "reason": ""
        }
      }
    ],
    "extraction_events": [
      {
        "start_byte": 0,
        "end_byte": 0,
        "shared_position_key": "",
        "event_ordinal": 1,
        "packet_candidate_index": 0,
        "origin": "primary"
      }
    ],
    "next_cursor": {
      "byte_offset": 0,
      "shared_position_key": null,
      "next_event_ordinal": null,
      "predecessor_walk_index": null,
      "predecessor_event_index": null,
      "source_hash": "",
      "reason": "initial|progress|bounded-pause|resumed-shared-position|source-complete"
    },
    "walk_exhausted": false,
    "notes": [],
    "material_findings": [
      {
        "object_id": "OBJ-…",
        "material_use": {
          "requirements": [
            {
              "object_id": "OBJ-…",
              "feature": "text-bytes|table-grid|header-association|caption-association|formal-structure|image|chart-values|spatial-region",
              "binding_ids": [
                "BND-…"
              ]
            }
          ],
          "use_state": "usable|CANNOT_DETERMINE",
          "fidelity_claim": "none|exact-representation|gold",
          "limitation_refs": [],
          "reason": ""
        }
      }
    ],
    "semantic_units": [
      {
        "output_kind": "packet-candidate|material-candidate",
        "output_index": 0,
        "review_mode": "proposal|unresolved-record",
        "origin_unit_refs": [
          "SEM-0001/U1"
        ],
        "anchors": [
          {
            "anchor_id": "A1",
            "source_id": "SRC-…",
            "locator": "",
            "start_byte": 0,
            "end_byte": 1,
            "exact_bytes_base64": ""
          }
        ],
        "semantics": {
          "atomicity": "single-assertion|multiple-separable|inseparable-context|CANNOT_DETERMINE|no-claim",
          "units": [
            {
              "unit_id": "U1",
              "proposition": "",
              "proposition_anchor_ids": [
                "A1"
              ],
              "claim_roles": {
                "state": "present|not-expressed|CANNOT_DETERMINE",
                "items": [
                  {
                    "kind": "result-observation|method-procedure|interpretation-inference|background-context|definition|recommendation|attribution-report|limitation-uncertainty",
                    "source_text": "",
                    "anchor_ids": [
                      "A1"
                    ]
                  }
                ],
                "basis_anchor_ids": [
                  "A1"
                ]
              },
              "scope": {
                "state": "present|not-expressed|CANNOT_DETERMINE",
                "items": [
                  {
                    "kind": "population|temporal|geographic|experiment-task|document-universe|quantified|exclusion-restriction",
                    "source_text": "",
                    "anchor_ids": [
                      "A1"
                    ]
                  }
                ],
                "basis_anchor_ids": [
                  "A1"
                ]
              },
              "conditions": {
                "state": "present|not-expressed|CANNOT_DETERMINE",
                "items": [
                  {
                    "kind": "condition|precondition",
                    "source_text": "",
                    "anchor_ids": [
                      "A1"
                    ]
                  }
                ],
                "basis_anchor_ids": [
                  "A1"
                ]
              },
              "qualifiers": {
                "state": "present|not-expressed|CANNOT_DETERMINE",
                "items": [
                  {
                    "kind": "degree|frequency|approximation|limitation|comparative|exception|confidence-uncertainty",
                    "source_text": "",
                    "anchor_ids": [
                      "A1"
                    ]
                  }
                ],
                "basis_anchor_ids": [
                  "A1"
                ]
              },
              "modality": {
                "state": "present|not-expressed|CANNOT_DETERMINE",
                "items": [
                  {
                    "kind": "observed-descriptive|possible|capable|normative-should|obligatory-must|intended-designed|predicted-expected|hypothetical|counterfactual|recommended",
                    "source_text": "",
                    "anchor_ids": [
                      "A1"
                    ]
                  }
                ],
                "basis_anchor_ids": [
                  "A1"
                ]
              },
              "attribution": {
                "state": "present|not-expressed|CANNOT_DETERMINE",
                "items": [
                  {
                    "kind": "source-author|quoted-entity|cited-external-in-corpus|reported-belief-opinion|system-model-interpretation",
                    "source_text": "",
                    "attributed_to": "",
                    "anchor_ids": [
                      "A1"
                    ]
                  }
                ],
                "basis_anchor_ids": [
                  "A1"
                ]
              },
              "comparator": {
                "state": "present|not-expressed|CANNOT_DETERMINE",
                "items": [
                  {
                    "kind": "comparison-basis",
                    "source_text": "",
                    "subject_anchor_ids": [
                      "A1"
                    ],
                    "baseline_anchor_ids": [
                      "A1"
                    ],
                    "dimension_anchor_ids": [
                      "A1"
                    ],
                    "anchor_ids": [
                      "A1"
                    ]
                  }
                ],
                "basis_anchor_ids": [
                  "A1"
                ]
              },
              "metric": {
                "state": "present|not-expressed|CANNOT_DETERMINE",
                "items": [
                  {
                    "kind": "measured-quantity",
                    "source_text": "",
                    "quantity_anchor_ids": [
                      "A1"
                    ],
                    "value_anchor_ids": [
                      "A1"
                    ],
                    "unit_anchor_ids": [
                      "A1"
                    ],
                    "anchor_ids": [
                      "A1"
                    ]
                  }
                ],
                "basis_anchor_ids": [
                  "A1"
                ]
              }
            }
          ],
          "contexts": [
            {
              "context_id": "C1",
              "kind": "necessary-local|attribution|definition-terms|condition-scope|representation-layout|discourse",
              "applies_to_unit_ids": [
                "U1"
              ],
              "anchor_ids": [
                "A1"
              ],
              "material_requirement_indexes": [
                0
              ],
              "use": "required-for-interpretation|inspection-only|non-evidentiary"
            }
          ],
          "couplings": [
            {
              "kind": "result-interpretation|attribution-content|comparison-comparator|metric-result|condition-claim|required-context",
              "unit_ids": [
                "U1"
              ],
              "anchor_ids": [
                "A1"
              ],
              "treatment": "keep-distinguishable|keep-together|CANNOT_DETERMINE"
            }
          ],
          "relation_proposals": [
            {
              "subject": {
                "format": "aleph-relation-review-subject/v1",
                "owner_stage": "S2|S3|S4",
                "family": "claim-dependency|source-context|formal-reference|discourse|none",
                "type": "semantic-prerequisite|antecedent-context|qualifier-context|configuration-context|structural-anchor|notation-definition|continuation-context|parallel-contrast-context|none",
                "source_kind": "PKT|CC",
                "source_id": "",
                "target_kind": "PKT|CC|source-locus|null",
                "target_id": "",
                "target_source_id": "",
                "target_locator": "",
                "target_span_hash": "",
                "record_state": "asserted|unresolved-target|explicitly-absent|indeterminate",
                "null_reason": "",
                "basis_packet_ids": [
                  "PKT-…"
                ],
                "proposed_by": ""
              },
              "review_subject_digest": "",
              "material_use": {
                "requirements": [
                  {
                    "object_id": "OBJ-…",
                    "feature": "text-bytes|table-grid|header-association|caption-association|formal-structure|image|chart-values|spatial-region",
                    "binding_ids": [
                      "BND-…"
                    ]
                  }
                ],
                "use_state": "usable|CANNOT_DETERMINE",
                "fidelity_claim": "none|exact-representation|gold",
                "limitation_refs": [],
                "reason": ""
              }
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
          ]
        }
      }
    ]
  }
}
```
(Packet/evidence/fragment keys and all hashes are assigned by the orchestrator
only after reopening and byte-comparing each returned fragment. Walk/event
IDs and the durable cursor are committed in the same single-writer
transaction as any admitted packet.)

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
- For a packet that yields no claim, return an explicit no-claim proposal
  with its packet id and structural basis. Do not invent a successor.
- If correcting an already materialized packet/claim identity is explicitly in
  the authorized S2-S4 task, propose the bounded lineage transformation; never
  mutate a predecessor row in place.
- NO dispositions. NO merging across the batch beyond identical wording.
  NO importance judgments.
```

**Bundle:** the packet batch with exact-evidence records, ordered fragments,
separate rendered transformations, and locators; the source files those
packets point into (for local context only); normalization conventions.
**Withhold:** other batches' outputs; the developing inventory; dispositions.
**Run format 1.7 semantic duties:** Return one semantic entry for every claim/no-claim/material candidate. Emit every facet slot, preserve source-supported force, actor and condition, and bind outputs to reviewed S2 origins. Request exact packets for required context before affirmative use; do not merge for prose elegance. The allowed source window is exactly the named spans and inspection anchors, with no automatic radius or full-source attachment.

**Output contract:**
```json
{
  "contract_format": "aleph-semantic-output-contract/v1",
  "capability": "semantic-unit-review",
  "role": "normalizer",
  "shape": {
    "claims": [
      {
        "normalized_claim": "",
        "packets": [
          "PKT-…"
        ],
        "claim_type": "",
        "widen_requests": [
          {
            "packet": "",
            "new_locator": ""
          }
        ],
        "rationale": "",
        "flags": [],
        "material_use": {
          "requirements": [
            {
              "object_id": "OBJ-…",
              "feature": "text-bytes|table-grid|header-association|caption-association|formal-structure|image|chart-values|spatial-region",
              "binding_ids": [
                "BND-…"
              ]
            }
          ],
          "use_state": "usable|CANNOT_DETERMINE",
          "fidelity_claim": "none|exact-representation|gold",
          "limitation_refs": [],
          "reason": ""
        }
      }
    ],
    "no_claim_packets": [
      {
        "packet": "PKT-…",
        "basis": ""
      }
    ],
    "lineage_proposals": [
      {
        "type": "split|replace|supersede|reject|exclude",
        "predecessors": [
          "PKT-…|CC-…"
        ],
        "successor_specs": [],
        "basis": ""
      }
    ],
    "material_findings": [
      {
        "object_id": "OBJ-…",
        "material_use": {
          "requirements": [
            {
              "object_id": "OBJ-…",
              "feature": "text-bytes|table-grid|header-association|caption-association|formal-structure|image|chart-values|spatial-region",
              "binding_ids": [
                "BND-…"
              ]
            }
          ],
          "use_state": "usable|CANNOT_DETERMINE",
          "fidelity_claim": "none|exact-representation|gold",
          "limitation_refs": [],
          "reason": ""
        }
      }
    ],
    "semantic_units": [
      {
        "output_kind": "claim-candidate|no-claim-candidate|material-candidate",
        "output_index": 0,
        "review_mode": "proposal|unresolved-record",
        "origin_unit_refs": [
          "SEM-0001/U1"
        ],
        "anchors": [
          {
            "anchor_id": "A1",
            "source_id": "SRC-…",
            "locator": "",
            "start_byte": 0,
            "end_byte": 1,
            "exact_bytes_base64": ""
          }
        ],
        "semantics": {
          "atomicity": "single-assertion|multiple-separable|inseparable-context|CANNOT_DETERMINE|no-claim",
          "units": [
            {
              "unit_id": "U1",
              "proposition": "",
              "proposition_anchor_ids": [
                "A1"
              ],
              "claim_roles": {
                "state": "present|not-expressed|CANNOT_DETERMINE",
                "items": [
                  {
                    "kind": "result-observation|method-procedure|interpretation-inference|background-context|definition|recommendation|attribution-report|limitation-uncertainty",
                    "source_text": "",
                    "anchor_ids": [
                      "A1"
                    ]
                  }
                ],
                "basis_anchor_ids": [
                  "A1"
                ]
              },
              "scope": {
                "state": "present|not-expressed|CANNOT_DETERMINE",
                "items": [
                  {
                    "kind": "population|temporal|geographic|experiment-task|document-universe|quantified|exclusion-restriction",
                    "source_text": "",
                    "anchor_ids": [
                      "A1"
                    ]
                  }
                ],
                "basis_anchor_ids": [
                  "A1"
                ]
              },
              "conditions": {
                "state": "present|not-expressed|CANNOT_DETERMINE",
                "items": [
                  {
                    "kind": "condition|precondition",
                    "source_text": "",
                    "anchor_ids": [
                      "A1"
                    ]
                  }
                ],
                "basis_anchor_ids": [
                  "A1"
                ]
              },
              "qualifiers": {
                "state": "present|not-expressed|CANNOT_DETERMINE",
                "items": [
                  {
                    "kind": "degree|frequency|approximation|limitation|comparative|exception|confidence-uncertainty",
                    "source_text": "",
                    "anchor_ids": [
                      "A1"
                    ]
                  }
                ],
                "basis_anchor_ids": [
                  "A1"
                ]
              },
              "modality": {
                "state": "present|not-expressed|CANNOT_DETERMINE",
                "items": [
                  {
                    "kind": "observed-descriptive|possible|capable|normative-should|obligatory-must|intended-designed|predicted-expected|hypothetical|counterfactual|recommended",
                    "source_text": "",
                    "anchor_ids": [
                      "A1"
                    ]
                  }
                ],
                "basis_anchor_ids": [
                  "A1"
                ]
              },
              "attribution": {
                "state": "present|not-expressed|CANNOT_DETERMINE",
                "items": [
                  {
                    "kind": "source-author|quoted-entity|cited-external-in-corpus|reported-belief-opinion|system-model-interpretation",
                    "source_text": "",
                    "attributed_to": "",
                    "anchor_ids": [
                      "A1"
                    ]
                  }
                ],
                "basis_anchor_ids": [
                  "A1"
                ]
              },
              "comparator": {
                "state": "present|not-expressed|CANNOT_DETERMINE",
                "items": [
                  {
                    "kind": "comparison-basis",
                    "source_text": "",
                    "subject_anchor_ids": [
                      "A1"
                    ],
                    "baseline_anchor_ids": [
                      "A1"
                    ],
                    "dimension_anchor_ids": [
                      "A1"
                    ],
                    "anchor_ids": [
                      "A1"
                    ]
                  }
                ],
                "basis_anchor_ids": [
                  "A1"
                ]
              },
              "metric": {
                "state": "present|not-expressed|CANNOT_DETERMINE",
                "items": [
                  {
                    "kind": "measured-quantity",
                    "source_text": "",
                    "quantity_anchor_ids": [
                      "A1"
                    ],
                    "value_anchor_ids": [
                      "A1"
                    ],
                    "unit_anchor_ids": [
                      "A1"
                    ],
                    "anchor_ids": [
                      "A1"
                    ]
                  }
                ],
                "basis_anchor_ids": [
                  "A1"
                ]
              }
            }
          ],
          "contexts": [
            {
              "context_id": "C1",
              "kind": "necessary-local|attribution|definition-terms|condition-scope|representation-layout|discourse",
              "applies_to_unit_ids": [
                "U1"
              ],
              "anchor_ids": [
                "A1"
              ],
              "material_requirement_indexes": [
                0
              ],
              "use": "required-for-interpretation|inspection-only|non-evidentiary"
            }
          ],
          "couplings": [
            {
              "kind": "result-interpretation|attribution-content|comparison-comparator|metric-result|condition-claim|required-context",
              "unit_ids": [
                "U1"
              ],
              "anchor_ids": [
                "A1"
              ],
              "treatment": "keep-distinguishable|keep-together|CANNOT_DETERMINE"
            }
          ],
          "relation_proposals": [
            {
              "subject": {
                "format": "aleph-relation-review-subject/v1",
                "owner_stage": "S2|S3|S4",
                "family": "claim-dependency|source-context|formal-reference|discourse|none",
                "type": "semantic-prerequisite|antecedent-context|qualifier-context|configuration-context|structural-anchor|notation-definition|continuation-context|parallel-contrast-context|none",
                "source_kind": "PKT|CC",
                "source_id": "",
                "target_kind": "PKT|CC|source-locus|null",
                "target_id": "",
                "target_source_id": "",
                "target_locator": "",
                "target_span_hash": "",
                "record_state": "asserted|unresolved-target|explicitly-absent|indeterminate",
                "null_reason": "",
                "basis_packet_ids": [
                  "PKT-…"
                ],
                "proposed_by": ""
              },
              "review_subject_digest": "",
              "material_use": {
                "requirements": [
                  {
                    "object_id": "OBJ-…",
                    "feature": "text-bytes|table-grid|header-association|caption-association|formal-structure|image|chart-values|spatial-region",
                    "binding_ids": [
                      "BND-…"
                    ]
                  }
                ],
                "use_state": "usable|CANNOT_DETERMINE",
                "fidelity_claim": "none|exact-representation|gold",
                "limitation_refs": [],
                "reason": ""
              }
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
          ]
        }
      }
    ]
  }
}
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
- For each merge/duplicate in run format 1.3 and later, do NOT reuse or mutate a
  predecessor as canonical. Propose a new successor claim specification with
  normalized text, claim type, and the complete packet-provenance union; the
  orchestrator assigns its new CC id and the LIN id only after validation.
- Distinguish `duplicate` (same-claim canonicalization) from `merge`
  (several distinct predecessor identities intentionally forming one successor).
  Record one-line basis and corroboration = independent (distinct origins
  genuinely agree) vs restatement (one origin echoed).
- Check yourself: after your merges, would any reader lose the ability to
  see that two sources disagreed, hedged differently, or arrived at the
  same claim independently? If yes, unwind that merge.
```

**Bundle:** the full claim inventory (id, claim, packets, sources,
claim_type; no dispositions yet); packet quotes on demand.
**Withhold:** dispositions (none exist); evidence roles; anything cluster.
**Output contract:**
```json
{
  "canonicalizations": [
    {
      "lineage_type": "merge|duplicate",
      "predecessors": [
        "CC-…"
      ],
      "successor": {
        "normalized_claim": "",
        "packets": [
          "PKT-…"
        ],
        "claim_type": "",
        "material_use": {
          "requirements": [
            {
              "object_id": "OBJ-…",
              "feature": "text-bytes|table-grid|header-association|caption-association|formal-structure|image|chart-values|spatial-region",
              "binding_ids": [
                "BND-…"
              ]
            }
          ],
          "use_state": "usable|CANNOT_DETERMINE",
          "fidelity_claim": "none|exact-representation|gold",
          "limitation_refs": [],
          "reason": ""
        }
      },
      "basis": "",
      "corroboration": "independent|restatement",
      "rationale": "",
      "flags": []
    }
  ],
  "contradiction_pairs": [
    {
      "a": "CC-…",
      "b": "CC-…",
      "why": ""
    }
  ],
  "material_findings": [
    {
      "object_id": "OBJ-…",
      "material_use": {
        "requirements": [
          {
            "object_id": "OBJ-…",
            "feature": "text-bytes|table-grid|header-association|caption-association|formal-structure|image|chart-values|spatial-region",
            "binding_ids": [
              "BND-…"
            ]
          }
        ],
        "use_state": "usable|CANNOT_DETERMINE",
        "fidelity_claim": "none|exact-representation|gold",
        "limitation_refs": [],
        "reason": ""
      }
    }
  ]
}
```

---

## Role: Local Relation Producer (S2 or S3)

```text
ROLE: Typed-relation producer for one legally bounded local context.
GOAL: propose complete typed relation subjects without writing the canonical
relation ledger or converting context into support.

CONSTRAINTS
- At S2, you see one source and its already materialized packet IDs only.
  Propose packet-source context, formal-reference, or discourse relations
  available from that source. Never inspect another source, propose a
  cross-source relation, target a claim, or create semantic-prerequisite.
- At S3, you see one current packet/claim batch and only its legal source
  context. You may propose claim-level relations, including
  semantic-prerequisite, but never inspect another batch merely to discover
  relations.
- Use only the closed four-family/eight-subtype vocabulary and the exact
  state/endpoint matrix. A missing target is typed null, never prose.
- Every durable endpoint you propose must be the explicit candidate ID. Never
  infer a successor for a historical identity.
- `basis_packet_ids` is ordered, nonempty, and source-bound. Relations are not
  proof, support, corroboration, contradiction, disposition, or authority.
- Serialize the complete 14-field pre-review subject as fixed-order compact
  JSON with format `aleph-relation-review-subject/v1`; preserve packet order;
  return its full lowercase `sha256:` digest.
- Propose only. You never assign REL IDs, cite a reviewer, or write
  ledgers/relations.md.
```

**Bundle at S2:** one frozen source, its manifest row, materialized packets,
and exact evidence.

**Bundle at S3:** the current packet/claim batch and its legal source context.

**Withhold:** every other source/batch, dispositions, evidence roles, routing,
answer keys, relation-density targets, and downstream artifacts.

**Output contract:**
```json
{
  "relation_proposals": [
    {
      "owner_stage": "S2|S3",
      "family": "claim-dependency|source-context|formal-reference|discourse|none",
      "type": "semantic-prerequisite|antecedent-context|qualifier-context|configuration-context|structural-anchor|notation-definition|continuation-context|parallel-contrast-context|none",
      "source_kind": "PKT|CC",
      "source_id": "PKT-…|CC-…",
      "target_kind": "PKT|CC|source-locus|null",
      "target_id": "PKT-…|CC-…|none",
      "target_source_id": "SRC-…|none",
      "target_locator": "",
      "target_span_hash": "sha256:…|none",
      "record_state": "asserted|unresolved-target|explicitly-absent|indeterminate",
      "null_reason": "none|unresolved-in-frozen-corpus|outside-frozen-corpus|target-not-materialized|bounded-review-found-none|insufficient-frozen-context|conflicting-durable-representations|unsupported-source-structure",
      "basis_packet_ids": [
        "PKT-…"
      ],
      "proposed_by": "human:…|invocation:…",
      "review_subject_digest": "sha256:…",
      "rationale": "",
      "flags": [],
      "material_use": {
        "requirements": [
          {
            "object_id": "OBJ-…",
            "feature": "text-bytes|table-grid|header-association|caption-association|formal-structure|image|chart-values|spatial-region",
            "binding_ids": [
              "BND-…"
            ]
          }
        ],
        "use_state": "usable|CANNOT_DETERMINE",
        "fidelity_claim": "none|exact-representation|gold",
        "limitation_refs": [],
        "reason": ""
      }
    }
  ],
  "not_applicable": [],
  "material_findings": [
    {
      "object_id": "OBJ-…",
      "material_use": {
        "requirements": [
          {
            "object_id": "OBJ-…",
            "feature": "text-bytes|table-grid|header-association|caption-association|formal-structure|image|chart-values|spatial-region",
            "binding_ids": [
              "BND-…"
            ]
          }
        ],
        "use_state": "usable|CANNOT_DETERMINE",
        "fidelity_claim": "none|exact-representation|gold",
        "limitation_refs": [],
        "reason": ""
      }
    }
  ]
}
```

---

## Role: Global Relation Producer (S4)

```text
ROLE: Typed-relation producer at the S4 global barrier.
GOAL: identify and reconcile relations that require the lineage-current global
inventory, cross-batch context, cross-source context, or other context
legally unavailable to S2/S3.

CONSTRAINTS
- All eight relation types are available when required by the bounded task.
- Start from the lineage-current inventory. Historical endpoints may appear
  in retained review evidence or packet basis, never as canonical endpoints.
  Do not auto-retarget a historical proposal; assess an explicit successor
  anew.
- Apply the exact schema, typed-null scopes, conflict rules, self-edge rules,
  and subtype-specific cycle policy. Qualifier/configuration cycles are only
  structurally permitted and still require fresh semantic challenge.
- Do not create duplicate/overlap/evidence/lineage relation types; do not
  decide disposition, evidence role, routing, ambiguity lifecycle, or human
  authority.
- Produce complete review subjects and digests exactly as the local producer
  does. Propose only; the fresh reviewer challenges, and the orchestrator is
  the sole canonical writer.
```

**Bundle:** complete lineage-current PKT/CC inventory; frozen source manifest
and exact loci needed for the bounded questions; retained S2/S3 proposals.

**Withhold:** producer rationales from the later reviewer, SRC-001 answer keys,
external facts, final density targets, and downstream decisions.

**Output contract:** the same `relation_proposals` contract as the local
producer, with `owner_stage = S4`.

## Material producer obligations — run format 1.6

The material constraint block in the assembly rules applies verbatim. Intake
reports captured facts and missing metadata without authoring objects or render
receipts. Extractor candidates declare same-source features and retain failed
material candidates. Normalizers request packet widening for necessary header
or caption bytes; AST context is never packet evidence. Merge successors name
their own requirements and preserve predecessor limitations and packet union.
Relation producers preserve the existing taxonomy and return material uses
without authoring support or source meaning.

`material_findings` is explicitly empty when there are no failed candidates.
Every populated finding has `CANNOT_DETERMINE` and nonempty limitation refs.
Findings-only output does not establish no-claim or a successful source walk.
Workers allocate no USE IDs, canonical subject IDs, review IDs, or digests for
material uses. Core reserves and verifies the exact subjects. Gold is a
recognized forbidden assertion and always rejected.

## Role: Successor Semantic Normalizer (S4 pre-C1)

```text
Express only the exact already-proposed lineage successor. Preserve the direct
predecessor provenance union and meaning in every semantic facet. Return the
same complete normalizer contract. Do not choose a merge group, decide
duplicate-versus-overlap, change its membership, inspect unrelated inventory,
or repair L3 judgment. If faithful preservation is impossible, retain the
refuted or indeterminate proposal and block that successor.
```

**Bundle:** exact proposed successor; direct predecessor semantic records and provenance union; explicitly named legal source context and Slice 6 material views.
**Withhold:** unrelated inventory and merge groups; L3 rationale or verdict preference; relation closure outcomes; downstream narratives; authority observations; expected answers.
**Output contract:**
```json
{
  "contract_format": "aleph-semantic-output-contract/v1",
  "capability": "semantic-unit-review",
  "role": "normalizer",
  "shape": {
    "claims": [
      {
        "normalized_claim": "",
        "packets": [
          "PKT-…"
        ],
        "claim_type": "",
        "widen_requests": [
          {
            "packet": "",
            "new_locator": ""
          }
        ],
        "rationale": "",
        "flags": [],
        "material_use": {
          "requirements": [
            {
              "object_id": "OBJ-…",
              "feature": "text-bytes|table-grid|header-association|caption-association|formal-structure|image|chart-values|spatial-region",
              "binding_ids": [
                "BND-…"
              ]
            }
          ],
          "use_state": "usable|CANNOT_DETERMINE",
          "fidelity_claim": "none|exact-representation|gold",
          "limitation_refs": [],
          "reason": ""
        }
      }
    ],
    "no_claim_packets": [
      {
        "packet": "PKT-…",
        "basis": ""
      }
    ],
    "lineage_proposals": [
      {
        "type": "split|replace|supersede|reject|exclude",
        "predecessors": [
          "PKT-…|CC-…"
        ],
        "successor_specs": [],
        "basis": ""
      }
    ],
    "material_findings": [
      {
        "object_id": "OBJ-…",
        "material_use": {
          "requirements": [
            {
              "object_id": "OBJ-…",
              "feature": "text-bytes|table-grid|header-association|caption-association|formal-structure|image|chart-values|spatial-region",
              "binding_ids": [
                "BND-…"
              ]
            }
          ],
          "use_state": "usable|CANNOT_DETERMINE",
          "fidelity_claim": "none|exact-representation|gold",
          "limitation_refs": [],
          "reason": ""
        }
      }
    ],
    "semantic_units": [
      {
        "output_kind": "claim-candidate|no-claim-candidate|material-candidate",
        "output_index": 0,
        "review_mode": "proposal|unresolved-record",
        "origin_unit_refs": [
          "SEM-0001/U1"
        ],
        "anchors": [
          {
            "anchor_id": "A1",
            "source_id": "SRC-…",
            "locator": "",
            "start_byte": 0,
            "end_byte": 1,
            "exact_bytes_base64": ""
          }
        ],
        "semantics": {
          "atomicity": "single-assertion|multiple-separable|inseparable-context|CANNOT_DETERMINE|no-claim",
          "units": [
            {
              "unit_id": "U1",
              "proposition": "",
              "proposition_anchor_ids": [
                "A1"
              ],
              "claim_roles": {
                "state": "present|not-expressed|CANNOT_DETERMINE",
                "items": [
                  {
                    "kind": "result-observation|method-procedure|interpretation-inference|background-context|definition|recommendation|attribution-report|limitation-uncertainty",
                    "source_text": "",
                    "anchor_ids": [
                      "A1"
                    ]
                  }
                ],
                "basis_anchor_ids": [
                  "A1"
                ]
              },
              "scope": {
                "state": "present|not-expressed|CANNOT_DETERMINE",
                "items": [
                  {
                    "kind": "population|temporal|geographic|experiment-task|document-universe|quantified|exclusion-restriction",
                    "source_text": "",
                    "anchor_ids": [
                      "A1"
                    ]
                  }
                ],
                "basis_anchor_ids": [
                  "A1"
                ]
              },
              "conditions": {
                "state": "present|not-expressed|CANNOT_DETERMINE",
                "items": [
                  {
                    "kind": "condition|precondition",
                    "source_text": "",
                    "anchor_ids": [
                      "A1"
                    ]
                  }
                ],
                "basis_anchor_ids": [
                  "A1"
                ]
              },
              "qualifiers": {
                "state": "present|not-expressed|CANNOT_DETERMINE",
                "items": [
                  {
                    "kind": "degree|frequency|approximation|limitation|comparative|exception|confidence-uncertainty",
                    "source_text": "",
                    "anchor_ids": [
                      "A1"
                    ]
                  }
                ],
                "basis_anchor_ids": [
                  "A1"
                ]
              },
              "modality": {
                "state": "present|not-expressed|CANNOT_DETERMINE",
                "items": [
                  {
                    "kind": "observed-descriptive|possible|capable|normative-should|obligatory-must|intended-designed|predicted-expected|hypothetical|counterfactual|recommended",
                    "source_text": "",
                    "anchor_ids": [
                      "A1"
                    ]
                  }
                ],
                "basis_anchor_ids": [
                  "A1"
                ]
              },
              "attribution": {
                "state": "present|not-expressed|CANNOT_DETERMINE",
                "items": [
                  {
                    "kind": "source-author|quoted-entity|cited-external-in-corpus|reported-belief-opinion|system-model-interpretation",
                    "source_text": "",
                    "attributed_to": "",
                    "anchor_ids": [
                      "A1"
                    ]
                  }
                ],
                "basis_anchor_ids": [
                  "A1"
                ]
              },
              "comparator": {
                "state": "present|not-expressed|CANNOT_DETERMINE",
                "items": [
                  {
                    "kind": "comparison-basis",
                    "source_text": "",
                    "subject_anchor_ids": [
                      "A1"
                    ],
                    "baseline_anchor_ids": [
                      "A1"
                    ],
                    "dimension_anchor_ids": [
                      "A1"
                    ],
                    "anchor_ids": [
                      "A1"
                    ]
                  }
                ],
                "basis_anchor_ids": [
                  "A1"
                ]
              },
              "metric": {
                "state": "present|not-expressed|CANNOT_DETERMINE",
                "items": [
                  {
                    "kind": "measured-quantity",
                    "source_text": "",
                    "quantity_anchor_ids": [
                      "A1"
                    ],
                    "value_anchor_ids": [
                      "A1"
                    ],
                    "unit_anchor_ids": [
                      "A1"
                    ],
                    "anchor_ids": [
                      "A1"
                    ]
                  }
                ],
                "basis_anchor_ids": [
                  "A1"
                ]
              }
            }
          ],
          "contexts": [
            {
              "context_id": "C1",
              "kind": "necessary-local|attribution|definition-terms|condition-scope|representation-layout|discourse",
              "applies_to_unit_ids": [
                "U1"
              ],
              "anchor_ids": [
                "A1"
              ],
              "material_requirement_indexes": [
                0
              ],
              "use": "required-for-interpretation|inspection-only|non-evidentiary"
            }
          ],
          "couplings": [
            {
              "kind": "result-interpretation|attribution-content|comparison-comparator|metric-result|condition-claim|required-context",
              "unit_ids": [
                "U1"
              ],
              "anchor_ids": [
                "A1"
              ],
              "treatment": "keep-distinguishable|keep-together|CANNOT_DETERMINE"
            }
          ],
          "relation_proposals": [
            {
              "subject": {
                "format": "aleph-relation-review-subject/v1",
                "owner_stage": "S2|S3|S4",
                "family": "claim-dependency|source-context|formal-reference|discourse|none",
                "type": "semantic-prerequisite|antecedent-context|qualifier-context|configuration-context|structural-anchor|notation-definition|continuation-context|parallel-contrast-context|none",
                "source_kind": "PKT|CC",
                "source_id": "",
                "target_kind": "PKT|CC|source-locus|null",
                "target_id": "",
                "target_source_id": "",
                "target_locator": "",
                "target_span_hash": "",
                "record_state": "asserted|unresolved-target|explicitly-absent|indeterminate",
                "null_reason": "",
                "basis_packet_ids": [
                  "PKT-…"
                ],
                "proposed_by": ""
              },
              "review_subject_digest": "",
              "material_use": {
                "requirements": [
                  {
                    "object_id": "OBJ-…",
                    "feature": "text-bytes|table-grid|header-association|caption-association|formal-structure|image|chart-values|spatial-region",
                    "binding_ids": [
                      "BND-…"
                    ]
                  }
                ],
                "use_state": "usable|CANNOT_DETERMINE",
                "fidelity_claim": "none|exact-representation|gold",
                "limitation_refs": [],
                "reason": ""
              }
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
          ]
        }
      }
    ]
  }
}
```
