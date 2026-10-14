"""cycle-129 FR-7 (SDD D-7.2; sprint-257 Task 3.1, AC-3.1) — the per-provider
insecure-endpoint opt-in on BOTH paths, and the request-time rules.

* One case table runs through the bash-path validator
  (`.claude/scripts/lib/endpoint-validator.py` `validate(..., allow_insecure_endpoint=...)`)
  and the cheval Python path (`loa_cheval.config.endpoint_policy.check_endpoint`); the two
  must agree on accept/refuse and on the refusal code.
* D-7.2 test list: IPv4 and IPv6 loopback accepted, RFC1918 accepted, link-local and metadata
  refused, DNS name refused, boolean refused, cross-provider isolation, and — at request time
  against a stub server bound to 127.0.0.1 — redirect refused, proxy env ignored, path prefix
  enforced, on the httpx and the urllib transport.
"""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from typing import Any, Dict, List, Optional

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from loa_cheval.config.endpoint_policy import EndpointPolicyError, check_endpoint  # noqa: E402
from loa_cheval.providers import base  # noqa: E402
from loa_cheval.providers.base import TransportPolicy, http_get, http_post, http_post_stream  # noqa: E402
from loa_cheval.types import InvalidConfigError  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[3]
VALIDATOR_PATH = REPO_ROOT / ".claude" / "scripts" / "lib" / "endpoint-validator.py"
ALLOWLIST_PATH = REPO_ROOT / ".claude" / "scripts" / "lib" / "allowlists" / "loa-providers.json"


def _load_validator():
    spec = importlib.util.spec_from_file_location("endpoint_validator_under_test", VALIDATOR_PATH)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod


EV = _load_validator()
ALLOWLIST = EV.load_allowlist(ALLOWLIST_PATH)

OK = None
# (case id, url, allow_insecure_endpoint, expected refusal code or OK)
CASES = [
    ("ipv4-loopback", "http://127.0.0.1:8000/v1", "127.0.0.1", OK),
    ("ipv4-loopback-other-127", "http://127.0.0.2:8000/v1", "127.0.0.2", OK),
    ("ipv6-loopback", "http://[::1]:8000/v1", "::1", OK),
    ("ipv6-loopback-bracketed-optin", "http://[::1]:8000/v1", "[::1]", OK),
    ("localhost", "http://localhost:11434/v1", "localhost", OK),
    ("rfc1918-10", "http://10.0.0.7:8000/v1", "10.0.0.7", OK),
    ("rfc1918-172-16", "http://172.16.5.5:8000/v1", "172.16.5.5", OK),
    ("rfc1918-192-168", "http://192.168.0.10:8000/v1", "192.168.0.10", OK),
    ("https-to-optin-host", "https://192.168.0.10/v1", "192.168.0.10", OK),
    ("link-local-v4", "http://169.254.7.7/v1", "169.254.7.7", "ENDPOINT-OPTIN-LINK-LOCAL"),
    ("link-local-v6", "http://[fe80::1]/v1", "fe80::1", "ENDPOINT-OPTIN-LINK-LOCAL"),
    ("metadata-v4", "http://169.254.169.254/latest", "169.254.169.254", "ENDPOINT-OPTIN-METADATA"),
    ("metadata-v6", "http://[fd00:ec2::254]/latest", "fd00:ec2::254", "ENDPOINT-OPTIN-METADATA"),
    ("dns-name", "http://llm.lan:8000/v1", "llm.lan", "ENDPOINT-OPTIN-DNS-NAME"),
    ("public-v4", "http://8.8.8.8/v1", "8.8.8.8", "ENDPOINT-OPTIN-NOT-LOCAL"),
    ("ipv6-unique-local", "http://[fd12:3456::1]/v1", "fd12:3456::1", "ENDPOINT-OPTIN-NOT-LOCAL"),
    ("cgnat-not-rfc1918", "http://100.64.0.1/v1", "100.64.0.1", "ENDPOINT-OPTIN-NOT-LOCAL"),
    ("boolean-true", "http://127.0.0.1:8000/v1", True, "ENDPOINT-OPTIN-BOOLEAN"),
    ("boolean-false", "http://127.0.0.1:8000/v1", False, "ENDPOINT-OPTIN-BOOLEAN"),
    ("optin-with-port", "http://127.0.0.1:8000/v1", "127.0.0.1:8000", "ENDPOINT-OPTIN-DNS-NAME"),
    ("optin-with-scheme", "http://127.0.0.1:8000/v1", "http://127.0.0.1", "ENDPOINT-OPTIN-INVALID"),
    ("mismatched-host", "http://localhost:8000/v1", "127.0.0.1", "ENDPOINT-INSECURE-HOST-MISMATCH"),
    ("mismatched-public", "http://8.8.8.8/v1", "127.0.0.1", "ENDPOINT-INSECURE-HOST-MISMATCH"),
    ("http-no-optin-loopback", "http://127.0.0.1:8000/v1", None, "ENDPOINT-INSECURE-SCHEME"),
    ("http-no-optin-public", "http://8.8.8.8/v1", None, "ENDPOINT-INSECURE-SCHEME"),
    ("https-no-optin-loopback", "https://127.0.0.1/v1", None, "ENDPOINT-IP-BLOCKED"),
    ("https-no-optin-rfc1918", "https://10.0.0.1/v1", None, "ENDPOINT-IP-BLOCKED"),
    ("https-no-optin-metadata", "https://169.254.169.254/", None, "ENDPOINT-IP-BLOCKED"),
    ("https-no-optin-v6-loopback", "https://[::1]/v1", None, "ENDPOINT-IPV6-BLOCKED"),
    ("userinfo-on-optin-host", "http://user:pw@127.0.0.1:8000/v1", "127.0.0.1", "ENDPOINT-USERINFO-PRESENT"),
]


