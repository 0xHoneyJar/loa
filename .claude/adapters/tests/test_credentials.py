"""Tests for credential provider chain (SDD §4.1.4, #300)."""

import json
import os
import stat
import sys
import tempfile
from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest

# Add adapters dir to path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.credentials.providers import (
    CompositeProvider,
    CredentialProvider,
    DotenvProvider,
    EnvProvider,
    get_credential_provider,
)
from loa_cheval.credentials.health import (
    HEALTH_CHECKS,
    HealthResult,
    check_credential,
    check_all,
)
from loa_cheval.config.interpolation import (
    _reset_credential_provider,
    interpolate_value,
)
from loa_cheval.types import ConfigError


# === EnvProvider Tests ===


class TestEnvProvider:
    def test_reads_existing_var(self):
        with patch.dict(os.environ, {"OPENAI_API_KEY": "sk-test"}):
            p = EnvProvider()
            assert p.get("OPENAI_API_KEY") == "sk-test"

    def test_returns_none_for_missing(self):
        with patch.dict(os.environ, {}, clear=True):
            p = EnvProvider()
            assert p.get("OPENAI_API_KEY") is None

    def test_name(self):
        assert EnvProvider().name() == "environment"


# === DotenvProvider Tests ===


class TestDotenvProvider:
    def test_reads_key_value(self, tmp_path):
        (tmp_path / ".env.local").write_text("OPENAI_API_KEY=sk-test123\n")
        p = DotenvProvider(str(tmp_path))
        assert p.get("OPENAI_API_KEY") == "sk-test123"

    def test_strips_double_quotes(self, tmp_path):
        (tmp_path / ".env.local").write_text('OPENAI_API_KEY="sk-quoted"\n')
        p = DotenvProvider(str(tmp_path))
        assert p.get("OPENAI_API_KEY") == "sk-quoted"

    def test_strips_single_quotes(self, tmp_path):
        (tmp_path / ".env.local").write_text("OPENAI_API_KEY='sk-single'\n")
        p = DotenvProvider(str(tmp_path))
        assert p.get("OPENAI_API_KEY") == "sk-single"

    def test_ignores_comments(self, tmp_path):
        (tmp_path / ".env.local").write_text("# Comment\nOPENAI_API_KEY=sk-val\n")
        p = DotenvProvider(str(tmp_path))
        assert p.get("OPENAI_API_KEY") == "sk-val"

    def test_ignores_blank_lines(self, tmp_path):
        (tmp_path / ".env.local").write_text("\n\nOPENAI_API_KEY=sk-val\n\n")
        p = DotenvProvider(str(tmp_path))
        assert p.get("OPENAI_API_KEY") == "sk-val"

    def test_handles_export_prefix(self, tmp_path):
        (tmp_path / ".env.local").write_text("export OPENAI_API_KEY=sk-export\n")
        p = DotenvProvider(str(tmp_path))
        assert p.get("OPENAI_API_KEY") == "sk-export"

    def test_returns_none_for_missing_key(self, tmp_path):
        (tmp_path / ".env.local").write_text("OTHER_KEY=val\n")
        p = DotenvProvider(str(tmp_path))
        assert p.get("OPENAI_API_KEY") is None

    def test_returns_none_when_file_missing(self, tmp_path):
        p = DotenvProvider(str(tmp_path))
        assert p.get("OPENAI_API_KEY") is None

    def test_multiple_keys(self, tmp_path):
        (tmp_path / ".env.local").write_text(
            "OPENAI_API_KEY=sk-oai\nANTHROPIC_API_KEY=sk-ant\n"
        )
        p = DotenvProvider(str(tmp_path))
        assert p.get("OPENAI_API_KEY") == "sk-oai"
        assert p.get("ANTHROPIC_API_KEY") == "sk-ant"

    def test_name(self, tmp_path):
        p = DotenvProvider(str(tmp_path))
        assert "dotenv" in p.name()


# === CompositeProvider Tests ===


