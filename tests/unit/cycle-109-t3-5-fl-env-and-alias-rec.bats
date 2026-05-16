#!/usr/bin/env bats
# =============================================================================
# tests/unit/cycle-109-t3-5-fl-env-and-alias-rec.bats
#
# cycle-109 Sprint 3 T3.5 — closes #820 Issues C + D.
#
#   Issue C: flatline-readiness.sh recommendation references
#            'gemini-3.1-pro' (unregistered) instead of an alias that
#            actually exists in model-config.yaml.
#   Issue D: flatline-orchestrator.sh does not load .env / .env.local
#            before invoking model adapters (BB does; FL does not).
#            Updated post-#898: loading is via load_env_file (safe
#            KEY=VALUE parser) instead of `set -a; source .env; set +a`
#            because the latter executes arbitrary bash inside .env.
#   Issue D': scoring parser empty-output — already covered by T3.3
#             extract_json_content regression corpus.
#
# These tests use grep-style wiring assertions because the actual
# behavior (env loading semantics + recommendation text) is structural;
# integration tests with live model invocation are out of scope for the
# unit suite.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
}

# =============================================================================
# T35-1..3: Issue D — flatline-orchestrator.sh loads .env / .env.local
# (post-#898: via load_env_file safe parser; T35-3 inverted to NEGATIVE
# control — the legacy `set -a; source .env; set +a` pattern MUST NOT
# reappear, because it would re-introduce the RCE vector.)
# =============================================================================

@test "T35-1: flatline-orchestrator.sh loads .env via load_env_file" {
    grep -qE 'load_env_file[[:space:]]+\.env\b' \
        "$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
}

@test "T35-2: flatline-orchestrator.sh loads .env.local via load_env_file" {
    grep -qE 'load_env_file[[:space:]]+\.env\.local' \
        "$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
}

@test "T35-3: flatline-orchestrator.sh does NOT use the unsafe 'set -a; source .env' pattern (#898 anti-regression)" {
    # Inverted post-#898: this is now a NEGATIVE control. The previous
    # version of T35-3 asserted the presence of `set -a / set +a`, but
    # that pattern is exactly what made .env loading an RCE vector.
    # `source .env` executes any bash inside the file (command
    # substitution, backticks, ; chains); the safe replacement
    # load_env_file parses KEY=VALUE structurally and refuses shell
    # metacharacters. See lib/env-loader.sh.
    # Comment lines that mention the legacy pattern (documenting WHY it
    # was removed) are filtered out — only CODE-line matches fail this.
    local hits
    hits=$(grep -hE 'set[[:space:]]+-a[[:space:]]*;[[:space:]]*source[[:space:]]+\.env' \
        "$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh" \
        | grep -vE '^[[:space:]]*#' || true)
    if [[ -n "$hits" ]]; then
        echo "FAIL: legacy 'set -a; source .env' pattern resurfaced on a code line:" >&2
        echo "$hits" >&2
        return 1
    fi
}

# =============================================================================
# T35-4: Issue C — recommendation text doesn't reference an unregistered alias
# =============================================================================

@test "T35-4: flatline-readiness.sh recommendation does NOT suggest unregistered 'gemini-3.1-pro'" {
    # #820 Issue C: the recommendation text literally says "use
    # 'gemini-3.1-pro' instead of 'gemini-3.1-pro-preview'" but
    # gemini-3.1-pro is NOT a registered alias. Either the recommendation
    # must reference a real alias OR drop the literal alias suggestion
    # and only point at the pin-form.
    #
    # Acceptable post-fix shapes:
    #   - "use 'google:<model_id>' pin form" (drops the alias suggestion)
    #   - References any alias that IS in model-config.yaml's aliases map
    #
    # Disallowed: the literal 'gemini-3.1-pro' string appearing as a
    # recommendation when no such alias exists.
    if grep -qE "'gemini-3\.1-pro'[[:space:]]+instead" "$PROJECT_ROOT/.claude/scripts/flatline-readiness.sh"; then
        echo "FAIL: recommendation still suggests 'gemini-3.1-pro' instead of a real alias" >&2
        return 1
    fi
}

# =============================================================================
# T35-5: BB / FL .env-load parity (positive control on the design intent)
# =============================================================================

@test "T35-5: BB entry.sh uses load_env_file (post-#898 parity baseline)" {
    grep -qE 'load_env_file[[:space:]]+\.env\b' \
        "$PROJECT_ROOT/.claude/skills/bridgebuilder-review/resources/entry.sh"
}

# =============================================================================
# T35-6: Issue D' coverage already enforced by T3.3 corpus
# =============================================================================

@test "T35-6: extract_json_content regression corpus exists (Issue D' coverage)" {
    [[ -f "$PROJECT_ROOT/tests/unit/cycle-109-t3-3-flatline-extract-json-content.bats" ]]
}
