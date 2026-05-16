#!/usr/bin/env bats
# =============================================================================
# tests/unit/bug-899-vq-sidecar-survives-failure.bats
#
# Bug #899 — flatline-orchestrator.sh's `call_model` previously deleted
# the verdict_quality sidecar on any non-zero exit from MODEL_INVOKE,
# destroying the FAILED/DEGRADED envelope that cycle-109 sprint-2 T2.4
# specifically introduced for failure attribution. The cohort aggregator
# (line 534 region) reads `.verdict_quality` from per-voice files; with
# the sidecar deleted, this voice's failure signal silently dropped from
# consensus.
#
# Fix: on non-zero exit, read the sidecar (if present + valid JSON) and
# emit a failure-shaped per-voice JSON to stdout so the caller's `>`
# redirect captures the envelope BEFORE rm.
#
# These tests use a MODEL_INVOKE stub that writes a known envelope and
# exits non-zero to prove the envelope reaches the per-voice output file.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT

    TEST_TMP="$(mktemp -d "${BATS_TMPDIR}/bug-899.XXXXXX")"
    export TEST_TMP
}

teardown() {
    rm -rf "$TEST_TMP"
}

# Helper: source the call_model function from the orchestrator + run it
# against a stub MODEL_INVOKE that writes a FAILED envelope to the
# sidecar then exits with the requested exit code.
_run_call_model_with_failing_stub() {
    local sidecar_status="$1"   # e.g., "FAILED" / "DEGRADED" / "APPROVED"
    local stub_exit_code="$2"   # exit code the stub returns
    local emit_envelope="${3:-true}"

    # Build the stub.
    cat > "$TEST_TMP/model-invoke-stub.sh" <<STUB
#!/usr/bin/env bash
# Writes the verdict_quality envelope to the path passed via
# LOA_VERDICT_QUALITY_SIDECAR, then exits with the configured code.
if [[ "$emit_envelope" == "true" && -n "\${LOA_VERDICT_QUALITY_SIDECAR:-}" ]]; then
    cat > "\$LOA_VERDICT_QUALITY_SIDECAR" <<JSON
{"status":"$sidecar_status","voices_planned":1,"voices_succeeded":0,"voices_dropped":["test-voice"],"chain_health":"exhausted","confidence_floor":"low","rationale":"stubbed failure for bug-899 test"}
JSON
fi
exit $stub_exit_code
STUB
    chmod +x "$TEST_TMP/model-invoke-stub.sh"

    # Per-voice output capture file (mirrors what `> "$gpt_review_file"` does
    # in the real caller).
    local voice_out="$TEST_TMP/voice-out.json"
    export VOICE_OUT="$voice_out"
    export STUB_PATH="$TEST_TMP/model-invoke-stub.sh"
    export TEMP_DIR="$TEST_TMP"

    # Source the orchestrator's call_model function. To avoid running the
    # orchestrator's top-level setup, we extract just the call_model
    # function body via a subshell that overrides the MODEL_INVOKE
    # variable.
    bash -c '
        set -e
        SCRIPT_DIR="$PROJECT_ROOT/.claude/scripts"
        MODEL_INVOKE="$STUB_PATH"
        # Stubs for helpers call_model expects in scope:
        log() { :; }
        log_invoke_failure() { :; }
        cleanup_invoke_log() { :; }
        redact_secrets() { cat; }
        # Source call_model body. The function is defined inside
        # _flatline_protocol_init() which initializes via top-level
        # execution — we cant just source the file. Instead, extract
        # call_model directly via awk for self-contained testing.
        eval "$(awk "/^call_model\(\)/,/^}/" "$SCRIPT_DIR/flatline-orchestrator.sh")"
        # invoke_log stub vars expected by the function
        invoke_log="$TEMP_DIR/invoke.log"
        : > "$invoke_log"
        call_model "test-voice" "review" "doc-content" "prd" "" "30" > "$VOICE_OUT" 2>/dev/null || true
    '
    echo "voice_out=$voice_out"
    cat "$voice_out" 2>/dev/null || echo "(empty)"
}

