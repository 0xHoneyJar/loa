# Structured-output fixture corpus (cycle-124 Sprint 2, FR-7)

Each file is a translated model envelope (`content`, token/cost fields, optional
`stop_reason`) plus two annotation keys the consumers ignore:

- `_case` — what the payload reproduces (`KF-004` dissent shapes, `KF-023` Flatline
  voice shapes, one `max_tokens` truncation); `_type` — the dissent type
  (`review` | `audit`) a kf004 fixture is processed as.
- kf004 (PRD AC-7.2): enforced-valid `review-blocking`, `review-advisory-anchorless`,
  `audit-critical`, `audit-all-severities`, `findings-empty-clean` — every one must
  land with `rejected_count == 0` and no sidecar row on the enforced path; legacy
  `legacy-fenced`, `legacy-prose-preamble` — rescued unenforced, refused enforced;
  `neg-*` — shapes the enforced branch must reject without repair.
- kf023 (PRD AC-7.2): `reviewer-empty-with-reason` (accepted), `reviewer-empty-no-reason`
  (`schema_invalid`), `reviewer-prose` (`normalization_failed` / `enforced_parse_failed`),
  plus two `extra-*` shapes.
- `_expect` — the outcome per parse path: `unenforced` (today's tolerant path:
  fence strip + raw_decode + normalization; the bats stub the model repair call
  to fail, so `unenforced` pins the path *without* a successful repair) and
  `enforced` (strict parse only). "Enforced-valid" is pinned mechanically by
  `.claude/adapters/tests/test_structured_outputs_fixtures_wire_valid.py`
  (every such fixture validates against its wire schema; every `neg-*` does not). For `process_findings` the value is the envelope `metadata.status`; for
  `qualify_flatline_content` it is the rejection reason (or `accepted`); optional
  `enforced_rejected` / `*_findings` pin the counts.

The bats suites feed every file through both paths:
`tests/unit/adversarial-review-schema-enforced.bats` (kf004 + truncated) and
`tests/integration/flatline-content-qualified-quorum.bats` (kf023).
SYNTHETIC — authored from the documented failure shapes, not captured live
(PRD Q8: synthetic fixtures are labelled as such).
