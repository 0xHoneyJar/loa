#!/usr/bin/env bats
# =============================================================================
# tests/unit/check-round-independence.bats
#
# tools/check-round-independence.sh reads the `<!-- round: N; questions: [...] -->`
# blocks that `interview.pacing: rounds` puts at the end of every round
# (discovering-requirements/resources/REFERENCE.md §Question Pacing) and fails
# when a question depends on another question of the same round, on one never
# asked earlier, when ids repeat without "reasked", or when rounds average
# fewer than --min-average new questions (final round exempt).
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    CHECK="$PROJECT_ROOT/tools/check-round-independence.sh"
    FIX="$PROJECT_ROOT/tests/fixtures/rounds"
    T="$BATS_TEST_TMPDIR/transcript.md"
}

# Write a transcript whose rounds are the given JSON arrays, in order.
transcript() {
    local n=0 arr
    : > "$T"
    for arr in "$@"; do
        n=$((n + 1))
        printf 'Round %d\n\nquestions...\n<!-- round: %d; questions: %s -->\n\n' "$n" "$n" "$arr" >> "$T"
    done
}

@test "RI-1 the independent fixture passes at the default minimum and reports per-round counts" {
    run "$CHECK" "$FIX/independent.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"round 1: 3 new question(s) [Q1 Q2 Q3]"* ]]
    [[ "$output" == *"round 3: 1 new question(s), 1 re-asked [Q6 Q7]"* ]]
    [[ "$output" == *"rounds: 4; questions: 8; average: 2.33 per round (final round exempt); min-average: 2"* ]]
    [[ "$output" == *"PASS"* ]]
}

@test "RI-2 the fixture has at least three rounds and --json carries the report fields" {
    run "$CHECK" "$FIX/independent.md" --json
    [ "$status" -eq 0 ]
    [ "$(jq -r '.rounds' <<< "$output")" -ge 3 ]
    [ "$(jq -r '.verdict' <<< "$output")" = "PASS" ]
    [ "$(jq -r '.min_average' <<< "$output")" = "2" ]
    [ "$(jq -r '.final_round_exempt' <<< "$output")" = "true" ]
    [ "$(jq -r '.violations | length' <<< "$output")" -eq 0 ]
    [ "$(jq -r '.per_round | length' <<< "$output")" -eq "$(jq -r '.rounds' <<< "$output")" ]
}

@test "RI-3 the negative fixture fails on its same-round dependency" {
    run "$CHECK" "$FIX/same-round-dependency.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"VIOLATION: round 1: Q3 depends on Q2, asked in the same round"* ]]
    [[ "$output" == *"FAIL"* ]]
}

@test "RI-4 a final one-question round does not lower the average" {
    transcript '[{"id":"Q1","depends_on":[]},{"id":"Q2","depends_on":[]}]' \
               '[{"id":"Q3","depends_on":["Q1"]},{"id":"Q4","depends_on":["Q2"]}]' \
               '[{"id":"Q5","depends_on":["Q3"]}]'
    run "$CHECK" "$T" --json
    [ "$status" -eq 0 ]
    [ "$(jq -r '.average' <<< "$output")" = "2" ]
}

@test "RI-5 a one-question round that is not the final round fails the default minimum" {
    transcript '[{"id":"Q1","depends_on":[]}]' \
               '[{"id":"Q2","depends_on":["Q1"]}]' \
               '[{"id":"Q3","depends_on":["Q2"]}]'
    run "$CHECK" "$T"
    [ "$status" -eq 1 ]
    [[ "$output" == *"below --min-average 2"* ]]
    run "$CHECK" "$T" --min-average 1
    [ "$status" -eq 0 ]
}

@test "RI-6 a single round is held to the minimum (no exemption with one round)" {
    transcript '[{"id":"Q1","depends_on":[]}]'
    run "$CHECK" "$T" --json
    [ "$status" -eq 1 ]
    [ "$(jq -r '.final_round_exempt' <<< "$output")" = "false" ]
}

