#!/usr/bin/env bats
# =============================================================================
# tests/property/model-resolution-properties.bats
#
# cycle-099 Sprint 2D.d (T2.6 closure) — SC-14 property suite.
#
# Verifies the six FR-3.9 invariants on ~100 random valid configs per
# invariant per CI run; nightly stress runs at ~1000 iterations.
#
# Six invariants (per FR-3.9 v1.2 SC-14) plus one positive S5 control:
#   I1. (S1) and (S4) both present → (S1) wins.
#   I2. Two same-priority pre-validation mechanisms always produce error
#       (extra+override id collision → [MODEL-EXTRA-OVERRIDE-CONFLICT];
#       override-targets-unknown-id → [OVERRIDE-UNKNOWN-MODEL]).
#   I3. prefer_pro overlay invariants:
#         * prefer_pro=false ⟹ no S6 entry in resolution_path
#         * prefer_pro=true  ⟹ exactly one S6 entry, and it is LAST
#       Multi-flavour generator covers all 5 S6-emission paths
#       (post-S1, post-S2, post-S3, post-S4 (with/without respect),
#       post-S5) plus applied/skipped variants.
#   I4. Per-entry biconditional: deprecation warning ⟺ stage4 entry.
#       Multi-flavour generator covers legacy-resolvable / modern-only /
#       legacy-unresolvable-falls-to-S5.
#   I5. Operator-set tier_groups mapping resolves before framework default
#       when both define the same (tier, provider) mapping.
#       Multi-flavour generator covers single-provider and multi-provider
#       (verifies `provider=sorted(operator_keys)[0]`, not framework's).
#   I6. Unmapped tier produces [TIER-NO-MAPPING] (stage_failed=3); never
#       silently falls through to S5.
#   I7. (positive S5 control) framework_defaults `agents.<skill>` resolves
#       cleanly via S5 when no operator overrides are set. Multi-flavour
#       covers `agents.<skill>.model` direct and `agents.<skill>.default_tier`
#       cascade. Catches a regression where S5 always returns None — a
#       failure mode that the negative-only I6 cannot detect.
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
    # Cypherpunk MED-5: in CI (`$CI` is set by GitHub Actions), tool
    # absence is a hard failure, not a skip. Skipping in CI silently
    # turns red checks green.
    _tool_check() {
        local tool="$1"
        if ! command -v "$tool" >/dev/null 2>&1; then
            if [[ -n "${CI:-}" ]]; then
                printf '[property-bats] FATAL: %s not present in CI\n' "$tool" >&2
                return 1
            else
                skip "$tool not present"
            fi
        fi
    }
    _tool_check jq
    _tool_check yq
    _tool_check python3
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
# Cypherpunk HIGH-7: control bytes in any stream are stripped before
# emission to CI logs. Even though hardcoded pools today contain none,
# resolver stderr may carry attacker-controlled bytes from a future
# diagnostic-leak path; pre-emptive strip prevents terminal-control-
# sequence injection into CI runner stdout.
_dump_failure() {
    local invariant="$1" seed="$2" detail="$3"
    {
        printf '\n========== property-fail invariant=%s seed=%s ==========\n' "$invariant" "$seed"
        printf '%s\n' "$detail"
        printf '----- config -----\n'
        if [[ -s "$CFG" ]]; then
            tr -d '\000-\010\013-\037' < "$CFG"
        else
            printf '[empty]\n'
        fi
        printf '\n----- resolver output -----\n'
        if [[ -s "$OUT" ]]; then
            tr -d '\000-\010\013-\037' < "$OUT"
        else
            printf '[empty]\n'
        fi
        printf '\n----- resolver stderr -----\n'
        if [[ -s "$WORK_DIR/stderr.log" ]]; then
            tr -d '\000-\010\013-\037' < "$WORK_DIR/stderr.log"
        else
            printf '[empty]\n'
        fi
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
@test "I2: same-priority pre-validation mechanisms always produce error (extra/override collision OR override-unknown-id)" {
    local i seed skill role flavour expected_code expected_stage
    local actual_code actual_stage has_resolution_path
    for ((i=0; i<ITER; i++)); do
        seed=$((BASE + i))
        prop_gen_inv2_config "$seed" > "$CFG" || {
            _dump_failure 2 "$seed" "generator failed"
            return 1
        }
        _read_query skill role
        flavour=$(yq '._property_query.flavour' "$CFG")
        expected_code=$(yq '._property_query.expected_error_code' "$CFG")
        expected_stage=$(yq '._property_query.expected_stage_failed' "$CFG")
        _run_resolver "$skill" "$role" || { _dump_failure 2 "$seed" "resolver crashed (flavour=$flavour)"; return 1; }

        actual_code=$(jq -r '.error.code // empty' "$OUT")
        actual_stage=$(jq -r '.error.stage_failed // empty' "$OUT")
        has_resolution_path=$(jq -r 'has("resolution_path")' "$OUT")

        if [[ "$actual_code" != "$expected_code" ]]; then
            _dump_failure 2 "$seed" "flavour=$flavour expected error.code=$expected_code got=$actual_code"
            return 1
        fi
        if [[ "$actual_stage" != "$expected_stage" ]]; then
            _dump_failure 2 "$seed" "flavour=$flavour expected error.stage_failed=$expected_stage got=$actual_stage"
            return 1
        fi
        if [[ "$has_resolution_path" != "false" ]]; then
            _dump_failure 2 "$seed" "flavour=$flavour resolution_path unexpectedly present alongside error"
            return 1
        fi
    done
}

# ---------------------------------------------------------------------
# Invariant 3 — prefer_pro overlay (S6) ordering exactness
# ---------------------------------------------------------------------
@test "I3: prefer_pro=false ⟹ no S6 entry; prefer_pro=true ⟹ exactly one S6 entry, and it is LAST" {
    local i seed skill role flavour prefer_pro expected_count expected_outcome expected_reason expected_alias_pro
    local stage6_count last_stage last_label last_outcome last_reason last_to path_len last_idx
    for ((i=0; i<ITER; i++)); do
        seed=$((BASE + i))
        prop_gen_inv3_config "$seed" > "$CFG" || {
            _dump_failure 3 "$seed" "generator failed"
            return 1
        }
        _read_query skill role
        flavour=$(yq '._property_query.flavour' "$CFG")
        prefer_pro=$(yq '._property_query.prefer_pro' "$CFG")
        expected_count=$(yq '._property_query.expect_stage6_count' "$CFG")
        expected_outcome=$(yq '._property_query.expect_stage6_outcome // ""' "$CFG")
        expected_reason=$(yq '._property_query.expect_stage6_reason // ""' "$CFG")
        expected_alias_pro=$(yq '._property_query.expect_alias_pro // ""' "$CFG")
        _run_resolver "$skill" "$role" || { _dump_failure 3 "$seed" "resolver crashed (flavour=$flavour)"; return 1; }

        # Count of stage 6 entries (must be 0 or 1).
        stage6_count=$(jq -r '[.resolution_path[]?.stage // empty] | map(select(. == 6)) | length' "$OUT")
        if [[ "$stage6_count" != "$expected_count" ]]; then
            _dump_failure 3 "$seed" "flavour=$flavour expected stage6_count=$expected_count got=$stage6_count"
            return 1
        fi

        path_len=$(jq -r '.resolution_path | length' "$OUT")
        if [[ -z "$path_len" ]] || [[ "$path_len" == "null" ]] || [[ "$path_len" == "0" ]]; then
            _dump_failure 3 "$seed" "flavour=$flavour expected non-empty resolution_path"
            return 1
        fi
        last_idx=$((path_len - 1))

        if [[ "$prefer_pro" == "false" ]]; then
            # No S6 entry should appear anywhere; this is the negative
            # control. Path resolves via S2 direct alias.
            last_stage=$(jq -r ".resolution_path[$last_idx].stage" "$OUT")
            if [[ "$last_stage" == "6" ]]; then
                _dump_failure 3 "$seed" "flavour=$flavour prefer_pro=false but stage6 present at last"
                return 1
            fi
        else
            # prefer_pro=true: stage 6 MUST be the last entry, AND no
            # stage 6 may appear at any non-last index.
            last_stage=$(jq -r ".resolution_path[$last_idx].stage" "$OUT")
            last_label=$(jq -r ".resolution_path[$last_idx].label" "$OUT")
            last_outcome=$(jq -r ".resolution_path[$last_idx].outcome" "$OUT")
            last_reason=$(jq -r ".resolution_path[$last_idx].details.reason // empty" "$OUT")
            last_to=$(jq -r ".resolution_path[$last_idx].details.to // empty" "$OUT")
            if [[ "$last_stage" != "6" ]]; then
                _dump_failure 3 "$seed" "flavour=$flavour expected last stage=6 got=$last_stage"
                return 1
            fi
            if [[ "$last_label" != "stage6_prefer_pro_overlay" ]]; then
                _dump_failure 3 "$seed" "flavour=$flavour expected last label=stage6_prefer_pro_overlay got=$last_label"
                return 1
            fi
            # Per-flavour outcome assertion.
            if [[ -n "$expected_outcome" ]] && [[ "$last_outcome" != "$expected_outcome" ]]; then
                _dump_failure 3 "$seed" "flavour=$flavour expected last outcome=$expected_outcome got=$last_outcome"
                return 1
            fi
            # When `applied`, verify the retargeted alias name; when
            # `skipped`, verify the skip reason.
            if [[ "$last_outcome" == "applied" ]] && [[ -n "$expected_alias_pro" ]]; then
                if [[ "$last_to" != "$expected_alias_pro" ]]; then
                    _dump_failure 3 "$seed" "flavour=$flavour expected stage6.details.to=$expected_alias_pro got=$last_to"
                    return 1
                fi
            fi
            if [[ "$last_outcome" == "skipped" ]] && [[ -n "$expected_reason" ]]; then
                if [[ "$last_reason" != "$expected_reason" ]]; then
                    _dump_failure 3 "$seed" "flavour=$flavour expected stage6.details.reason=$expected_reason got=$last_reason"
                    return 1
                fi
            fi
            # Defense-in-depth: also verify that no stage 6 entry exists
            # at any non-last index. The stage6_count==1 above is a
            # sufficient check (stage6_count==1 + last==6 ⟹ no stage 6
            # at non-last index), but we surface a clearer error if the
            # invariant is violated.
            local stage6_at_non_last
            stage6_at_non_last=$(jq -r --argjson last "$last_idx" \
                '[.resolution_path | to_entries[] | select(.value.stage == 6 and .key != $last)] | length' "$OUT")
            if [[ "$stage6_at_non_last" != "0" ]]; then
                _dump_failure 3 "$seed" "flavour=$flavour stage 6 entry at non-last index ($stage6_at_non_last entries)"
                return 1
            fi
        fi
    done
}

# ---------------------------------------------------------------------
# Invariant 4 — deprecation warning emitted ⟺ stage 4 entry (per-entry)
# ---------------------------------------------------------------------
@test "I4: deprecation warning ⟺ stage 4 entry — per-entry biconditional" {
    local i seed skill role flavour expect_warning expect_stage4
    local has_stage4 has_warning warning_only_on_stage4 stage4_always_has_warning
    for ((i=0; i<ITER; i++)); do
        seed=$((BASE + i))
        prop_gen_inv4_config "$seed" > "$CFG" || {
            _dump_failure 4 "$seed" "generator failed"
            return 1
        }
        _read_query skill role
        flavour=$(yq '._property_query.flavour' "$CFG")
        expect_warning=$(yq '._property_query.expect_warning' "$CFG")
        expect_stage4=$(yq '._property_query.expect_stage4' "$CFG")
        _run_resolver "$skill" "$role" || { _dump_failure 4 "$seed" "resolver crashed (flavour=$flavour)"; return 1; }

        has_stage4=$(jq -r '[.resolution_path[]?.label // empty] | any(. == "stage4_legacy_shape")' "$OUT")
        has_warning=$(jq -r '[.resolution_path[]?.details.warning // empty] | any(. == "[LEGACY-SHAPE-DEPRECATED]")' "$OUT")

        # Flavour-specific positive controls.
        if [[ "$has_stage4" != "$expect_stage4" ]]; then
            _dump_failure 4 "$seed" "flavour=$flavour expected has_stage4=$expect_stage4 got=$has_stage4"
            return 1
        fi
        if [[ "$has_warning" != "$expect_warning" ]]; then
            _dump_failure 4 "$seed" "flavour=$flavour expected has_warning=$expect_warning got=$has_warning"
            return 1
        fi

        # GP HIGH-2 strengthen: per-entry biconditional. The warning
        # MUST appear ONLY on stage4 entries, AND every stage4 entry
        # MUST carry the warning. Catches a bug where the warning is
        # emitted on (e.g.) stage5 via copy-paste — the per-resolution
        # check would not detect that if stage4 is also present.
        warning_only_on_stage4=$(jq -r '
            [.resolution_path[]?
             | select(.details.warning == "[LEGACY-SHAPE-DEPRECATED]")
             | .label]
            | all(. == "stage4_legacy_shape")
        ' "$OUT")
        if [[ "$warning_only_on_stage4" != "true" ]]; then
            _dump_failure 4 "$seed" "flavour=$flavour deprecation warning found on a non-stage4 entry"
            return 1
        fi
        stage4_always_has_warning=$(jq -r '
            [.resolution_path[]?
             | select(.label == "stage4_legacy_shape")
             | .details.warning // ""]
            | all(. == "[LEGACY-SHAPE-DEPRECATED]")
        ' "$OUT")
        if [[ "$stage4_always_has_warning" != "true" ]]; then
            _dump_failure 4 "$seed" "flavour=$flavour stage4 entry without [LEGACY-SHAPE-DEPRECATED] warning"
            return 1
        fi
    done
}

# ---------------------------------------------------------------------
# Invariant 5 — operator tier_groups precedence over framework default
# ---------------------------------------------------------------------
@test "I5: operator tier_groups.mappings resolves before framework default" {
    local i seed skill role flavour expected_alias expected_model_id expected_provider
    local resolved_provider resolved_model_id resolved_alias has_stage3 has_stage5
    for ((i=0; i<ITER; i++)); do
        seed=$((BASE + i))
        prop_gen_inv5_config "$seed" > "$CFG" || {
            _dump_failure 5 "$seed" "generator failed"
            return 1
        }
        _read_query skill role
        flavour=$(yq '._property_query.flavour' "$CFG")
        expected_alias=$(yq '._property_query.expected_resolved_alias' "$CFG")
        expected_model_id=$(yq '._property_query.expected_resolved_model_id' "$CFG")
        # multi_provider flavour additionally pins expected_resolved_provider
        # to verify provider=sorted(operator_keys)[0], not framework's keys.
        expected_provider=$(yq '._property_query.expected_resolved_provider // ""' "$CFG")
        _run_resolver "$skill" "$role" || { _dump_failure 5 "$seed" "resolver crashed (flavour=$flavour)"; return 1; }

        resolved_provider=$(jq -r '.resolved_provider // empty' "$OUT")
        resolved_model_id=$(jq -r '.resolved_model_id // empty' "$OUT")
        has_stage3=$(jq -r '[.resolution_path[]?.label // empty] | any(. == "stage3_tier_groups")' "$OUT")
        has_stage5=$(jq -r '[.resolution_path[]?.label // empty] | any(. == "stage5_framework_default")' "$OUT")
        resolved_alias=$(jq -r '[.resolution_path[]? | select(.label=="stage3_tier_groups") | .details.resolved_alias][0] // empty' "$OUT")

        if [[ "$has_stage3" != "true" ]]; then
            _dump_failure 5 "$seed" "flavour=$flavour expected stage3_tier_groups in resolution_path"
            return 1
        fi
        # Cypherpunk HIGH-3: assert S5 is NOT in resolution_path. A
        # resolver bug that resolved at S3 correctly but ALSO emitted
        # S5 (e.g., a mis-merged early-return) would otherwise pass.
        if [[ "$has_stage5" == "true" ]]; then
            _dump_failure 5 "$seed" "flavour=$flavour stage5_framework_default unexpectedly present alongside stage3"
            return 1
        fi
        if [[ "$resolved_alias" != "$expected_alias" ]]; then
            _dump_failure 5 "$seed" "flavour=$flavour expected stage3.details.resolved_alias=$expected_alias got=$resolved_alias"
            return 1
        fi
        if [[ "$resolved_model_id" != "$expected_model_id" ]]; then
            _dump_failure 5 "$seed" "flavour=$flavour expected resolved_model_id=$expected_model_id got=$resolved_model_id"
            return 1
        fi
        if [[ -n "$expected_provider" ]] && [[ "$resolved_provider" != "$expected_provider" ]]; then
            _dump_failure 5 "$seed" "flavour=$flavour expected resolved_provider=$expected_provider got=$resolved_provider"
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

# ---------------------------------------------------------------------
# Invariant 7 — positive S5 control (cypherpunk HIGH-3 / GP MED-1)
# ---------------------------------------------------------------------
@test "I7: framework_defaults agents.<skill> resolves cleanly via S5 — positive S5 control" {
    local i seed skill role flavour expected_provider expected_model_id
    local resolved_provider resolved_model_id has_stage5 has_error
    for ((i=0; i<ITER; i++)); do
        seed=$((BASE + i))
        prop_gen_inv7_config "$seed" > "$CFG" || {
            _dump_failure 7 "$seed" "generator failed"
            return 1
        }
        _read_query skill role
        flavour=$(yq '._property_query.flavour' "$CFG")
        expected_provider=$(yq '._property_query.expected_resolved_provider' "$CFG")
        expected_model_id=$(yq '._property_query.expected_resolved_model_id' "$CFG")
        _run_resolver "$skill" "$role" || { _dump_failure 7 "$seed" "resolver crashed (flavour=$flavour)"; return 1; }

        has_error=$(jq -r 'has("error")' "$OUT")
        if [[ "$has_error" == "true" ]]; then
            _dump_failure 7 "$seed" "flavour=$flavour S5 positive control returned error"
            return 1
        fi
        has_stage5=$(jq -r '[.resolution_path[]?.label // empty] | any(. == "stage5_framework_default")' "$OUT")
        resolved_provider=$(jq -r '.resolved_provider // empty' "$OUT")
        resolved_model_id=$(jq -r '.resolved_model_id // empty' "$OUT")
        if [[ "$has_stage5" != "true" ]]; then
            _dump_failure 7 "$seed" "flavour=$flavour expected stage5 hit; got resolution_path missing it"
            return 1
        fi
        if [[ "$resolved_provider" != "$expected_provider" ]]; then
            _dump_failure 7 "$seed" "flavour=$flavour expected resolved_provider=$expected_provider got=$resolved_provider"
            return 1
        fi
        if [[ "$resolved_model_id" != "$expected_model_id" ]]; then
            _dump_failure 7 "$seed" "flavour=$flavour expected resolved_model_id=$expected_model_id got=$resolved_model_id"
            return 1
        fi
    done
}
