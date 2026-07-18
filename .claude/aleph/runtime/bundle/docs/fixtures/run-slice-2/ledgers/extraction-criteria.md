# Extraction Criteria — RUN-slice-2

- written: 2026-07-16 08:25 UTC
- author: manual-fixture-coordinator

## Candidate-claim definition

A candidate claim is a declarative assertion about the token-gated access model
or its immediate community and growth mechanics that could plausibly bear on a
downstream decision. Once admitted, a claim receives one recorded disposition;
apparent irrelevance, conflict, deferral, or harm is handled by disposition
rather than pre-extraction deletion.

## Admission criteria

| # | criterion | example span that qualifies |
|---|-----------|-----------------------------|
| 1 | Assertion about the access gate, membership tiering, or an access constraint | holding a threshold unlocks gated member channels |
| 2 | Assertion about retention, engagement, growth, referrals, or category context | gating appears to improve member retention |
| 3 | Open implementation choice whose resolution could change the access or referral design | single token versus one token per tier |
| 4 | Concrete proposal that must be dispositioned to preserve scope or negative-boundary accountability | token buyback or publishing wallet holdings |

## Exclusion classes

| class | description | example |
|-------|-------------|---------|
| scaffolding | speaker labels, conversational fillers, formatting, and acknowledgements that assert nothing independently | `A:`, `Maybe`, `Sure` |
| corpus-description | headings and fixture framing that describe the source container rather than its subject | source-title heading |
| tool-noise | logs or tool output quoted without a subject-matter assertion | none present |
| refusal-blocked | a span a classifier refused to process and that requires manual handling | none present |

## Packet granularity policy

One claim-bearing paragraph is one packet unless distinct claims inside the
paragraph require independent re-entry coordinates. Locators include every line
needed to preserve the assertion's qualification. Over-extraction is preferred
to a missed subject-matter assertion, but overlapping packets are not created
merely to inflate inventory size.

## Normalization conventions

Restate each claim once in neutral declarative language. Preserve uncertainty,
association language, alternatives, and normative force. Do not import facts
outside the packet spans. Near-duplicates remain separate claims until the
global merge pass; incompatible claims remain separate.

## Supersessions

| # | date | change | re-extraction completed over |
|---|------|--------|------------------------------|

No criteria supersession occurred in this fixture.