class TestCompositeProvider:
    def test_env_wins_over_dotenv(self, tmp_path):
        (tmp_path / ".env.local").write_text("OPENAI_API_KEY=sk-dotenv\n")
        with patch.dict(os.environ, {"OPENAI_API_KEY": "sk-env"}):
            composite = CompositeProvider([
                EnvProvider(),
                DotenvProvider(str(tmp_path)),
            ])
            assert composite.get("OPENAI_API_KEY") == "sk-env"

    def test_falls_through_to_dotenv(self, tmp_path):
        (tmp_path / ".env.local").write_text("OPENAI_API_KEY=sk-dotenv\n")
        with patch.dict(os.environ, {}, clear=True):
            composite = CompositeProvider([
                EnvProvider(),
                DotenvProvider(str(tmp_path)),
            ])
            assert composite.get("OPENAI_API_KEY") == "sk-dotenv"

    def test_returns_none_when_all_miss(self, tmp_path):
        with patch.dict(os.environ, {}, clear=True):
            composite = CompositeProvider([
                EnvProvider(),
                DotenvProvider(str(tmp_path)),
            ])
            assert composite.get("NONEXISTENT") is None

    def test_providers_property(self):
        providers = [EnvProvider(), EnvProvider()]
        composite = CompositeProvider(providers)
        assert len(composite.providers) == 2

    def test_name_shows_chain(self, tmp_path):
        composite = CompositeProvider([
            EnvProvider(),
            DotenvProvider(str(tmp_path)),
        ])
        name = composite.name()
        assert "environment" in name
        assert "dotenv" in name


# === EncryptedStore Tests ===


def _has_cryptography():
    try:
        import cryptography  # noqa: F401
        return True
    except ImportError:
        return False


@pytest.mark.skipif(not _has_cryptography(), reason="cryptography package not installed")
class TestEncryptedStore:
    """Tests for encrypted credential store.

    These tests only run if cryptography is installed.
    """

    @pytest.fixture
    def store_dir(self, tmp_path):
        return tmp_path / "cred_store"

    def _make_store(self, store_dir):
        from loa_cheval.credentials.store import EncryptedStore
        return EncryptedStore(store_dir)

    def test_set_and_get(self, store_dir):
        store = self._make_store(store_dir)
        store.set("OPENAI_API_KEY", "sk-test123")
        assert store.get("OPENAI_API_KEY") == "sk-test123"

    def test_get_returns_none_for_missing(self, store_dir):
        store = self._make_store(store_dir)
        assert store.get("NONEXISTENT") is None

    def test_delete(self, store_dir):
        store = self._make_store(store_dir)
        store.set("KEY", "val")
        assert store.delete("KEY") is True
        assert store.get("KEY") is None

    def test_delete_nonexistent(self, store_dir):
        store = self._make_store(store_dir)
        assert store.delete("NOPE") is False

    def test_list_keys(self, store_dir):
        store = self._make_store(store_dir)
        store.set("KEY_A", "a")
        store.set("KEY_B", "b")
        keys = store.list_keys()
        assert set(keys) == {"KEY_A", "KEY_B"}

    def test_directory_permissions(self, store_dir):
        store = self._make_store(store_dir)
        store.set("KEY", "val")
        mode = stat.S_IMODE(store_dir.stat().st_mode)
        assert mode == 0o700

    def test_store_file_permissions(self, store_dir):
        store = self._make_store(store_dir)
        store.set("KEY", "val")
        enc_file = store_dir / "store.json.enc"
        mode = stat.S_IMODE(enc_file.stat().st_mode)
        assert mode == 0o600

    def test_key_file_permissions(self, store_dir):
        store = self._make_store(store_dir)
        store.set("KEY", "val")
        key_file = store_dir / ".key"
        mode = stat.S_IMODE(key_file.stat().st_mode)
        assert mode == 0o600

    def test_corrupted_store_recovery(self, store_dir):
        store = self._make_store(store_dir)
        store.set("KEY", "val")
        # Corrupt the file
        (store_dir / "store.json.enc").write_bytes(b"corrupt data")
        # Fresh instance should recover gracefully
        store2 = self._make_store(store_dir)
        assert store2.get("KEY") is None


# === EncryptedFileProvider Tests ===


