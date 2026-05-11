"""Cheval HTTP-asymmetry reproduction harness — KF-002 layer 3.

Tests transport variants against api.anthropic.com and api.openai.com
with a ~30K-token (~120KB) prompt. Goal: identify which transport tweak
survives the 60s server-side disconnect that vanilla httpx HTTP/1.1 hits.

Variants:
  V0: httpx.post() HTTP/1.1 — matches current base.py:http_post()  [control]
  V1: httpx.Client(http2=True).post() — HTTP/2 multiplexing
  V2: httpx streaming response (stream=True body + iter_text)
  V3: httpx.Client() HTTP/1.1 with TCP_KEEPALIVE socket option
"""
from __future__ import annotations

import json
import os
import socket
import sys
import time
import traceback
from typing import Any, Dict, Tuple

import httpx


def make_prompt(target_chars: int) -> str:
    """Build a deterministic prompt of approximately target_chars characters.

    We use a paragraph of recognisable English text repeated, so token
    estimation is close to char/3.5. Anthropic counts subwords slightly
    differently but this is in the right order of magnitude.
    """
    para = (
        "The quick brown fox jumps over the lazy dog. Pack my box with "
        "five dozen liquor jugs. How razorback-jumping frogs can level "
        "six piqued gymnasts. Sphinx of black quartz judge my vow. "
        "Amazingly few discotheques provide jukeboxes. Crazy Fredrick "
        "bought many very exquisite opal jewels. We promptly judged "
        "antique ivory buckles for the next prize. A wizard's job is "
        "to vex chumps quickly in fog. Jaded zombies acted quaintly "
        "but kept driving their oxen forward. "
    )
    out = []
    n = 0
    while n < target_chars:
        out.append(para)
        n += len(para)
    return "".join(out)[:target_chars]


def build_anthropic_request(prompt: str) -> Tuple[str, Dict[str, str], Dict[str, Any]]:
    key = os.environ["ANTHROPIC_API_KEY"]
    url = "https://api.anthropic.com/v1/messages"
    headers = {
        "Content-Type": "application/json",
        "x-api-key": key,
        "anthropic-version": "2023-06-01",
    }
    # Allow env overrides so the harness can flip between reasoning vs non-reasoning
    # and high vs low max_tokens without code edits.
    model = os.environ.get("ANTHROPIC_MODEL", "claude-opus-4-5")
    max_tokens = int(os.environ.get("ANTHROPIC_MAX_TOKENS", "256"))
    body: Dict[str, Any] = {
        "model": model,
        "max_tokens": max_tokens,
        "messages": [
            {
                "role": "user",
                "content": prompt
                + "\n\nReply with a single short sentence summarising the above.",
            }
        ],
    }
    # Toggle extended thinking on demand — this is the reasoning path that pushes
    # pre-first-byte latency above the 60s intermediary timeout in KF-002.
    if os.environ.get("ANTHROPIC_THINKING", "").lower() in ("1", "true", "yes"):
        body["thinking"] = {"type": "enabled", "budget_tokens": 8000}
        # Anthropic requires max_tokens > budget_tokens when thinking is on.
        if body["max_tokens"] <= 8000:
            body["max_tokens"] = 9000
    return url, headers, body


def build_openai_request(prompt: str) -> Tuple[str, Dict[str, str], Dict[str, Any]]:
    key = os.environ["OPENAI_API_KEY"]
    url = "https://api.openai.com/v1/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {key}",
    }
    body = {
        "model": "gpt-4o-mini",  # cheap + non-reasoning
        "max_tokens": 256,
        "messages": [
            {
                "role": "user",
                "content": prompt
                + "\n\nReply with a single short sentence summarising the above.",
            }
        ],
    }
    return url, headers, body


# --- Variants ---


def v0_httpx_post_h11(url: str, headers: Dict[str, str], body: Dict[str, Any]) -> dict:
    """Control: matches cheval base.py http_post() exactly."""
    encoded = json.dumps(body).encode("utf-8")
    timeout = httpx.Timeout(connect=10.0, read=300.0, write=120.0, pool=10.0)
    resp = httpx.post(url, headers=headers, content=encoded, timeout=timeout)
    return {"status": resp.status_code, "http_version": resp.http_version, "bytes": len(resp.content)}


def v1_httpx_client_h2(url: str, headers: Dict[str, str], body: Dict[str, Any]) -> dict:
    """HTTP/2 via persistent Client."""
    encoded = json.dumps(body).encode("utf-8")
    timeout = httpx.Timeout(connect=10.0, read=300.0, write=120.0, pool=10.0)
    with httpx.Client(http2=True, timeout=timeout) as client:
        resp = client.post(url, headers=headers, content=encoded)
        return {"status": resp.status_code, "http_version": resp.http_version, "bytes": len(resp.content)}


