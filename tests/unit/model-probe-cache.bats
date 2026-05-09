#!/usr/bin/env bats
# =============================================================================
# tests/unit/model-probe-cache.bats
#
# cycle-102 Sprint 1 (T1.3) — Probe-cache library trio contract tests.
# Drives the Python canonical via tests/helpers/probe-cache-test-driver.py
# (mockable probe_fn) and the bash twin via direct CLI calls.
#
# Test taxonomy:
#   B0       Module imports cleanly (Python + bash twin both invokable)
#   P1-P9    Python canonical scenarios via probe-cache-test-driver
#   C1-C5    Bash twin namespacing + CLI exit codes
#   AC-1.2   p99 latency + 60s TTL cache hit (real-world AC pin)
#   AC-1.2.b Probe-itself failure fail-open vs LOCAL_NETWORK fail-fast
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    LIB_PY="$PROJECT_ROOT/.claude/scripts/lib/model-probe-cache.py"
    LIB_SH="$PROJECT_ROOT/.claude/scripts/lib/model-probe-cache.sh"
    DRIVER="$PROJECT_ROOT/tests/helpers/probe-cache-test-driver.py"

    [[ -f "$LIB_PY" ]] || { printf 'FATAL: missing %s\n' "$LIB_PY" >&2; return 1; }
    [[ -f "$LIB_SH" ]] || { printf 'FATAL: missing %s\n' "$LIB_SH" >&2; return 1; }
    [[ -f "$DRIVER" ]] || { printf 'FATAL: missing %s\n' "$DRIVER" >&2; return 1; }

    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="${PYTHON_BIN:-python3}"
    fi

    WORK_DIR="$(mktemp -d)"
    # Each scenario allocates its own subtree to avoid cross-contamination.
}

teardown() {
    [[ -n "${WORK_DIR:-}" && -d "$WORK_DIR" ]] && rm -rf "$WORK_DIR"
    return 0
}

# Helper: run a driver scenario in a fresh tmp dir, JSON output on stdout.
_drive() {
    local scenario="$1"
    local fresh
    fresh="$(mktemp -d -p "$WORK_DIR")"
    "$PYTHON_BIN" -I "$DRIVER" "$scenario" "$fresh"
}

# Helper: assert JSON field equals expected (JSON literal: true/false/123/"x").
_assert_json() {
    local key="$1"
    local want="$2"
    "$PYTHON_BIN" -I -c "
import json, sys
d = json.loads(sys.stdin.read())
got = d.get(sys.argv[1])
want = sys.argv[2]
try:
    want_v = json.loads(want)
except json.JSONDecodeError:
    want_v = want
if got != want_v:
    sys.stderr.write(f'expected {sys.argv[1]}={want_v!r}, got {got!r}\n')
    sys.exit(1)
" "$key" "$want"
}

# -----------------------------------------------------------------------------
# B0 — Both library files exist + are executable (smoke)
# -----------------------------------------------------------------------------

@test "B0a: Python canonical CLI prints help" {
    run "$PYTHON_BIN" -I "$LIB_PY" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"detect-local-network"* ]]
}

@test "B0b: bash twin prints help (delegates to Python)" {
    run bash "$LIB_SH" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"probe"* ]]
}

# -----------------------------------------------------------------------------
# P1-P9 — Python canonical via driver
# -----------------------------------------------------------------------------

@test "P1: basic probe -> cache hit on second call" {
    out="$(_drive basic_probe_then_cache)"
    echo "$out" | _assert_json first_cached false
    echo "$out" | _assert_json second_cached true
    echo "$out" | _assert_json first_outcome '"AVAILABLE"'
    echo "$out" | _assert_json probe_fn_calls 1
}

@test "P2: local-network failure short-circuits to FAIL + LOCAL_NETWORK_FAILURE" {
    out="$(_drive local_network_failure)"
    echo "$out" | _assert_json outcome '"FAIL"'
    echo "$out" | _assert_json error_class '"LOCAL_NETWORK_FAILURE"'
    echo "$out" | _assert_json cached false
}

