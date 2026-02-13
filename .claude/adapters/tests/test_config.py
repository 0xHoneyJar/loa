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
    _matches_lazy_path,
    interpolate_config,
    interpolate_value,
    redact_config,
    LazyValue,
    REDACTED,
    _DEFAULT_LAZY_PATHS,
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


# === LazyValue Tests (v1.35.0, FR-1) ===


class TestLazyValue:
    def test_str_triggers_resolution(self):
        with patch.dict(os.environ, {"OPENAI_API_KEY": "sk-test123"}):
            lazy = LazyValue("{env:OPENAI_API_KEY}", "/tmp")
            assert str(lazy) == "sk-test123"

    def test_repr_shows_raw_token(self):
        lazy = LazyValue("{env:OPENAI_API_KEY}", "/tmp")
        assert repr(lazy) == "LazyValue('{env:OPENAI_API_KEY}')"

    def test_resolve_caches_result(self):
        """Second call should return cached value, not re-resolve."""
        with patch.dict(os.environ, {"OPENAI_API_KEY": "sk-first"}):
            lazy = LazyValue("{env:OPENAI_API_KEY}", "/tmp")
            first = lazy.resolve()

        # Even after env var changes, cached value is returned
        with patch.dict(os.environ, {"OPENAI_API_KEY": "sk-second"}):
            second = lazy.resolve()

        assert first == second == "sk-first"

    def test_raw_property(self):
        lazy = LazyValue("{env:OPENAI_API_KEY}", "/tmp")
        assert lazy.raw == "{env:OPENAI_API_KEY}"

    def test_bool_truthy(self):
        lazy = LazyValue("{env:OPENAI_API_KEY}", "/tmp")
        assert bool(lazy) is True

    def test_bool_falsy(self):
        lazy = LazyValue("", "/tmp")
        assert bool(lazy) is False

    def test_eq_with_string(self):
        with patch.dict(os.environ, {"OPENAI_API_KEY": "sk-test123"}):
            lazy = LazyValue("{env:OPENAI_API_KEY}", "/tmp")
            assert lazy == "sk-test123"

    def test_eq_with_lazy_value(self):
        lazy1 = LazyValue("{env:OPENAI_API_KEY}", "/tmp")
        lazy2 = LazyValue("{env:OPENAI_API_KEY}", "/tmp")
        lazy3 = LazyValue("{env:ANTHROPIC_API_KEY}", "/tmp")
        assert lazy1 == lazy2
        assert lazy1 != lazy3

    def test_hash(self):
        lazy1 = LazyValue("{env:OPENAI_API_KEY}", "/tmp")
        lazy2 = LazyValue("{env:OPENAI_API_KEY}", "/tmp")
        assert hash(lazy1) == hash(lazy2)

    def test_missing_env_error_with_context(self):
        with patch.dict(os.environ, {}, clear=True):
            lazy = LazyValue(
                "{env:OPENAI_API_KEY}", "/tmp",
                context={"provider": "openai", "agent": "gpt-reviewer"},
            )
            with pytest.raises(ConfigError, match="provider 'openai'"):
                lazy.resolve()

    def test_missing_env_error_includes_hint(self):
        with patch.dict(os.environ, {}, clear=True):
            lazy = LazyValue(
                "{env:OPENAI_API_KEY}", "/tmp",
                context={"provider": "openai"},
            )
            with pytest.raises(ConfigError, match="/loa-credentials set OPENAI_API_KEY"):
                lazy.resolve()


class TestLazyPathMatching:
    def test_exact_match(self):
        assert _matches_lazy_path("providers.openai.auth", {"providers.*.auth"}) is True

    def test_no_match(self):
        assert _matches_lazy_path("providers.openai.endpoint", {"providers.*.auth"}) is False

    def test_wildcard_matches_any_provider(self):
        assert _matches_lazy_path("providers.anthropic.auth", {"providers.*.auth"}) is True
        assert _matches_lazy_path("providers.moonshot.auth", {"providers.*.auth"}) is True

    def test_non_provider_key(self):
        assert _matches_lazy_path("aliases.opus", {"providers.*.auth"}) is False

    def test_empty_lazy_paths(self):
        assert _matches_lazy_path("providers.openai.auth", set()) is False


