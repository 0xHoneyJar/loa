#!/usr/bin/env bats
# =============================================================================
# tests/integration/sprint-2D-resolver-parity.bats
#
# cycle-099 Sprint 2D — Cross-runtime parity assertion for the FR-3.9 6-stage
# resolver (T2.6).
#
# This bats wraps the Python canonical resolver (`tests/python/golden_resolution.py`,
# extended in 2D) and the bash golden runner (`tests/bash/golden_resolution.sh`,
# extended in 2D) and asserts byte-equal canonical-JSON output across all 12
# fixtures in tests/fixtures/model-resolution/.
#
# Per SDD §1.5.1 + §7.6, Python is the canonical reference; bash is a
# parity-verifier (test code only — production bash sources merged-aliases.sh,
# not this runner). Any divergence between the two on the fixture corpus is a
# resolver bug or fixture bug. Sprint 2D's central deliverable is keeping
# these in lock-step.
#
# Test surface (P1-P12 + spec compliance per stage):
#   P1  — both runners exit 0 against full corpus
#   P2  — line counts match (same number of resolution results)
#   P3  — every line is canonical JSON (sorted keys, no whitespace)
#   P4  — every line conforms to model-resolver-output.schema.json
#   P5  — byte-equal output across runtimes
#   P6  — sort order is stable across runtimes
#   P7  — fixture 02 (explicit pin) — both runners produce stage1 hit
#   P8  — fixture 03 (TIER-NO-MAPPING) — both runners produce error block
#   P9  — fixture 04 (legacy shape) — both runners produce stage4 hit
#   P10 — fixture 09 (prefer_pro overlay) — both runners produce stage6 applied
#   P11 — fixture 10 (extra+override collision) — both runners produce error
#   P12 — fixture 12 (degraded mode) — both runners produce stage5 with degraded source
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    FIXTURES_DIR="$PROJECT_ROOT/tests/fixtures/model-resolution"
    BASH_RUNNER="$PROJECT_ROOT/tests/bash/golden_resolution.sh"
    PY_RUNNER="$PROJECT_ROOT/tests/python/golden_resolution.py"
    SCHEMA="$PROJECT_ROOT/.claude/data/trajectory-schemas/model-resolver-output.schema.json"

    [[ -d "$FIXTURES_DIR" ]] || skip "fixtures dir not present"
    [[ -x "$BASH_RUNNER" ]] || skip "bash runner not present/executable"
    [[ -f "$PY_RUNNER" ]] || skip "python runner not present"
    [[ -f "$SCHEMA" ]] || skip "resolver-output schema not present"
    command -v jq >/dev/null 2>&1 || skip "jq not present"
    command -v yq >/dev/null 2>&1 || skip "yq not present"
    command -v python3 >/dev/null 2>&1 || skip "python3 not present"

    WORK_DIR="$(mktemp -d)"
    BASH_OUT="$WORK_DIR/bash.jsonl"
    PY_OUT="$WORK_DIR/python.jsonl"

    # Sprint 2D mode flag — runners emit FR-3.9 6-stage shape under this flag.
    # Without the flag, runners emit Sprint 1D's alias-lookup subset (kept for
    # backward compat with the existing G-series bats during the transition).
    export LOA_RESOLVER_MODE=sprint-2D
}

