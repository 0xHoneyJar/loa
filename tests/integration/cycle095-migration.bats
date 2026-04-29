#!/usr/bin/env bats
# =============================================================================
# cycle-095 Sprint 1 — endpoint_family migration invariants (PRD §3.4)
#
# Asserts the migration ordering invariant locked by SDD §3.4:
#   - Every providers.openai.models.* entry in .claude/defaults/model-config.yaml
#     has an explicit endpoint_family field (BEFORE strict validation activates,
#     same commit as the loader change).
#   - The endpoint_family value is in the allowlist {chat, responses}.
#   - The cheval Python validator agrees: load_config() succeeds on the
#     committed YAML and FAILS if a synthetic delete is injected.
#   - The LOA_LEGACY_ENDPOINT_FAMILY_DEFAULT=chat backstop converts FAIL → WARN.
#
# This is a CHEAP CI gate (no network). It runs alongside the existing
# model-registry-sync.bats; together they enforce the SSOT + migration
# invariants for cycle-095.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    CONFIG="$PROJECT_ROOT/.claude/defaults/model-config.yaml"
    LEGACY_ALIASES="$PROJECT_ROOT/.claude/defaults/aliases-legacy.yaml"
    PYTHON_BIN="${PYTHON_BIN:-python3}"
}

# -----------------------------------------------------------------------------
# Migration step (Task 1.2) — every OpenAI entry has endpoint_family
# -----------------------------------------------------------------------------
@test "migration: every providers.openai.models.* has explicit endpoint_family" {
    local missing
    missing="$(yq eval -o=json '.providers.openai.models' "$CONFIG" \
        | jq -r 'to_entries[] | select(.value.endpoint_family == null) | .key')"
    if [[ -n "$missing" ]]; then
        echo "OpenAI entries missing endpoint_family:" >&2
        echo "$missing" >&2
        return 1
    fi
}

@test "migration: every endpoint_family is in {chat, responses}" {
    local invalid
    invalid="$(yq eval -o=json '.providers.openai.models' "$CONFIG" \
        | jq -r 'to_entries[]
                 | select(.value.endpoint_family != null)
                 | select(.value.endpoint_family | test("^(chat|responses)$") | not)
                 | "\(.key)=\(.value.endpoint_family)"')"
    if [[ -n "$invalid" ]]; then
        echo "OpenAI entries with invalid endpoint_family:" >&2
        echo "$invalid" >&2
        return 1
    fi
}

@test "migration: gpt-5.5 and gpt-5.5-pro route to /v1/responses" {
    local v
    v="$(yq eval '.providers.openai.models["gpt-5.5"].endpoint_family' "$CONFIG")"
    [[ "$v" == "responses" ]] || { echo "gpt-5.5 endpoint_family=$v"; return 1; }

    v="$(yq eval '.providers.openai.models["gpt-5.5-pro"].endpoint_family' "$CONFIG")"
    [[ "$v" == "responses" ]] || { echo "gpt-5.5-pro endpoint_family=$v"; return 1; }
}

@test "migration: gpt-5.2 routes to /v1/chat/completions (regression sentinel)" {
    local v
    v="$(yq eval '.providers.openai.models["gpt-5.2"].endpoint_family' "$CONFIG")"
    [[ "$v" == "chat" ]] || { echo "gpt-5.2 endpoint_family=$v"; return 1; }
}

@test "migration: gpt-5.3-codex routes to /v1/responses (codex precedent)" {
    local v
    v="$(yq eval '.providers.openai.models["gpt-5.3-codex"].endpoint_family' "$CONFIG")"
    [[ "$v" == "responses" ]] || { echo "gpt-5.3-codex endpoint_family=$v"; return 1; }
}

