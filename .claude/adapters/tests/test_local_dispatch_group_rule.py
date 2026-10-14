"""cycle-129 sprint-257 review round r257-1 (HIGH-1 (a)/(b), LOW-2, LOW-3; SDD D-8.1, D-7.2).

THE LOCAL-HOP RULE: a hop is local only when its provider is an HTTP provider whose endpoint host is an IP literal
in a loopback (127.0.0.0/8, ::1) or RFC1918 (10/8, 172.16/12, 192.168/16) range, or the literal ``localhost``.

(a) Load time: ``validate_providers`` refuses ``dispatch_group: local`` (model entry or provider block) on a CLI
    provider or on an endpoint whose host fails the rule; an https endpoint on a passing host needs no opt-in.
(b) Request time: ``TransportPolicy(local=True)`` refuses by name a request host that fails the rule, and the
    OpenAI adapter sets ``local`` for a model whose dispatch_group is ``local``.
LOW-2: ``keyless: false`` beside the literal ``auth: "local"`` is refused by name.
LOW-3: the probe helper CLI turns every load failure into one JSON line on stderr and exit 78.
"""

from __future__ import annotations

import copy
import json
import shutil
import sys
from pathlib import Path
from typing import Any, Dict

import pytest
import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from loa_cheval.config import endpoint_policy  # noqa: E402
from loa_cheval.config.endpoint_policy import (  # noqa: E402
    local_endpoint_host,
    local_host,
    normalise_keyless,
)
from loa_cheval.config.loader import clear_config_cache, load_config  # noqa: E402
from loa_cheval.providers.base import TransportPolicy  # noqa: E402
from loa_cheval.types import ConfigError, InvalidConfigError, ModelConfig, ProviderConfig  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[3]
DEFAULTS = REPO_ROOT / ".claude" / "defaults" / "model-config.yaml"

RULE = "dispatch_group local requires an endpoint on a loopback or RFC1918 IP literal or localhost"


def _project(tmp_path: Path, body: Any) -> str:
    root = tmp_path / "proj"
    (root / ".claude" / "defaults").mkdir(parents=True, exist_ok=True)
    shutil.copy(DEFAULTS, root / ".claude" / "defaults" / "model-config.yaml")
    text = body if isinstance(body, str) else yaml.safe_dump({"hounfour": body}, sort_keys=False)
    (root / ".loa.config.yaml").write_text(text)
    return str(root)


def _load(tmp_path: Path, hounfour: Dict[str, Any]) -> Dict[str, Any]:
    clear_config_cache()
    merged, _ = load_config(project_root=_project(tmp_path, hounfour))
    return merged


def _box(endpoint: str, *, optin: Any = None, model_group: str = "local", block_group: Any = None) -> Dict[str, Any]:
    prov: Dict[str, Any] = {
        "type": "openai_compat",
        "endpoint": endpoint,
        "keyless": True,
        "models": {
            "qwen-local": {
                "endpoint_family": "chat", "auth_type": "http_api", "dispatch_group": model_group,
                "capabilities": ["chat"], "context_window": 32768,
            }
        },
    }
    if optin is not None:
        prov["allow_insecure_endpoint"] = optin
    if block_group is not None:
        prov["dispatch_group"] = block_group
    return {"providers": {"box": prov}}


# --- (a) load time -----------------------------------------------------------------------------------------


def test_hosted_dns_endpoint_with_a_local_model_is_refused_by_name(tmp_path):
    with pytest.raises(ConfigError) as info:
        _load(tmp_path, _box("https://api.acme.example/v1"))
    msg = str(info.value)
    assert f"[CONFIG-INVALID] providers.box.models.qwen-local: {RULE} (host api.acme.example)" in msg


def test_hosted_dns_endpoint_with_a_local_provider_block_is_refused_naming_the_provider(tmp_path):
    with pytest.raises(ConfigError) as info:
        _load(tmp_path, _box("https://api.acme.example/v1", model_group="acme", block_group="local"))
    msg = str(info.value)
    assert f"[CONFIG-INVALID] providers.box: {RULE} (host api.acme.example)" in msg
    assert "providers.box.models" not in msg


@pytest.mark.parametrize("endpoint, host", [
    ("https://169.254.169.254/v1", "169.254.169.254"),
    ("https://203.0.113.5/v1", "203.0.113.5"),     # TEST-NET-3: the validator's blocked-range check fires first
    ("https://[fd12::1]:8443/v1", "fd12::1"),
    ("https://8.8.8.8/v1", "8.8.8.8"),             # a public literal the D-7.2 https rule admits: the local rule refuses
])
def test_non_local_ip_literal_with_a_local_model_is_refused(tmp_path, endpoint, host):
    with pytest.raises(ConfigError) as info:
        _load(tmp_path, _box(endpoint))
    msg = str(info.value)
    # the D-7.2 code is the more specific reason where it fires (metadata, documentation, ULA); else the local rule
    assert ("ENDPOINT-IP" in msg) or (f"{RULE} (host {host})" in msg), msg
    if host == "8.8.8.8":
        assert f"[CONFIG-INVALID] providers.box.models.qwen-local: {RULE} (host 8.8.8.8)" in msg


