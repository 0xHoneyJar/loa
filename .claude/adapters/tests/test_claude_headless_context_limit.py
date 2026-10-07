"""cycle-127 review r251-2 K8 (n65): the claude CLI's own pre-flight size rejection is the provider's size verdict.

`ClaudeHeadlessAdapter._raise_for_error` used to map "Prompt is too long" / "the request is ~N tokens (limit M)" to
ProviderUnavailableError — walked to the next voice (which would get the same payload) and counted by the breaker. It is
now ProviderContextLimitError: cheval does not walk it, the breaker is not incremented, and no observation is written
for the CLI hop (its window is the CLI's, not an HTTP ceiling). No model is called: the CLI is a local fake script.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import cheval  # noqa: E402
from loa_cheval.providers.claude_headless_adapter import ClaudeHeadlessAdapter  # noqa: E402
from loa_cheval.types import ProviderContextLimitError, RateLimitError  # noqa: E402
from tests.test_claude_headless_adapter import _make_config  # noqa: E402
from tests.test_chain_walk_audit_envelope import _make_args  # noqa: E402

_CLI_TOKENS = "API Error: the request is ~1052900 tokens (limit 1000000) but the model's context window is exceeded"


@pytest.mark.parametrize("stderr,parsed,want_in,want_limit", [
    ("", {"is_error": True, "result": "Prompt is too long"}, None, None),
    ("Prompt is too long\n", None, None, None),
    (_CLI_TOKENS, None, 1052900, 1000000),            # ("529" inside the count is not a 529 overload)
    ("", {"is_error": True, "result": _CLI_TOKENS}, 1052900, 1000000),
])
def test_the_cli_size_rejection_is_a_provider_context_limit(stderr, parsed, want_in, want_limit):
    adapter = ClaudeHeadlessAdapter(_make_config())
    with pytest.raises(ProviderContextLimitError) as exc:
        adapter._raise_for_error(returncode=1, stderr=stderr, parsed=parsed)
    assert exc.value.input_tokens == want_in and exc.value.limit == want_limit
    assert exc.value.retryable is False


def test_a_real_rate_limit_still_wins():
    adapter = ClaudeHeadlessAdapter(_make_config())
    with pytest.raises(RateLimitError):
        adapter._raise_for_error(returncode=1, stderr="429 rate limit: too many requests (context window busy)", parsed=None)


def _fake_cli(tmp_path):
    counter = tmp_path / "calls"
    binary = tmp_path / "claude"
    binary.write_text(
        "#!/usr/bin/env python3\nimport json, sys\n"
        f"open({str(counter)!r}, 'a').write('x')\n"
        f"print(json.dumps({{'is_error': True, 'result': {_CLI_TOKENS!r}}}))\n"
        "sys.exit(1)\n"
    )
    binary.chmod(0o755)
    return binary, counter


def test_cheval_does_not_walk_count_or_record_a_cli_size_rejection(tmp_path, monkeypatch, capsys):
    binary, counter = _fake_cli(tmp_path)
    monkeypatch.chdir(tmp_path)
    monkeypatch.setenv("CLAUDE_HEADLESS_BIN", str(binary))
    monkeypatch.setenv("LOA_HEADLESS_MODE", "cli-only")
    observed = tmp_path / "observed.json"
    monkeypatch.setenv("LOA_CHEVAL_CEILING_OBSERVED_PATH", str(observed))
    monkeypatch.setattr(cheval, "_load_persona", lambda *a, **kw: None)
    monkeypatch.setattr(cheval, "_load_persona_parts", lambda *a, **kw: (None, None))
    monkeypatch.setattr(cheval, "_check_feature_flags", lambda *a, **kw: None)
    entry = {"kind": "cli", "auth_type": "headless", "capabilities": ["chat"], "context_window": 1000000,
             "extra": {"cli_model": "opus"}}
    cfg = {
        "providers": {"anthropic": {
            "type": "anthropic", "endpoint": "", "auth": "",
            "models": {"claude-headless": dict(entry, fallback_chain=["anthropic:claude-headless-b"]),
                       "claude-headless-b": dict(entry)},
        }},
        "retry": {"max_retries": 0},
        "feature_flags": {"metering": False},
    }
    captured: dict = {}
    failures: list = []
    with patch.object(cheval, "load_config", return_value=(cfg, {})), \
         patch.object(cheval, "resolve_execution", return_value=(
             MagicMock(temperature=0.7, capability_class=None),
             MagicMock(provider="anthropic", model_id="claude-headless"),
         )), \
         patch("loa_cheval.providers.retry._record_failure", side_effect=lambda *a, **k: failures.append(a)), \
         patch("loa_cheval.audit_envelope.audit_emit",
               side_effect=lambda level, event, payload, *a, **kw: captured.update(payload)):
        code = cheval.cmd_invoke(_make_args())
    err = capsys.readouterr().err
    assert code == cheval.EXIT_CODES["CONTEXT_TOO_LARGE"], err
    assert counter.read_text() == "x", "the size verdict was walked to the next hop"
    assert failures == [], "the breaker was incremented"
    assert [f["error_class"] for f in captured["models_failed"]] == ["PROVIDER_CONTEXT_LIMIT"], captured["models_failed"]
    assert not observed.exists() or not json.loads(observed.read_text() or "{}"), observed.read_text()
