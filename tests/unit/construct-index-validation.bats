#!/usr/bin/env bats
# JQ-R3: exercise the actual validator and its --validate caller offline.

setup() {
    bats_require_minimum_version 1.5.0
    REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRIPT="$REPO/.claude/scripts/construct-index-gen.sh"
    FIXTURES="$REPO/tests/fixtures/construct-index-validation"
    export PROJECT_ROOT="$BATS_TEST_TMPDIR/project"
    export LOA_PACKS_DIR="$PROJECT_ROOT/packs"
    export LOA_SKILLS_DIR="$PROJECT_ROOT/skills"
    export REAL_JQ="$(command -v jq)"
    INDEX="$PROJECT_ROOT/index.json"
    mkdir -p "$LOA_PACKS_DIR/demo" "$LOA_SKILLS_DIR"
    cat > "$LOA_PACKS_DIR/demo/manifest.json" <<'JSON'
{"slug":"demo","name":"Demo","version":"1.0.0","skills":[],"commands":[]}
JSON
    cat > "$INDEX" <<'JSON'
{"metadata":{"generated_at":"fixture"},"constructs":[{"slug":"demo","name":"Demo","version":"1.0.0","skills":[],"commands":[]}]}
JSON
}

validate_literal() {
    # Source the real file with no CLI arguments; do not copy/reimplement its
    # function. Checking the return explicitly also tests callers without errexit.
    run --separate-stderr bash -c '
        script="$1" index="$2" quiet="$3"
        set --
        source "$script"
        QUIET="$quiet"
        if validate_index "$index"; then exit 0; else exit $?; fi
    ' _ "$SCRIPT" "$INDEX" "${1:-false}"
}

generate_and_validate() {
    run --separate-stderr bash "$SCRIPT" --json --validate --output "$INDEX" "$@"
}

assert_rejected() {
    printf 'exit=%s\nstdout=%s\nstderr=%s\n' "$status" "$output" "$stderr"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"VALIDATE ERROR:"* ]]
    [[ "$output" != *"all valid"* ]]
}

inject_jq_read() {
    export JQ_FAULT_FIELD="$1" JQ_FAULT_STATUS="$2" JQ_FAULT_OUTPUT="$3"
    export JQ_FAULT_HIT="$PROJECT_ROOT/jq-fault-hit"
    mkdir -p "$PROJECT_ROOT/bin"
    cat > "$PROJECT_ROOT/bin/jq" <<'SH'
#!/usr/bin/env bash
for arg in "$@"; do
    field=""
    case "$arg" in
        '.constructs | '*) field=count ;;
        '.constructs[0].skills | type') field=skills ;;
        '.constructs[0].commands | type') field=commands ;;
    esac
    if [[ -n "$field" && "$field" == "$JQ_FAULT_FIELD" ]]; then
        printf '%s' "$field" > "$JQ_FAULT_HIT"
        printf '%s' "$JQ_FAULT_OUTPUT"
        if [[ "$JQ_FAULT_STATUS" -ne 0 ]]; then
            printf 'fixture jq read failed: %s\n' "$field" >&2
        fi
        exit "$JQ_FAULT_STATUS"
    fi
done
exec "$REAL_JQ" "$@"
SH
    chmod +x "$PROJECT_ROOT/bin/jq"
    export PATH="$PROJECT_ROOT/bin:$PATH"
}

@test "JQ-R3: retained boolean count failure cannot report all valid" {
    cp "$FIXTURES/jq-count-error-index.json" "$INDEX"
    validate_literal
    assert_rejected
    [[ "$stderr" == *"constructs"* ]]
}

@test "JQ-R3: only an actual constructs array can supply a count" {
    local value
    for value in false null 0 '""' '{}'; do
        "$REAL_JQ" -n --argjson value "$value" \
            '{metadata:{generated_at:"fixture"},constructs:$value}' > "$INDEX"
        validate_literal
        assert_rejected
        [[ "$stderr" == *"constructs"* ]]
    done
    printf '%s\n' '{"metadata":{"generated_at":"fixture"}}' > "$INDEX"
    validate_literal
    assert_rejected
}

@test "JQ-R3: retained actual empty array remains a valid zero count" {
    cp "$FIXTURES/valid-empty-index.json" "$INDEX"
    validate_literal
    [ "$status" -eq 0 ]
    [ "$output" = "VALIDATE: 0 constructs checked, all valid" ]
    [ -z "$stderr" ]
}

