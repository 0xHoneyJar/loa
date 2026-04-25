#!/usr/bin/env bats
# =============================================================================
# Tests for bash-3.2 portability across .claude/scripts/
# Cycle-094 sprint-1 T1.2 (G-2) — meta-tests that prevent regression of the
# named-fd `exec {var}>file` pattern, which crashes on macOS default bash 3.2.
#
# The pattern is rewritten as `( flock -w T 9 ... ) 9>"$lockfile"` (subshell
# with hardcoded fd) — see model-health-probe.sh:_cache_atomic_write and
# bridge-state.sh:_atomic_state_update_flock.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
}

# -----------------------------------------------------------------------------
# G-2: No named-fd `exec {var}>file` patterns in production scripts
# -----------------------------------------------------------------------------
@test "G-2: no exec {var}>file named-fd patterns in .claude/scripts/" {
    # The grep regex matches the literal pattern. Test files that intentionally
    # exercise the pattern are excluded (none currently exist; if added, list
    # them in the EXCLUDE array below).
    local matches
    matches="$(grep -rnE 'exec \{[a-z_]+\}>' "$PROJECT_ROOT/.claude/scripts/" 2>/dev/null || true)"
    if [[ -n "$matches" ]]; then
        echo "Forbidden named-fd patterns found:" >&2
        echo "$matches" >&2
        echo "" >&2
        echo "Replace with: ( flock -w T 9 || exit 1 ; <work> ) 9>\"\$lockfile\"" >&2
        return 1
    fi
}

@test "G-2: no exec {var}>>file (append form) either" {
    local matches
    matches="$(grep -rnE 'exec \{[a-z_]+\}>>' "$PROJECT_ROOT/.claude/scripts/" 2>/dev/null || true)"
    [[ -z "$matches" ]] || { echo "$matches" >&2; return 1; }
}

@test "G-2: bridge-state.sh uses subshell+fd9 pattern" {
    # Positive assertion: the canonical replacement pattern is present.
    grep -qE '\) 9>"\$BRIDGE_STATE_LOCK"' "$PROJECT_ROOT/.claude/scripts/bridge-state.sh"
}

@test "G-2: model-health-probe.sh uses subshell+fd9 pattern in _cache_atomic_write" {
    grep -qE '\) 9>"\$lockfile"' "$PROJECT_ROOT/.claude/scripts/model-health-probe.sh"
}

@test "G-2: all .claude/scripts/ pass bash -n syntax check" {
    local failures=()
    while IFS= read -r script; do
        if ! bash -n "$script" 2>/dev/null; then
            failures+=("$script")
        fi
    done < <(find "$PROJECT_ROOT/.claude/scripts" -type f -name '*.sh' 2>/dev/null)
    if (( ${#failures[@]} > 0 )); then
        echo "Scripts failing bash -n:" >&2
        printf '  %s\n' "${failures[@]}" >&2
        return 1
    fi
}