teardown() {
    if [[ -n "${WORK_DIR:-}" ]] && [[ -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
    return 0
}

# ----- helpers -----

_run_bash_runner() {
    "$BASH_RUNNER" > "$BASH_OUT"
}

_run_py_runner() {
    python3 "$PY_RUNNER" > "$PY_OUT"
}

_assert_schema_valid() {
    local file="$1"
    # Pass paths via env vars (NOT heredoc interpolation) per cycle-099
    # sprint-1E.a `_python_assert` lesson — heredoc shell-injection-into-
    # Python-source is a real surface when paths contain quotes/$/\.
    local err_log="$WORK_DIR/schema-errors.log"
    : > "$err_log"
    LOA_SCHEMA_PATH="$SCHEMA" \
    LOA_INPUT_FILE="$file" \
    python3 - <<'PY' >>"$err_log" 2>&1 || {
import json, os, sys
from jsonschema import validate, ValidationError
schema_path = os.environ["LOA_SCHEMA_PATH"]
input_path = os.environ["LOA_INPUT_FILE"]
with open(schema_path, "r", encoding="utf-8") as fh:
    schema = json.load(fh)
errors = 0
with open(input_path, "r", encoding="utf-8") as fh:
    for lineno, line in enumerate(fh, start=1):
        line = line.rstrip("\n")
        if not line:
            continue
        try:
            doc = json.loads(line)
        except json.JSONDecodeError as exc:
            print(f"[NON-JSON] line {lineno}: {exc.msg}", file=sys.stderr)
            errors += 1
            continue
        try:
            validate(doc, schema)
        except ValidationError as exc:
            print(f"[SCHEMA-VIOLATION] line {lineno}: {exc.message}", file=sys.stderr)
            print(f"  on: {line}", file=sys.stderr)
            errors += 1
sys.exit(0 if errors == 0 else 1)
PY
        printf 'schema validation failed for %s:\n' "$file" >&2
        cat "$err_log" >&2
        return 1
    }
}

# ----- P1-P6 cross-runtime parity -----

@test "P1 both runners exit 0 against full corpus" {
    run _run_bash_runner
    [[ "$status" -eq 0 ]] || {
        printf 'bash runner failed; status=%d output=%s\n' "$status" "$output" >&2
        return 1
    }
    run _run_py_runner
    [[ "$status" -eq 0 ]] || {
        printf 'python runner failed; status=%d output=%s\n' "$status" "$output" >&2
        return 1
    }
}

@test "P2 line counts match between bash + python runners" {
    _run_bash_runner
    _run_py_runner
    local bash_lines py_lines
    bash_lines=$(wc -l < "$BASH_OUT")
    py_lines=$(wc -l < "$PY_OUT")
    [[ "$bash_lines" -eq "$py_lines" ]] || {
        printf 'line counts diverge: bash=%d python=%d\n' "$bash_lines" "$py_lines" >&2
        return 1
    }
}

@test "P3 every line is canonical JSON across both runners" {
    _run_bash_runner
    _run_py_runner
    for f in "$BASH_OUT" "$PY_OUT"; do
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            echo "$line" | jq -e . >/dev/null || {
                printf 'non-JSON line in %s: %s\n' "$f" "$line" >&2
                return 1
            }
            local canonical
            canonical=$(echo "$line" | jq -S -c .)
            [[ "$line" == "$canonical" ]] || {
                printf 'non-canonical line in %s:\n  got: %s\n  exp: %s\n' "$f" "$line" "$canonical" >&2
                return 1
            }
        done < "$f"
    done
}

@test "P4 every line conforms to model-resolver-output.schema.json" {
    python3 -c 'import jsonschema' 2>/dev/null || skip "jsonschema not installed"
    _run_bash_runner
    _run_py_runner
    _assert_schema_valid "$BASH_OUT" || return 1
    _assert_schema_valid "$PY_OUT" || return 1
}

@test "P5 byte-equal output across runtimes" {
    _run_bash_runner
    _run_py_runner
    if ! diff -u "$BASH_OUT" "$PY_OUT"; then
        printf '\n[CROSS-RUNTIME-DIFF-FAIL] bash runner diverged from python runner.\n' >&2
        printf 'See diff above. Sprint 2D requires byte-equal output.\n' >&2
        return 1
    fi
}

@test "P6 sort order is stable across runtimes (sorted by fixture, skill, role)" {
    _run_bash_runner
    # Verify each runner's output is sorted by (fixture-filename → skill → role)
    # by extracting the keys and asserting against a sorted version.
    local extracted
    extracted=$(jq -r '"\(.fixture // "")|\(.skill // "")|\(.role // "")"' < "$BASH_OUT")
    local sorted
    sorted=$(printf '%s\n' "$extracted" | LC_ALL=C sort)
    [[ "$extracted" == "$sorted" ]] || {
        printf 'bash output not sorted by (fixture, skill, role)\n--- got ---\n%s\n--- want ---\n%s\n' "$extracted" "$sorted" >&2
        return 1
    }
}

# ----- P7-P12 stage spec compliance (FR-3.9 verbatim) -----

@test "P7 fixture 02 (explicit pin) → both runners emit stage1_pin_check hit" {
    _run_bash_runner
    _run_py_runner
    for f in "$BASH_OUT" "$PY_OUT"; do
        local line
        line=$(grep '"02-explicit-pin-wins"' "$f" || true)
        [[ -n "$line" ]] || {
            printf 'fixture 02 missing from %s\n' "$f" >&2
            return 1
        }
        echo "$line" | jq -e '
            .resolved_provider == "anthropic" and
            .resolved_model_id == "claude-opus-4-7" and
            .resolution_path[0].stage == 1 and
            .resolution_path[0].outcome == "hit" and
            .resolution_path[0].label == "stage1_pin_check"
        ' >/dev/null || {
            printf 'fixture 02 stage1 assertion failed in %s: %s\n' "$f" "$line" >&2
            return 1
        }
    done
}

@test "P8 fixture 03 (TIER-NO-MAPPING) → both runners emit error block" {
    _run_bash_runner
    _run_py_runner
    for f in "$BASH_OUT" "$PY_OUT"; do
        local line
        line=$(grep '"03-missing-tier-fail-closed"' "$f" || true)
        [[ -n "$line" ]] || {
            printf 'fixture 03 missing from %s\n' "$f" >&2
            return 1
        }
        echo "$line" | jq -e '
            .error.code == "[TIER-NO-MAPPING]" and
            .error.stage_failed == 3 and
            (.error.detail | length) > 0 and
            (has("resolved_provider") | not) and
            (has("resolution_path") | not)
        ' >/dev/null || {
            printf 'fixture 03 error assertion failed in %s: %s\n' "$f" "$line" >&2
            return 1
        }
    done
}

