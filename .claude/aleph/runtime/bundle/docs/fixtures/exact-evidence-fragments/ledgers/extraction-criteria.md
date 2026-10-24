# Extraction Criteria — RUN-exact-evidence-fragments

- written: 2026-08-13 09:15 UTC
- author: manual-fixture-coordinator

## Candidate-claim definition

Any synthetic declarative sentence selected to exercise exact evidence.

## Admission criteria

| # | criterion | example span that qualifies |
|---|-----------|-----------------------------|
| 1 | exact source bytes selected for the structural fixture | one complete source line |

## Exclusion classes

| class | description | example |
|-------|-------------|---------|
| scaffolding | headings and explanatory fixture prose | source heading |

## Packet granularity policy

Use one packet per exact fragment. Group packets into an evidence record when
the represented evidence has multiple ordered fragments.

## Normalization conventions

Rendered and normalized text may differ from source bytes, but neither may
replace or mutate the exact fragment records.

## Supersessions

| # | date | change | re-extraction completed over |
|---|------|--------|------------------------------|
