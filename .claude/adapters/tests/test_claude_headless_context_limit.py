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


_BEDROCK_TPM = "Too many tokens, please wait before trying again"


@pytest.mark.parametrize("stderr,parsed,token_limited", [
    ("429 rate limit: too many requests (context window busy)", None, True),
    # r251-3 R1: Bedrock's tokens-per-minute throttle carries the context marker `too many tokens`;
    # the throttle marker wins (SDD D-3.12), as it does in the probe.
    (f"API Error: 429 {_BEDROCK_TPM}.", None, True),
    ("", {"is_error": True, "result": f"{_BEDROCK_TPM}.", "api_error_status": 429}, True),
    (_BEDROCK_TPM, None, True),
    (f"ThrottlingException: {_BEDROCK_TPM}.", None, True),
    ("API Error: 429 Too many requests, please wait", None, False),
    ("API Error: 429 rate limit exceeded", None, False),
    ("API Error: 529 overloaded", None, False),
])
def test_a_real_rate_limit_still_wins(stderr, parsed, token_limited):
    adapter = ClaudeHeadlessAdapter(_make_config())
    with pytest.raises(RateLimitError) as exc:
        adapter._raise_for_error(returncode=1, stderr=stderr, parsed=parsed)
    assert exc.value.token_limited is token_limited


@pytest.mark.parametrize("stderr,parsed", [
    ("", {"is_error": True, "result": "Prompt is too long: 1,429,000 tokens > 1,000,000 maximum"}),
    ("Prompt is too long: 1,429,000 tokens > 1,000,000 maximum", None),
    ("the request is ~1065182 tokens (limit 1000000)", None),
    ("API Error: the request is ~1052900 tokens (limit 1000000)", None),   # "529" inside the count
    # the CLI's own answer decides; a stale stderr throttle line does not (probe r251-2 Q1)
    ("warning: earlier rate limit hit, please wait", {"is_error": True,
                                                      "result": "Prompt is too long: 1,065,182 tokens > 1,000,000 maximum"}),
])
def test_digits_in_a_token_count_never_read_as_a_throttle_status(stderr, parsed):
    adapter = ClaudeHeadlessAdapter(_make_config())
    with pytest.raises(ProviderContextLimitError):
        adapter._raise_for_error(returncode=1, stderr=stderr, parsed=parsed)


@pytest.mark.parametrize("text,want", [
    ("Too many tokens, please wait before trying again", True),
    ("ThrottlingException: slow down", True),
    ("API Error: 429. Too many tokens", True),
    ("API Error: 429, too many tokens", True),
    ("HTTP 529 overloaded", True),
    ("529", True),
    ("too many requests", True),
    ("monthly quota exhausted", True),
    ("input tokens per minute exceeded", True),
    ("Rate limit reached", True),
    ("Prompt is too long: 1,429,000 tokens > 1,000,000 maximum", False),
    ("Prompt is too long: 429,000 tokens > 400,000 maximum", False),
    ("Prompt is too long: 1,429.5k tokens > 1,000,000 maximum", False),
    ("the request is ~1052900 tokens (limit 1000000)", False),
    ("the request is ~4290 tokens", False),
    ("the request is ~429 tokens (limit 400)", False),
    ("~529k tokens", False),
    ("Prompt is too long", False),
    ("", False),
    (None, False),
])
def test_is_throttle_message(text, want):
    from loa_cheval.routing.ceiling import is_throttle_message
    assert is_throttle_message(text) is want


# --- r251-3 R1: one throttle rule, probe and adapter agree ------------------

_CONFORMANCE = [
    # (result, api_error_status, stderr)
    (f"{_BEDROCK_TPM}.", None, ""),
    (f"{_BEDROCK_TPM}.", 429, ""),
    (f"ThrottlingException: {_BEDROCK_TPM}.", None, ""),
    ("", None, f"API Error: 429 {_BEDROCK_TPM}."),
    ("", None, _BEDROCK_TPM),
    ("API Error: 429. Too many tokens", None, ""),
    ("too many tokens per minute", None, ""),
    ("API Error: 429 prompt is too long for your rate limit", None, ""),
    ("Overloaded: too many tokens in flight", 529, ""),
    ("Prompt is too long: 1,429,000 tokens > 1,000,000 maximum", None, ""),
    ("Prompt is too long: 429,000 tokens > 400,000 maximum", None, ""),
    ("Prompt is too long: 1,429.5k tokens > 1,000,000 maximum", None, ""),
    ("Prompt is too long", None, ""),
    ("", None, "the request is ~1065182 tokens (limit 1000000)"),
    (_CLI_TOKENS, None, ""),
    ("Prompt is too long: 1,065,182 tokens > 1,000,000 maximum", None, "warning: earlier rate limit hit, please wait"),
    ("API Error: 429 rate limit exceeded", 429, ""),
    ("", None, "API Error: 529 overloaded"),
]


