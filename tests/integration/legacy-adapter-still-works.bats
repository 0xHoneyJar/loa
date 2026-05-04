#!/usr/bin/env bats
# =============================================================================
# legacy-adapter-still-works.bats — cycle-099 sprint-1B (T1.10 partial)
# =============================================================================
# Sentinel that nothing in the cycle-098 / cycle-097 / cycle-095 Flatline +
# Red Team + Bridgebuilder behavior regressed under sprint-1B's adapter
# migrations (T1.3, T1.4, T1.8). Each test pins ONE pre-cycle-099 invariant
# that the migration must preserve.
#
# Sprint plan: grimoires/loa/cycles/cycle-099-model-registry/sprint.md §1
# AC: AC-S1.6 (legacy-adapter-still-works.bats PASSES on green main; FAILS
# under any sprint-1B change that would break a downstream caller)

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export RT_ADAPTER="$PROJECT_ROOT/.claude/scripts/red-team-model-adapter.sh"
    export RT_CVDS="$PROJECT_ROOT/.claude/scripts/red-team-code-vs-design.sh"
    export DEFAULT_ADAPTER="$PROJECT_ROOT/.claude/scripts/model-adapter.sh"
    export RESOLVER_LIB="$PROJECT_ROOT/.claude/scripts/lib/model-resolver.sh"
    export GENERATED_MAPS="$PROJECT_ROOT/.claude/scripts/generated-model-maps.sh"
}

# ---------------------------------------------------------------------------
# S1: file inventory — every migrated script exists and is bash-syntactically valid
# ---------------------------------------------------------------------------

@test "S1: red-team-model-adapter.sh exists and parses (bash -n)" {
    [ -f "$RT_ADAPTER" ]
    bash -n "$RT_ADAPTER"
}

@test "S1: red-team-code-vs-design.sh exists and parses (bash -n)" {
    [ -f "$RT_CVDS" ]
    bash -n "$RT_CVDS"
}

@test "S1: model-adapter.sh exists and parses (bash -n)" {
    [ -f "$DEFAULT_ADAPTER" ]
    bash -n "$DEFAULT_ADAPTER"
}

@test "S1: model-resolver.sh exists and parses (bash -n)" {
    [ -f "$RESOLVER_LIB" ]
    bash -n "$RESOLVER_LIB"
}

@test "S1: generated-model-maps.sh exists and parses (bash -n)" {
    [ -f "$GENERATED_MAPS" ]
    bash -n "$GENERATED_MAPS"
}

# ---------------------------------------------------------------------------
# S2: resolver lib contract — resolve_alias / resolve_provider_id work
# ---------------------------------------------------------------------------

@test "S2: resolver populates MODEL_PROVIDERS / MODEL_IDS after sourcing" {
    set +u
    # shellcheck disable=SC1090
    source "$RESOLVER_LIB"
    [ "${#MODEL_PROVIDERS[@]}" -gt 10 ]
    [ "${#MODEL_IDS[@]}" -gt 10 ]
}

@test "S2: resolve_alias opus → claude-opus-4-7" {
    set +u
    # shellcheck disable=SC1090
    source "$RESOLVER_LIB"
    local result
    result="$(resolve_alias opus)"
    [ "$result" = "claude-opus-4-7" ]
}

@test "S2: resolve_alias claude-opus-4.6 → claude-opus-4-7 (cycle-082 retarget)" {
    set +u
    # shellcheck disable=SC1090
    source "$RESOLVER_LIB"
    local result
    result="$(resolve_alias claude-opus-4.6)"
    [ "$result" = "claude-opus-4-7" ]
}

@test "S2: resolve_provider_id opus → anthropic:claude-opus-4-7" {
    set +u
    # shellcheck disable=SC1090
    source "$RESOLVER_LIB"
    local result
    result="$(resolve_provider_id opus)"
    [ "$result" = "anthropic:claude-opus-4-7" ]
}

@test "S2: resolve_provider_id reviewer → openai:gpt-5.5" {
    set +u
    # shellcheck disable=SC1090
    source "$RESOLVER_LIB"
    local result
    result="$(resolve_provider_id reviewer)"
    [ "$result" = "openai:gpt-5.5" ]
}

@test "S2: resolve_alias bogus → exit 1 + stderr error" {
    set +u
    # shellcheck disable=SC1090
    source "$RESOLVER_LIB"
    run resolve_alias bogus-nonexistent-model
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown alias"* ]]
}

