# Vision: Opus Review-Quality Benchmark Harness

**ID**: vision-010
**Source**: Flatline PRD review of Opus 4.7 migration (simstim-20260417-4a16c55f)
**PR**: [#547](https://github.com/0xHoneyJar/loa/pull/547) (Opus 4.7 migration, cycle-082)
**Date**: 2026-04-17T00:00:00Z
**Status**: Captured
**Tags**: [quality-validation, review-regression, benchmarks, flatline, model-migration]

## Insight

Loa's model-migration PRDs currently rely on vendor announcements + one dogfood Flatline run to validate that a new top-review model is "not worse" than the predecessor. This is directionally fine but offers no early warning for subtler regressions: refusal-rate drift, false-positive finding rates, consistency across runs on the same document, or changes in tone/severity calibration. A formal benchmark harness — a fixed suite of PRD/SDD/sprint artifacts with known-good/known-bad findings, scored quantitatively against new vs. old models — would give a reproducible pass-rate metric for every future opus/sonnet cutover.

## Potential

- Automated regression detection across Opus 4.6→4.7, 4.7→4.8, etc.
- Evidence trail for auditors: "model X scored 87% finding recall on the canonical benchmark suite"
- Unblocks aggressive cutover cadence (today's migrations are cautious partly because we can't measure regression precisely)
- Reusable for sonnet/cheap-tier migrations and for evaluating alternative providers (gemini, gpt) on review roles

## Connection Points

- Flatline finding: SKP-001 (CRITICAL, 910) from Flatline PRD review of Opus 4.7 migration
- Deferred from Opus 4.7 migration PRD per operator acceptance (simstim blocker_decisions[] `SKP-001: defer`)
- Relates to existing `.claude/evals/flatline-3model.sh` (infrastructure scaffold exists)
- Connects to `grimoires/loa/reports/spiral-harness-benchmark-report.md` (prior benchmarking work)
- Would plug into `/eval` skill and CI pipeline

## Estimated Scope

- 3–5 PRD/SDD/sprint artifacts with hand-labeled finding sets (small corpus to start)
- Scoring runner: calls each configured model on the corpus, compares against gold-standard findings
- Metrics: precision/recall on finding detection, severity-calibration correlation, refusal rate, latency delta
- Integration: new `/eval review-quality` subcommand; CI gate on model-registry PRs
- Cycle cost: 1 full /simstim cycle
