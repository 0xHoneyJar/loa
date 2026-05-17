#!/usr/bin/env bats
# cycle-112 Sprint 1 (#166) T1.6 — model-economy NFR-Perf-1 gate.
#
# AC (PRD §7 NFR-Perf-1): roll-up over a 100K-envelope synthetic JSONL
# completes in < 5s wall clock.

setup() {
    export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export TMP="$(mktemp -d -t loa-economy-perf-XXXXXX)"
    export CLI="$PROJECT_ROOT/tools/model-economy-roll-up.sh"
    export MODEL_CONFIG="$PROJECT_ROOT/.claude/defaults/model-config.yaml"
}

teardown() {
    rm -rf "$TMP"
}

# Generate a synthetic 100K-envelope log. ~150 bytes per line → ~15 MB.
_generate_100k_log() {
    local log="$1"
    python3 - "$log" <<'PY'
import json, sys
from datetime import datetime, timedelta, timezone

log = sys.argv[1]
base = datetime(2026, 5, 16, 0, 0, 0, tzinfo=timezone.utc)
models = [
    "anthropic:claude-opus-4-7",
    "openai:gpt-5.5-pro",
    "google:gemini-3.1-pro-preview",
    "openai:gpt-5.3-codex",
]
pricing_per_mtok = [30000000, 5000000, 1750000, 1250000]
with open(log, "w") as fh:
    for i in range(100_000):
        m = i % len(models)
        ts = (base + timedelta(seconds=i)).isoformat().replace("+00:00", "Z")
        payload = {
            "models_requested": [models[m]],
            "models_succeeded": [models[m]],
            "final_model_id": models[m],
            "invocation_latency_ms": 1000 + (i % 5000),
            "pricing_snapshot": {"input_per_mtok": pricing_per_mtok[m]},
            "capability_evaluation": {"estimated_input_tokens": 100 + (i % 1000)},
            "verdict_quality": {"status": "APPROVED" if i % 3 else "DEGRADED",
                                "chain_health": "ok" if i % 3 else "degraded"},
        }
        envelope = {
            "primitive_id": "MODELINV",
            "event_type": "model.invoke.complete",
            "ts_utc": ts,
            "payload": payload,
        }
        fh.write(json.dumps(envelope) + "\n")
PY
}

@test "T1.6.perf: 100K-envelope roll-up completes in <5s (NFR-Perf-1)" {
    log="$TMP/synthetic-100k.jsonl"
    _generate_100k_log "$log"
    [ -s "$log" ]

    # Measure wall-clock time. Use 365d window so all entries fall in scope.
    start_ns="$(date +%s%N)"
    run "$CLI" --log-path "$log" --model-config "$MODEL_CONFIG" \
        --window 365d --json
    end_ns="$(date +%s%N)"
    [ "$status" -eq 0 ]

    # Convert nanos → milliseconds. POSIX bash arithmetic on big ints is fine.
    elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))
    echo "elapsed_ms=$elapsed_ms"

    # NFR-Perf-1 budget: 5000ms.
    [ "$elapsed_ms" -lt 5000 ]
}

@test "T1.6.perf: 100K-envelope roll-up emits correct envelope count" {
    log="$TMP/synthetic-100k.jsonl"
    _generate_100k_log "$log"

    run "$CLI" --log-path "$log" --model-config "$MODEL_CONFIG" \
        --window 365d --json
    [ "$status" -eq 0 ]

    count=$(echo "$output" | python3 -c "import json, sys; print(json.loads(sys.stdin.read())['coverage']['total_envelopes'])")
    [ "$count" -eq 100000 ]
}