@pytest.mark.parametrize("endpoint, optin", [
    ("https://192.168.1.10:8443/v1", None),       # https on an RFC1918 literal: no opt-in needed
    ("https://10.0.0.5/v1", None),
    ("https://172.20.0.4/v1", None),
    ("https://[::1]:8443/v1", None),              # IPv6 loopback, bracketed in the URL
    ("https://localhost:8443/v1", None),
    ("https://127.0.0.1:8443/v1", None),
    ("http://127.0.0.1:8000/v1", "127.0.0.1"),    # http keeps today's opt-in
    ("http://[::1]:8000/v1", "::1"),
])
def test_local_endpoint_with_a_local_model_loads(tmp_path, endpoint, optin):
    merged = _load(tmp_path, _box(endpoint, optin=optin))
    assert merged["providers"]["box"]["endpoint"] == endpoint
    assert merged["providers"]["box"]["models"]["qwen-local"]["dispatch_group"] == "local"


def test_http_local_endpoint_still_needs_the_optin(tmp_path):
    with pytest.raises(ConfigError) as info:
        _load(tmp_path, _box("http://127.0.0.1:8000/v1"))
    assert "ENDPOINT-INSECURE-SCHEME" in str(info.value)


def test_cli_provider_with_a_local_label_is_refused(tmp_path):
    hounfour = {"providers": {"mycli": {
        "type": "claude-headless",
        "models": {"claude-x": {"kind": "cli", "auth_type": "headless", "dispatch_group": "local", "context_window": 200000}},
    }}}
    with pytest.raises(ConfigError) as info:
        _load(tmp_path, hounfour)
    assert "[CONFIG-INVALID] providers.mycli: dispatch_group local is not admitted on a CLI provider" in str(info.value)


def test_cli_provider_refusal_in_validate_providers_directly():
    merged = {"providers": {"mycli": {"type": "codex-headless", "dispatch_group": "local", "models": {}}}}
    with pytest.raises(ConfigError, match="dispatch_group local is not admitted on a CLI provider"):
        endpoint_policy.validate_providers(merged)


def test_local_label_without_an_endpoint_is_refused():
    merged = {"providers": {"box": {"type": "openai_compat",
                                    "models": {"m": {"dispatch_group": "local", "context_window": 1}}}}}
    with pytest.raises(ConfigError, match=r"providers\.box\.models\.m: dispatch_group local requires .* \(host missing\)"):
        endpoint_policy.validate_providers(merged)


def test_hosted_provider_without_a_local_label_is_untouched(tmp_path):
    merged = _load(tmp_path, _box("https://api.acme.example/v1", model_group="acme"))
    assert merged["providers"]["box"]["endpoint"] == "https://api.acme.example/v1"


def test_unlabelled_provider_keeps_the_https_private_refusal(tmp_path):
    with pytest.raises(ConfigError, match="ENDPOINT-IP-BLOCKED"):
        _load(tmp_path, _box("https://192.168.1.10:8443/v1", model_group="lab-gpu"))


@pytest.mark.parametrize("host, expected", [
    ("127.0.0.1", "127.0.0.1"), ("127.9.9.9", "127.9.9.9"), ("::1", "::1"), ("[::1]", "::1"),
    ("localhost", "localhost"), ("LOCALHOST", "localhost"), ("10.0.0.5", "10.0.0.5"), ("172.31.255.1", "172.31.255.1"),
    ("192.168.0.1", "192.168.0.1"),
    ("169.254.169.254", None), ("169.254.1.1", None), ("fe80::1", None), ("fd12::1", None), ("203.0.113.5", None),
    ("8.8.8.8", None), ("172.32.0.1", None), ("api.acme.example", None), ("localhost.example", None), ("", None),
    ("::ffff:127.0.0.1", None),
])
def test_local_host_rule_table(host, expected):
    assert local_host(host) == expected


def test_local_endpoint_host_needs_http_or_https():
    assert local_endpoint_host("https://[::1]:8443/v1") == "::1"
    assert local_endpoint_host("ftp://127.0.0.1/v1") is None
    assert local_endpoint_host("not a url") is None
    assert local_endpoint_host(None) is None
    assert local_endpoint_host("http://127.0.0.1:notaport/v1") is None


# --- (b) request time --------------------------------------------------------------------------------------


