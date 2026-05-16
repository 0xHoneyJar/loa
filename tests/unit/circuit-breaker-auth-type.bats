#!/usr/bin/env bats

# Cycle-110 Sprint 1 — (provider, auth_type)-keyed circuit breaker
#
# T1.5  FR-0.4  KF-008-shape masking pattern reproduction
# T1.6  FR-0.5  Concurrent-migration race (8 parallel readers)
# T1.7         Corrupt-legacy fail-open + [L4-MIGRATION-CORRUPT] journal marker
#
# These tests drive the Python circuit-breaker library through a minimal
# Python invocation per test. Each test creates an isolated tmp dir so
# fixtures cannot leak across cases.

setup() {
  BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
  export PROJECT_ROOT
  export PYTHONPATH="$PROJECT_ROOT/.claude/adapters${PYTHONPATH:+:$PYTHONPATH}"
  export TEST_TMPDIR="${BATS_TMPDIR:-/tmp}/cb-auth-type-$$-$BATS_TEST_NUMBER"
  mkdir -p "$TEST_TMPDIR"
}

teardown() {
  if [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]]; then
    rm -rf "$TEST_TMPDIR"
  fi
}

py() {
  python3 -c "$1"
}

# Use `run py "..."` to capture status; the bare `py` helper above is
# also kept so tests that simply want to assert the script exits 0 can
# call `py "..."` directly and rely on bats's `set -e` propagation.

# ============================================================================
# T1.5 — KF-008-shape masking: per-bucket states do not mask each other
# ============================================================================

