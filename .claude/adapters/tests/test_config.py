"""Tests for config merge pipeline and interpolation (SDD §4.1.1, §4.1.3)."""

import os
import sys
import tempfile
from pathlib import Path
from unittest.mock import patch

import pytest

# Add adapters dir to path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.config.loader import (
    _deep_merge,
    _flatten_keys,
    apply_cli_overrides,
    clear_config_cache,
    load_env_overrides,
    load_config,
)
from loa_cheval.config.interpolation import (
    _check_env_allowed,
    interpolate_value,
    redact_config,
    REDACTED,
)
from loa_cheval.types import ConfigError


class TestDeepMerge:
    def test_flat_merge(self):
        base = {"a": 1, "b": 2}
        overlay = {"b": 3, "c": 4}
        result = _deep_merge(base, overlay)
        assert result == {"a": 1, "b": 3, "c": 4}

    def test_nested_merge(self):
        base = {"a": {"x": 1, "y": 2}}
        overlay = {"a": {"y": 3, "z": 4}}
        result = _deep_merge(base, overlay)
        assert result == {"a": {"x": 1, "y": 3, "z": 4}}

    def test_overlay_replaces_non_dict(self):
        base = {"a": {"x": 1}}
        overlay = {"a": "replaced"}
        result = _deep_merge(base, overlay)
        assert result == {"a": "replaced"}

    def test_no_mutation_of_base(self):
        base = {"a": {"x": 1}}
        overlay = {"a": {"y": 2}}
        _deep_merge(base, overlay)
        assert base == {"a": {"x": 1}}


class TestFlattenKeys:
    def test_flat_dict(self):
        keys = _flatten_keys({"a": 1, "b": 2})
        assert set(keys) == {"a", "b"}

    def test_nested_dict(self):
        keys = _flatten_keys({"a": {"x": 1, "y": 2}})
        assert set(keys) == {"a", "a.x", "a.y"}


class TestEnvOverrides:
    def test_no_env_set(self):
        with patch.dict(os.environ, {}, clear=True):
            result = load_env_overrides()
            assert result == {}

    def test_loa_model_set(self):
        with patch.dict(os.environ, {"LOA_MODEL": "openai:gpt-5.2"}):
            result = load_env_overrides()
            assert result == {"env_model_override": "openai:gpt-5.2"}


class TestCliOverrides:
    def test_model_override(self):
        config = {"existing": "value"}
        result = apply_cli_overrides(config, {"model": "anthropic:claude-opus-4-6"})
        assert result["cli_model_override"] == "anthropic:claude-opus-4-6"

    def test_timeout_override(self):
        config = {}
        result = apply_cli_overrides(config, {"timeout": 300})
        assert result["defaults"]["timeout"] == 300

    def test_none_values_ignored(self):
        config = {"existing": "value"}
        result = apply_cli_overrides(config, {"model": None})
        assert "cli_model_override" not in result


class TestEnvAllowlist:
    def test_loa_prefix_allowed(self):
        assert _check_env_allowed("LOA_MODEL") is True
        assert _check_env_allowed("LOA_ANYTHING") is True

    def test_openai_key_allowed(self):
        assert _check_env_allowed("OPENAI_API_KEY") is True

    def test_anthropic_key_allowed(self):
        assert _check_env_allowed("ANTHROPIC_API_KEY") is True

    def test_moonshot_key_allowed(self):
        assert _check_env_allowed("MOONSHOT_API_KEY") is True

    def test_random_var_rejected(self):
        assert _check_env_allowed("PATH") is False
        assert _check_env_allowed("HOME") is False
        assert _check_env_allowed("AWS_SECRET_KEY") is False

    def test_extra_patterns(self):
        import re
        extra = [re.compile(r"^CUSTOM_")]
        assert _check_env_allowed("CUSTOM_VAR", extra) is True
        assert _check_env_allowed("OTHER_VAR", extra) is False


class TestInterpolation:
    def test_env_interpolation(self):
        with patch.dict(os.environ, {"OPENAI_API_KEY": "sk-test123"}):
            result = interpolate_value("{env:OPENAI_API_KEY}", "/tmp")
            assert result == "sk-test123"

    def test_env_not_set(self):
        with patch.dict(os.environ, {}, clear=True):
            with pytest.raises(ConfigError, match="not set"):
                interpolate_value("{env:OPENAI_API_KEY}", "/tmp")

    def test_env_not_allowed(self):
        with pytest.raises(ConfigError, match="not in the allowlist"):
            interpolate_value("{env:PATH}", "/tmp")

    def test_cmd_disabled_by_default(self):
        with pytest.raises(ConfigError, match="disabled"):
            interpolate_value("{cmd:echo hello}", "/tmp")

    def test_file_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            real_file = Path(tmpdir) / "real.txt"
            real_file.write_text("secret")
            os.chmod(str(real_file), 0o600)

            link_file = Path(tmpdir) / "link.txt"
            link_file.symlink_to(real_file)

            with pytest.raises(ConfigError, match="symlink"):
                interpolate_value(
                    f"{{file:{link_file}}}",
                    "/tmp",
                    allowed_file_dirs=[tmpdir],
                )


class TestRedaction:
    def test_auth_key_redacted(self):
        config = {"auth": "sk-real-key-value", "name": "openai"}
        result = redact_config(config)
        assert result["auth"] == REDACTED
        assert result["name"] == "openai"

    def test_secret_suffix_redacted(self):
        config = {"api_secret": "my-secret", "name": "test"}
        result = redact_config(config)
        assert result["api_secret"] == REDACTED

    def test_nested_redaction(self):
        config = {"providers": {"openai": {"auth": "sk-key"}}}
        result = redact_config(config)
        assert result["providers"]["openai"]["auth"] == REDACTED

    def test_interpolation_token_redacted(self):
        config = {"auth": "{env:OPENAI_API_KEY}"}
        result = redact_config(config)
        assert REDACTED in result["auth"]
        assert "OPENAI_API_KEY" in result["auth"]
