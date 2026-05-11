"""T1.5 (cycle-103 sprint-1) — `--mock-fixture-dir` flag for cheval.py.

Tests cover the AC-1.2 substrate that lets BB delegate tests serve a
pre-recorded CompletionResult instead of dispatching to the real provider.

Test taxonomy:
- happy path: response.json + per-provider fixture precedence
- normalization (IMP-006): latency_ms / interaction_id / usage.source defaults
- error paths: missing dir, no fixture file, malformed JSON, missing fields
- path-traversal defense: fixture path must stay inside the directory
- argparse: flag is registered and threaded through to cmd_invoke
"""

from __future__ import annotations

import json
import sys
import types
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import cheval  # type: ignore[import-not-found]
from loa_cheval.types import (
    CompletionResult,
    InvalidInputError,
    Usage,
)


# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------


def _write_fixture(dir_path: Path, name: str, payload: dict) -> Path:
    p = dir_path / name
    p.write_text(json.dumps(payload), encoding="utf-8")
    return p


def _make_args(tmp_path: Path, *, mock_fixture_dir: str | None = None) -> object:
    args = types.SimpleNamespace()
    args.agent = "flatline-reviewer"
    args.input = None
    args.prompt = "test prompt"
    args.system = None
    args.model = None
    args.max_tokens = 4096
    args.max_input_tokens = None
    args.output_format = "json"
    args.json_errors = True
    args.timeout = 30
    args.include_thinking = False
    args.async_mode = False
    args.poll_id = None
    args.cancel_id = None
    args.dry_run = False
    args.print_config = False
    args.validate_bindings = False
    args.mock_fixture_dir = mock_fixture_dir
    return args


def _make_resolved(provider: str = "anthropic", model_id: str = "claude-opus-4-7"):
    return MagicMock(provider=provider, model_id=model_id)


def _make_minimal_config(provider: str = "anthropic", model_id: str = "claude-opus-4-7") -> dict:
    return {
        "providers": {
            provider: {
                "type": provider,
                "endpoint": "https://api.example.invalid/v1/messages",
                "auth": "dummy",
                "models": {
                    model_id: {
                        "capabilities": ["chat"],
                        "context_window": 200000,
                    },
                },
            },
        },
        "feature_flags": {"metering": False},
    }


# ----------------------------------------------------------------------------
# Direct helper tests — _load_mock_fixture_response
# ----------------------------------------------------------------------------


