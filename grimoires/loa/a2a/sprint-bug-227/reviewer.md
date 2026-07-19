# Implementation Report: sprint-bug-227

## Executive Summary

Flatline now qualifies each Phase 1 review against the `flatline-reviewer` content contract before the voice can contribute to quorum or enter Phase 2. The planned cohort size remains independent of the qualified input count, canonical verdict quality is embedded in the primary result and enforced by Spiral, stale consensus is cleared before provider work, and Cursor structured inference uses read-only `ask` mode while retaining its sandbox boundaries.

## AC Verification

**AC-1**: Bug is no longer reproducible.
- Status: ✓ Met
- Evidence: tests/integration/flatline-content-qualified-quorum.bats:47
- Verification: The captured exit-0 prose response is rejected and the resulting planned three-voice cohort is degraded 2/3, never APPROVED.

**AC-2**: Failing test proves the fix.
- Status: ✓ Met
- Evidence: tests/integration/flatline-content-qualified-quorum.bats:47
- Verification: CQ-1 failed before `qualify_flatline_content` existed and passes after the production qualification path was added.

**AC-3**: Planned quorum never shrinks because content is invalid.
- Status: ✓ Met
- Evidence: .claude/scripts/flatline-orchestrator.sh:2420
- Verification: The configured cohort determines `expected_review_voices`; only qualified files enter aggregation, and the explicit planned count is passed separately.

**AC-4**: No APPROVED result is possible when any planned voice lacks valid review content.
- Status: ✓ Met
- Evidence: .claude/scripts/spiral-evidence.sh:168
- Verification: Schema-invalid content is excluded while the denominator remains three; CQ-1 proves the aggregate is degraded and non-APPROVED, main skips Phase 2, and the consumer rejects any status other than APPROVED. CQ-3 proves prior APPROVED evidence is cleared before provider work.

**AC-5**: Cursor safety boundaries remain intact.
- Status: ✓ Met
- Evidence: .claude/adapters/tests/test_cursor_headless_adapter.py:103
- Verification: Command construction pins read-only `--mode ask`, `--sandbox enabled`, and `--trust`, while prohibiting `-f`, `--force`, and `--yolo`.

## Tasks Completed

- Added a hermetic false-green reproduction using the exact exit-0 prose failure shape observed downstream.
- Added pre-aggregation content normalization and schema qualification with bounded rejection trajectory events.
- Preserved the planned cohort denominator when invalid responses are excluded.
- Cleared stale final-consensus output before provider work and published replacements atomically.
- Embedded canonical verdict quality in the primary Flatline result and taught Spiral to fail closed on DEGRADED or missing status.
- Enforced canonical single-voice verdict envelopes before aggregation.
- Switched Cursor from planning narration mode to read-only Q&A mode and pinned the safety flags in tests.
- Registered KF-023 with the downstream reproduction, workaround, and repair evidence.
- Added the operator-facing Unreleased changelog entry.

## Technical Highlights

- Transport success and epistemic participation are now separate states.
- The existing canonical Python verdict aggregator remains the sole merge implementation.
- A rejected voice is auditable as `consensus.voice_rejected` with voice, reason, agent, and phase.
- DEGRADED content quorum skips Phase 2, is emitted in the primary result, and exits 6.
- Zero qualified voices or malformed verdict inputs fail closed with exit 3.

## Testing Summary

- Focused Flatline, voice-drop, verdict aggregation, normalization, and Spiral Bats suites: 61 passed.
- Cursor adapter and verdict aggregation Python suites: 78 passed, 1 skipped.
- `bash -n .claude/scripts/flatline-orchestrator.sh`: passed.
- `git diff --check`: passed.
- Live Cursor Grok 4.5 `ask`-mode probe returned schema-valid `improvements` JSON under session `23f4abf9-d41e-48a0-97f5-f6de7d7ccb06`.

## Known Limitations

- The default latest-consensus filename is phase-global. Tests and concurrent callers can isolate it with `LOA_FLATLINE_OUTPUT_DIR_OVERRIDE`; automatic run-scoped publication is a separate concurrency hardening.
- Independent Fable, Cursor, and Codex re-review remains the next gate before audit.

## Verification Steps

1. Run the focused Bats suites listed above.
2. Run the Cursor adapter and verdict aggregation Python suites with `PYTHONDONTWRITEBYTECODE=1`.
3. Inspect CQ-1 and confirm `voices_planned=3`, `voices_succeeded=2`, `chain_health=degraded`, and `status!=APPROVED`.
4. Inspect CQ-2 and confirm all-valid behavior remains APPROVED 3/3.
5. Inspect CQ-3 and confirm phase start removes stale consensus before provider work.
6. Inspect CQ-4 and confirm a forged multi-success input fails without publishing consensus.
7. Run Spiral evidence tests and confirm DEGRADED or missing verdict quality is rejected.

## Feedback Addressed

- **Consumer-visible false green**: resolved by skipping Phase 2 on non-APPROVED content quorum, embedding canonical verdict quality in `final_result`, returning exit 6, and enforcing APPROVED in `_verify_flatline_output`.
- **Early stale evidence**: resolved by invalidating the phase artifact before `run_phase1` and using atomic replacement on success.
- **Malformed single-voice verdict input**: resolved by `validate_single_voice_envelope` before aggregation.
- **Missing changelog**: resolved under `[Unreleased]`.
- **Wiring coverage**: CQ-1/CQ-2 call the production participation helper, CQ-5 pins main integration, and Spiral tests pin the consuming gate.
- **Telemetry robustness**: rejection trajectory logging now fails soft like voice-drop logging.
