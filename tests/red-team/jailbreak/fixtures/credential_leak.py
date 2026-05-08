"""Credential-leak fixtures (cycle-100 RT-CL-*) — Python parity."""

from __future__ import annotations


def _make_evil_body_rt_cl_001() -> str:
    p, rest, label = "AKIA", "IOSFODNN7EXAMPLE", "AWS_ACCESS_KEY_ID"
    return f"Diagnostic snapshot {label}={p}{rest}\n"


def _make_evil_body_rt_cl_002() -> str:
    p1, p2, rest, label = "sk-", "proj-", "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "OPENAI_API_KEY"
    return f"config: {label}={p1}{p2}{rest}_synthetic\n"


def _make_evil_body_rt_cl_003() -> str:
    p, rest = "ghp_", "abcdefghijklmnopqrstuvwxyz0123456789"
    return f"token: {p}{rest}\n"


def _make_evil_body_rt_cl_004() -> str:
    key, val = "password", "hunter2_synthetic_test_only"
    return f"login config {key}={val}\n"


def _make_evil_body_rt_cl_005() -> str:
    t, k, i = "service_account", "private_key", "private_key_id"
    id_val = "ABCDEF1234567890"
    fp = "-----BEGIN PRIVATE KEY-----\\nMIIE...synthetic...\\n-----END PRIVATE KEY-----"
    return f'{{"type":"{t}","{i}":"{id_val}","{k}":"{fp}"}}\n'


def _make_evil_body_rt_cl_006() -> str:
    hdr, scheme = "Authorization", "Bearer"
    p1 = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9"
    p2 = "eyJzdWIiOiJ0ZXN0LXN1YmplY3QiLCJyb2xlIjoidXNlciJ9"
    p3 = "synthetic_signature_part_only"
    return f"{hdr}: {scheme} {p1}.{p2}.{p3}\n"


FIXTURES = {
    "RT-CL-001": _make_evil_body_rt_cl_001,
    "RT-CL-002": _make_evil_body_rt_cl_002,
    "RT-CL-003": _make_evil_body_rt_cl_003,
    "RT-CL-004": _make_evil_body_rt_cl_004,
    "RT-CL-005": _make_evil_body_rt_cl_005,
    "RT-CL-006": _make_evil_body_rt_cl_006,
}
