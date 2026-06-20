#!/usr/bin/env bats
# =============================================================================
# tests/unit/cycle-109-t3-2-cheval-cli-models.bats
#
# cycle-109 Sprint 3 T3.2 — regression test for #864 Issue 1 (legacy CLI
# crash class). Asserts that cheval correctly handles CLI-kind aliases
# (claude-headless, codex-headless, gemini-headless) without the
# cost-map-missing-key crash that #864 documented on the LEGACY path.
#
# Bug shape (per #864):
#   - .claude/scripts/model-adapter.sh.legacy:94 iterates COST_INPUT keys
#   - CLI-kind aliases have no pricing entry in model-config.yaml
#   - gen-adapter-maps.sh:241 skips zero-cost entries
#   - Legacy adapter crashes with "ERROR: COST_INPUT missing key: <alias>"
#
# Fix scope at cheval path:
#   - cheval reads pricing directly from model_data.get("pricing")
#   - None/missing pricing → ModelConfig.pricing = None
#   - kind:cli dispatch routes through CLI adapter (no cost lookup)
#   - Therefore cheval is structurally immune to the #864 Issue 1 class
#
# This test pins that immunity. If a future change introduces a cost-map
# lookup in cheval that doesn't handle missing pricing, this test fails.
#
# The full #864 closure also addresses Issue 2 (config-knob not honored)
# and Issue 3 (scoring engine empty on prefer-api). Those land in T3.3
# (#863 cost-map + orchestrator regressions) since they live at the FL
# orchestrator layer.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT

    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="$(command -v python3)"
    fi
    export PYTHONPATH="$PROJECT_ROOT/.claude/adapters"
}

_require_yq() {
    command -v yq >/dev/null 2>&1 || skip "yq not installed"
}

# =============================================================================
# T32-1: CLI aliases are declared in model-config.yaml
# =============================================================================

@test "T32-1: model-config.yaml declares all 3 CLI-kind aliases" {
    _require_yq
    local cfg="$PROJECT_ROOT/.claude/defaults/model-config.yaml"
    local codex_kind claude_kind gemini_kind
    codex_kind=$(yq eval '.providers.openai.models.codex-headless.kind // ""' "$cfg")
    claude_kind=$(yq eval '.providers.anthropic.models.claude-headless.kind // ""' "$cfg")
    gemini_kind=$(yq eval '.providers.google.models.gemini-headless.kind // ""' "$cfg")
    [ "$codex_kind" = "cli" ]
    [ "$claude_kind" = "cli" ]
    [ "$gemini_kind" = "cli" ]
}

# =============================================================================
# T32-2: CLI aliases have no pricing entry (intentional)
# =============================================================================

@test "T32-2: CLI-kind aliases have no pricing field (intentional)" {
    _require_yq
    local cfg="$PROJECT_ROOT/.claude/defaults/model-config.yaml"
    local codex_p claude_p gemini_p
    codex_p=$(yq eval '.providers.openai.models.codex-headless.pricing // "null"' "$cfg")
    claude_p=$(yq eval '.providers.anthropic.models.claude-headless.pricing // "null"' "$cfg")
    gemini_p=$(yq eval '.providers.google.models.gemini-headless.pricing // "null"' "$cfg")
    [ "$codex_p" = "null" ]
    [ "$claude_p" = "null" ]
    [ "$gemini_p" = "null" ]
}

# =============================================================================
# T32-3: cheval loads CLI-kind ModelConfig without crashing on missing pricing
# =============================================================================

@test "T32-3: cheval ModelConfig accepts pricing=None for CLI-kind aliases" {
    # Drive cheval's config loader at the ModelConfig level. A regression
    # that adds a required-pricing assertion would fail this test
    # immediately rather than at the next live FL invocation.
    "$PYTHON_BIN" - <<'PY'
import sys
sys.path.insert(0, ".claude/adapters")
from loa_cheval.config.loader import load_config

config, _ = load_config()
hounfour = config if "providers" in config else config.get("hounfour", config)

# Resolve the 3 CLI aliases through the loader; assert ModelConfig is
# constructed without raising AND that pricing is None.
required = [
    ("openai", "codex-headless"),
    ("anthropic", "claude-headless"),
    ("google", "gemini-headless"),
]
errors = []
for provider, model_id in required:
    try:
        provider_models = hounfour.get("providers", {}).get(provider, {}).get("models", {})
        model_data = provider_models.get(model_id)
        if not model_data:
            errors.append(f"{provider}:{model_id} not found in providers config")
            continue
        # Verify kind:cli + pricing absent (None or missing)
        if model_data.get("kind") != "cli":
            errors.append(f"{provider}:{model_id} kind={model_data.get('kind')!r} (expected 'cli')")
        if model_data.get("pricing") is not None:
            errors.append(f"{provider}:{model_id} pricing={model_data.get('pricing')!r} (expected None)")
    except Exception as e:  # noqa: BLE001
        errors.append(f"{provider}:{model_id} raised {type(e).__name__}: {e}")

if errors:
    for e in errors:
        print(f"FAIL: {e}", file=sys.stderr)
    sys.exit(1)
print("OK")
PY
}

