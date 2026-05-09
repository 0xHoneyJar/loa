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
# YAML parsing — yq is REQUIRED. The previous grep-based fallback was unusable:
# under `set -euo pipefail` it returned non-zero for missing optional fields
# AND silently dropped multiline `body: |` content. Per BB iter-1 F1/FIND-001
# convergent finding (both anthropic + openai flagged the same root cause):
# fail-closed must be transitive — if the harness's fail-loud claim depends
# on yq, yq's absence is itself a fail-loud trigger. Mirrors Meta's Buck2
# hermetic-toolchain approach: tool absence is a hard error, never a soft
# fallback.
# -----------------------------------------------------------------------------

if ! command -v yq >/dev/null 2>&1; then
    printf 'curl-mock: yq is required (mikefarah/yq v4 or kislyuk/yq) — install before running.\n' >&2
    printf '  The previous grep fallback silently dropped multiline body content;\n' >&2
    printf '  that fallback was removed per BB iter-1 F1/FIND-001 closure.\n' >&2
    exit 99
fi

_yq() {
    yq -r "$1 // \"\"" "$FIXTURE_PATH"
}

STATUS_CODE=$(_yq '.status_code')
EXIT_CODE=$(_yq '.exit_code')
DELAY=$(_yq '.delay_seconds')
BODY=$(_yq '.body')
BODY_FILE=$(_yq '.body_file')
STDERR_TEXT=$(_yq '.stderr')

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
FAIL_FLAG=0   # BB iter-1 FIND-003 closure: --fail / -f / --fail-with-body
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
        -f|--fail|--fail-with-body|--fail-early)
            # BB iter-1 FIND-003: real curl returns exit 22 when --fail is
            # set and status >=400. The shim must model this faithfully —
            # silent omission means a caller using `curl --fail` against
            # 4xx/5xx fixtures gets exit 0 and false-positives.
            FAIL_FLAG=1
            ;;
        -w|--write-out)
            # BB iter-1 FIND-002 (deferred): -w/--write-out output not yet
            # emitted. Tests using `curl -w '%{http_code}'` to split body
            # from status will see no write-out. Tracked for follow-up.
            _dbg "WARN: -w/--write-out not honored by curl-mock (FIND-002 follow-up)"
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
# BB iter-1 FIND-003 closure: --fail / -f handling. Real curl returns exit 22
# when --fail is set and the response status code is >= 400. The 4xx/5xx
# fixtures shipped here imply this surface is in scope; modeling it
# faithfully is the difference between tests that catch real failures and
# tests that pass for the wrong reasons (Mockito-style strictness — Netflix
# 2018 mocking lessons).
# -----------------------------------------------------------------------------
if [[ "$FAIL_FLAG" == "1" && "$STATUS_CODE" -ge 400 ]]; then
    _dbg "FAIL_FLAG=1 + status=$STATUS_CODE — emitting exit 22 (CURLE_HTTP_RETURNED_ERROR)"
    if [[ -n "$STDERR_TEXT" && "$SILENT" != "1" ]]; then
        printf '%s\n' "$STDERR_TEXT" >&2
    else
        # Real curl writes a brief diagnostic on --fail; preserve fidelity
        printf 'curl: (22) The requested URL returned error: %s\n' "$STATUS_CODE" >&2
    fi
    exit 22
fi

# -----------------------------------------------------------------------------
# Emit response. With -i/--include, prepend HTTP status line + headers.
# Without, just emit body. Direct to OUTPUT_FILE if -o was passed.
# -----------------------------------------------------------------------------
_emit_response() {
    if [[ "$INCLUDE_HEADERS" == "1" ]]; then
        printf 'HTTP/1.1 %s\r\n' "$STATUS_CODE"
        # yq is now a hard requirement (see early guard); always available here.
        yq -r '.headers // {} | to_entries | .[] | "\(.key): \(.value)"' "$FIXTURE_PATH" 2>/dev/null \
            | while IFS= read -r line; do
                [[ -n "$line" ]] && printf '%s\r\n' "$line"
            done
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