def _cheval(url: str, optin: Any) -> Optional[str]:
    try:
        check_endpoint(url, optin, "p")
    except EndpointPolicyError as exc:
        return exc.policy_code
    return OK


def _bash_path(url: str, optin: Any) -> Optional[str]:
    result = EV.validate(url, ALLOWLIST, allow_insecure_endpoint=optin)
    return OK if result.valid else result.code


@pytest.mark.parametrize("case, url, optin, expected", CASES, ids=[c[0] for c in CASES])
def test_both_paths_agree(case, url, optin, expected):
    assert _cheval(url, optin) == expected, f"cheval path: {case}"
    assert _bash_path(url, optin) == expected, f"endpoint-validator.py: {case}"


def test_validator_cli_flag_admits_only_the_optin_host():
    def run(*args: str) -> subprocess.CompletedProcess:
        return subprocess.run([sys.executable, "-I", str(VALIDATOR_PATH), "--allowlist", str(ALLOWLIST_PATH), *args],
                              capture_output=True, text=True, timeout=30)

    ok = run("--allow-insecure-endpoint", "127.0.0.1", "--json", "http://127.0.0.1:8000/v1/models")
    assert ok.returncode == 0, ok.stderr
    assert json.loads(ok.stdout)["extra"] == {"insecure_optin": "127.0.0.1"}
    refused = run("--allow-insecure-endpoint", "true", "http://127.0.0.1:8000/v1/models")
    assert refused.returncode == 78 and "ENDPOINT-OPTIN-DNS-NAME" in refused.stderr
    no_optin = run("http://127.0.0.1:8000/v1/models")
    assert no_optin.returncode == 78 and "ENDPOINT-INSECURE-SCHEME" in no_optin.stderr


def test_cross_provider_isolation_on_both_paths():
    """Provider A's opt-in is passed with A's URL only; provider B (same loopback host, no
    opt-in of its own) keeps every refusal on both paths, before and after A is validated."""
    a_url, a_optin = "http://127.0.0.1:8000/v1", "127.0.0.1"
    b_url = "http://127.0.0.1:9000/v1"
    for _ in range(2):
        assert _cheval(a_url, a_optin) is OK and _bash_path(a_url, a_optin) is OK
        assert _cheval(b_url, None) == "ENDPOINT-INSECURE-SCHEME"
        assert _bash_path(b_url, None) == "ENDPOINT-INSECURE-SCHEME"
    # the hosted provider's https URL is untouched by A's opt-in
    assert _bash_path("https://api.openai.com/v1", None) is OK
    assert _bash_path("https://api.openai.com/v1", a_optin) is OK


# --- request time: a stub server on 127.0.0.1 -------------------------------------------------------------


class _Stub:
    """127.0.0.1 HTTP server the test starts and stops. Paths: /v1/ok (200 JSON),
    /v1/redirect (302 to /v1/ok), /v1/stream (one SSE chunk). Records request headers."""

    def __init__(self) -> None:
        stub = self
        self.seen: List[Dict[str, Any]] = []

        class H(BaseHTTPRequestHandler):
            def _reply(self) -> None:
                length = int(self.headers.get("Content-Length") or 0)
                if length:
                    self.rfile.read(length)
                stub.seen.append({"path": self.path, "headers": dict(self.headers)})
                if self.path.endswith("/redirect"):
                    self.send_response(302)
                    self.send_header("Location", f"http://127.0.0.1:{stub.port}/v1/ok")
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return
                payload = b'{"ok": true}'
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)

            do_GET = _reply
            do_POST = _reply

            def log_message(self, *args: Any) -> None:
                pass

        self.server = HTTPServer(("127.0.0.1", 0), H)
        self.port = self.server.server_port
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    def __enter__(self) -> "_Stub":
        self.thread.start()
        return self

    def __exit__(self, *exc: Any) -> None:
        self.server.shutdown()
        self.server.server_close()

    @property
    def endpoint(self) -> str:
        return f"http://127.0.0.1:{self.port}/v1"


