#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
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

_lsp5_catalog() {  # $1 file, $2 calibrated_at ("" = uncalibrated), $3 transport ("" = absent); bound 200000 / 936000
  local cal_block=""
  if [[ -n "$2" ]]; then
    cal_block="          source: operator_set
          calibrated_at: \"$2\"
          stale_after_days: 90"
    [[ -n "$3" ]] && cal_block+="
          transport: $3"
  else
    cal_block="          source: conservative_default
          calibrated_at: null
          stale_after_days: 90"
  fi
  local bound=200000; [[ -n "$2" ]] && bound=936000
  cat > "$1" <<YAML
aliases:
  opus: "anthropic:claude-fixture-1"
providers:
  anthropic:
    models:
      claude-fixture-1:
        context_window: 1000000
        effective_input_ceiling: $bound
        probed_ceiling: $bound
        ceiling_calibration:
$cal_block
YAML
}
_lsp5_obs() {  # $1 model, then (tokens class) pairs → the observed store at $T/obs.json
  local m="$1" rows="" sep=""; shift
  while (( $# >= 2 )); do
    rows+="$sep{\"provider\":\"anthropic\",\"model\":\"$m\",\"observed_input_tokens\":$1,\"error_class\":\"$2\"}"; sep=","; shift 2
  done
  printf '{"version":1,"entries":[%s]}\n' "$rows" > "$T/obs.json"
  export LOA_CHEVAL_CEILING_OBSERVED_PATH="$T/obs.json"
}

@test "LSP-5a the anthropic row carries the committed catalog's input bound for the opus target (cycle-126 FR-1.1, cycle-127 FR-3.4)" {
  # The committed entry, whatever its state (the probe may calibrate it; a rollback may not):
  # one assertion per state. Both states also run on every pass against fixtures (LSP-5b/5c/5d).
  local cfg="$PROJECT_ROOT/.claude/defaults/model-config.yaml" m probed eff cal
  m="$(yq -r '.aliases.opus' "$cfg")"; m="${m#anthropic:}"
  probed="$(yq -r ".providers.anthropic.models.\"$m\".probed_ceiling" "$cfg")"
  eff="$(yq -r ".providers.anthropic.models.\"$m\".effective_input_ceiling" "$cfg")"
  cal="$(yq -r ".providers.anthropic.models.\"$m\".ceiling_calibration.calibrated_at // \"\"" "$cfg")"
  [[ "$probed" =~ ^[0-9]+$ && "$eff" =~ ^[0-9]+$ ]]
  export LOA_CHEVAL_CEILING_OBSERVED_PATH="$T/none.json"   # no store → the catalog's bound
  run timeout 120 bash "$STATUS" --no-stale-check
  [ "$status" -eq 0 ]
  if [[ -n "$cal" ]]; then
    echo "$output" | grep -qF "  ceiling: calibrated $eff ($m, calibrated $cal)"
  else
    echo "$output" | grep -qF "  ceiling: probed $probed ($m; calibrate: python3 tools/ceiling-probe-live.py --model $m --write-catalog)"
  fi
}

@test "LSP-5b an uncalibrated entry (fixture catalog): probed by default, observed after a provider verdict below it, never a 429" {
  _lsp5_catalog "$T/catalog.yaml" "" ""
  export LOA_STATUS_MODEL_CONFIG="$T/catalog.yaml"
  local m=claude-fixture-1
  export LOA_CHEVAL_CEILING_OBSERVED_PATH="$T/none.json"
  run timeout 120 bash "$STATUS" --no-stale-check
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "  ceiling: probed 200000 ($m; calibrate: python3 tools/ceiling-probe-live.py --model $m --write-catalog)"
  # an observation above the probed bound: the default bound stands, the observation is shown for the opt-in; a 429 row never counts
  _lsp5_obs "$m" 500000 RATE_LIMIT_UNVERIFIED 412000 CEILING_UNVERIFIED_LIMIT
  run timeout 120 bash "$STATUS" --no-stale-check
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "  ceiling: probed 200000 ($m; observed 411999 under the opt-in; calibrate: python3 tools/ceiling-probe-live.py --model $m --write-catalog)"
  run timeout 120 bash "$STATUS" --no-stale-check --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.providers.providers.anthropic.ceiling | .basis == "probed" and .value == 200000 and .observed == 411999' >/dev/null
  echo "$output" | jq -e '.providers.providers.openai.ceiling == null' >/dev/null
  # an observation BELOW the probed bound becomes the bound
  _lsp5_obs "$m" 150000 PROVIDER_CONTEXT_LIMIT
  run timeout 120 bash "$STATUS" --no-stale-check
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "  ceiling: observed 149999 ($m; calibrate: python3 tools/ceiling-probe-live.py --model $m --write-catalog)"
}

