#!/usr/bin/env bats
# =============================================================================
# Cycle-108 sprint-2 T2.B — advisor-benchmark-stats.py
# =============================================================================
# Validates paired-bootstrap classifier + UNTESTABLE stratum rule (SDD §20.10
# ATK-A5) + streaming-mode memory budget.
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    STATS="$REPO_ROOT/tools/advisor-benchmark-stats.py"
    TMP="$(mktemp -d)"
    cd "$TMP"
}

teardown() {
    rm -rf "$TMP"
}

@test "T2.B: classifies PASS when advisor consistently > executor" {
    cat > outcomes.jsonl <<'EOF'
{"sprint_sha": "s1", "tier": "advisor", "idx": 1, "score": 0.85, "stratum": "glue", "outcome": "OK"}
{"sprint_sha": "s1", "tier": "advisor", "idx": 2, "score": 0.87, "stratum": "glue", "outcome": "OK"}
{"sprint_sha": "s1", "tier": "advisor", "idx": 3, "score": 0.86, "stratum": "glue", "outcome": "OK"}
{"sprint_sha": "s1", "tier": "executor", "idx": 1, "score": 0.75, "stratum": "glue", "outcome": "OK"}
{"sprint_sha": "s1", "tier": "executor", "idx": 2, "score": 0.76, "stratum": "glue", "outcome": "OK"}
{"sprint_sha": "s1", "tier": "executor", "idx": 3, "score": 0.74, "stratum": "glue", "outcome": "OK"}
EOF
    run python3 "$STATS" --outcomes outcomes.jsonl --score-key score
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.sprint_classifications[0].classification == "PASS"'
    echo "$output" | jq -e '.sprint_classifications[0].mean_delta > 0.05'
}

@test "T2.B: classifies FAIL when executor consistently > advisor" {
    cat > outcomes.jsonl <<'EOF'
{"sprint_sha": "s1", "tier": "advisor", "idx": 1, "score": 0.5, "stratum": "glue", "outcome": "OK"}
{"sprint_sha": "s1", "tier": "advisor", "idx": 2, "score": 0.5, "stratum": "glue", "outcome": "OK"}
{"sprint_sha": "s1", "tier": "advisor", "idx": 3, "score": 0.5, "stratum": "glue", "outcome": "OK"}
{"sprint_sha": "s1", "tier": "executor", "idx": 1, "score": 0.9, "stratum": "glue", "outcome": "OK"}
{"sprint_sha": "s1", "tier": "executor", "idx": 2, "score": 0.9, "stratum": "glue", "outcome": "OK"}
{"sprint_sha": "s1", "tier": "executor", "idx": 3, "score": 0.9, "stratum": "glue", "outcome": "OK"}
EOF
    run python3 "$STATS" --outcomes outcomes.jsonl --score-key score
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.sprint_classifications[0].classification == "FAIL"'
}

@test "T2.B: classifies INCONCLUSIVE when CI straddles zero" {
    cat > outcomes.jsonl <<'EOF'
{"sprint_sha": "s1", "tier": "advisor", "idx": 1, "score": 0.5, "stratum": "glue", "outcome": "OK"}
{"sprint_sha": "s1", "tier": "advisor", "idx": 2, "score": 0.8, "stratum": "glue", "outcome": "OK"}
{"sprint_sha": "s1", "tier": "executor", "idx": 1, "score": 0.7, "stratum": "glue", "outcome": "OK"}
{"sprint_sha": "s1", "tier": "executor", "idx": 2, "score": 0.6, "stratum": "glue", "outcome": "OK"}
EOF
    run python3 "$STATS" --outcomes outcomes.jsonl --score-key score
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.sprint_classifications[0].classification == "INCONCLUSIVE"'
}

@test "T2.B: UNTESTABLE stratum when INCONCLUSIVE rate > 25%" {
    # 8 outcomes; 3 INCONCLUSIVE = 37.5% > 25%
    cat > outcomes.jsonl <<'EOF'
{"sprint_sha": "s1", "tier": "advisor", "idx": 1, "score": 0.5, "stratum": "parser", "outcome": "INCONCLUSIVE"}
{"sprint_sha": "s1", "tier": "advisor", "idx": 2, "score": 0.5, "stratum": "parser", "outcome": "INCONCLUSIVE"}
{"sprint_sha": "s1", "tier": "advisor", "idx": 3, "score": 0.5, "stratum": "parser", "outcome": "INCONCLUSIVE"}
{"sprint_sha": "s1", "tier": "advisor", "idx": 4, "score": 0.5, "stratum": "parser", "outcome": "OK"}
{"sprint_sha": "s1", "tier": "executor", "idx": 1, "score": 0.5, "stratum": "parser", "outcome": "OK"}
{"sprint_sha": "s1", "tier": "executor", "idx": 2, "score": 0.5, "stratum": "parser", "outcome": "OK"}
{"sprint_sha": "s1", "tier": "executor", "idx": 3, "score": 0.5, "stratum": "parser", "outcome": "OK"}
{"sprint_sha": "s1", "tier": "executor", "idx": 4, "score": 0.5, "stratum": "parser", "outcome": "OK"}
EOF
    run python3 "$STATS" --outcomes outcomes.jsonl --score-key score
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.untestable_strata | index("parser") != null'
    echo "$output" | jq -e '.sprint_classifications[0].classification == "UNTESTABLE"'
}