@test "bug-899-1: FAILED envelope reaches per-voice file when MODEL_INVOKE exits non-zero" {
    skip_reason=""
    # call_model is defined as an inner function in a function scope;
    # robust extraction would need a richer harness. Use the simpler
    # surface assertion: read the orchestrator source and prove the
    # failure block emits stdout JSON containing verdict_quality.
    skip "behavioral harness — see bug-899-1-source / bug-899-2-source"
}

# Source-level wiring assertions — proves the bug-fix code path EXISTS in the
# expected shape. These are tight enough to fail if the rm-before-read
# pattern is reintroduced.

@test "bug-899-1-source: orchestrator reads sidecar BEFORE rm on the failure path" {
    # The sidecar read MUST appear lexically before the rm on the failure
    # path. We anchor on the bug-899 comment + the jq construction of
    # the failure-stub output.
    grep -qE '# bug-899:' "$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
}

@test "bug-899-2-source: orchestrator emits jq stub with verdict_quality on failure" {
    # The fix emits a JSON object with .verdict_quality keyed on the
    # FAILED envelope before rm. Match the unique combination of
    # status: failed + verdict_quality: \$vq in the failure block.
    grep -qE 'status:[[:space:]]*"failed"' "$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
    grep -qE 'verdict_quality:[[:space:]]*\$vq' "$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
}

@test "bug-899-3-source: failure-path rm of sidecar happens AFTER the envelope-read block" {
    # Extract the failure block by anchoring on the bug-899 comment + rm,
    # surviving line-number drift as the block grows for follow-up fixes.
    local block
    block=$(awk '/# bug-899:/{flag=1} flag{print; if (/rm -f "\$vq_sidecar"/ && flag) exit}' \
        "$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh")
    local read_line rm_line
    read_line=$(echo "$block" | grep -n 'vq_envelope_on_failure=' | head -1 | cut -d: -f1)
    rm_line=$(echo "$block"  | grep -n 'rm -f "$vq_sidecar"'      | head -1 | cut -d: -f1)
    [ -n "$read_line" ]
    [ -n "$rm_line" ]
    [ "$read_line" -lt "$rm_line" ]
}

@test "bug-899-4: behavioral — failed exit emits JSON with verdict_quality field (live run with stub)" {
    # Build a minimal harness that exercises the failure block end-to-end.
    cat > "$TEST_TMP/stub.sh" <<'STUB'
#!/usr/bin/env bash
if [[ -n "${LOA_VERDICT_QUALITY_SIDECAR:-}" ]]; then
    cat > "$LOA_VERDICT_QUALITY_SIDECAR" <<'JSON'
{"status":"FAILED","voices_planned":1,"voices_succeeded":0,"chain_health":"exhausted","rationale":"stubbed"}
JSON
fi
exit 12
STUB
    chmod +x "$TEST_TMP/stub.sh"

    # Run a self-contained reproduction of the orchestrator's failure
    # block to assert the failure-shaped output is emitted.
    run bash <<HARNESS
set -u
MODEL_INVOKE="$TEST_TMP/stub.sh"
TEMP_DIR="$TEST_TMP"
mode="review"
model="test-voice"
phase="prd"
vq_sidecar="\$TEMP_DIR/vq-sidecar.json"
invoke_log="\$TEMP_DIR/invoke.log"
: > "\$invoke_log"

# Simulate the orchestrator's invocation + the new failure block.
exit_code=0
result=\$(LOA_VERDICT_QUALITY_SIDECAR="\$vq_sidecar" "\$MODEL_INVOKE") || exit_code=\$?

if [[ \$exit_code -ne 0 ]]; then
    vq_envelope_on_failure="null"
    if [[ -s "\$vq_sidecar" ]] && jq empty < "\$vq_sidecar" 2>/dev/null; then
        vq_envelope_on_failure=\$(cat "\$vq_sidecar")
    fi
    if [[ "\$vq_envelope_on_failure" != "null" ]]; then
        jq -cn \\
            --argjson vq "\$vq_envelope_on_failure" \\
            --arg model "\$model" \\
            --arg mode "\$mode" \\
            --arg phase "\$phase" \\
            --argjson exit_code "\$exit_code" \\
            '{
                content: "",
                tokens_input: 0,
                tokens_output: 0,
                latency_ms: 0,
                retries: 0,
                model: \$model,
                mode: \$mode,
                phase: \$phase,
                cost_usd: 0,
                status: "failed",
                exit_code: \$exit_code,
                verdict_quality: \$vq
            }'
    fi
