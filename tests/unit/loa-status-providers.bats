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
  # (r251-5 U1/U2: every agy opt-in reader refuses a group- or world-writable config — fixtures are written owner-only
  # whatever the host umask; a `>` redirect under umask 002 makes 0664)
  umask 022
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

_lsp5_catalog() {  # $1 file, $2 calibrated_at ("" = uncalibrated), $3 transport ("" = absent); bound 200000 / 920000 (fixture values, not the live catalog — r251-3 R2)
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
  local bound=200000; [[ -n "$2" ]] && bound=920000
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
    echo "$output" | grep -qF "  ceiling: calibrated 920000 ($m, calibrated 2026-10-07T09:29:07Z)"
    [[ "$output" != *"below on this route"* ]]
    run timeout 120 bash "$STATUS" --no-stale-check --json
    echo "$output" | jq -e '.providers.providers.anthropic.ceiling | .basis == "calibrated" and .value == 920000' >/dev/null
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
  echo "$output" | grep -qF "  ceiling: calibrated 920000 ($m, calibrated 2026-10-07T09:29:07Z)"
  # below it (a 429 row never counts): the observed bound governs and the line names both
  _lsp5_obs "$m" 300000 RATE_LIMIT_UNVERIFIED 500001 PROVIDER_CONTEXT_LIMIT
  run timeout 120 bash "$STATUS" --no-stale-check
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "  ceiling: calibrated 920000 (claude-headless); observed 500000 below on this route, reprobe suggested ($m, calibrated 2026-10-07T09:29:07Z; calibrate: python3 tools/ceiling-probe-live.py --model $m --write-catalog)"
  run timeout 120 bash "$STATUS" --no-stale-check --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.providers.providers.anthropic.ceiling | .basis == "observed" and .value == 500000 and .calibrated == true
    and .calibrated_value == 920000 and .calibration_transport == "claude-headless" and .reprobe_suggested == true
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

@test "LSP-6 (r251-4 S8, audit n11) the opus target reaches yq as a value, never as expression text" {
  # an alias crafted to rewrite the old interpolated expression into `… // 777 // …`
  cat > "$T/catalog.yaml" <<'YAML'
aliases:
  opus: 'anthropic:zz" // 777 // ."zz'
providers:
  anthropic:
    models:
      claude-fixture-1:
        context_window: 1000000
        effective_input_ceiling: 200000
        probed_ceiling: 200000
YAML
  export LOA_STATUS_MODEL_CONFIG="$T/catalog.yaml"
  export LOA_CHEVAL_CEILING_OBSERVED_PATH="$T/none.json"
  run timeout 120 bash "$STATUS" --no-stale-check --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.providers.providers.anthropic.ceiling.value != 777' >/dev/null || { echo "$output" | jq -c '.providers.providers.anthropic.ceiling'; return 1; }
  # (and the printed probe command quotes the id, as cheval's hint does — audit n4)
  echo "$output" | jq -e '.providers.providers.anthropic.ceiling.calibrate == ("python3 tools/ceiling-probe-live.py --model " + ("zz\" // 777 // .\"zz" | @sh) + " --write-catalog")' >/dev/null || { echo "$output" | jq -c '.providers.providers.anthropic.ceiling'; return 1; }
}

@test "LSP-7 (r251-4 S7 parity with routing.ceiling) an implausible observation (below 0.1 × the window) never becomes the displayed bound" {
  _lsp5_catalog "$T/catalog.yaml" "" ""
  export LOA_STATUS_MODEL_CONFIG="$T/catalog.yaml"
  local m=claude-fixture-1
  _lsp5_obs "$m" 1 PROVIDER_CONTEXT_LIMIT 150000 PROVIDER_CONTEXT_LIMIT
  run timeout 120 bash "$STATUS" --no-stale-check --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.providers.providers.anthropic.ceiling | .basis == "observed" and .value == 149999' >/dev/null || { echo "$output" | jq -c '.providers.providers.anthropic.ceiling'; return 1; }
  _lsp5_obs "$m" 1 PROVIDER_CONTEXT_LIMIT
  run timeout 120 bash "$STATUS" --no-stale-check --json
  echo "$output" | jq -e '.providers.providers.anthropic.ceiling | .basis == "probed" and .value == 200000' >/dev/null || { echo "$output" | jq -c '.providers.providers.anthropic.ceiling'; return 1; }
}

@test "LSP-8 (r251-4, sibling of S4) without lib/agy-gate-lib.sh /loa still answers: exit 0, the agy route reads off (fail closed), one WARN in human mode, --json quiet" {
  local S="$T/copy/.claude/scripts"; mkdir -p "$S"
  cp -- "$STATUS" "$S/loa-status.sh"   # (no lib/ beside it — a partial install)
  run --separate-stderr timeout 120 bash "$S/loa-status.sh" --no-stale-check --json
  [ "$status" -eq 0 ] || { echo "status=$status stderr=$stderr"; return 1; }
  echo "$output" | jq -e '.providers.providers.google.cli_hop == null and .providers.providers.google.cli_hop_note == "agy: opt-in (disabled; hounfour.headless.agy_opt_in)"' >/dev/null || { echo "$output" | jq -c '.providers.providers.google'; return 1; }
  [[ "$stderr" != *"agy-gate-lib"* ]] || { echo "--json warned: $stderr"; return 1; }
  run --separate-stderr timeout 120 bash "$S/loa-status.sh" --no-stale-check
  [ "$status" -eq 0 ]
  [ "$(grep -c 'agy-gate-lib.sh.*not loaded' <<<"$stderr")" = 1 ] || { echo "stderr=$stderr"; return 1; }
}

@test "LSP-COLD (r251-5 U4, audit LOW-004) loa-status --json on a cold workflow-state cache is one valid JSON document" {
  # (the AGC-6 batch flake: the first --json call after a grimoire edit missed the workflow-state cache, cache-manager's
  # "v Cached result for key" line led workflow-state's stdout, and the final jq merge exited 5 — no retry hides it here:
  # CACHE_DIR is a fresh directory, so this call is always the miss)
  run --separate-stderr env CACHE_DIR="$T/cold-cache" LOA_STATUS_RUN_DIR="$T/run" LOA_STATUS_ENV_DIR="$T/env" \
      timeout 180 bash "$STATUS" --no-stale-check --json
  [ "$status" -eq 0 ] || { echo "status=$status stderr=$stderr"; return 1; }
  jq -e '.providers.providers | type == "object"' >/dev/null <<<"$output" || { printf '%s\n' "$output" | head -5 | cat -v; return 1; }
}

# ---- cycle-137 FR-3 (Task 2.3a, bd-gv5jf): the ceiling read is ONE yq program printing six lines ----
_lsp9_fn() {  # the two catalog functions, extracted from the script under test (it has no source guard) → $T/fn.sh
  awk '/^_providers_model_config\(\) *\{/,/^}/' "$STATUS" > "$T/fn.sh"
  awk '/^_anthropic_ceiling_json\(\) *\{/,/^}/' "$STATUS" >> "$T/fn.sh"
  grep -q '^_anthropic_ceiling_json' "$T/fn.sh"
}
_lsp9_run() {  # $1 catalog [$2 PATH] → stdout the ceiling JSON; xtrace (PS4='+') of the call → $T/trace
  env PATH="${2:-$PATH}" PS4='+' BATS_VERSION="${BATS_VERSION:-1}" LOA_STATUS_MODEL_CONFIG="$1" \
      LOA_CHEVAL_CEILING_OBSERVED_PATH="$T/none.json" PROJECT_ROOT="$T" \
      "$BASH" -c 'source "$1"; set -x; _anthropic_ceiling_json' _ "$T/fn.sh" 2>"$T/trace"
}
_lsp9_yq_count() { grep -cE '^\++ *(M=[^ ]* )?yq eval' "$T/trace" || true; }
_lsp9_shim() {  # a yq on PATH that refuses the six-line program (forces the verbatim six-read fallback = the original code)
  mkdir -p "$T/shim"
  local real; real=$(command -v yq)
  printf '#!/usr/bin/env bash\ncase "$*" in *" as \\$m "*) exit 1 ;; esac\nexec %q "$@"\n' "$real" > "$T/shim/yq"
  chmod +x "$T/shim/yq"
}
_lsp9_case() {  # $1 name, catalog body on stdin → $T/c-$1.yaml
  cat > "$T/c-$1.yaml"
}
_lsp9_decoys() {  # $1 catalog: append decoy models before and after the target (every field differs from it), so a
  # lookup that is not bound to the target model prints extra lines or the wrong values
  yq -i '.providers.anthropic.models = ({"aa-decoy": {"context_window": 11, "effective_input_ceiling": 12, "probed_ceiling": 13,
           "ceiling_calibration": {"calibrated_at": "2001-01-01T00:00:00Z", "transport": "decoy-a"}}}
         + (.providers.anthropic.models // {})
         + {"zz-decoy": {"context_window": 21, "effective_input_ceiling": 22, "probed_ceiling": 23,
           "ceiling_calibration": {"calibrated_at": "2002-02-02T00:00:00Z", "transport": "decoy-z"}}})' "$1"
}

