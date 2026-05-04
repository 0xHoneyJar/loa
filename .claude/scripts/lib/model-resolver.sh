#!/usr/bin/env bash
# =============================================================================
# model-resolver.sh — alias → canonical model_id resolver (cycle-099 sprint-1B)
# =============================================================================
# Sources generated-model-maps.sh (the cycle-095 codegen output) and exposes
# small, well-defined functions for callers that want to look up a model alias
# (e.g. "opus", "reviewer", "tiny") without re-implementing the lookup logic.
#
# Why this lib exists:
#   Pre-cycle-099, every script that needed to map an alias to a canonical
#   model_id either (a) maintained its own associative array (drift surface),
#   or (b) hardcoded a model name like `--model opus` and trusted the
#   downstream model-invoke layer to resolve it (silent failure when the
#   alias was retired upstream).
#
#   Cycle-099 PRD G-1 ("single edit point") + G-3 ("zero drift") require
#   that all consumers source one place. This lib is that place for bash.
#   The TS path uses the codegen'd config.generated.ts emitted by sprint-1A's
#   gen-bb-registry.ts.
#
# Usage:
#   source "$REPO_ROOT/.claude/scripts/lib/model-resolver.sh"
#
#   # Plain alias → canonical model_id
#   model_id="$(resolve_alias opus)"
#   # → "claude-opus-4-7"
#
#   # Alias → provider:model_id (the format model-invoke accepts)
#   provider_id="$(resolve_provider_id opus)"
#   # → "anthropic:claude-opus-4-7"
#
# Both functions:
#   - Echo the resolved value on stdout (success path)
#   - Write `[MODEL-RESOLVER] unknown alias: <input>` to stderr and return 1
#     when the alias is not present in MODEL_IDS / MODEL_PROVIDERS
#   - Idempotent: calling resolve_alias on an already-canonical model_id
#     (which is a key in MODEL_IDS by codegen invariant) returns it unchanged
#
# This file is hand-maintained (NOT codegen output). It depends on the
# codegen output being kept in sync with the yaml — that's the drift gate's
# job (sprint-1B T1.5).

# Strict mode is the caller's choice; we don't enforce it because some legacy
# scripts source us under `set +e` and we shouldn't surprise them.

# Resolve repo paths relative to this lib's own location so callers don't
# need to set globals before sourcing.
_MODEL_RESOLVER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_MODEL_RESOLVER_GENERATED_MAPS="${_MODEL_RESOLVER_LIB_DIR}/../generated-model-maps.sh"

# Allow override for testing. The override sources arbitrary bash (the
# pointed-at file becomes the source of MODEL_PROVIDERS / MODEL_IDS),
# so it MUST be gated behind an explicit opt-in to prevent ambient env
# variables from redirecting model lookups to attacker-controlled values.
# Mirrors the cycle-098 LOA_L3_L2_LIB_OVERRIDE gate (CLAUDE.md "NEVER set
# LOA_L3_L2_LIB_OVERRIDE outside test fixtures").
#
# Honored when EITHER of these is set:
#   LOA_MODEL_RESOLVER_TEST_MODE=1
#   BATS_TEST_DIRNAME (bats sets this before each test)
if [[ -n "${LOA_MODEL_RESOLVER_GENERATED_MAPS_OVERRIDE:-}" ]]; then
    if [[ "${LOA_MODEL_RESOLVER_TEST_MODE:-}" == "1" ]] || [[ -n "${BATS_TEST_DIRNAME:-}" ]]; then
        echo "[MODEL-RESOLVER] override active: $LOA_MODEL_RESOLVER_GENERATED_MAPS_OVERRIDE" >&2
        _MODEL_RESOLVER_GENERATED_MAPS="$LOA_MODEL_RESOLVER_GENERATED_MAPS_OVERRIDE"
    else
        echo "[MODEL-RESOLVER] WARNING: LOA_MODEL_RESOLVER_GENERATED_MAPS_OVERRIDE set but LOA_MODEL_RESOLVER_TEST_MODE!=1 and not running under bats — override IGNORED" >&2
    fi
fi

if [[ ! -f "$_MODEL_RESOLVER_GENERATED_MAPS" ]]; then
    echo "[MODEL-RESOLVER] generated-model-maps.sh not found at $_MODEL_RESOLVER_GENERATED_MAPS" >&2
    echo "[MODEL-RESOLVER] regenerate via: bash .claude/scripts/gen-adapter-maps.sh" >&2
    return 1 2>/dev/null || exit 1
fi

# Sourcing populates MODEL_PROVIDERS, MODEL_IDS, COST_INPUT, COST_OUTPUT in the
# caller's shell. By design — these are the public interface of the codegen
# output and several existing callers already read them directly.
# shellcheck source=/dev/null
source "$_MODEL_RESOLVER_GENERATED_MAPS"

# resolve_alias <alias> — echo canonical model_id from MODEL_IDS.
# Returns 1 + stderr error if alias is unknown.
resolve_alias() {
    local alias="${1:-}"
    if [[ -z "$alias" ]]; then
        echo "[MODEL-RESOLVER] resolve_alias: missing alias argument" >&2
        return 1
    fi
    if [[ -z "${MODEL_IDS[$alias]+_}" ]]; then
        echo "[MODEL-RESOLVER] unknown alias: $alias" >&2
        return 1
    fi
    printf '%s\n' "${MODEL_IDS[$alias]}"
}

# resolve_provider_id <alias> — echo "<provider>:<model_id>" composed from
# MODEL_IDS + MODEL_PROVIDERS. Format consumed by model-invoke / cheval.
# Returns 1 + stderr error if alias is unknown OR if the resolved model_id
# is not present in MODEL_PROVIDERS (registry inconsistency — should never
# happen if codegen ran cleanly; surfaces it loudly if it does).
resolve_provider_id() {
    local alias="${1:-}"
    local model_id
    model_id="$(resolve_alias "$alias")" || return 1
    if [[ -z "${MODEL_PROVIDERS[$model_id]+_}" ]]; then
        echo "[MODEL-RESOLVER] registry inconsistency: model_id '$model_id' has no provider entry" >&2
        echo "[MODEL-RESOLVER] regenerate via: bash .claude/scripts/gen-adapter-maps.sh" >&2
        return 1
    fi
    printf '%s:%s\n' "${MODEL_PROVIDERS[$model_id]}" "$model_id"
}
