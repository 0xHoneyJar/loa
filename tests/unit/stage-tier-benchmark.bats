#!/usr/bin/env bats
# =============================================================================
# tests/unit/stage-tier-benchmark.bats — cycle-116 D3 (bd-c116-d3-tiering)
# =============================================================================
# Arg-validation / dry-run / cost-cap tests for tools/stage-tier-benchmark.sh,
# the single-call A/B sibling of tools/advisor-benchmark.sh. No live API calls:
# dry-run mode + an env-injected historical-medians fixture keep every test
# hermetic. Mirrors tests/integration/advisor-benchmark-hermeticity.bats shape.
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    HARNESS="$REPO_ROOT/tools/stage-tier-benchmark.sh"
    TMP="$(mktemp -d)"
    OUTDIR="$TMP/stage-tier-manifests"
}

teardown() {
    rm -rf "$TMP"
}

@test "arg: --help prints usage and exits 0" {
    run bash "$HARNESS" --help
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "stage-tier-benchmark.sh"
}

@test "arg: missing --agent exits 2" {
    run bash "$HARNESS" --dry-run
    [ "$status" -eq 2 ]
    echo "$output" | grep -q "\-\-agent is required"
}

@test "arg: unknown flag exits 2" {
    run bash "$HARNESS" --dry-run --agent x --bogus-flag
    [ "$status" -eq 2 ]
    echo "$output" | grep -q "unknown argument"
}

@test "arg: invalid --tiers entry exits 2" {
    run bash "$HARNESS" --dry-run --agent x --tiers advisor,bogus
    [ "$status" -eq 2 ]
    echo "$output" | grep -q "advisor|executor"
}

@test "arg: non-integer --trials-per-tier exits 2" {
    run bash "$HARNESS" --dry-run --agent x --trials-per-tier abc
    [ "$status" -eq 2 ]
    echo "$output" | grep -q "positive integer"
}

@test "arg: live run without --prompt-file exits 2" {
    run bash "$HARNESS" --agent x --no-cost-cap --output-dir "$OUTDIR"
    [ "$status" -eq 2 ]
    echo "$output" | grep -q "\-\-prompt-file is required"
}

@test "dry-run: emits (tiers × trials) JSONL records" {
    run bash "$HARNESS" --dry-run --agent flatline-scorer \
        --trials-per-tier 3 --output-dir "$OUTDIR"
    [ "$status" -eq 0 ]
    [ -f "$OUTDIR/outcomes.jsonl" ]
    # 2 tiers (advisor,executor default) × 3 trials = 6 one-line records
    test "$(wc -l < "$OUTDIR/outcomes.jsonl")" -eq 6
}

@test "dry-run: each record has the advisor-benchmark-stats.py shape" {
    run bash "$HARNESS" --dry-run --agent flatline-scorer \
        --trials-per-tier 1 --output-dir "$OUTDIR"
    [ "$status" -eq 0 ]
    # Every line is valid JSON carrying all six required keys.
    while IFS= read -r line; do
        echo "$line" | jq -e 'has("sprint_sha") and has("tier") and has("idx") and has("score") and has("outcome") and has("stratum")'
    done < "$OUTDIR/outcomes.jsonl"
}

@test "dry-run: single-tier --tiers advisor emits only advisor records" {
    run bash "$HARNESS" --dry-run --agent flatline-scorer \
        --tiers advisor --trials-per-tier 2 --output-dir "$OUTDIR"
    [ "$status" -eq 0 ]
    test "$(wc -l < "$OUTDIR/outcomes.jsonl")" -eq 2
    run jq -rs 'map(.tier) | unique | join(",")' "$OUTDIR/outcomes.jsonl"
    [ "$output" = "advisor" ]
}

@test "cost-cap: estimate over cap aborts with exit 78" {
    echo '{"median_input_tokens":50000,"median_output_tokens":20000,"median_input_per_mtok":10000000,"median_output_per_mtok":30000000}' > "$TMP/med.json"
    LOA_HISTORICAL_MEDIANS_PATH="$TMP/med.json" run bash "$HARNESS" \
        --agent flatline-scorer --prompt-file "$TMP/med.json" \
        --cost-cap-usd 0.01 --trials-per-tier 5 --output-dir "$OUTDIR"
    [ "$status" -eq 78 ]
    echo "$output" | grep -q "ABORT: estimate"
}

@test "cost-cap: --no-cost-cap skips the pre-estimate" {
    echo '{"median_input_tokens":50000,"median_output_tokens":20000,"median_input_per_mtok":10000000,"median_output_per_mtok":30000000}' > "$TMP/med.json"
    # Even with an over-cap fixture, --no-cost-cap must not abort (dry-run so no calls).
    LOA_HISTORICAL_MEDIANS_PATH="$TMP/med.json" run bash "$HARNESS" \
        --dry-run --agent flatline-scorer --no-cost-cap \
        --cost-cap-usd 0.01 --trials-per-tier 2 --output-dir "$OUTDIR"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "cost-cap pre-estimate disabled"
}

@test "cost-cap: missing medians file discloses coverage gap, does not abort" {
    LOA_HISTORICAL_MEDIANS_PATH="$TMP/does-not-exist.json" run bash "$HARNESS" \
        --dry-run --agent flatline-scorer --trials-per-tier 1 --output-dir "$OUTDIR"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "cost pre-estimate unavailable"
}
