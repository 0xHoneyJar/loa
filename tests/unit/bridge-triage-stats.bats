#!/usr/bin/env bats
# =============================================================================
# bridge-triage-stats.bats — cycle-059 regression tests (closes #467 tooling)
# =============================================================================

setup() {
    TEST_TMPDIR=$(mktemp -d)
    export TEST_TMPDIR
    SCRIPT="$BATS_TEST_DIRNAME/../../.claude/scripts/bridge-triage-stats.sh"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# Helper: write a JSONL file with given entries (args: path, entry1, entry2, ...)
write_jsonl() {
    local path="$1"; shift
    : > "$path"
    for entry in "$@"; do
        printf '%s\n' "$entry" >> "$path"
    done
}

# Helper: standard set of decision entries
write_standard_fixture() {
    local path="$1"
    write_jsonl "$path" \
        '{"timestamp":"2026-04-13T05:00:00Z","pr_number":100,"finding_id":"F1","severity":"HIGH","action":"fix","reasoning":"reasoning text here"}' \
        '{"timestamp":"2026-04-13T05:01:00Z","pr_number":100,"finding_id":"F2","severity":"MEDIUM","action":"defer","reasoning":"reasoning text here"}' \
        '{"timestamp":"2026-04-13T05:02:00Z","pr_number":100,"finding_id":"F3","severity":"LOW","action":"log_only","reasoning":"reasoning text here"}' \
        '{"timestamp":"2026-04-13T05:03:00Z","pr_number":100,"finding_id":"F4","severity":"PRAISE","action":"lore_candidate","reasoning":"reasoning text here"}' \
        '{"timestamp":"2026-04-13T06:00:00Z","pr_number":469,"finding_id":"F1","severity":"HIGH","action":"dispute","reasoning":"reasoning text here"}' \
        '{"timestamp":"2026-04-13T06:01:00Z","pr_number":469,"finding_id":"F2","severity":"MEDIUM","action":"fix","reasoning":"reasoning text here"}' \
        '{"timestamp":"2026-04-13T06:02:00Z","pr_number":469,"finding_id":"F3","severity":"LOW","action":"noise","reasoning":"reasoning text here"}'
}

# T1: happy path — default glob with valid entries yields expected counts
@test "bridge-triage-stats: happy path produces expected counts" {
    write_standard_fixture "$TEST_TMPDIR/bridge-triage-2026-04-13.jsonl"
    run "$SCRIPT" "$TEST_TMPDIR/bridge-triage-*.jsonl"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Total decisions**: 7"* ]]
    [[ "$output" == *"PRs**: 2"* ]]
    [[ "$output" == *"| 100 | 4 |"* ]]
    [[ "$output" == *"| 469 | 3 |"* ]]
}

# T2: empty glob exits 0 with a warning on stderr
@test "bridge-triage-stats: empty glob exits 0 with stderr warning" {
    run "$SCRIPT" "$TEST_TMPDIR/no-such-pattern-*.jsonl"
    [ "$status" -eq 0 ]
    # stderr was merged into $output by BATS
    [[ "$output" == *"no trajectory files matched"* ]]
}

# T3: malformed/pretty-printed lines skipped with INFO on stderr, valid entries still counted
@test "bridge-triage-stats: pretty-printed lines parse via jq stream mode" {
    # Write a pretty-printed JSON value (multi-line) alongside JSONL
    cat > "$TEST_TMPDIR/bridge-triage-2026-04-13.jsonl" <<'EOF'
{"timestamp":"2026-04-13T05:00:00Z","pr_number":100,"finding_id":"F1","severity":"HIGH","action":"fix","reasoning":"rsn"}
{
  "timestamp": "2026-04-13T05:01:00Z",
  "pr_number": 200,
  "finding_id": "F2",
  "severity": "MEDIUM",
  "action": "defer",
  "reasoning": "rsn"
}
EOF
    run "$SCRIPT" "$TEST_TMPDIR/bridge-triage-*.jsonl"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Total decisions**: 2"* ]]
    [[ "$output" == *"| 100 | 1 |"* ]]
    [[ "$output" == *"| 200 | 1 |"* ]]
}

# T4: --pr filter restricts to a single PR
@test "bridge-triage-stats: --pr N filters to that PR only" {
    write_standard_fixture "$TEST_TMPDIR/bridge-triage-2026-04-13.jsonl"
    run "$SCRIPT" --pr 469 "$TEST_TMPDIR/bridge-triage-*.jsonl"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Total decisions**: 3"* ]]
    [[ "$output" == *"| 469 | 3 |"* ]]
    [[ "$output" != *"| 100 |"* ]]
}

# T5: --since filter restricts by timestamp date
@test "bridge-triage-stats: --since YYYY-MM-DD filters by date" {
    cat > "$TEST_TMPDIR/bridge-triage-2026-04-13.jsonl" <<'EOF'
{"timestamp":"2026-04-12T23:59:59Z","pr_number":100,"finding_id":"F1","severity":"HIGH","action":"fix","reasoning":"old"}
{"timestamp":"2026-04-13T00:00:00Z","pr_number":200,"finding_id":"F1","severity":"HIGH","action":"fix","reasoning":"new"}
{"timestamp":"2026-04-14T12:00:00Z","pr_number":300,"finding_id":"F1","severity":"LOW","action":"defer","reasoning":"newer"}
EOF
    run "$SCRIPT" --since 2026-04-13 "$TEST_TMPDIR/bridge-triage-*.jsonl"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Total decisions**: 2"* ]]
    [[ "$output" != *"| 100 |"* ]]
    [[ "$output" == *"| 200 |"* ]]
    [[ "$output" == *"| 300 |"* ]]
}

# T6: --json produces valid JSON with expected top-level keys
@test "bridge-triage-stats: --json produces valid JSON with required keys" {
    write_standard_fixture "$TEST_TMPDIR/bridge-triage-2026-04-13.jsonl"
    run bash -c "'$SCRIPT' --json '$TEST_TMPDIR/bridge-triage-*.jsonl' 2>/dev/null"
    [ "$status" -eq 0 ]
    # Pipe to jq and verify required keys present
    for key in total_decisions prs severities actions fp_proxy generated_at input_files filters_applied; do
        echo "$output" | jq -e ". | has(\"$key\")" >/dev/null
    done
    # Verify FP rate arithmetic: disputes=1, defers=1, noise=1, total=7 → rate = 3/7 ≈ 0.4286
    rate=$(echo "$output" | jq -r '.fp_proxy.rate')
    [[ "$rate" == "0.42857142857142855" ]] || [[ "$rate" == "0.42857142857142857" ]]
}

# T7: --help exits 0 with usage text
@test "bridge-triage-stats: --help prints usage and exits 0" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"--json"* ]]
    [[ "$output" == *"--pr N"* ]]
    [[ "$output" == *"--since"* ]]
    [[ "$output" == *"--comment-issue"* ]]
}