@test "S2: resolve_alias '' → exit 1 + 'missing alias argument'" {
    # Empty-arg path — verified at the call site under set -euo pipefail
    # because rt-cvds invokes via $(resolve_alias ...) || error+exit.
    set +u
    # shellcheck disable=SC1090
    source "$RESOLVER_LIB"
    run resolve_alias ""
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing alias argument"* ]]
}

@test "S2: resolve_alias via \$() in strict-mode subshell handles failure cleanly" {
    # Pin the rt-cvds invocation pattern: `$(resolve_alias opus)` || error.
    # Under set -euo pipefail with command substitution, return 1 from the
    # function must propagate so the `||` branch fires (NOT silently capture
    # empty stdout while $? gets reset).
    set +u
    # shellcheck disable=SC1090
    source "$RESOLVER_LIB"

    local result rc
    set -euo pipefail
    if result="$(resolve_alias bogus-alias-that-does-not-exist 2>/dev/null)"; then
        rc=0
    else
        rc=$?
    fi
    set +eo pipefail
    [ "$rc" -eq 1 ]
    [ -z "$result" ]
}

# ---------------------------------------------------------------------------
# S2b: resolver-wins-over-local for shared keys (review M4 + audit M4)
# ---------------------------------------------------------------------------
# Pre-migration the local MODEL_TO_PROVIDER_ID was always consulted. Post-
# migration the resolver path runs first, with the local map as fallback.
# For aliases present in BOTH (e.g., `opus`, `gpt-5.5`), the resolver MUST
# win. This test pins that contract — without it, a future yaml retarget
# that disagrees with a stale local map entry would silently route to the
# stale value.
@test "S2b: shared-key 'opus' resolves via the lib (resolver path, not local fallback)" {
    set +u
    # Reset state, source the script which declares both MODEL_TO_PROVIDER_ID
    # AND brings in MODEL_IDS from the resolver lib.
    # shellcheck disable=SC1090
    source "$RT_ADAPTER"

    # Both sources have a value for 'opus'. They MUST agree (G-7 invariant
    # already enforces this via model-registry-sync.bats), but verify here
    # directly that the resolver path is the operative one.
    [[ -n "${MODEL_IDS[opus]:-}" ]]
    [[ -n "${MODEL_TO_PROVIDER_ID[opus]:-}" ]]

    local resolver_value local_value
    resolver_value="$(resolve_provider_id opus)"
    local_value="${MODEL_TO_PROVIDER_ID[opus]}"

    # Today these are byte-equal (anthropic:claude-opus-4-7). If they ever
    # diverge, this test FAILS — surfacing the drift instead of letting
    # the migration silently route through the stale local entry.
    [ "$resolver_value" = "$local_value" ]
    [ "$resolver_value" = "anthropic:claude-opus-4-7" ]
}

