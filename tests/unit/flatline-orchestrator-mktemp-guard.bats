#!/usr/bin/env bats
# =============================================================================
# Issue #878 — flatline-orchestrator: chmod-on-empty-arg when mktemp fails
# =============================================================================
# Pins the contract that flatline-orchestrator.sh guards every `mktemp`
# assignment against failure (template collision, disk full, mktemp not on
# PATH) before downstream chmod/write operations. Without the guard, a
# failed mktemp produces an empty variable, and `chmod 600 ""` errors with
# "No such file or directory" that masks the real mktemp failure.
#
# Strategy: grep-level static check. The script's mktemp call sites at
# the verdict-quality (~L577) + arbiter-prompt (~L2282) sections are the
# documented historical hot spots. New unguarded mktemp sites should also
# be flagged at review time.
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    ORCHESTRATOR="$REPO_ROOT/.claude/scripts/flatline-orchestrator.sh"
    [[ -f "$ORCHESTRATOR" ]] || skip "flatline-orchestrator.sh not found"
}

@test "#878: arbiter_prompt_file mktemp is guarded against failure" {
    # The exact guard pattern: `if ! arbiter_prompt_file=$(mktemp); then`
    # followed (within the next ~5 lines) by a `continue` or `return`.
    # If a future PR reverts the guard to bare `arbiter_prompt_file=$(mktemp)`,
    # this test fails.
    grep -A1 "arbiter_prompt_file=" "$ORCHESTRATOR" \
        | grep -qE "if ! arbiter_prompt_file=\\\$\\(mktemp\\)" \
        || {
            echo "REGRESSION: arbiter_prompt_file mktemp is no longer guarded." >&2
            echo "See issue #878. Expected pattern:" >&2
            echo "    if ! arbiter_prompt_file=\$(mktemp); then" >&2
            return 1
        }
}

@test "#878: vq-input mktemp is guarded against failure" {
    # The verdict-quality temp file site at ~L577. Same shape.
    grep -B1 -A1 'mktemp.*vq-input' "$ORCHESTRATOR" \
        | grep -qE "if ! tmp=\\\$\\(mktemp" \
        || {
            echo "REGRESSION: vq-input mktemp is no longer guarded." >&2
            echo "See issue #878. Expected pattern:" >&2
            echo "    if ! tmp=\$(mktemp \"\${TEMP_DIR:-/tmp}/vq-input.XXXXXX.json\"); then" >&2
            return 1
        }
}

@test "#878: chmod-after-mktemp pattern is guarded" {
    # Narrower invariant than "all chmod must be guarded": specifically
    # the chmod-after-mktemp pattern. A `chmod NNN "$var"` line preceded
    # within 3 lines by `$var=$(mktemp...)` MUST have the mktemp itself
    # guarded by an `if !` or trailing `|| ...` clause; otherwise an
    # empty $var reaches chmod and produces the documented #878 error.
    #
    # Template-assigned vars (e.g., `var="$DIR/file.jsonl"`) don't need
    # this guard because string assignment can't fail to an empty value.
    while IFS=: read -r line _content; do
        local var_name
        var_name=$(sed -n "${line}p" "$ORCHESTRATOR" \
            | grep -oE 'chmod [0-9]+ "\$[A-Za-z_][A-Za-z0-9_]*"' \
            | grep -oE '\$[A-Za-z_][A-Za-z0-9_]*' \
            | tr -d '$' | head -1)
        [[ -z "$var_name" ]] && continue

        local start=$(( line > 3 ? line - 3 : 1 ))
        local end=$(( line - 1 ))
        local preceding_lines
        preceding_lines=$(sed -n "${start},${end}p" "$ORCHESTRATOR")

        # Is this chmod preceded by a mktemp assignment to the same var?
        if echo "$preceding_lines" | grep -qE "${var_name}=\\\$\\(.*mktemp"; then
            # mktemp assignment found — check it's guarded
            if echo "$preceding_lines" | grep -qE "(if ! ${var_name}=|${var_name}=\\\$\\(mktemp.*\\) \\|\\| )"; then
                continue  # guarded ✓
            fi
            echo "REGRESSION at line $line: chmod on $var_name follows unguarded mktemp" >&2
            echo "Add: if ! ${var_name}=\$(mktemp); then log ERROR; continue; fi" >&2
            return 1
        fi
    done < <(grep -n 'chmod [0-9]* "\$' "$ORCHESTRATOR")
}
