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
@test "G-2: no exec {var}>{>,<,<>}file named-fd patterns in .claude/scripts/" {
    # Broadened regex (Bridgebuilder F5): cover all redirection directions
    # (`>`, `<`, `<>`) and digit-suffixed identifiers (`exec {fd1}>...`).
    # Without the digit class, names like `_lock_fd0` slipped past the gate.
    # NOTE: the EXCLUDE array below is documentation-only — no test fixtures
    # currently need to assert the forbidden pattern, so there is no skip-path
    # to plumb. If a future test ever needs to embed `exec {var}>...` literally
    # (for a portability negative-fixture), list its path here AND add a path
    # filter to the grep invocation. We chose not to wire one preemptively
    # because adding unused machinery makes the gate harder to reason about.
    local -a EXCLUDE=()
    local matches
    matches="$(grep -rnE 'exec[[:space:]]+\{[a-zA-Z_][a-zA-Z0-9_]*\}[<>]' "$PROJECT_ROOT/.claude/scripts/" 2>/dev/null || true)"
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
    matches="$(grep -rnE 'exec[[:space:]]+\{[a-zA-Z_][a-zA-Z0-9_]*\}>>' "$PROJECT_ROOT/.claude/scripts/" 2>/dev/null || true)"
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

# -----------------------------------------------------------------------------
# G-2 (Bridgebuilder F-002): the bash -n check above runs against the host's
# bash. On Linux CI that is bash 5+, which accepts every bash 4-only feature
# the gate is meant to catch (associative arrays, [[ -v var ]], ${var^^},
# globstar, etc.). To exercise the actual portability target, locate a 3.2
# binary (macOS /bin/bash, or LOA_BASH32_PATH override) and re-run -n there.
# When no 3.2 binary is reachable the test emits a loud `skip` so the gap is
# visible in the test output rather than silently green.
# -----------------------------------------------------------------------------
@test "G-2: all .claude/scripts/ pass bash 3.2 -n syntax check (when 3.2 available)" {
    local bash32="${LOA_BASH32_PATH:-}"

    # macOS ships bash 3.2.57 at /bin/bash. Auto-detect when the override
    # is unset.
    if [[ -z "$bash32" && -x /bin/bash ]]; then
        local v
        v="$(/bin/bash -c 'echo $BASH_VERSION' 2>/dev/null || true)"
        case "$v" in
            3.2*) bash32="/bin/bash" ;;
        esac
    fi

    if [[ -z "$bash32" ]]; then
        skip "bash 3.2 not available on host; export LOA_BASH32_PATH=/path/to/bash3.2 to run this gate"
    fi

    local failures=()
    while IFS= read -r script; do
        if ! "$bash32" -n "$script" 2>/dev/null; then
            failures+=("$script")
        fi
    done < <(find "$PROJECT_ROOT/.claude/scripts" -type f -name '*.sh' 2>/dev/null)
    if (( ${#failures[@]} > 0 )); then
        echo "Scripts failing bash 3.2 -n ($bash32):" >&2
        printf '  %s\n' "${failures[@]}" >&2
        return 1
    fi
}