class TestLazyInterpolation:
    def test_auth_fields_become_lazy(self):
        config = {
            "providers": {
                "openai": {
                    "endpoint": "https://api.openai.com/v1",
                    "auth": "{env:OPENAI_API_KEY}",
                },
            },
        }
        with patch.dict(os.environ, {}, clear=True):
            # Should NOT raise — auth is lazy
            result = interpolate_config(config, "/tmp")
            assert isinstance(result["providers"]["openai"]["auth"], LazyValue)
            # Endpoint is NOT lazy — but doesn't contain interpolation tokens here
            assert result["providers"]["openai"]["endpoint"] == "https://api.openai.com/v1"

    def test_lazy_auth_resolves_on_str(self):
        config = {
            "providers": {
                "openai": {
                    "auth": "{env:OPENAI_API_KEY}",
                },
            },
        }
        with patch.dict(os.environ, {}, clear=True):
            result = interpolate_config(config, "/tmp")
            lazy_auth = result["providers"]["openai"]["auth"]
            assert isinstance(lazy_auth, LazyValue)

        # Now set the env var and resolve
        with patch.dict(os.environ, {"OPENAI_API_KEY": "sk-test123"}):
            assert str(lazy_auth) == "sk-test123"

    def test_non_auth_fields_resolve_eagerly(self):
        config = {
            "providers": {
                "openai": {
                    "endpoint": "{env:LOA_OPENAI_ENDPOINT}",
                    "auth": "{env:OPENAI_API_KEY}",
                },
            },
        }
        with patch.dict(os.environ, {"LOA_OPENAI_ENDPOINT": "https://custom.api.com"}, clear=True):
            result = interpolate_config(config, "/tmp")
            # endpoint resolves eagerly
            assert result["providers"]["openai"]["endpoint"] == "https://custom.api.com"
            # auth is lazy
            assert isinstance(result["providers"]["openai"]["auth"], LazyValue)

    def test_multiple_providers_independent(self):
        """Missing env for one provider should not affect another."""
        config = {
            "providers": {
                "openai": {"auth": "{env:OPENAI_API_KEY}"},
                "anthropic": {"auth": "{env:ANTHROPIC_API_KEY}"},
            },
        }
        with patch.dict(os.environ, {}, clear=True):
            result = interpolate_config(config, "/tmp")
            assert isinstance(result["providers"]["openai"]["auth"], LazyValue)
            assert isinstance(result["providers"]["anthropic"]["auth"], LazyValue)

        # Only set openai key — anthropic stays unresolvable
        with patch.dict(os.environ, {"OPENAI_API_KEY": "sk-oai"}):
            assert str(result["providers"]["openai"]["auth"]) == "sk-oai"

        with patch.dict(os.environ, {}, clear=True):
            with pytest.raises(ConfigError):
                str(result["providers"]["anthropic"]["auth"])

    def test_lazy_disabled_with_empty_set(self):
        config = {
            "providers": {
                "openai": {"auth": "{env:OPENAI_API_KEY}"},
            },
        }
        with patch.dict(os.environ, {}, clear=True):
            with pytest.raises(ConfigError, match="not set"):
                interpolate_config(config, "/tmp", lazy_paths=set())

    def test_lazy_config_with_all_env_set(self):
        """When all env vars are set, lazy behavior is invisible."""
        config = {
            "providers": {
                "openai": {"auth": "{env:OPENAI_API_KEY}"},
            },
        }
        with patch.dict(os.environ, {"OPENAI_API_KEY": "sk-test"}):
            result = interpolate_config(config, "/tmp")
            # auth is LazyValue but resolves transparently
            assert str(result["providers"]["openai"]["auth"]) == "sk-test"

    def test_secret_keys_tracked_for_lazy_paths(self):
        config = {
            "providers": {
                "openai": {"auth": "{env:OPENAI_API_KEY}"},
            },
        }
        secret_keys = set()
        with patch.dict(os.environ, {}, clear=True):
            interpolate_config(config, "/tmp", _secret_keys=secret_keys)
            assert "auth" in secret_keys


class TestLazyRedaction:
    def test_redact_config_handles_lazy_value(self):
        lazy = LazyValue("{env:OPENAI_API_KEY}", "/tmp")
        config = {"providers": {"openai": {"auth": lazy, "name": "openai"}}}
        result = redact_config(config)
        assert REDACTED in result["providers"]["openai"]["auth"]
        assert "lazy" in result["providers"]["openai"]["auth"]
        assert "OPENAI_API_KEY" in result["providers"]["openai"]["auth"]
        assert result["providers"]["openai"]["name"] == "openai"

    def test_redact_does_not_resolve_lazy(self):
        """Redacting a LazyValue with missing env var should NOT raise."""
        with patch.dict(os.environ, {}, clear=True):
            lazy = LazyValue("{env:OPENAI_API_KEY}", "/tmp")
            config = {"auth": lazy}
            # Should not raise — redaction reads .raw, not .resolve()
            result = redact_config(config)
            assert REDACTED in result["auth"]

    def test_redact_config_value_handles_lazy(self):
        from loa_cheval.config.redaction import redact_config_value
        lazy = LazyValue("{env:OPENAI_API_KEY}", "/tmp")
        result = redact_config_value("auth", lazy)
        assert REDACTED in result
        assert "lazy" in result