@test "LSP-5c a same-route calibration (transport api or absent, fixture catalog) is never lowered by an observation" {
  local m=claude-fixture-1 t
  for t in api ""; do
    _lsp5_catalog "$T/catalog.yaml" "2026-10-07T09:29:07Z" "$t"
    export LOA_STATUS_MODEL_CONFIG="$T/catalog.yaml"
    _lsp5_obs "$m" 500001 PROVIDER_CONTEXT_LIMIT
    run timeout 120 bash "$STATUS" --no-stale-check
    [ "$status" -eq 0 ]
    echo "$output" | grep -qF "  ceiling: calibrated 936000 ($m, calibrated 2026-10-07T09:29:07Z)"
    [[ "$output" != *"below on this route"* ]]
    run timeout 120 bash "$STATUS" --no-stale-check --json
    echo "$output" | jq -e '.providers.providers.anthropic.ceiling | .basis == "calibrated" and .value == 936000' >/dev/null
  done
}

@test "LSP-5d a foreign-transport calibration (claude-headless, fixture catalog) is tightened by an observation below it on this route and says so (cycle-127 r251-1)" {
  local m=claude-fixture-1
  _lsp5_catalog "$T/catalog.yaml" "2026-10-07T09:29:07Z" claude-headless
  export LOA_STATUS_MODEL_CONFIG="$T/catalog.yaml"
  # an observation above the calibrated bound: the calibration stands
  _lsp5_obs "$m" 990000 PROVIDER_CONTEXT_LIMIT
  run timeout 120 bash "$STATUS" --no-stale-check
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "  ceiling: calibrated 936000 ($m, calibrated 2026-10-07T09:29:07Z)"
  # below it (a 429 row never counts): the observed bound governs and the line names both
  _lsp5_obs "$m" 300000 RATE_LIMIT_UNVERIFIED 500001 PROVIDER_CONTEXT_LIMIT
  run timeout 120 bash "$STATUS" --no-stale-check
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "  ceiling: calibrated 936000 (claude-headless); observed 500000 below on this route, reprobe suggested ($m, calibrated 2026-10-07T09:29:07Z; calibrate: python3 tools/ceiling-probe-live.py --model $m --write-catalog)"
  run timeout 120 bash "$STATUS" --no-stale-check --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.providers.providers.anthropic.ceiling | .basis == "observed" and .value == 500000 and .calibrated == true
    and .calibrated_value == 936000 and .calibration_transport == "claude-headless" and .reprobe_suggested == true
    and .calibrated_at == "2026-10-07T09:29:07Z"' >/dev/null
}

@test "LSP-AGY the google hop reads agy: opt-in (disabled; hounfour.headless.agy_opt_in) while the opt-in is off, today's hop text when it is true (cycle-127 FR-1)" {
  mkdir -p "$T/bin"; printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/agy"; chmod +x "$T/bin/agy"
  export PATH="$T/bin:$PATH"
  printf 'hounfour:\n  headless:\n    mode: cli-only\n' > "$T/loa.config.yaml"
  export LOA_STATUS_CONFIG_FILE="$T/loa.config.yaml"
  run timeout 120 bash "$STATUS" --no-stale-check
  [ "$status" -eq 0 ] || { echo "rc=$status"; echo "$output" | tail -20; return 1; }
  echo "$output" | grep -qE '^  google +key absent +hop agy: opt-in \(disabled; hounfour\.headless\.agy_opt_in\)'
  run --separate-stderr timeout 120 bash "$STATUS" --no-stale-check --json
  echo "$output" | jq -e '.providers.providers.google.cli_hop == null and .providers.providers.google.cli_hop_note == "agy: opt-in (disabled; hounfour.headless.agy_opt_in)"' >/dev/null
  echo "$output" | jq -e '.providers.providers.openai | has("cli_hop_note") | not' >/dev/null
  # (review r251-1 G12: the string "true" is not the boolean — off, and one WARN naming the key and the type)
  printf 'hounfour:\n  headless:\n    agy_opt_in: "true"\n' > "$T/loa.config.yaml"
  run --separate-stderr timeout 120 bash "$STATUS" --no-stale-check
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^  google +key absent +hop agy: opt-in \(disabled; hounfour\.headless\.agy_opt_in\)'
  [ "$(grep -c 'hounfour.headless.agy_opt_in.*not a YAML boolean' <<<"$stderr")" = 1 ] || { echo "stderr=$stderr"; return 1; }
  printf 'hounfour:\n  headless:\n    agy_opt_in: true\n' > "$T/loa.config.yaml"
  run timeout 120 bash "$STATUS" --no-stale-check
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^  google +key absent +hop agy +· http_api OPEN'
  run --separate-stderr timeout 120 bash "$STATUS" --no-stale-check --json
  echo "$output" | jq -e '.providers.providers.google.cli_hop == "agy" and (.providers.providers.google | has("cli_hop_note") | not)' >/dev/null
}
