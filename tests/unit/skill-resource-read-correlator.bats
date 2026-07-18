#!/usr/bin/env bats
# =============================================================================
# skill-resource-read-correlator.bats — Tests for the offline
# read-vs-manifest correlator (cycle-116 D2 instrumentation)
# =============================================================================
# Fixture: tests/fixtures/skill-read-correlator/
#   fake-repo/                       — a tiny synthetic "project" with one
#                                       skill (fixture-skill, declares an
#                                       `inputs:` manifest + resources/) and
#                                       one never-invoked skill (other-skill).
#   session.jsonl.tmpl               — a synthetic session transcript with
#                                       the __FAKE_REPO__ placeholder, resolved
#                                       to an absolute path in setup() since
#                                       real Read tool_use file_path values
#                                       are always absolute.
#
# The transcript encodes, in order:
#   1. leading assistant text (must never appear in correlator output)
#   2. a Read of CLAUDE.md BEFORE any Skill invocation (must NOT be attributed
#      to fixture-skill — proves the correlator doesn't misattribute reads
#      that precede the first Skill call)
#   3. Skill fixture-skill (args carries a secret marker — must never leak)
#   4. Read of CLAUDE.md (declared input -> should show as read)
#   5. Read of resources/REFERENCE.md (resource -> should show as read)
#   6. a SIDECHAIN Read of resources/UNREAD.md (must be excluded -> UNREAD.md
#      must show as never-read despite this Read existing in the transcript)
#   7. a second Skill fixture-skill invocation (invocations must count 2)
#   8. a second Read of CLAUDE.md (dedup: inputs_read must still list it once)
#
# other-skill is never referenced by the transcript at all, so it must be
# entirely absent from output (not printed with invocations=0).

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    REPO="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCRIPT="$REPO/.claude/scripts/skill-resource-read-correlator.sh"
    FIXTURE_DIR="$REPO/tests/fixtures/skill-read-correlator"

    FAKE_REPO="$(cd "$FIXTURE_DIR/fake-repo" && pwd)"
    export PROJECT_ROOT="$FAKE_REPO"
    export SKILLS_DIR="$FAKE_REPO/.claude/skills"

    TRANSCRIPT_DIR="$BATS_TEST_TMPDIR/transcripts"
    mkdir -p "$TRANSCRIPT_DIR"
    sed "s#__FAKE_REPO__#$FAKE_REPO#g" "$FIXTURE_DIR/session.jsonl.tmpl" > "$TRANSCRIPT_DIR/session.jsonl"
}

# =========================================================================
# Attribution correctness
# =========================================================================

@test "correlator: attributes invocations, reads, and not-read/never-read correctly" {
    run bash "$SCRIPT" --project-dir "$TRANSCRIPT_DIR" --json
    [ "$status" -eq 0 ]

    invocations="$(echo "$output" | jq -r '.[] | select(.skill=="fixture-skill") | .invocations')"
    [ "$invocations" -eq 2 ]

    # declared input CLAUDE.md was read -> appears in inputs_read, not in inputs_not_read
    echo "$output" | jq -e '.[] | select(.skill=="fixture-skill") | .inputs_read | index("'"$FAKE_REPO"'/CLAUDE.md") != null' >/dev/null
    echo "$output" | jq -e '.[] | select(.skill=="fixture-skill") | (.inputs_not_read | index("'"$FAKE_REPO"'/CLAUDE.md")) == null' >/dev/null

    # declared input notes.md was never read -> appears in inputs_not_read
    echo "$output" | jq -e '.[] | select(.skill=="fixture-skill") | .inputs_not_read | index("'"$FAKE_REPO"'/notes.md") != null' >/dev/null

    # resources/REFERENCE.md was read (main-chain) -> resources_read
    echo "$output" | jq -e '.[] | select(.skill=="fixture-skill") | .resources_read | index("'"$FAKE_REPO"'/.claude/skills/fixture-skill/resources/REFERENCE.md") != null' >/dev/null

    # resources/UNREAD.md was only read on a sidechain -> must still be "never read"
    echo "$output" | jq -e '.[] | select(.skill=="fixture-skill") | .resources_never_read | index("'"$FAKE_REPO"'/.claude/skills/fixture-skill/resources/UNREAD.md") != null' >/dev/null
    echo "$output" | jq -e '.[] | select(.skill=="fixture-skill") | (.resources_read | index("'"$FAKE_REPO"'/.claude/skills/fixture-skill/resources/UNREAD.md")) == null' >/dev/null
}

@test "correlator: dedups repeated reads of the same declared input" {
    run bash "$SCRIPT" --project-dir "$TRANSCRIPT_DIR" --json
    [ "$status" -eq 0 ]
    count="$(echo "$output" | jq -r '[.[] | select(.skill=="fixture-skill") | .inputs_read[] | select(. == "'"$FAKE_REPO"'/CLAUDE.md")] | length')"
    [ "$count" -eq 1 ]
}

@test "correlator: a never-invoked skill is entirely absent from output" {
    run bash "$SCRIPT" --project-dir "$TRANSCRIPT_DIR" --json
    [ "$status" -eq 0 ]
    [[ "$output" != *"other-skill"* ]]
    echo "$output" | jq -e '[.[] | select(.skill=="other-skill")] | length == 0' >/dev/null
}

@test "correlator: text output mirrors the JSON attribution" {
    run bash "$SCRIPT" --project-dir "$TRANSCRIPT_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"fixture-skill: invocations=2"* ]]
    [[ "$output" == *"notes.md"* ]]
    [[ "$output" == *"UNREAD.md"* ]]
    [[ "$output" != *"other-skill"* ]]
}

# =========================================================================
# No-op path (CI / sandbox without ~/.claude/projects)
# =========================================================================

@test "correlator: graceful no-op with a clear message when the transcript dir is absent" {
    run bash "$SCRIPT" --project-dir "$BATS_TEST_TMPDIR/does-not-exist"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No session transcripts found"* ]]
    [[ "$output" == *"Nothing to correlate"* ]]
}

@test "correlator: graceful no-op when the transcript dir exists but has no .jsonl files" {
    empty_dir="$BATS_TEST_TMPDIR/empty-transcripts"
    mkdir -p "$empty_dir"
    run bash "$SCRIPT" --project-dir "$empty_dir"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Nothing to correlate"* ]]
}

# =========================================================================
# PII / content-leakage posture
# =========================================================================

@test "correlator: never leaks Skill args, message text, or any content beyond file paths" {
    run bash "$SCRIPT" --project-dir "$TRANSCRIPT_DIR" --json
    [ "$status" -eq 0 ]
    [[ "$output" != *"SECRET_TOKEN_DO_NOT_LEAK"* ]]
    [[ "$output" != *"PRE_SKILL_TEXT_SHOULD_NOT_LEAK"* ]]

    run bash "$SCRIPT" --project-dir "$TRANSCRIPT_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" != *"SECRET_TOKEN_DO_NOT_LEAK"* ]]
    [[ "$output" != *"PRE_SKILL_TEXT_SHOULD_NOT_LEAK"* ]]
}

# =========================================================================
# CLI surface
# =========================================================================

@test "correlator: --help exits 0 and documents --project-dir" {
    run bash "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--project-dir"* ]]
}

@test "correlator: exits nonzero on an unknown flag" {
    run bash "$SCRIPT" --nonsense-flag
    [ "$status" -ne 0 ]
}
