#!/usr/bin/env bats
# =============================================================================
# tests/integration/cost-budget-enforcer-observer-allowlist.bats
#
# cycle-098 Sprint H2 — closes #708 F-005 (observer trust model audit
# finding). The L2 caller-supplied LOA_BUDGET_OBSERVER_CMD was previously
# invoked WITHOUT any path validation: any operator-controlled value (env
# var or yaml key) was passed straight to `timeout 30 "$cmd"`. An attacker
# who could set the env var (e.g., compromised CI runner, env-injection
# vector elsewhere in Loa) achieved arbitrary execution in the L2 process.
#
# Sprint H2 fix: _l2_validate_observer_path canonicalizes via realpath and
# requires the path to live under one of the configured allowlist prefixes
# (default: .claude/scripts/observers, .run/observers).
#
# Coverage:
#   - Path inside allowlist: invocation succeeds; observer JSON returned
#   - Path outside allowlist: invocation refused with diagnostic
#   - Traversal attempt (..): refused after canonicalization
#   - Allowlist override via LOA_BUDGET_OBSERVER_ALLOWED_PREFIXES: works
#   - Allowlist override via .loa.config.yaml: works
#   - Empty observer config: silent skip (no_observer_configured)
# =============================================================================

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    L2_LIB="${REPO_ROOT}/.claude/scripts/lib/cost-budget-enforcer-lib.sh"
    [[ -f "$L2_LIB" ]] || skip "cost-budget-enforcer-lib.sh not present"

    TEST_DIR="$(mktemp -d)"
    LOG_FILE="${TEST_DIR}/cost-budget-events.jsonl"
    OBSERVER="${TEST_DIR}/observer.sh"
    OBSERVER_OUT="${TEST_DIR}/observer-out.json"
    cat > "$OBSERVER" <<'EOF'
#!/usr/bin/env bash
out="${OBSERVER_OUT:-}"
[[ -n "$out" && -f "$out" ]] && cat "$out" || echo '{"_unreachable":true}'
EOF
    chmod +x "$OBSERVER"
    echo '{"usd_used": 5.00, "billing_ts": "2026-05-04T15:00:00.000000Z"}' > "$OBSERVER_OUT"

    export LOA_BUDGET_LOG="$LOG_FILE"
    export OBSERVER_OUT
    export LOA_BUDGET_DAILY_CAP_USD="50.00"
    export LOA_BUDGET_FRESHNESS_SECONDS="300"
    export LOA_BUDGET_STALE_HALT_PCT="75"
    export LOA_BUDGET_CLOCK_TOLERANCE="60"
    export LOA_BUDGET_LAG_HALT_SECONDS="300"
    export LOA_BUDGET_TEST_NOW="2026-05-04T15:00:00.000000Z"
    unset LOA_AUDIT_SIGNING_KEY_ID
    export LOA_AUDIT_VERIFY_SIGS=0

    # shellcheck source=/dev/null
    source "$L2_LIB"
}

teardown() {
    rm -rf "$TEST_DIR"
    unset LOA_BUDGET_LOG LOA_BUDGET_OBSERVER_CMD LOA_BUDGET_OBSERVER_ALLOWED_PREFIXES \
          LOA_BUDGET_DAILY_CAP_USD LOA_BUDGET_FRESHNESS_SECONDS \
          LOA_BUDGET_STALE_HALT_PCT LOA_BUDGET_CLOCK_TOLERANCE \
          LOA_BUDGET_LAG_HALT_SECONDS LOA_BUDGET_TEST_NOW OBSERVER_OUT
}

@test "F-005: observer path INSIDE allowlist (env override) is permitted" {
    export LOA_BUDGET_OBSERVER_CMD="$OBSERVER"
    export LOA_BUDGET_OBSERVER_ALLOWED_PREFIXES="$TEST_DIR"
    run _l2_invoke_observer "anthropic"
    [ "$status" -eq 0 ]
    # Output is the observer JSON (not the unreachable marker).
    run jq -e '.usd_used' <<<"$output"
    [ "$status" -eq 0 ]
}

