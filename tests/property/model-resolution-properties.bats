#!/usr/bin/env bats
# =============================================================================
# tests/property/model-resolution-properties.bats
#
# cycle-099 Sprint 2D.d (T2.6 closure) — SC-14 property suite.
#
# Verifies the six FR-3.9 invariants on ~100 random valid configs per
# invariant per CI run; nightly stress runs at ~1000 iterations.
#
# Six invariants (per FR-3.9 v1.2 SC-14):
#   I1. (S1) and (S4) both present → (S1) wins.
#   I2. Two same-priority mechanisms always produce error
#       (extra+override id collision → [MODEL-EXTRA-OVERRIDE-CONFLICT]).
#   I3. prefer_pro overlay always applied last (S6 entry, when present,
#       is the last entry in resolution_path).
#   I4. Deprecation warning emitted ⟺ S4 was the resolution path.
#   I5. Operator-set tier_groups mapping resolves before framework default
#       when both define the same (tier, provider) mapping.
#   I6. Unmapped tier produces [TIER-NO-MAPPING] (stage_failed=3); never
#       silently falls through to S5.
#
# Determinism: each iteration's seed is `${LOA_PROPERTY_SEED_BASE} + i`.
# Default base=1, default iterations=100. Operators reproduce a CI failure
# by running:
#
#     LOA_PROPERTY_SEED_BASE=<failed-seed> LOA_PROPERTY_ITERATIONS=1 \
#       bats tests/property/model-resolution-properties.bats
#
# Per AC-S2.d.3: shells out to canonical Python resolver. The fully-qualified
# command is `python3 .claude/scripts/lib/model-resolver.py resolve` because
# the resolver lives at a hyphenated path (not an importable module). This
# satisfies the spirit of the AC ("invokes the canonical Python resolver").
# =============================================================================

setup_file() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export SCRIPT_DIR PROJECT_ROOT
    export PROPERTY_GEN_LIB="$PROJECT_ROOT/tests/property/lib/property-gen.bash"
    export RESOLVER_PY="$PROJECT_ROOT/.claude/scripts/lib/model-resolver.py"
    [[ -f "$PROPERTY_GEN_LIB" ]] || {
        printf '[property-bats] property-gen library missing\n' >&2
        return 1
    }
    [[ -f "$RESOLVER_PY" ]] || {
        printf '[property-bats] resolver missing\n' >&2
        return 1
    }
}

setup() {
    command -v jq >/dev/null 2>&1 || skip "jq not present"
    command -v yq >/dev/null 2>&1 || skip "yq not present"
    command -v python3 >/dev/null 2>&1 || skip "python3 not present"
    # shellcheck source=tests/property/lib/property-gen.bash
    source "$PROPERTY_GEN_LIB"
    WORK_DIR="$(mktemp -d)"
    CFG="$WORK_DIR/config.yaml"
    OUT="$WORK_DIR/resolver.json"
    ITER="${LOA_PROPERTY_ITERATIONS:-100}"
    BASE="${LOA_PROPERTY_SEED_BASE:-1}"
    if ! [[ "$ITER" =~ ^[1-9][0-9]*$ ]]; then
        skip "LOA_PROPERTY_ITERATIONS must be a positive integer"
    fi
    if ! [[ "$BASE" =~ ^[1-9][0-9]*$ ]]; then
        skip "LOA_PROPERTY_SEED_BASE must be a positive integer"
    fi
}

