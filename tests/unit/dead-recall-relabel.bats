#!/usr/bin/env bats
# D2 (cycle-115 sprint-1) — dead-recall docs relabel: doc-lint + regression guard.
#
# These tests assert two things, TEST-FIRST:
#   (a) the EXPERIMENTAL marker is present near the recall / Memory-Writer-Hook
#       section in EACH of the 3 target doc files;
#   (b) a docs-only regression guard — `git diff --name-only` (vs HEAD) touches
#       NONE of the behavioral surfaces: .claude/hooks/*.sh, memory-*.sh,
#       settings.hooks.json, .loa*/ . D2 is docs-only: it changes ZERO behavior.

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT

    MEMORY_REF="$PROJECT_ROOT/.claude/loa/reference/memory-reference.md"
    REC_HOOKS="$PROJECT_ROOT/.claude/protocols/recommended-hooks.md"
    HOOKS_README="$PROJECT_ROOT/.claude/hooks/README.md"

    # The exact marker string D2 standardizes on across all three files.
    MARKER="EXPERIMENTAL — not wired, do not rely on"
}

# --- (a) EXPERIMENTAL marker present in each of the 3 files -----------------

@test "memory-reference.md carries the EXPERIMENTAL marker" {
    run grep -F "$MARKER" "$MEMORY_REF"
    [ "$status" -eq 0 ]
}

@test "recommended-hooks.md carries the EXPERIMENTAL marker" {
    run grep -F "$MARKER" "$REC_HOOKS"
    [ "$status" -eq 0 ]
}

@test "hooks/README.md carries the EXPERIMENTAL marker" {
    run grep -F "$MARKER" "$HOOKS_README"
    [ "$status" -eq 0 ]
}

# --- marker sits near the relevant section, not stranded elsewhere ----------

@test "memory-reference.md marker is near the Memory Writer / recall section" {
    # Marker must appear within the first part of the doc, alongside the
    # "Memory Writer Hook" / "Progressive Disclosure" recall description.
    run grep -nE "Memory Writer Hook|Progressive Disclosure|recall" "$MEMORY_REF"
    [ "$status" -eq 0 ]
    run grep -F "$MARKER" "$MEMORY_REF"
    [ "$status" -eq 0 ]
}

@test "recommended-hooks.md marker is near memory-inject / memory-writer wiring" {
    run grep -nE "memory-inject\.sh|memory-writer\.sh" "$REC_HOOKS"
    [ "$status" -eq 0 ]
    run grep -F "$MARKER" "$REC_HOOKS"
    [ "$status" -eq 0 ]
}

@test "hooks/README.md marker is near the optional memory hooks" {
    run grep -nE "memory-writer\.sh|memory-inject\.sh" "$HOOKS_README"
    [ "$status" -eq 0 ]
    run grep -F "$MARKER" "$HOOKS_README"
    [ "$status" -eq 0 ]
}

# --- ownership cell corrected to the accurate wording (not "all-null") ------

@test "memory-reference.md ownership cell says hand-authored, zero hook-generated" {
    run grep -F "hand-authored, zero hook-generated entries" "$MEMORY_REF"
    [ "$status" -eq 0 ]
}

@test "memory-reference.md does NOT introduce the inaccurate all-null claim" {
    run grep -Fi "all-null" "$MEMORY_REF"
    [ "$status" -ne 0 ]
}

# --- (b) docs-only regression guard -----------------------------------------

@test "git diff touches no behavioral surface (docs-only)" {
    cd "$PROJECT_ROOT"
    # All paths changed vs HEAD across the whole tree.
    run git diff --name-only HEAD
    [ "$status" -eq 0 ]

    # No .sh hook, no memory-*.sh, no settings.hooks.json, no .loa*/ may be touched.
    forbidden=0
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        case "$f" in
            .claude/hooks/*.sh) echo "FORBIDDEN hook .sh changed: $f"; forbidden=1 ;;
            *memory-*.sh)       echo "FORBIDDEN memory-*.sh changed: $f"; forbidden=1 ;;
            *settings.hooks.json) echo "FORBIDDEN settings.hooks.json changed: $f"; forbidden=1 ;;
            .loa*/*)            echo "FORBIDDEN .loa*/ changed: $f"; forbidden=1 ;;
        esac
    done <<< "$output"

    [ "$forbidden" -eq 0 ]
}