@test "JQ-R3: normal entries and optional absent or null arrays remain valid" {
    "$REAL_JQ" '.constructs += [
        {slug:"absent",name:"Absent",version:"1.0.0"},
        {slug:"nulls",name:"Nulls",version:"1.0.0",skills:null,commands:null}
    ]' "$INDEX" > "$PROJECT_ROOT/normal.json"
    mv "$PROJECT_ROOT/normal.json" "$INDEX"
    validate_literal
    [ "$status" -eq 0 ]
    [ "$output" = "VALIDATE: 3 constructs checked, all valid" ]
    [ -z "$stderr" ]
}

@test "JQ-R3: quiet validation hides success but retains errors" {
    validate_literal true
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ -z "$stderr" ]
    cp "$FIXTURES/jq-count-error-index.json" "$INDEX"
    validate_literal true
    assert_rejected
}

@test "JQ-R3: a failed count discards even a plausible partial zero" {
    inject_jq_read count 7 0
    validate_literal
    [ "$(cat "$JQ_FAULT_HIT")" = count ]
    assert_rejected
    [[ "$stderr" == *"fixture jq read failed: count"* ]]
}

@test "JQ-R3: successful extraction with no usable count is rejected" {
    local value
    for value in '' null 0.5; do
        inject_jq_read count 0 "$value"
        validate_literal
        [ "$(cat "$JQ_FAULT_HIT")" = count ]
        assert_rejected
    done
}

@test "JQ-R3: a failed skills type read cannot become an allowed null" {
    inject_jq_read skills 7 null
    validate_literal
    [ "$(cat "$JQ_FAULT_HIT")" = skills ]
    assert_rejected
    [[ "$stderr" == *"fixture jq read failed: skills"* ]]
    [[ "$stderr" == *"skills type"* ]]
}

@test "JQ-R3: a failed commands type read cannot become an allowed null" {
    inject_jq_read commands 7 null
    validate_literal
    [ "$(cat "$JQ_FAULT_HIT")" = commands ]
    assert_rejected
    [[ "$stderr" == *"fixture jq read failed: commands"* ]]
    [[ "$stderr" == *"commands type"* ]]
}

@test "JQ-R3: empty type output is invalid while real null optionals stay allowed" {
    local field
    for field in skills commands; do
        inject_jq_read "$field" 0 ""
        validate_literal
        [ "$(cat "$JQ_FAULT_HIT")" = "$field" ]
        assert_rejected
    done
}

@test "JQ-R3: existing invalid array-field types and missing slug still fail" {
    local field
    for field in skills commands; do
        "$REAL_JQ" --arg field "$field" \
            '.constructs[0] |= (.skills = [] | .commands = [] | .[$field] = true)' \
            "$INDEX" > "$PROJECT_ROOT/invalid.json"
        mv "$PROJECT_ROOT/invalid.json" "$INDEX"
        validate_literal
        assert_rejected
        [[ "$stderr" == *"$field is boolean, expected array"* ]]
    done
    "$REAL_JQ" 'del(.constructs[0].slug)' "$INDEX" > "$PROJECT_ROOT/invalid.json"
    mv "$PROJECT_ROOT/invalid.json" "$INDEX"
    validate_literal
    assert_rejected
    [[ "$stderr" == *"missing slug"* ]]
}

@test "JQ-R3: YAML array count and type validation retains normal behavior" {
    INDEX="$PROJECT_ROOT/index.yaml"
    cat > "$INDEX" <<'YAML'
metadata:
  generated_at: fixture
constructs:
  - slug: demo
    name: Demo
    version: 1.0.0
    skills: []
    commands: []
YAML
    validate_literal
    [ "$status" -eq 0 ]
    [ "$output" = "VALIDATE: 1 constructs checked, all valid" ]
    [ -z "$stderr" ]
}

@test "JQ-R3: actual generate --validate caller succeeds on a normal local pack" {
    generate_and_validate
    [ "$status" -eq 0 ]
    [ "$output" = "VALIDATE: 1 constructs checked, all valid" ]
    "$REAL_JQ" -e '.constructs | length == 1' "$INDEX"
    "$REAL_JQ" -e '.constructs[0] | .slug == "demo" and .skills == [] and .commands == []' "$INDEX"
}

@test "JQ-R3: actual generate --validate caller propagates all three read failures" {
    local field
    for field in count skills commands; do
        inject_jq_read "$field" 7 null
        generate_and_validate --quiet
        [ "$(cat "$JQ_FAULT_HIT")" = "$field" ]
        assert_rejected
        [[ "$stderr" == *"fixture jq read failed: $field"* ]]
    done
}
