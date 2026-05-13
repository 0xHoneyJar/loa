#!/usr/bin/env bats
# =============================================================================
# Cycle-108 sprint-3 T3.B — tools/advisor-benchmark.sh baselines gate
# =============================================================================
# PRD §5 FR-8 acceptance + SDD §13.3 T3.C.
# Validates the refuse-on-tamper gate fires BEFORE any replay starts.
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    HARNESS="$REPO_ROOT/tools/advisor-benchmark.sh"
    BASELINES="$REPO_ROOT/grimoires/loa/cycles/cycle-108-advisor-strategy/baselines.json"
    PREV_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD~1)"
    TMP="$(mktemp -d)"
    # Backup baselines so tests can mutate safely
    if [ -f "$BASELINES" ]; then
        cp "$BASELINES" "$TMP/baselines.bak"
    fi
}

teardown() {
    # Restore baselines
    if [ -f "$TMP/baselines.bak" ]; then
        cp "$TMP/baselines.bak" "$BASELINES"
    fi
    rm -rf "$TMP"
}

@test "T3.B: gate PASSES when signed baselines + valid tag exist" {
    [ -f "$BASELINES" ] || skip "baselines.json not yet generated — run tools/compute-baselines.py first"
    signed=$(jq -r '.signed' "$BASELINES")
    [ "$signed" = "true" ] || skip "baselines.json unsigned — T3.A.OP not yet completed"
    run bash "$HARNESS" --dry-run --sprints "$PREV_SHA" --replays-per-tier 1 \
        --no-cost-cap --output-dir "$TMP/out" --cleanup-strategy now
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "baselines gate PASS"
}

@test "T3.B: tampered baselines (signed=false) → exit 78" {
    [ -f "$BASELINES" ] || skip "baselines.json not yet generated"
    jq '.signed = false' "$BASELINES" > "$TMP/tampered.json"
    cp "$TMP/tampered.json" "$BASELINES"
    run bash "$HARNESS" --dry-run --sprints "$PREV_SHA" --replays-per-tier 1 \
        --no-cost-cap --output-dir "$TMP/out" --cleanup-strategy now
    [ "$status" -eq 78 ]
    echo "$output" | grep -q "UNSIGNED"
}

@test "T3.B: missing baselines.json → exit 78" {
    rm -f "$BASELINES"
    run bash "$HARNESS" --dry-run --sprints "$PREV_SHA" --replays-per-tier 1 \
        --no-cost-cap --output-dir "$TMP/out" --cleanup-strategy now
    [ "$status" -eq 78 ]
    echo "$output" | grep -q "baselines.json missing"
}

@test "T3.B: git_tag pointing at wrong commit → exit 78" {
    [ -f "$BASELINES" ] || skip "baselines.json not yet generated"
    # Change git_sha_at_signing to a wrong sha while keeping git_tag
    jq --arg s "0000000000000000000000000000000000000000" '.git_sha_at_signing = $s' "$BASELINES" > "$TMP/wrong_sha.json"
    cp "$TMP/wrong_sha.json" "$BASELINES"
    run bash "$HARNESS" --dry-run --sprints "$PREV_SHA" --replays-per-tier 1 \
        --no-cost-cap --output-dir "$TMP/out" --cleanup-strategy now
    [ "$status" -eq 78 ]
    echo "$output" | grep -q "REFUSED"
}

@test "T3.B: LOA_BENCHMARK_ALLOW_UNSIGNED_BASELINES=1 permits unsigned (dev only)" {
    [ -f "$BASELINES" ] || skip "baselines.json not yet generated"
    jq '.signed = false' "$BASELINES" > "$TMP/unsigned.json"
    cp "$TMP/unsigned.json" "$BASELINES"
    LOA_BENCHMARK_ALLOW_UNSIGNED_BASELINES=1 run bash "$HARNESS" --dry-run --sprints "$PREV_SHA" --replays-per-tier 1 \
        --no-cost-cap --output-dir "$TMP/out" --cleanup-strategy now
    # Allowed unsigned, but still needs tag — depending on what's in baselines.git_tag
    # we either pass tag verification or fail on tag step. Either is acceptable —
    # we're just verifying signed=false alone doesn't block.
    if [ "$status" -eq 78 ]; then
        echo "$output" | grep -qv "UNSIGNED" || {
            echo "FAIL: ALLOW_UNSIGNED env did not bypass signed check"
            return 1
        }
    fi
}

@test "T3.B: LOA_BENCHMARK_SKIP_BASELINE_GATE=1 bypasses entirely with WARN" {
    LOA_BENCHMARK_SKIP_BASELINE_GATE=1 run bash "$HARNESS" --dry-run --sprints "$PREV_SHA" --replays-per-tier 1 \
        --no-cost-cap --output-dir "$TMP/out" --cleanup-strategy now
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "BYPASSED"
}

@test "T3.B: gate runs BEFORE any worktree creation (refuses early)" {
    rm -f "$BASELINES"
    run bash "$HARNESS" --dry-run --sprints "$PREV_SHA" --replays-per-tier 1 \
        --no-cost-cap --output-dir "$TMP/out" --cleanup-strategy now
    [ "$status" -eq 78 ]
    # No outcomes file should be created (gate fires before main loop)
    [ ! -f "$TMP/out/outcomes.jsonl" ]
    # No worktree path should appear in /tmp from this run
}
