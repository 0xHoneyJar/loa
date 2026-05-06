#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# =============================================================================
# AC-S2.12 — Overlay resolution latency (cycle-099 Sprint 2B / SDD §7.5.1)
#
# Per NFR-Perf-1: warm cache hit p95 ≤ 50ms; cold regen p95 ≤ 500ms.
# Measurement methodology: tests/perf/measure.py uses time.perf_counter_ns().
# CI runs 1000 iterations; local runs use a smaller iteration count to keep
# the test fast (override via LOA_LATENCY_ITERATIONS).
#
# This file ships BOTH warm and cold cases. Cold goes in the same file rather
# than a separate latency-cold.bats since the fixture/setup are identical.
# =============================================================================

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  HOOK="$REPO_ROOT/.claude/scripts/lib/model-overlay-hook.py"
  MEASURE="$REPO_ROOT/tests/perf/measure.py"
  PYTHON="$(command -v python3)"
  [[ -n "$PYTHON" ]] || skip "python3 not on PATH"
  WORK="$(mktemp -d)"
  RUN_DIR="$WORK/run"
  mkdir -p "$RUN_DIR"
  SCHEMA="$REPO_ROOT/.claude/data/trajectory-schemas/model-aliases-extra.schema.json"
  SOT="$REPO_ROOT/.claude/defaults/model-config.yaml"
  # Empty operator config keeps the test focused on framework-only resolution
  OP="$WORK/.loa.config.yaml"
  printf '{}\n' > "$OP"
  ITERATIONS="${LOA_LATENCY_ITERATIONS:-100}"
  WARMUP="${LOA_LATENCY_WARMUP:-10}"
}

teardown() {
  rm -rf "$WORK"
}

# -----------------------------------------------------------------------------
# Warm cache: p95 ≤ 50ms (NFR-Perf-1)
# -----------------------------------------------------------------------------

@test "warm cache hit p95 under 50ms (in-process)" {
  # In-process measurement matches the cheval startup pattern. NFR-Perf-1
  # budget is 50ms warm. We allow 50ms here for parity with CI.
  run --separate-stderr \
    "$PYTHON" "$MEASURE" \
      --hook "$HOOK" \
      --sot "$SOT" \
      --operator "$OP" \
      --merged "$RUN_DIR/merged.sh" \
      --lockfile "$RUN_DIR/merged.sh.lock" \
      --state "$RUN_DIR/state.json" \
      --schema "$SCHEMA" \
      --iterations "$ITERATIONS" \
      --warmup "$WARMUP" \
      --invoke-mode in-process \
      --mode warm
  [ "$status" -eq 0 ]
  p95=$(printf '%s' "$output" | "$PYTHON" -c 'import json,sys; print(json.load(sys.stdin)["p95_ms"])')
  echo "warm p95 (in-process): ${p95} ms" >&3
  result=$("$PYTHON" -c "print(1 if float('$p95') < 50 else 0)")
  [ "$result" -eq 1 ]
}

# -----------------------------------------------------------------------------
# Cold regen: p95 ≤ 500ms (NFR-Perf-1 cold-cache budget)
# -----------------------------------------------------------------------------

@test "cold regen p95 under 500ms (in-process)" {
  run --separate-stderr \
    "$PYTHON" "$MEASURE" \
      --hook "$HOOK" \
      --sot "$SOT" \
      --operator "$OP" \
      --merged "$RUN_DIR/merged.sh" \
      --lockfile "$RUN_DIR/merged.sh.lock" \
      --state "$RUN_DIR/state.json" \
      --schema "$SCHEMA" \
      --iterations "$ITERATIONS" \
      --warmup "$WARMUP" \
      --invoke-mode in-process \
      --mode cold
  [ "$status" -eq 0 ]
  p95=$(printf '%s' "$output" | "$PYTHON" -c 'import json,sys; print(json.load(sys.stdin)["p95_ms"])')
  echo "cold p95 (in-process): ${p95} ms" >&3
  result=$("$PYTHON" -c "print(1 if float('$p95') < 500 else 0)")
  [ "$result" -eq 1 ]
}

# -----------------------------------------------------------------------------
# JSON shape contract (regression pin for measure.py output)
# -----------------------------------------------------------------------------

@test "measure.py emits canonical JSON with all required percentiles" {
  run --separate-stderr \
    "$PYTHON" "$MEASURE" \
      --hook "$HOOK" \
      --sot "$SOT" \
      --operator "$OP" \
      --merged "$RUN_DIR/merged.sh" \
      --lockfile "$RUN_DIR/merged.sh.lock" \
      --state "$RUN_DIR/state.json" \
      --schema "$SCHEMA" \
      --iterations 5 \
      --warmup 1 \
      --mode warm
  [ "$status" -eq 0 ]
  # Required keys present
  printf '%s' "$output" | "$PYTHON" -c '
import json, sys
d = json.load(sys.stdin)
for k in ["p50_ms", "p95_ms", "p99_ms", "stddev_ms", "iterations", "mode", "platform"]:
    assert k in d, f"missing key: {k}"
assert d["mode"] == "warm"
assert d["iterations"] == 5
print("OK")
'
}
