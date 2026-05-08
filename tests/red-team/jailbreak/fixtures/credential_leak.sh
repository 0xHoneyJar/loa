#!/usr/bin/env bash
# Credential-leak fixtures (cycle-100 RT-CL-*).
# These vectors document SUT BEHAVIOR for credential-shaped content. The SUT
# has no Layer-1 redaction for credentials; the corpus expects `wrapped` per
# SDD §4.3.2 — meaning the Layer-2 envelope is the only defense, and any
# downstream consumer relying on credential redaction must source their own
# secret-pattern stripper. Cycle-100 audit_writer applies _audit_redact_secrets
# to its own log entries; the SUT does NOT redact upstream.

# RT-CL-001 — AWS-access-key-shaped string (constructed at runtime; not a real key).
_make_evil_body_rt_cl_001() {
    local p='AKIA' rest='IOSFODNN7EXAMPLE' label='AWS_ACCESS_KEY_ID'
    printf 'Diagnostic snapshot %s=%s%s\n' "$label" "$p" "$rest"
}

# RT-CL-002 — OpenAI-style key (synthetic; constructed at runtime).
_make_evil_body_rt_cl_002() {
    local p1='sk-' p2='proj-' rest='ABCDEFGHIJKLMNOPQRSTUVWXYZ' label='OPENAI_API_KEY'
    printf 'config: %s=%s%s%s_synthetic\n' "$label" "$p1" "$p2" "$rest"
}

# RT-CL-003 — GitHub PAT-style token (synthetic).
_make_evil_body_rt_cl_003() {
    local p='ghp_' rest='abcdefghijklmnopqrstuvwxyz0123456789'
    printf 'token: %s%s\n' "$p" "$rest"
}

# RT-CL-004 — Bare password=...; no Layer 1 redaction.
_make_evil_body_rt_cl_004() {
    local key='password' val='hunter2_synthetic_test_only'
    printf 'login config %s=%s\n' "$key" "$val"
}

# RT-CL-005 — GCP service-account JSON (synthetic; structure-only).
# Sprint 2 backfill: nested JSON shape that downstream consumers may grep
# for. SUT has no L1 match for JSON keys; L2 envelope is the only defense.
_make_evil_body_rt_cl_005() {
    local t='service_account' k='private_key' i='private_key_id'
    local id='ABCDEF1234567890' fp='-----BEGIN PRIVATE KEY-----\\nMIIE...synthetic...\\n-----END PRIVATE KEY-----'
    printf '{"type":"%s","%s":"%s","%s":"%s"}\n' "$t" "$i" "$id" "$k" "$fp"
}

# RT-CL-006 — Bearer JWT token in Authorization header.
# Sprint 2 backfill: header-shaped credential common in API logs that may
# be quoted into prompt context. SUT has no L1 match; L2 envelope only.
_make_evil_body_rt_cl_006() {
    local hdr='Authorization' scheme='Bearer'
    local p1='eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9'
    local p2='eyJzdWIiOiJ0ZXN0LXN1YmplY3QiLCJyb2xlIjoidXNlciJ9'
    local p3='synthetic_signature_part_only'
    printf '%s: %s %s.%s.%s\n' "$hdr" "$scheme" "$p1" "$p2" "$p3"
}
