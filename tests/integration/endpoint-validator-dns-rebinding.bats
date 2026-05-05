#!/usr/bin/env bats
# =============================================================================
# tests/integration/endpoint-validator-dns-rebinding.bats
#
# cycle-099 Sprint 1E.c.2 — DNS rebinding + HTTP redirect enforcement.
#
# Per SDD §1.9.1 + NFR-Sec-1 v1.2, the validator exposes:
#   - lock_resolved_ip(host) → LockedIP        (resolve once, lock the pair)
#   - verify_locked_ip(locked, host) → bool    (re-resolve, check unchanged)
#   - validate_redirect(orig_locked, new_url, allowlist) → ValidationResult
#
# DNS is mocked via monkeypatching `socket.getaddrinfo` at runtime so the
# test corpus runs offline. Each test asserts the expected rejection code
# (ENDPOINT-DNS-REBOUND, ENDPOINT-REDIRECT-DENIED, ENDPOINT-DNS-RESOLUTION-FAILED)
# or the expected acceptance.
#
# Sprint-1E.c.2 ships Python-only — the TS port from 1E.c.1 doesn't include
# DNS APIs (sync TS would need Promise<LockedIP> which doesn't fit the
# codegen template's sync model). Bash wrapper delegates.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    PY_VALIDATOR="$PROJECT_ROOT/.claude/scripts/lib/endpoint-validator.py"
    ALLOWLIST="$PROJECT_ROOT/tests/fixtures/endpoint-validator/allowlist.json"

    [[ -f "$PY_VALIDATOR" ]] || skip "endpoint-validator.py not present"
    [[ -f "$ALLOWLIST" ]] || skip "allowlist fixture not present"

    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="${PYTHON_BIN:-python3}"
    fi

    WORK_DIR="$(mktemp -d)"
}

