#!/usr/bin/env bats
# =============================================================================
# Sprint-4 T4.4 — model registry SSOT invariant (closes SDD §1.4 C4 SKP-002)
#
# Asserts that canonical model IDs and aliases agree across the four files
# that historically drifted during model migrations:
#
#   1. .claude/defaults/model-config.yaml         — single source of truth
#   2. .claude/scripts/generated-model-maps.sh    — derived by gen-adapter-maps.sh
#   3. .claude/scripts/flatline-orchestrator.sh   — sources generated maps
#   4. .claude/scripts/red-team-model-adapter.sh  — hand-maintained MODEL_TO_PROVIDER_ID
#
# A drift between #1 and #2 means the operator forgot to re-run
# `gen-adapter-maps.sh` after editing the YAML — caught by --check below.
# A drift in #3 or #4 means a hand-edit slipped past the generator — caught
# by the cross-file ID-presence assertions.
#
# This is a CHEAP CI gate (no network, no provider calls). It runs on every
# build alongside the existing tests, providing a belt-and-suspenders check
# that complements the live model-health-probe.yml workflow.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    CONFIG="$PROJECT_ROOT/.claude/defaults/model-config.yaml"
    GENERATED="$PROJECT_ROOT/.claude/scripts/generated-model-maps.sh"
    GENERATOR="$PROJECT_ROOT/.claude/scripts/gen-adapter-maps.sh"
    FLATLINE="$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
    REDTEAM="$PROJECT_ROOT/.claude/scripts/red-team-model-adapter.sh"
}

# -----------------------------------------------------------------------------
# Generator drift check
# -----------------------------------------------------------------------------
@test "generator: --check passes (YAML and generated-model-maps.sh in sync)" {
    run bash "$GENERATOR" --check
    [ "$status" -eq 0 ]
}

@test "generator: regenerated output is byte-identical to committed file" {
    local tmp; tmp="$(mktemp)"
    bash "$GENERATOR" --output "$tmp"
    diff -q "$tmp" "$GENERATED"
    rm -f "$tmp"
}

# -----------------------------------------------------------------------------
# YAML / generated-maps consistency
# -----------------------------------------------------------------------------
@test "yaml-generated: every provider/model in YAML appears in MODEL_PROVIDERS" {
    local yaml_models
    yaml_models="$(yq eval -o=json '.providers' "$CONFIG" \
        | jq -r 'to_entries[] as $p | $p.value.models | keys[]' | sort -u)"

    while IFS= read -r model; do
        [[ -z "$model" ]] && continue
        grep -qF "[\"$model\"]=" "$GENERATED" \
            || { echo "Missing in generated-model-maps.sh: $model"; return 1; }
    done <<< "$yaml_models"
}

@test "yaml-generated: every alias in YAML appears in MODEL_IDS" {
    local yaml_aliases
    yaml_aliases="$(yq eval -o=json '.aliases // {}' "$CONFIG" \
        | jq -r 'to_entries[]
                 | select((.value | split(":")[0]) != "claude-code")
                 | select(.value | test("^[^:]+:"))
                 | .key' | sort -u)"

    while IFS= read -r alias; do
        [[ -z "$alias" ]] && continue
        grep -qF "[\"$alias\"]=" "$GENERATED" \
            || { echo "Missing in generated-model-maps.sh: $alias"; return 1; }
    done <<< "$yaml_aliases"
}

# -----------------------------------------------------------------------------
# Flatline orchestrator sources the generated allowlist (Sprint-4 T4.2)
# -----------------------------------------------------------------------------
@test "flatline: sources generated-model-maps.sh (no hand-maintained allowlist)" {
    grep -qF 'source "$_GENERATED_MAPS"' "$FLATLINE"
}

@test "flatline: VALID_FLATLINE_MODELS defined in generated maps" {
    grep -qF 'declare -a VALID_FLATLINE_MODELS=' "$GENERATED"
}

@test "flatline: sourced VALID_FLATLINE_MODELS contains gemini-3.1-pro-preview" {
    # Sprint-4 T4.1 — gemini-3.1-pro-preview is re-added; allowlist must reflect.
    local out
    out="$(bash -c 'source "'"$GENERATED"'" && printf "%s\n" "${VALID_FLATLINE_MODELS[@]}"')"
    grep -qFx 'gemini-3.1-pro-preview' <<< "$out"
}

@test "flatline: sourced VALID_FLATLINE_MODELS contains gpt-5.5 (latent)" {
    local out
    out="$(bash -c 'source "'"$GENERATED"'" && printf "%s\n" "${VALID_FLATLINE_MODELS[@]}"')"
    grep -qFx 'gpt-5.5' <<< "$out"
}

# -----------------------------------------------------------------------------
# Red-team adapter — every value in MODEL_TO_PROVIDER_ID resolves to YAML
# -----------------------------------------------------------------------------
@test "red-team: every MODEL_TO_PROVIDER_ID value is a known provider:model-id" {
    # Extract values like "openai:gpt-5.3-codex" from the bash declaration.
    local values
    values="$(grep -oE '"[a-z]+:[a-zA-Z0-9._-]+"' "$REDTEAM" \
        | tr -d '"' | sort -u)"

    [[ -n "$values" ]] || { echo "no provider:model-id values in red-team adapter"; return 1; }

    while IFS= read -r pair; do
        local provider="${pair%%:*}"
        local model_id="${pair#*:}"
        # Skip non-canonical provider tags used by red-team only (kimi, qwen).
        case "$provider" in
            kimi|qwen) continue ;;
        esac

        # Either the model-id is a key under providers.<provider>.models
        # OR it's a backward-compat retarget (legacy alias points to current).
        local found
        found="$(yq eval ".providers[\"$provider\"].models | has(\"$model_id\")" "$CONFIG" 2>/dev/null)"
        [[ "$found" == "true" ]] \
            || { echo "red-team references $pair which is missing from model-config.yaml"; return 1; }
    done <<< "$values"
}