def v2_httpx_stream(url: str, headers: Dict[str, str], body: Dict[str, Any]) -> dict:
    """Streaming response — body has stream:true."""
    streamed_body = dict(body)
    streamed_body["stream"] = True
    encoded = json.dumps(streamed_body).encode("utf-8")
    timeout = httpx.Timeout(connect=10.0, read=300.0, write=120.0, pool=10.0)
    chunks = 0
    first_byte_at = None
    total_bytes = 0
    start = time.monotonic()
    with httpx.Client(timeout=timeout) as client:
        with client.stream("POST", url, headers=headers, content=encoded) as resp:
            for chunk in resp.iter_bytes():
                if first_byte_at is None:
                    first_byte_at = time.monotonic() - start
                chunks += 1
                total_bytes += len(chunk)
            return {
                "status": resp.status_code,
                "http_version": resp.http_version,
                "chunks": chunks,
                "bytes": total_bytes,
                "ttfb_s": first_byte_at,
            }


def v3_httpx_h11_keepalive(url: str, headers: Dict[str, str], body: Dict[str, Any]) -> dict:
    """HTTP/1.1 with TCP_KEEPALIVE socket option enabled."""
    import httpcore

    class _KeepaliveTransport(httpx.HTTPTransport):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, **kwargs)

    # httpx doesn't expose socket options cleanly; we set kernel keepalive
    # via the socket factory used by httpcore. Simplest: monkey-patch
    # socket.socket to set SO_KEEPALIVE on every new socket for this call.
    original_socket = socket.socket

    class KeepaliveSocket(original_socket):  # type: ignore[misc,valid-type]
        def __init__(self, *a, **kw):
            super().__init__(*a, **kw)
            try:
                self.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
                # Linux-specific TCP keepalive tuning: probe every 20s after 20s idle.
                if hasattr(socket, "TCP_KEEPIDLE"):
                    self.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPIDLE, 20)
                if hasattr(socket, "TCP_KEEPINTVL"):
                    self.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPINTVL, 20)
                if hasattr(socket, "TCP_KEEPCNT"):
                    self.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPCNT, 3)
            except OSError:
                pass

    socket.socket = KeepaliveSocket  # type: ignore[misc,assignment]
    try:
        encoded = json.dumps(body).encode("utf-8")
        timeout = httpx.Timeout(connect=10.0, read=300.0, write=120.0, pool=10.0)
        with httpx.Client(timeout=timeout) as client:
            resp = client.post(url, headers=headers, content=encoded)
            return {"status": resp.status_code, "http_version": resp.http_version, "bytes": len(resp.content)}
    finally:
        socket.socket = original_socket  # type: ignore[misc,assignment]


VARIANTS = {
    "V0_h11_post":    v0_httpx_post_h11,
    "V1_h2_client":   v1_httpx_client_h2,
    "V2_stream_h11":  v2_httpx_stream,
    "V3_h11_keepalv": v3_httpx_h11_keepalive,
}


def run(provider: str, target_chars: int, variants: list[str]) -> None:
    prompt = make_prompt(target_chars)
    if provider == "anthropic":
        url, headers, body = build_anthropic_request(prompt)
    elif provider == "openai":
        url, headers, body = build_openai_request(prompt)
    else:
        raise SystemExit(f"unknown provider: {provider}")

    body_size = len(json.dumps(body).encode("utf-8"))
    print(f"\n=== Provider: {provider} | prompt_chars: {target_chars:,} | body_bytes: {body_size:,} ===")

    for vname in variants:
        if vname not in VARIANTS:
            print(f"  [skip] unknown variant {vname}")
            continue
        fn = VARIANTS[vname]
        start = time.monotonic()
        try:
            result = fn(url, headers, body)
            elapsed = time.monotonic() - start
            print(f"  [PASS] {vname:18s} elapsed={elapsed:6.2f}s  {result}")
        except Exception as e:
            elapsed = time.monotonic() - start
            exc_class = type(e).__name__
            msg = str(e)[:120]
            print(f"  [FAIL] {vname:18s} elapsed={elapsed:6.2f}s  {exc_class}: {msg}")


if __name__ == "__main__":
    provider = sys.argv[1] if len(sys.argv) > 1 else "anthropic"
    chars = int(sys.argv[2]) if len(sys.argv) > 2 else 120_000
    variants = sys.argv[3].split(",") if len(sys.argv) > 3 else list(VARIANTS.keys())
    run(provider, chars, variants)