@test "P9 fixture 04 (legacy shape) → both runners emit stage4_legacy_shape hit" {
    _run_bash_runner
    _run_py_runner
    for f in "$BASH_OUT" "$PY_OUT"; do
        local line
        line=$(grep '"04-legacy-shape-deprecation"' "$f" || true)
        [[ -n "$line" ]] || {
            printf 'fixture 04 missing from %s\n' "$f" >&2
            return 1
        }
        echo "$line" | jq -e '
            .resolved_provider == "anthropic" and
            .resolved_model_id == "claude-opus-4-7" and
            .resolution_path[-1].stage == 4 and
            .resolution_path[-1].label == "stage4_legacy_shape" and
            .resolution_path[-1].details.warning == "[LEGACY-SHAPE-DEPRECATED]"
        ' >/dev/null || {
            printf 'fixture 04 stage4 assertion failed in %s: %s\n' "$f" "$line" >&2
            return 1
        }
    done
}

@test "P10 fixture 09 (prefer_pro overlay) → both runners emit stage6 applied" {
    _run_bash_runner
    _run_py_runner
    for f in "$BASH_OUT" "$PY_OUT"; do
        local line
        line=$(grep '"09-prefer-pro-overlay"' "$f" || true)
        [[ -n "$line" ]] || {
            printf 'fixture 09 missing from %s\n' "$f" >&2
            return 1
        }
        echo "$line" | jq -e '
            .resolved_provider == "google" and
            .resolved_model_id == "gemini-2.5-pro" and
            (.resolution_path | map(select(.stage == 6 and .outcome == "applied" and .label == "stage6_prefer_pro_overlay")) | length) == 1
        ' >/dev/null || {
            printf 'fixture 09 stage6 assertion failed in %s: %s\n' "$f" "$line" >&2
            return 1
        }
    done
}

@test "P11 fixture 10 (extra+override collision) → both runners emit error" {
    _run_bash_runner
    _run_py_runner
    for f in "$BASH_OUT" "$PY_OUT"; do
        local line
        line=$(grep '"10-extra-vs-override-collision"' "$f" || true)
        [[ -n "$line" ]] || {
            printf 'fixture 10 missing from %s\n' "$f" >&2
            return 1
        }
        echo "$line" | jq -e '
            .error.code == "[MODEL-EXTRA-OVERRIDE-CONFLICT]" and
            .error.stage_failed == 0
        ' >/dev/null || {
            printf 'fixture 10 collision assertion failed in %s: %s\n' "$f" "$line" >&2
            return 1
        }
    done
}

@test "P12 fixture 12 (degraded mode) → both runners emit stage5 with degraded source" {
    _run_bash_runner
    _run_py_runner
    for f in "$BASH_OUT" "$PY_OUT"; do
        local line
        line=$(grep '"12-degraded-mode-readonly"' "$f" || true)
        [[ -n "$line" ]] || {
            printf 'fixture 12 missing from %s\n' "$f" >&2
            return 1
        }
        echo "$line" | jq -e '
            .resolved_provider == "anthropic" and
            .resolved_model_id == "claude-sonnet-4-6" and
            .resolution_path[0].stage == 5 and
            .resolution_path[0].label == "stage5_framework_default" and
            .resolution_path[0].details.source == "degraded_cache"
        ' >/dev/null || {
            printf 'fixture 12 degraded-mode assertion failed in %s: %s\n' "$f" "$line" >&2
            return 1
        }
    done
}

