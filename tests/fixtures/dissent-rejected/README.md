# dissent-rejected — the real rejected payloads (cycle-126 Sprint 2, PRD FR-2.2, SDD D-2.2 / D-2.4)

Three findings a cross-model dissenter actually produced and `adversarial-review.sh`
silently dropped for a trivial schema mismatch (`missing-or-empty-failure_mode`,
KF-004 class), copied verbatim from the sprint-237 and sprint-247 rejected sidecars
with a `_fixture` header added. All three were judged real defects by a lead:

| Fixture | Judged | Where it lives |
|---------|--------|----------------|
| `01-guardrails-fail-open.json` | real (pre-existing, tallied MEDIUM) | bead `bd-rk9o` (P2, open): `guardrails-orchestrator.sh` passes `--mode run`, which the danger-level enforcer rejects, so run-mode input guardrails fall open |
| `02-cleanup-continues.json` | real (pre-existing, narrow) | bead `bd-mfqp` (P3, open): Phase 0.0 of `autonomous-agent` halts only on exit 3 or a partial state on the exit-0 path, so a stage-4 failure of `workspace-cleanup.sh` (originals partly removed, exit 1) is logged and the run continues on a half-cleaned grimoire |
| `03-message-redacted.json` | real, fixed | `4b289413`: `cheval.py::_calibration_needed_exit` passes the text through `sanitize_provider_error_message` before recording it as `message_redacted` or printing it. Every other `models_failed` entry is redacted again when MODELINV emits it (`loa_cheval/audit/modelinv.py`) |

They drive two tests:
- `tests/unit/adversarial-review-normalise.bats` — the normaliser derives
  `failure_mode` from the first sentence of `description` (`failure_mode_derived: true`)
  and every one becomes a finding without a repair round-trip.
- the repair-loop case in the same file — with the normaliser bypassed and a stubbed
  repair model, the repair path still recovers them.

`payload` is exactly what the model returned (after the case-fold normaliser). Add a
new fixture only from a real sidecar row, never a hand-written one.
