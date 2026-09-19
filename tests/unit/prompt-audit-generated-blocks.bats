#!/usr/bin/env bats
# =============================================================================
# tests/unit/prompt-audit-generated-blocks.bats — cycle-124 FR-8 / AC-8.3
#
# Registry-rendered prompt sections are edited only through their generator:
# generate-constraints.sh --dry-run must print no hunk and
# generate-skill-includes.sh --check must pass, and every generated-block
# start marker must be closed by its end marker in the same file.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
}

@test "GB-1 generate-constraints.sh --dry-run reports no drift" {
    run bash -c "cd '$PROJECT_ROOT' && bash .claude/scripts/generate-constraints.sh --dry-run 2>&1"
    [ "$status" -eq 0 ]
    # a drifted target prints unified-diff hunks; a clean one prints only the headers
    ! grep -qE '^(\+|-)[^+-]|^@@' <<<"$output"
}

@test "GB-2 generate-skill-includes.sh --check passes" {
    run bash -c "cd '$PROJECT_ROOT' && bash .claude/scripts/generate-skill-includes.sh --check"
    [ "$status" -eq 0 ]
}

@test "GB-3 every @constraint-generated / @skill-include start marker is closed in its file" {
    local bad=0 f
    while IFS= read -r f; do
        while IFS= read -r name; do
            grep -qE "@(constraint-generated|skill-include): end ${name}( |$|-->)" "$f" \
                || { echo "$f: unclosed generated block '$name'"; bad=$((bad + 1)); }
        done < <(grep -oE '@(constraint-generated|skill-include): start [A-Za-z0-9_-]+' "$f" | awk '{print $3}')
    done < <(cd "$PROJECT_ROOT" && grep -rlE '@(constraint-generated|skill-include): start' .claude/loa .claude/skills .claude/protocols | sed "s|^|$PROJECT_ROOT/|")
    [ "$bad" -eq 0 ]
}
