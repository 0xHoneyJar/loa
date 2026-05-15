#!/usr/bin/env bats
# cycle-109 Sprint 5 T5.3 — closes #870.
#
# Pins both behavior + perf of the strip-attack scanner in
# tools/modelinv-rollup.sh after the O(N) → single-pass jq refactor.
# Behavior tests assert that the scanner still catches violations,
# skips seal markers, and exits with the right code under
# --strict-strip. Perf test asserts <2s wall-clock on 1000 envelopes
# (the original implementation took ~5-10s on this scale per #870's
# BB iter-6 F001 evidence).

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    ROLLUP="$PROJECT_ROOT/tools/modelinv-rollup.sh"
    TMP="$(mktemp -d -t modelinv-rollup-perf-XXXXXX)"

    [[ -x "$ROLLUP" ]] || skip "rollup script not executable"
}

teardown() {
    if [[ -d "$TMP" ]]; then
        find "$TMP" -mindepth 1 -delete
        rmdir "$TMP"
    fi
}

# Helper: write a stub envelope to $1 with ts $2 and writer_version $3
# ($3 = "" → field missing entirely; "1.2" → conforming; "1.3" → drift).
_emit_env() {
    local log="$1" ts="$2" wv="$3"
    if [[ -z "$wv" ]]; then
        printf '{"primitive_id":"MODELINV","ts_utc":"%s","payload":{"x":1}}\n' "$ts" >> "$log"
    else
        printf '{"primitive_id":"MODELINV","ts_utc":"%s","payload":{"writer_version":"%s","x":1}}\n' \
            "$ts" "$wv" >> "$log"
    fi
}

# ---------------------------------------------------------------------------
# Behavior — preserves correctness post-refactor
# ---------------------------------------------------------------------------

@test "T5.3: empty log → strip-detect is a no-op (exits 0)" {
    log="$TMP/empty.jsonl"
    : > "$log"
    run "$ROLLUP" --input "$log" --no-chain-verify
    [ "$status" -eq 0 ] || [ "$status" -eq 2 ]
    # Empty log may exit 2 ("no entries") from later aggregation — strip
    # phase itself does not flag.
    ! echo "$output" | grep -q "STRIP-ATTACK-DETECTED"
}

@test "T5.3: all conforming entries → no violation" {
    log="$TMP/conforming.jsonl"
    _emit_env "$log" "2026-05-14T10:00:00Z" "1.2"
    _emit_env "$log" "2026-05-14T11:00:00Z" "1.2"
    _emit_env "$log" "2026-05-14T12:00:00Z" "1.2"
    run "$ROLLUP" --input "$log" --no-chain-verify
    ! echo "$output" | grep -q "STRIP-ATTACK-DETECTED"
}

@test "T5.3: post-cutoff entry missing writer_version → flagged" {
    log="$TMP/violation.jsonl"
    _emit_env "$log" "2026-05-14T10:00:00Z" "1.2"  # cutoff
    _emit_env "$log" "2026-05-14T11:00:00Z" "1.2"
    _emit_env "$log" "2026-05-14T12:00:00Z" ""    # violation
    run "$ROLLUP" --input "$log" --no-chain-verify
    [ "$status" -eq 1 ]
    echo "$output$stderr" | grep -q "STRIP-ATTACK-DETECTED"
}

@test "T5.3: post-cutoff entry with wrong writer_version → flagged" {
    log="$TMP/drift.jsonl"
    _emit_env "$log" "2026-05-14T10:00:00Z" "1.2"
    _emit_env "$log" "2026-05-14T11:00:00Z" "1.3"  # drift, also post-cutoff
    run "$ROLLUP" --input "$log" --no-chain-verify
    [ "$status" -eq 1 ]
    echo "$output$stderr" | grep -q "STRIP-ATTACK-DETECTED"
}

@test "T5.3: --strict-strip elevates exit code to 78" {
    log="$TMP/strict.jsonl"
    _emit_env "$log" "2026-05-14T10:00:00Z" "1.2"
    _emit_env "$log" "2026-05-14T11:00:00Z" ""
    run "$ROLLUP" --input "$log" --no-chain-verify --strict-strip
    [ "$status" -eq 78 ]
}

@test "T5.3: seal-marker lines are skipped (no false positive)" {
    log="$TMP/seal.jsonl"
    _emit_env "$log" "2026-05-14T10:00:00Z" "1.2"
    printf '[L4-DISABLED]\n' >> "$log"
    _emit_env "$log" "2026-05-14T11:00:00Z" "1.2"
    run "$ROLLUP" --input "$log" --no-chain-verify
    ! echo "$output$stderr" | grep -q "STRIP-ATTACK-DETECTED"
}

@test "T5.3: pre-cutoff entries (before first 1.2) are not flagged" {
    log="$TMP/pre-cutoff.jsonl"
    _emit_env "$log" "2026-05-14T09:00:00Z" ""    # pre-cutoff, no wv — OK
    _emit_env "$log" "2026-05-14T10:00:00Z" "1.2"  # cutoff
    run "$ROLLUP" --input "$log" --no-chain-verify
    ! echo "$output$stderr" | grep -q "STRIP-ATTACK-DETECTED"
}

# ---------------------------------------------------------------------------
# Perf — the actual issue #870 closure
# ---------------------------------------------------------------------------

@test "T5.3: strip-detect runs in <2s on 1000-envelope log" {
    log="$TMP/perf.jsonl"
    {
        printf '{"primitive_id":"MODELINV","ts_utc":"2026-05-14T00:00:00Z","payload":{"writer_version":"1.2","i":0}}\n'
        for i in $(seq 1 1000); do
            ts=$(printf '2026-05-14T%02d:%02d:00Z' $((i / 60)) $((i % 60)))
            printf '{"primitive_id":"MODELINV","ts_utc":"%s","payload":{"writer_version":"1.2","i":%d}}\n' "$ts" "$i"
        done
    } > "$log"

    start_ns=$(date +%s%N)
    run "$ROLLUP" --input "$log" --no-chain-verify
    end_ns=$(date +%s%N)
    elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))

    echo "elapsed_ms=$elapsed_ms (1001 envelopes)" >&2
    # Acceptance criterion from issue #870: <1s on 10k; we test 1k <2s
    # to keep test wall-time bounded and CI-friendly.
    [ "$elapsed_ms" -lt 2000 ]
    ! echo "$output$stderr" | grep -q "STRIP-ATTACK-DETECTED"
}