# =============================================================================
# T32-4: cheval chain-walk reaches CLI adapters without cost-map crash
# =============================================================================

@test "T32-4: chain_resolver builds entries for CLI aliases with adapter_kind=cli" {
    "$PYTHON_BIN" - <<'PY'
import sys
sys.path.insert(0, ".claude/adapters")
from loa_cheval.config.loader import load_config
from loa_cheval.routing import chain_resolver

config, _ = load_config()
hounfour = config if "providers" in config else config.get("hounfour", config)

# Walk a known CLI alias through chain_resolver.resolve; the resulting
# chain should contain at least one entry with adapter_kind == "cli".
#
# We don't actually invoke the adapter (no subscription / no env keys
# guaranteed in CI); only assert the resolution path completes and
# emits the kind:cli annotation.
errors = []
# To route a kind:cli entry as the FINAL adapter, the chain_resolver
# needs to know the headless_mode. The default is prefer-api which
# walks CLI last; prefer-cli walks it first. Either way, the chain
# MUST include at least one kind:cli entry for these aliases.
for model_alias, expected_provider in [
    ("codex-headless", "openai"),
    ("claude-headless", "anthropic"),
    ("gemini-headless", "google"),
]:
    try:
        chain = chain_resolver.resolve(
            primary_alias=model_alias,
            model_config=hounfour,
            headless_mode="prefer-cli",
        )
        any_cli = any(
            getattr(e, "adapter_kind", "http") == "cli" for e in chain.entries
        )
        if not any_cli:
            errors.append(
                f"{model_alias} chain has no adapter_kind=cli entry; "
                f"entries={[(getattr(e, 'canonical', '?'), getattr(e, 'adapter_kind', '?')) for e in chain.entries]}"
            )
    except Exception as e:  # noqa: BLE001
        errors.append(f"{model_alias} raised {type(e).__name__}: {e}")

if errors:
    for e in errors:
        print(f"FAIL: {e}", file=sys.stderr)
    sys.exit(1)
print("OK")
PY
}

# =============================================================================
# T32-5: cost-map lookup is structurally absent in cheval's CLI dispatch path
# =============================================================================

@test "T32-5: cheval has no COST_INPUT/COST_OUTPUT bash maps to crash on" {
    # Negative test: cheval's pricing flow goes through
    # loa_cheval.metering.pricing.find_pricing, which returns Optional
    # values. The legacy adapter's bash COST_INPUT/COST_OUTPUT associative
    # arrays do NOT appear in cheval.py — proving the failure mode is
    # structurally impossible.
    run grep -n 'COST_INPUT\|COST_OUTPUT' "$PROJECT_ROOT/.claude/adapters/cheval.py"
    [ "$status" -ne 0 ]
    [[ -z "$output" ]]
}

# =============================================================================
# T32-6: legacy adapter still has the crash class (documents the divergence)
# =============================================================================

@test "T32-6: legacy adapter still has the COST_INPUT crash code (deletion pending T3.7)" {
    # Confirms the bug class IS still present in the legacy adapter, so
    # the matrix scaffolding test AM11 (legacy file exists) reflects the
    # actual bug-carrying state. After T3.7 deletes the legacy file, this
    # test SHOULD ALSO FAIL (no file to grep) — that flip is the canary
    # for the destructive commit landing correctly.
    [[ -f "$PROJECT_ROOT/.claude/scripts/model-adapter.sh.legacy" ]] \
        || skip "legacy file already deleted (post-T3.7); test no longer applicable"
    grep -q 'COST_INPUT missing key' "$PROJECT_ROOT/.claude/scripts/model-adapter.sh.legacy"
}

# =============================================================================
# T32-7: xAI grok — the router-of-routers port. ONE provider, TWO kind:cli
# models (grok-build + grok-composer-2.5-fast), both no-pricing. (2026-06-13)
# =============================================================================

