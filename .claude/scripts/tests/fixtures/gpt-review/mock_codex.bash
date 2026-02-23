#!/usr/bin/env bash
# mock_codex.bash — Mock codex binary for testing
#
# Behavior controlled by environment variables:
#   MOCK_CODEX_BEHAVIOR: success|fail|timeout|bad_json|no_verdict|version_old
#   MOCK_CODEX_VERSION: version string (default: "codex 0.2.0")
#   MOCK_CODEX_RESPONSE: custom JSON response (overrides behavior for exec)
#   MOCK_CODEX_EXIT_CODE: custom exit code (default: behavior-dependent)
#   MOCK_CODEX_CAPS: comma-separated list of unsupported flags (default: none)

set -euo pipefail

BEHAVIOR="${MOCK_CODEX_BEHAVIOR:-success}"
VERSION="${MOCK_CODEX_VERSION:-codex 0.2.0}"

case "${1:-}" in
  --version)
    echo "$VERSION"
    exit 0
    ;;
  exec)
    shift
    # Parse flags to find --output-last-message target
    output_file=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --output-last-message) output_file="$2"; shift 2 ;;
        --help)
          echo "Usage: codex exec [options]"
          echo "Options:"
          echo "  --sandbox <mode>        Sandbox mode"
          echo "  --ephemeral             Ephemeral session"
          echo "  --output-last-message   Write last message to file"
          echo "  --cd <dir>              Working directory"
          echo "  --skip-git-repo-check   Skip git check"
          echo "  --model <model>         Model to use"
          echo "  --json                  JSON output"
          # Check for unsupported caps
          if [[ -n "${MOCK_CODEX_CAPS:-}" ]]; then
            for cap in ${MOCK_CODEX_CAPS//,/ }; do
              echo "  (unsupported: $cap)"
            done
          fi
          exit 0
          ;;
        *) shift ;;
      esac
    done

    # Multi-pass state tracking: increment call counter and load per-call overrides
    if [[ -n "${MOCK_CODEX_STATE_DIR:-}" ]]; then
      count_file="$MOCK_CODEX_STATE_DIR/call-count"
      if [[ -f "$count_file" ]]; then
        call_num=$(($(cat "$count_file") + 1))
      else
        call_num=1
      fi
      echo "$call_num" > "$count_file"
      # Per-call behavior override
      behav_file="$MOCK_CODEX_STATE_DIR/behavior-${call_num}"
      [[ -f "$behav_file" ]] && BEHAVIOR=$(cat "$behav_file")
      # Per-call response override
      resp_file="$MOCK_CODEX_STATE_DIR/response-${call_num}.json"
      [[ -f "$resp_file" ]] && MOCK_CODEX_RESPONSE=$(cat "$resp_file")
    fi

    case "$BEHAVIOR" in
      success)
        _default_resp='{"verdict":"APPROVED","summary":"All looks good","findings":[]}'
        response="${MOCK_CODEX_RESPONSE:-$_default_resp}"
        if [[ -n "$output_file" ]]; then
          echo "$response" > "$output_file"
        fi
        exit "${MOCK_CODEX_EXIT_CODE:-0}"
        ;;
      fail)
        echo "Error: codex exec failed" >&2
        exit "${MOCK_CODEX_EXIT_CODE:-1}"
        ;;
      timeout)
        sleep 999
        ;;
      bad_json)
        bad="This is not valid JSON at all"
        if [[ -n "$output_file" ]]; then
          echo "$bad" > "$output_file"
        fi
        exit 0
        ;;
      no_verdict)
        nv='{"summary":"Missing verdict field","findings":[]}'
        if [[ -n "$output_file" ]]; then
          echo "$nv" > "$output_file"
        fi
        exit 0
        ;;
      version_old)
        # This shouldn't reach exec — codex_is_available should fail first
        echo "Error: version too old" >&2
        exit 1
        ;;
    esac
    ;;
  *)
    echo "Unknown command: ${1:-}" >&2
    exit 1
    ;;
esac
