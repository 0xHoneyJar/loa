#!/usr/bin/env bats
# cycle-103 sprint-1 T1.6 — unit tests for call_flatline_chat in
# .claude/scripts/lib-curl-fallback.sh.
#
# The helper is the single chokepoint flatline-*.sh scripts use to route
# chat/completion calls through model-invoke (cheval) instead of direct
# OpenAI / Anthropic curl. These tests pin the helper's contract:
#   - argv validation (missing args → return 2)
#   - happy path: model-invoke succeeds → content surfaces on stdout
#   - error path: model-invoke fails → exit code propagates, stderr message
#   - temp-file cleanup: no /tmp leftovers after happy or error paths
#   - fixture-mode round-trip: real cheval.py with --mock-fixture-dir
#
# The fixture-mode test confirms the T1.6 dispatch reaches the same cheval
# substrate the T1.2 + T1.5 work landed.

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    LIB="$PROJECT_ROOT/.claude/scripts/lib-curl-fallback.sh"

    # Sanity check the lib file exists.
    [[ -f "$LIB" ]] || skip "lib-curl-fallback.sh not found at $LIB"

    # Per-test sandbox for temp files we want to inspect.
    TMP_DIR="$(mktemp -d)"
    export TMP_DIR

    # Track temp files at start so we can detect leaks.
    BEFORE_TMP_COUNT=$(find /tmp -maxdepth 1 -name "tmp.*" -newer /dev/null 2>/dev/null | wc -l)
}

teardown() {
    rm -rf "$TMP_DIR"
}

# Source the helper into the bats shell.
_source_helper() {
    # shellcheck disable=SC1090
    source "$LIB"
}

# --------------------------------------------------------------------------
# Argv validation
# --------------------------------------------------------------------------

@test "call_flatline_chat rejects missing model" {
    _source_helper
    run call_flatline_chat "" "some prompt" "30" "500"
    [ "$status" -eq 2 ]
    [[ "$output" == *"requires (model, prompt, timeout)"* ]]
}

@test "call_flatline_chat rejects missing prompt" {
    _source_helper
    run call_flatline_chat "claude-opus-4-7" "" "30" "500"
    [ "$status" -eq 2 ]
    [[ "$output" == *"requires (model, prompt, timeout)"* ]]
}

@test "call_flatline_chat rejects missing timeout" {
    _source_helper
    run call_flatline_chat "claude-opus-4-7" "prompt" "" "500"
    [ "$status" -eq 2 ]
    [[ "$output" == *"requires (model, prompt, timeout)"* ]]
}

# --------------------------------------------------------------------------
# Happy path with stub model-invoke
# --------------------------------------------------------------------------

@test "call_flatline_chat returns content text on success" {
    # Stub model-invoke that prints a known content string and exits 0.
    cat > "$TMP_DIR/model-invoke-stub" <<'STUB'
#!/usr/bin/env bash
# Capture argv for assertion if the test wants to inspect it.
echo "$@" >> "${STUB_ARGV_LOG:-/dev/null}"
echo "## Findings\n- Looks fine."
exit 0
STUB
    chmod +x "$TMP_DIR/model-invoke-stub"

    # Override _MODEL_INVOKE before sourcing — the helper uses this var.
    MODEL_INVOKE="$TMP_DIR/model-invoke-stub" _source_helper

    run call_flatline_chat "claude-opus-4-7" "review this" "30" "500"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Looks fine"* ]]
}

@test "call_flatline_chat passes correct argv shape to model-invoke" {
    # Stub captures argv for inspection.
    cat > "$TMP_DIR/model-invoke-stub" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$STUB_ARGV_LOG"
echo "content"
exit 0
STUB
    chmod +x "$TMP_DIR/model-invoke-stub"
    export STUB_ARGV_LOG="$TMP_DIR/argv.txt"

    MODEL_INVOKE="$TMP_DIR/model-invoke-stub" _source_helper
    call_flatline_chat "gpt-4o-mini" "the prompt" "30" "500" > /dev/null

    [[ -f "$STUB_ARGV_LOG" ]]
    grep -qx -- "--agent" "$STUB_ARGV_LOG"
    grep -qx -- "flatline-reviewer" "$STUB_ARGV_LOG"
    grep -qx -- "--model" "$STUB_ARGV_LOG"
    grep -qx -- "gpt-4o-mini" "$STUB_ARGV_LOG"
    grep -qx -- "--output-format" "$STUB_ARGV_LOG"
    grep -qx -- "text" "$STUB_ARGV_LOG"
    grep -qx -- "--json-errors" "$STUB_ARGV_LOG"
    grep -qx -- "--max-tokens" "$STUB_ARGV_LOG"
    grep -qx -- "500" "$STUB_ARGV_LOG"
    grep -qx -- "--timeout" "$STUB_ARGV_LOG"
    grep -qx -- "30" "$STUB_ARGV_LOG"
}

