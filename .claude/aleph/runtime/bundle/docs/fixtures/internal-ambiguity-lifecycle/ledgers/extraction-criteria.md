# Extraction Criteria — RUN-internal-ambiguity-lifecycle

- written: 2026-08-14 08:10 UTC
- author: manual-fixture-coordinator

## Candidate-claim definition

Synthetic declarative statements selected to exercise traversal accounting.

## Admission criteria

| # | criterion | example span that qualifies |
|---|-----------|-----------------------------|
| 1 | a direct synthetic assertion | a complete assertion |
| 2 | two ordered source fragments that form one synthetic observation | separated source fragments |

## Exclusion classes

| class | description | example |
|-------|-------------|---------|
| scaffolding | fixture-only heading text | source heading |

## Packet granularity policy

Use one packet per exact fragment. Multiple qualifying events may share one
source position when their shared-position key and ordinals remain explicit.

## Normalization conventions

Rendered text never replaces exact source bytes.

## Supersessions

| # | date | change | re-extraction completed over |
|---|------|--------|------------------------------|