teardown() {
    if [[ -n "${WORK_DIR:-}" ]] && [[ -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
    return 0
}

# Helpers --------------------------------------------------------------

# Run resolver against $CFG with (skill, role); writes JSON to $OUT.
# Returns 0 on success-OR-error-block (resolver exits 0 success / 1 error,
# both are valid resolver behavior; we differentiate via the JSON shape).
_run_resolver() {
    local skill="$1" role="$2"
    python3 "$RESOLVER_PY" resolve --config "$CFG" --skill "$skill" --role "$role" \
        > "$OUT" 2>"$WORK_DIR/stderr.log" || true
    if ! [[ -s "$OUT" ]]; then
        printf '[property-bats] resolver produced empty stdout; stderr was:\n' >&2
        cat "$WORK_DIR/stderr.log" >&2
        return 1
    fi
}

# Read query metadata from $CFG; sets bash-level locals via printf -v.
# Caller declares the locals and passes them by name.
_read_query() {
    local skill_var="$1" role_var="$2"
    local s r
    s=$(yq '._property_query.skill' "$CFG")
    r=$(yq '._property_query.role' "$CFG")
    printf -v "$skill_var" '%s' "$s"
    printf -v "$role_var" '%s' "$r"
}

# Pretty failure dump for reproducibility.
_dump_failure() {
    local invariant="$1" seed="$2" detail="$3"
    {
        printf '\n========== property-fail invariant=%s seed=%s ==========\n' "$invariant" "$seed"
        printf '%s\n' "$detail"
        printf '----- config -----\n'
        cat "$CFG"
        printf '\n----- resolver output -----\n'
        cat "$OUT" 2>/dev/null || true
        printf '\n----- resolver stderr -----\n'
        cat "$WORK_DIR/stderr.log" 2>/dev/null || true
        printf '----- end -----\n'
    } >&2
}

# ---------------------------------------------------------------------
# Invariant 1 — explicit pin (S1) always wins over legacy shape (S4)
# ---------------------------------------------------------------------
@test "I1: skill_models pin always wins over legacy <skill>.models entry" {
    local i seed skill role expected_provider expected_model_id
    local first_label has_stage4 actual_provider actual_model_id
    for ((i=0; i<ITER; i++)); do
        seed=$((BASE + i))
        prop_gen_inv1_config "$seed" > "$CFG" || {
            _dump_failure 1 "$seed" "generator failed"
            return 1
        }
        _read_query skill role
        expected_provider=$(yq '._property_query.expected_pin_provider' "$CFG")
        expected_model_id=$(yq '._property_query.expected_pin_model_id' "$CFG")
        _run_resolver "$skill" "$role" || { _dump_failure 1 "$seed" "resolver crashed"; return 1; }

        actual_provider=$(jq -r '.resolved_provider // empty' "$OUT")
        actual_model_id=$(jq -r '.resolved_model_id // empty' "$OUT")
        first_label=$(jq -r '.resolution_path[0].label // empty' "$OUT")
        has_stage4=$(jq -r '[.resolution_path[]?.label // empty] | any(. == "stage4_legacy_shape")' "$OUT")

        if [[ "$actual_provider" != "$expected_provider" ]]; then
            _dump_failure 1 "$seed" "expected resolved_provider=$expected_provider got=$actual_provider"
            return 1
        fi
        if [[ "$actual_model_id" != "$expected_model_id" ]]; then
            _dump_failure 1 "$seed" "expected resolved_model_id=$expected_model_id got=$actual_model_id"
            return 1
        fi
        if [[ "$first_label" != "stage1_pin_check" ]]; then
            _dump_failure 1 "$seed" "expected first stage label=stage1_pin_check got=$first_label"
            return 1
        fi
        if [[ "$has_stage4" != "false" ]]; then
            _dump_failure 1 "$seed" "stage4_legacy_shape unexpectedly present in resolution_path"
            return 1
        fi
    done
}

# ---------------------------------------------------------------------
# Invariant 2 — same id in extra+override → MODEL-EXTRA-OVERRIDE-CONFLICT
# ---------------------------------------------------------------------
@test "I2: model_aliases_extra/override id collision yields error, never silent tiebreaker" {
    local i seed skill role expected_code expected_stage
    local actual_code actual_stage has_resolution_path
    for ((i=0; i<ITER; i++)); do
        seed=$((BASE + i))
        prop_gen_inv2_config "$seed" > "$CFG" || {
            _dump_failure 2 "$seed" "generator failed"
            return 1
        }
        _read_query skill role
        expected_code=$(yq '._property_query.expected_error_code' "$CFG")
        expected_stage=$(yq '._property_query.expected_stage_failed' "$CFG")
        _run_resolver "$skill" "$role" || { _dump_failure 2 "$seed" "resolver crashed"; return 1; }

        actual_code=$(jq -r '.error.code // empty' "$OUT")
        actual_stage=$(jq -r '.error.stage_failed // empty' "$OUT")
        has_resolution_path=$(jq -r 'has("resolution_path")' "$OUT")

        if [[ "$actual_code" != "$expected_code" ]]; then
            _dump_failure 2 "$seed" "expected error.code=$expected_code got=$actual_code"
            return 1
        fi
        if [[ "$actual_stage" != "$expected_stage" ]]; then
            _dump_failure 2 "$seed" "expected error.stage_failed=$expected_stage got=$actual_stage"
            return 1
        fi
        if [[ "$has_resolution_path" != "false" ]]; then
            _dump_failure 2 "$seed" "resolution_path unexpectedly present alongside error"
            return 1
        fi
    done
}

# ---------------------------------------------------------------------
# Invariant 3 — prefer_pro overlay (S6) always applied last
# ---------------------------------------------------------------------
@test "I3: stage6 entry, when present, is always the last entry in resolution_path" {
    local i seed skill role expected_alias_base expected_alias_pro
    local last_stage last_label last_to last_outcome path_len last_idx
    for ((i=0; i<ITER; i++)); do
        seed=$((BASE + i))
        prop_gen_inv3_config "$seed" > "$CFG" || {
            _dump_failure 3 "$seed" "generator failed"
            return 1
        }
        _read_query skill role
        expected_alias_base=$(yq '._property_query.expected_alias_base' "$CFG")
        expected_alias_pro=$(yq '._property_query.expected_alias_pro' "$CFG")
        _run_resolver "$skill" "$role" || { _dump_failure 3 "$seed" "resolver crashed"; return 1; }

        path_len=$(jq -r '.resolution_path | length' "$OUT")
        if [[ -z "$path_len" ]] || [[ "$path_len" == "null" ]] || [[ "$path_len" == "0" ]]; then
            _dump_failure 3 "$seed" "expected non-empty resolution_path"
            return 1
        fi
        last_idx=$((path_len - 1))
        last_stage=$(jq -r ".resolution_path[$last_idx].stage" "$OUT")
        last_label=$(jq -r ".resolution_path[$last_idx].label" "$OUT")
        last_outcome=$(jq -r ".resolution_path[$last_idx].outcome" "$OUT")
        last_to=$(jq -r ".resolution_path[$last_idx].details.to // empty" "$OUT")

        if [[ "$last_stage" != "6" ]]; then
            _dump_failure 3 "$seed" "expected last stage=6 got=$last_stage"
            return 1
        fi
        if [[ "$last_label" != "stage6_prefer_pro_overlay" ]]; then
            _dump_failure 3 "$seed" "expected last label=stage6_prefer_pro_overlay got=$last_label"
            return 1
        fi
        if [[ "$last_outcome" != "applied" ]]; then
            _dump_failure 3 "$seed" "expected last outcome=applied got=$last_outcome"
            return 1
        fi
        if [[ "$last_to" != "$expected_alias_pro" ]]; then
            _dump_failure 3 "$seed" "expected stage6.details.to=$expected_alias_pro got=$last_to"
            return 1
        fi
    done
}

# ---------------------------------------------------------------------
# Invariant 4 — deprecation warning emitted ⟺ S4 was the resolution path
# ---------------------------------------------------------------------
@test "I4: deprecation warning iff stage4 was on the resolution path (biconditional)" {
    local i seed skill role legacy_only
    local has_stage4 has_warning
    for ((i=0; i<ITER; i++)); do
        seed=$((BASE + i))
        prop_gen_inv4_config "$seed" > "$CFG" || {
            _dump_failure 4 "$seed" "generator failed"
            return 1
        }
        _read_query skill role
        legacy_only=$(yq '._property_query.legacy_only' "$CFG")
        _run_resolver "$skill" "$role" || { _dump_failure 4 "$seed" "resolver crashed"; return 1; }

        has_stage4=$(jq -r '[.resolution_path[]?.label // empty] | any(. == "stage4_legacy_shape")' "$OUT")
        has_warning=$(jq -r '[.resolution_path[]?.details.warning // empty] | any(. == "[LEGACY-SHAPE-DEPRECATED]")' "$OUT")

        if [[ "$legacy_only" == "true" ]]; then
            if [[ "$has_stage4" != "true" ]]; then
                _dump_failure 4 "$seed" "legacy_only=true but no stage4 in resolution_path"
                return 1
            fi
            if [[ "$has_warning" != "true" ]]; then
                _dump_failure 4 "$seed" "legacy_only=true but no [LEGACY-SHAPE-DEPRECATED] warning"
                return 1
            fi
        else
            if [[ "$has_stage4" != "false" ]]; then
                _dump_failure 4 "$seed" "legacy_only=false but stage4 is present"
                return 1
            fi
            if [[ "$has_warning" != "false" ]]; then
                _dump_failure 4 "$seed" "legacy_only=false but [LEGACY-SHAPE-DEPRECATED] warning present"
                return 1
            fi
        fi

        # Biconditional: stage4_present ⟺ warning_present (catches a bug
        # where the warning is on a non-stage-4 entry, e.g. via copy-paste).
        if [[ "$has_stage4" != "$has_warning" ]]; then
            _dump_failure 4 "$seed" "biconditional violated: has_stage4=$has_stage4 has_warning=$has_warning"
            return 1
        fi
    done
}

# ---------------------------------------------------------------------
# Invariant 5 — operator tier_groups precedence over framework default
# ---------------------------------------------------------------------
@test "I5: operator tier_groups.mappings resolves before framework default" {
    local i seed skill role expected_alias expected_model_id
    local resolved_model_id resolved_alias has_stage3
    for ((i=0; i<ITER; i++)); do
        seed=$((BASE + i))
        prop_gen_inv5_config "$seed" > "$CFG" || {
            _dump_failure 5 "$seed" "generator failed"
            return 1
        }
        _read_query skill role
        expected_alias=$(yq '._property_query.expected_resolved_alias' "$CFG")
        expected_model_id=$(yq '._property_query.expected_resolved_model_id' "$CFG")
        _run_resolver "$skill" "$role" || { _dump_failure 5 "$seed" "resolver crashed"; return 1; }

        resolved_model_id=$(jq -r '.resolved_model_id // empty' "$OUT")
        has_stage3=$(jq -r '[.resolution_path[]?.label // empty] | any(. == "stage3_tier_groups")' "$OUT")
        resolved_alias=$(jq -r '[.resolution_path[]? | select(.label=="stage3_tier_groups") | .details.resolved_alias][0] // empty' "$OUT")

        if [[ "$has_stage3" != "true" ]]; then
            _dump_failure 5 "$seed" "expected stage3_tier_groups in resolution_path"
            return 1
        fi
        if [[ "$resolved_alias" != "$expected_alias" ]]; then
            _dump_failure 5 "$seed" "expected stage3.details.resolved_alias=$expected_alias got=$resolved_alias"
            return 1
        fi
        if [[ "$resolved_model_id" != "$expected_model_id" ]]; then
            _dump_failure 5 "$seed" "expected resolved_model_id=$expected_model_id got=$resolved_model_id"
            return 1
        fi
    done
}

# ---------------------------------------------------------------------
# Invariant 6 — unmapped tier ⇒ TIER-NO-MAPPING; never falls through to S5
# ---------------------------------------------------------------------
@test "I6: unmapped tier produces [TIER-NO-MAPPING]; never silently falls through to S5" {
    local i seed skill role expected_code expected_stage
    local actual_code actual_stage has_stage5 has_resolution_path
    for ((i=0; i<ITER; i++)); do
        seed=$((BASE + i))
        prop_gen_inv6_config "$seed" > "$CFG" || {
            _dump_failure 6 "$seed" "generator failed"
            return 1
        }
        _read_query skill role
        expected_code=$(yq '._property_query.expected_error_code' "$CFG")
        expected_stage=$(yq '._property_query.expected_stage_failed' "$CFG")
        _run_resolver "$skill" "$role" || { _dump_failure 6 "$seed" "resolver crashed"; return 1; }

        actual_code=$(jq -r '.error.code // empty' "$OUT")
        actual_stage=$(jq -r '.error.stage_failed // empty' "$OUT")
        has_resolution_path=$(jq -r 'has("resolution_path")' "$OUT")
        has_stage5=$(jq -r '[.resolution_path[]?.label // empty] | any(. == "stage5_framework_default")' "$OUT")

        if [[ "$actual_code" != "$expected_code" ]]; then
            _dump_failure 6 "$seed" "expected error.code=$expected_code got=$actual_code"
            return 1
        fi
        if [[ "$actual_stage" != "$expected_stage" ]]; then
            _dump_failure 6 "$seed" "expected error.stage_failed=$expected_stage got=$actual_stage"
            return 1
        fi
        if [[ "$has_resolution_path" != "false" ]]; then
            _dump_failure 6 "$seed" "resolution_path present alongside error (silent fall-through suspected)"
            return 1
        fi
        if [[ "$has_stage5" != "false" ]]; then
            _dump_failure 6 "$seed" "stage5_framework_default present — silent S5 fall-through detected"
            return 1
        fi
    done
}
