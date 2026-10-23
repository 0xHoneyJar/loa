#!/usr/bin/env bash
# claude-ablation-stub.sh — wraps evals/tests/fixtures/claude-stub.sh for the
# cycle-130 bats (run-arms.bats, arm-toggles.bats). No model call.
#
#   STUB_COST_USD      the result event's total_cost_usd (default: the base stub's
#                      canned transcript is used unchanged)
#   STUB_FULL_ENV_FILE the complete environment (`env`) is written there
#   STUB_CONC_DIR      concurrency probe: each call registers itself in the dir
#                      for STUB_SLEEP seconds and appends the number of calls
#                      running at its start to <dir>.log
#   STUB_SLEEP         seconds to stay registered (default 0)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$HERE/../claude-stub.sh"
if [[ "${1:-}" == "--version" ]]; then exec "$BASE" --version; fi

if [[ -n "${STUB_FULL_ENV_FILE:-}" ]]; then env > "$STUB_FULL_ENV_FILE"; fi
if [[ -n "${STUB_CONC_DIR:-}" ]]; then
  mkdir -p "$STUB_CONC_DIR"
  : > "$STUB_CONC_DIR/$$"
  ls "$STUB_CONC_DIR" | wc -l | tr -d ' ' >> "$STUB_CONC_DIR.log"
  sleep "${STUB_SLEEP:-0}"
  rm -f "$STUB_CONC_DIR/$$"
fi
if [[ -n "${STUB_COST_USD:-}" ]]; then
  ev="$(mktemp "${TMPDIR:-/tmp}/stub-events.XXXXXX")"
  cat > "$ev" <<EVENTS
{"type":"system","subtype":"init","model":"claude-sonnet-5"}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"review.md","content":"r"}}]}}
{"type":"result","subtype":"success","is_error":false,"duration_ms":1000,"num_turns":2,"result":"done","total_cost_usd":${STUB_COST_USD},"usage":{"input_tokens":10,"output_tokens":5},"modelUsage":{"claude-sonnet-5-20260401":{"inputTokens":10,"outputTokens":5,"costUSD":${STUB_COST_USD}}}}
EVENTS
  export STUB_EVENTS_FILE="$ev"
fi
exec "$BASE" "$@"