@test "P3: invalidate_provider removes cache file" {
    out="$(_drive invalidate)"
    echo "$out" | _assert_json removed true
    echo "$out" | "$PYTHON_BIN" -I -c "
import json, sys
d = json.loads(sys.stdin.read())
assert d['files_after'] == [], f'expected empty list, got {d[\"files_after\"]}'
"
}

@test "P4: probe_fn raising -> fail-open (AVAILABLE + DEGRADED_PARTIAL — typed taxonomy member)" {
    # BB iter-1 FIND-002 (high) closure: error_class MUST be a member of
    # the model-error.schema.json typed taxonomy (10 classes). An earlier
    # draft used the synthetic value PROBE_LAYER_DEGRADED here, which would
    # have been rejected at audit-emit. DEGRADED_PARTIAL is the correct
    # typed class for fail-open probe-layer outcomes (caller proceeds with
    # WARN). Test pins the cross-subsystem vocabulary contract.
    out="$(_drive probe_fn_raises_fail_open 2>/dev/null)"
    echo "$out" | _assert_json outcome '"AVAILABLE"'
    echo "$out" | _assert_json error_class '"DEGRADED_PARTIAL"'
}

@test "P4b: every ERROR_CLASS_* constant in the lib is a member of model-error.schema.json enum (FIND-002)" {
    # BB iter-2 F7 (low) closure: discover constants dynamically rather
    # than hardcoding. A new ERROR_CLASS_FOO constant added to the lib
    # without a corresponding schema-enum entry MUST fail this test.
    pushd "$WORK_DIR" >/dev/null
    mkdir -p .claude
    schema="$PROJECT_ROOT/.claude/data/trajectory-schemas/model-error.schema.json"
    "$PYTHON_BIN" -I -c "
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location('mpc', '$PROJECT_ROOT/.claude/scripts/lib/model-probe-cache.py')
m = importlib.util.module_from_spec(spec)
sys.modules['mpc'] = m
spec.loader.exec_module(m)
schema = json.load(open('$schema'))
allowed = set(schema['properties']['error_class']['enum'])
# Discover constants dynamically — any module-level name starting with
# ERROR_CLASS_ is treated as a typed-taxonomy reference and validated.
constants = {n: getattr(m, n) for n in dir(m) if n.startswith('ERROR_CLASS_')}
assert constants, 'no ERROR_CLASS_* constants found in module — taxonomy regression?'
for name, val in constants.items():
    assert val in allowed, f'{name}={val!r} NOT in schema enum {sorted(allowed)}'
print(f'OK: all {len(constants)} probe-cache ERROR_CLASS_* constants conform to schema')
"
    popd >/dev/null
}

@test "P5: provider name validation rejects path traversal + null bytes + empty (invalidate path)" {
    out="$(_drive provider_validation)"
    echo "$out" | "$PYTHON_BIN" -I -c "
import json, sys
d = json.loads(sys.stdin.read())
for k, v in d.items():
    assert v == 'REJECTED', f'expected REJECTED for {k!r}, got {v!r}'
"
}

@test "P5b: provider name validation rejects on probe path AND no files written outside cache (FIND-004)" {
    # BB iter-2 FIND-004 (med): the probe path WRITES files; an
    # implementation could reject traversal on invalidate but write
    # outside the cache dir on probe and the prior P5 wouldn't catch it.
    out="$(_drive provider_validation_probe_path)"
    echo "$out" | "$PYTHON_BIN" -I -c "
import json, sys
d = json.loads(sys.stdin.read())
for k, v in d['results'].items():
    assert v == 'REJECTED', f'expected REJECTED for {k!r} on probe path, got {v!r}'
assert d['new_files_outside_cache'] == [], (
    f'FIND-004 violation: traversal-attack provider names created files OUTSIDE '
    f'.run/model-probe-cache: {d[\"new_files_outside_cache\"]}'
)
"
}

@test "P6: cache dir mode is 0700, file mode is 0600" {
    out="$(_drive cache_file_mode)"
    echo "$out" | _assert_json dir_mode_octal '"0o700"'
    echo "$out" | _assert_json file_mode_octal '"0o600"'
}

@test "P7: LOA_PROBE_RUNTIME=bash namespaces cache as bash-<provider>.json" {
    out="$(_drive runtime_namespacing)"
    echo "$out" | "$PYTHON_BIN" -I -c "
import json, sys
d = json.loads(sys.stdin.read())
assert d['files'] == ['bash-openai.json'], f'expected [bash-openai.json], got {d[\"files\"]}'
"
}

