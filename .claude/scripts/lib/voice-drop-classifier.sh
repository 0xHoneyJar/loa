#!/usr/bin/env bash
# =============================================================================
# voice-drop-classifier.sh — classify a flatline call_model exit code
# =============================================================================
# Cycle-104 sprint-2 T2.8 (FR-S2.5). Pure function with no side effects.
#
# Input:  exit code from call_model (which propagates cheval's exit code).
# Output: one of "success" | "dropped" | "failed" on stdout, status 0.
#         Bad usage exits non-zero (usage on stderr).
#
# Classification rules
# --------------------
#   0           → "success"    — voice produced a result
#   12          → "dropped"    — cheval's CHAIN_EXHAUSTED: within-company
#                                fallback chain walked to end. Per SDD §6.5
#                                the voice is DROPPED from consensus, not
#                                substituted across companies.
#   11          → "failed"     — cheval's NO_ELIGIBLE_ADAPTER: misconfig,
#                                surfaces as hard failure (operator action).
#   anything else → "failed"   — timeout, validation, JSON, transport, etc.
#
# Why not also drop on 11? The chain_resolver returns zero entries only
# when the operator's mode/capability filters rule out every adapter for
# the requested voice. That is a configuration error, not a graceful
# fall-through, and silent voice-drop would hide it. cycle-104 SDD §6.3
# pins NO_ELIGIBLE_ADAPTER as a surfaced error class.

set -euo pipefail

readonly EXIT_CHAIN_EXHAUSTED=12

usage() {
    cat >&2 <<'USAGE'
Usage: voice-drop-classifier.sh <exit_code>
       voice-drop-classifier.sh --self-test

Classifies a flatline call_model exit code. Writes one of:
  success | dropped | failed
to stdout. Always exits 0 on a well-formed call.
USAGE
}

self_test() {
    local fails=0
    local got expected

    classify_case() {
        local input="$1"
        local want="$2"
        local out
        out=$("$0" "$input")
        if [[ "$out" != "$want" ]]; then
            printf 'FAIL: classify(%s) = %s, want %s\n' "$input" "$out" "$want" >&2
            fails=$((fails + 1))
        fi
    }

    classify_case 0 success
    classify_case 12 dropped
    classify_case 11 failed
    classify_case 1 failed
    classify_case 124 failed
    classify_case 137 failed

    if [[ $fails -eq 0 ]]; then
        printf 'voice-drop-classifier self-test: PASS\n'
        return 0
    fi
    printf 'voice-drop-classifier self-test: %d FAIL\n' "$fails" >&2
    return 1
}

classify_voice_exit() {
    local code="$1"
    if [[ "$code" == "0" ]]; then
        printf 'success\n'
        return 0
    fi
    if [[ "$code" == "$EXIT_CHAIN_EXHAUSTED" ]]; then
        printf 'dropped\n'
        return 0
    fi
    printf 'failed\n'
}

main() {
    if [[ $# -ne 1 ]]; then
        usage
        return 2
    fi

    case "$1" in
        --self-test) self_test ;;
        -h|--help)   usage; return 0 ;;
        *)
            # Must be a non-negative integer; reject anything else so
            # callers don't silently get "failed" for a typo'd variable.
            if [[ ! "$1" =~ ^[0-9]+$ ]]; then
                printf 'ERROR: exit code must be a non-negative integer, got %q\n' "$1" >&2
                return 2
            fi
            classify_voice_exit "$1"
            ;;
    esac
}

# Allow sourcing for direct function access; run main() only when invoked
# as a script.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
