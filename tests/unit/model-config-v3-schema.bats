#!/usr/bin/env bats
# =============================================================================
# tests/unit/model-config-v3-schema.bats
#
# cycle-109 Sprint 1 T1.1 — model-config-v3 schema validation.
#
# Per SDD §3.1 the v3 schema extends v2 additively with capability-aware
# fields per model entry: effective_input_ceiling, reasoning_class,
# recommended_for, failure_modes_observed, ceiling_calibration (object),
# streaming_recovery (object).
#
# Per SDD §3.1.3 "validates additive-only — v3 must accept all valid v2
# documents". Per AC-T1.1: schema lands + schema-validation bats covers
# (a) v2-compatible passthrough, (b) v3-with-new-fields valid, (c) per-field
# rejection of malformed entries.
#
# Test-first protocol: this file lands BEFORE the schema. Initial state:
# every test should `skip` (not exist) cleanly so the bats run is green.
# The implementation commit removes the skips by adding the schema file.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    SCHEMA_V3="$PROJECT_ROOT/.claude/data/schemas/model-config-v3.schema.json"
    SCHEMA_V2="$PROJECT_ROOT/.claude/data/schemas/model-config-v2.schema.json"

    [[ -f "$SCHEMA_V3" ]] || skip "v3 schema not yet implemented (T1.1 pending)"
    [[ -f "$SCHEMA_V2" ]] || skip "v2 schema (parent) missing"

    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="${PYTHON_BIN:-python3}"
    fi

    "$PYTHON_BIN" -c "import jsonschema" 2>/dev/null \
        || skip "jsonschema not available in $PYTHON_BIN"

    WORK_DIR="$(mktemp -d)"
}

teardown() {
    if [[ -n "${WORK_DIR:-}" ]] && [[ -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
    return 0
}

# Validate a JSON document against the v3 schema.
# Args: $1=JSON-doc-as-string. Returns: 0 if valid, non-zero on failure.
validate_v3() {
    local doc="$1"
    "$PYTHON_BIN" - <<PYEOF
import json, sys, jsonschema
with open("$SCHEMA_V3") as f:
    schema = json.load(f)
doc = json.loads(r'''$doc''')
try:
    jsonschema.validate(doc, schema)
    sys.exit(0)
except jsonschema.ValidationError as e:
    sys.stderr.write(f"INVALID: {e.message}\n")
    sys.exit(1)
PYEOF
}

# -----------------------------------------------------------------------------
# G-1: schema itself parses + declares itself v3
# -----------------------------------------------------------------------------

@test "G-1.1: v3 schema is valid JSON" {
    run "$PYTHON_BIN" -c "import json; json.load(open('$SCHEMA_V3'))"
    [ "$status" -eq 0 ]
}

@test "G-1.2: v3 schema validates as a JSON Schema (Draft 2020-12)" {
    run "$PYTHON_BIN" - <<'PYEOF'
import json, jsonschema, sys
schema = json.load(open("$SCHEMA_V3".replace("$SCHEMA_V3", "$SCHEMA_V3")))
# Use module-level checker for whichever Draft 2020-12 validator is exposed.
validator_cls = jsonschema.validators.validator_for(schema)
validator_cls.check_schema(schema)
sys.exit(0)
PYEOF
    # Re-run with proper variable interpolation
    run "$PYTHON_BIN" -c "
import json, jsonschema, sys
schema = json.load(open('$SCHEMA_V3'))
validator_cls = jsonschema.validators.validator_for(schema)
validator_cls.check_schema(schema)
"
    [ "$status" -eq 0 ]
}

@test "G-1.3: v3 schema declares schema_version const 3" {
    run "$PYTHON_BIN" -c "
import json, sys
s = json.load(open('$SCHEMA_V3'))
sv = s['properties']['schema_version']
assert sv.get('const') == 3, f'expected const:3 got {sv}'
"
    [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# V2-compat: any minimum-valid v2 doc with schema_version bumped to 3 validates
# -----------------------------------------------------------------------------

@test "V2-compat: minimum v2 doc (schema_version=3, empty providers) validates" {
    doc='{"schema_version": 3, "providers": {}}'
    run validate_v3 "$doc"
    [ "$status" -eq 0 ]
}

@test "V2-compat: v2 model entry without new fields validates (additive-only)" {
    doc='{
        "schema_version": 3,
        "providers": {
            "anthropic": {
                "type": "anthropic",
                "endpoint": "https://api.anthropic.com",
                "models": {
                    "claude-opus-4-7": {
                        "context_window": 200000,
                        "max_output_tokens": 8192
                    }
                }
            }
        }
    }'
    run validate_v3 "$doc"
    [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# V3 additions: each new field accepted at the model-entry level
# -----------------------------------------------------------------------------

@test "V3-add: effective_input_ceiling integer accepted" {
    doc='{
        "schema_version": 3,
        "providers": {
            "anthropic": {
                "models": {
                    "claude-opus-4-7": {
                        "context_window": 200000,
                        "effective_input_ceiling": 40000
                    }
                }
            }
        }
    }'
    run validate_v3 "$doc"
    [ "$status" -eq 0 ]
}

@test "V3-add: reasoning_class boolean accepted" {
    doc='{
        "schema_version": 3,
        "providers": {"anthropic": {"models": {
            "claude-opus-4-7": {"context_window": 200000, "reasoning_class": true}
        }}}
    }'
    run validate_v3 "$doc"
    [ "$status" -eq 0 ]
}

@test "V3-add: recommended_for role array accepted (allow-all default)" {
    doc='{
        "schema_version": 3,
        "providers": {"anthropic": {"models": {
            "claude-opus-4-7": {
                "context_window": 200000,
                "recommended_for": ["review", "audit", "implementation", "dissent", "arbiter"]
            }
        }}}
    }'
    run validate_v3 "$doc"
    [ "$status" -eq 0 ]
}

@test "V3-add: recommended_for empty list accepted (operator kill-switch per SDD §3.1.4)" {
    doc='{
        "schema_version": 3,
        "providers": {"anthropic": {"models": {
            "claude-opus-4-7": {"context_window": 200000, "recommended_for": []}
        }}}
    }'
    run validate_v3 "$doc"
    [ "$status" -eq 0 ]
}

@test "V3-add: failure_modes_observed KF-ref array accepted" {
    doc='{
        "schema_version": 3,
        "providers": {"anthropic": {"models": {
            "claude-opus-4-7": {
                "context_window": 200000,
                "failure_modes_observed": ["KF-002", "KF-003"]
            }
        }}}
    }'
    run validate_v3 "$doc"
    [ "$status" -eq 0 ]
}