# -----------------------------------------------------------------------------
# Strict validation (Task 1.3) — Python loader rejects deletions
# -----------------------------------------------------------------------------
@test "validation: load_config succeeds on the committed YAML" {
    run "$PYTHON_BIN" -c "
import sys
sys.path.insert(0, '$PROJECT_ROOT/.claude/adapters')
from loa_cheval.config.loader import load_config, clear_config_cache, _reset_warning_state_for_tests
clear_config_cache()
_reset_warning_state_for_tests()
import os
os.environ.pop('LOA_LEGACY_ENDPOINT_FAMILY_DEFAULT', None)
os.environ.pop('LOA_FORCE_LEGACY_ALIASES', None)
merged, _ = load_config(project_root='$PROJECT_ROOT')
assert merged['providers']['openai']['models']['gpt-5.5']['endpoint_family'] == 'responses'
print('ok')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "validation: load_config FAILS when a synthetic delete is injected" {
    local tmpdir; tmpdir="$(mktemp -d)"
    mkdir -p "$tmpdir/.claude/defaults"
    # Copy committed config and snapshot, then strip endpoint_family from one entry.
    cp "$CONFIG" "$tmpdir/.claude/defaults/model-config.yaml"
    yq eval -i 'del(.providers.openai.models["gpt-5.2"].endpoint_family)' \
        "$tmpdir/.claude/defaults/model-config.yaml"
    if [[ -f "$LEGACY_ALIASES" ]]; then
        cp "$LEGACY_ALIASES" "$tmpdir/.claude/defaults/aliases-legacy.yaml"
    fi

    run "$PYTHON_BIN" -c "
import sys, os
sys.path.insert(0, '$PROJECT_ROOT/.claude/adapters')
from loa_cheval.config.loader import load_config, clear_config_cache, _reset_warning_state_for_tests
clear_config_cache()
_reset_warning_state_for_tests()
os.environ.pop('LOA_LEGACY_ENDPOINT_FAMILY_DEFAULT', None)
os.environ.pop('LOA_FORCE_LEGACY_ALIASES', None)
try:
    load_config(project_root='$tmpdir')
except Exception as exc:
    if 'endpoint_family' in str(exc):
        print('expected_error')
    else:
        print('wrong_error:', exc)
        sys.exit(1)
"
    rm -rf "$tmpdir"
    [ "$status" -eq 0 ]
    [[ "$output" == *"expected_error"* ]]
}

@test "validation: LOA_LEGACY_ENDPOINT_FAMILY_DEFAULT=chat converts FAIL to WARN" {
    local tmpdir; tmpdir="$(mktemp -d)"
    mkdir -p "$tmpdir/.claude/defaults"
    cp "$CONFIG" "$tmpdir/.claude/defaults/model-config.yaml"
    yq eval -i 'del(.providers.openai.models["gpt-5.2"].endpoint_family)' \
        "$tmpdir/.claude/defaults/model-config.yaml"
    if [[ -f "$LEGACY_ALIASES" ]]; then
        cp "$LEGACY_ALIASES" "$tmpdir/.claude/defaults/aliases-legacy.yaml"
    fi

    LOA_LEGACY_ENDPOINT_FAMILY_DEFAULT=chat run "$PYTHON_BIN" -c "
import sys, os
sys.path.insert(0, '$PROJECT_ROOT/.claude/adapters')
from loa_cheval.config.loader import load_config, clear_config_cache, _reset_warning_state_for_tests
clear_config_cache()
_reset_warning_state_for_tests()
os.environ.pop('LOA_FORCE_LEGACY_ALIASES', None)
merged, _ = load_config(project_root='$tmpdir')
v = merged['providers']['openai']['models']['gpt-5.2'].get('endpoint_family')
print('defaulted_to=' + repr(v))
"
    rm -rf "$tmpdir"
    [ "$status" -eq 0 ]
    [[ "$output" == *"defaulted_to='chat'"* ]]
}

# -----------------------------------------------------------------------------
# Kill-switch snapshot (Task 1.7) — pre-cycle-095 alias state preserved
# -----------------------------------------------------------------------------
@test "snapshot: aliases-legacy.yaml exists and has reviewer + reasoning entries" {
    [[ -f "$LEGACY_ALIASES" ]] || { echo "missing: $LEGACY_ALIASES"; return 1; }
    local reviewer reasoning
    reviewer="$(yq eval '.aliases.reviewer' "$LEGACY_ALIASES")"
    reasoning="$(yq eval '.aliases.reasoning' "$LEGACY_ALIASES")"
    [[ "$reviewer" == "openai:gpt-5.3-codex" ]] || { echo "reviewer=$reviewer"; return 1; }
    [[ "$reasoning" == "openai:gpt-5.3-codex" ]] || { echo "reasoning=$reasoning"; return 1; }
}
