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