@test "LSP-9a (cycle-137 FR-3) a plain catalog takes the fast path: ONE yq call in the function's trace, no per-field read" {
  _lsp9_fn
  _lsp5_catalog "$T/catalog.yaml" "2026-10-07T09:29:07Z" "claude-headless"; _lsp9_decoys "$T/catalog.yaml"
  out=$(_lsp9_run "$T/catalog.yaml")
  [ "$(_lsp9_yq_count)" = 1 ] || { echo "yq calls: $(_lsp9_yq_count)"; grep 'yq' "$T/trace"; return 1; }
  ! grep -q 'strenv(M)' "$T/trace" || { grep 'strenv' "$T/trace"; return 1; }
  jq -e '.basis == "calibrated" and .value == 920000 and .model == "claude-fixture-1" and .calibration_transport == "claude-headless"' <<<"$out" >/dev/null || { echo "$out"; return 1; }
}

@test "LSP-9b (cycle-137 FR-3) the six-line read and the original six reads give the same JSON over the catalog matrix" {
  _lsp9_fn; _lsp9_shim
  printf 'providers:\n  anthropic:\n    models:\n      m1:\n        context_window: 5\n' | _lsp9_case alias-absent
  printf 'aliases:\n  opus: "anthropic:m1"\nproviders:\n  anthropic:\n    models:\n      m1:\n        context_window: 1000000\n' | _lsp9_case no-ceiling
  _lsp5_catalog "$T/c-all-five.yaml" "2026-10-07T09:29:07Z" "claude-headless"
  printf 'aliases:\n  opus: "anthropic:m1"\nproviders:\n  anthropic:\n    models:\n      m1:\n        context_window: null\n        effective_input_ceiling: null\n        probed_ceiling: null\n        ceiling_calibration:\n          calibrated_at: null\n          transport: null\n' | _lsp9_case nulls
  printf 'aliases:\n  opus: "anthropic:m1"\nproviders:\n  anthropic:\n    models:\n      m1:\n        context_window: false\n        effective_input_ceiling: false\n        probed_ceiling: 7\n        ceiling_calibration:\n          calibrated_at: false\n          transport: false\n' | _lsp9_case falses
  printf 'aliases:\n  opus: "anthropic:m1"\nproviders:\n  anthropic:\n    models:\n      m1:\n        effective_input_ceiling: 300\n        probed_ceiling: 300\n        ceiling_calibration:\n          calibrated_at: "2026-01-01T00:00:00Z"\n          transport: api\n        context_window: ""\n' | _lsp9_case empty-last
  printf 'aliases:\n  opus: "anthropic:m1"\nproviders:\n  anthropic:\n    models:\n      m1:\n        effective_input_ceiling: 300\n        ceiling_calibration:\n          calibrated_at: "2026-01-01T00:00:00Z"\n          transport: "claude-\\nheadless"\n' | _lsp9_case newline
  printf 'aliases:\n  opus: "anthropic:m1"\nproviders: [unclosed\n  anthropic: {\n' | _lsp9_case malformed
  printf 'aliases:\n  opus: "anthropic:m1"\nproviders:\n  anthropic:\n    models:\n      m1:\n        effective_input_ceiling: {a: 1}\n        probed_ceiling: {a: 1, b: 2}\n' | _lsp9_case map
  printf 'aliases:\n  opus: {x: 1}\n' | _lsp9_case alias-map
  printf 'aliases:\n  opus: "anthropic:"\n' | _lsp9_case alias-empty-model
  printf 'aliases:\n  opus: "anthropic:m1"\nproviders:\n  anthropic:\n    models:\n      m1:\n        effective_input_ceiling: &x 5\n        probed_ceiling: *x\n        context_window: *x\n' | _lsp9_case anchors
  local c new old
  for c in no-ceiling all-five nulls falses empty-last newline map anchors; do
    cp "$T/c-$c.yaml" "$T/c-$c-decoys.yaml"; _lsp9_decoys "$T/c-$c-decoys.yaml"
  done
  for c in alias-absent no-ceiling all-five nulls falses empty-last newline malformed map alias-map alias-empty-model anchors \
           no-ceiling-decoys all-five-decoys nulls-decoys falses-decoys empty-last-decoys newline-decoys map-decoys anchors-decoys; do
    new=$(_lsp9_run "$T/c-$c.yaml")
    old=$(_lsp9_run "$T/c-$c.yaml" "$T/shim:$PATH")
    [ "$new" = "$old" ] || { echo "case $c: new=$new old=$old"; return 1; }
  done
  # the cases whose answer is fixed whatever the path
  for c in alias-absent malformed alias-empty-model; do [ "$(_lsp9_run "$T/c-$c.yaml")" = null ] || { echo "case $c not null"; return 1; }; done
}