@test "RI-7 reasked entries are ignored for uniqueness and the average" {
    transcript '[{"id":"Q1","depends_on":[]},{"id":"Q2","depends_on":[]}]' \
               '[{"id":"Q2","depends_on":[],"reasked":true},{"id":"Q3","depends_on":["Q1"]},{"id":"Q4","depends_on":[]}]' \
               '[{"id":"Q5","depends_on":["Q2"]}]'
    run "$CHECK" "$T" --json
    [ "$status" -eq 0 ]
    [ "$(jq -r '.questions' <<< "$output")" = "5" ]
    [ "$(jq -r '.reasked' <<< "$output")" = "1" ]
    [ "$(jq -r '.average' <<< "$output")" = "2" ]
}

@test "RI-8 a repeated id without reasked fails; reasked on a never-asked id fails" {
    transcript '[{"id":"Q1","depends_on":[]},{"id":"Q2","depends_on":[]}]' \
               '[{"id":"Q2","depends_on":[]},{"id":"Q3","depends_on":[]}]'
    run "$CHECK" "$T"
    [ "$status" -eq 1 ]
    [[ "$output" == *'Q2 is asked again without "reasked": true'* ]]
    transcript '[{"id":"Q1","depends_on":[]},{"id":"Q2","depends_on":[]}]' \
               '[{"id":"Q9","depends_on":[],"reasked":true},{"id":"Q3","depends_on":[]}]'
    run "$CHECK" "$T"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Q9 is marked reasked but was not asked in an earlier round"* ]]
}

@test "RI-9 a dependency on an unknown or later question fails" {
    transcript '[{"id":"Q1","depends_on":["Q7"]},{"id":"Q2","depends_on":[]}]' \
               '[{"id":"Q7","depends_on":[]},{"id":"Q3","depends_on":[]}]'
    run "$CHECK" "$T"
    [ "$status" -eq 1 ]
    [[ "$output" == *"round 1: Q1 depends on Q7, not asked in an earlier round"* ]]
}

@test "RI-10 a self-dependency and a non-increasing round number fail" {
    transcript '[{"id":"Q1","depends_on":["Q1"]},{"id":"Q2","depends_on":[]}]'
    run "$CHECK" "$T"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Q1 depends on itself"* ]]
    printf '%s\n' '<!-- round: 2; questions: [{"id":"Q1","depends_on":[]},{"id":"Q2","depends_on":[]}] -->' \
                  '<!-- round: 1; questions: [{"id":"Q3","depends_on":[]},{"id":"Q4","depends_on":[]}] -->' > "$T"
    run "$CHECK" "$T"
    [ "$status" -eq 1 ]
    [[ "$output" == *"round 1 does not follow round 2"* ]]
}

@test "RI-11 a malformed questions array is a violation, not a crash" {
    printf '%s\n' '<!-- round: 1; questions: [{"id":"Q1"},{"id":"Q2","depends_on":"Q1"}] -->' \
                  '<!-- round: 2; questions: [not json] -->' > "$T"
    run "$CHECK" "$T"
    [ "$status" -eq 1 ]
    [[ "$output" == *"round 1: malformed questions array"* ]]
    [[ "$output" == *"round 2: malformed questions array"* ]]
}

@test "RI-12 no round block exits 2; usage errors exit 2" {
    printf 'an interview with no round blocks\n' > "$T"
    run "$CHECK" "$T"
    [ "$status" -eq 2 ]
    [[ "$output" == *"no <!-- round: N; questions: [...] --> block"* ]]
    run "$CHECK"
    [ "$status" -eq 2 ]
    run "$CHECK" "$BATS_TEST_TMPDIR/missing.md"
    [ "$status" -eq 2 ]
    run "$CHECK" "$FIX/independent.md" --min-average two
    [ "$status" -eq 2 ]
    run "$CHECK" "$FIX/independent.md" --bogus
    [ "$status" -eq 2 ]
}

@test "RI-13 the REFERENCE.md worked example is itself a valid round" {
    local ref="$PROJECT_ROOT/.claude/skills/discovering-requirements/resources/REFERENCE.md"
    {
        printf '%s\n' '<!-- round: 1; questions: [{"id":"Q1","depends_on":[]},{"id":"Q2","depends_on":[]},{"id":"Q3","depends_on":[]}] -->'
        grep -E '^<!-- round: 2;' "$ref"
    } > "$T"
    [ "$(grep -c '^<!-- round: 2;' "$T")" -eq 1 ]
    run "$CHECK" "$T"
    [ "$status" -eq 0 ]
}
