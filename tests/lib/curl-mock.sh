#!/usr/bin/env bash
# =============================================================================
# tests/lib/curl-mock.sh — curl-mocking shim for adapter behavior tests
# =============================================================================
#
# cycle-102 Sprint 1C T1C.1 (Issue #808; closes BB iter-4 REFRAME-1
# "static bash analysis approaching ceiling"; closes DISS-001/002/003
# Sprint 1A test-quality debt).
#
# This shim is placed earlier on PATH than /usr/bin/curl during a test.
# It records argv + stdin to a JSONL call log, then emits a configured
# response (status code + headers + body) per a fixture YAML.
#
# Activation: a bats helper (see tests/lib/curl-mock-helpers.bash) creates
# a tempdir with a `curl` symlink pointing here, prepends it to PATH, and
# exports LOA_CURL_MOCK_FIXTURE + LOA_CURL_MOCK_CALL_LOG.
#
# Hermetic: NEVER FALL THROUGH TO REAL CURL. Missing/malformed fixture is
# a fail-loud error. The whole point of this shim is to refuse silent
# degradation — exactly the failure mode vision-019/023/024 named.
#
# Fixture format (YAML):
#   status_code: 200          # required, integer 100-599
#   exit_code: 0              # optional, default 0 (28=timeout, 7=disconnect)
#   delay_seconds: 0          # optional, default 0 (sleep before response)
#   headers:                  # optional, map of header-name -> value
#     content-type: application/json
#     x-custom: foo
#   body: |                   # optional inline body (mutually exclusive with body_file)
#     {"ok": true}
#   body_file: bodies/x.json  # optional, relative to fixture's dir or absolute
#   stderr: ""                # optional, written to stderr verbatim
#
# Call log (JSONL, one entry per invocation):
#   {"ts": "...", "argv": ["curl", "-X", ...], "stdin": "...",
#    "fixture": "...", "exit_code": 0}
#
# Environment:
#   LOA_CURL_MOCK_FIXTURE  Required. Path to fixture file (absolute or relative).
#   LOA_CURL_MOCK_CALL_LOG Required. Path to JSONL call-log file (created if absent).
#   LOA_CURL_MOCK_DEBUG    Optional, "1" to emit shim-trace to stderr.
# =============================================================================

set -euo pipefail

# Hard fail-loud guards — cycle-102 vision-019/023 anti-silent-degradation.
if [[ -z "${LOA_CURL_MOCK_FIXTURE:-}" ]]; then
    printf 'curl-mock: LOA_CURL_MOCK_FIXTURE not set — refusing to run silently.\n' >&2
    printf '  Use _with_curl_mock <fixture-name> from tests/lib/curl-mock-helpers.bash\n' >&2
    exit 99
fi
if [[ -z "${LOA_CURL_MOCK_CALL_LOG:-}" ]]; then
    printf 'curl-mock: LOA_CURL_MOCK_CALL_LOG not set — refusing to run without audit.\n' >&2
    exit 99
fi

FIXTURE_PATH="$LOA_CURL_MOCK_FIXTURE"
CALL_LOG="$LOA_CURL_MOCK_CALL_LOG"
DEBUG="${LOA_CURL_MOCK_DEBUG:-}"

if [[ ! -f "$FIXTURE_PATH" ]]; then
    printf 'curl-mock: fixture not found at %s\n' "$FIXTURE_PATH" >&2
    exit 99
fi

_dbg() { [[ "$DEBUG" == "1" ]] && printf 'curl-mock[trace]: %s\n' "$*" >&2; return 0; }

_dbg "fixture=$FIXTURE_PATH call_log=$CALL_LOG argv_count=$#"

# -----------------------------------------------------------------------------
# YAML parsing — we use yq if available, fall back to a tiny grep-based parser
# for the small fixture schema (status_code, exit_code, delay_seconds, body,
# body_file, headers, stderr). Keeping the fallback minimal so this shim has
# no hard dep on yq beyond what bats-fixtures already require.
# -----------------------------------------------------------------------------

_yq_exists() { command -v yq >/dev/null 2>&1; }

_yq() {
    # Read field with yq if available
    yq -r "$1 // \"\"" "$FIXTURE_PATH"
}

_grep_field() {
    # Fallback: grep the literal `key:` line for scalar fields.
    # Only handles top-level scalar fields. For nested headers + multiline
    # body we require yq.
    local key="$1"
    grep -E "^${key}:[[:space:]]*" "$FIXTURE_PATH" 2>/dev/null \
        | head -1 \
        | sed -E "s/^${key}:[[:space:]]*//" \
        | sed -E 's/^"(.*)"$/\1/' \
        | sed -E "s/^'(.*)'\$/\1/"
}

if _yq_exists; then
    STATUS_CODE=$(_yq '.status_code')
    EXIT_CODE=$(_yq '.exit_code')
    DELAY=$(_yq '.delay_seconds')
    BODY=$(_yq '.body')
    BODY_FILE=$(_yq '.body_file')
    STDERR_TEXT=$(_yq '.stderr')