teardown() {
    if [[ -n "${WORK_DIR:-}" ]] && [[ -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
    return 0
}

# Helper: invoke a Python expression that imports the canonical via
# spec_loader (same pattern as the codegen module) and runs the assertion.
# Paths are passed via env vars to avoid heredoc shell-injection.
_python_assert() {
    PY_VALIDATOR="$PY_VALIDATOR" \
    ALLOWLIST="$ALLOWLIST" \
    WORK_DIR="$WORK_DIR" \
    PROJECT_ROOT="$PROJECT_ROOT" \
    "$PYTHON_BIN" -
}

# ---------------------------------------------------------------------------
# L — lock_resolved_ip
# ---------------------------------------------------------------------------

@test "L1 lock: returns LockedIP for resolvable host" {
    _python_assert <<'EOF'
import importlib.util, os, socket, sys
spec = importlib.util.spec_from_file_location("ev", os.environ["PY_VALIDATOR"])
m = importlib.util.module_from_spec(spec)
sys.modules["ev"] = m
spec.loader.exec_module(m)

# Monkeypatch getaddrinfo to return a deterministic IPv4.
def fake_getaddrinfo(host, port, *args, **kwargs):
    return [(socket.AF_INET, socket.SOCK_STREAM, 0, "", ("8.8.8.8", port or 443))]
m.socket.getaddrinfo = fake_getaddrinfo

locked = m.lock_resolved_ip("api.openai.com")
assert locked.host == "api.openai.com", f"host mismatch: {locked}"
assert locked.ip == "8.8.8.8", f"ip mismatch: {locked}"
assert locked.family in (socket.AF_INET, socket.AF_INET6)
EOF
}

@test "L2 lock: raises DnsResolutionError on getaddrinfo failure" {
    _python_assert <<'EOF'
import importlib.util, os, socket, sys
spec = importlib.util.spec_from_file_location("ev", os.environ["PY_VALIDATOR"])
m = importlib.util.module_from_spec(spec)
sys.modules["ev"] = m
spec.loader.exec_module(m)

def failing_getaddrinfo(*args, **kwargs):
    raise socket.gaierror(-2, "Name or service not known")
m.socket.getaddrinfo = failing_getaddrinfo

try:
    m.lock_resolved_ip("nonexistent.example.invalid")
    raise AssertionError("expected DnsResolutionError")
except m.DnsResolutionError as e:
    assert "DNS-RESOLUTION-FAILED" in str(e), f"unexpected error: {e}"
EOF
}

@test "L3 lock: rejects IPv4 in blocked range (private, loopback, IMDS)" {
    _python_assert <<'EOF'
import importlib.util, os, socket, sys
spec = importlib.util.spec_from_file_location("ev", os.environ["PY_VALIDATOR"])
m = importlib.util.module_from_spec(spec)
sys.modules["ev"] = m
spec.loader.exec_module(m)

def imds_getaddrinfo(host, port, *args, **kwargs):
    # Operator allowlists api.example.com but DNS resolves it to AWS IMDS.
    return [(socket.AF_INET, socket.SOCK_STREAM, 0, "", ("169.254.169.254", port or 443))]
m.socket.getaddrinfo = imds_getaddrinfo

try:
    m.lock_resolved_ip("api.example.com")
    raise AssertionError("expected DnsRebindingError on IMDS resolution")
except m.DnsRebindingError as e:
    # F3 (BB iter-1): tightened to single specific code. ENDPOINT-IP-BLOCKED
    # is the load-time check; DNS-REBOUND fires only on subsequent re-resolve.
    assert "ENDPOINT-IP-BLOCKED" in str(e), f"unexpected: {e}"
    assert "AWS IMDS" in str(e), f"expected IMDS-specific reason; got {e}"
EOF
}

# ---------------------------------------------------------------------------
# V — verify_locked_ip
# ---------------------------------------------------------------------------

@test "V1 verify: stable resolution succeeds" {
    _python_assert <<'EOF'
import importlib.util, os, socket, sys
spec = importlib.util.spec_from_file_location("ev", os.environ["PY_VALIDATOR"])
m = importlib.util.module_from_spec(spec)
sys.modules["ev"] = m
spec.loader.exec_module(m)

def stable_getaddrinfo(host, port, *args, **kwargs):
    return [(socket.AF_INET, socket.SOCK_STREAM, 0, "", ("8.8.8.8", port or 443))]
m.socket.getaddrinfo = stable_getaddrinfo

locked = m.lock_resolved_ip("api.openai.com")
# Re-resolve; same IP returned. Must succeed.
assert m.verify_locked_ip(locked) is True
EOF
}

@test "V2 verify: changed IP raises DnsRebindingError" {
    _python_assert <<'EOF'
import importlib.util, os, socket, sys
spec = importlib.util.spec_from_file_location("ev", os.environ["PY_VALIDATOR"])
m = importlib.util.module_from_spec(spec)
sys.modules["ev"] = m
spec.loader.exec_module(m)

# Phase 1: resolve to public IP. Lock.
state = {"call": 0}
def shifting_getaddrinfo(host, port, *args, **kwargs):
    state["call"] += 1
    if state["call"] == 1:
        return [(socket.AF_INET, socket.SOCK_STREAM, 0, "", ("8.8.8.8", port or 443))]
    # Phase 2: re-resolve to attacker-controlled internal IP — DNS rebinding.
    return [(socket.AF_INET, socket.SOCK_STREAM, 0, "", ("169.254.169.254", port or 443))]
m.socket.getaddrinfo = shifting_getaddrinfo

locked = m.lock_resolved_ip("api.openai.com")
try:
    m.verify_locked_ip(locked)
    raise AssertionError("expected DnsRebindingError")
except m.DnsRebindingError as e:
    assert "ENDPOINT-DNS-REBOUND" in str(e), f"unexpected: {e}"
EOF
}

@test "V3 verify: multi-record resolution accepts ANY record matching locked IP" {
    _python_assert <<'EOF'
import importlib.util, os, socket, sys
spec = importlib.util.spec_from_file_location("ev", os.environ["PY_VALIDATOR"])
m = importlib.util.module_from_spec(spec)
sys.modules["ev"] = m
spec.loader.exec_module(m)

# CDN-style: getaddrinfo returns multiple A records. Lock picks the first.
# On re-resolve, the first record may differ (round-robin) but if any
# record matches the locked IP, that's the same backend pool.
state = {"call": 0}
def cdn_getaddrinfo(host, port, *args, **kwargs):
    state["call"] += 1
    if state["call"] == 1:
        return [
            (socket.AF_INET, socket.SOCK_STREAM, 0, "", ("8.8.8.8", port or 443)),
            (socket.AF_INET, socket.SOCK_STREAM, 0, "", ("1.1.1.1", port or 443)),
        ]
    return [
        (socket.AF_INET, socket.SOCK_STREAM, 0, "", ("1.1.1.1", port or 443)),
        (socket.AF_INET, socket.SOCK_STREAM, 0, "", ("8.8.8.8", port or 443)),
    ]
m.socket.getaddrinfo = cdn_getaddrinfo

locked = m.lock_resolved_ip("api.openai.com")
# Original locked IP was the first in phase-1 (8.8.8.8); phase-2 record
# set still includes 8.8.8.8 — must accept.
assert m.verify_locked_ip(locked) is True
EOF
}

# ---------------------------------------------------------------------------
# R — validate_redirect
# ---------------------------------------------------------------------------

@test "R1 redirect: same-host same-IP redirect accepted" {
    _python_assert <<'EOF'
import importlib.util, json, os, socket, sys
spec = importlib.util.spec_from_file_location("ev", os.environ["PY_VALIDATOR"])
m = importlib.util.module_from_spec(spec)
sys.modules["ev"] = m
spec.loader.exec_module(m)

def stable_getaddrinfo(host, port, *args, **kwargs):
    return [(socket.AF_INET, socket.SOCK_STREAM, 0, "", ("8.8.8.8", port or 443))]
m.socket.getaddrinfo = stable_getaddrinfo

with open(os.environ["ALLOWLIST"]) as f:
    allowlist = json.load(f).get("providers", {})
orig = m.validate("https://api.openai.com/v1", allowlist)
assert orig.valid
locked = m.lock_resolved_ip(orig.host)

# Redirect to same host, different path — should accept.
result = m.validate_redirect(locked, "https://api.openai.com/v1/redirected", allowlist)
assert result.valid, f"expected accept; got {result.code}"
EOF
}

@test "R2 redirect: cross-host redirect rejected with REDIRECT-DENIED" {
    _python_assert <<'EOF'
import importlib.util, json, os, socket, sys
spec = importlib.util.spec_from_file_location("ev", os.environ["PY_VALIDATOR"])
m = importlib.util.module_from_spec(spec)
sys.modules["ev"] = m
spec.loader.exec_module(m)

def stable_getaddrinfo(host, port, *args, **kwargs):
    if host == "api.openai.com":
        return [(socket.AF_INET, socket.SOCK_STREAM, 0, "", ("8.8.8.8", port or 443))]
    return [(socket.AF_INET, socket.SOCK_STREAM, 0, "", ("9.9.9.9", port or 443))]
m.socket.getaddrinfo = stable_getaddrinfo

with open(os.environ["ALLOWLIST"]) as f:
    allowlist = json.load(f).get("providers", {})
orig = m.validate("https://api.openai.com/v1", allowlist)
locked = m.lock_resolved_ip(orig.host)

result = m.validate_redirect(locked, "https://api.anthropic.com/v1", allowlist)
assert not result.valid
assert result.code == "ENDPOINT-REDIRECT-DENIED", f"unexpected: {result.code}"
EOF
}

@test "R3 redirect: same-host with rebound IP rejected" {
    _python_assert <<'EOF'
import importlib.util, json, os, socket, sys
spec = importlib.util.spec_from_file_location("ev", os.environ["PY_VALIDATOR"])
m = importlib.util.module_from_spec(spec)
sys.modules["ev"] = m
spec.loader.exec_module(m)

state = {"call": 0}
def shifting_getaddrinfo(host, port, *args, **kwargs):
    state["call"] += 1
    if state["call"] <= 1:
        return [(socket.AF_INET, socket.SOCK_STREAM, 0, "", ("8.8.8.8", port or 443))]
    return [(socket.AF_INET, socket.SOCK_STREAM, 0, "", ("169.254.169.254", port or 443))]
m.socket.getaddrinfo = shifting_getaddrinfo

with open(os.environ["ALLOWLIST"]) as f:
    allowlist = json.load(f).get("providers", {})
orig = m.validate("https://api.openai.com/v1", allowlist)
locked = m.lock_resolved_ip(orig.host)

# Phase 2 returns rebinding-style internal IP. validate_redirect must reject
# even when the URL host matches the locked host.
result = m.validate_redirect(locked, "https://api.openai.com/v1/sub", allowlist)
assert not result.valid
assert result.code in ("ENDPOINT-DNS-REBOUND", "ENDPOINT-IP-BLOCKED"), f"unexpected: {result.code}"
EOF
}

@test "R4 redirect: validation pipeline still applies (e.g., scheme rejected)" {
    _python_assert <<'EOF'
import importlib.util, json, os, socket, sys
spec = importlib.util.spec_from_file_location("ev", os.environ["PY_VALIDATOR"])
m = importlib.util.module_from_spec(spec)
sys.modules["ev"] = m
spec.loader.exec_module(m)

def stable_getaddrinfo(host, port, *args, **kwargs):
    return [(socket.AF_INET, socket.SOCK_STREAM, 0, "", ("8.8.8.8", port or 443))]
m.socket.getaddrinfo = stable_getaddrinfo

with open(os.environ["ALLOWLIST"]) as f:
    allowlist = json.load(f).get("providers", {})
orig = m.validate("https://api.openai.com/v1", allowlist)
locked = m.lock_resolved_ip(orig.host)

# Redirect downgrade to http should fail at the canonicalization gate, not
# the same-host gate — verify the code reflects scheme-rejection.
result = m.validate_redirect(locked, "http://api.openai.com/v1", allowlist)
assert not result.valid
assert result.code == "ENDPOINT-INSECURE-SCHEME", f"unexpected: {result.code}"
EOF
}

# ---------------------------------------------------------------------------
# C — cdn_cidr_exemptions (per SDD §1.9 — relaxing semantics for CDN-fronted
# providers; matching IPs SKIP the blocked-range check)
# ---------------------------------------------------------------------------

@test "C1 cdn_exemption: in-CIDR private IP bypasses blocked-range check" {
    _python_assert <<'EOF'
import importlib.util, os, socket, sys
spec = importlib.util.spec_from_file_location("ev", os.environ["PY_VALIDATOR"])
m = importlib.util.module_from_spec(spec)
sys.modules["ev"] = m
spec.loader.exec_module(m)

def cdn_getaddrinfo(host, port, *args, **kwargs):
    return [(socket.AF_INET, socket.SOCK_STREAM, 0, "", ("10.0.0.5", port or 443))]
m.socket.getaddrinfo = cdn_getaddrinfo

# 10.0.0.0/8 is normally rejected as RFC 1918 private. Operator declares it
# as a CDN exemption (legitimate for self-hosted CDN-fronted endpoints).
allowlist = {
    "openai": [
        {"host": "api.openai.com", "ports": [443], "cdn_cidr_exemptions": ["10.0.0.0/8"]},
    ],
}
locked = m.lock_resolved_ip("api.openai.com", allowlist=allowlist, provider_id="openai")
assert locked.ip == "10.0.0.5", f"expected exempted private IP; got {locked.ip}"
EOF
}

@test "C2 cdn_exemption: NOT in CIDR → standard blocked-range check fires" {
    _python_assert <<'EOF'
import importlib.util, os, socket, sys
spec = importlib.util.spec_from_file_location("ev", os.environ["PY_VALIDATOR"])
m = importlib.util.module_from_spec(spec)
sys.modules["ev"] = m
spec.loader.exec_module(m)

def out_of_exemption_getaddrinfo(host, port, *args, **kwargs):
    # Operator's exemption is 10.0.0.0/8 but resolution lands on 192.168.1.1
    # (also private, but NOT in the configured exemption).
    return [(socket.AF_INET, socket.SOCK_STREAM, 0, "", ("192.168.1.1", port or 443))]
m.socket.getaddrinfo = out_of_exemption_getaddrinfo

allowlist = {
    "openai": [
        {"host": "api.openai.com", "ports": [443], "cdn_cidr_exemptions": ["10.0.0.0/8"]},
    ],
}
try:
    m.lock_resolved_ip("api.openai.com", allowlist=allowlist, provider_id="openai")
    raise AssertionError("expected DnsRebindingError on private IP outside exemption")
except m.DnsRebindingError as e:
    assert "ENDPOINT-IP-BLOCKED" in str(e), f"unexpected: {e}"
EOF
}

@test "C3 cdn_exemption_extra: operator-side extension is honored" {
    _python_assert <<'EOF'
import importlib.util, os, socket, sys
spec = importlib.util.spec_from_file_location("ev", os.environ["PY_VALIDATOR"])
m = importlib.util.module_from_spec(spec)
sys.modules["ev"] = m
spec.loader.exec_module(m)

def cdn_getaddrinfo(host, port, *args, **kwargs):
    return [(socket.AF_INET, socket.SOCK_STREAM, 0, "", ("10.0.0.5", port or 443))]
m.socket.getaddrinfo = cdn_getaddrinfo

# Framework defaults are empty; operator extends with their own range. The
# union of both sets should be honored per SDD §1.9.
allowlist = {
    "openai": [
        {
            "host": "api.openai.com",
            "ports": [443],
            "cdn_cidr_exemptions": [],
            "cdn_cidr_exemptions_extra": ["10.0.0.0/8"],
        },
    ],
}
locked = m.lock_resolved_ip("api.openai.com", allowlist=allowlist, provider_id="openai")
assert locked.ip == "10.0.0.5"
EOF
}

@test "C4 cdn_exemption: missing field → standard blocked-range check applies" {
    _python_assert <<'EOF'
import importlib.util, os, socket, sys
spec = importlib.util.spec_from_file_location("ev", os.environ["PY_VALIDATOR"])
m = importlib.util.module_from_spec(spec)
sys.modules["ev"] = m
spec.loader.exec_module(m)

def imds_getaddrinfo(host, port, *args, **kwargs):
    return [(socket.AF_INET, socket.SOCK_STREAM, 0, "", ("169.254.169.254", port or 443))]
m.socket.getaddrinfo = imds_getaddrinfo

# Provider entry has no cdn_cidr_exemptions — standard check fires.
allowlist = {
    "openai": [{"host": "api.openai.com", "ports": [443]}],
}
try:
    m.lock_resolved_ip("api.openai.com", allowlist=allowlist, provider_id="openai")
    raise AssertionError("expected IMDS rejection")
except m.DnsRebindingError as e:
    assert "ENDPOINT-IP-BLOCKED" in str(e), f"unexpected: {e}"
EOF
}

# ---------------------------------------------------------------------------
# H — Happy Eyeballs / dual-stack hardening (cypherpunk MEDIUM)
# ---------------------------------------------------------------------------

@test "H1 dual-stack: ALL records in set checked, not just records[0]" {
    _python_assert <<'EOF'
import importlib.util, os, socket, sys
spec = importlib.util.spec_from_file_location("ev", os.environ["PY_VALIDATOR"])
m = importlib.util.module_from_spec(spec)
sys.modules["ev"] = m
spec.loader.exec_module(m)

# Phase-1: getaddrinfo returns [public IPv4 8.8.8.8, IMDS 169.254.169.254].
# Records[0] is benign but Happy Eyeballs / OS connect could pivot to
# records[1]. The validator MUST reject when ANY record is blocked.
def dual_stack_getaddrinfo(host, port, *args, **kwargs):
    return [
        (socket.AF_INET, socket.SOCK_STREAM, 0, "", ("8.8.8.8", port or 443)),
        (socket.AF_INET, socket.SOCK_STREAM, 0, "", ("169.254.169.254", port or 443)),
    ]
m.socket.getaddrinfo = dual_stack_getaddrinfo

try:
    m.lock_resolved_ip("api.openai.com")
    raise AssertionError("expected blocked-range rejection on records[1] IMDS")
except m.DnsRebindingError as e:
    assert "ENDPOINT-IP-BLOCKED" in str(e), f"unexpected: {e}"
EOF
}

# ---------------------------------------------------------------------------
# N — LockedIP normalization + forge-defense (cypherpunk HIGH 2 + LOW)
# ---------------------------------------------------------------------------

@test "N1 normalize: trailing-dot FQDN + uppercase host normalized" {
    _python_assert <<'EOF'
import importlib.util, os, socket, sys
spec = importlib.util.spec_from_file_location("ev", os.environ["PY_VALIDATOR"])
m = importlib.util.module_from_spec(spec)
sys.modules["ev"] = m
spec.loader.exec_module(m)

def stable_getaddrinfo(host, port, *args, **kwargs):
    return [(socket.AF_INET, socket.SOCK_STREAM, 0, "", ("8.8.8.8", port or 443))]
m.socket.getaddrinfo = stable_getaddrinfo

locked = m.lock_resolved_ip("API.OpenAI.com.")
# host normalized to lowercase + trailing-dot stripped at __post_init__.
assert locked.host == "api.openai.com", f"unexpected host: {locked.host!r}"
EOF
}

@test "N2 forge-defense: LockedIP construction with garbage IP fails fast" {
    _python_assert <<'EOF'
import importlib.util, os, socket, sys
spec = importlib.util.spec_from_file_location("ev", os.environ["PY_VALIDATOR"])
m = importlib.util.module_from_spec(spec)
sys.modules["ev"] = m
spec.loader.exec_module(m)

# Forged LockedIP from a JSON state file with garbage IP must reject at
# __post_init__ rather than silently accepting.
try:
    m.LockedIP(host="api.openai.com", ip="not-an-ip", family=socket.AF_INET, port=443)
    raise AssertionError("expected ValueError on invalid IP")
except ValueError as e:
    assert "not a valid IP" in str(e), f"unexpected: {e}"
EOF
}

# ---------------------------------------------------------------------------
# P — Port-pivot defense in validate_redirect (gp MEDIUM)
# ---------------------------------------------------------------------------

@test "P1 redirect: same-host different-port rejected (port-pivot defense)" {
    _python_assert <<'EOF'
import importlib.util, os, socket, sys
spec = importlib.util.spec_from_file_location("ev", os.environ["PY_VALIDATOR"])
m = importlib.util.module_from_spec(spec)
sys.modules["ev"] = m
spec.loader.exec_module(m)

def stable_getaddrinfo(host, port, *args, **kwargs):
    return [(socket.AF_INET, socket.SOCK_STREAM, 0, "", ("8.8.8.8", port or 443))]
m.socket.getaddrinfo = stable_getaddrinfo

# Allowlist openai with two ports (operator allowed both 443 and 8443).
allowlist = {
    "openai": [{"host": "api.openai.com", "ports": [443, 8443]}],
}
orig = m.validate("https://api.openai.com/v1", allowlist)
assert orig.valid
locked = m.lock_resolved_ip(orig.host)

# Redirect to the SAME host but on the alternate allowlisted port.
# 8-step pipeline accepts (port allowlisted), but validate_redirect rejects
# because the lock was made at port 443 — locking is per-port.
result = m.validate_redirect(locked, "https://api.openai.com:8443/v1", allowlist)
assert not result.valid
assert result.code == "ENDPOINT-REDIRECT-DENIED", f"unexpected: {result.code}"
assert "port" in result.detail.lower()
EOF
}

# ---------------------------------------------------------------------------
# X — Multi-hop redirect chain helper (cypherpunk MEDIUM)
# ---------------------------------------------------------------------------

@test "X1 chain: per-hop validation rejects mid-chain bounce to new host" {
    _python_assert <<'EOF'
import importlib.util, json, os, socket, sys
spec = importlib.util.spec_from_file_location("ev", os.environ["PY_VALIDATOR"])
m = importlib.util.module_from_spec(spec)
sys.modules["ev"] = m
spec.loader.exec_module(m)

def stable_getaddrinfo(host, port, *args, **kwargs):
    return [(socket.AF_INET, socket.SOCK_STREAM, 0, "", ("8.8.8.8", port or 443))]
m.socket.getaddrinfo = stable_getaddrinfo

with open(os.environ["ALLOWLIST"]) as f:
    allowlist = json.load(f).get("providers", {})
orig = m.validate("https://api.openai.com/v1", allowlist)
locked = m.lock_resolved_ip(orig.host)

# Chain: same-host → same-host → cross-host (attacker goal). Helper rejects
# at the third hop, NOT silently accept-and-follow.
chain = [
    "https://api.openai.com/v1/step1",
    "https://api.openai.com/v1/step2",
    "https://api.anthropic.com/v1",
]
result = m.validate_redirect_chain(locked, chain, allowlist)
assert not result.valid
assert result.code == "ENDPOINT-REDIRECT-DENIED", f"unexpected: {result.code}"
EOF
}

@test "X3 chain: rejects chains longer than max_hops (default 10)" {
    _python_assert <<'EOF'
import importlib.util, json, os, socket, sys
spec = importlib.util.spec_from_file_location("ev", os.environ["PY_VALIDATOR"])
m = importlib.util.module_from_spec(spec)
sys.modules["ev"] = m
spec.loader.exec_module(m)

def stable_getaddrinfo(host, port, *args, **kwargs):
    return [(socket.AF_INET, socket.SOCK_STREAM, 0, "", ("8.8.8.8", port or 443))]
m.socket.getaddrinfo = stable_getaddrinfo

with open(os.environ["ALLOWLIST"]) as f:
    allowlist = json.load(f).get("providers", {})
locked = m.lock_resolved_ip("api.openai.com")

# 11-hop chain (default max is 10) — must reject before validating any hop.
chain = [f"https://api.openai.com/v1/step{i}" for i in range(11)]
result = m.validate_redirect_chain(locked, chain, allowlist)
assert not result.valid
assert result.code == "ENDPOINT-REDIRECT-DENIED"
assert "max_hops" in result.detail
EOF
}

@test "X2 chain: empty chain returns valid (no redirect)" {
    _python_assert <<'EOF'
import importlib.util, json, os, socket, sys
spec = importlib.util.spec_from_file_location("ev", os.environ["PY_VALIDATOR"])
m = importlib.util.module_from_spec(spec)
sys.modules["ev"] = m
spec.loader.exec_module(m)

def stable_getaddrinfo(host, port, *args, **kwargs):
    return [(socket.AF_INET, socket.SOCK_STREAM, 0, "", ("8.8.8.8", port or 443))]
m.socket.getaddrinfo = stable_getaddrinfo

with open(os.environ["ALLOWLIST"]) as f:
    allowlist = json.load(f).get("providers", {})
orig = m.validate("https://api.openai.com/v1", allowlist)
locked = m.lock_resolved_ip(orig.host)

result = m.validate_redirect_chain(locked, [], allowlist)
assert result.valid, f"empty chain should be valid; got {result.code}"
EOF
}

# ---------------------------------------------------------------------------
# B — Common error base + load-time CIDR warning (gp MEDIUM + cypherpunk MEDIUM)
# ---------------------------------------------------------------------------

@test "B1 errors: DnsResolutionError + DnsRebindingError share EndpointDnsError base" {
    _python_assert <<'EOF'
import importlib.util, os, socket, sys
spec = importlib.util.spec_from_file_location("ev", os.environ["PY_VALIDATOR"])
m = importlib.util.module_from_spec(spec)
sys.modules["ev"] = m
spec.loader.exec_module(m)

assert issubclass(m.DnsResolutionError, m.EndpointDnsError)
assert issubclass(m.DnsRebindingError, m.EndpointDnsError)
EOF
}

# ---------------------------------------------------------------------------
# I — IPv6 lock + verify (BB iter-1 F11 — was IPv4-monoculture)
# ---------------------------------------------------------------------------

@test "I1 ipv6 lock: AF_INET6 record locked correctly" {
    _python_assert <<'EOF'
import importlib.util, os, socket, sys
spec = importlib.util.spec_from_file_location("ev", os.environ["PY_VALIDATOR"])
m = importlib.util.module_from_spec(spec)
sys.modules["ev"] = m
spec.loader.exec_module(m)

def v6_getaddrinfo(host, port, *args, **kwargs):
    # Cloudflare DNS public IPv6 — globally routable, not in any blocked range.
    return [(socket.AF_INET6, socket.SOCK_STREAM, 0, "", ("2606:4700:4700::1111", port or 443, 0, 0))]
m.socket.getaddrinfo = v6_getaddrinfo

locked = m.lock_resolved_ip("api.openai.com")
assert locked.ip == "2606:4700:4700::1111"
assert locked.family == socket.AF_INET6
EOF
}

@test "I2 ipv6 lock: link-local fe80:: rejected with link-local reason" {
    _python_assert <<'EOF'
import importlib.util, os, socket, sys
spec = importlib.util.spec_from_file_location("ev", os.environ["PY_VALIDATOR"])
m = importlib.util.module_from_spec(spec)
sys.modules["ev"] = m
spec.loader.exec_module(m)

def linklocal_getaddrinfo(host, port, *args, **kwargs):
    return [(socket.AF_INET6, socket.SOCK_STREAM, 0, "", ("fe80::1", port or 443, 0, 0))]
m.socket.getaddrinfo = linklocal_getaddrinfo

try:
    m.lock_resolved_ip("api.openai.com")
    raise AssertionError("expected IPv6 link-local rejection")
except m.DnsRebindingError as e:
    assert "ENDPOINT-IP-BLOCKED" in str(e)
    assert "link-local" in str(e), f"expected link-local reason; got {e}"
EOF
}

@test "I3 ipv6 lock: AWS IPv6 IMDS (fd00:ec2::254) rejected with IMDS reason" {
    _python_assert <<'EOF'
import importlib.util, os, socket, sys
spec = importlib.util.spec_from_file_location("ev", os.environ["PY_VALIDATOR"])
m = importlib.util.module_from_spec(spec)
sys.modules["ev"] = m
spec.loader.exec_module(m)

def imds_v6_getaddrinfo(host, port, *args, **kwargs):
    return [(socket.AF_INET6, socket.SOCK_STREAM, 0, "", ("fd00:ec2::254", port or 443, 0, 0))]
m.socket.getaddrinfo = imds_v6_getaddrinfo

try:
    m.lock_resolved_ip("api.openai.com")
    raise AssertionError("expected IPv6 IMDS rejection")
except m.DnsRebindingError as e:
    assert "ENDPOINT-IP-BLOCKED" in str(e)
    assert "IMDS" in str(e), f"expected IMDS reason; got {e}"
EOF
}

@test "I4 ipv6 zone-id: stripped before blocked-range check" {
    _python_assert <<'EOF'
import importlib.util, os, socket, sys
spec = importlib.util.spec_from_file_location("ev", os.environ["PY_VALIDATOR"])
m = importlib.util.module_from_spec(spec)
sys.modules["ev"] = m
spec.loader.exec_module(m)

def zone_id_getaddrinfo(host, port, *args, **kwargs):
    # getaddrinfo can include zone-id in sockaddr[0] (e.g., fe80::1%eth0).
    # _resolve_addrinfo strips %... before the blocked-range check.
    return [(socket.AF_INET6, socket.SOCK_STREAM, 0, "", ("fe80::1%eth0", port or 443, 0, 0))]
m.socket.getaddrinfo = zone_id_getaddrinfo

try:
    m.lock_resolved_ip("api.openai.com")
    raise AssertionError("expected link-local rejection (zone-id stripped)")
except m.DnsRebindingError as e:
    assert "ENDPOINT-IP-BLOCKED" in str(e)
    assert "link-local" in str(e)
EOF
}

@test "B2 cidr-warn: 0.0.0.0/0 in cdn_cidr_exemptions emits stderr WARN" {
    # Operator copy-pastes 0.0.0.0/0 thinking it means "match anything"; it
    # actually disables the rebinding defense entirely. Warn loudly at load.
    local bad_allowlist="$WORK_DIR/permissive.json"
    cat > "$bad_allowlist" <<'JSON'
{
  "providers": {
    "openai": [
      {"host": "api.openai.com", "ports": [443], "cdn_cidr_exemptions": ["0.0.0.0/0"]}
    ]
  }
}
JSON
    BAD_ALLOWLIST="$bad_allowlist" \
    PY_VALIDATOR="$PY_VALIDATOR" \
    "$PYTHON_BIN" - <<'EOF'
import importlib.util, io, os, sys
spec = importlib.util.spec_from_file_location("ev", os.environ["PY_VALIDATOR"])
m = importlib.util.module_from_spec(spec)
sys.modules["ev"] = m
spec.loader.exec_module(m)

# Capture stderr around load_allowlist.
buf = io.StringIO()
real_stderr = sys.stderr
sys.stderr = buf
try:
    m.load_allowlist(os.environ["BAD_ALLOWLIST"])
finally:
    sys.stderr = real_stderr
warn = buf.getvalue()
assert "ALLOWLIST-OVERLY-PERMISSIVE" in warn, f"expected warning; got {warn!r}"
assert "0.0.0.0/0" in warn, f"expected CIDR in warning; got {warn!r}"
EOF
}