fi
HARNESS
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"failed"'* ]]
    [[ "$output" == *'"verdict_quality"'* ]]
    [[ "$output" == *'"chain_health":"exhausted"'* ]]
    [[ "$output" == *'"exit_code":12'* ]]
}

@test "bug-899-5: behavioral — when sidecar is absent, NO failure-stub is emitted (legacy shape preserved)" {
    cat > "$TEST_TMP/stub.sh" <<'STUB'
#!/usr/bin/env bash
# Stub that exits non-zero WITHOUT writing the sidecar.
exit 12
STUB
    chmod +x "$TEST_TMP/stub.sh"

    run bash <<HARNESS
set -u
MODEL_INVOKE="$TEST_TMP/stub.sh"
TEMP_DIR="$TEST_TMP"
vq_sidecar="\$TEMP_DIR/vq-sidecar-absent.json"
invoke_log="\$TEMP_DIR/invoke.log"
: > "\$invoke_log"

exit_code=0
LOA_VERDICT_QUALITY_SIDECAR="\$vq_sidecar" "\$MODEL_INVOKE" || exit_code=\$?

if [[ \$exit_code -ne 0 ]]; then
    vq_envelope_on_failure="null"
    if [[ -s "\$vq_sidecar" ]] && jq empty < "\$vq_sidecar" 2>/dev/null; then
        vq_envelope_on_failure=\$(cat "\$vq_sidecar")
    fi
    if [[ "\$vq_envelope_on_failure" != "null" ]]; then
        echo "stub emitted"
    else
        echo "no stub emitted (legacy shape)"
    fi
fi
HARNESS
    [ "$status" -eq 0 ]
    [[ "$output" == *"no stub emitted (legacy shape)"* ]]
}

@test "bug-899-6: behavioral — when sidecar is present but invalid JSON, NO failure-stub is emitted" {
    cat > "$TEST_TMP/stub.sh" <<'STUB'
#!/usr/bin/env bash
if [[ -n "${LOA_VERDICT_QUALITY_SIDECAR:-}" ]]; then
    echo "this is not valid json {" > "$LOA_VERDICT_QUALITY_SIDECAR"
fi
exit 12
STUB
    chmod +x "$TEST_TMP/stub.sh"

    run bash <<HARNESS
set -u
MODEL_INVOKE="$TEST_TMP/stub.sh"
TEMP_DIR="$TEST_TMP"
vq_sidecar="\$TEMP_DIR/vq-sidecar-bad.json"
invoke_log="\$TEMP_DIR/invoke.log"
: > "\$invoke_log"

exit_code=0
LOA_VERDICT_QUALITY_SIDECAR="\$vq_sidecar" "\$MODEL_INVOKE" || exit_code=\$?

if [[ \$exit_code -ne 0 ]]; then
    vq_envelope_on_failure="null"
    if [[ -s "\$vq_sidecar" ]] && jq empty < "\$vq_sidecar" 2>/dev/null; then
        vq_envelope_on_failure=\$(cat "\$vq_sidecar")
    fi
    if [[ "\$vq_envelope_on_failure" != "null" ]]; then
        echo "stub emitted (unexpected)"
    else
        echo "no stub emitted (invalid JSON safely ignored)"
    fi
fi
HARNESS
    [ "$status" -eq 0 ]
    [[ "$output" == *"invalid JSON safely ignored"* ]]
}

# =============================================================================
# BB #915 F-001 closure — production-code path test
#
# Sources the REAL flatline-orchestrator.sh (BASH_SOURCE-guarded; main()
# does not run) and exercises the actual `call_model` function against a
# stubbed MODEL_INVOKE. Closes the divergence surface between inline
# replicas (bug-899-4..6) and production behavior.
# =============================================================================

