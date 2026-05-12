#!/usr/bin/env bats
# =============================================================================
# test_cli_only_zero_api_key.bats — cycle-104 sprint-2 T2.11 (FR-S2.9 / AC-8)
# =============================================================================
# Zero-API-key end-to-end proof: with `LOA_HEADLESS_MODE=cli-only` and
# every `*_API_KEY` env var unset, cheval MUST succeed via subscription-
# CLI dispatch and MUST issue ZERO HTTPS connections.
#
# Verification is two-layered:
#
#   1. cheval exits 0 with non-empty content (functional success — the
#      cli-only path actually works).
#   2. `strace -f -e trace=connect` (or equivalent network monitor)
#      records ZERO connect() syscalls with sin_port=443 across the
#      lifetime of the cheval invocation (no HTTPS issued).
#
# Layer 2 is the SDD §1.9 defense-in-depth claim: cheval MUST refuse to
# issue HTTPS when the resolved chain is CLI-only. The audit envelope
# also records `transport: cli` for the winning entry; we assert that
# in the cheval JSON output too.
#
# **Gated behind `LOA_RUN_E2E_TESTS=1`** (separate from
# `LOA_RUN_LIVE_TESTS=1` because this consumes the operator's CLI
# subscription quota, NOT live HTTP API budget). Operators with a Claude
# Code / Codex / Gemini subscription run this; operators without a
# subscription do not.
#
# Pre-requisites for the operator running this:
#
#   - `claude` / `codex` / `gemini` binaries on $PATH and authenticated
#     (one-time `claude` / `codex` / `gemini` OAuth handshake)
#   - `strace` available (Linux). On macOS the test skips with a
#     diagnostic instead of using `dtruss` (which requires SIP off).
#   - `LOA_RUN_E2E_TESTS=1`
#
# Invocation:
#
#     LOA_RUN_E2E_TESTS=1 \\
#     bats tests/e2e/test_cli_only_zero_api_key.bats

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
    CHEVAL="$PROJECT_ROOT/.claude/adapters/cheval.py"

    # ----- Gate -----------------------------------------------------------
    if [[ "${LOA_RUN_E2E_TESTS:-0}" != "1" ]]; then
        skip "Set LOA_RUN_E2E_TESTS=1 to run (consumes CLI subscription quota)"
    fi

    # ----- Tool availability ---------------------------------------------
    if ! command -v strace >/dev/null 2>&1; then
        skip "strace not available (Linux-only on this test path; macOS dtruss requires SIP off)"
    fi
    if [[ ! -f "$CHEVAL" ]]; then
        skip "cheval.py not at $CHEVAL"
    fi

    # ----- Per-test scratch ----------------------------------------------
    local slug
    slug=$(echo "${BATS_TEST_NAME:-test}" | tr -c 'A-Za-z0-9_' '_')
    SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/cli-only-${slug}-XXXXXX")"
    chmod 700 "$SCRATCH"
    STRACE_LOG="$SCRATCH/strace.log"
    CHEVAL_STDOUT="$SCRATCH/cheval.stdout"
    CHEVAL_STDERR="$SCRATCH/cheval.stderr"
}

teardown() {
    if [[ -n "${SCRATCH:-}" && -d "$SCRATCH" ]]; then
        # Preserve the strace log if the test failed (helps the operator
        # forensics-walk a violation). Bats sets $BATS_TEST_COMPLETED=1
        # only on pass.
        if [[ "${BATS_TEST_COMPLETED:-0}" != "1" ]]; then
            echo "[debug] strace log preserved at $STRACE_LOG" >&3 2>/dev/null || true
        else
            rm -rf "$SCRATCH"
        fi
    fi
}

# Helper: count outbound connect() syscalls to port 443.
# strace -e trace=connect logs one line per connect call; we grep for
# `sin_port=htons(443)` which is the IPv4/IPv6 portable form.
_count_https_connects() {
    local log="$1"
    if [[ ! -f "$log" ]]; then
        echo 0
        return
    fi
    # Match both v4 (`sin_port=htons(443)`) and v6 forms.
    grep -cE 'sin6?_port=htons\(443\)' "$log" 2>/dev/null || echo 0
}

# Helper: count outbound connect() syscalls to ports OTHER than 443.
# We accept localhost / unix-socket connects (the CLI binaries talk to
# their parent OAuth refresh helpers via local channels).
_count_non_https_connects() {
    local log="$1"
    if [[ ! -f "$log" ]]; then
        echo 0
        return
    fi
    grep -cE 'connect\(' "$log" 2>/dev/null || echo 0
}

# ---- T2.11 happy path -----------------------------------------------------

