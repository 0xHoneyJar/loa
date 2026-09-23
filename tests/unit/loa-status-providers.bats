#!/usr/bin/env bats
# =============================================================================
# tests/unit/loa-status-providers.bats — cycle-125 Sprint 4 (PRD FR-4 AC 2)
# `/loa` Providers block: per provider the credential PRESENCE (never the
# value), the CLI hop on PATH, and every breaker bucket with state / age /
# probe timing; `--json` mirrors it. Fixture run dir via the bats-gated
# LOA_STATUS_RUN_DIR seam.
# =============================================================================

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  STATUS="$PROJECT_ROOT/.claude/scripts/loa-status.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/lsp.XXXXXX")"
  mkdir -p "$T/run"
  export LOA_STATUS_RUN_DIR="$T/run"
  now=$(date +%s)
  printf '{"provider":"google","auth_type":"http_api","state":"OPEN","failure_count":5,"opened_at":%d,"half_open_probes":0}\n' $(( now - 7200 )) > "$T/run/circuit-breaker-google-http_api.json"
  printf '{"provider":"openai","auth_type":"http_api","state":"CLOSED","failure_count":0,"opened_at":null,"half_open_probes":0}\n' > "$T/run/circuit-breaker-openai-http_api.json"
  printf '{"state":"CLOSED"}\n' > "$T/run/circuit-breaker.json"   # run-mode ICE breaker: not a provider bucket
  export OPENAI_API_KEY="sk-test-value-must-never-print"
  unset GOOGLE_API_KEY GEMINI_API_KEY
}
teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

@test "LSP-1 human output: Providers block lists presence, hop and buckets; OPEN carries age and probe timing; no credential value" {
  run timeout 120 bash "$STATUS"
  [ "$status" -eq 0 ]
  block=$(echo "$output" | sed -n '/^Providers/,/reset: cheval --reset-breaker/p')
  [ -n "$block" ]
  echo "$block" | grep -qE '^  openai +key present +hop [a-z-]+ +· http_api CLOSED'
  echo "$block" | grep -qE '^  google +key absent +hop [a-z-]+ +· http_api OPEN 2h \(probe overdue → HALF_OPEN on next call\)'
  echo "$block" | grep -qE '^  anthropic +key (present|absent)'
  [[ "$output" != *"sk-test-value-must-never-print"* ]]
}

@test "LSP-2 --json mirrors the block under .providers and carries no credential value" {
  run timeout 120 bash "$STATUS" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.providers.reset_timeout_seconds | type == "number"' >/dev/null
  echo "$output" | jq -e '.providers.providers.google.credential == "absent" and .providers.providers.google.breakers.http_api.state == "OPEN" and .providers.providers.google.breakers.http_api.probe_due_in_s == 0' >/dev/null
  echo "$output" | jq -e '.providers.providers.openai.credential == "present" and .providers.providers.openai.breakers.http_api.state == "CLOSED"' >/dev/null
  echo "$output" | jq -e '.providers.providers | has("anthropic")' >/dev/null
  [[ "$output" != *"sk-test-value-must-never-print"* ]]
}

@test "LSP-3 a provider with no breaker state is still listed (credential and hop only)" {
  rm "$T/run"/circuit-breaker-*.json
  run timeout 120 bash "$STATUS"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^  anthropic +key (present|absent) +hop [a-z-]+ +no breaker state'
}