else
    STATUS_CODE=$(_grep_field 'status_code')
    EXIT_CODE=$(_grep_field 'exit_code')
    DELAY=$(_grep_field 'delay_seconds')
    BODY=""  # multiline bodies require yq
    BODY_FILE=$(_grep_field 'body_file')
    STDERR_TEXT=$(_grep_field 'stderr')
fi

# Defaults
STATUS_CODE="${STATUS_CODE:-200}"
EXIT_CODE="${EXIT_CODE:-0}"
DELAY="${DELAY:-0}"

# Validate status_code is an integer in 100-599 range (or matches exit_code semantics)
case "$STATUS_CODE" in
    ''|*[!0-9]*)
        printf 'curl-mock: invalid status_code in fixture %s: %s\n' "$FIXTURE_PATH" "$STATUS_CODE" >&2
        exit 99
        ;;
esac
case "$EXIT_CODE" in
    ''|*[!0-9]*)
        printf 'curl-mock: invalid exit_code in fixture %s: %s\n' "$FIXTURE_PATH" "$EXIT_CODE" >&2
        exit 99
        ;;
esac

# -----------------------------------------------------------------------------
# Capture the payload curl would have sent. Real curl accepts data via:
#   -d "literal" / --data "literal"
#   -d @file / --data @file / -d @- / --data @-
#   --data-binary @file / --data-binary "literal" / --data-binary @-
#   --data-raw "literal"
#   --data-urlencode "key=val"
# We capture in this priority order:
#   1. If any `-d/--data*` flag with `@-` is present → read from stdin
#   2. If any `-d/--data*` flag with `@<file>` is present → read that file
#      AT INVOCATION TIME (callers may rm the file via trap RETURN, so the
#      file must be read while the shim runs, not later from the call log)
#   3. If any `-d/--data*` flag with literal value is present → use that
#   4. If stdin is piped (e.g., `echo X | curl`) → read stdin
#   5. Otherwise → empty string
# -----------------------------------------------------------------------------

_capture_payload() {
    local i=1
    local arg next_arg
    local stdin_seen=0 file_seen=0 literal_seen=0
    local payload=""

    while [[ $i -le $# ]]; do
        arg="${@:$i:1}"
        # Handle --flag=value form
        case "$arg" in
            -d=*|--data=*|--data-raw=*|--data-binary=*|--data-urlencode=*)
                next_arg="${arg#*=}"
                ;;
            -d|--data|--data-raw|--data-binary|--data-urlencode)
                i=$((i + 1))
                if [[ $i -le $# ]]; then
                    next_arg="${@:$i:1}"
                else
                    next_arg=""
                fi
                ;;
            *)
                i=$((i + 1))
                continue
                ;;
        esac

        # Now next_arg is the data-flag value
        case "$next_arg" in
            @-)
                stdin_seen=1
                ;;
            @*)
                local fpath="${next_arg#@}"
                if [[ -f "$fpath" ]]; then
                    payload=$(head -c 16777216 < "$fpath" || true)
                    file_seen=1
                fi
                ;;
            *)
                payload="$next_arg"
                literal_seen=1
                ;;
        esac
        i=$((i + 1))
    done

    if [[ $stdin_seen -eq 1 ]]; then
        # explicit @- request — read stdin
        payload=$(head -c 16777216 || true)
    elif [[ $file_seen -eq 0 && $literal_seen -eq 0 && ! -t 0 ]]; then
        # no -d flag at all but stdin is piped (e.g., echo X | curl)
        payload=$(head -c 16777216 || true)
    fi

    printf '%s' "$payload"
}

STDIN_DATA="$(_capture_payload "$@")"