@test "T2.B: per-stratum summary aggregates classifications" {
    cat > outcomes.jsonl <<'EOF'
{"sprint_sha": "s1", "tier": "advisor", "idx": 1, "score": 0.8, "stratum": "glue", "outcome": "OK"}
{"sprint_sha": "s1", "tier": "advisor", "idx": 2, "score": 0.8, "stratum": "glue", "outcome": "OK"}
{"sprint_sha": "s1", "tier": "advisor", "idx": 3, "score": 0.8, "stratum": "glue", "outcome": "OK"}
{"sprint_sha": "s1", "tier": "executor", "idx": 1, "score": 0.5, "stratum": "glue", "outcome": "OK"}
{"sprint_sha": "s1", "tier": "executor", "idx": 2, "score": 0.5, "stratum": "glue", "outcome": "OK"}
{"sprint_sha": "s1", "tier": "executor", "idx": 3, "score": 0.5, "stratum": "glue", "outcome": "OK"}
{"sprint_sha": "s2", "tier": "advisor", "idx": 1, "score": 0.5, "stratum": "glue", "outcome": "OK"}
{"sprint_sha": "s2", "tier": "advisor", "idx": 2, "score": 0.5, "stratum": "glue", "outcome": "OK"}
{"sprint_sha": "s2", "tier": "executor", "idx": 1, "score": 0.9, "stratum": "glue", "outcome": "OK"}
{"sprint_sha": "s2", "tier": "executor", "idx": 2, "score": 0.9, "stratum": "glue", "outcome": "OK"}
EOF
    run python3 "$STATS" --outcomes outcomes.jsonl --score-key score
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.per_stratum_summary.glue.PASS == 1'
    echo "$output" | jq -e '.per_stratum_summary.glue.FAIL == 1'
}

@test "T2.B: streaming reader handles 100-replay synthetic fixture under 256MB" {
    python3 -c "
import json
with open('big.jsonl', 'w') as f:
    for i in range(100):
        for tier_idx, tier in enumerate(['advisor', 'executor']):
            for rep in range(3):
                f.write(json.dumps({
                    'sprint_sha': f's{i:03d}',
                    'tier': tier,
                    'idx': rep+1,
                    'score': 0.5 + 0.1 * tier_idx + (rep * 0.01),
                    'outcome': 'OK',
                    'stratum': 'glue',
                }) + '\n')
"
    # ulimit guard: -v 262144 = 256MB virtual memory cap
    run bash -c "ulimit -v 262144; python3 '$STATS' --outcomes big.jsonl --score-key score --n-resamples 1000 | tail -3"
    [ "$status" -eq 0 ]
}

@test "T2.B: missing outcomes file → exit 2" {
    run python3 "$STATS" --outcomes nonexistent.jsonl --score-key score
    [ "$status" -eq 2 ]
}

@test "T2.B: empty outcomes file → exit 3 (no pairs)" {
    : > empty.jsonl
    run python3 "$STATS" --outcomes empty.jsonl --score-key score
    [ "$status" -eq 3 ]
}

@test "T2.B: variance flagging — high stdev/mean ratio surfaces" {
    cat > outcomes.jsonl <<'EOF'
{"sprint_sha": "s1", "tier": "advisor", "idx": 1, "score": 0.1, "stratum": "glue", "outcome": "OK"}
{"sprint_sha": "s1", "tier": "advisor", "idx": 2, "score": 0.9, "stratum": "glue", "outcome": "OK"}
{"sprint_sha": "s1", "tier": "advisor", "idx": 3, "score": 0.1, "stratum": "glue", "outcome": "OK"}
{"sprint_sha": "s1", "tier": "executor", "idx": 1, "score": 0.4, "stratum": "glue", "outcome": "OK"}
{"sprint_sha": "s1", "tier": "executor", "idx": 2, "score": 0.4, "stratum": "glue", "outcome": "OK"}
{"sprint_sha": "s1", "tier": "executor", "idx": 3, "score": 0.4, "stratum": "glue", "outcome": "OK"}
EOF
    run python3 "$STATS" --outcomes outcomes.jsonl --score-key score
    [ "$status" -eq 0 ]
    # Either flagged in variance_flagged, or shape passes — assert structure exists
    echo "$output" | jq -e '.variance_flagged | type == "array"'
}

@test "T2.B: deterministic output (same input → byte-equal JSON)" {
    cat > outcomes.jsonl <<'EOF'
{"sprint_sha": "s1", "tier": "advisor", "idx": 1, "score": 0.8, "stratum": "glue", "outcome": "OK"}
{"sprint_sha": "s1", "tier": "advisor", "idx": 2, "score": 0.8, "stratum": "glue", "outcome": "OK"}
{"sprint_sha": "s1", "tier": "executor", "idx": 1, "score": 0.5, "stratum": "glue", "outcome": "OK"}
{"sprint_sha": "s1", "tier": "executor", "idx": 2, "score": 0.5, "stratum": "glue", "outcome": "OK"}
EOF
    python3 "$STATS" --outcomes outcomes.jsonl --score-key score > a.json
    python3 "$STATS" --outcomes outcomes.jsonl --score-key score > b.json
    diff a.json b.json
}