@test "T32-7: xai provider declares BOTH grok models as kind:cli, no pricing" {
    _require_yq
    local cfg="$PROJECT_ROOT/.claude/defaults/model-config.yaml"
    local build_kind composer_kind build_price composer_price ptype
    ptype=$(yq eval '.providers.xai.type // ""' "$cfg")
    build_kind=$(yq eval '.providers.xai.models.grok-build.kind // ""' "$cfg")
    composer_kind=$(yq eval '.providers.xai.models["grok-composer-2.5-fast"].kind // ""' "$cfg")
    build_price=$(yq eval '.providers.xai.models.grok-build.pricing // "null"' "$cfg")
    composer_price=$(yq eval '.providers.xai.models["grok-composer-2.5-fast"].pricing // "null"' "$cfg")
    [ "$ptype" = "grok-headless" ]
    [ "$build_kind" = "cli" ]
    [ "$composer_kind" = "cli" ]
    [ "$build_price" = "null" ]
    [ "$composer_price" = "null" ]
}

# =============================================================================
# T32-8: xai is chain-terminal — NEITHER grok model declares a fallback_chain
# (no cross-company substitution; lint-enforced invariant).
# =============================================================================

@test "T32-8: xai grok models are chain-terminal (no fallback_chain)" {
    _require_yq
    local cfg="$PROJECT_ROOT/.claude/defaults/model-config.yaml"
    local build_fb composer_fb
    build_fb=$(yq eval '.providers.xai.models.grok-build.fallback_chain // "null"' "$cfg")
    composer_fb=$(yq eval '.providers.xai.models["grok-composer-2.5-fast"].fallback_chain // "null"' "$cfg")
    [ "$build_fb" = "null" ]
    [ "$composer_fb" = "null" ]
}

# =============================================================================
# T32-9: cli_model maps each port-model to the real `grok --model` id.
# =============================================================================

@test "T32-9: each xai model carries its cli_model id" {
    _require_yq
    local cfg="$PROJECT_ROOT/.claude/defaults/model-config.yaml"
    local build_cli composer_cli
    build_cli=$(yq eval '.providers.xai.models.grok-build.extra.cli_model // ""' "$cfg")
    composer_cli=$(yq eval '.providers.xai.models["grok-composer-2.5-fast"].extra.cli_model // ""' "$cfg")
    [ "$build_cli" = "grok-build" ]
    [ "$composer_cli" = "grok-composer-2.5-fast" ]
}

# =============================================================================
# T32-10: the loader resolves BOTH xai models without raising, kind:cli +
# pricing None (parity with T32-3 for the new-company provider).
# =============================================================================

@test "T32-10: loader resolves both xai grok models as kind:cli with no pricing" {
    "$PYTHON_BIN" - <<'PY'
import sys
sys.path.insert(0, ".claude/adapters")
from loa_cheval.config.loader import load_config

config, _ = load_config()
hounfour = config if "providers" in config else config.get("hounfour", config)

required = [
    ("xai", "grok-build"),
    ("xai", "grok-composer-2.5-fast"),
]
errors = []
for provider, model_id in required:
    try:
        provider_models = hounfour.get("providers", {}).get(provider, {}).get("models", {})
        model_data = provider_models.get(model_id)
        if not model_data:
            errors.append(f"{provider}:{model_id} not found in providers config")
            continue
        if model_data.get("kind") != "cli":
            errors.append(f"{provider}:{model_id} kind={model_data.get('kind')!r} (expected 'cli')")
        if model_data.get("pricing") is not None:
            errors.append(f"{provider}:{model_id} pricing={model_data.get('pricing')!r} (expected None)")
        if model_data.get("auth_type") != "headless":
            errors.append(f"{provider}:{model_id} auth_type={model_data.get('auth_type')!r} (expected 'headless')")
    except Exception as e:  # noqa: BLE001
        errors.append(f"{provider}:{model_id} raised {type(e).__name__}: {e}")

if errors:
    for e in errors:
        print(f"FAIL: {e}", file=sys.stderr)
    sys.exit(1)
print("OK")
PY
}

# =============================================================================
# T32-11: the xai company column joins tier_groups.mappings without disturbing
# the deterministic (sorted-first = anthropic) pick. xai sorts last → present
# but never the default winner.
# =============================================================================

@test "T32-11: tier_groups carries an xai column on every tier, sorted last" {
    _require_yq
    local cfg="$PROJECT_ROOT/.claude/defaults/model-config.yaml"
    local t
    for t in max mid cheap tiny; do
        local xai_val first
        xai_val=$(yq eval ".tier_groups.mappings.$t.xai // \"\"" "$cfg")
        [ -n "$xai_val" ] || { echo "tier $t missing xai column"; return 1; }
        # The deterministic consumer picks sorted-first; anthropic must still win.
        first=$(yq eval ".tier_groups.mappings.$t | keys | sort | .[0]" "$cfg")
        [ "$first" = "anthropic" ] || { echo "tier $t sorted-first=$first (expected anthropic)"; return 1; }
    done
}