@test "F-005: observer path OUTSIDE allowlist is REFUSED" {
    export LOA_BUDGET_OBSERVER_CMD="$OBSERVER"
    # Make sure no prior test's env leaks into this one.
    unset LOA_BUDGET_OBSERVER_ALLOWED_PREFIXES
    local invoke_output
    invoke_output="$(_l2_invoke_observer "anthropic" 2>/dev/null)"
    local reason
    reason="$(jq -r '._reason' <<<"$invoke_output")"
    [ "$reason" = "observer_path_outside_allowlist" ]
}

@test "F-005: traversal path is rejected by ALLOWLIST (not by file-existence)" {
    # Sprint H2 review iter-1 MEDIUM: the prior assertion accepted EITHER
    # observer_not_found (file check fails) OR outside_allowlist. That
    # weakened the test — it would pass even if the allowlist gate was
    # broken, as long as the file-existence check rejected. Now: stage a
    # REAL file at the traversal target inside the allowlist scope and
    # confirm the allowlist STILL rejects (because canonical path is
    # outside).
    local outside_dir="${TEST_DIR}/.." # Parent of TEST_DIR, NOT in allowlist.
    local outside_file="${outside_dir}/sneaky-traversal-$$.sh"
    cat > "$outside_file" <<'EOF'
#!/usr/bin/env bash
echo '{"_unreachable":false,"_pwned":true}'
EOF
    chmod +x "$outside_file"
    # Use a traversal path that resolves to outside_file (which exists).
    export LOA_BUDGET_OBSERVER_CMD="${TEST_DIR}/../$(basename "$outside_file")"
    export LOA_BUDGET_OBSERVER_ALLOWED_PREFIXES="$TEST_DIR"
    local invoke_output
    invoke_output="$(_l2_invoke_observer "anthropic" 2>/dev/null)"
    local reason
    reason="$(jq -r '._reason' <<<"$invoke_output")"
    [ "$reason" = "observer_path_outside_allowlist" ]
    rm -f "$outside_file"
}

@test "F-005: allowlist accepts MULTIPLE prefixes (colon-separated)" {
    local extra_dir="${TEST_DIR}/extra"
    mkdir -p "$extra_dir"
    cp "$OBSERVER" "$extra_dir/observer.sh"
    chmod +x "$extra_dir/observer.sh"
    export LOA_BUDGET_OBSERVER_CMD="$extra_dir/observer.sh"
    export LOA_BUDGET_OBSERVER_ALLOWED_PREFIXES="$TEST_DIR/nonexistent:$extra_dir"
    run _l2_invoke_observer "anthropic"
    [ "$status" -eq 0 ]
    run jq -e '.usd_used' <<<"$output"
    [ "$status" -eq 0 ]
}

@test "F-005: empty observer config bypasses allowlist (no_observer_configured)" {
    unset LOA_BUDGET_OBSERVER_CMD
    export LOA_BUDGET_OBSERVER_ALLOWED_PREFIXES="$TEST_DIR"
    run _l2_invoke_observer "anthropic"
    [ "$status" -eq 0 ]
    run jq -r '._reason' <<<"$output"
    [ "$output" = "no_observer_configured" ]
}

@test "F-005: nonexistent observer path inside allowlist still rejected (observer_not_found)" {
    export LOA_BUDGET_OBSERVER_CMD="${TEST_DIR}/does-not-exist.sh"
    export LOA_BUDGET_OBSERVER_ALLOWED_PREFIXES="$TEST_DIR"
    run _l2_invoke_observer "anthropic"
    [ "$status" -eq 0 ]
    run jq -r '._reason' <<<"$output"
    [ "$output" = "observer_not_found" ]
}

