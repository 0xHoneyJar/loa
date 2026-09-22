#!/usr/bin/env bash
# claude-stub.sh — stand-in for the `claude` CLI used by evals/tests/*.bats.
# Records argv + selected env, optionally writes files into the cwd, and
# emits a canned stream-json transcript so execute-agent.sh can be tested
# without a model call.
#
#   STUB_ARGV_FILE   where "$@" is written (one arg per line)
#   STUB_ENV_FILE    where selected env vars are written (KEY=VALUE)
#   STUB_EVENTS_FILE stream-json lines to emit (default: a 2-write transcript)
#   STUB_WRITE_<n>   "relative/path::content" files to create in the cwd
#   STUB_EXIT        exit code (default 0)
set -euo pipefail

if [[ -n "${STUB_ARGV_FILE:-}" ]]; then
  printf '%s\n' "$@" > "$STUB_ARGV_FILE"
fi
if [[ -n "${STUB_ENV_FILE:-}" ]]; then
  {
    printf 'PWD=%s\n' "$PWD"
    for k in LOA_MODELINV_LOG_PATH LOA_COST_LEDGER_PATH HOME EVAL_MODEL TMPDIR GH_TOKEN GITHUB_TOKEN OPENAI_API_KEY AWS_SECRET_ACCESS_KEY; do
      printf '%s=%s\n' "$k" "${!k:-}"
    done
  } > "$STUB_ENV_FILE"
fi

for var in "${!STUB_WRITE_@}"; do
  spec="${!var}"
  rel="${spec%%::*}"
  body="${spec#*::}"
  mkdir -p "$(dirname "$rel")"
  printf '%b' "$body" > "$rel"
done

if [[ -n "${STUB_EVENTS_FILE:-}" && -f "${STUB_EVENTS_FILE}" ]]; then
  cat "$STUB_EVENTS_FILE"
else
  cat <<'EVENTS'
{"type":"system","subtype":"init","model":"claude-sonnet-5"}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"tests/test_x.py","content":"def test_x(): assert False"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"src/x.py","content":"X = 1"}}]}}
{"type":"result","subtype":"success","is_error":false,"duration_ms":1234,"num_turns":3,"result":"done","total_cost_usd":0.0123,"usage":{"input_tokens":100,"output_tokens":42,"cache_creation_input_tokens":5,"cache_read_input_tokens":7},"modelUsage":{"claude-sonnet-5-20260401":{"inputTokens":100,"outputTokens":42,"cacheReadInputTokens":7,"cacheCreationInputTokens":5,"costUSD":0.0123}}}
EVENTS
fi

exit "${STUB_EXIT:-0}"