@pytest.fixture(params=["httpx", "urllib"])
def transport(request, monkeypatch):
    monkeypatch.setattr(base, "_HTTP_CLIENT", request.param)
    yield request.param
    base._reset_http_client_detection_for_tests()


@pytest.fixture
def stub():
    with _Stub() as s:
        yield s


def _policy(s: _Stub) -> TransportPolicy:
    return TransportPolicy(endpoint=s.endpoint, provider="local")


def test_redirect_refused(transport, stub):
    with pytest.raises(InvalidConfigError, match="redirect refused"):
        http_post(f"{stub.endpoint}/redirect", {}, {"x": 1}, policy=_policy(stub))
    with pytest.raises(InvalidConfigError, match="redirect refused"):
        http_get(f"{stub.endpoint}/redirect", {}, policy=_policy(stub))
    with pytest.raises(InvalidConfigError, match="redirect refused"):
        with http_post_stream(f"{stub.endpoint}/redirect", {}, {"x": 1}, policy=_policy(stub)):
            pass
    # never followed: the stub saw only the redirecting request, never /v1/ok
    assert all(r["path"].endswith("/redirect") for r in stub.seen)


_PROXY_VARS = ("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy")


def test_proxy_env_ignored(transport, stub, monkeypatch):
    import urllib.request

    for var in ("NO_PROXY", "no_proxy"):
        monkeypatch.delenv(var, raising=False)
    for var in _PROXY_VARS:
        monkeypatch.setenv(var, "http://127.0.0.1:1")   # a dead proxy: any use of it fails
    # urllib caches a process-wide default opener whose ProxyHandler read the env when it
    # was built; drop it so the no-policy control below sees this test's proxy env.
    monkeypatch.setattr(urllib.request, "_opener", None)
    status, body = http_post(f"{stub.endpoint}/ok", {}, {"x": 1}, policy=_policy(stub))
    assert (status, body) == (200, {"ok": True})
    status, _ = http_get(f"{stub.endpoint}/ok", {}, policy=_policy(stub))
    assert status == 200
    with http_post_stream(f"{stub.endpoint}/ok", {}, {"x": 1}, policy=_policy(stub)) as resp:
        assert resp.status_code == 200 and b"".join(resp.iter_bytes()) == b'{"ok": true}'
    # control: without the policy the same call goes to the dead proxy and never reaches the stub
    seen_before = len(stub.seen)
    try:
        control_status: Optional[int] = http_post(f"{stub.endpoint}/ok", {}, {"x": 1})[0]
    except Exception:  # noqa: BLE001 — httpx raises ConnectionLostError; urllib returns 503
        control_status = None
    assert control_status != 200
    assert len(stub.seen) == seen_before


@pytest.mark.parametrize("url", [
    "/other/chat/completions",          # outside the declared path
    "/v10/chat/completions",            # a sibling that only shares the prefix string
    "/v1/../admin",                     # traversal
])
def test_path_prefix_enforced(stub, url):
    with pytest.raises(InvalidConfigError, match="outside the declared endpoint"):
        http_post(f"http://127.0.0.1:{stub.port}{url}", {}, {}, policy=_policy(stub))
    assert stub.seen == []


def test_origin_must_match(stub):
    pol = _policy(stub)
    for url in (f"http://127.0.0.1:{stub.port + 1}/v1/x", f"http://localhost:{stub.port}/v1/x",
                f"https://127.0.0.1:{stub.port}/v1/x"):
        with pytest.raises(InvalidConfigError):
            pol.check_url(url)
    pol.check_url(f"{stub.endpoint}/chat/completions")
    pol.check_url(stub.endpoint)


def test_opted_in_adapter_sends_no_credential_and_uses_the_policy(stub, monkeypatch):
    """A keyless opted-in provider: the OpenAI adapter's request carries no Authorization
    header and goes through the TransportPolicy (dead proxy env set; still reaches the stub)."""
    from loa_cheval.providers.openai_adapter import OpenAIAdapter
    from loa_cheval.types import CompletionRequest, ModelConfig, ProviderConfig

    for var in _PROXY_VARS:
        monkeypatch.setenv(var, "http://127.0.0.1:1")
    monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
    cfg = ProviderConfig(
        name="local", type="openai_compat", endpoint=stub.endpoint, auth="",
        keyless=True, allow_insecure_endpoint="127.0.0.1",
        models={"m": ModelConfig(capabilities=["chat"], context_window=32768, endpoint_family="chat",
                                 dispatch_group="local")},
    )
    adapter = OpenAIAdapter(cfg)
    assert adapter.validate_config() == []
    # the stub answers {"ok": true}: no `choices`, so the parse fails AFTER the request
    with pytest.raises(Exception, match="no choices"):
        adapter.complete(CompletionRequest(messages=[{"role": "user", "content": "hi"}], model="m", max_tokens=16))
    assert len(stub.seen) == 1
    assert stub.seen[0]["path"] == "/v1/chat/completions"
    assert "Authorization" not in stub.seen[0]["headers"]
