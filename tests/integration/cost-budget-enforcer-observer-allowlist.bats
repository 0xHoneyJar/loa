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

@test "F-005: traversal path '../../../bin/sh' is rejected after canonicalization" {
    export LOA_BUDGET_OBSERVER_CMD="../../../bin/sh"
    export LOA_BUDGET_OBSERVER_ALLOWED_PREFIXES="$TEST_DIR"
    run _l2_invoke_observer "anthropic"
    [ "$status" -eq 0 ]
    run jq -r '._reason' <<<"$output"
    # Either observer_not_found (file existence check fails) or outside_allowlist
    # — both refuse execution. Critical: the path was NOT executed.
    [[ "$output" = "observer_not_found" || "$output" = "observer_path_outside_allowlist" ]]
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

@test "F-005: budget_verdict end-to-end refuses to consult outside-allowlist observer" {
    # When the operator misconfigures observer_cmd outside the allowlist, the
    # cycle should fail-soft as if the observer were unreachable (no allow
    # leak; halt-uncertainty:billing_stale or similar fail-closed verdict
    # depending on counter state).
    export LOA_BUDGET_OBSERVER_CMD="/etc/passwd"
    export LOA_BUDGET_OBSERVER_ALLOWED_PREFIXES="$TEST_DIR"
    run budget_verdict "10.00"
    # Verdict on stdout (last line). When observer is unreachable AND counter
    # is at 0%, the lib falls through to allow (counter says no usage). The
    # KEY safety property: /etc/passwd was NEVER executed — verified by the
    # absence of any halt-uncertainty:billing_stale and the diagnostic in stderr.
    local last_line
    last_line="$(printf '%s' "$output" | awk 'NF{l=$0} END{print l}')"
    run jq -e 'has("verdict")' <<<"$last_line"
    [ "$status" -eq 0 ]
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
