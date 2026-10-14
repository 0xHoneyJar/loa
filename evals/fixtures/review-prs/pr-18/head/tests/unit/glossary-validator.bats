#!/usr/bin/env bats
# =============================================================================
# tests/unit/glossary-validator.bats
#
# validate-artifact.sh --type glossary (grimoires/loa/sdd.md D-6.4, §4.5): an
# H1, a context paragraph before '## Language', one-line '**Term**: definition'
# entries of at most two sentences and 300 characters, _Avoid_: and _Aliases_:
# only directly below an entry, no duplicate term or alias, WARN on a path or
# file extension in '## Language'. Cases write temp files only.
# =============================================================================

setup() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    SCRIPT="${PROJECT_ROOT}/.claude/scripts/validate-artifact.sh"
    G="$BATS_TEST_TMPDIR/GLOSSARY.md"
}

# glossary <language-section lines...>: a valid head plus the given body
glossary() {
    { printf '# Glossary: test\n\nThe vocabulary of a test project.\n\n## Language\n\n'; printf '%s\n' "$@"; } > "$G"
}

val() { run "$SCRIPT" --type glossary --file "$G" "$@"; }

@test "GV-1 the framework glossary validates with no warning" {
    run "$SCRIPT" --type glossary --file "$PROJECT_ROOT/.claude/loa/GLOSSARY.md"
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARN"* ]]
}

@test "GV-2 the root project glossary validates with no warning" {
    run "$SCRIPT" --type glossary --file "$PROJECT_ROOT/GLOSSARY.md"
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARN"* ]]
}

@test "GV-3 both fixture glossaries validate" {
    run "$SCRIPT" --type glossary --file "$PROJECT_ROOT/tests/fixtures/glossary/ok/GLOSSARY.md"
    [ "$status" -eq 0 ]
    run "$SCRIPT" --type glossary --file "$PROJECT_ROOT/tests/fixtures/glossary/miss/GLOSSARY.md"
    [ "$status" -eq 0 ]
}

@test "GV-4 a well-formed entry with _Avoid_ and _Aliases_ lines passes" {
    glossary '**Dissent**: A second review. It is triaged.' '_Avoid_: second opinion' '_Aliases_: DIS, counter-review' '' '### Group' '' '**Voice**: Who decided.'
    val
    [ "$status" -eq 0 ]
}

@test "GV-5 a duplicate term fails, case-insensitively" {
    glossary '**Spike**: A prototype.' '' '**spike**: Another one.'
    val
    [ "$status" -eq 1 ]
    [[ "$output" == *'term "spike" duplicates term "Spike"'* ]]
}

@test "GV-6 an alias that repeats a term or another alias fails" {
    glossary '**Run mode**: Unattended runs.' '_Aliases_: RUNNING' '' '**Halt**: A stop.' '_Aliases_: running, run_mode'
    val
    [ "$status" -eq 1 ]
    [[ "$output" == *'alias "running" duplicates alias "RUNNING"'* ]]
    [[ "$output" == *'alias "run_mode" duplicates term "Run mode"'* ]]
}

@test "GV-7 a definition over 300 characters fails" {
    glossary "**Long**: $(printf 'a%.0s' $(seq 1 301))."
    val
    [ "$status" -eq 1 ]
    [[ "$output" == *'the definition of "Long" is 302 characters, over 300'* ]]
}

@test "GV-8 a definition of exactly 300 characters passes; multibyte characters count once" {
    glossary "**Edge**: $(printf 'a%.0s' $(seq 1 299))." "**Wide**: $(printf 'é%.0s' $(seq 1 299))."
    val
    [ "$status" -eq 0 ]
}

@test "GV-9 a three-sentence definition fails; two sentences pass" {
    glossary '**Three**: One. Two! Three?'
    val
    [ "$status" -eq 1 ]
    [[ "$output" == *'the definition of "Three" has 3 sentences; at most two'* ]]
    glossary '**Two**: One sentence here. And a second (with a note).'
    val
    [ "$status" -eq 0 ]
}

@test "GV-10 _Aliases_ without an entry fails" {
    glossary '_Aliases_: orphan' '' '**Real**: An entry.'
    val
    [ "$status" -eq 1 ]
    [[ "$output" == *"_Aliases_: is not directly after an entry"* ]]
}

@test "GV-11 _Avoid_ separated from its entry by a blank line fails" {
    glossary '**Real**: An entry.' '' '_Avoid_: other word'
    val
    [ "$status" -eq 1 ]
    [[ "$output" == *"_Avoid_: is not directly after an entry"* ]]
}

@test "GV-12 a missing ## Language section fails" {
    printf '# Glossary: test\n\nContext.\n\n## Terms\n\n**A**: B.\n' > "$G"
    val
    [ "$status" -eq 1 ]
    [[ "$output" == *'no "## Language" section'* ]]
}

@test "GV-13 a missing H1 or context paragraph fails" {
    printf 'Context.\n\n## Language\n\n**A**: B.\n' > "$G"
    val
    [ "$status" -eq 1 ]
    [[ "$output" == *"no H1"* ]]
    printf '# Glossary: test\n\n## Language\n\n**A**: B.\n' > "$G"
    val
    [ "$status" -eq 1 ]
    [[ "$output" == *"no context paragraph"* ]]
}

@test "GV-14 a definition wrapped onto a second line fails" {
    glossary '**Wrapped**: A definition that' 'continues on the next line.'
    val
    [ "$status" -eq 1 ]
    [[ "$output" == *"not an entry"* ]]
}

@test "GV-15 a path or file extension in a definition WARNs and still passes" {
    glossary '**Hook**: The guard in hooks/implement-gate that asks first.' '**Doc**: The plan in a markdown file named plan.md for review.'
    val
    [ "$status" -eq 0 ]
    [[ "$output" == *":7: a path or file extension"* ]]
    [[ "$output" == *":8: a path or file extension"* ]]
}

@test "GV-16 an empty Language section and an entry without text fail" {
    glossary ''
    val
    [ "$status" -eq 1 ]
    [[ "$output" == *"has no **Term**: entries"* ]]
    glossary '**Bare**:'
    val
    [ "$status" -eq 1 ]
    [[ "$output" == *"needs \"**Term**: definition\""* ]]
}

@test "GV-17 --json reports the glossary type and its violations" {
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
    glossary '**Spike**: A prototype.' '**SPIKE**: Again.'
    run bash -c '"$0" --type glossary --file "$1" --json 2>/dev/null' "$SCRIPT" "$G"
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.type == "glossary" and .pass == false and (.violations | length) == 1' >/dev/null
}

@test "GV-18 an H1 not shaped '# Glossary: <name>' WARNs" {
    printf '# Words\n\nContext.\n\n## Language\n\n**A**: B.\n' > "$G"
    val
    [ "$status" -eq 0 ]
    [[ "$output" == *'WARN:'*'the H1 is not "# Glossary: <name>"'* ]]
}

@test "GV-19 lines inside fenced code in Language are not judged" {
    glossary '**A**: B.' '' '```' 'not an entry' '_Aliases_: x' '```'
    val
    [ "$status" -eq 0 ]
}
