# Structured-output fixture corpus (cycle-124 Sprint 2, FR-7)

Each file is a translated model envelope (`content`, token/cost fields, optional
`stop_reason`) plus two annotation keys the consumers ignore:

- `_case` — what the payload reproduces (`KF-004` dissent shapes, `KF-023` Flatline
  voice shapes, one `max_tokens` truncation).
- `_expect` — the outcome per parse path: `unenforced` (today's tolerant path:
  fence strip + raw_decode + normalization + repair) and `enforced` (strict parse
  only). For `process_findings` the value is the envelope `metadata.status`; for
  `qualify_flatline_content` it is the rejection reason (or `accepted`).

The bats suites feed every file through both paths:
`tests/unit/adversarial-review-schema-enforced.bats` (kf004 + truncated) and
`tests/integration/flatline-content-qualified-quorum.bats` (kf023).
SYNTHETIC — authored from the documented failure shapes, not captured live
(PRD Q8: synthetic fixtures are labelled as such).
