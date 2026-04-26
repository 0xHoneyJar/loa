#!/usr/bin/env bats
# =============================================================================
# Tests for .claude/scripts/construct-compose.sh — cycle-006 L1 pipe runner
# Reads composition YAML from $LOA_COMPOSITIONS_DIR/<name>.yaml, sequences
# stages via construct-invoke entry/exit, validates type compatibility at
# chain build time, validates final output against the last-stage write
# schema. Exit codes: 0 ok · 1 missing/malformed · 2 type mismatch ·
# 3 stage exec fail · 4 final-output schema fail.
# =============================================================================

setup_file() {
    # Bridgebuilder F-001: emit a clear "skipped: <tool> missing" signal when
    # external tooling is unavailable, instead of red failures that look like
    # real regressions. construct-compose.sh requires both yq and jq.
    command -v yq >/dev/null 2>&1 || skip "yq required (the script under test depends on it)"
    command -v jq >/dev/null 2>&1 || skip "jq required (the script under test depends on it)"
}

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/.claude/scripts/construct-compose.sh"

    # Hermetic per-test compositions dir + trajectory
    export LOA_COMPOSITIONS_DIR="$BATS_TEST_TMPDIR/compositions"
    mkdir -p "$LOA_COMPOSITIONS_DIR"
    export LOA_TRAJECTORY_FILE="$BATS_TEST_TMPDIR/construct-trajectory.jsonl"
    export LOA_FEEDBACK_FILE="$BATS_TEST_TMPDIR/feedback-v3.jsonl"
    # Force a known PROJECT_ROOT so bare-script defaults resolve under our temp.
    # (The script also accepts overrides, but PROJECT_ROOT lookup is the
    # cleanest hermetic seam.)
    export PROJECT_ROOT
    export TMPDIR="$BATS_TEST_TMPDIR"
}

write_composition() {
    local name="$1"
    local body="$2"
    printf '%s' "$body" > "$LOA_COMPOSITIONS_DIR/$name.yaml"
}

# A simple type-compatible composition: stage 1 reads Artifact (provided as
# composition input), writes Signal; stage 2 reads Signal, writes Verdict.
COMPAT_BODY='inputs:
  - type: Artifact
chain:
  - stage: scan
    construct: observer
    skill: observing-things
    reads:
      - Artifact
    writes:
      - Signal
  - stage: judge
    construct: arbiter
    skill: judging-things
    reads:
      - Signal
    writes:
      - Verdict
'

# Type-incompatible composition: stage 1 reads Verdict but no upstream
# produces it (inputs only carry Artifact).
INCOMPAT_BODY='inputs:
  - type: Artifact
chain:
  - stage: judge
    construct: arbiter
    skill: judging-things
    reads:
      - Verdict
    writes:
      - Verdict
'

EMPTY_CHAIN_BODY='inputs:
  - type: Artifact
chain: []
'

# -----------------------------------------------------------------------------
# Help / arg validation
# -----------------------------------------------------------------------------
@test "construct-compose: --help exits 0" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"composition-name"* || "$output" == *"construct-compose"* ]]
}

@test "construct-compose: missing composition name -> exit 1" {
    run "$SCRIPT"
    [ "$status" -eq 1 ]
}

@test "construct-compose: unknown flag -> exit 1" {
    run "$SCRIPT" --bogus some-comp
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown flag"* ]]
}

# -----------------------------------------------------------------------------
# Composition load
# -----------------------------------------------------------------------------
@test "construct-compose: composition file not found -> exit 1" {
    run "$SCRIPT" --compositions-dir "$LOA_COMPOSITIONS_DIR" no-such-comp
    [ "$status" -eq 1 ]
    [[ "$output" == *"composition not found"* ]]
}

@test "construct-compose: malformed composition YAML -> exit 1" {
    write_composition broken 'this :: is not valid yaml :: ['
    run "$SCRIPT" --compositions-dir "$LOA_COMPOSITIONS_DIR" broken
    [ "$status" -eq 1 ]
}

