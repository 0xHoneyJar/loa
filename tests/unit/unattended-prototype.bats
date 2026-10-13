#!/usr/bin/env bats
# =============================================================================
# tests/unit/unattended-prototype.bats: the prototype route in the planning
# interview (grimoires/loa/sdd.md D-5.1, D-5.7, D-5.8).
#
# The behaviour itself is skill prose; these checks pin what is checkable:
# the config example documents interview.unattended_prototype with both values
# and the default, each planning skill carries the interview rule in at most
# two lines, and the sequencing guidance points at prototype tickets.
# =============================================================================

setup() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    CONFIG="$PROJECT_ROOT/.loa.config.yaml.example"
    SKILLS="$PROJECT_ROOT/.claude/skills"
}

# The interview block's unattended_prototype comment and key, as text.
prototype_block() {
    awk '/^interview:/ { on = 1; next } on && /^[^[:space:]#]/ { on = 0 } on' "$CONFIG" \
        | awk '/Prototype-class questions/ { on = 1 } on { print } on && /^  unattended_prototype:/ { exit }'
}

@test "config example: interview.unattended_prototype defaults to defer" {
    if command -v yq >/dev/null 2>&1 && yq --version 2>&1 | grep -q 'mikefarah.*version v4\.'; then
        [ "$(yq '.interview.unattended_prototype' "$CONFIG")" = "defer" ]
    fi
    grep -qE '^  unattended_prototype: defer[[:space:]]+# defer \| halt$' "$CONFIG"
}

@test "config example: both values are documented with their semantics" {
    local block; block="$(prototype_block)"
    [[ -n "$block" ]]
    # defer: the bead, the open row, the PRD Deferred line, and planning continues
    [[ "$block" == *"defer (default)"* ]]
    [[ "$block" == *"decision:prototype bead"* ]]
    [[ "$block" == *"open DEC row"* ]]
    [[ "$block" == *"**Deferred:** pending prototype <bead-id> (DEC-NNNN)"* ]]
    [[ "$block" == *"continue planning"* ]]
    # halt: the same bead and row, then planning stops with the documented message
    [[ "$block" == *"halt: create the same bead and row, then stop planning"* ]]
    [[ "$block" == *"planning halted: prototype <bead-id> (DEC-NNNN)"* ]]
}

@test "config example: the Deferred line it documents is the form the PRD validator recognises" {
    grep -q 'the form is \*\*Deferred:\*\* pending prototype <bead> (DEC-NNNN)' \
        "$PROJECT_ROOT/.claude/scripts/validate-artifact.sh"
}

@test "planning skills: each carries the prototype interview rule on at most two lines" {
    local s f n
    for s in discovering-requirements designing-architecture planning-sprints; do
        f="$SKILLS/$s/SKILL.md"
        n="$(grep -c 'I need to see it' "$f")"
        [ "$n" -eq 1 ]
        # the whole rule (through the config key) fits in the matching line and the next
        grep -A1 'I need to see it' "$f" | tr '\n' ' ' | grep -q 'decision:prototype.*never an `\[ASSUMPTION\]`.*interview.unattended_prototype'
    done
}

@test "planning-sprints REFERENCE: High-Risk Early points at prototype tickets, not spike tasks in build sprints" {
    local ref="$SKILLS/planning-sprints/resources/REFERENCE.md" block
    block="$(awk '/\*\*High-Risk Early\*\*/ { on = 1; next } on && /^[0-9]+\. \*\*/ { exit } on' "$ref")"
    [[ "$block" == *"decision:prototype"* ]]
    [[ "$block" == *"not a spike task inside a build sprint"* ]]
    [[ "$block" != *"Technical spikes"* ]]
}

@test "planning-sprints: the integration-context list moved to REFERENCE.md behind a pointer" {
    grep -q '§Integration Context' "$SKILLS/planning-sprints/SKILL.md"
    grep -q '^## Integration Context$' "$SKILLS/planning-sprints/resources/REFERENCE.md"
}