class TestEncryptedFileProvider:
    def test_returns_none_without_cryptography(self, tmp_path):
        from loa_cheval.credentials.store import EncryptedFileProvider
        provider = EncryptedFileProvider(tmp_path / "nonexistent")
        # Should not raise even if store can't initialize
        result = provider.get("OPENAI_API_KEY")
        assert result is None

    def test_name(self, tmp_path):
        from loa_cheval.credentials.store import EncryptedFileProvider
        provider = EncryptedFileProvider(tmp_path)
        assert "encrypted" in provider.name()


# === Factory Tests ===


class TestGetCredentialProvider:
    def test_returns_composite(self, tmp_path):
        provider = get_credential_provider(str(tmp_path))
        assert isinstance(provider, CompositeProvider)

    def test_chain_includes_env(self, tmp_path):
        provider = get_credential_provider(str(tmp_path))
        names = [p.name() for p in provider.providers]
        assert any("environment" in n for n in names)

    def test_chain_includes_dotenv(self, tmp_path):
        provider = get_credential_provider(str(tmp_path))
        names = [p.name() for p in provider.providers]
        assert any("dotenv" in n for n in names)


# === Health Check Tests ===


class TestHealthChecks:
    def test_known_credentials_have_checks(self):
        assert "OPENAI_API_KEY" in HEALTH_CHECKS
        assert "ANTHROPIC_API_KEY" in HEALTH_CHECKS

    def test_unknown_credential_skipped(self):
        result = check_credential("UNKNOWN_KEY", "val")
        assert result.status == "skipped"

    def test_check_all_with_missing_keys(self, tmp_path):
        with patch.dict(os.environ, {}, clear=True):
            provider = CompositeProvider([
                EnvProvider(),
                DotenvProvider(str(tmp_path)),
            ])
            results = check_all(provider)
            for r in results:
                assert r.status == "missing"

    def test_health_result_namedtuple(self):
        r = HealthResult("KEY", "ok", "msg")
        assert r.credential_id == "KEY"
        assert r.status == "ok"
        assert r.message == "msg"


# === Interpolation Integration Tests ===


class TestInterpolationWithCredentialChain:
    """Test that interpolate_value uses the credential provider chain."""

    def setup_method(self):
        _reset_credential_provider()

    def teardown_method(self):
        _reset_credential_provider()

    def test_env_var_still_works(self):
        with patch.dict(os.environ, {"OPENAI_API_KEY": "sk-env"}):
            result = interpolate_value("{env:OPENAI_API_KEY}", "/tmp")
            assert result == "sk-env"

    def test_dotenv_fallback(self, tmp_path):
        """When env var is missing, falls through to .env.local."""
        dotenv = tmp_path / ".env.local"
        dotenv.write_text("OPENAI_API_KEY=sk-dotenv-val\n")

        test_provider = CompositeProvider([
            EnvProvider(),
            DotenvProvider(str(tmp_path)),
        ])
        with patch.dict(os.environ, {}, clear=True), \
             patch("loa_cheval.config.interpolation._get_credential_provider", return_value=test_provider):
            result = interpolate_value("{env:OPENAI_API_KEY}", str(tmp_path))
            assert result == "sk-dotenv-val"

    def test_env_wins_over_dotenv(self, tmp_path):
        """Env var has higher priority than .env.local."""
        dotenv = tmp_path / ".env.local"
        dotenv.write_text("OPENAI_API_KEY=sk-dotenv-val\n")

        test_provider = CompositeProvider([
            EnvProvider(),
            DotenvProvider(str(tmp_path)),
        ])
        with patch.dict(os.environ, {"OPENAI_API_KEY": "sk-env-val"}), \
             patch("loa_cheval.config.interpolation._get_credential_provider", return_value=test_provider):
            result = interpolate_value("{env:OPENAI_API_KEY}", str(tmp_path))
            assert result == "sk-env-val"

    def test_missing_everywhere_raises(self, tmp_path):
        """When credential is not in any provider, raises ConfigError."""
        test_provider = CompositeProvider([
            EnvProvider(),
            DotenvProvider(str(tmp_path)),
        ])
        with patch.dict(os.environ, {}, clear=True), \
             patch("loa_cheval.config.interpolation._get_credential_provider", return_value=test_provider):
            with pytest.raises(ConfigError, match="not set"):
                interpolate_value("{env:OPENAI_API_KEY}", str(tmp_path))
