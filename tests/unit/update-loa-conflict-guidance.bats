#!/usr/bin/env bats
# =============================================================================
# update-loa-conflict-guidance.bats — #1180 (bd-c1180-hook-brick-trlm)
# =============================================================================
# Locks in the /update-loa slash-command guidance that names .claude/hooks/**
# and .claude/settings.json as FIRST-to-resolve on a merge conflict, plus the
# fully-bricked-session escape hatch whose recovery command must NOT carry the
# inert `LOA_ACTOR=update-loa` prefix. Grep-based, mirroring the style of
# gitattributes-merge-protection.bats.

setup() {
    ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    UPDATE_LOA="$ROOT/.claude/commands/update-loa.md"
}

@test "Phase 5 conflict handling names .claude/hooks/** as first-to-resolve" {
    grep -qF 'Conflict handling — resolve `.claude/hooks/**` and `.claude/settings.json` FIRST' "$UPDATE_LOA"
}

@test "hooks-first recovery one-liner is present (checkout --theirs both paths)" {
    grep -qF "git checkout --theirs .claude/hooks/ .claude/settings.json && git add .claude/hooks/ .claude/settings.json" "$UPDATE_LOA"
}

@test "hooks-first ordering explains the PreToolUse:Bash re-trigger reason" {
    grep -qF 'PreToolUse:Bash' "$UPDATE_LOA"
    grep -q 'bricking the session' "$UPDATE_LOA"
}

@test "hooks-first rule appears BEFORE the '## Conflict Resolution' section" {
    local rule_line cr_line
    rule_line=$(grep -n 'Conflict handling — resolve' "$UPDATE_LOA" | head -1 | cut -d: -f1)
    cr_line=$(grep -n '^## Conflict Resolution' "$UPDATE_LOA" | head -1 | cut -d: -f1)
    [ -n "$rule_line" ]
    [ -n "$cr_line" ]
    [ "$rule_line" -lt "$cr_line" ]
}

@test "escape hatch documents the fully-bricked case must run OUTSIDE Claude Code" {
    grep -q 'OUTSIDE Claude Code' "$UPDATE_LOA"
    grep -q 'every' "$UPDATE_LOA"  # "every Bash call fails identically"
}

@test "escape hatch recovery command drops the inert LOA_ACTOR prefix" {
    # The plain recovery command exists...
    grep -qF 'git checkout --theirs .claude/hooks/safety/block-destructive-bash.sh' "$UPDATE_LOA"
    # ...and no recovery command anywhere is prefixed with LOA_ACTOR=update-loa.
    ! grep -qE 'LOA_ACTOR=update-loa[[:space:]]+git checkout' "$UPDATE_LOA"
    # The doc explicitly calls the prefix inert.
    grep -q 'inert here' "$UPDATE_LOA"
}

@test "guidance references issue #1180" {
    grep -qF '#1180' "$UPDATE_LOA"
}