@test "V3-add: ceiling_calibration object with all fields accepted" {
    doc='{
        "schema_version": 3,
        "providers": {"anthropic": {"models": {
            "claude-opus-4-7": {
                "context_window": 200000,
                "ceiling_calibration": {
                    "source": "empirical_probe",
                    "calibrated_at": "2026-05-13T00:00:00Z",
                    "sample_size": 25,
                    "stale_after_days": 30,
                    "reprobe_trigger": "first KF entry referencing model OR 30d elapsed OR operator-forced"
                }
            }
        }}}
    }'
    run validate_v3 "$doc"
    [ "$status" -eq 0 ]
}

@test "V3-add: streaming_recovery object accepted" {
    doc='{
        "schema_version": 3,
        "providers": {"anthropic": {"models": {
            "claude-opus-4-7": {
                "context_window": 200000,
                "streaming_recovery": {
                    "first_token_deadline_seconds": 60,
                    "empty_detection_window_tokens": 200,
                    "cot_token_budget": 500
                }
            }
        }}}
    }'
    run validate_v3 "$doc"
    [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# Rejection: malformed v3 fields
# -----------------------------------------------------------------------------

@test "Reject: effective_input_ceiling must be integer (string rejected)" {
    doc='{
        "schema_version": 3,
        "providers": {"anthropic": {"models": {
            "claude-opus-4-7": {"context_window": 200000, "effective_input_ceiling": "40000"}
        }}}
    }'
    run validate_v3 "$doc"
    [ "$status" -ne 0 ]
}

@test "Reject: effective_input_ceiling minimum 1 (zero rejected)" {
    doc='{
        "schema_version": 3,
        "providers": {"anthropic": {"models": {
            "claude-opus-4-7": {"context_window": 200000, "effective_input_ceiling": 0}
        }}}
    }'
    run validate_v3 "$doc"
    [ "$status" -ne 0 ]
}

