"""Cycle-110 sprint-2a T2.4 — auth_type + dispatch_group strict validation.

Tests `_validate_model_auth_metadata` in loader.py:
- Missing auth_type → ConfigError with [CONFIG-INVALID].
- Enum-invalid auth_type → ConfigError with [CONFIG-ENUM-INVALID].
- Missing dispatch_group → ConfigError with [CONFIG-INVALID] + C14 hint.
- Pattern-invalid dispatch_group → ConfigError with [CONFIG-INVALID].
- Valid metadata → no raise.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest
import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.config.loader import (  # noqa: E402
    _reset_warning_state_for_tests,
    _validate_model_auth_metadata,
    clear_config_cache,
    load_config,
)
from loa_cheval.types import ConfigError  # noqa: E402


def _write_minimal_project(tmp_path, openai_models):
    root = tmp_path
    (root / ".claude" / "defaults").mkdir(parents=True, exist_ok=True)
    config = {
        "providers": {
            "openai": {
                "type": "openai",
                "endpoint": "https://api.example.com/v1",
                "auth": "test-key",
                "models": openai_models,
            }
        },
        "aliases": {},
    }
    with (root / ".claude" / "defaults" / "model-config.yaml").open("w") as f:
        yaml.safe_dump(config, f, sort_keys=False)
    return str(root)


@pytest.fixture(autouse=True)
def _isolate(monkeypatch):
    clear_config_cache()
    _reset_warning_state_for_tests()
    monkeypatch.delenv("LOA_LEGACY_ENDPOINT_FAMILY_DEFAULT", raising=False)
    monkeypatch.delenv("LOA_FORCE_LEGACY_ALIASES", raising=False)


class TestAuthTypeValidation:
    def test_missing_auth_type_raises_config_invalid(self, tmp_path):
        root = _write_minimal_project(tmp_path, {
            "gpt-5.2": {
                "capabilities": ["chat"],
                "context_window": 128000,
                "endpoint_family": "chat",
                "dispatch_group": "openai-gpt",
            },
        })
        with pytest.raises(ConfigError, match=r"\[CONFIG-INVALID\].*auth_type"):
            load_config(project_root=root)

    def test_enum_invalid_auth_type_raises_config_enum_invalid(self, tmp_path):
        root = _write_minimal_project(tmp_path, {
            "gpt-5.2": {
                "capabilities": ["chat"],
                "context_window": 128000,
                "endpoint_family": "chat",
                "auth_type": "subscription",   # not in enum
                "dispatch_group": "openai-gpt",
            },
        })
        with pytest.raises(ConfigError, match=r"\[CONFIG-ENUM-INVALID\].*auth_type"):
            load_config(project_root=root)

    def test_valid_auth_type_loads_cleanly(self, tmp_path):
        root = _write_minimal_project(tmp_path, {
            "gpt-5.2": {
                "capabilities": ["chat"],
                "context_window": 128000,
                "endpoint_family": "chat",
                "auth_type": "http_api",
                "dispatch_group": "openai-gpt",
            },
        })
        merged, _ = load_config(project_root=root)
        assert merged["providers"]["openai"]["models"]["gpt-5.2"]["auth_type"] == "http_api"

    def test_all_three_enum_values_accepted(self, tmp_path):
        for auth_type in ("headless", "http_api", "aws_iam"):
            root = _write_minimal_project(tmp_path / f"sub-{auth_type}", {
                "gpt-5.2": {
                    "capabilities": ["chat"],
                    "context_window": 128000,
                    "endpoint_family": "chat",
                    "auth_type": auth_type,
                    "dispatch_group": "openai-gpt",
                },
            })
            merged, _ = load_config(project_root=root)
            assert merged["providers"]["openai"]["models"]["gpt-5.2"]["auth_type"] == auth_type


class TestDispatchGroupValidation:
    """C14 closure — dispatch_group is REQUIRED."""

    def test_missing_dispatch_group_raises_with_c14_hint(self, tmp_path):
        root = _write_minimal_project(tmp_path, {
            "gpt-5.2": {
                "capabilities": ["chat"],
                "context_window": 128000,
                "endpoint_family": "chat",
                "auth_type": "http_api",
            },
        })
        with pytest.raises(ConfigError, match=r"\[CONFIG-INVALID\].*dispatch_group"):
            load_config(project_root=root)

    def test_pattern_invalid_dispatch_group_raises(self, tmp_path):
        # Reject empty string, leading digit, shell metas, uppercase.
        for bad in ("", "1openai", "openai gpt", "OPENAI", "openai$", "$(rm -rf /)"):
            root = _write_minimal_project(tmp_path / f"sub-{abs(hash(bad))}", {
                "gpt-5.2": {
                    "capabilities": ["chat"],
                    "context_window": 128000,
                    "endpoint_family": "chat",
                    "auth_type": "http_api",
                    "dispatch_group": bad,
                },
            })
            with pytest.raises(ConfigError, match=r"\[CONFIG-INVALID\].*dispatch_group"):
                load_config(project_root=root)

    def test_valid_dispatch_group_patterns_accepted(self, tmp_path):
        for good in ("openai-gpt", "anthropic-claude", "google-gemini", "bedrock-anthropic"):
            root = _write_minimal_project(tmp_path / f"sub-{good}", {
                "gpt-5.2": {
                    "capabilities": ["chat"],
                    "context_window": 128000,
                    "endpoint_family": "chat",
                    "auth_type": "http_api",
                    "dispatch_group": good,
                },
            })
            merged, _ = load_config(project_root=root)
            assert merged["providers"]["openai"]["models"]["gpt-5.2"]["dispatch_group"] == good


class TestProductionConfigPasses:
    """Smoke-test against the real shipped .claude/defaults/model-config.yaml —
    every entry MUST have auth_type + dispatch_group post-T2.3 migration."""

    def test_default_config_passes_validation(self):
        # The real load_config walks the production file. If any of the 21
        # entries are missing auth_type/dispatch_group, this fails.
        merged, _ = load_config()
        providers = merged.get("providers", {})
        for prov_id, prov in providers.items():
            for model_id, model in (prov.get("models") or {}).items():
                assert "auth_type" in model, f"{prov_id}/{model_id} missing auth_type"
                assert model["auth_type"] in {"headless", "http_api", "aws_iam"}, (
                    f"{prov_id}/{model_id} auth_type={model['auth_type']} invalid"
                )
                assert "dispatch_group" in model, f"{prov_id}/{model_id} missing dispatch_group"
                assert isinstance(model["dispatch_group"], str) and model["dispatch_group"], (
                    f"{prov_id}/{model_id} dispatch_group invalid: {model['dispatch_group']!r}"
                )


class TestDirectValidatorCall:
    """Direct unit tests on `_validate_model_auth_metadata` for non-loader call paths."""

    def test_empty_providers_passes(self):
        _validate_model_auth_metadata({"providers": {}})

    def test_no_providers_key_passes(self):
        _validate_model_auth_metadata({})

    def test_provider_without_models_passes(self):
        _validate_model_auth_metadata({"providers": {"openai": {}}})

    def test_non_dict_models_raises(self):
        with pytest.raises(ConfigError, match=r"must be a mapping"):
            _validate_model_auth_metadata({
                "providers": {"openai": {"models": "not-a-dict"}}
            })

    def test_non_dict_model_entry_raises(self):
        with pytest.raises(ConfigError, match=r"must be a mapping"):
            _validate_model_auth_metadata({
                "providers": {"openai": {"models": {"gpt-5.2": "not-a-dict"}}}
            })


# ---------------------------------------------------------------------------
# sprint-bug-197 (#979): auth_type / dispatch_group inference for custom
# *-headless providers declared in .loa.config.yaml (hounfour: section).
#
# The framework's own .loa.config.yaml.example (~803-895) and the headless
# adapter docstrings document a FIELD-LESS model shape for the three headless
# provider types. PR #904 stamped auth_type/dispatch_group only onto the
# System-Zone defaults, so operators copying the documented example got a
# config-dead multi-model lane: _validate_model_auth_metadata raised
# [CONFIG-INVALID] at load time.
# ---------------------------------------------------------------------------


def _write_project_with_custom_provider(
    tmp_path, provider_id, ptype, models, include_type=True
):
    """Defaults with empty providers + .loa.config.yaml custom provider."""
    root = tmp_path
    (root / ".claude" / "defaults").mkdir(parents=True, exist_ok=True)
    with (root / ".claude" / "defaults" / "model-config.yaml").open("w") as f:
        yaml.safe_dump({"providers": {}, "aliases": {}}, f, sort_keys=False)

    provider = {
        "endpoint": "",
        "auth": "",
        "read_timeout": 600.0,
        "models": models,
    }
    if include_type:
        provider["type"] = ptype
    loa_config = {"hounfour": {"providers": {provider_id: provider}}}
    with (root / ".loa.config.yaml").open("w") as f:
        yaml.safe_dump(loa_config, f, sort_keys=False)
    return str(root)


# The documented field-less model shape (mirrors .loa.config.yaml.example
# gemini-headless / claude-headless blocks: capabilities, context_window,
# pricing — no auth_type, no dispatch_group).
def _fieldless_model():
    return {
        "capabilities": ["chat"],
        "context_window": 200000,
        "pricing": {"input_per_mtok": 0, "output_per_mtok": 0},
    }


class TestHeadlessProviderInference:
    def test_custom_claude_headless_fieldless_model_loads(self, tmp_path):
        """The exact documented example shape must load — not die [CONFIG-INVALID]."""
        root = _write_project_with_custom_provider(
            tmp_path, "claude-headless", "claude-headless",
            {"claude-opus-4-7": _fieldless_model()},
        )
        merged, _ = load_config(project_root=root)
        entry = merged["providers"]["claude-headless"]["models"]["claude-opus-4-7"]
        assert entry["auth_type"] == "headless"
        assert entry["dispatch_group"] == "anthropic-claude"

    def test_codex_headless_infers_openai_gpt_group(self, tmp_path):
        root = _write_project_with_custom_provider(
            tmp_path, "my-codex", "codex-headless",
            {"gpt-5.5": _fieldless_model()},
        )
        merged, _ = load_config(project_root=root)
        entry = merged["providers"]["my-codex"]["models"]["gpt-5.5"]
        assert entry["auth_type"] == "headless"
        assert entry["dispatch_group"] == "openai-gpt"

    def test_gemini_headless_infers_google_gemini_group(self, tmp_path):
        root = _write_project_with_custom_provider(
            tmp_path, "gemini-headless", "gemini-headless",
            {"gemini-3.1-pro-preview": _fieldless_model()},
        )
        merged, _ = load_config(project_root=root)
        entry = merged["providers"]["gemini-headless"]["models"]["gemini-3.1-pro-preview"]
        assert entry["auth_type"] == "headless"
        assert entry["dispatch_group"] == "google-gemini"

    def test_operator_explicit_values_never_overwritten(self, tmp_path):
        model = _fieldless_model()
        model["auth_type"] = "http_api"
        model["dispatch_group"] = "operator-custom-group"
        root = _write_project_with_custom_provider(
            tmp_path, "claude-headless", "claude-headless",
            {"claude-opus-4-7": model},
        )
        merged, _ = load_config(project_root=root)
        entry = merged["providers"]["claude-headless"]["models"]["claude-opus-4-7"]
        assert entry["auth_type"] == "http_api"
        assert entry["dispatch_group"] == "operator-custom-group"

    def test_non_headless_custom_provider_still_rejected_with_fix_hint(self, tmp_path):
        root = _write_project_with_custom_provider(
            tmp_path, "my-proxy", "openai_compat",
            {"some-model": _fieldless_model()},
        )
        with pytest.raises(ConfigError, match=r"\[CONFIG-INVALID\].*auth_type") as exc_info:
            load_config(project_root=root)
        # The diagnostic must now tell the operator WHERE to fix it.
        assert ".loa.config.yaml" in str(exc_info.value)

    def test_unknown_type_gets_no_inference(self, tmp_path):
        root = _write_project_with_custom_provider(
            tmp_path, "mystery", "some-future-type",
            {"some-model": _fieldless_model()},
        )
        with pytest.raises(ConfigError, match=r"\[CONFIG-INVALID\].*auth_type"):
            load_config(project_root=root)

    def test_missing_type_gets_no_inference(self, tmp_path):
        root = _write_project_with_custom_provider(
            tmp_path, "typeless", "claude-headless",
            {"some-model": _fieldless_model()},
            include_type=False,
        )
        with pytest.raises(ConfigError, match=r"\[CONFIG-INVALID\].*auth_type"):
            load_config(project_root=root)

    def test_inferred_groups_satisfy_dispatch_group_pattern(self, tmp_path):
        from loa_cheval.config.loader import _DISPATCH_GROUP_PATTERN

        for group in ("anthropic-claude", "openai-gpt", "google-gemini"):
            assert _DISPATCH_GROUP_PATTERN.match(group)