# ---------------------------------------------------------------------------
# S2c: override gate (audit M1)
# ---------------------------------------------------------------------------
# The LOA_MODEL_RESOLVER_GENERATED_MAPS_OVERRIDE env var sources arbitrary
# bash. It MUST be gated behind LOA_MODEL_RESOLVER_TEST_MODE=1 (or running
# under bats) to prevent ambient env from redirecting model lookups.
@test "S2c: override IGNORED when LOA_MODEL_RESOLVER_TEST_MODE unset and not under bats" {
    # Stage a malicious-looking override file. Two attack paths the gate
    # MUST block:
    #   1. Bash syntax must be VALID — a syntax error would let the
    #      negative assertion pass vacuously (BB iter-1 F1: the previous
    #      version had `])` extra bracket and the [ATTACKER] echo never
    #      reached parse-time anyway).
    #   2. The payload must produce an OBSERVABLE side-effect — a positive
    #      control. A marker file written by the payload proves the payload
    #      WOULD have fired if the gate were absent (BB iter-1 F1 fix).
    local fake_maps="$BATS_TEST_TMPDIR/fake-maps.sh"
    local sentinel="$BATS_TEST_TMPDIR/attacker-sentinel"
    cat > "$fake_maps" <<EOF
declare -A MODEL_PROVIDERS=(["opus"]="attacker")
declare -A MODEL_IDS=(["opus"]="evil")
# Positive control: write a sentinel file. If the gate is absent and the
# override sources this file, the sentinel exists post-source and the test
# fails loudly. Today the gate IS present, so the sentinel must NOT exist.
echo "fired-at-\$(date -u +%s)" > "$sentinel"
echo "[ATTACKER] arbitrary code executed" >&2
EOF
    # Verify our fixture parses (defense-in-depth against future edits that
    # break syntax and re-introduce the vacuous-pass risk).
    bash -n "$fake_maps"

    # Source in a clean subshell with the override env set BUT no test-mode
    # flag and BATS_TEST_DIRNAME explicitly unset. The gate must drop the
    # override and source the real generated-model-maps.sh instead.
    local output rc=0
    output="$(env -u BATS_TEST_DIRNAME -u LOA_MODEL_RESOLVER_TEST_MODE \
        LOA_MODEL_RESOLVER_GENERATED_MAPS_OVERRIDE="$fake_maps" \
        bash -c 'source "$1"; echo "opus → ${MODEL_IDS[opus]:-MISSING}"' \
        _ "$RESOLVER_LIB" 2>&1)" || rc=$?

    # The gate should write a WARNING to stderr and ignore the override.
    [[ "$output" == *"WARNING"* ]]
    [[ "$output" == *"override IGNORED"* ]]
    # Real maps loaded — opus resolves to claude-opus-4-7, not "evil".
    [[ "$output" == *"opus → claude-opus-4-7"* ]]
    # Attacker echo MUST NOT have run.
    [[ "$output" != *"[ATTACKER]"* ]]
    # POSITIVE CONTROL: sentinel file MUST NOT exist. If a future regression
    # accepts the override, the sentinel will be present and this test will
    # FAIL with a clear signal (instead of passing vacuously).
    [ ! -f "$sentinel" ]
}

@test "S2c: override HONORED when running under bats (BATS_TEST_DIRNAME is set)" {
    # We ARE running under bats — BATS_TEST_DIRNAME is set by the harness.
    # An override should be honored without setting LOA_MODEL_RESOLVER_TEST_MODE.
    [ -n "$BATS_TEST_DIRNAME" ]

    local fake_maps="$BATS_TEST_TMPDIR/test-maps.sh"
    cat > "$fake_maps" <<'EOF'
declare -A MODEL_PROVIDERS=(["test-alias"]="testprov")
declare -A MODEL_IDS=(["test-alias"]="test-canonical-id")
EOF

    set +u
    # Pass BATS_TEST_DIRNAME as env to the inner shell so the gate condition
    # `[[ -n "${BATS_TEST_DIRNAME:-}" ]]` evaluates true. Without exporting,
    # bats variables don't survive into bash -c subshells.
    BATS_TEST_DIRNAME="$BATS_TEST_DIRNAME" \
    LOA_MODEL_RESOLVER_GENERATED_MAPS_OVERRIDE="$fake_maps" \
    RESOLVER_LIB="$RESOLVER_LIB" \
        bash -c 'export BATS_TEST_DIRNAME LOA_MODEL_RESOLVER_GENERATED_MAPS_OVERRIDE
                 source "$1"
                 echo "${MODEL_IDS[test-alias]:-FAIL}"' \
        _ "$RESOLVER_LIB" > "$BATS_TEST_TMPDIR/sub-output" 2>&1

    grep -q "test-canonical-id" "$BATS_TEST_TMPDIR/sub-output"
}

# ---------------------------------------------------------------------------
# S3: red-team-model-adapter.sh post-migration contract
# ---------------------------------------------------------------------------
#
# The G-7 invariant test in tests/integration/model-registry-sync.bats sources
# this script and reads MODEL_TO_PROVIDER_ID; that contract MUST survive the
# sprint-1B migration. These tests pin the contract from a different angle.

@test "S3: sourcing red-team-model-adapter.sh declares MODEL_TO_PROVIDER_ID" {
    set +u
    # shellcheck disable=SC1090
    source "$RT_ADAPTER"
    [[ -n "$(declare -p MODEL_TO_PROVIDER_ID 2>/dev/null)" ]]
    [ "${#MODEL_TO_PROVIDER_ID[@]}" -gt 5 ]
}