@test "Reject: reasoning_class string instead of boolean" {
    doc='{
        "schema_version": 3,
        "providers": {"anthropic": {"models": {
            "claude-opus-4-7": {"context_window": 200000, "reasoning_class": "true"}
        }}}
    }'
    run validate_v3 "$doc"
    [ "$status" -ne 0 ]
}

@test "Reject: recommended_for role outside enum" {
    doc='{
        "schema_version": 3,
        "providers": {"anthropic": {"models": {
            "claude-opus-4-7": {"context_window": 200000, "recommended_for": ["bogus_role"]}
        }}}
    }'
    run validate_v3 "$doc"
    [ "$status" -ne 0 ]
}

@test "Reject: ceiling_calibration.source outside enum" {
    doc='{
        "schema_version": 3,
        "providers": {"anthropic": {"models": {
            "claude-opus-4-7": {
                "context_window": 200000,
                "ceiling_calibration": {"source": "made_up_source"}
            }
        }}}
    }'
    run validate_v3 "$doc"
    [ "$status" -ne 0 ]
}

@test "Reject: ceiling_calibration extra property rejected (additionalProperties:false)" {
    doc='{
        "schema_version": 3,
        "providers": {"anthropic": {"models": {
            "claude-opus-4-7": {
                "context_window": 200000,
                "ceiling_calibration": {
                    "source": "conservative_default",
                    "rogue_field": "should reject"
                }
            }
        }}}
    }'
    run validate_v3 "$doc"
    [ "$status" -ne 0 ]
}

@test "Reject: failure_modes_observed entry that doesn't match KF-NNN pattern" {
    doc='{
        "schema_version": 3,
        "providers": {"anthropic": {"models": {
            "claude-opus-4-7": {
                "context_window": 200000,
                "failure_modes_observed": ["not-a-kf-ref"]
            }
        }}}
    }'
    run validate_v3 "$doc"
    [ "$status" -ne 0 ]
}

@test "Reject: model entry with unknown top-level v3 property" {
    doc='{
        "schema_version": 3,
        "providers": {"anthropic": {"models": {
            "claude-opus-4-7": {
                "context_window": 200000,
                "rogue_capability_field": "should reject"
            }
        }}}
    }'
    run validate_v3 "$doc"
    [ "$status" -ne 0 ]
}

@test "Reject: schema_version must be 3 (not 2 or 4)" {
    for bad_ver in 2 4; do
        doc="{\"schema_version\": $bad_ver, \"providers\": {}}"
        run validate_v3 "$doc"
        [ "$status" -ne 0 ] || {
            echo "expected rejection for schema_version=$bad_ver but got success" >&2
            return 1
        }
    done
}

# -----------------------------------------------------------------------------
# Streaming-recovery nested validation
# -----------------------------------------------------------------------------

@test "Reject: streaming_recovery.first_token_deadline_seconds must be positive" {
    doc='{
        "schema_version": 3,
        "providers": {"anthropic": {"models": {
            "claude-opus-4-7": {
                "context_window": 200000,
                "streaming_recovery": {"first_token_deadline_seconds": 0}
            }
        }}}
    }'
    run validate_v3 "$doc"
    [ "$status" -ne 0 ]
}

@test "Reject: streaming_recovery extra property rejected" {
    doc='{
        "schema_version": 3,
        "providers": {"anthropic": {"models": {
            "claude-opus-4-7": {
                "context_window": 200000,
                "streaming_recovery": {
                    "first_token_deadline_seconds": 30,
                    "rogue_streaming_field": "should reject"
                }
            }
        }}}
    }'
    run validate_v3 "$doc"
    [ "$status" -ne 0 ]
}

# -----------------------------------------------------------------------------
# cycle-124 FR-1/FR-3 (SDD §2.1): typed `params` wire gates + live catalog
# -----------------------------------------------------------------------------

@test "V3-add (c124): params.thinking_adaptive + temperature_supported booleans accepted" {
    doc='{"schema_version": 3, "providers": {"anthropic": {"type": "anthropic", "endpoint": "https://api.anthropic.com", "models": {"claude-opus-5": {"context_window": 1000000, "params": {"thinking_adaptive": true, "temperature_supported": false}}}}}}'
    run validate_v3 "$doc"
    [ "$status" -eq 0 ]
}

