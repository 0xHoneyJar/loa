# cycle-109 Sprint 2 T2.8 — verdict_quality conformance fixtures

Canonical regression fixtures for the 5 substrate-degradation failure
modes the verdict_quality envelope is designed to surface. Each fixture
is a single-voice or multi-voice envelope (per the schema at
`.claude/data/schemas/verdict-quality.schema.json`); the conformance
bats matrix at `tests/unit/cycle-109-conformance-matrix.bats` runs each
fixture through `loa_cheval.verdict.quality.compute_verdict_status` and
asserts the expected classification.

## Fixtures

| File | Issue | Description | Expected status |
|---|---|---|---|
| `kf002-empty-content-prd-review.json` | cycle-109 PRD-review | 1 voice dropped (Opus EmptyContent) in 3-voice cohort under implementation sprint | **DEGRADED** |
| `bug-807-multi-model-fallback-misses.json` | [#807](https://github.com/0xHoneyJar/loa/issues/807) | 2 voices fallback-walked; 1 succeeded; remaining voices reached consensus | **DEGRADED** |
| `bug-809-status-clean-misleading.json` | [#809](https://github.com/0xHoneyJar/loa/issues/809) | flatline-dissenter empty-content 3/3 cohort; auto-promotes per NFR-Rel-1 | **FAILED** |
| `bug-868-chain-exhausted-both-phases.json` | [#868](https://github.com/0xHoneyJar/loa/issues/868) | adversarial-review fallback chain exhausts (gpt-5.2 → gemini-2.5-pro both fail) | **FAILED** |
| `bug-805-single-model-bb-claim.json` | [#805](https://github.com/0xHoneyJar/loa/issues/805) | BB claims multi-model but Pass-2 fails 80% → 1-voice envelope with chain_health degraded | **DEGRADED** |

## How to extend

Add a new envelope JSON file conforming to verdict-quality.schema.json.
Add a row to `tests/unit/cycle-109-conformance-matrix.bats` with the
expected classification. The matrix bats validates each fixture against
the schema AND runs it through the canonical Python classifier; a
mismatch between expected status and computed status fails the test.
