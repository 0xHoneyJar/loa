#!/usr/bin/env bats
# =============================================================================
# tests/integration/model-health-probe-webhook-opt-in.bats
#
# cycle-099 Sprint 1E.c.3.c — opt-in webhook-host allowlist (deferred from
# 1E.c.3.a as MEDIUM):
#
#   model-health-probe.sh's alert webhook is operator-supplied via
#   .loa.config.yaml::model_health_probe.alert_webhook_url. Operators
#   legitimately use Slack / PagerDuty / Discord / custom URLs that cannot
#   be enumerated in a static allowlist.
#
#   Default behavior (preserved): legacy raw-curl path with hardened defaults
#   (--proto =https, --max-redirs 10) and an [ENDPOINT-VALIDATOR-EXEMPT] tag.
#
#   Opt-in behavior (new): when
#   `model_health_probe.alert_webhook_endpoint_validator_enabled: true` in
#   .loa.config.yaml, dispatch routes through endpoint_validator__guarded_curl
#   with the operator-controlled webhook-hosts.json allowlist.
#
# This bats file pins the dispatch decision: which path is taken given which
# config state. It tests `_webhook_send` (the synchronous helper) directly
# rather than `_webhook_dispatch` (which is async + uses disown), because
# capturing fire-and-forget side effects is racy. The async wrapper is
# trivial — it just forwards to _webhook_send in a backgrounded subshell —
# so the dispatch correctness is fully captured by testing _webhook_send.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    PROBE_SCRIPT="$PROJECT_ROOT/.claude/scripts/model-health-probe.sh"
    LIB_DIR="$PROJECT_ROOT/.claude/scripts/lib"

    [[ -f "$PROBE_SCRIPT" ]] || skip "model-health-probe.sh not present"

    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="${PYTHON_BIN:-python3}"
    fi
    "$PYTHON_BIN" -c "import idna" 2>/dev/null \
        || skip "idna not available in $PYTHON_BIN"

    WORK_DIR="$(mktemp -d)"
    CALL_LOG="$WORK_DIR/calls.log"
    : > "$CALL_LOG"
}