@pytest.mark.parametrize("url, host", [
    ("https://api.acme.example/v1/chat/completions", "api.acme.example"),
    ("https://203.0.113.5/v1/chat/completions", "203.0.113.5"),
    ("https://169.254.169.254/v1/chat/completions", "169.254.169.254"),
])
def test_local_policy_refuses_a_non_local_request_host_by_name(url, host):
    endpoint = url.rsplit("/chat/completions", 1)[0]
    policy = TransportPolicy(endpoint=endpoint, provider="box", local=True)
    with pytest.raises(InvalidConfigError) as info:
        policy.check_url(url)
    assert (f"request host {host} for provider 'box' is not a loopback or RFC1918 IP literal or localhost "
            f"(dispatch_group local, D-7.2)") in str(info.value)


@pytest.mark.parametrize("endpoint", [
    "http://127.0.0.1:8000/v1", "https://10.0.0.5/v1", "http://[::1]:8000/v1", "http://localhost:11434/v1",
])
def test_local_policy_accepts_a_local_request_host(endpoint):
    TransportPolicy(endpoint=endpoint, provider="box", local=True).check_url(endpoint + "/chat/completions")


def test_opted_in_policy_without_the_local_label_keeps_todays_behaviour():
    # same-origin and path-prefix only: a DNS host declared as the endpoint is not refused by the host rule
    TransportPolicy(endpoint="https://api.acme.example/v1", provider="box").check_url(
        "https://api.acme.example/v1/chat/completions")


# --- audit a257-1 LOW-A1: `localhost` is resolved and checked at request time (IP literals are never resolved) ---


def _gai(*addrs):
    import socket as _s

    def fake(host, port, *_a, **_kw):
        assert host == "localhost"
        return [(_s.AF_INET6 if ":" in a else _s.AF_INET, _s.SOCK_STREAM, 6, "", (a, 0)) for a in addrs]
    return fake


@pytest.mark.parametrize("local", [True, False])
def test_localhost_resolving_to_loopback_only_is_accepted(monkeypatch, local):
    monkeypatch.setattr("socket.getaddrinfo", _gai("127.0.0.1", "::1", "127.0.1.1", "::ffff:127.0.0.1"))
    TransportPolicy(endpoint="http://localhost:11434/v1", provider="box", local=local).check_url(
        "http://localhost:11434/v1/chat/completions")


@pytest.mark.parametrize("local", [True, False])
def test_localhost_with_a_public_address_among_the_results_is_refused_by_name(monkeypatch, local):
    monkeypatch.setattr("socket.getaddrinfo", _gai("127.0.0.1", "203.0.113.5"))
    with pytest.raises(InvalidConfigError) as info:
        TransportPolicy(endpoint="http://localhost:11434/v1", provider="box", local=local).check_url(
            "http://localhost:11434/v1/chat/completions")
    assert ("request host localhost for provider 'box' resolves to 203.0.113.5, not a loopback address "
            "(dispatch_group local, D-7.2)") in str(info.value)


def test_localhost_resolving_to_an_rfc1918_address_is_refused(monkeypatch):
    monkeypatch.setattr("socket.getaddrinfo", _gai("192.168.1.10"))
    with pytest.raises(InvalidConfigError, match="resolves to 192.168.1.10, not a loopback address"):
        TransportPolicy(endpoint="http://localhost:11434/v1", provider="box", local=True).check_url(
            "http://localhost:11434/v1/chat/completions")


@pytest.mark.parametrize("fake", [
    pytest.param(lambda *_a, **_kw: (_ for _ in ()).throw(OSError("no resolver")), id="raises"),
    pytest.param(lambda *_a, **_kw: [], id="empty"),
])
def test_localhost_resolver_failure_is_refused(monkeypatch, fake):
    monkeypatch.setattr("socket.getaddrinfo", fake)
    with pytest.raises(InvalidConfigError) as info:
        TransportPolicy(endpoint="http://localhost:11434/v1", provider="box", local=True).check_url(
            "http://localhost:11434/v1/chat/completions")
    assert "request host localhost for provider 'box' could not be resolved" in str(info.value)


def test_an_ip_literal_is_never_resolved(monkeypatch):
    def boom(*_a, **_kw):
        raise AssertionError("an IP literal must not reach the resolver")
    monkeypatch.setattr("socket.getaddrinfo", boom)
    TransportPolicy(endpoint="http://127.0.0.1:8000/v1", provider="box", local=True).check_url(
        "http://127.0.0.1:8000/v1/chat/completions")


def _adapter(dispatch_group: str, endpoint: str = "https://api.acme.example/v1", optin: Any = None):
    from loa_cheval.providers.openai_adapter import OpenAIAdapter

    cfg = ProviderConfig(
        name="box", type="openai_compat", endpoint=endpoint, auth="", keyless=True,
        allow_insecure_endpoint=optin,
        models={"m": ModelConfig(capabilities=["chat"], context_window=32768, endpoint_family="chat",
                                 dispatch_group=dispatch_group)},
    )
    return OpenAIAdapter(cfg), cfg.models["m"]