class TestLoadMockFixtureResponse:
    def test_loads_response_json_fallback(self, tmp_path: Path) -> None:
        _write_fixture(tmp_path, "response.json", {
            "content": "## Summary\nLooks good.",
            "usage": {"input_tokens": 1500, "output_tokens": 200},
        })
        result = cheval._load_mock_fixture_response(
            str(tmp_path), "anthropic", "claude-opus-4-7"
        )
        assert isinstance(result, CompletionResult)
        assert result.content == "## Summary\nLooks good."
        assert result.usage.input_tokens == 1500
        assert result.usage.output_tokens == 200
        # Defaults from the resolved binding when fixture omits them.
        assert result.model == "claude-opus-4-7"
        assert result.provider == "anthropic"

    def test_per_provider_fixture_wins_over_response_json(self, tmp_path: Path) -> None:
        _write_fixture(tmp_path, "response.json", {
            "content": "fallback",
            "usage": {"input_tokens": 1, "output_tokens": 1},
        })
        _write_fixture(tmp_path, "anthropic__claude-opus-4-7.json", {
            "content": "per-provider",
            "usage": {"input_tokens": 100, "output_tokens": 50},
        })
        result = cheval._load_mock_fixture_response(
            str(tmp_path), "anthropic", "claude-opus-4-7"
        )
        assert result.content == "per-provider"
        assert result.usage.input_tokens == 100

    def test_model_id_with_colon_sanitized_in_filename(self, tmp_path: Path) -> None:
        _write_fixture(tmp_path, "openai__gpt-5.5-pro.json", {
            "content": "ok",
            "usage": {"input_tokens": 1, "output_tokens": 1},
        })
        result = cheval._load_mock_fixture_response(
            str(tmp_path), "openai", "gpt-5.5-pro"
        )
        assert result.content == "ok"

    def test_imp006_normalization_latency_ms_defaults_to_zero(self, tmp_path: Path) -> None:
        _write_fixture(tmp_path, "response.json", {
            "content": "ok",
            "usage": {"input_tokens": 1, "output_tokens": 1},
        })
        result = cheval._load_mock_fixture_response(
            str(tmp_path), "anthropic", "claude-opus-4-7"
        )
        assert result.latency_ms == 0

    def test_imp006_normalization_interaction_id_defaults_to_none(self, tmp_path: Path) -> None:
        _write_fixture(tmp_path, "response.json", {
            "content": "ok",
            "usage": {"input_tokens": 1, "output_tokens": 1},
        })
        result = cheval._load_mock_fixture_response(
            str(tmp_path), "anthropic", "claude-opus-4-7"
        )
        assert result.interaction_id is None

    def test_imp006_normalization_usage_source_is_actual(self, tmp_path: Path) -> None:
        _write_fixture(tmp_path, "response.json", {
            "content": "ok",
            "usage": {"input_tokens": 1, "output_tokens": 1},
        })
        result = cheval._load_mock_fixture_response(
            str(tmp_path), "anthropic", "claude-opus-4-7"
        )
        assert result.usage.source == "actual"

    def test_fixture_overrides_normalized_defaults_when_present(self, tmp_path: Path) -> None:
        _write_fixture(tmp_path, "response.json", {
            "content": "ok",
            "usage": {"input_tokens": 1, "output_tokens": 1, "reasoning_tokens": 7},
            "latency_ms": 8421,
            "interaction_id": "inter-fixture-001",
            "model": "claude-fixture-pin",
            "provider": "fixture-pinned",
        })
        result = cheval._load_mock_fixture_response(
            str(tmp_path), "anthropic", "claude-opus-4-7"
        )
        assert result.latency_ms == 8421
        assert result.interaction_id == "inter-fixture-001"
        assert result.usage.reasoning_tokens == 7
        # Fixture pins overrride resolved binding when present.
        assert result.model == "claude-fixture-pin"
        assert result.provider == "fixture-pinned"

    def test_mock_fixture_metadata_attached(self, tmp_path: Path) -> None:
        path = _write_fixture(tmp_path, "response.json", {
            "content": "ok",
            "usage": {"input_tokens": 1, "output_tokens": 1},
        })
        result = cheval._load_mock_fixture_response(
            str(tmp_path), "anthropic", "claude-opus-4-7"
        )
        assert result.metadata.get("mock_fixture") is True
        assert result.metadata.get("fixture_path") == str(path.resolve())

    # ---- Error paths ----

    def test_dir_does_not_exist_raises(self, tmp_path: Path) -> None:
        missing = tmp_path / "nope"
        with pytest.raises(InvalidInputError, match="does not exist"):
            cheval._load_mock_fixture_response(str(missing), "anthropic", "claude-opus-4-7")

    def test_no_matching_fixture_raises(self, tmp_path: Path) -> None:
        with pytest.raises(InvalidInputError, match="no fixture found"):
            cheval._load_mock_fixture_response(str(tmp_path), "anthropic", "claude-opus-4-7")

    def test_malformed_json_raises(self, tmp_path: Path) -> None:
        (tmp_path / "response.json").write_text("{not json", encoding="utf-8")
        with pytest.raises(InvalidInputError, match="not valid JSON"):
            cheval._load_mock_fixture_response(str(tmp_path), "anthropic", "claude-opus-4-7")

    def test_top_level_array_rejected(self, tmp_path: Path) -> None:
        (tmp_path / "response.json").write_text("[1,2,3]", encoding="utf-8")
        with pytest.raises(InvalidInputError, match="must be a JSON object"):
            cheval._load_mock_fixture_response(str(tmp_path), "anthropic", "claude-opus-4-7")

    def test_missing_content_field_raises(self, tmp_path: Path) -> None:
        _write_fixture(tmp_path, "response.json", {
            "usage": {"input_tokens": 1, "output_tokens": 1},
        })
        with pytest.raises(InvalidInputError, match="required string `content`"):
            cheval._load_mock_fixture_response(str(tmp_path), "anthropic", "claude-opus-4-7")

    def test_content_not_string_raises(self, tmp_path: Path) -> None:
        _write_fixture(tmp_path, "response.json", {
            "content": ["array", "not", "string"],
            "usage": {"input_tokens": 1, "output_tokens": 1},
        })
        with pytest.raises(InvalidInputError, match="required string `content`"):
            cheval._load_mock_fixture_response(str(tmp_path), "anthropic", "claude-opus-4-7")

    def test_usage_must_be_object(self, tmp_path: Path) -> None:
        _write_fixture(tmp_path, "response.json", {
            "content": "ok",
            "usage": "not-an-object",
        })
        with pytest.raises(InvalidInputError, match="`usage` must be an object"):
            cheval._load_mock_fixture_response(str(tmp_path), "anthropic", "claude-opus-4-7")

    def test_usage_tokens_non_integer_raises(self, tmp_path: Path) -> None:
        _write_fixture(tmp_path, "response.json", {
            "content": "ok",
            "usage": {"input_tokens": "not-a-number", "output_tokens": 1},
        })
        with pytest.raises(InvalidInputError, match="token counts must be integers"):
            cheval._load_mock_fixture_response(str(tmp_path), "anthropic", "claude-opus-4-7")

    def test_interaction_id_non_string_raises(self, tmp_path: Path) -> None:
        _write_fixture(tmp_path, "response.json", {
            "content": "ok",
            "usage": {"input_tokens": 1, "output_tokens": 1},
            "interaction_id": 12345,
        })
        with pytest.raises(InvalidInputError, match="`interaction_id` must be a string"):
            cheval._load_mock_fixture_response(str(tmp_path), "anthropic", "claude-opus-4-7")

    def test_tool_calls_non_list_raises(self, tmp_path: Path) -> None:
        _write_fixture(tmp_path, "response.json", {
            "content": "ok",
            "usage": {"input_tokens": 1, "output_tokens": 1},
            "tool_calls": "not-a-list",
        })
        with pytest.raises(InvalidInputError, match="`tool_calls` must be a list"):
            cheval._load_mock_fixture_response(str(tmp_path), "anthropic", "claude-opus-4-7")

    def test_thinking_non_string_raises(self, tmp_path: Path) -> None:
        _write_fixture(tmp_path, "response.json", {
            "content": "ok",
            "usage": {"input_tokens": 1, "output_tokens": 1},
            "thinking": ["not", "a", "string"],
        })
        with pytest.raises(InvalidInputError, match="`thinking` must be a string"):
            cheval._load_mock_fixture_response(str(tmp_path), "anthropic", "claude-opus-4-7")

    # ---- Path traversal defense ----

    def test_symlink_escaping_dir_is_not_followed(self, tmp_path: Path) -> None:
        """A symlink pointing outside the fixture dir must not be followed."""
        outside = tmp_path / "outside.json"
        outside.write_text(json.dumps({
            "content": "secret-leaked",
            "usage": {"input_tokens": 1, "output_tokens": 1},
        }), encoding="utf-8")

        fixture_dir = tmp_path / "fixtures"
        fixture_dir.mkdir()
        # response.json inside fixture_dir is a symlink that targets ../outside.json
        # The containment guard must reject the resolved path (outside fixture_dir).
        try:
            (fixture_dir / "response.json").symlink_to(outside)
        except (OSError, NotImplementedError):
            pytest.skip("symlinks not supported on this platform")

        with pytest.raises(InvalidInputError, match="no fixture found"):
            cheval._load_mock_fixture_response(
                str(fixture_dir), "anthropic", "claude-opus-4-7"
            )


