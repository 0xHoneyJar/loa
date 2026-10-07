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
  unset GOOGLE_API_KEY GEMINI_API_KEY ANTHROPIC_API_KEY
  mkdir -p "$T/env"; export LOA_STATUS_ENV_DIR="$T/env"   # bats-gated dotenv dir (no .env files → absent unless env)
  export LOA_STATUS_CONFIG_FILE="$T/no-loa-config.yaml"   # bats-gated: no config → the agy opt-in is off (cycle-127 FR-1)
}
teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

@test "LSP-1 human output: Providers block lists presence, hop and buckets; OPEN carries age and probe timing; no credential value" {
  run timeout 120 bash "$STATUS" --no-stale-check
  [ "$status" -eq 0 ]
  block=$(echo "$output" | sed -n '/^Providers/,/reset: cheval --reset-breaker/p')
  [ -n "$block" ]
  echo "$block" | grep -qE '^  openai +key present \(env\) +hop [a-z-]+ +· http_api CLOSED'
  echo "$block" | grep -qE '^  google +key absent +hop agy: opt-in \(disabled; hounfour\.headless\.agy_opt_in\) +· http_api OPEN 2h \(probe overdue → HALF_OPEN on next call\)'
  echo "$block" | grep -qE '^  anthropic +key absent'
  [[ "$output" != *"sk-test-value-must-never-print"* ]]
}

@test "LSP-4 a key present only in .env.local counts as present (same rule as the preflight) and its value never prints" {
  printf 'ANTHROPIC_API_KEY="sk-ant-from-dotenv-never-print"\nGOOGLE_API_KEY=\n' > "$T/env/.env.local"
  run timeout 120 bash "$STATUS" --no-stale-check
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^  anthropic +key present \(\.env\.local\)'
  echo "$output" | grep -qE '^  google +key absent'
  [[ "$output" != *"sk-ant-from-dotenv-never-print"* ]]
  run timeout 120 bash "$STATUS" --no-stale-check --json
  echo "$output" | jq -e '.providers.providers.anthropic.credential == "present (.env.local)" and .providers.providers.google.credential == "absent"' >/dev/null
}

@test "LSP-2 --json mirrors the block under .providers and carries no credential value" {
  run timeout 120 bash "$STATUS" --no-stale-check --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.providers.reset_timeout_seconds | type == "number"' >/dev/null
  echo "$output" | jq -e '.providers.providers.google.credential == "absent" and .providers.providers.google.breakers.http_api.state == "OPEN" and .providers.providers.google.breakers.http_api.probe_due_in_s == 0' >/dev/null
  echo "$output" | jq -e '.providers.providers.openai.credential == "present (env)" and .providers.providers.openai.breakers.http_api.state == "CLOSED"' >/dev/null
  echo "$output" | jq -e '.providers.providers | has("anthropic")' >/dev/null
  [[ "$output" != *"sk-test-value-must-never-print"* ]]
}

@test "LSP-3 a provider with no breaker state is still listed (credential and hop only)" {
  rm "$T/run"/circuit-breaker-*.json
  run timeout 120 bash "$STATUS" --no-stale-check
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^  anthropic +key (present|absent) +hop [a-z-]+ +no breaker state'
}

