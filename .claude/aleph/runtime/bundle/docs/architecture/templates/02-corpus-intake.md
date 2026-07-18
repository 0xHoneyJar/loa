# Templates 02 — Corpus Intake

## T2.1 Corpus manifest → `runs/<run-id>/corpus/manifest.md`

```markdown
# Corpus Manifest — ⟨RUN-slug⟩

## Scope
⟨The approved scope statement, verbatim from the manifest sign-off.⟩

## Span-addressing schemes in use
| scheme id | applies to | locator format |
|-----------|------------|----------------|
| md-lines | markdown/plain files | `L⟨start⟩-L⟨end⟩` of the frozen file |
| chat-msg | conversation exports | `M⟨n⟩` (1-based message index) or `M⟨n⟩:S⟨k⟩` (sentence k within message n) |
| ⟨add per format; propose new schemes in the same PR that first needs them⟩ | | |

## Source inventory
| source_id | kind | locus | scheme | content_hash | date(s) | trust_class | sensitivity | admission note |
|-----------|------|-------|--------|--------------|---------|-------------|-------------|----------------|
```

Column rules:

- `kind`: `conversation-export` | `deep-research-output` | `design-note` |
  `spec` | `external-research-intake` | `authority-statement` (closed set;
  extend only via PR).
- `trust_class`: `first-party` | `model-generated` | `third-party` |
  `unverifiable` — records provenance character, judges nothing.
- `sensitivity`: `none` | `pii` | `confidential` | `licensing` (comma-join
  multiple). Any non-`none` value requires an S0 authority ruling row in the
  run manifest before extraction may start.
- `admission note`: one line — why this source is inside the declared scope.
- `external-research-intake` and `authority-statement` rows must cite the
  `REF-NN` they resolve (see T4.4).
- Every source row is admitted before S0 freeze. Research material received
  later belongs to a successor run whose manifest names this run; never append
  it to the frozen corpus. A post-freeze authority resolution belongs in the
  current run's manifest sign-off table, not in a new source row.

<!-- example -->
| SRC-101 | deep-research-output | sources/access-model.md | md-lines | sha256:9f31… | 2026-06 | model-generated | none | core access-model research named by scope |

## T2.2 Extraction criteria → `runs/<run-id>/ledgers/extraction-criteria.md`

```markdown
# Extraction Criteria — ⟨RUN-slug⟩
<!-- The written timestamp must predate the first packet row. -->
- written: ⟨date/time⟩
- author: ⟨actor⟩

## Candidate-claim definition (this corpus)
⟨One paragraph instantiating the wedge definition for this scope: a
declarative assertion about ⟨scope subject⟩ that could plausibly bear on a
downstream decision.⟩

## Admission criteria  <!-- numbered; packets cite these numbers -->
| # | criterion | example span that qualifies |
|---|-----------|-----------------------------|
| 1 | ⟨…⟩ | ⟨…⟩ |

## Exclusion classes (outside candidacy, recorded here once)
| class | description | example |
|-------|-------------|---------|
| scaffolding | greetings, "agreed/right", speaker labels, formatting | "Sounds good — " |
| tool-noise | logs, stack traces quoted without assertion | ⟨…⟩ |
| refusal-blocked | span a safety classifier refused to process (agent mode); routed to manual handling | n/a |
| ⟨…⟩ | | |

## Packet granularity policy
⟨2–4 sentences: what a span is for each source kind; when to widen; the
over-extraction bias stated explicitly.⟩

## Normalization conventions (used at S3)
⟨Restated-once rules: tense, actor naming, hedging words preserved or
normalized how, units.⟩

## Supersessions  <!-- criteria changes; each forces re-extraction -->
| # | date | change | re-extraction completed over |
|---|------|--------|------------------------------|
```