@test "construct-compose: empty chain -> exit 1" {
    write_composition empty "$EMPTY_CHAIN_BODY"
    run "$SCRIPT" --compositions-dir "$LOA_COMPOSITIONS_DIR" empty
    [ "$status" -eq 1 ]
    [[ "$output" == *"empty chain"* ]]
}

# -----------------------------------------------------------------------------
# Type compatibility at chain build time
# -----------------------------------------------------------------------------
@test "construct-compose: type-compatible chain --dry-run exits 0 with plan" {
    write_composition compat "$COMPAT_BODY"
    run "$SCRIPT" --compositions-dir "$LOA_COMPOSITIONS_DIR" --dry-run compat
    [ "$status" -eq 0 ]
    [[ "$output" == *"dry-run OK"* ]]
    [[ "$output" == *"stage scan"* ]]
    [[ "$output" == *"stage judge"* ]]
}

@test "construct-compose: type-mismatch chain --dry-run -> exit 2" {
    write_composition incompat "$INCOMPAT_BODY"
    run "$SCRIPT" --compositions-dir "$LOA_COMPOSITIONS_DIR" --dry-run incompat
    [ "$status" -eq 2 ]
    [[ "$output" == *"type mismatch"* ]]
    [[ "$output" == *"Verdict"* ]]
}

@test "construct-compose: type-mismatch chain (live run) also exits 2" {
    write_composition incompat "$INCOMPAT_BODY"
    run "$SCRIPT" --compositions-dir "$LOA_COMPOSITIONS_DIR" incompat
    [ "$status" -eq 2 ]
    [[ "$output" == *"type mismatch"* ]]
}

# -----------------------------------------------------------------------------
# Run-id and read-mode wiring
# -----------------------------------------------------------------------------
@test "construct-compose: --run-id is honored in dry-run plan" {
    write_composition compat "$COMPAT_BODY"
    run "$SCRIPT" --compositions-dir "$LOA_COMPOSITIONS_DIR" \
        --dry-run --run-id "fixed-run-1234" compat
    [ "$status" -eq 0 ]
    [[ "$output" == *"run_id=fixed-run-1234"* ]]
}

@test "construct-compose: composition with single Verdict-writing stage -> exit 0 final-validates" {
    # Stage 1 reads Artifact, writes Verdict. The default executor stub will
    # produce a Verdict-shaped row that satisfies stream-validate.
    local body='inputs:
  - type: Artifact
chain:
  - stage: judge
    construct: arbiter
    skill: judging-things
    reads:
      - Artifact
    writes:
      - Verdict
'
    write_composition single "$body"
    # Capture stdout-only (compose prints final JSON to stdout, summary to stderr)
    # F-003: use $BATS_TEST_TMPDIR rather than /tmp/x — the latter assumes a
    # writable shared /tmp which fails on read-only-root containers.
    local stdout
    stdout=$("$SCRIPT" --compositions-dir "$LOA_COMPOSITIONS_DIR" \
        --target "$BATS_TEST_TMPDIR/target" --run-id test-single single 2>/dev/null)
    local rc=$?
    [ "$rc" -eq 0 ]
    # Compose pretty-prints the final payload across multiple lines; parse the
    # whole stdout as one JSON object and assert the Verdict declaration.
    echo "$stdout" | jq -e '.stream_type == "Verdict"' >/dev/null
}

@test "construct-compose: --orient summary prints per-stage durations" {
    local body='inputs:
  - type: Artifact
chain:
  - stage: judge
    construct: arbiter
    skill: judging-things
    reads:
      - Artifact
    writes:
      - Verdict
'
    write_composition single "$body"
    run "$SCRIPT" --compositions-dir "$LOA_COMPOSITIONS_DIR" --orient single
    [ "$status" -eq 0 ]
    [[ "$output" == *"stage judge:arbiter/judging-things"* ]]
    [[ "$output" == *"final writes: Verdict"* ]]
}