# T8: FP rate arithmetic — explicit check with crafted fixture
@test "bridge-triage-stats: FP rate computed correctly" {
    # 5 disputes + 10 defers + 2 noise = 17 out of 100 → 0.17
    : > "$TEST_TMPDIR/bridge-triage-2026-04-13.jsonl"
    for i in $(seq 1 100); do
        action="fix"
        if [ $i -le 5 ]; then action="dispute"
        elif [ $i -le 15 ]; then action="defer"
        elif [ $i -le 17 ]; then action="noise"
        fi
        printf '{"timestamp":"2026-04-13T05:00:00Z","pr_number":100,"finding_id":"F%d","severity":"LOW","action":"%s","reasoning":"rsn"}\n' "$i" "$action" >> "$TEST_TMPDIR/bridge-triage-2026-04-13.jsonl"
    done
    run bash -c "'$SCRIPT' --json '$TEST_TMPDIR/bridge-triage-*.jsonl' 2>/dev/null"
    [ "$status" -eq 0 ]
    rate=$(echo "$output" | jq -r '.fp_proxy.rate')
    [ "$rate" = "0.17" ]
}

# T9: Multi-file glob concatenates correctly
@test "bridge-triage-stats: multi-file glob aggregates across files" {
    write_jsonl "$TEST_TMPDIR/bridge-triage-2026-04-12.jsonl" \
        '{"timestamp":"2026-04-12T05:00:00Z","pr_number":100,"finding_id":"F1","severity":"HIGH","action":"fix","reasoning":"rsn"}'
    write_jsonl "$TEST_TMPDIR/bridge-triage-2026-04-13.jsonl" \
        '{"timestamp":"2026-04-13T05:00:00Z","pr_number":200,"finding_id":"F1","severity":"LOW","action":"defer","reasoning":"rsn"}'
    run "$SCRIPT" "$TEST_TMPDIR/bridge-triage-*.jsonl"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Total decisions**: 2"* ]]
    [[ "$output" == *"| 100 |"* ]]
    [[ "$output" == *"| 200 |"* ]]
}

# T10: Unknown flag exits 2 with error
@test "bridge-triage-stats: unknown flag exits 2" {
    run "$SCRIPT" --bogus-flag
    [ "$status" -eq 2 ]
    [[ "$output" == *"Unknown flag"* ]]
}

# T11: --pr with non-numeric input exits 2
@test "bridge-triage-stats: --pr with non-numeric input exits 2" {
    run "$SCRIPT" --pr abc
    [ "$status" -eq 2 ]
    [[ "$output" == *"must be a positive integer"* ]]
}

# T12: --since with invalid format exits 2
@test "bridge-triage-stats: --since with invalid date format exits 2" {
    run "$SCRIPT" --since "April 13"
    [ "$status" -eq 2 ]
    [[ "$output" == *"must be YYYY-MM-DD"* ]]
}

# T13: --comment-issue without number exits 2
@test "bridge-triage-stats: --comment-issue with non-numeric input exits 2" {
    run "$SCRIPT" --comment-issue xyz
    [ "$status" -eq 2 ]
    [[ "$output" == *"must be a positive integer"* ]]
}

# T14: GH_BIN override works for testing (mock gh)
@test "bridge-triage-stats: --comment-issue uses GH_BIN for gh invocation" {
    write_standard_fixture "$TEST_TMPDIR/bridge-triage-2026-04-13.jsonl"
    # Create a mock gh that records its invocation
    mock_gh="$TEST_TMPDIR/mock-gh"
    cat > "$mock_gh" <<'EOF'
#!/usr/bin/env bash
echo "MOCK_GH_CALLED with: $*" > "$TEST_TMPDIR/mock-gh-call.txt"
cat > "$TEST_TMPDIR/mock-gh-body.txt"
EOF
    chmod +x "$mock_gh"
    # Propagate TEST_TMPDIR through run's subshell
    GH_BIN="$mock_gh" TEST_TMPDIR="$TEST_TMPDIR" run env GH_BIN="$mock_gh" TEST_TMPDIR="$TEST_TMPDIR" \
        "$SCRIPT" --comment-issue 467 "$TEST_TMPDIR/bridge-triage-*.jsonl"
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMPDIR/mock-gh-call.txt" ]
    grep -q "issue comment 467" "$TEST_TMPDIR/mock-gh-call.txt"
    # Body must contain markdown tables
    grep -q "Bridge Triage Stats" "$TEST_TMPDIR/mock-gh-body.txt"
}
