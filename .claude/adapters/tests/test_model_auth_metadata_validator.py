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