@pytest.fixture(scope="module")
def probe_tool():
    import importlib.util
    tool_path = Path(__file__).resolve().parents[3] / "tools" / "ceiling-probe-live.py"
    spec = importlib.util.spec_from_file_location("ceiling_probe_live_conformance", tool_path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["ceiling_probe_live_conformance"] = mod
    spec.loader.exec_module(mod)
    return mod


@pytest.mark.parametrize("result,api_status,stderr", _CONFORMANCE)
def test_probe_and_adapter_classify_the_same_text_the_same_way(probe_tool, result, api_status, stderr):
    parsed = None
    if result:
        parsed = {"type": "result", "is_error": True, "result": result}
        if api_status:
            parsed["api_error_status"] = api_status
    probe = probe_tool._classify(1, json.dumps(parsed) if parsed else "", stderr, "abcdefabcdef")
    adapter = ClaudeHeadlessAdapter(_make_config())
    with pytest.raises((RateLimitError, ProviderContextLimitError)) as exc:
        adapter._raise_for_error(returncode=1, stderr=stderr, parsed=parsed)
    if isinstance(exc.value, RateLimitError):
        assert probe["kind"] == "transient", (probe, exc.value)
        assert bool(probe.get("token_limit")) is exc.value.token_limited, (probe, exc.value)
    else:
        assert probe["kind"] == "size" and probe.get("failure_class") == "context_limit", (probe, exc.value)


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
    # r251-3 R4: no HTTP entry in the chain — no calibrate hint naming the CLI entry (the tool refuses it)
    assert "--model claude-headless" not in err, err
    assert "the CLI's own window refused the payload" in err, err
    assert captured["capability_evaluation"]["calibration_needed"]["calibrate"] is None


def _hop(provider, model_id, kind):
    from types import SimpleNamespace
    return SimpleNamespace(provider=provider, model_id=model_id, canonical=f"{provider}:{model_id}", adapter_kind=kind)


def test_the_calibrate_hint_for_an_http_hop_is_unchanged():
    hop = _hop("anthropic", "claude-opus-5-5", "http")
    assert cheval._calibrate_hint(hop, [hop]) == "python3 tools/ceiling-probe-live.py --model claude-opus-5-5 --write-catalog"


def test_a_cli_hop_names_the_chain_s_http_entry_with_the_cli_transport():
    head, cli = _hop("anthropic", "claude-opus-5-5", "http"), _hop("anthropic", "claude-headless", "cli")
    hint = cheval._calibrate_hint(cli, [head, cli])
    assert hint == ("python3 tools/ceiling-probe-live.py --model claude-opus-5-5 --write-catalog"
                    " --transport claude-headless"), hint


@pytest.mark.parametrize("chain", [
    [("anthropic", "claude-headless", "cli")],
    [("openai", "gpt-5.5", "http"), ("anthropic", "claude-headless", "cli")],   # another provider's HTTP entry
])
def test_a_cli_hop_without_an_anthropic_http_entry_gets_no_calibrate_hint(chain):
    hops = [_hop(*h) for h in chain]
    assert cheval._calibrate_hint(hops[-1], hops) is None


def test_a_non_claude_cli_hop_gets_no_calibrate_hint():
    head, cli = _hop("openai", "gpt-5.5", "http"), _hop("openai", "codex-headless", "cli")
    assert cheval._calibrate_hint(cli, [head, cli]) is None


# --- review r251-5 U3 (audit LOW-003): a static-auth marker outranks a throttle match that rests on `please wait` alone ----

from loa_cheval.types import AuthRevokedError, ConfigError  # noqa: E402


@pytest.mark.parametrize("stderr,parsed,want", [
    # the auth marker first, then `please wait` — and the reverse order: the auth class either way
    ("Not logged in · please wait, then run /login", None, ConfigError),
    ("Please wait — not logged in. Run /login", None, ConfigError),
    ("", {"is_error": True, "result": "Not logged in · please wait, then run /login"}, ConfigError),
    ("Authentication failed, please wait and retry", None, ConfigError),
    ("Please wait: authentication required", None, ConfigError),
    ("Invalid API key · please wait, then run /login", None, ConfigError),
    ("Please wait. Invalid API key", None, ConfigError),
    # `unauthorized` keeps its existing walkable class (runtime revocation) — it is not a throttle either
    ("Unauthorized — please wait", None, AuthRevokedError),
    ("Please wait: unauthorized", None, AuthRevokedError),
])
def test_r251_5_u3_an_auth_failure_saying_please_wait_is_not_a_throttle(stderr, parsed, want):
    adapter = ClaudeHeadlessAdapter(_make_config())
    with pytest.raises(want):
        adapter._raise_for_error(returncode=1, stderr=stderr, parsed=parsed)


@pytest.mark.parametrize("stderr,parsed", [
    # a throttle that rests on more than `please wait` still wins over an auth marker, in either order
    ("API Error: 429 not logged in? please wait", None),
    ("not logged in? API Error: 429. please wait", None),
    ("", {"is_error": True, "result": "Not logged in · please wait", "api_error_status": 429}),
    ("API Error: 529 authentication service overloaded, please wait", None),
    ("rate limit reached — please wait, then run /login", None),
    ("please wait, then run /login: rate limit reached", None),
    ("Authentication ok but input tokens per minute exceeded, please wait", None),
    ("please wait: tokens per min exceeded (authentication fine)", None),
    # and with no auth marker a bare `please wait` is a throttle as before (Bedrock)
    ("Too many tokens, please wait before trying again", None),
])
def test_r251_5_u3_a_status_or_named_rate_limit_still_wins_as_a_throttle(stderr, parsed):
    adapter = ClaudeHeadlessAdapter(_make_config())
    with pytest.raises(RateLimitError):
        adapter._raise_for_error(returncode=1, stderr=stderr, parsed=parsed)