def test_adapter_marks_a_local_hop_policy_local():
    adapter, model = _adapter("local")
    policy = adapter._transport_policy(model)
    assert policy is not None and policy.local is True
    with pytest.raises(InvalidConfigError, match="dispatch_group local, D-7.2"):
        policy.check_url("https://api.acme.example/v1/chat/completions")


def test_adapter_opted_in_hop_without_the_label_is_not_local():
    adapter, model = _adapter("lab-gpu", endpoint="http://127.0.0.1:8000/v1", optin="127.0.0.1")
    policy = adapter._transport_policy(model)
    assert policy is not None and policy.local is False
    adapter2, model2 = _adapter("acme")
    assert adapter2._transport_policy(model2) is None


def test_modelinv_never_records_local_for_a_hop_the_rule_calls_hosted():
    from loa_cheval.audit.modelinv import hop_locality_of

    def h(endpoint: Any, ptype: str = "openai_compat") -> Dict[str, Any]:
        return {"providers": {"box": {"type": ptype, "endpoint": endpoint, "models": {"m": {"dispatch_group": "local"}}}}}

    assert hop_locality_of("box", "m", h("http://127.0.0.1:8000/v1")) == "local"
    assert hop_locality_of("box", "m", h("https://[::1]:8443/v1")) == "local"
    assert hop_locality_of("box", "m", h("https://api.acme.example/v1")) == "hosted"
    assert hop_locality_of("box", "m", h(None)) == "hosted"
    assert hop_locality_of("box", "m", h("http://127.0.0.1:8000/v1", ptype="claude-headless")) == "hosted"


# --- LOW-2 -------------------------------------------------------------------------------------------------


def test_keyless_false_beside_literal_auth_local_is_refused():
    merged = {"providers": {"box": {"auth": "local", "keyless": False}}}
    with pytest.raises(ConfigError) as info:
        normalise_keyless(merged)
    assert '[CONFIG-INVALID] providers.box: keyless: false conflicts with the literal auth "local"' in str(info.value)


def test_literal_auth_local_still_normalises_to_keyless():
    merged = {"providers": {"box": {"auth": "local"}, "box2": {"auth": "local", "keyless": True}}}
    normalise_keyless(merged)
    assert merged["providers"]["box"]["keyless"] is True
    assert merged["providers"]["box2"]["keyless"] is True


# --- LOW-3 -------------------------------------------------------------------------------------------------


def _one_json_line(err: str) -> Dict[str, Any]:
    lines = [ln for ln in err.splitlines() if ln.strip()]
    assert "Traceback" not in err, err
    payload = [json.loads(ln) for ln in lines if ln.lstrip().startswith("{")]
    assert len(payload) == 1, err
    return payload[0]


def test_main_unparseable_config_is_78_with_json(tmp_path, capsys):
    clear_config_cache()
    root = _project(tmp_path, "hounfour: [unclosed\n")
    rc = endpoint_policy._main(["list-providers", "--project-root", root])
    err = capsys.readouterr().err
    assert rc == 78
    assert _one_json_line(err)["error"] == "config_load_failed"


def test_main_any_load_exception_is_78_with_class_and_message(monkeypatch, capsys):
    import loa_cheval.config.loader as loader

    def boom(**_kw):
        raise RuntimeError("interpolation exploded")

    monkeypatch.setattr(loader, "load_config", boom)
    rc = endpoint_policy._main(["describe-provider", "box"])
    err = capsys.readouterr().err
    assert rc == 78
    doc = _one_json_line(err)
    assert doc == {"error": "config_load_failed", "detail": "RuntimeError: interpolation exploded"}


def test_main_describe_provider_config_error_is_78_and_missing_provider_stays_64(monkeypatch, capsys):
    import loa_cheval.config.loader as loader

    merged = {"providers": {"box": {"type": "openai_compat", "allow_insecure_endpoint": True, "models": {}}}}
    monkeypatch.setattr(loader, "load_config", lambda **_kw: (copy.deepcopy(merged), {}))
    rc = endpoint_policy._main(["describe-provider", "box"])
    err = capsys.readouterr().err
    assert rc == 78
    doc = _one_json_line(err)
    assert doc["error"] == "config_load_failed" and "ENDPOINT-OPTIN-BOOLEAN" in doc["detail"]
    rc = endpoint_policy._main(["describe-provider", "nobody"])
    err = capsys.readouterr().err
    assert rc == 64
    assert _one_json_line(err) == {"error": "provider_not_configured", "provider": "nobody"}
