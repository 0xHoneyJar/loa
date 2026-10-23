# Reviewer concerns (Phase 2 seed)

Scope: 88-file registry migration opus->claude-opus-5-5 across cheval adapter, model-config.yaml, generated maps, bridgebuilder dist, tests and docs.
Concerns: generated artifacts vs source parity; checksum staleness; hard-coded model ids in tests/fixtures; residue of claude-opus-4-7; hook/gate logic changes (implement-gate.sh, hook-guard.sh); eval grader and fixture SHA256 consistency.