# -----------------------------------------------------------------------------
# G-7 (cycle-094 sprint-2): Cross-file key invariant. The hand-maintained
# MODEL_TO_PROVIDER_ID in red-team-model-adapter.sh is the FALLBACK seam from
# the SSOT plan: instead of refactoring the adapter to source generated maps
# (which would require adding red-team-only aliases like "gpt", "gemini",
# "kimi", "qwen" to model-config.yaml), we tighten the invariant test to
# catch provider-drift between the two files.
#
# Invariant: for every key K shared between MODEL_TO_PROVIDER_ID (red-team
# adapter) and MODEL_PROVIDERS (generated from YAML), the provider component
# of the red-team value MUST equal MODEL_PROVIDERS[K].
#
# Catches drift like: generator says `opus → anthropic`, adapter says
# `opus → openai:gpt-5.3-codex`. Pre-G-7 the values-only test would not
# catch a key mismatch — only that "openai:gpt-5.3-codex" is a real pair.
# -----------------------------------------------------------------------------
@test "red-team: shared keys agree on provider with generated MODEL_PROVIDERS (G-7)" {
    # Iter-1 BB F3/e43e (MEDIUM, vacuous-pass risk): the previous version of
    # this test re-parsed the bash associative array via `awk` + regex.
    # If the source formatting drifted (line-break shuffles, multi-pair lines,
    # quoting style) the parser would silently extract zero entries and the
    # test would pass without asserting anything — a drift detector that
    # silently fails to detect drift.
    #
    # Fix per Bridgebuilder F3 + e43e: bash is the only robust parser of bash
    # data. Source the red-team adapter in a clean subshell to populate
    # MODEL_TO_PROVIDER_ID natively, then iterate via "${!MODEL_TO_PROVIDER_ID[@]}".
    # Add a `compared > 0` guard at the end so a silent zero-iteration regression
    # surfaces as a real test failure rather than a passing-but-vacuous run.

    # shellcheck disable=SC1090
    source "$GENERATED"

    # The red-team adapter has a `case "$1" in --self-test) ...; ;; esac`
    # at the top of `main` and a `if [[ ... ]]; then main "$@"; fi` guard
    # at the bottom — sourcing without args runs only the declarations.
    # Stash and restore the pre-existing array (if any) to avoid leaking
    # state across tests.
    local -a saved_keys=()
    if declare -p MODEL_TO_PROVIDER_ID >/dev/null 2>&1; then
        saved_keys=("${!MODEL_TO_PROVIDER_ID[@]}")
    fi
    # shellcheck disable=SC1090
    source "$REDTEAM"

    [[ -n "$(declare -p MODEL_TO_PROVIDER_ID 2>/dev/null)" ]] || {
        echo "MODEL_TO_PROVIDER_ID not defined after sourcing $REDTEAM" >&2
        return 1
    }

    local -a mismatches=()
    local compared=0
    local key
    for key in "${!MODEL_TO_PROVIDER_ID[@]}"; do
        local value="${MODEL_TO_PROVIDER_ID[$key]}"
        local rt_provider="${value%%:*}"

        # Only validate keys that ALSO exist in the generated MODEL_PROVIDERS.
        # Red-team-only aliases (gpt, gemini, kimi, qwen) are intentionally
        # not in the generated map; skip them.
        if [[ -n "${MODEL_PROVIDERS[$key]+x}" ]]; then
            compared=$((compared + 1))
            local gen_provider="${MODEL_PROVIDERS[$key]}"
            if [[ "$rt_provider" != "$gen_provider" ]]; then
                mismatches+=("$key: red-team='$rt_provider' vs generated='$gen_provider'")
            fi
        fi
    done

    # Vacuous-pass guard (Bridgebuilder F3): if zero shared keys were compared,
    # the test asserts nothing. The red-team adapter currently has at least
    # 6 keys present in MODEL_PROVIDERS (gpt-5.2, gpt-5.3-codex, opus,
    # gemini-2.5-pro, claude-opus-4-7, claude-opus-4-6); a count below 4 is
    # almost certainly a parse/source regression worth surfacing.
    (( compared >= 4 )) || {
        echo "Vacuous-pass guard tripped: compared=$compared (expected >= 4 shared keys)" >&2
        echo "Likely cause: red-team adapter restructured, MODEL_TO_PROVIDER_ID renamed, OR" >&2
        echo "the generator dropped canonical aliases that the adapter still references." >&2
        return 1
    }

    if (( ${#mismatches[@]} > 0 )); then
        printf 'Provider drift between red-team adapter and generated map (compared=%d):\n' "$compared" >&2
        printf '  %s\n' "${mismatches[@]}" >&2
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Stable sort + dedupe ordering (deterministic invariant)
# -----------------------------------------------------------------------------
@test "generator: VALID_FLATLINE_MODELS is sorted and deduplicated" {
    local list
    list="$(grep -A 200 'declare -a VALID_FLATLINE_MODELS=' "$GENERATED" \
        | sed -n '/^(/,/^)$/p' | sed -n 's/^    \([^ ]*\)$/\1/p')"

    # Sorted check
    local sorted
    sorted="$(printf '%s\n' "$list" | LC_ALL=C sort -u)"
    [ "$list" = "$sorted" ]
}