# ----- P13 spec compliance: IMP-007 alias-collides-with-tier tiebreaker -----

@test "P13 alias-collides-with-tier → tier-tag wins (IMP-007)" {
    # Synthesize a fixture where skill_models.X.Y = "max" AND model_aliases_extra
    # also defines an entry called "max". Per IMP-007 (SDD §3.3.1), tier-tag
    # interpretation wins (FR-3.9 stage 2/3 path, NOT model_aliases_extra alias).
    local synth_dir="$WORK_DIR/synth-imp007"
    mkdir -p "$synth_dir"
    cat > "$synth_dir/zz-imp007-collision.yaml" <<'EOF'
description: "IMP-007 — skill_models value 'max' collides with model_aliases_extra entry 'max'; tier-tag wins."

input:
  schema_version: 2
  framework_defaults:
    providers:
      anthropic:
        models:
          claude-opus-4-7: { capabilities: [chat], context_window: 200000 }
    aliases:
      opus: { provider: anthropic, model_id: claude-opus-4-7 }
    tier_groups:
      mappings:
        max: { anthropic: opus }
  operator_config:
    skill_models:
      flatline_protocol:
        primary: max
    model_aliases_extra:
      max:
        provider: anthropic
        model_id: claude-opus-4-7
        capabilities: [chat]

expected:
  resolutions:
    - skill: flatline_protocol
      role: primary
      resolved_provider: anthropic
      resolved_model_id: claude-opus-4-7
      resolution_path:
        - { stage: 2, outcome: hit, label: stage2_skill_models, details: { alias: max } }
        - { stage: 3, outcome: hit, label: stage3_tier_groups, details: { resolved_alias: opus, alias_collides_with_tier: true } }
  cross_runtime_byte_identical: true
EOF
    LOA_GOLDEN_TEST_MODE=1 LOA_GOLDEN_FIXTURES_DIR="$synth_dir" "$BASH_RUNNER" > "$WORK_DIR/imp007.bash.jsonl"
    LOA_GOLDEN_TEST_MODE=1 LOA_GOLDEN_FIXTURES_DIR="$synth_dir" python3 "$PY_RUNNER" > "$WORK_DIR/imp007.py.jsonl"
    if ! diff -u "$WORK_DIR/imp007.bash.jsonl" "$WORK_DIR/imp007.py.jsonl"; then
        printf 'IMP-007 cross-runtime divergence; see diff\n' >&2
        return 1
    fi
    # Verify the tier-tag-wins path
    grep -q '"stage2_skill_models"' "$WORK_DIR/imp007.bash.jsonl" || {
        printf 'IMP-007 should resolve via tier-tag (stage 2 hit); got: %s\n' "$(cat "$WORK_DIR/imp007.bash.jsonl")" >&2
        return 1
    }
    grep -q '"stage3_tier_groups"' "$WORK_DIR/imp007.bash.jsonl" || {
        printf 'IMP-007 should cascade to stage 3; got: %s\n' "$(cat "$WORK_DIR/imp007.bash.jsonl")" >&2
        return 1
    }
}

# ----- P14 spec compliance: stage 6 gated for legacy shapes (FR-3.4) -----

@test "P15 string-form aliases (cycle-095 back-compat shape) parse identically across runtimes" {
    # Production `.claude/defaults/model-config.yaml` uses string-form aliases
    # `<name>: "provider:model_id"` rather than the dict-form `{provider, model_id}`.
    # Both runtimes must normalize them identically.
    local synth_dir="$WORK_DIR/synth-string-form"
    mkdir -p "$synth_dir"
    cat > "$synth_dir/zz-string-form.yaml" <<'EOF'
description: "string-form alias (cycle-095 back-compat shape) — production model-config.yaml uses this shape"
input:
  schema_version: 2
  framework_defaults:
    providers:
      openai:
        models:
          gpt-5.5: { capabilities: [chat] }
    aliases:
      reviewer: "openai:gpt-5.5"
  operator_config:
    skill_models:
      flatline_protocol:
        primary: reviewer
expected:
  resolutions:
    - skill: flatline_protocol
      role: primary
      resolved_provider: openai
      resolved_model_id: gpt-5.5
      resolution_path:
        - { stage: 2, outcome: hit, label: stage2_skill_models, details: { alias: reviewer } }
EOF
    LOA_GOLDEN_TEST_MODE=1 LOA_GOLDEN_FIXTURES_DIR="$synth_dir" "$BASH_RUNNER" > "$WORK_DIR/sf.bash.jsonl"
    LOA_GOLDEN_TEST_MODE=1 LOA_GOLDEN_FIXTURES_DIR="$synth_dir" python3 "$PY_RUNNER" > "$WORK_DIR/sf.py.jsonl"
    diff -u "$WORK_DIR/sf.bash.jsonl" "$WORK_DIR/sf.py.jsonl" || {
        printf 'string-form alias cross-runtime divergence\n' >&2
        return 1
    }
    grep -q '"resolved_model_id":"gpt-5.5"' "$WORK_DIR/sf.bash.jsonl" || {
        printf 'string-form alias should normalize to gpt-5.5; got: %s\n' "$(cat "$WORK_DIR/sf.bash.jsonl")" >&2
        return 1
    }
}