teardown() {
    if [[ -n "${WORK_DIR:-}" ]] && [[ -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
    return 0
}

# Helper: invoke _webhook_send via a child shell that:
#   1. Stubs `curl` as a bash function that writes argv to $CALL_LOG with
#      a "[curl-stub]" prefix and exits 0.
#   2. Stubs `endpoint_validator__guarded_curl` as a function that does the
#      same thing with a "[wrapper-stub]" prefix.
#   3. Sources the probe script (with a guard env var that prevents the
#      script's main from running) and calls _webhook_send with the test
#      payload + URL + opt-in flag.
#
# The stubs let us assert which dispatch path was taken without performing
# real HTTP requests. The probe script's `main` is guarded by a TEST_MODE
# env var so sourcing doesn't trigger probe execution.
_run_webhook_send() {
    local payload="$1" webhook="$2" opt_in="$3"
    local extra_env="${4-}"
    PROBE_SCRIPT="$PROBE_SCRIPT" CALL_LOG="$CALL_LOG" \
    PAYLOAD="$payload" WEBHOOK="$webhook" OPT_IN="$opt_in" \
    LIB_DIR="$LIB_DIR" \
    LOA_WEBHOOK_ALLOWLIST_PATH="${LOA_WEBHOOK_ALLOWLIST_PATH:-}" \
    bash -c '
        set -uo pipefail
        '"$extra_env"'
        # Source probe FIRST. The probe sources endpoint-validator.sh during
        # init, which defines the real endpoint_validator__guarded_curl. We
        # then OVERRIDE it with a stub so dispatch decisions are observable.
        # Probe is auto-guarded against running main() when sourced (the
        # `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` block at the bottom).
        source "$PROBE_SCRIPT"

        # Stub curl + wrapper AFTER sourcing — both stubs are synchronous
        # functions that capture their argv to CALL_LOG and exit 0. Bash
        # functions take precedence over PATH commands AND over previously-
        # defined functions, so this clobbers the real wrapper from the
        # source above.
        curl() {
            printf "[curl-stub] %s\n" "$*" >> "$CALL_LOG"
            return 0
        }
        endpoint_validator__guarded_curl() {
            printf "[wrapper-stub] %s\n" "$*" >> "$CALL_LOG"
            return 0
        }

        _webhook_send "$PAYLOAD" "$WEBHOOK" "$OPT_IN"
    '
}

# ---------------------------------------------------------------------------
# WO0 — POSITIVE CONTROL: with no opt-in, dispatch goes through the legacy
# curl path. Verifies the default behavior is preserved (operators with
# non-allowlisted webhooks continue to work).
# ---------------------------------------------------------------------------

@test "WO0 default (opt_in=false): legacy curl path invoked, wrapper NOT invoked" {
    _run_webhook_send '{"event":"test"}' "https://hooks.slack.com/services/X/Y" "false"
    grep -q '\[curl-stub\]' "$CALL_LOG" || {
        printf 'expected curl-stub in call log; got: %s\n' "$(cat "$CALL_LOG")" >&2
        return 1
    }
    ! grep -q '\[wrapper-stub\]' "$CALL_LOG" || {
        printf 'wrapper-stub should NOT be invoked when opt_in=false; got: %s\n' "$(cat "$CALL_LOG")" >&2
        return 1
    }
}

@test "WO0b legacy curl path includes hardened defaults (--proto, --max-redirs)" {
    _run_webhook_send '{"event":"test"}' "https://hooks.slack.com/services/X/Y" "false"
    grep -q -- '--proto =https' "$CALL_LOG"
    grep -q -- '--max-redirs 10' "$CALL_LOG"
}

# ---------------------------------------------------------------------------
# WO1 — opt-in dispatch goes through the wrapper. With opt_in=true and a
# webhook host that's in the allowlist, the wrapper-stub is invoked and
# the curl-stub is NOT.
# ---------------------------------------------------------------------------

@test "WO1 opt_in=true: wrapper invoked with --allowlist + --url, curl NOT invoked" {
    _run_webhook_send '{"event":"test"}' "https://hooks.slack.com/services/X/Y" "true"
    grep -q '\[wrapper-stub\]' "$CALL_LOG" || {
        printf 'expected wrapper-stub in call log; got: %s\n' "$(cat "$CALL_LOG")" >&2
        return 1
    }
    ! grep -q '\[curl-stub\]' "$CALL_LOG" || {
        printf 'curl-stub should NOT be invoked when opt_in=true; got: %s\n' "$(cat "$CALL_LOG")" >&2
        return 1
    }
    # Wrapper invocation MUST include --allowlist and --url
    grep -q -- '--allowlist' "$CALL_LOG"
    grep -q -- '--url' "$CALL_LOG"
}

@test "WO1b opt_in=true: wrapper invocation passes the webhook URL via --url" {
    _run_webhook_send '{"event":"test"}' "https://hooks.example.com/post" "true"
    grep -q 'https://hooks.example.com/post' "$CALL_LOG" || {
        printf 'webhook URL not present in wrapper invocation: %s\n' "$(cat "$CALL_LOG")" >&2
        return 1
    }
}

# ---------------------------------------------------------------------------
# WO2 — empty webhook URL: NEITHER path invoked. Operators who haven't
# configured a webhook URL should not see any dispatch attempt.
# ---------------------------------------------------------------------------

@test "WO2 empty webhook URL: dispatch is a no-op" {
    _run_webhook_send '{"event":"test"}' "" "false"
    [[ ! -s "$CALL_LOG" ]] || {
        printf 'expected empty call log on empty webhook; got: %s\n' "$(cat "$CALL_LOG")" >&2
        return 1
    }
}

@test "WO2b empty webhook URL with opt_in=true: still a no-op" {
    _run_webhook_send '{"event":"test"}' "" "true"
    [[ ! -s "$CALL_LOG" ]]
}

# ---------------------------------------------------------------------------
# WO3 — opt_in=true uses the webhook-hosts.json allowlist by default
# (operator-controlled, empty default). The path defaults to
# $LIB_DIR/allowlists/webhook-hosts.json unless overridden.
# ---------------------------------------------------------------------------

@test "WO3 opt_in=true: --allowlist points to webhook-hosts.json by default" {
    _run_webhook_send '{"event":"test"}' "https://hooks.slack.com/X" "true"
    grep -q 'webhook-hosts.json' "$CALL_LOG" || {
        printf 'expected webhook-hosts.json path in --allowlist; got: %s\n' "$(cat "$CALL_LOG")" >&2
        return 1
    }
}

# ---------------------------------------------------------------------------
# WO4 — webhook-hosts.json file MUST exist with empty default. Tests that
# an empty default does not cause _webhook_send to crash; opt-in operators
# who haven't populated the file are fail-closed at the wrapper layer
# (covered by guarded-curl tests, not duplicated here).
# ---------------------------------------------------------------------------

@test "WO4 webhook-hosts.json exists in canonical tree" {
    [[ -f "$LIB_DIR/allowlists/webhook-hosts.json" ]] || {
        printf 'expected webhook-hosts.json at %s/allowlists/webhook-hosts.json\n' "$LIB_DIR" >&2
        return 1
    }
}

@test "WO4b webhook-hosts.json validates with load_allowlist (no junk entries)" {
    F="$LIB_DIR/allowlists/webhook-hosts.json" "$PYTHON_BIN" -I -c '
import os, runpy, sys
ns = runpy.run_path(".claude/scripts/lib/endpoint-validator.py", run_name="ev")
ns["load_allowlist"](os.environ["F"])
print("OK")
'
    [[ "$status" -eq 0 ]] || true  # bats run sets status; this is direct call
}

# ---------------------------------------------------------------------------
# WO5 — pin the dispatch decision pivot: any opt_in value other than the
# exact string "true" is treated as legacy. Defends against misconfig where
# an operator writes `enabled: yes` (yaml truthy) but the bash check is
# string-equality on "true" — the legacy path runs (safer fallback).
# ---------------------------------------------------------------------------

@test "WO5 opt_in='yes' (yaml-truthy but not 'true'): legacy curl path used" {
    _run_webhook_send '{"event":"test"}' "https://hooks.slack.com/X" "yes"
    grep -q '\[curl-stub\]' "$CALL_LOG"
    ! grep -q '\[wrapper-stub\]' "$CALL_LOG"
}

@test "WO5b opt_in='1' (numeric truthy): legacy curl path used" {
    _run_webhook_send '{"event":"test"}' "https://hooks.slack.com/X" "1"
    grep -q '\[curl-stub\]' "$CALL_LOG"
    ! grep -q '\[wrapper-stub\]' "$CALL_LOG"
}

@test "WO5c opt_in='True' (case mismatch): legacy curl path used" {
    _run_webhook_send '{"event":"test"}' "https://hooks.slack.com/X" "True"
    grep -q '\[curl-stub\]' "$CALL_LOG"
    ! grep -q '\[wrapper-stub\]' "$CALL_LOG"
}