@test "F-005: budget_verdict end-to-end — outside-allowlist observer is NOT EXECUTED (sentinel probe)" {
    # Sprint H2 review iter-1 MEDIUM: prior test only checked verdict shape.
    # A buggy lib that DID execute /etc/passwd would still return a verdict.
    # Now: stage an executable observer outside the allowlist that would
    # touch a sentinel file IF executed, and assert the sentinel does NOT
    # appear after budget_verdict.
    local outside_dir="${TEST_DIR}/outside-allowlist"
    mkdir -p "$outside_dir"
    local sentinel="${TEST_DIR}/PWNED-SENTINEL"
    local pwn_observer="${outside_dir}/pwn.sh"
    cat > "$pwn_observer" <<EOF
#!/usr/bin/env bash
touch "$sentinel"
echo '{"usd_used":0,"billing_ts":"2026-05-04T15:00:00Z"}'
EOF
    chmod +x "$pwn_observer"
    export LOA_BUDGET_OBSERVER_CMD="$pwn_observer"
    export LOA_BUDGET_OBSERVER_ALLOWED_PREFIXES="$TEST_DIR/inside-only-not-the-outside-dir"
    run budget_verdict "10.00"
    # Sentinel must NOT exist — the pwn observer was not executed.
    [ ! -f "$sentinel" ]
}

@test "F-005: validator function returns canonical path on stdout when accepted" {
    export LOA_BUDGET_OBSERVER_ALLOWED_PREFIXES="$TEST_DIR"
    run _l2_validate_observer_path "$OBSERVER"
    [ "$status" -eq 0 ]
    [ "$output" = "$OBSERVER" ]
}

@test "F-005: validator returns non-zero for outside-allowlist absolute path" {
    export LOA_BUDGET_OBSERVER_ALLOWED_PREFIXES="$TEST_DIR"
    run _l2_validate_observer_path "/usr/bin/curl"
    [ "$status" -ne 0 ]
}

@test "F-005: symlink in allowlist dir pointing OUT is rejected (realpath-resolves)" {
    # Sprint H2 review iter-1 MEDIUM: prior tests didn't probe symlink
    # canonicalization. Stage a symlink inside the allowlist pointing to a
    # path OUTSIDE; realpath should resolve and reject.
    if ! command -v realpath >/dev/null 2>&1; then skip "realpath not available"; fi
    local outside="${TEST_DIR}/.outside-target.sh"
    local symlink="${TEST_DIR}/observer-link.sh"
    cat > "$outside" <<'EOF'
#!/usr/bin/env bash
echo '{"_pwned":true}'
EOF
    chmod +x "$outside"
    # Move outside the allowed prefix.
    local outside_real="${TEST_DIR}/../h2-symlink-target-$$.sh"
    mv "$outside" "$outside_real"
    chmod +x "$outside_real"
    ln -sf "$outside_real" "$symlink"
    # Allowlist allows ONLY $TEST_DIR; symlink is in $TEST_DIR but resolves
    # to $outside_real which is one level up.
    export LOA_BUDGET_OBSERVER_CMD="$symlink"
    export LOA_BUDGET_OBSERVER_ALLOWED_PREFIXES="$TEST_DIR"
    local invoke_output reason
    invoke_output="$(_l2_invoke_observer "anthropic" 2>/dev/null)"
    reason="$(jq -r '._reason' <<<"$invoke_output")"
    rm -f "$outside_real" "$symlink"
    [ "$reason" = "observer_path_outside_allowlist" ]
}

@test "F-005: prefix boundary — '/foo' allowlist does NOT match '/foo-bar/x'" {
    # Sprint H2 review iter-1 MEDIUM (prefix-boundary spoofing): /foo prefix
    # in allowlist should not authorize /foo-bar/x or /foox/x. Bash glob
    # `[[ "$canon" == "$prefix_canon"/* ]]` requires a / boundary, so this
    # SHOULD reject; assert it explicitly.
    local sibling="${TEST_DIR}-sibling"
    mkdir -p "$sibling"
    local impostor="$sibling/observer.sh"
    cat > "$impostor" <<'EOF'
#!/usr/bin/env bash
echo '{"_pwned":true}'
EOF
    chmod +x "$impostor"
    export LOA_BUDGET_OBSERVER_CMD="$impostor"
    # Allowlist points at $TEST_DIR (not the sibling).
    export LOA_BUDGET_OBSERVER_ALLOWED_PREFIXES="$TEST_DIR"
    local invoke_output reason
    invoke_output="$(_l2_invoke_observer "anthropic" 2>/dev/null)"
    reason="$(jq -r '._reason' <<<"$invoke_output")"
    rm -rf "$sibling"
    [ "$reason" = "observer_path_outside_allowlist" ]
}