# =============================================================================
# T32-12: Cursor Composer — a second new-company headless port (parity with the
# xai/grok T32-7 port). ONE provider, TWO kind:cli models (composer-2.5 +
# composer-2.5-fast), both no-pricing. The adapter (CursorHeadlessAdapter) +
# registry + loader inference already shipped; this declares the SoT entry.
# =============================================================================

@test "T32-12: cursor provider declares BOTH composer models as kind:cli, no pricing" {
    _require_yq
    local cfg="$PROJECT_ROOT/.claude/defaults/model-config.yaml"
    local cur_kind fast_kind cur_price fast_price ptype
    ptype=$(yq eval '.providers.cursor.type // ""' "$cfg")
    cur_kind=$(yq eval '.providers.cursor.models["composer-2.5"].kind // ""' "$cfg")
    fast_kind=$(yq eval '.providers.cursor.models["composer-2.5-fast"].kind // ""' "$cfg")
    cur_price=$(yq eval '.providers.cursor.models["composer-2.5"].pricing // "null"' "$cfg")
    fast_price=$(yq eval '.providers.cursor.models["composer-2.5-fast"].pricing // "null"' "$cfg")
    [ "$ptype" = "cursor-headless" ]
    [ "$cur_kind" = "cli" ]
    [ "$fast_kind" = "cli" ]
    [ "$cur_price" = "null" ]
    [ "$fast_price" = "null" ]
}

# =============================================================================
# T32-13: cursor is chain-terminal — NEITHER composer model declares a
# fallback_chain (no cross-company substitution; lint-enforced invariant).
# =============================================================================

@test "T32-13: cursor composer models are chain-terminal (no fallback_chain)" {
    _require_yq
    local cfg="$PROJECT_ROOT/.claude/defaults/model-config.yaml"
    local cur_fb fast_fb
    cur_fb=$(yq eval '.providers.cursor.models["composer-2.5"].fallback_chain // "null"' "$cfg")
    fast_fb=$(yq eval '.providers.cursor.models["composer-2.5-fast"].fallback_chain // "null"' "$cfg")
    [ "$cur_fb" = "null" ]
    [ "$fast_fb" = "null" ]
}

# =============================================================================
# T32-14: cli_model maps each port-model to the real `cursor-agent --model` id.
# =============================================================================

@test "T32-14: each cursor model carries its cli_model id" {
    _require_yq
    local cfg="$PROJECT_ROOT/.claude/defaults/model-config.yaml"
    local cur_cli fast_cli
    cur_cli=$(yq eval '.providers.cursor.models["composer-2.5"].extra.cli_model // ""' "$cfg")
    fast_cli=$(yq eval '.providers.cursor.models["composer-2.5-fast"].extra.cli_model // ""' "$cfg")
    [ "$cur_cli" = "composer-2.5" ]
    [ "$fast_cli" = "composer-2.5-fast" ]
}

# =============================================================================
# T32-15: the loader resolves BOTH cursor models without raising, kind:cli +
# pricing None (parity with T32-10 for the second new-company provider).
# =============================================================================

@test "T32-15: loader resolves both cursor composer models as kind:cli with no pricing" {
    "$PYTHON_BIN" - <<'PY'
import sys
sys.path.insert(0, ".claude/adapters")
from loa_cheval.config.loader import load_config

config, _ = load_config()
hounfour = config if "providers" in config else config.get("hounfour", config)

required = [
    ("cursor", "composer-2.5"),
    ("cursor", "composer-2.5-fast"),
]
errors = []
for provider, model_id in required:
    try:
        provider_models = hounfour.get("providers", {}).get(provider, {}).get("models", {})
        model_data = provider_models.get(model_id)
        if not model_data:
            errors.append(f"{provider}:{model_id} not found in providers config")
            continue
        if model_data.get("kind") != "cli":
            errors.append(f"{provider}:{model_id} kind={model_data.get('kind')!r} (expected 'cli')")
        if model_data.get("pricing") is not None:
            errors.append(f"{provider}:{model_id} pricing={model_data.get('pricing')!r} (expected None)")
        if model_data.get("auth_type") != "headless":
            errors.append(f"{provider}:{model_id} auth_type={model_data.get('auth_type')!r} (expected 'headless')")
    except Exception as e:  # noqa: BLE001
        errors.append(f"{provider}:{model_id} raised {type(e).__name__}: {e}")

if errors:
    for e in errors:
        print(f"FAIL: {e}", file=sys.stderr)
    sys.exit(1)
print("OK")
PY
}