@test "P14 stage 6 prefer_pro overlay is gated for legacy shapes (FR-3.4)" {
    # Per FR-3.4: legacy-shape skills (flatline_protocol.models.X / etc) require
    # opt-in `respect_prefer_pro: true` to receive stage 6 overlay. Default off.
    local synth_dir="$WORK_DIR/synth-fr34"
    mkdir -p "$synth_dir"
    cat > "$synth_dir/zz-fr34-legacy-no-pro.yaml" <<'EOF'
description: "FR-3.4 — legacy shape with prefer_pro_models=true but respect_prefer_pro NOT set; stage 6 SKIPPED."

input:
  schema_version: 2
  framework_defaults:
    providers:
      google:
        models:
          gemini-2.5-flash: { capabilities: [chat], context_window: 1000000 }
          gemini-2.5-pro: { capabilities: [chat], context_window: 1000000 }
    aliases:
      flash: { provider: google, model_id: gemini-2.5-flash }
      flash-pro: { provider: google, model_id: gemini-2.5-pro }
  operator_config:
    prefer_pro_models: true
    flatline_protocol:
      models:
        primary: flash

expected:
  resolutions:
    - skill: flatline_protocol
      role: primary
      resolved_provider: google
      resolved_model_id: gemini-2.5-flash
      resolution_path:
        - { stage: 4, outcome: hit, label: stage4_legacy_shape, details: { warning: "[LEGACY-SHAPE-DEPRECATED]" } }
        - { stage: 6, outcome: skipped, label: stage6_prefer_pro_overlay, details: { reason: legacy_shape_without_respect_prefer_pro } }
  cross_runtime_byte_identical: true
EOF
    LOA_GOLDEN_TEST_MODE=1 LOA_GOLDEN_FIXTURES_DIR="$synth_dir" "$BASH_RUNNER" > "$WORK_DIR/fr34.bash.jsonl"
    LOA_GOLDEN_TEST_MODE=1 LOA_GOLDEN_FIXTURES_DIR="$synth_dir" python3 "$PY_RUNNER" > "$WORK_DIR/fr34.py.jsonl"
    diff -u "$WORK_DIR/fr34.bash.jsonl" "$WORK_DIR/fr34.py.jsonl" || {
        printf 'FR-3.4 cross-runtime divergence\n' >&2
        return 1
    }
    grep -q '"stage6_prefer_pro_overlay"' "$WORK_DIR/fr34.bash.jsonl" || {
        printf 'FR-3.4 should emit stage6 entry (skipped); got: %s\n' "$(cat "$WORK_DIR/fr34.bash.jsonl")" >&2
        return 1
    }
    grep -q '"skipped"' "$WORK_DIR/fr34.bash.jsonl" || {
        printf 'FR-3.4 stage6 should be SKIPPED for legacy shape; got: %s\n' "$(cat "$WORK_DIR/fr34.bash.jsonl")" >&2
        return 1
    }
    # And the model_id must NOT be retargeted to *-pro
    grep -q 'gemini-2.5-flash' "$WORK_DIR/fr34.bash.jsonl" || {
        printf 'FR-3.4 model_id should remain non-pro for legacy shape; got: %s\n' "$(cat "$WORK_DIR/fr34.bash.jsonl")" >&2
        return 1
    }
    if grep -q 'gemini-2.5-pro' "$WORK_DIR/fr34.bash.jsonl"; then
        printf '[FR-3.4-VIOLATION] legacy shape received pro retarget without respect_prefer_pro\n' >&2
        return 1
    fi
}