@test "call_flatline_chat AC-1.8: prompt content is NOT passed via argv" {
    # The prompt may contain provider secrets in real flatline use; the helper
    # MUST write the prompt to a temp file passed via --input, never inline as
    # argv. Pin this behavior.
    cat > "$TMP_DIR/model-invoke-stub" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$STUB_ARGV_LOG"
echo "content"
exit 0
STUB
    chmod +x "$TMP_DIR/model-invoke-stub"
    export STUB_ARGV_LOG="$TMP_DIR/argv.txt"

    MODEL_INVOKE="$TMP_DIR/model-invoke-stub" _source_helper

    local secret="sk-ant-test-do-not-leak-AAAA"
    call_flatline_chat "claude-opus-4-7" "$secret in prompt" "30" "500" > /dev/null

    # The secret must NOT appear anywhere in argv.
    ! grep -qF "$secret" "$STUB_ARGV_LOG"
}

# --------------------------------------------------------------------------
# Error path
# --------------------------------------------------------------------------

@test "call_flatline_chat propagates non-zero exit code" {
    cat > "$TMP_DIR/model-invoke-stub" <<'STUB'
#!/usr/bin/env bash
echo '{"code":"RATE_LIMITED","message":"x"}' >&2
exit 1
STUB
    chmod +x "$TMP_DIR/model-invoke-stub"

    MODEL_INVOKE="$TMP_DIR/model-invoke-stub" _source_helper

    run call_flatline_chat "claude-opus-4-7" "p" "30" "500"
    [ "$status" -eq 1 ]
    [[ "$output" == *"model-invoke failed"* ]]
}

@test "call_flatline_chat returns non-zero when model-invoke binary missing" {
    MODEL_INVOKE="$TMP_DIR/no-such-binary" _source_helper
    run call_flatline_chat "claude-opus-4-7" "p" "30" "500"
    [ "$status" -ne 0 ]
}

# --------------------------------------------------------------------------
# Temp-file cleanup
# --------------------------------------------------------------------------

@test "call_flatline_chat cleans up its --input tempfile on success" {
    # Stub records the --input path so we can verify it's removed afterward.
    cat > "$TMP_DIR/model-invoke-stub" <<'STUB'
#!/usr/bin/env bash
# Find --input <path> in argv, copy the path to LOG.
prev=""
for arg in "$@"; do
    if [[ "$prev" == "--input" ]]; then
        echo "$arg" > "$STUB_INPUT_PATH_LOG"
        break
    fi
    prev="$arg"
done
echo "ok"
exit 0
STUB
    chmod +x "$TMP_DIR/model-invoke-stub"
    export STUB_INPUT_PATH_LOG="$TMP_DIR/input-path.txt"

    MODEL_INVOKE="$TMP_DIR/model-invoke-stub" _source_helper
    call_flatline_chat "claude-opus-4-7" "the prompt body" "30" "500" > /dev/null

    [[ -s "$STUB_INPUT_PATH_LOG" ]]
    local recorded_path
    recorded_path=$(cat "$STUB_INPUT_PATH_LOG")
    [[ ! -e "$recorded_path" ]]
}

@test "call_flatline_chat cleans up its --input tempfile on error" {
    cat > "$TMP_DIR/model-invoke-stub" <<'STUB'
#!/usr/bin/env bash
prev=""
for arg in "$@"; do
    if [[ "$prev" == "--input" ]]; then
        echo "$arg" > "$STUB_INPUT_PATH_LOG"
        break
    fi
    prev="$arg"
done
echo "boom" >&2
exit 5
STUB
    chmod +x "$TMP_DIR/model-invoke-stub"
    export STUB_INPUT_PATH_LOG="$TMP_DIR/input-path.txt"

    MODEL_INVOKE="$TMP_DIR/model-invoke-stub" _source_helper
    call_flatline_chat "claude-opus-4-7" "the prompt body" "30" "500" >/dev/null 2>&1 || true

    [[ -s "$STUB_INPUT_PATH_LOG" ]]
    local recorded_path
    recorded_path=$(cat "$STUB_INPUT_PATH_LOG")
    [[ ! -e "$recorded_path" ]]
}

# --------------------------------------------------------------------------
# Fixture-mode end-to-end (closes the loop with T1.5)
# --------------------------------------------------------------------------

@test "call_flatline_chat round-trip via real cheval.py --mock-fixture-dir" {
    if ! command -v python3 >/dev/null 2>&1; then
        skip "python3 not on PATH"
    fi
    local cheval="$PROJECT_ROOT/.claude/adapters/cheval.py"
    [[ -f "$cheval" ]] || skip "cheval.py not found"

    local fixture_dir="$TMP_DIR/fixture"
    mkdir -p "$fixture_dir"
    cat > "$fixture_dir/response.json" <<'EOF'
{
  "content": "## E2E\nfixture content reached the flatline helper.",
  "usage": {"input_tokens": 5, "output_tokens": 7}
}
EOF

    # Wrap cheval.py + --mock-fixture-dir into a shim that call_flatline_chat
    # can invoke as if it were the model-invoke binary.
    cat > "$TMP_DIR/model-invoke-shim" <<SHIM
#!/usr/bin/env bash
exec python3 "$cheval" "\$@" --mock-fixture-dir "$fixture_dir"
SHIM
    chmod +x "$TMP_DIR/model-invoke-shim"

    MODEL_INVOKE="$TMP_DIR/model-invoke-shim" _source_helper

    run call_flatline_chat "claude-opus-4.7" "review this PR" "30" "500"
    [ "$status" -eq 0 ]
    [[ "$output" == *"E2E"* ]]
    [[ "$output" == *"fixture content reached the flatline helper"* ]]
}