# -----------------------------------------------------------------------------
# Resolve body_file relative to fixture's own directory if not absolute
# -----------------------------------------------------------------------------
RESOLVED_BODY=""
if [[ -n "$BODY_FILE" ]]; then
    if [[ "$BODY_FILE" == /* ]]; then
        BODY_FILE_PATH="$BODY_FILE"
    else
        FIXTURE_DIR="$(cd "$(dirname "$FIXTURE_PATH")" && pwd)"
        BODY_FILE_PATH="$FIXTURE_DIR/$BODY_FILE"
    fi
    if [[ ! -f "$BODY_FILE_PATH" ]]; then
        printf 'curl-mock: body_file not found at %s (referenced from %s)\n' \
            "$BODY_FILE_PATH" "$FIXTURE_PATH" >&2
        exit 99
    fi
    RESOLVED_BODY="$(cat "$BODY_FILE_PATH")"
elif [[ -n "$BODY" ]]; then
    RESOLVED_BODY="$BODY"
fi

# -----------------------------------------------------------------------------
# Optional pre-response delay (used to simulate timeouts when paired with
# --max-time on caller's curl flags; here delay just sleeps then exits)
# -----------------------------------------------------------------------------
if [[ "$DELAY" != "0" ]]; then
    _dbg "delaying $DELAY seconds"
    sleep "$DELAY"
fi

# -----------------------------------------------------------------------------
# Detect curl flags that would change output behavior — the shim must be
# faithful enough that adapters relying on curl's own behaviors don't break.
# Specifically:
#   -i / --include      → emit headers + body
#   -o <path>           → write body to file instead of stdout
#   -w <fmt>            → not honored (caller must handle); we WARN if seen
#   --silent / -s       → suppress stderr we'd write
#   --output-dir <dir>  → not honored
# -----------------------------------------------------------------------------
INCLUDE_HEADERS=0
OUTPUT_FILE=""
SILENT=0
i=1
ARGS=("$@")
while [[ $i -le $# ]]; do
    arg="${ARGS[$((i-1))]}"
    case "$arg" in
        -i|--include) INCLUDE_HEADERS=1 ;;
        -s|--silent) SILENT=1 ;;
        -o|--output)
            if [[ $i -lt $# ]]; then
                OUTPUT_FILE="${ARGS[$i]}"
            fi
            ;;
        -w|--write-out)
            _dbg "WARN: -w/--write-out not honored by curl-mock"
            ;;
    esac
    i=$((i + 1))
done

# -----------------------------------------------------------------------------
# Compose argv as JSON array — capture full invocation for assertion helpers.
# Use jq if available for byte-correct JSON-string escaping; fall back to a
# minimal Python escape if jq is missing (Python is required by the
# repo's test infra so this is safe).
# -----------------------------------------------------------------------------
_argv_json() {
    if command -v jq >/dev/null 2>&1; then
        # shellcheck disable=SC2016
        jq -nc --args '$ARGS.positional' -- "$@"
    else
        python3 -c '
import json, sys
print(json.dumps(sys.argv[1:]))
' "$@"
    fi
}

_string_json() {
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$1" | jq -Rs .
    else
        python3 -c '
import json, sys
print(json.dumps(sys.stdin.read()))
' <<<"$1"
    fi
}

ARGV_JSON=$(_argv_json "curl" "$@")
STDIN_JSON=$(_string_json "$STDIN_DATA")
FIXTURE_JSON=$(_string_json "$FIXTURE_PATH")
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# -----------------------------------------------------------------------------
# Append to call log atomically (per-line append is atomic on POSIX <PIPE_BUF)
# -----------------------------------------------------------------------------
mkdir -p "$(dirname "$CALL_LOG")"
{
    if command -v jq >/dev/null 2>&1; then
        jq -nc --arg ts "$TS" \
              --argjson argv "$ARGV_JSON" \
              --argjson stdin "$STDIN_JSON" \
              --argjson fixture "$FIXTURE_JSON" \
              --argjson exit_code "$EXIT_CODE" \
              --argjson status_code "$STATUS_CODE" \
              '{ts: $ts, argv: $argv, stdin: $stdin, fixture: $fixture, exit_code: $exit_code, status_code: $status_code}'
    else
        python3 -c '
import json, sys
print(json.dumps({
    "ts": sys.argv[1],
    "argv": json.loads(sys.argv[2]),
    "stdin": json.loads(sys.argv[3]),
    "fixture": json.loads(sys.argv[4]),
    "exit_code": int(sys.argv[5]),
    "status_code": int(sys.argv[6]),
}))
' "$TS" "$ARGV_JSON" "$STDIN_JSON" "$FIXTURE_JSON" "$EXIT_CODE" "$STATUS_CODE"
    fi
} >> "$CALL_LOG"

_dbg "logged call: status=$STATUS_CODE exit=$EXIT_CODE include_headers=$INCLUDE_HEADERS"

# -----------------------------------------------------------------------------
# Honor exit_code != 0 (disconnect=7, timeout=28). Real curl writes nothing
# to stdout on these paths but may write a brief diagnostic to stderr.
# -----------------------------------------------------------------------------
if [[ "$EXIT_CODE" != "0" ]]; then
    if [[ -n "$STDERR_TEXT" && "$SILENT" != "1" ]]; then
        printf '%s\n' "$STDERR_TEXT" >&2
    fi
    exit "$EXIT_CODE"
fi

# -----------------------------------------------------------------------------
# Emit response. With -i/--include, prepend HTTP status line + headers.
# Without, just emit body. Direct to OUTPUT_FILE if -o was passed.
# -----------------------------------------------------------------------------
_emit_response() {
    if [[ "$INCLUDE_HEADERS" == "1" ]]; then
        printf 'HTTP/1.1 %s\r\n' "$STATUS_CODE"
        if _yq_exists; then
            yq -r '.headers // {} | to_entries | .[] | "\(.key): \(.value)"' "$FIXTURE_PATH" 2>/dev/null \
                | while IFS= read -r line; do
                    [[ -n "$line" ]] && printf '%s\r\n' "$line"
                done
        fi
        printf '\r\n'
    fi
    printf '%s' "$RESOLVED_BODY"
}

if [[ -n "$OUTPUT_FILE" ]]; then
    _emit_response > "$OUTPUT_FILE"
else
    _emit_response
fi

if [[ -n "$STDERR_TEXT" && "$SILENT" != "1" ]]; then
    printf '%s\n' "$STDERR_TEXT" >&2
fi

exit 0