@test "Reject (c124): params.thinking_adaptive must be boolean (string rejected)" {
    doc='{"schema_version": 3, "providers": {"anthropic": {"type": "anthropic", "endpoint": "https://api.anthropic.com", "models": {"claude-opus-5": {"context_window": 1000000, "params": {"thinking_adaptive": "yes"}}}}}}'
    run validate_v3 "$doc"
    [ "$status" -ne 0 ]
}

@test "Reject (c124): unknown params key rejected (a misspelt gate must not silently no-op)" {
    doc='{"schema_version": 3, "providers": {"anthropic": {"type": "anthropic", "endpoint": "https://api.anthropic.com", "models": {"claude-opus-5": {"context_window": 1000000, "params": {"thinking_adaptve": true}}}}}}'
    run validate_v3 "$doc"
    [ "$status" -ne 0 ]
}

@test "Reject (c124 audit): pricing.cache_read_per_mtok must be a non-negative integer (string rejected)" {
    doc='{"schema_version": 3, "providers": {"anthropic": {"type": "anthropic", "endpoint": "https://api.anthropic.com", "models": {"claude-opus-5": {"context_window": 1000000, "pricing": {"input_per_mtok": 5000000, "output_per_mtok": 25000000, "cache_read_per_mtok": "250000"}}}}}}'
    run validate_v3 "$doc"
    [ "$status" -ne 0 ]
    doc='{"schema_version": 3, "providers": {"anthropic": {"type": "anthropic", "endpoint": "https://api.anthropic.com", "models": {"claude-opus-5": {"context_window": 1000000, "pricing": {"input_per_mtok": 5000000, "output_per_mtok": 25000000, "cache_read_per_mtok": 250000}}}}}}'
    run validate_v3 "$doc"
    [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# cycle-126 sprint-250: the catalog keys Sprints 1–2 added (probed_ceiling,
# account_limits, headless_timeout_seconds, params.beta_headers) are typed in
# v3 to match their consumers — each test pairs an accepted shape with the
# refusals, so it is red while the key is unknown to the schema.
# -----------------------------------------------------------------------------

_c126_model() {  # <model-entry-json> → a one-model v3 document
    printf '{"schema_version": 3, "providers": {"anthropic": {"type": "anthropic", "endpoint": "https://api.anthropic.com", "models": {"m": %s}}}}' "$1"
}

@test "V3-add (c126): probed_ceiling is a positive integer (string, zero, boolean refused)" {
    run validate_v3 "$(_c126_model '{"context_window": 1000000, "probed_ceiling": 180000}')"
    [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
    for bad in '"180000"' 0 -1 true 1.5; do
        run validate_v3 "$(_c126_model "{\"context_window\": 1000000, \"probed_ceiling\": $bad}")"
        [ "$status" -ne 0 ] || { echo "accepted probed_ceiling: $bad" >&2; return 1; }
    done
}

@test "V3-add (c126): account_limits is {tier enum, itpm positive integer | null} and nothing else" {
    run validate_v3 "$(_c126_model '{"context_window": 1000000, "account_limits": {"tier": "unverified", "itpm": null}}')"
    [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
    run validate_v3 "$(_c126_model '{"context_window": 1000000, "account_limits": {"tier": "2", "itpm": 450000}}')"
    [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
    for bad in '{"tier": "5", "itpm": null}' '{"tier": 2, "itpm": null}' '{"tier": "unverified", "itpm": 0}' \
               '{"tier": "unverified", "itpm": "450000"}' '{"tier": "unverified", "itpm": null, "rpm": 50}' \
               '{"itpm": null}' '"unverified"'; do
        run validate_v3 "$(_c126_model "{\"context_window\": 1000000, \"account_limits\": $bad}")"
        [ "$status" -ne 0 ] || { echo "accepted account_limits: $bad" >&2; return 1; }
    done
}

@test "V3-add (c126): headless_timeout_seconds is a positive number (negative, zero, string, boolean refused)" {
    run validate_v3 "$(_c126_model '{"kind": "cli", "context_window": 1000000, "headless_timeout_seconds": 900}')"
    [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
    # above the 3600 s ceiling is accepted: cheval clamps it at load (types.coerce_headless_timeout_seconds)
    run validate_v3 "$(_c126_model '{"kind": "cli", "context_window": 1000000, "headless_timeout_seconds": 7200.5}')"
    [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
    for bad in -1 0 '"900"' true null; do
        run validate_v3 "$(_c126_model "{\"kind\": \"cli\", \"context_window\": 1000000, \"headless_timeout_seconds\": $bad}")"
        [ "$status" -ne 0 ] || { echo "accepted headless_timeout_seconds: $bad" >&2; return 1; }
    done
}

@test "V3-add (c126): params.beta_headers is a list of dated beta flags (the adapter's allowlist)" {
    run validate_v3 "$(_c126_model '{"context_window": 1000000, "params": {"beta_headers": []}}')"
    [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
    run validate_v3 "$(_c126_model '{"context_window": 1000000, "params": {"beta_headers": ["context-1m-2025-08-07", "interleaved-thinking-2025-05-14"]}}')"
    [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
    for bad in '"context-1m-2025-08-07"' '["Context-1M-2025-08-07"]' '["context-1m"]' '["context-1m-2025-8-7"]' \
               '[1]' '["context-1m-2025-08-07,x-2025-01-01"]' '["context--1m-2025-08-07"]' null; do
        run validate_v3 "$(_c126_model "{\"context_window\": 1000000, \"params\": {\"beta_headers\": $bad}}")"
        [ "$status" -ne 0 ] || { echo "accepted beta_headers: $bad" >&2; return 1; }
    done
}

@test "V3 (c126): every beta-header value the schema accepts, the adapter accepts (never looser)" {
    cd "$PROJECT_ROOT/.claude/adapters"
    run "$PYTHON_BIN" - "$SCHEMA_V3" <<'PYEOF'
import json, re, sys
from loa_cheval.providers import anthropic_adapter as a
schema = json.load(open(sys.argv[1]))
pat = schema["$defs"]["modelEntry"]["properties"]["params"]["properties"]["beta_headers"]["items"]["pattern"]
cases = ["context-1m-2025-08-07", "a-2025-01-01", "x1-y2-2030-12-31", "Context-1m-2025-08-07", "context-1m",
         "context-1m-2025-8-7", "-a-2025-01-01", "a--b-2025-01-01", "a-2025-01-01-", "a b-2025-01-01",
         "a-٢٠٢٥-01-01"]
accepted = [c for c in cases if re.search(pat, c)]
assert "context-1m-2025-08-07" in accepted, accepted
bad = [c for c in accepted if not a._BETA_HEADER_RE.match(c)]
print("MISMATCH %r" % bad if bad else "OK")
PYEOF
    [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
    [[ "$output" == *"OK"* ]] || { echo "$output" >&2; return 1; }
}

@test "Live (c124): production model-config.yaml migrated with --to-v3 validates against v3 and keeps the catalog's own ceiling" {
    MIGRATE="$PROJECT_ROOT/.claude/scripts/loa-migrate-model-config.py"
    "$PYTHON_BIN" -c "import ruamel.yaml" 2>/dev/null || skip "ruamel.yaml not available in $PYTHON_BIN"
    run "$PYTHON_BIN" "$MIGRATE" "$PROJECT_ROOT/.claude/defaults/model-config.yaml" \
        -o "$WORK_DIR/live-v3.yaml" --to-v3 \
        --model-permissions "$PROJECT_ROOT/.claude/data/model-permissions.yaml" \
        --report-format json
    [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
    run "$PYTHON_BIN" - <<PYEOF
import json, jsonschema
from ruamel.yaml import YAML
data = YAML(typ="safe").load(open("$WORK_DIR/live-v3.yaml"))
schema = json.load(open("$SCHEMA_V3"))
jsonschema.Draft202012Validator(schema).validate(data)
assert data["schema_version"] == 3, data.get("schema_version")
m = data["providers"]["anthropic"]["models"]["claude-opus-5"]
assert m["effective_input_ceiling"] == 180000, m.get("effective_input_ceiling")
assert m["params"]["thinking_adaptive"] is True, m.get("params")
print("OK")
PYEOF
    [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
    [[ "$output" == *"OK"* ]]
}
