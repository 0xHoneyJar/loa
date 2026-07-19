# Bug Triage: Flatline approves schema-invalid Cursor review content

## Metadata
- **schema_version**: 1
-**bug_id**: 20260718-i1227-cf7ca4
- **classification**: contract_violation
- **severity**: high
- **eligibility_score**: 4
- **eligibility_reasoning**: GitHub issue #1227 provides executable reproduction steps, a captured raw response, a framework version, and a known-good expectation from the verdict-quality contract.
- **test_type**: contract
- **risk_level**: high
- **bead**: bd-8ya
- **created**: 2026-07-19T00:14:49Z

## Reproduction
### Steps
1. Configure Flatline with three headless voices, including `cursor-headless`.
2. Make the Cursor transport exit successfully with a clean single-voice `verdict_quality` envelope while returning prose that cannot normalize to the `flatline-reviewer` JSON contract.
3. Run the sprint-phase Flatline orchestration through Phase 1 aggregation.
4. Inspect `grimoires/loa/a2a/flatline/sprint-final_consensus.json`.

### Expected Behavior
Only responses that normalize and validate against the phase agent schema count as successful voices. The invalid Cursor response is rejected before aggregation, the planned denominator remains three, and the result is visibly degraded or failed.

### Actual Behavior
Transport success is counted before content qualification. Flatline writes `voices_succeeded: 3`, `chain_health: ok`, and `status: APPROVED`; later normalization silently substitutes an empty default.

### Environment
Downstream reproduction: `0xHoneyJar/sonar-api`, Loa v1.198.7, Cursor Agent 2026.07.16-899851b, sprint-phase review on 2026-07-18.

## Analysis
### Suspected Files
| File | Line(s) | Confidence | Reason |
|------|---------|------------|--------|
| `.claude/scripts/flatline-orchestrator.sh` | 268-303, 607-690, 2287-2297 | high | Aggregates raw transport verdict quality before normalizing or validating `.content`; normalization failure is defaulted later. |
| `.claude/adapters/loa_cheval/providers/cursor_headless_adapter.py` | 298-318, 360-420 | high | Uses planning mode for an inference contract and permits empty results as successful completions. |
| `tests/integration/flatline-content-qualified-quorum.bats` | new | high | Contract regression should exercise invalid prose against a nominally clean transport envelope. |
| `.claude/adapters/tests/test_cursor_headless_adapter.py` | 1-130 | medium | Existing command test pins `--mode plan`; it must pin the safer Q&A mode if the adapter changes. |

### Related Tests
| Test File | Coverage |
|-----------|----------|
| `tests/integration/flatline-orchestrator-voice-drop.bats` | Preserves the planned denominator when transport voices are missing. |
| `tests/unit/cycle-109-t3-3-flatline-extract-json-content.bats` | Normalization and defaulting behavior after Phase 1. |
| `.claude/adapters/tests/test_cursor_headless_adapter.py` | Cursor command construction and result parsing. |
| `.claude/adapters/tests/test_verdict_aggregate.py` | Canonical multi-voice status derivation. |

### Test Target
An exit-0 review file with valid transport metadata, clean verdict quality, and schema-invalid prose must be rejected before quorum aggregation; two valid peers plus that rejected voice must produce `voices_planned: 3`, `voices_succeeded: 2`, and a non-APPROVED status.

### Constraints
- Preserve the canonical Python verdict-quality status writer.
- Do not shrink the planned denominator when content is rejected.
- Do not weaken Cursor sandboxing, workspace isolation, or the prohibition on `--force`/`--yolo`.
- No provider substitution, production mutation, or Sonar indexing change is in scope.
- The subprocess-tree timeout defect and updater defects are separate follow-ups unless the same minimal cut fixes them.

## Fix Strategy
Qualify each Phase 1 review response by normalizing `.content` and validating it against `flatline-reviewer` before selecting verdict-quality inputs. Pass the original planned voice count separately to the canonical aggregator so rejected content becomes a degraded missing voice instead of an approved participant. Emit a trajectory event with the rejected voice label and content-failure reason. Switch Cursor from planning mode to its read-only Q&A mode so structured inference is the default while retaining sandbox, trust, isolated cwd, and no-force defenses.

### Fix Hints
Structured hints for multi-model handoff (each hint targets one file change):

| File | Action | Target | Constraint |
|------|--------|--------|------------|
| `.claude/scripts/flatline-orchestrator.sh` | validate | Phase 1 review content before verdict-quality aggregation | Keep expected voice count equal to the planned cohort and use the canonical aggregator for final status. |
| `.claude/adapters/loa_cheval/providers/cursor_headless_adapter.py` | fix | Cursor execution mode | Use read-only `ask`; retain sandbox, trust, isolated cwd, and no force flags. |
| `tests/integration/flatline-content-qualified-quorum.bats` | add | false-green content-qualified quorum regression | Hermetic; no provider calls. |
| `.claude/adapters/tests/test_cursor_headless_adapter.py` | update | command construction assertion | Pin `--mode ask` and existing safety flags. |