# ----------------------------------------------------------------------------
# cmd_invoke end-to-end through cheval CLI
# ----------------------------------------------------------------------------


class TestCmdInvokeWithMockFixtureDir:
    def test_happy_path_returns_success_and_emits_json(
        self, tmp_path: Path, capsys, monkeypatch
    ) -> None:
        _write_fixture(tmp_path, "response.json", {
            "content": "## Findings\n- one\n- two",
            "usage": {"input_tokens": 1500, "output_tokens": 200},
        })

        fake_resolved = _make_resolved()
        fake_binding = MagicMock(temperature=0.7, capability_class=None)
        fake_provider_cfg = MagicMock()
        fake_adapter = MagicMock()

        with patch.object(cheval, "load_config",
                          return_value=(_make_minimal_config(), {})), \
             patch.object(cheval, "resolve_execution",
                          return_value=(fake_binding, fake_resolved)), \
             patch.object(cheval, "_build_provider_config",
                          return_value=fake_provider_cfg), \
             patch.object(cheval, "get_adapter", return_value=fake_adapter):

            args = _make_args(tmp_path, mock_fixture_dir=str(tmp_path))
            exit_code = cheval.cmd_invoke(args)

        captured = capsys.readouterr()
        assert exit_code == cheval.EXIT_CODES["SUCCESS"], (
            f"Expected SUCCESS, got {exit_code}. stderr:\n{captured.err}"
        )

        # The real adapter must NOT have been called — the fixture bypassed it.
        fake_adapter.complete.assert_not_called()

        # Stdout JSON output.
        payload = json.loads(captured.out.strip())
        assert payload["content"] == "## Findings\n- one\n- two"
        assert payload["usage"]["input_tokens"] == 1500
        assert payload["usage"]["output_tokens"] == 200
        assert payload["provider"] == "anthropic"
        assert payload["model"] == "claude-opus-4-7"

    def test_missing_fixture_returns_invalid_input(
        self, tmp_path: Path, capsys
    ) -> None:
        fake_resolved = _make_resolved()
        fake_binding = MagicMock(temperature=0.7, capability_class=None)
        fake_adapter = MagicMock()

        with patch.object(cheval, "load_config",
                          return_value=(_make_minimal_config(), {})), \
             patch.object(cheval, "resolve_execution",
                          return_value=(fake_binding, fake_resolved)), \
             patch.object(cheval, "_build_provider_config",
                          return_value=MagicMock()), \
             patch.object(cheval, "get_adapter", return_value=fake_adapter):

            args = _make_args(tmp_path, mock_fixture_dir=str(tmp_path))
            exit_code = cheval.cmd_invoke(args)

        captured = capsys.readouterr()
        assert exit_code == cheval.EXIT_CODES["INVALID_INPUT"]
        assert "no fixture found" in captured.err
        fake_adapter.complete.assert_not_called()


# ----------------------------------------------------------------------------
# argparse — flag is registered
# ----------------------------------------------------------------------------


class TestArgparseRegistration:
    def test_flag_is_registered(self, monkeypatch, tmp_path: Path) -> None:
        """Invoking cheval.main() with --mock-fixture-dir + --dry-run must parse
        without ArgumentError. Uses --dry-run + a fake config to short-circuit
        actual invocation."""
        # Build a deliberately minimal config so resolve_execution doesn't fail.
        fake_resolved = _make_resolved()
        fake_binding = MagicMock(temperature=0.7, capability_class=None)
        with patch.object(cheval, "load_config",
                          return_value=(_make_minimal_config(), {})), \
             patch.object(cheval, "resolve_execution",
                          return_value=(fake_binding, fake_resolved)), \
             patch.object(sys, "argv", [
                 "cheval.py",
                 "--agent", "flatline-reviewer",
                 "--prompt", "x",
                 "--dry-run",
                 "--mock-fixture-dir", str(tmp_path),
             ]):
            rc = cheval.main()
        # --dry-run path returns SUCCESS without doing fixture lookup
        assert rc == cheval.EXIT_CODES["SUCCESS"]
