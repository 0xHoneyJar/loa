Changes required

## Overall Assessment

The patch correctly separates content qualification from transport success in `final_consensus.json`, preserves the configured tertiary denominator, and keeps Cursor read-only. It does not yet close the consumer-visible false green: rejected review files still feed Phase 2, the primary Flatline result omits verdict quality, and Spiral accepts that result by checking only `consensus_summary`.

## Critical Issues

### 1. Qualified quorum is not enforced on the primary result

- Severity: HIGH
- Evidence: `.claude/scripts/flatline-orchestrator.sh:2370`, `.claude/scripts/flatline-orchestrator.sh:2600`, `.claude/scripts/spiral-evidence.sh:162`
- Issue: A rejected review file still reaches `run_phase2`, where normalization substitutes `{"improvements":[]}`. The degraded verdict exists only in a sidecar; `final_result` omits it and `_verify_flatline_output` can report PASSED.
- Required fix: Make the same qualification govern Phase 2 and the primary result. Embed canonical `verdict_quality` in `final_result`, and make the consuming verifier reject any status other than APPROVED.

### 2. Pre-aggregation failures can retain stale APPROVED evidence

- Severity: HIGH
- Evidence: `.claude/scripts/flatline-orchestrator.sh:2320`, `.claude/scripts/flatline-orchestrator.sh:656`
- Issue: The stale artifact is cleared only after `run_phase1` returns. Invalid model configuration, all-voice failure, or any earlier exit leaves the previous phase consensus untouched.
- Required fix: Invalidate the phase consensus before Phase 1 begins, then publish a new result atomically. Add an early-failure regression.

### 3. Aggregator trusts malformed single-voice verdict envelopes

- Severity: HIGH
- Evidence: `.claude/adapters/loa_cheval/verdict/aggregate.py:70`, `.claude/scripts/flatline-orchestrator.sh:672`
- Issue: The aggregator documents `voices_planned == 1` as a MUST but explicitly does not enforce it. A malformed input can overclaim successes and produce a structurally valid clean aggregate.
- Required fix: Validate every input as a single-voice envelope before summing: `voices_planned == 1`, `voices_succeeded <= 1`, `single_voice_call == true`, and internally valid IDs/drop counts. Add malformed-envelope tests.

### 4. Operator-facing changelog is missing

- Severity: HIGH
- Evidence: `CHANGELOG.md:8`
- Issue: `[Unreleased]` has no entry for issue #1227, the Cursor mode change, or the Flatline quorum repair.
- Required fix: Add a concise Unreleased entry after the final behavior is settled.

## Non-Critical Improvements

1. `tests/integration/flatline-content-qualified-quorum.bats:56` manually reconstructs the qualification loop. Add a hermetic main/consumer wiring test so deleting the production call site cannot leave the suite green.
2. `.claude/scripts/flatline-orchestrator.sh:334` should make rejection telemetry fail-soft like the sibling voice-drop event; observability failure must not convert a bounded rejection into an unclassified abort.
3. The phase-global consensus filename remains concurrency-sensitive. Prefer run-scoped evidence plus an atomic latest pointer; if deferred, state the single-run assumption explicitly and track it.

## Previous Feedback Status

No prior engineer-feedback file existed for this sprint.

## Incomplete Tasks

- The configured three-model review has now run, but its blocking findings are not yet repaired.
- Audit cannot begin until the consumer-visible verdict and malformed-envelope boundaries are fixed.

## Adversarial Analysis

### Concerns Identified

1. `.claude/scripts/flatline-orchestrator.sh:2370` lets content-rejected responses influence later consensus as empty reviews.
2. `.claude/scripts/flatline-orchestrator.sh:2320` can leave a stale APPROVED sidecar when failure occurs before aggregation.
3. `.claude/adapters/loa_cheval/verdict/aggregate.py:70` trusts a documented-but-unenforced single-voice input invariant.

### Assumptions Challenged

- **Assumption**: Repairing `final_consensus.json` repairs the Flatline gate.
- **Risk if wrong**: The visible consumer still passes while the sidecar says DEGRADED.
- **Recommendation**: Treat canonical verdict quality as part of the primary output contract and verify it at every consumer.

### Alternatives Not Considered

- **Alternative**: Fail the entire run immediately when any planned review content is rejected.
- **Tradeoff**: Stronger truth boundary and simpler consumers, but loses useful degraded-majority review output.
- **Verdict**: Preserve degraded output, but make it explicit and non-passing; do not silently continue as clean.

## Cross-Model Observations

- Fable: CHANGES_REQUIRED; independently identified the sidecar/primary-output split, early stale evidence, malformed envelope trust, and missing main-path tests.
- Cursor Grok 4.5: APPROVED with three advisories; its strongest advisory matches the blocker that rejected content still reaches Phase 2.
- Codex GPT-5.6 Sol: CHANGES_REQUIRED; identified the consumer-visible false green, pre-aggregation stale artifact, and unenforced single-voice invariant.
- Configured Loa `adversarial-review.sh`: returned clean on a narrower context, with context-escalation `sed` warnings. The broader three-voice council overrules that clean result.
- Fable’s proposed denominator-shrink finding is not applicable: configured tertiary mode always emits its review path from `run_phase1` even when the file is empty (`.claude/scripts/flatline-orchestrator.sh:1551`).

## Complexity Analysis

- `qualify_flatline_content()`: acceptable, 38 lines, four parameters, shallow nesting.
- Aggregation changes: surgical, but the truth boundary is incomplete across producer and consumer.
- Duplication: the test reconstructs main wiring; this is a coverage gap rather than production duplication.
- Dependencies: no new dependency.
- Dead code: none found.
- Net deletion opportunity: none material. The smallest correct repair needs stronger contract checks, not abstraction.

## Documentation Verification

- KF-023 is present with reproduction and reading guide.
- No new command or public API was added.
- CHANGELOG entry is missing and blocks approval.

## Next Steps

1. Return to IMPLEMENTING.
2. Repair the four critical issues with failing-first tests.
3. Re-run focused suites and the three-model council.
4. Return to review only after the primary result and its consumer fail closed on degraded verdict quality.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":4,"medium":3,"low":0},"sprint_id":"sprint-bug-227","ts":"2026-07-19T00:38:02Z"} -->