@test "T1.5 / FR-0.4: tripping http_api does NOT mask headless CLOSED state" {
  run python3 -c "
import sys
sys.path.insert(0, '$PROJECT_ROOT/.claude/adapters')
from loa_cheval.routing.circuit_breaker import (
    record_failure, check_state,
    AUTH_TYPE_HTTP_API, AUTH_TYPE_HEADLESS,
    OPEN, CLOSED,
)
config = {'routing': {'circuit_breaker': {'failure_threshold': 3, 'count_window_seconds': 60}}}
for _ in range(3):
    record_failure('google', AUTH_TYPE_HTTP_API, config, '$TEST_TMPDIR')
assert check_state('google', AUTH_TYPE_HTTP_API, config, '$TEST_TMPDIR') == OPEN, 'http_api should be OPEN'
assert check_state('google', AUTH_TYPE_HEADLESS, config, '$TEST_TMPDIR') == CLOSED, 'headless must stay CLOSED'
print('OK')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "T1.5 / FR-0.4: tripping headless does NOT mask http_api CLOSED state" {
  run python3 -c "
import sys
sys.path.insert(0, '$PROJECT_ROOT/.claude/adapters')
from loa_cheval.routing.circuit_breaker import (
    record_failure, check_state,
    AUTH_TYPE_HTTP_API, AUTH_TYPE_HEADLESS,
    OPEN, CLOSED,
)
config = {'routing': {'circuit_breaker': {'failure_threshold': 3, 'count_window_seconds': 60}}}
for _ in range(3):
    record_failure('google', AUTH_TYPE_HEADLESS, config, '$TEST_TMPDIR')
assert check_state('google', AUTH_TYPE_HEADLESS, config, '$TEST_TMPDIR') == OPEN, 'headless should be OPEN'
assert check_state('google', AUTH_TYPE_HTTP_API, config, '$TEST_TMPDIR') == CLOSED, 'http_api must stay CLOSED'
print('OK')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "T1.5 / FR-0.4: state files are written to distinct paths per bucket" {
  py "
import sys
sys.path.insert(0, '$PROJECT_ROOT/.claude/adapters')
from loa_cheval.routing.circuit_breaker import (
    record_failure, AUTH_TYPE_HTTP_API, AUTH_TYPE_HEADLESS,
)
config = {'routing': {'circuit_breaker': {'failure_threshold': 5, 'count_window_seconds': 60}}}
record_failure('google', AUTH_TYPE_HTTP_API, config, '$TEST_TMPDIR')
record_failure('google', AUTH_TYPE_HEADLESS, config, '$TEST_TMPDIR')
print('OK')
"
  [ -f "$TEST_TMPDIR/circuit-breaker-google-http_api.json" ]
  [ -f "$TEST_TMPDIR/circuit-breaker-google-headless.json" ]
}

# ============================================================================
# T1.6 — Concurrent-migration race (8 parallel readers)
# ============================================================================

@test "T1.6 / FR-0.5: 8 parallel migrators converge to one consistent state" {
  # Seed a legacy file.
  cat > "$TEST_TMPDIR/circuit-breaker-anthropic.json" <<EOF
{
  "provider": "anthropic",
  "state": "OPEN",
  "failure_count": 4,
  "last_failure_ts": 1715000000.0,
  "opened_at": 1715000000.0,
  "half_open_probes": 0
}
EOF

  # Spawn 8 readers in parallel; each invokes the migration helper.
  pids=()
  for i in $(seq 1 8); do
    python3 -c "
import sys
sys.path.insert(0, '$PROJECT_ROOT/.claude/adapters')
from loa_cheval.routing.circuit_breaker import _migrate_legacy_state_if_present
_migrate_legacy_state_if_present('anthropic', '$TEST_TMPDIR')
" &
    pids+=($!)
  done
  for pid in "${pids[@]}"; do
    wait "$pid"
  done

  # Exactly one http_api bucket file with preserved state.
  [ -f "$TEST_TMPDIR/circuit-breaker-anthropic-http_api.json" ]
  # Legacy file was replaced by a transitional symlink.
  [ -L "$TEST_TMPDIR/circuit-breaker-anthropic.json" ]
  target="$(readlink "$TEST_TMPDIR/circuit-breaker-anthropic.json")"
  [ "$target" = "circuit-breaker-anthropic-http_api.json" ]

  # State preserved.
  state=$(python3 -c "import json; print(json.load(open('$TEST_TMPDIR/circuit-breaker-anthropic-http_api.json'))['state'])")
  [ "$state" = "OPEN" ]
  failures=$(python3 -c "import json; print(json.load(open('$TEST_TMPDIR/circuit-breaker-anthropic-http_api.json'))['failure_count'])")
  [ "$failures" = "4" ]

  # Headless bucket seeded CLOSED.
  [ -f "$TEST_TMPDIR/circuit-breaker-anthropic-headless.json" ]
  head_state=$(python3 -c "import json; print(json.load(open('$TEST_TMPDIR/circuit-breaker-anthropic-headless.json'))['state'])")
  [ "$head_state" = "CLOSED" ]
}

@test "T1.6 / FR-0.5: migration is idempotent on repeat invocation" {
  cat > "$TEST_TMPDIR/circuit-breaker-google.json" <<EOF
{"provider":"google","state":"CLOSED","failure_count":0,"last_failure_ts":null,"opened_at":null,"half_open_probes":0}
EOF

  for i in 1 2 3; do
    python3 -c "
import sys
sys.path.insert(0, '$PROJECT_ROOT/.claude/adapters')
from loa_cheval.routing.circuit_breaker import _migrate_legacy_state_if_present
_migrate_legacy_state_if_present('google', '$TEST_TMPDIR')
"
  done

  # File still present, symlink intact.
  [ -L "$TEST_TMPDIR/circuit-breaker-google.json" ]
  [ -f "$TEST_TMPDIR/circuit-breaker-google-http_api.json" ]
}

# ============================================================================
# T1.7 — Corrupt-legacy cold-start fail-open + [L4-MIGRATION-CORRUPT] marker
# ============================================================================

@test "T1.7: corrupt legacy → CLOSED bucket + journal marker" {
  printf "this is not json at all{{{" > "$TEST_TMPDIR/circuit-breaker-openai.json"

  python3 -c "
import sys
sys.path.insert(0, '$PROJECT_ROOT/.claude/adapters')
from loa_cheval.routing.circuit_breaker import _migrate_legacy_state_if_present
_migrate_legacy_state_if_present('openai', '$TEST_TMPDIR')
"

  # http_api bucket seeded CLOSED on fail-open.
  [ -f "$TEST_TMPDIR/circuit-breaker-openai-http_api.json" ]
  state=$(python3 -c "import json; print(json.load(open('$TEST_TMPDIR/circuit-breaker-openai-http_api.json'))['state'])")
  [ "$state" = "CLOSED" ]

  # Journal marker present.
  [ -f "$TEST_TMPDIR/substrate-health-journal.jsonl" ]
  marker=$(python3 -c "import json; print(json.loads(open('$TEST_TMPDIR/substrate-health-journal.jsonl').read().splitlines()[0])['marker'])")
  [ "$marker" = "L4-MIGRATION-CORRUPT" ]
}

@test "T1.7: empty legacy file is treated as corrupt → fail-open + marker" {
  : > "$TEST_TMPDIR/circuit-breaker-azure.json"

  python3 -c "
import sys
sys.path.insert(0, '$PROJECT_ROOT/.claude/adapters')
from loa_cheval.routing.circuit_breaker import _migrate_legacy_state_if_present
_migrate_legacy_state_if_present('azure', '$TEST_TMPDIR')
"

  state=$(python3 -c "import json; print(json.load(open('$TEST_TMPDIR/circuit-breaker-azure-http_api.json'))['state'])")
  [ "$state" = "CLOSED" ]
  [ -f "$TEST_TMPDIR/substrate-health-journal.jsonl" ]
}

# ============================================================================
# Smoke: substrate-health surfaces (provider, auth_type) state
# ============================================================================

@test "T1.9 smoke: substrate-health JSON includes circuit_breaker section" {
  # Seed one bucket directly.
  cat > "$TEST_TMPDIR/circuit-breaker-google-headless.json" <<EOF
{"provider":"google","auth_type":"headless","state":"OPEN","failure_count":5,"opened_at":1715000000.0}
EOF
  # MODELINV log must exist for the aggregator to produce a report.
  : > "$TEST_TMPDIR/model-invoke.jsonl"

  out=$(python3 -c "
import sys, json
sys.path.insert(0, '$PROJECT_ROOT/.claude/adapters')
from pathlib import Path
from loa_cheval.health import aggregate_substrate_health
report = aggregate_substrate_health(
    log_path=Path('$TEST_TMPDIR/model-invoke.jsonl'),
    window='24h',
    run_dir='$TEST_TMPDIR',
)
print(json.dumps(report['circuit_breaker']))
")
  [[ "$out" == *"google"* ]]
  [[ "$out" == *"headless"* ]]
  [[ "$out" == *"OPEN"* ]]
}
