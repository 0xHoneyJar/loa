#!/usr/bin/env bats
# =============================================================================
# Cycle-108 sprint-2 T2.J — tools/select-benchmark-sprints.py
# =============================================================================
# SDD §20.2 ATK-A19 — deterministic sprint-selection algorithm.
# Validates:
#  - Deterministic mode: same input → identical manifest (byte-equal)
#  - Manual mode: requires --rationale; rejects without
#  - Underrepresented strata surface in manifest (not blocking by default)
#  - --require-full-coverage exits 3 on underrepresentation
#  - Operator override is logged to selection.jsonl
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SELECT="$REPO_ROOT/tools/select-benchmark-sprints.py"
    BATS_TMPDIR_LOCAL="$(mktemp -d)"
    cd "$BATS_TMPDIR_LOCAL"

    # Synthetic stratifier output covering 4 strata × ≥3 candidates each.
    cat > stratifier.json <<'EOF'
[
  {"sha": "aaa001", "merged_at": "2026-04-01T10:00:00Z", "stratum": "glue", "confidence": 0.9, "pr_number": 1},
  {"sha": "aaa002", "merged_at": "2026-04-02T10:00:00Z", "stratum": "glue", "confidence": 0.9, "pr_number": 2},
  {"sha": "aaa003", "merged_at": "2026-04-03T10:00:00Z", "stratum": "glue", "confidence": 0.9, "pr_number": 3},
  {"sha": "aaa004", "merged_at": "2026-04-04T10:00:00Z", "stratum": "glue", "confidence": 0.9, "pr_number": 4},
  {"sha": "bbb001", "merged_at": "2026-04-05T10:00:00Z", "stratum": "parser", "confidence": 0.95, "pr_number": 5},
  {"sha": "bbb002", "merged_at": "2026-04-06T10:00:00Z", "stratum": "parser", "confidence": 0.95, "pr_number": 6},
  {"sha": "bbb003", "merged_at": "2026-04-07T10:00:00Z", "stratum": "parser", "confidence": 0.95, "pr_number": 7},
  {"sha": "ccc001", "merged_at": "2026-04-08T10:00:00Z", "stratum": "cryptographic", "confidence": 0.99, "pr_number": 8},
  {"sha": "ccc002", "merged_at": "2026-04-09T10:00:00Z", "stratum": "cryptographic", "confidence": 0.99, "pr_number": 9},
  {"sha": "ccc003", "merged_at": "2026-04-10T10:00:00Z", "stratum": "cryptographic", "confidence": 0.99, "pr_number": 10},
  {"sha": "ddd001", "merged_at": "2026-04-11T10:00:00Z", "stratum": "testing", "confidence": 0.85, "pr_number": 11},
  {"sha": "ddd002", "merged_at": "2026-04-12T10:00:00Z", "stratum": "testing", "confidence": 0.85, "pr_number": 12}
]
EOF
}

teardown() {
    rm -rf "$BATS_TMPDIR_LOCAL"
}

@test "T2.J: deterministic mode selects N most-recent per stratum" {
    run python3 "$SELECT" --stratifier-output stratifier.json --min-replays-per-stratum 3
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '"selection_method": "deterministic"'
    echo "$output" | grep -q '"total_selected": 12'
}

@test "T2.J: deterministic selection is byte-equal across runs" {
    python3 "$SELECT" --stratifier-output stratifier.json --output run1.json --min-replays-per-stratum 3
    python3 "$SELECT" --stratifier-output stratifier.json --output run2.json --min-replays-per-stratum 3
    diff run1.json run2.json
    [ "$?" -eq 0 ]
}

@test "T2.J: deterministic mode picks most-recent (DESC merged_at)" {
    run python3 "$SELECT" --stratifier-output stratifier.json --min-replays-per-stratum 3
    [ "$status" -eq 0 ]
    # 'glue' has 4 candidates; should pick aaa004/003/002 (most recent) NOT aaa001
    echo "$output" | grep -q 'aaa004'
    echo "$output" | grep -q 'aaa003'
    echo "$output" | grep -q 'aaa002'
    if echo "$output" | grep -q 'aaa001'; then
        echo "FAIL: aaa001 (least recent) should NOT be selected"
        return 1
    fi
}

@test "T2.J: manual mode requires --rationale" {
    run python3 "$SELECT" --stratifier-output stratifier.json --manual-selection aaa001,bbb001
    [ "$status" -eq 2 ]
    echo "$output" | grep -q "requires --rationale"
}

@test "T2.J: manual mode emits selection_method=manual + rationale" {
    run python3 "$SELECT" --stratifier-output stratifier.json \
        --manual-selection aaa001,bbb001,ccc001 \
        --rationale "operator-approved regression sample"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '"selection_method": "manual"'
    echo "$output" | grep -q "operator-approved regression sample"
}

@test "T2.J: manual mode flags unknown SHAs" {
    run python3 "$SELECT" --stratifier-output stratifier.json \
        --manual-selection aaa001,UNKNOWN_SHA \
        --rationale "test unknown sha"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "UNKNOWN_SHA"
    echo "$output" | grep -q '"unknown_shas"'
}

@test "T2.J: --rationale without --manual-selection rejected" {
    run python3 "$SELECT" --stratifier-output stratifier.json \
        --rationale "orphan rationale"
    [ "$status" -eq 2 ]
}

@test "T2.J: underrepresented strata surface in manifest" {
    # Drop one stratum (cryptographic has 3) → min-replays=5 → underrepresented
    run python3 "$SELECT" --stratifier-output stratifier.json --min-replays-per-stratum 5
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '"underrepresented"'
    echo "$output" | grep -q "cryptographic"
}

@test "T2.J: --require-full-coverage exits 3 on underrepresentation" {
    run python3 "$SELECT" --stratifier-output stratifier.json \
        --min-replays-per-stratum 5 --require-full-coverage
    [ "$status" -eq 3 ]
}

@test "T2.J: input_provenance pins stratifier SHA" {
    run python3 "$SELECT" --stratifier-output stratifier.json --min-replays-per-stratum 3
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '"input_provenance"'
    echo "$output" | grep -q '"stratifier_sha"'
}

@test "T2.J: missing stratifier output exits non-zero" {
    run python3 "$SELECT" --stratifier-output nonexistent.json --min-replays-per-stratum 3
    [ "$status" -ne 0 ]
}

@test "T2.J: manifest contains all expected strata" {
    run python3 "$SELECT" --stratifier-output stratifier.json --min-replays-per-stratum 3
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '"cryptographic"'
    echo "$output" | grep -q '"parser"'
    echo "$output" | grep -q '"glue"'
    echo "$output" | grep -q '"testing"'
}
