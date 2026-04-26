#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# secret-redaction.sh — Centralized secret-scrubber library
#
# Cycle: 093 (Loa Stabilization & Model-Currency Architecture)
# Sprint: 3B (Health-Probe Resilience — T2.2 part 2)
# SDD: grimoires/loa/cycles/cycle-093-stabilization/sdd.md §1.9, §6.5
# Closes: Flatline sprint-review SKP-005 HIGH (centralized scrubber)
#
# Single source for secret redaction across the Loa probe + adapter surface.
# All log paths and audit emissions MUST route through `_redact_secrets`.
#
# Usage:
#   source "$REPO_ROOT/.claude/scripts/lib/secret-redaction.sh"
#   safe_text="$(_redact_secrets "$untrusted_text")"
#
# Patterns redacted (SDD §1.9):
#   sk-...           OpenAI keys
#   AIza...          Google keys
#   ghp_..., gho_... GitHub PATs / OAuth tokens
#   xoxb-...         Slack bot tokens
#   Bearer <token>   Authorization header values
#   -----BEGIN .*    PEM-encoded keys (single-line block via `tr` flatten)
#
# Structured-logging allowlist:
#   _emit_structured_field <field> <value>
#   Only emits if field is in $LOA_LOG_ALLOWLIST (default: model_id, state,
#   latency_ms, http_status, provider, error_class, probe_run_id, exit_code).
# -----------------------------------------------------------------------------

# Idempotent-source guard — sourcing twice is a no-op.
if [[ "${_LOA_SECRET_REDACTION_SOURCED:-0}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi
_LOA_SECRET_REDACTION_SOURCED=1

# Default allowlist for structured logging. Operators can extend via env var.
: "${LOA_LOG_ALLOWLIST:=model_id state latency_ms http_status provider error_class probe_run_id exit_code reason confidence}"

# Redact known secret patterns from a string.
# Multi-line PEM blocks are first flattened to a single line (via `tr`) so the
# regex can match across what was previously distinct lines.
_redact_secrets() {
    local text="${1-}"
    [[ -z "$text" ]] && { printf '%s' ""; return 0; }

    # Flatten PEM-style multi-line blocks: collapse `\n` to literal `\n` so the
    # regex below can match across line boundaries inside a single-line buffer.
    local flat
    flat="$(printf '%s' "$text" | tr '\n' '\f')"

    # shellcheck disable=SC2001
    flat="$(printf '%s' "$flat" \
        | sed -E 's/sk-[A-Za-z0-9_-]{20,}/sk-REDACTED/g' \
        | sed -E 's/AIza[A-Za-z0-9_-]{20,}/AIza-REDACTED/g' \
        | sed -E 's/ghp_[A-Za-z0-9_-]{20,}/ghp_REDACTED/g' \
        | sed -E 's/gho_[A-Za-z0-9_-]{20,}/gho_REDACTED/g' \
        | sed -E 's/xox[abporsu]-[A-Za-z0-9-]{20,}/xox-REDACTED/g' \
        | sed -E 's/Bearer [A-Za-z0-9._\-]{20,}/Bearer REDACTED/g' \
        | sed -E 's/-----BEGIN[^-]*-----[^-]*-----END[^-]*-----/-----REDACTED-PEM-BLOCK-----/g' \
    )"

    # Restore line breaks.
    printf '%s' "$flat" | tr '\f' '\n'
}

# Emit a structured log line containing only allowlisted fields.
# Caller passes alternating field=value pairs as positional args.
# Usage:
#   _emit_structured_log INFO "probe complete" model_id=openai:gpt-5.3 state=AVAILABLE latency_ms=342
#
# Produces (to stderr):
#   [model-health-probe] INFO probe complete model_id=openai:gpt-5.3 state=AVAILABLE latency_ms=342
_emit_structured_log() {
    local level="$1"
    local message="$2"
    shift 2

    local out="[model-health-probe] $level $message"
    local pair key value
    for pair in "$@"; do
        key="${pair%%=*}"
        value="${pair#*=}"
        if _allowlist_contains "$key"; then
            out+=" ${key}=$(_redact_secrets "$value")"
        fi
    done
    echo "$out" >&2
}

# Check whether a field name is in the structured-logging allowlist.
_allowlist_contains() {
    local needle="$1"
    local item
    # shellcheck disable=SC2086
    for item in $LOA_LOG_ALLOWLIST; do
        [[ "$item" == "$needle" ]] && return 0
    done
    return 1
}

# Wrap any command so its stdout AND stderr are routed through `_redact_secrets`.
# Usage: _with_redaction curl -sS https://...
# Note: This buffers output; not suitable for streaming long outputs.
_with_redaction() {
    local out
    out="$("$@" 2>&1)"
    local rc=$?
    _redact_secrets "$out"
    return "$rc"
}
