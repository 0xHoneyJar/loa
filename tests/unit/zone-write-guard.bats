#!/usr/bin/env bats
# =============================================================================
# tests/unit/zone-write-guard.bats — cycle-106 sprint-1 T1.5
# =============================================================================
# Exercises .claude/hooks/safety/zone-write-guard.sh decision matrix per
# SDD §3.1 + escape hatches per §3.2.

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    HOOK="$PROJECT_ROOT/.claude/hooks/safety/zone-write-guard.sh"
    [[ -x "$HOOK" ]] || skip "hook not executable"
    command -v yq >/dev/null 2>&1 || skip "yq not on PATH"

    SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/zwg-XXXXXX")"
    chmod 700 "$SCRATCH"

    # Make a minimal zones.yaml fixture and point the hook at it.
    cat > "$SCRATCH/zones.yaml" <<'YAML'
schema_version: "1.0"
zones:
  framework:
    tracked_paths:
      - ".claude/**"
      - "tools/**"
  project:
    tracked_paths:
      - "grimoires/loa/cycles/**"
      - "grimoires/loa/NOTES.md"
  shared:
    tracked_paths:
      - "grimoires/loa/known-failures.md"
YAML
    export LOA_ZONES_FILE="$SCRATCH/zones.yaml"
}

teardown() {
    [[ -n "${SCRATCH:-}" && -d "$SCRATCH" ]] && rm -rf "$SCRATCH"
    unset LOA_ZONES_FILE LOA_ACTOR LOA_ZONE_GUARD_BYPASS LOA_ZONE_GUARD_DISABLE LOA_REQUIRE_ZONES
}

# ---- ZWG-T1..T6 decision matrix -----------------------------------------

@test "ZWG-T1: project work writes project-zone path → ALLOW" {
    CLAUDE_TOOL_FILE_PATH="grimoires/loa/cycles/cycle-X/sprint.md" \
    LOA_ACTOR="project-work" \
    run "$HOOK"
    [ "$status" -eq 0 ]
}

@test "ZWG-T2: project work writes framework-zone path → BLOCK" {
    CLAUDE_TOOL_FILE_PATH=".claude/loa/CLAUDE.loa.md" \
    LOA_ACTOR="project-work" \
    run "$HOOK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCKED"* ]]
    [[ "$output" == *"framework-zone"* ]]
}

@test "ZWG-T3: update-loa writes framework-zone path → ALLOW" {
    CLAUDE_TOOL_FILE_PATH=".claude/scripts/some-script.sh" \
    LOA_ACTOR="update-loa" \
    run "$HOOK"
    [ "$status" -eq 0 ]
}

@test "ZWG-T4: update-loa writes project-zone path → BLOCK" {
    CLAUDE_TOOL_FILE_PATH="grimoires/loa/cycles/cycle-X/sprint.md" \
    LOA_ACTOR="update-loa" \
    run "$HOOK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCKED"* ]]
    [[ "$output" == *"update-loa MUST NOT"* ]]
}

@test "ZWG-T5: shared zone any actor → ALLOW" {
    CLAUDE_TOOL_FILE_PATH="grimoires/loa/known-failures.md" \
    LOA_ACTOR="update-loa" \
    run "$HOOK"
    [ "$status" -eq 0 ]

    CLAUDE_TOOL_FILE_PATH="grimoires/loa/known-failures.md" \
    LOA_ACTOR="project-work" \
    run "$HOOK"
    [ "$status" -eq 0 ]
}

@test "ZWG-T6: unclassified path → ALLOW (positive declaration only)" {
    CLAUDE_TOOL_FILE_PATH="src/main.py" \
    LOA_ACTOR="project-work" \
    run "$HOOK"
    [ "$status" -eq 0 ]

    CLAUDE_TOOL_FILE_PATH="docs/notes.md" \
    LOA_ACTOR="update-loa" \
    run "$HOOK"
    [ "$status" -eq 0 ]
}

# ---- ZWG-T7..T8 escape hatches ------------------------------------------

@test "ZWG-T7: LOA_ZONE_GUARD_BYPASS=1 → ALLOW + stderr WARN" {
    CLAUDE_TOOL_FILE_PATH=".claude/loa/CLAUDE.loa.md" \
    LOA_ACTOR="project-work" \
    LOA_ZONE_GUARD_BYPASS=1 \
    run "$HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING"* ]] || [[ "$output" == *"WARN"* ]]
    [[ "$output" == *"BYPASS"* ]] || [[ "$output" == *"allowing"* ]]
}

@test "ZWG-T8: LOA_ZONE_GUARD_DISABLE=1 → ALLOW with no diagnostic" {
    CLAUDE_TOOL_FILE_PATH=".claude/loa/CLAUDE.loa.md" \
    LOA_ACTOR="project-work" \
    LOA_ZONE_GUARD_DISABLE=1 \
    run "$HOOK"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ---- ZWG-T9..T10 config edge cases --------------------------------------

@test "ZWG-T9: missing zones.yaml → ALLOW with graceful degradation" {
    LOA_ZONES_FILE="$SCRATCH/does-not-exist.yaml" \
    CLAUDE_TOOL_FILE_PATH=".claude/loa/CLAUDE.loa.md" \
    LOA_ACTOR="project-work" \
    run "$HOOK"
    [ "$status" -eq 0 ]
}

@test "ZWG-T9b: missing zones.yaml + LOA_REQUIRE_ZONES=1 → exit 2" {
    LOA_ZONES_FILE="$SCRATCH/does-not-exist.yaml" \
    LOA_REQUIRE_ZONES=1 \
    CLAUDE_TOOL_FILE_PATH=".claude/loa/CLAUDE.loa.md" \
    LOA_ACTOR="project-work" \
    run "$HOOK"
    [ "$status" -eq 2 ]
}

# ---- ZWG-T11 glob matching ----------------------------------------------

@test "ZWG-T11: ** glob recursive match (deep path in framework zone) → BLOCK" {
    CLAUDE_TOOL_FILE_PATH=".claude/scripts/beads/beads-health.sh" \
    LOA_ACTOR="project-work" \
    run "$HOOK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCKED"* ]]
}

@test "ZWG-T11b: exact-file match (NOTES.md project zone)" {
    CLAUDE_TOOL_FILE_PATH="grimoires/loa/NOTES.md" \
    LOA_ACTOR="update-loa" \
    run "$HOOK"
    [ "$status" -eq 1 ]
}

# ---- ZWG-T12 trajectory logging (best-effort, soft check) --------------

@test "ZWG-T12: blocked write logs a trajectory entry (when dir exists)" {
    local trajdir="$SCRATCH/trajectory"
    mkdir -p "$trajdir"
    # Point PROJECT_ROOT-derived path indirectly. Hook computes
    # trajectory dir from $PROJECT_ROOT/grimoires/loa/a2a/trajectory; we
    # cannot easily override that within this isolated fixture, so we
    # just confirm the hook doesn't crash when invoked. Real-world
    # logging is exercised via the integration smoke in CI.
    CLAUDE_TOOL_FILE_PATH=".claude/loa/CLAUDE.loa.md" \
    LOA_ACTOR="project-work" \
    run "$HOOK"
    [ "$status" -eq 1 ]
}

# ---- ZWG-T13 absolute path normalization --------------------------------

@test "ZWG-T13: absolute path under PROJECT_ROOT is normalized" {
    CLAUDE_TOOL_FILE_PATH="${PROJECT_ROOT}/.claude/loa/CLAUDE.loa.md" \
    LOA_ACTOR="project-work" \
    run "$HOOK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCKED"* ]]
}
