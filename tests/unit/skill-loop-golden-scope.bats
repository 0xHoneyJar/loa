#!/usr/bin/env bats
# =============================================================================
# tests/unit/skill-loop-golden-scope.bats — cycle-124 FR-8 / AC-8.3
#
# The prompt audit touches no hook and no hook-emitted text, so the 32 parity
# goldens under grimoires/loa/perf/skill-loop-2026-07-05/golden/ stay
# byte-identical: capture.sh --verify recaptures every hook x payload combo
# into a temp dir and diffs it against the committed set.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    GOLDEN="$PROJECT_ROOT/grimoires/loa/perf/skill-loop-2026-07-05/golden"
}

@test "GS-1 capture.sh --verify: all 32 golden outputs match byte for byte" {
    run bash "$GOLDEN/capture.sh" --verify
    [ "$status" -eq 0 ]
    [[ "$output" == *"VERIFY OK: all 32 golden outputs match"* ]]
}

@test "GS-2 the committed checksum set lists 32 goldens and verifies" {
    [ "$(wc -l < "$GOLDEN/golden_checksums.txt")" -eq 32 ]
    [ "$(ls "$GOLDEN"/*.golden | wc -l)" -eq 32 ]
    ( cd "$GOLDEN" && sha256sum -c --quiet golden_checksums.txt )
}
