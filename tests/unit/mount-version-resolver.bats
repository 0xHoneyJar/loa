#!/usr/bin/env bats
# =============================================================================
# mount-version-resolver.bats — Regression test for #640 / sprint-bug-122
# =============================================================================
# Static-grep regression suite for `.claude/skills/mounting-framework/SKILL.md`.
#
# Purpose: prevent recurrence-class #4 of the "/mount writes stale
# framework_version" defect. Prior recurrences:
#   #56  (Jan 2026) — original
#   #123 (Feb 2026) — bumped literal, returned at next release
#   #640 (Apr 2026) — same literal back at "0.6.0" again
#
# The structural fix routes /mount through update-loa-bump-version.sh
# (single source of truth shared with /update-loa) and reads the version
# back from .loa-version.json via jq. These tests fail the moment any
# hardcoded version literal reappears in the SKILL.md template.
# =============================================================================

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export SKILL_FILE="$PROJECT_ROOT/.claude/skills/mounting-framework/SKILL.md"
    [[ -f "$SKILL_FILE" ]] || skip "SKILL.md not found at $SKILL_FILE"
}

@test "SKILL.md must not contain framework_version JSON literal (e.g., \"framework_version\": \"0.6.0\")" {
    run grep -nE '"framework_version"[[:space:]]*:[[:space:]]*"[0-9]' "$SKILL_FILE"
    if [[ "$status" -eq 0 ]]; then
        echo "Found stale framework_version literal(s) — see #640:"
        echo "$output"
        return 1
    fi
}

@test "SKILL.md must not contain version-string literal in trajectory line (e.g., \"version\":\"0.6.0\")" {
    run grep -nE '"version"[[:space:]]*:[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' "$SKILL_FILE"
    if [[ "$status" -eq 0 ]]; then
        echo "Found stale trajectory version literal(s) — see #640:"
        echo "$output"
        return 1
    fi
}

@test "SKILL.md must not contain v0.X.Y NOTES.md template literal (e.g., 'Mounted Loa v0.6.0')" {
    run grep -nE 'Mounted Loa v[0-9]+\.[0-9]+\.[0-9]+' "$SKILL_FILE"
    if [[ "$status" -eq 0 ]]; then
        echo "Found stale NOTES.md template literal(s) — see #640:"
        echo "$output"
        return 1
    fi
}

@test "SKILL.md invokes update-loa-bump-version.sh resolver (single source of truth)" {
    grep -qF 'update-loa-bump-version.sh' "$SKILL_FILE"
}

@test "SKILL.md reads version BACK via jq from .loa-version.json (trajectory + NOTES read-back, not just idempotency check)" {
    # SKILL.md already reads .loa-version.json for the "Loa already mounted"
    # idempotency check at the top of the skill (~line 49). Post-fix MUST
    # read it back at LEAST one more time — for the trajectory log + NOTES.md
    # row that no longer use templated literals. Threshold: >= 2 occurrences.
    local count
    count=$(grep -cE 'jq.*-r.*framework_version.*\.loa-version\.json' "$SKILL_FILE" || true)
    if [[ "$count" -lt 2 ]]; then
        echo "Expected >= 2 jq read-backs of .loa-version.json (idempotency + trajectory/NOTES); found $count"
        return 1
    fi
}