@test "T2.11-1: cli-only mode succeeds with zero *_API_KEY env" {
    # Unset every HTTP API key — defense-in-depth proof that nothing
    # leaks an env-derived auth header to the HTTPS path.
    unset ANTHROPIC_API_KEY OPENAI_API_KEY GOOGLE_API_KEY \
          AWS_BEDROCK_API_KEY AWS_BEARER_TOKEN_BEDROCK

    # cli-only mode + claude-headless alias (T2.4): the entire chain
    # is `[anthropic:claude-headless]` after the api-mode filter.
    # If any HTTP entry leaks through, the strace assertion below
    # catches it.
    export LOA_HEADLESS_MODE="cli-only"

    # Invoke under strace. -f for child processes (cheval spawns the
    # CLI binary); -e trace=connect for outbound connect() only;
    # output to a file.
    strace -f -e trace=connect -o "$STRACE_LOG" \
        python3 "$CHEVAL" invoke \
            --agent flatline-reviewer \
            --model claude-headless \
            --prompt "Reply with the single word 'ack'." \
            --output-format json \
            --json-errors \
            --timeout 120 \
            >"$CHEVAL_STDOUT" 2>"$CHEVAL_STDERR" || true

    # Read the cheval exit code from a marker (strace returns its own
    # success status; the child's exit is in the strace log).
    # Easier: re-run without strace if the test fails on JSON parse —
    # but the primary path checks the JSON envelope cheval wrote.
    local rc=0
    if ! jq -e '.content | length > 0' "$CHEVAL_STDOUT" >/dev/null 2>&1; then
        rc=1
    fi

    # Assertion 1: cheval produced non-empty content
    if [[ "$rc" -ne 0 ]]; then
        echo "--- cheval stdout (truncated) ---" >&2
        head -c 2000 "$CHEVAL_STDOUT" >&2
        echo >&2
        echo "--- cheval stderr (truncated) ---" >&2
        head -c 2000 "$CHEVAL_STDERR" >&2
        echo >&2
        false
    fi

    # Assertion 2: cheval recorded transport: cli
    run jq -r '.transport // empty' "$CHEVAL_STDOUT"
    [ "$status" -eq 0 ]
    [ "$output" = "cli" ]

    # Assertion 3 (the load-bearing one): ZERO connect() to port 443.
    local https_count
    https_count=$(_count_https_connects "$STRACE_LOG")
    if [[ "$https_count" -ne 0 ]]; then
        echo "VIOLATION: cli-only mode issued $https_count HTTPS connect() syscalls" >&2
        echo "--- offending strace lines ---" >&2
        grep -E 'sin6?_port=htons\(443\)' "$STRACE_LOG" | head -10 >&2
        false
    fi
}

# ---- T2.11 negative control: prefer-api MUST issue HTTPS ------------------

@test "T2.11-2: control: prefer-api WITH api keys DOES issue HTTPS (proves strace works)" {
    # Negative control. Without this, a strace-broken test would pass
    # T2.11-1 by accident (zero HTTPS counted because strace logged
    # nothing). This test FAILS if strace didn't catch a known-HTTPS
    # call — proving the assertion in T2.11-1 has teeth.
    if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
        skip "Negative control requires ANTHROPIC_API_KEY (the test deliberately uses HTTP)"
    fi
    export LOA_HEADLESS_MODE="api-only"
    strace -f -e trace=connect -o "$STRACE_LOG" \
        python3 "$CHEVAL" invoke \
            --agent flatline-reviewer \
            --model anthropic:claude-opus-4-7 \
            --prompt "Reply with the single word 'ack'." \
            --output-format json \
            --json-errors \
            --timeout 60 \
            >"$CHEVAL_STDOUT" 2>"$CHEVAL_STDERR" || true

    local https_count
    https_count=$(_count_https_connects "$STRACE_LOG")
    if [[ "$https_count" -lt 1 ]]; then
        echo "STRACE INSTRUMENTATION BROKEN: prefer-api with keys issued zero HTTPS in strace log" >&2
        echo "T2.11-1's zero-HTTPS claim is therefore unverified." >&2
        false
    fi
}

# ---- T2.11 audit envelope cross-check -------------------------------------

@test "T2.11-3: audit trajectory records transport=cli for cli-only invocations" {
    unset ANTHROPIC_API_KEY OPENAI_API_KEY GOOGLE_API_KEY
    export LOA_HEADLESS_MODE="cli-only"

    python3 "$CHEVAL" invoke \
        --agent flatline-reviewer \
        --model claude-headless \
        --prompt "Reply with the single word 'ack'." \
        --output-format json \
        --json-errors \
        --timeout 120 \
        >"$CHEVAL_STDOUT" 2>"$CHEVAL_STDERR" || true

    # The cheval stdout envelope itself carries transport per T2.6.
    run jq -r '.transport // empty' "$CHEVAL_STDOUT"
    [ "$status" -eq 0 ]
    [ "$output" = "cli" ]

    # config_observed.headless_mode must reflect the operator's env.
    run jq -r '.config_observed.headless_mode // empty' "$CHEVAL_STDOUT"
    [ "$status" -eq 0 ]
    [ "$output" = "cli-only" ]

    run jq -r '.config_observed.headless_mode_source // empty' "$CHEVAL_STDOUT"
    [ "$status" -eq 0 ]
    [ "$output" = "env" ]
}
