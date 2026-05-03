#!/usr/bin/env bats
# =============================================================================
# tests/security/hitl-jury-panel-argv-safety.bats — issue #692
#
# sprint-bug-141 (T2+T3 hardening). Pre-fix: hitl-jury-panel-lib.sh
# panel_solicit invokes `model-invoke --prompt "$(cat "$context_path")"`
# which puts the entire prompt content on argv. Briefly visible in
# `ps aux` between fork+exec; sensitive context (e.g., panel deliberation
# input) leaks to anyone with /proc read access.
#
# Post-fix: switch to `model-invoke --input <tmpfile>` so prompt content
# only ever transits a mode-0600 file, never argv. Mirrors the
# sprint-bug-131 cheval HTTP/2 + argv-safety pattern that closed #675.
# =============================================================================

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT_REAL="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    PANEL_LIB="$PROJECT_ROOT_REAL/.claude/scripts/lib/hitl-jury-panel-lib.sh"

    [[ -f "$PANEL_LIB" ]] || skip "hitl-jury-panel-lib.sh not present"

    TEST_DIR="$(mktemp -d)"
    BIN_DIR="$TEST_DIR/bin"
    mkdir -p "$BIN_DIR"
    ARGV_LOG="$TEST_DIR/argv.log"
    INPUT_LOG="$TEST_DIR/input.log"
    export ARGV_LOG INPUT_LOG

    # Stub model-invoke captures argv + (if --input passed) the file content.
    # Argv is written verbatim as a single line per invocation. The post-fix
    # invocation should NOT include the prompt content on argv.
    cat > "$BIN_DIR/model-invoke" <<'SHIM'
#!/usr/bin/env bash
# Capture every arg as one quoted line so the test can grep without ambiguity.
{
    for a in "$@"; do
        printf '%s\n' "$a"
    done
    printf '---END---\n'
} >> "$ARGV_LOG"
# When --input <file> is used, also capture the file's content (so we can
# verify the lib actually populated the tmpfile correctly).
input_path=""
seen_input=false
for arg in "$@"; do
    if [[ "$seen_input" == "true" ]]; then
        input_path="$arg"
        break
    fi
    [[ "$arg" == "--input" ]] && seen_input=true
done
if [[ -n "$input_path" && -f "$input_path" ]]; then
    cat "$input_path" >> "$INPUT_LOG"
    printf '---END---\n' >> "$INPUT_LOG"
fi
# Emit a valid JSON view so the panel function doesn't error.
printf '{"view":"OK","reasoning_summary":"stub"}\n'
exit 0
SHIM
    chmod +x "$BIN_DIR/model-invoke"

    export PATH="$BIN_DIR:$PATH"
    export LOA_PANEL_TEST_INVOKE_DIR="$TEST_DIR/invoke"
    mkdir -p "$LOA_PANEL_TEST_INVOKE_DIR"
}

teardown() {
    cd /
    [[ -d "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}

# -----------------------------------------------------------------------------
# Pre-fix this test FAILS: prompt content is on argv via --prompt "$(cat ...)".
# Post-fix: prompt content goes through --input <tmpfile>; argv carries only
# the tmpfile path, not the content.
# -----------------------------------------------------------------------------
@test "argv-safety: prompt content is NOT exposed on model-invoke argv" {
    # Source the lib in a subshell with stub PATH.
    local context_path="$TEST_DIR/context.txt"
    # Choose a recognizable secret marker that should NEVER show up on argv.
    local secret_marker="LOA_ARGV_LEAK_CANARY_$(date +%s)"
    printf 'Confidential panel deliberation content. %s\n' "$secret_marker" > "$context_path"

    # Invoke panel_solicit (via the lib's source).
    # panel_solicit signature: (panelist_id, model, persona_path, context_path, [--timeout N])
    run bash -c "
        source '$PANEL_LIB'
        # Persona path can be empty/dummy (lib reads it but doesn't fail on empty).
        persona='$TEST_DIR/persona.md'; printf 'You are a panelist.' > \"\$persona\"
        panel_solicit 'panelist-A' 'claude-test-stub' \"\$persona\" '$context_path' --timeout 5 || true
    "
    [[ "$status" -eq 0 ]] || {
        echo "panel_solicit failed: $output"
        echo "--- argv log ---"
        cat "$ARGV_LOG" 2>/dev/null
        return 1
    }

    [[ -f "$ARGV_LOG" ]] || {
        echo "model-invoke stub never invoked"
        return 1
    }

    # Argv MUST NOT contain the secret marker. Pre-fix, --prompt \"\$(cat ...)\"
    # places the entire prompt body on argv → secret marker present.
    if grep -qF "$secret_marker" "$ARGV_LOG"; then
        echo "ERROR: secret marker leaked to argv (issue #692 not fixed)"
        echo "--- argv log ---"
        cat "$ARGV_LOG"
        return 1
    fi
}

@test "argv-safety: prompt content IS reachable via --input <tmpfile>" {
    local context_path="$TEST_DIR/context.txt"
    local secret_marker="LOA_INPUT_REACHABLE_$(date +%s)"
    printf 'Panel context. %s\n' "$secret_marker" > "$context_path"

    run bash -c "
        source '$PANEL_LIB'
        persona='$TEST_DIR/persona.md'; printf 'You are a panelist.' > \"\$persona\"
        panel_solicit 'panelist-A' 'claude-test-stub' \"\$persona\" '$context_path' --timeout 5 || true
    "
    [[ "$status" -eq 0 ]]

    # Post-fix uses --input → INPUT_LOG should contain the secret marker
    # (proving the prompt content was successfully passed via the file path).
    [[ -f "$INPUT_LOG" ]] || {
        echo "model-invoke was not called with --input <file>"
        echo "--- argv log ---"
        cat "$ARGV_LOG"
        return 1
    }
    grep -qF "$secret_marker" "$INPUT_LOG" || {
        echo "Prompt content not delivered via --input file"
        echo "--- input log ---"
        cat "$INPUT_LOG"
        return 1
    }
}

@test "argv-safety: --input flag is on argv (not --prompt)" {
    local context_path="$TEST_DIR/context.txt"
    printf 'short context\n' > "$context_path"

    run bash -c "
        source '$PANEL_LIB'
        persona='$TEST_DIR/persona.md'; printf 'You are a panelist.' > \"\$persona\"
        panel_solicit 'panelist-A' 'claude-test-stub' \"\$persona\" '$context_path' --timeout 5 || true
    "
    [[ "$status" -eq 0 ]]
    [[ -f "$ARGV_LOG" ]]

    grep -qF -- '--input' "$ARGV_LOG" || {
        echo "Expected --input on argv (post-fix); got:"
        cat "$ARGV_LOG"
        return 1
    }
    if grep -qF -- '--prompt' "$ARGV_LOG"; then
        echo "ERROR: --prompt still on argv (pre-fix pattern)"
        cat "$ARGV_LOG"
        return 1
    fi
}