@test "LSP-9d (cycle-137 FR-3) an embedded newline in a field is not six lines: the verbatim six-read fallback runs" {
  _lsp9_fn
  printf 'aliases:\n  opus: "anthropic:m1"\nproviders:\n  anthropic:\n    models:\n      m1:\n        effective_input_ceiling: 300\n        ceiling_calibration:\n          calibrated_at: "2026-01-01T00:00:00Z"\n          transport: "claude-\\nheadless"\n' | _lsp9_case newline
  out=$(_lsp9_run "$T/c-newline.yaml")
  [ "$(_lsp9_yq_count)" = 7 ] || { echo "newline case yq calls: $(_lsp9_yq_count)"; return 1; }
  jq -e '.basis == "calibrated" and .calibration_transport == "claude-\nheadless"' <<<"$out" >/dev/null || { echo "$out"; return 1; }
}

@test "LSP-9c (cycle-137 FR-3) without yq on PATH the ceiling is null (no read attempted)" {
  _lsp9_fn
  _lsp5_catalog "$T/catalog.yaml" "" ""
  mkdir -p "$T/nobin"; ln -s "$(command -v jq)" "$T/nobin/jq"
  [ "$(_lsp9_run "$T/catalog.yaml" "$T/nobin")" = null ]
  [ "$(_lsp9_yq_count)" = 0 ]
}