@test "S3: red-team-model-adapter.sh keeps red-team-only short aliases (gpt, kimi, qwen)" {
    set +u
    # shellcheck disable=SC1090
    source "$RT_ADAPTER"
    # These short aliases are intentionally NOT in yaml — must remain in
    # the local fallback map per G-7 invariant.
    [[ -n "${MODEL_TO_PROVIDER_ID[gpt]:-}" ]]
    [[ -n "${MODEL_TO_PROVIDER_ID[kimi]:-}" ]]
    [[ -n "${MODEL_TO_PROVIDER_ID[qwen]:-}" ]]
}

@test "S3: red-team-model-adapter.sh exposes resolve_provider_id (sourced from lib)" {
    set +u
    # shellcheck disable=SC1090
    source "$RT_ADAPTER"
    declare -F resolve_provider_id >/dev/null
}

# ---------------------------------------------------------------------------
# S4: red-team-code-vs-design.sh — alias-resolution at invocation site (T1.4)
# ---------------------------------------------------------------------------

@test "S4: red-team-code-vs-design.sh sources model-resolver.sh before main" {
    # Pin the migration without running main (review M2 — original regex was
    # fragile; sourcing the script triggers `main "$@"` which crashes on the
    # bats positional args). Two-prong assertion: (1) a source line referencing
    # model-resolver.sh exists, (2) it appears before main()'s definition.
    # Tolerant of relative-path / quote-style variations.
    local src_line main_line
    src_line=$(grep -n 'source.*model-resolver\.sh' "$RT_CVDS" | head -1 | cut -d: -f1)
    [ -n "$src_line" ]
    main_line=$(grep -n '^main()' "$RT_CVDS" | head -1 | cut -d: -f1)
    [ -n "$main_line" ]
    [ "$src_line" -lt "$main_line" ]
}

@test "S4: red-team-code-vs-design.sh no longer hardcodes --model opus literal" {
    # Pin the migration: the literal `--model opus` line must be gone.
    # If someone reverts T1.4, this test catches it. Allows --model FOO
    # where FOO is a variable expansion (`$_opus_model_id`).
    if grep -E '^[[:space:]]+--model opus[[:space:]]*\\?[[:space:]]*$' "$RT_CVDS"; then
        echo "FAIL: --model opus literal found — T1.4 migration regressed"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# S5: default model-adapter.sh post-migration contract
# ---------------------------------------------------------------------------

@test "S5: model-adapter.sh greppable for cycle-082 backward-compat keys (T8 contract)" {
    # Pre-cycle-099 test (tests/unit/model-adapter-aliases.bats:T8) greps
    # the file directly for these keys. Migration must preserve them.
    for key in "claude-opus-4-7" "claude-opus-4.7" "claude-opus-4-5" "claude-opus-4.1" "claude-opus-4-1" "claude-opus-4.0" "claude-opus-4-0"; do
        grep -q "\"$key\"" "$DEFAULT_ADAPTER" || {
            echo "FAIL: missing cycle-082 key '$key' in $DEFAULT_ADAPTER (T8 contract)"
            return 1
        }
    done
}

@test "S5: model-adapter.sh sources model-resolver.sh before main" {
    # Same approach as S4 (review M2): position-anchored without running main.
    local src_line main_line
    src_line=$(grep -n 'source.*model-resolver\.sh' "$DEFAULT_ADAPTER" | head -1 | cut -d: -f1)
    [ -n "$src_line" ]
    main_line=$(grep -n '^main()' "$DEFAULT_ADAPTER" | head -1 | cut -d: -f1)
    [ -n "$main_line" ]
    [ "$src_line" -lt "$main_line" ]
}

@test "S5: model-adapter.sh runs usage path without crashing on missing args" {
    # Pin: invoking the adapter with no args produces the usage block AND
    # exits with code 2 (Invalid input — the documented exit code in the
    # script's docstring header). Sprint-1B migration must not break the
    # entry path before --model parsing happens. A regression to a hard
    # crash (exit 1, segfault, set -u unbound) would surface here.
    run bash "$DEFAULT_ADAPTER"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"Model required"* ]]
}

# ---------------------------------------------------------------------------
# S6: lockfile + checksum invariants
# ---------------------------------------------------------------------------

@test "S6: model-config.yaml.checksum matches yaml SHA256" {
    local recorded computed
    recorded="$(cat "$PROJECT_ROOT/.claude/defaults/model-config.yaml.checksum" | tr -d '\n[:space:]')"
    computed="$(sha256sum < "$PROJECT_ROOT/.claude/defaults/model-config.yaml" | awk '{print $1}')"
    [ "$recorded" = "$computed" ]
}