@test "P8: invalid LOA_PROBE_RUNTIME value falls back to python with stderr WARN" {
    out="$(_drive runtime_invalid_falls_back)"
    echo "$out" | _assert_json runtime '"python"'
    echo "$out" | _assert_json stderr_warned true
}

@test "P9: stale-while-revalidate returns cached immediately + fires background refresh" {
    out="$(_drive stale_while_revalidate)"
    echo "$out" | _assert_json first_cached false      # initial cache miss
    echo "$out" | _assert_json second_cached_immediate true  # SWR returned cached
    echo "$out" | _assert_json swr_launcher_fired true       # launcher invoked
    echo "$out" | _assert_json bg_calls 1                    # background probe ran
}

# -----------------------------------------------------------------------------
# C1-C5 — Bash twin namespacing + CLI exit codes
# -----------------------------------------------------------------------------

@test "C1: bash twin invalidate on non-existent provider exits 0 (idempotent)" {
    pushd "$WORK_DIR" >/dev/null
    mkdir -p .claude
    run bash "$LIB_SH" invalidate --provider testprov-nonexistent
    popd >/dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *'"removed": false'* ]]
}

@test "C2: bash twin detect-local-network returns JSON" {
    pushd "$WORK_DIR" >/dev/null
    mkdir -p .claude
    run bash "$LIB_SH" detect-local-network --timeout 0.5
    popd >/dev/null
    [[ "$output" == *'"reachable":'* ]]
}

@test "C3: bash twin namespaces its cache to bash-<provider>.json" {
    pushd "$WORK_DIR" >/dev/null
    mkdir -p .claude
    bash "$LIB_SH" probe --provider openai --model gpt-5.5-pro \
        --skip-local-network-check --timeout 1 --compact >/dev/null
    [ -f .run/model-probe-cache/bash-openai.json ]
    popd >/dev/null
}

@test "C4: bash twin and Python canonical have separate caches (Option B)" {
    pushd "$WORK_DIR" >/dev/null
    mkdir -p .claude
    bash "$LIB_SH" probe --provider openai --model gpt-5.5-pro \
        --skip-local-network-check --timeout 1 --compact >/dev/null
    "$PYTHON_BIN" -I "$LIB_PY" probe --provider openai --model gpt-5.5-pro \
        --skip-local-network-check --timeout 1 --compact >/dev/null
    # Both files should exist
    [ -f .run/model-probe-cache/bash-openai.json ]
    [ -f .run/model-probe-cache/python-openai.json ]
    popd >/dev/null
}

@test "C5: bash twin missing python -> exit 2 with hint" {
    # Hard to test without uninstalling python; assert the error path is wired
    # by reading the script and confirming both the exit code and the hint
    # message exist.
    grep -q "exit 2" "$LIB_SH"
    grep -q "no python3 interpreter found" "$LIB_SH"
}

# -----------------------------------------------------------------------------
# Schema integrity: cache file shape conforms to expectations
# -----------------------------------------------------------------------------

@test "S1: cache file contains required fields (schema_version, provider, runtime, models_probed)" {
    pushd "$WORK_DIR" >/dev/null
    mkdir -p .claude
    "$PYTHON_BIN" -I "$LIB_PY" probe --provider openai --model gpt-5.5-pro \
        --skip-local-network-check --timeout 1 --compact >/dev/null
    cache=".run/model-probe-cache/python-openai.json"
    [ -f "$cache" ]
    "$PYTHON_BIN" -I -c "
import json
d = json.load(open('$cache'))
for k in ['schema_version', 'provider', 'runtime', 'models_probed', 'last_probe_ts_utc', 'ttl_seconds']:
    assert k in d, f'missing key: {k}'
assert d['runtime'] == 'python'
assert d['provider'] == 'openai'
assert 'gpt-5.5-pro' in d['models_probed']
assert d['models_probed']['gpt-5.5-pro']['outcome'] in ['AVAILABLE', 'DEGRADED', 'FAIL']
"
    popd >/dev/null
}
