#!/usr/bin/env bats
# =============================================================================
# tests/perf/model-resolver-latency.bats — cycle-099 Sprint 2D latency
# micro-bench for the FR-3.9 6-stage resolver.
#
# Per SDD §1.8 and §7.5.1:
#   - <100µs warm hot-path (resolver only; no I/O, no logging)
#   - <2ms with FR-5.7 tracing enabled
#
# Sprint 2D landed the canonical Python resolver (`.claude/scripts/lib/
# model-resolver.py`). This bench measures `resolve(config, skill, role)`
# directly — no YAML parse, no fixture I/O. The hot-path is N=1000 iterations
# of `resolve()` against a pre-loaded config.
#
# Sprint 2D scope: Python canonical only. Bash twin is test code (test
# runner) and not on the production hot path; bash latency budget is
# documented in NFR-Op-5 (build-time toolchain only). The Sprint 2B
# `overlay-resolution-latency.bats` covers the full overlay-write +
# resolve cycle (cold-cache p95 ≤500ms; warm p95 ≤50ms).
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    RESOLVER_PY="$PROJECT_ROOT/.claude/scripts/lib/model-resolver.py"

    [[ -f "$RESOLVER_PY" ]] || skip "model-resolver.py not present"
    command -v python3 >/dev/null 2>&1 || skip "python3 not present"

    WORK_DIR="$(mktemp -d)"
}

teardown() {
    if [[ -n "${WORK_DIR:-}" ]] && [[ -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
    return 0
}

# L1: warm-cache hot-path latency (resolver only, no I/O)
# Budget per SDD §1.8: per-resolution overhead without tracing <100µs.
# Allowing 5× headroom for CI noise: assert p95 < 500µs.
@test "L1 warm hot-path p95 < 500µs (1000 iterations, no I/O)" {
    cat > "$WORK_DIR/bench.py" <<'PY'
import importlib.util, os, sys, time

spec = importlib.util.spec_from_file_location("mr", os.environ["LOA_RESOLVER_PY"])
mr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mr)

# Representative merged config — 4 skills × 1 role + tier_groups.
config = {
    "schema_version": 2,
    "framework_defaults": {
        "providers": {
            "anthropic": {"models": {"claude-opus-4-7": {"capabilities": ["chat"]}}},
        },
        "aliases": {
            "opus": {"provider": "anthropic", "model_id": "claude-opus-4-7"},
            "max":  {"provider": "anthropic", "model_id": "claude-opus-4-7"},
        },
        "tier_groups": {"mappings": {"max": {"anthropic": "opus"}}},
        "agents": {
            "flatline_protocol": {"default_tier": "max"},
        },
    },
    "operator_config": {
        "skill_models": {
            "flatline_protocol": {"primary": "max"},
        },
    },
}

# Warm-up: 50 untimed iterations
for _ in range(50):
    mr.resolve(config, "flatline_protocol", "primary")

# Measure: 1000 timed iterations
samples_ns = []
for _ in range(1000):
    t0 = time.perf_counter_ns()
    mr.resolve(config, "flatline_protocol", "primary")
    samples_ns.append(time.perf_counter_ns() - t0)

samples_ns.sort()
def percentile(s, p):
    idx = int(len(s) * p / 100)
    return s[min(idx, len(s) - 1)]

p50 = percentile(samples_ns, 50)
p95 = percentile(samples_ns, 95)
p99 = percentile(samples_ns, 99)
print(f"p50={p50/1000:.1f}us p95={p95/1000:.1f}us p99={p99/1000:.1f}us iter=1000")

# Budget: warm hot-path p95 < 500us (5× headroom over <100us SDD budget)
budget_us = 500.0
p95_us = p95 / 1000.0
if p95_us > budget_us:
    print(f"::error::p95={p95_us:.1f}us exceeds budget {budget_us}us (SDD §1.8 + 5× CI-noise headroom)")
    sys.exit(1)
PY
    LOA_RESOLVER_PY="$RESOLVER_PY" python3 "$WORK_DIR/bench.py"
}

# L2: Resolver behavior is deterministic (same input → same output across iterations)
@test "L2 resolver is deterministic across 100 iterations on same config" {
    cat > "$WORK_DIR/det.py" <<'PY'
import importlib.util, os, sys

spec = importlib.util.spec_from_file_location("mr", os.environ["LOA_RESOLVER_PY"])
mr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mr)

config = {
    "schema_version": 2,
    "framework_defaults": {
        "aliases": {"opus": {"provider": "anthropic", "model_id": "claude-opus-4-7"}},
        "tier_groups": {"mappings": {"max": {"anthropic": "opus"}}},
    },
    "operator_config": {
        "skill_models": {"flatline_protocol": {"primary": "max"}},
    },
}

first = mr.dump_canonical_json(mr.resolve(config, "flatline_protocol", "primary"))
for i in range(100):
    output = mr.dump_canonical_json(mr.resolve(config, "flatline_protocol", "primary"))
    if output != first:
        print(f"::error::iteration {i} diverged from first call")
        print(f"first:  {first}")
        print(f"i={i}: {output}")
        sys.exit(1)
print(f"OK — deterministic across 100 iterations")
PY
    LOA_RESOLVER_PY="$RESOLVER_PY" python3 "$WORK_DIR/det.py"
}
