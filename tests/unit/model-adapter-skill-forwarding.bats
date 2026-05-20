#!/usr/bin/env bats
# =============================================================================
# Cycle-112 D-6 (#931) — model-adapter.sh forwards --skill to MODEL_INVOKE
# =============================================================================
# Pins the bash-side half of the D-6 contract: model-adapter.sh accepts
# --skill and propagates it to invoke_args. Paired with
# `cheval-calling-primitive-attribution.bats` which pins the Python-side
# half (cheval.cmd_invoke threads args.skill into calling_primitive).
#
# Strategy: replace MODEL_INVOKE with a shim that records its argv. Invoke
# model-adapter.sh with --skill, assert the shim received --skill in argv.
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    ADAPTER="$REPO_ROOT/.claude/scripts/model-adapter.sh"
    TMP_DIR="$(mktemp -d)"

    # Build a recording shim that captures argv to a file
    cat > "$TMP_DIR/model-invoke-shim" <<SHIM
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$TMP_DIR/argv.recorded"
# Emit a minimal model-invoke JSON envelope so model-adapter's
# downstream translate_output doesn't choke on empty input.
cat <<'JSON'
{"content": "ok", "model": "stub", "provider": "stub", "usage": {"input_tokens": 1, "output_tokens": 1}, "latency_ms": 1}
JSON
SHIM
    chmod +x "$TMP_DIR/model-invoke-shim"
    export MODEL_INVOKE="$TMP_DIR/model-invoke-shim"

    # Minimal input file
    INPUT_FILE="$TMP_DIR/input.txt"
    echo "test input" > "$INPUT_FILE"

    # Skip cache probe so we don't hit the real network
    export FLATLINE_MOCK_MODE=true
    export PROJECT_ROOT="$REPO_ROOT"
}

teardown() {
    rm -rf "$TMP_DIR"
}

@test "D-6 (bash): model-adapter.sh forwards --skill to MODEL_INVOKE argv" {
    # Use a model alias that exists in the config; --dry-run avoids the
    # full chain walk but still exercises the argv builder.
    run "$ADAPTER" \
        --model claude-opus-4-7 \
        --mode dissent \
        --input "$INPUT_FILE" \
        --skill "adversarial-review:review" \
        --dry-run

    # --dry-run path uses a different invocation, so for this test we need
    # the non-dry-run path. Re-run without --dry-run.
    run "$ADAPTER" \
        --model claude-opus-4-7 \
        --mode dissent \
        --input "$INPUT_FILE" \
        --skill "adversarial-review:review"

    [ -f "$TMP_DIR/argv.recorded" ]
    grep -qF -- "--skill" "$TMP_DIR/argv.recorded"
    grep -qF -- "adversarial-review:review" "$TMP_DIR/argv.recorded"
}

@test "D-6 (bash): model-adapter.sh omits --skill from MODEL_INVOKE argv when not supplied" {
    # Backward-compat: callers that don't pass --skill must produce
    # argv WITHOUT --skill (cheval falls back to --agent name).
    run "$ADAPTER" \
        --model claude-opus-4-7 \
        --mode dissent \
        --input "$INPUT_FILE"

    [ -f "$TMP_DIR/argv.recorded" ]
    ! grep -qF -- "--skill" "$TMP_DIR/argv.recorded"
}

@test "D-6 (bash): --skill arg with colon is preserved verbatim (no quoting damage)" {
    # The skill string "adversarial-review:audit" has a colon which is
    # safe in argv but a common source of shell-escape bugs. Pin that
    # it round-trips verbatim.
    run "$ADAPTER" \
        --model claude-opus-4-7 \
        --mode dissent \
        --input "$INPUT_FILE" \
        --skill "adversarial-review:audit"

    [ -f "$TMP_DIR/argv.recorded" ]
    grep -qFx -- "adversarial-review:audit" "$TMP_DIR/argv.recorded"
}