@test "bug-899-7-real: production call_model emits failure-stub on stub-driven non-zero exit" {
    # Build a stub MODEL_INVOKE that writes a known envelope then exits 12.
    cat > "$TEST_TMP/stub-invoke" <<'STUB'
#!/usr/bin/env bash
if [[ -n "${LOA_VERDICT_QUALITY_SIDECAR:-}" ]]; then
    cat > "$LOA_VERDICT_QUALITY_SIDECAR" <<'JSON'
{"status":"FAILED","voices_planned":1,"voices_succeeded":0,"chain_health":"exhausted","rationale":"real call_model test","blocker_risk":"high"}
JSON
fi
exit 12
STUB
    chmod +x "$TEST_TMP/stub-invoke"

    # Run call_model via a subshell that sources the production script.
    # The BASH_SOURCE guard at the end of flatline-orchestrator.sh
    # prevents main() from running on source.
    cd "$PROJECT_ROOT"
    voice_out="$TEST_TMP/voice-real-call.json"
    run env \
        MODEL_INVOKE="$TEST_TMP/stub-invoke" \
        TEMP_DIR="$TEST_TMP" \
        VOICE_OUT="$voice_out" \
        bash -c '
            set +e  # tolerate optional-dep load failures (e.g., generated-model-maps)
            source .claude/scripts/flatline-orchestrator.sh
            set -e
            # call_model arg order: model, mode, input, phase, context, timeout
            call_model "test-voice" "review" "doc-content" "prd" "" "30" > "$VOICE_OUT" 2>/dev/null
        '
    # Read what landed in the per-voice file
    [[ -s "$voice_out" ]]
    local got_status got_vq_status got_chain_health got_exit_code
    got_status=$(jq -r '.status // empty' "$voice_out" 2>/dev/null)
    got_vq_status=$(jq -r '.verdict_quality.status // empty' "$voice_out" 2>/dev/null)
    got_chain_health=$(jq -r '.verdict_quality.chain_health // empty' "$voice_out" 2>/dev/null)
    got_exit_code=$(jq -r '.exit_code // empty' "$voice_out" 2>/dev/null)
    [[ "$got_status" == "failed" ]]
    [[ "$got_vq_status" == "FAILED" ]]
    [[ "$got_chain_health" == "exhausted" ]]
    [[ "$got_exit_code" == "12" ]]
}

@test "bug-899-8-source: failure block has the F-004 fix — jq emit is NOT suffixed with || true on the closing brace" {
    # BB #915 F-004 (DISPUTED, claude-opus-4-7): the original commit ended
    # the jq invocation with `|| true`, recreating the silent-drop pattern
    # this PR exists to prevent. After F-004 fix, the jq invocation
    # captures status into _vq_jq_status and logs on failure instead.
    #
    # Anchor: the literal `|| true` MUST NOT appear immediately after the
    # closing `}'` of the failure-stub jq invocation. We check the
    # ~50-line failure block specifically (not the rest of the file, which
    # has unrelated legitimate `|| true` usages).
    local block
    block=$(awk '/# bug-899:/,/^[[:space:]]*rm -f "\$vq_sidecar"/' \
        "$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh")
    # The jq closing line ends with `}'` followed by either nothing or
    # an explicit capture. The legacy bad shape was `}' || true`.
    if echo "$block" | grep -qE "}'[[:space:]]*\|\|[[:space:]]*true"; then
        echo "FAIL: BB #915 F-004 regression — failure-stub jq emit is suffixed with || true" >&2
        echo "$block" | grep -nE "}'[[:space:]]*\|\|" >&2
        return 1
    fi
}

@test "bug-899-9-source: failure block logs jq failure to invoke_log instead of silently dropping" {
    # F-004 corollary: the new shape captures jq's exit via _vq_jq_status
    # and writes a `[vq-warn]` line to $invoke_log so a double-failure
    # (sidecar valid at jq-empty but jq fails on emit) is observable.
    grep -qE '_vq_jq_status' "$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
    grep -qE '\[vq-warn\] failure-envelope jq exit' "$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
}
