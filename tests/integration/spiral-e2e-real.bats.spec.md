# Spec: Real-Dispatch Spiral E2E Test — FR-4b (cycle-068)

**Owner**: cycle-068
**Status**: Spec only — not executable this cycle
**Gate**: `SPIRAL_REAL_DISPATCH=1` env var (default: skip)

## Prerequisites

- Real simstim dispatch wired in spiral-orchestrator.sh (cycle-068 FR-1.1)
- Canned fixture repo with valid PRD/SDD/sprint.md (or auto-generated)
- API keys for all configured Flatline providers (or single-provider degraded mode)
- `SPIRAL_REAL_DISPATCH=1` set in environment

## Test: `spiral-e2e-real.bats`

```bash
@test "real-dispatch: 1 full cycle against fixture repo" {
    skip_unless_env "SPIRAL_REAL_DISPATCH"

    # Setup: copy fixture repo into temp dir
    # Configure: max_cycles=1, simstim dispatching to fixture
    # Execute: --start --max-cycles 1
    # Assert: subprocess exit 0
    # Assert: real reviewer.md exists (not stub)
    # Assert: real auditor-sprint-feedback.md exists
    # Assert: cycle-outcome.json sidecar valid
    # Assert: state transitions valid
    # Assert: elapsed_sec > 30 (real work takes time)
}
```

## Expected Runtime / Cost

- **Runtime**: 5-15 minutes per cycle (real simstim)
- **Cost**: ~$10-20 per cycle (API calls for implement + review + audit)
- **Gate**: nightly CI or on-demand only

## Exit Criteria

- Subprocess exits 0
- Artifacts present: reviewer.md, auditor-sprint-feedback.md, cycle-outcome.json
- State transitions: SEED → SIMSTIM → HARVEST → EVALUATE → COMPLETE
- Checkpoint monotonicity preserved
- No crash diagnostic produced

## Known Unknowns (from FR-1.1)

| Unknown | Why stub can't exercise | Validated here |
|---------|------------------------|----------------|
| Subprocess exit codes for partial failures | Stub returns fixed | Yes |
| Partial stdout/stderr streaming | Stub writes deterministic | Yes |
| Real timeout behavior under load | Stub completes in ms | Yes |
| State pollution between real cycles | Stub writes isolated | Partially (1 cycle) |
| Error propagation from nested skill stack | Stub has no nesting | Yes |