@test "LSP-5 the anthropic row carries the input bound the opus target runs under: probed by default, observed after a provider verdict, never a 429 (cycle-126 FR-1.1)" {
  # cycle-127 FR-3.4: the values follow the catalog (the probe may calibrate the opus target);
  # the policy is pinned per state — uncalibrated: probed, lowered only by a context-class
  # observation below it; calibrated: the measured bound, observations never lower it.
  local cfg="$PROJECT_ROOT/.claude/defaults/model-config.yaml" m probed eff cal
  m="$(yq -r '.aliases.opus' "$cfg")"; m="${m#anthropic:}"
  probed="$(yq -r ".providers.anthropic.models.\"$m\".probed_ceiling" "$cfg")"
  eff="$(yq -r ".providers.anthropic.models.\"$m\".effective_input_ceiling" "$cfg")"
  cal="$(yq -r ".providers.anthropic.models.\"$m\".ceiling_calibration.calibrated_at // \"\"" "$cfg")"
  [[ "$probed" =~ ^[0-9]+$ && "$eff" =~ ^[0-9]+$ ]]
  local above=$(( probed + 232000 )) below=$(( probed - 30000 ))
  unset LOA_CHEVAL_CEILING_OBSERVED_PATH
  export LOA_CHEVAL_CEILING_OBSERVED_PATH="$T/none.json"   # no store → the catalog's bound
  run timeout 120 bash "$STATUS" --no-stale-check
  [ "$status" -eq 0 ]
  if [[ -n "$cal" ]]; then
    echo "$output" | grep -qF "  ceiling: calibrated $eff ($m, calibrated $cal)"
  else
    echo "$output" | grep -qE "^  ceiling: probed $probed \($m; calibrate: python3 tools/ceiling-probe-live.py --model $m --write-catalog\)"
  fi
  printf '{"version":1,"entries":[{"provider":"anthropic","model":"%s","observed_input_tokens":%d,"error_class":"RATE_LIMIT_UNVERIFIED"},{"provider":"anthropic","model":"%s","observed_input_tokens":%d,"error_class":"CEILING_UNVERIFIED_LIMIT"}]}\n' "$m" $(( above + 88000 )) "$m" "$above" > "$T/obs.json"
  export LOA_CHEVAL_CEILING_OBSERVED_PATH="$T/obs.json"
  run timeout 120 bash "$STATUS" --no-stale-check
  [ "$status" -eq 0 ]
  if [[ -n "$cal" ]]; then
    echo "$output" | grep -qF "  ceiling: calibrated $eff ($m, calibrated $cal)"
  else
    # an observation above the probed bound: the default bound stands, the observation is shown for the opt-in
    echo "$output" | grep -qE "^  ceiling: probed $probed \($m; observed $(( above - 1 )) under the opt-in; calibrate: python3 tools/ceiling-probe-live.py"
  fi
  run timeout 120 bash "$STATUS" --no-stale-check --json
  [ "$status" -eq 0 ]
  if [[ -n "$cal" ]]; then
    echo "$output" | jq -e --argjson e "$eff" '.providers.providers.anthropic.ceiling.basis == "calibrated" and .providers.providers.anthropic.ceiling.value == $e and .providers.providers.openai.ceiling == null' >/dev/null
  else
    echo "$output" | jq -e --argjson o "$(( above - 1 ))" '.providers.providers.anthropic.ceiling.basis == "probed" and .providers.providers.anthropic.ceiling.observed == $o and .providers.providers.openai.ceiling == null' >/dev/null
  fi
  # an observation BELOW the probed bound becomes the bound (uncalibrated) / never lowers a calibrated one
  printf '{"version":1,"entries":[{"provider":"anthropic","model":"%s","observed_input_tokens":%d,"error_class":"PROVIDER_CONTEXT_LIMIT"}]}\n' "$m" "$below" > "$T/obs.json"
  run timeout 120 bash "$STATUS" --no-stale-check
  [ "$status" -eq 0 ]
  if [[ -n "$cal" ]]; then
    echo "$output" | grep -qF "  ceiling: calibrated $eff ($m, calibrated $cal)"
  else
    echo "$output" | grep -qE "^  ceiling: observed $(( below - 1 )) \($m; calibrate: python3 tools/ceiling-probe-live.py"
  fi
}

@test "LSP-AGY the google hop reads agy: opt-in (disabled; hounfour.headless.agy_opt_in) while the opt-in is off, today's hop text when it is true (cycle-127 FR-1)" {
  mkdir -p "$T/bin"; printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/agy"; chmod +x "$T/bin/agy"
  export PATH="$T/bin:$PATH"
  printf 'hounfour:\n  headless:\n    mode: cli-only\n' > "$T/loa.config.yaml"
  export LOA_STATUS_CONFIG_FILE="$T/loa.config.yaml"
  run timeout 120 bash "$STATUS" --no-stale-check
  [ "$status" -eq 0 ] || { echo "rc=$status"; echo "$output" | tail -20; return 1; }
  echo "$output" | grep -qE '^  google +key absent +hop agy: opt-in \(disabled; hounfour\.headless\.agy_opt_in\)'
  run timeout 120 bash "$STATUS" --no-stale-check --json
  echo "$output" | jq -e '.providers.providers.google.cli_hop == null and .providers.providers.google.cli_hop_note == "agy: opt-in (disabled; hounfour.headless.agy_opt_in)"' >/dev/null
  echo "$output" | jq -e '.providers.providers.openai | has("cli_hop_note") | not' >/dev/null
  printf 'hounfour:\n  headless:\n    agy_opt_in: true\n' > "$T/loa.config.yaml"
  run timeout 120 bash "$STATUS" --no-stale-check
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^  google +key absent +hop agy +· http_api OPEN'
  run timeout 120 bash "$STATUS" --no-stale-check --json
  echo "$output" | jq -e '.providers.providers.google.cli_hop == "agy" and (.providers.providers.google | has("cli_hop_note") | not)' >/dev/null
}
