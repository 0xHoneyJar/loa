#!/usr/bin/env python3
"""endpoint-validator — canonical Python implementation per cycle-099 SDD §1.9.1.

The cycle-099 SDD §6.5 specifies an 8-step URL canonicalization pipeline that
ALL HTTP callers funneling through Loa MUST share. This module is the SOLE
implementation; bash callers wrap it via subprocess (`endpoint-validator.sh`),
and the Bridgebuilder TS port (Sprint 1E.c follow-up) will be Jinja2-codegen'd
from this canonical source so the validation logic lives in exactly one place.

Sprint 1E.b first PR scope: 8-step URL canonicalization (offline string logic,
no network). Deferred to 1E.c follow-up: TS port via Jinja2 codegen, DNS
re-resolution + IP-range allowlist (NFR-Sec-1 v1.2), HTTP redirect same-host
enforcement.

Pipeline (each step has a distinct rejection code per SDD §6.5):
  1. urlsplit()        → ENDPOINT-PARSE-FAILED
  2. scheme == https   → ENDPOINT-INSECURE-SCHEME
  3. netloc present    → ENDPOINT-RELATIVE
  4. IPv6 ranges       → ENDPOINT-IPV6-BLOCKED
  5. IDN allowlist     → ENDPOINT-IDN-NOT-ALLOWED
  6. port allowlist    → ENDPOINT-PORT-NOT-ALLOWED
  7. path normalization→ ENDPOINT-PATH-INVALID
  8. host allowlist    → ENDPOINT-NOT-ALLOWED

Stdlib + idna only. The bash twin invokes this module via subprocess; the
Bridgebuilder TS port is Jinja2-generated from this Python source so all three
runtimes share the same validation contract.

CLI:
    endpoint-validator.py --json --allowlist <path> <url>
    Exit 0 if valid; non-zero otherwise. JSON shape:
      {"valid": true, "url": "...", "scheme": "https", "host": "...", "port": 443}
      {"valid": false, "code": "ENDPOINT-...", "detail": "...", "url": "..."}

Library:
    from endpoint_validator import validate, ValidationResult, load_allowlist
    result = validate(url, allowlist)
"""

from __future__ import annotations

import argparse
import ipaddress
import json
import re
import socket
import sys
import urllib.parse
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import idna  # ≥ 3.6, RFC 5891

EXIT_VALID = 0
EXIT_REJECTED = 78  # EX_CONFIG (sysexits.h)
EXIT_USAGE = 64  # EX_USAGE

# Per SDD §6.5 step 4: IPv6 ranges that must be blocked. We use ipaddress
# module's network containment check rather than literal string match so all
# representations of these ranges (compressed, expanded) are caught uniformly.
# Sprint-1E.c.1 review additions: ::/96 (IPv4-compatible deprecated per RFC
# 4291) so `::1.2.3.4`-style addresses fall under IPV6-BLOCKED.
_BLOCKED_IPV6_NETWORKS: tuple[ipaddress.IPv6Network, ...] = (
    ipaddress.IPv6Network("::1/128"),       # loopback
    ipaddress.IPv6Network("fe80::/10"),     # link-local
    ipaddress.IPv6Network("fc00::/7"),      # unique-local (RFC 4193)
    ipaddress.IPv6Network("ff00::/8"),      # multicast
    ipaddress.IPv6Network("::/128"),        # unspecified
    ipaddress.IPv6Network("::/96"),         # IPv4-compatible (deprecated, RFC 4291)
    ipaddress.IPv6Network("::ffff:0:0/96"), # IPv4-mapped (might decode to private v4)
    ipaddress.IPv6Network("64:ff9b::/96"),  # NAT64 well-known
)

# Sprint-1E.c.1 review remediation: pre-parse authority gate. The TS port
# (URL constructor) silently percent-decodes/normalizes the hostname before
# my validator sees it; Python's urlsplit preserves the raw form. To keep
# both runtimes byte-equal we reject ANY authority segment (between `://`
# and first `/`/`?`/`#`) that contains parser-confusion vectors. The list:
#
#   - `%`     : percent-encoded chars in hostname (decode in TS, raw in Py)
#   - `\`     : WHATWG-vs-RFC3986 ambiguity (TS treats as `/`, Py as part of host)
#   - U+FF0E  : FULLWIDTH FULL STOP — IDN-normalized to `.` in TS only
#   - U+3002  : IDEOGRAPHIC FULL STOP — same
#   - U+FF61  : HALFWIDTH IDEOGRAPHIC FULL STOP — same
#   - U+00AD  : SOFT HYPHEN — stripped in TS only
#   - U+200B-U+200F, U+202A-U+202E, U+2066-U+2069 : zero-width / bidi controls
#
# Plus: octets with a leading zero or `0x` prefix in dotted-quad form
# (e.g., `010.0.0.1`, `0x7f.0.0.1`) — these are obfuscated IPv4 forms that
# urlsplit preserves but URL constructor partially normalizes.
_AUTHORITY_FORBIDDEN_CHARS: frozenset[str] = frozenset(
    [
        "%",
        "\\",
        "．",
        "。",
        "｡",
        "­",
    ]
    + [chr(cp) for cp in range(0x200B, 0x2010)]   # ZWSP through RLM
    + [chr(cp) for cp in range(0x202A, 0x202F)]   # LRE/RLE/PDF/LRO/RLO
    + [chr(cp) for cp in range(0x2066, 0x206A)]   # LRI/RLI/FSI/PDI
)

# Defense-in-depth beyond SDD §6.5 step 4 (which is IPv6-only). The general-
# purpose review (Sprint 1E.b correctness pass) flagged that an IPv4 literal
# like https://127.0.0.1/v1, https://169.254.169.254/ (AWS IMDS), or
# https://10.0.0.1/v1 falls through step 4 and is rejected only as
# ENDPOINT-NOT-ALLOWED at step 8. The risk: a future allowlist that mixes
# hostnames + IP literals (e.g., an internal Bedrock VPC endpoint) could
# accidentally allowlist an IP literal that happens to match a private range.
# We add an explicit `[ENDPOINT-IP-BLOCKED]` rejection that fires regardless
# of allowlist contents — the cycle-099 SDD §1.9.1 mitigation rationale ("any
# caller bypassing canonicalization/rebinding/redirect checks lets attacker-
# controlled endpoints reach the wire despite policy intent") applies equally
# to v4 and v6.
def _is_ip_literal_blocked(host: str) -> tuple[bool, str | None]:
    """If `host` is an IP literal (v4 or v6 unbracketed), return (blocked, reason).

    `host` is the IPv4-form string OR the IPv6-form WITHOUT brackets.
    Bracketed-form IPv6 must be unwrapped by the caller before invoking.
    Returns (False, None) when host is not an IP literal at all.
    """
    try:
        addr = ipaddress.ip_address(host)
    except (ValueError, ipaddress.AddressValueError):
        return False, None
    # AWS IMDS — surface its identity ahead of the generic is_link_local match
    # so operator diagnostics name the threat (BB iter-1 F3 surfaced this dead
    # code path; the more-specific message must run first).
    if isinstance(addr, ipaddress.IPv4Address) and str(addr) == "169.254.169.254":
        return True, "IP 169.254.169.254 is the AWS IMDS metadata endpoint"
    if addr.is_loopback:
        return True, f"IP {host} is loopback"
    if addr.is_private:
        return True, f"IP {host} is in a private range"
    if addr.is_link_local:
        return True, f"IP {host} is link-local"
    if addr.is_multicast:
        return True, f"IP {host} is multicast"
    if addr.is_unspecified:
        return True, f"IP {host} is unspecified (0.0.0.0 / ::)"
    if addr.is_reserved:
        return True, f"IP {host} is reserved"
    return False, None


def _extract_authority(url: str) -> str | None:
    """Extract the authority segment of a URL: everything between `://` and
    the first `/`, `?`, or `#`. Returns None if no `://` is present."""
    schemeEnd = url.find("://")
    if schemeEnd < 0:
        return None
    pos = schemeEnd + 3
    end = len(url)
    for ch in ("/", "?", "#"):
        idx = url.find(ch, pos)
        if 0 <= idx < end:
            end = idx
    return url[pos:end]


def _has_obfuscated_ipv4_octet(authority: str) -> bool:
    """Detect dotted-quad IPv4 with at least one octet that has a leading
    zero (e.g., `010.0.0.1`) or a `0x` prefix (e.g., `0x7f.0.0.1`). These
    forms are decoded inconsistently by getaddrinfo on different OSes and
    by URL constructor in browsers; we reject them all to keep the TS port
    parity-equal with Python's behavior on raw octets."""
    # Strip optional userinfo + port for analysis.
    host = authority.rsplit("@", 1)[-1]
    if host.startswith("["):
        return False  # Bracketed IPv6, not IPv4.
    host = host.rsplit(":", 1)[0]
    parts = host.split(".")
    if len(parts) != 4:
        return False
    obfuscated = False
    for p in parts:
        if not p:
            return False  # Empty octet — let parser reject.
        # Leading zero on a multi-digit octet (e.g., 010, 007) → octal flavor.
        if len(p) > 1 and p.startswith("0") and not p.lower().startswith("0x"):
            obfuscated = True
        # `0x` prefix → hex flavor.
        elif p.lower().startswith("0x"):
            obfuscated = True
        elif not p.isdigit():
            return False  # Non-IPv4 string like `api.openai.com` — fall through.
    return obfuscated


def _validate_authority(url: str) -> tuple[bool, str, str]:
    """Pre-parse defense (sprint-1E.c.1 review remediation).

    Returns (ok, code, detail). The two CRITICAL TS-vs-Python parity bypasses
    plus the HIGH backslash + obfuscated-IPv4 vectors all get rejected at the
    same gate.

    `%` handling carve-out: RFC 6874 IPv6 zone-id URLs encode the zone
    separator as `%25` inside the brackets (e.g., `[fe80::1%25eth0]`).
    We allow `%` inside brackets and reject elsewhere in the authority.
    """
    authority = _extract_authority(url)
    if authority is None:
        return True, "", ""  # Step-3 RELATIVE will catch this.
    # Carve out the bracketed IPv6 segment (if any); `%` inside the brackets
    # is the RFC 6874 zone-id marker and must be allowed through.
    outside_brackets = authority
    if authority.startswith("["):
        close = authority.find("]")
        if close >= 0:
            outside_brackets = authority[:1] + authority[close:]
    for ch in _AUTHORITY_FORBIDDEN_CHARS:
        if ch in outside_brackets:
            cp = ord(ch)
            return (
                False,
                "ENDPOINT-PARSE-FAILED",
                f"authority contains forbidden character (U+{cp:04X}); "
                "percent-encoding, backslashes, Unicode dot equivalents, "
                "and zero-width / bidi controls are all rejected",
            )
    if _has_obfuscated_ipv4_octet(authority):
        return (
            False,
            "ENDPOINT-IP-BLOCKED",
            f"obfuscated IPv4 octet in authority {authority!r}; use plain dotted-quad",
        )
    return True, "", ""


def _coerce_ipv4_obfuscation(host: str) -> str | None:
    """Convert obfuscated IPv4 forms (decimal / octal / hex int) to dotted-quad
    string, if possible. Returns None if `host` doesn't look like a coerced
    integer form. Examples:
        '2130706433'   → '127.0.0.1'   (decimal)
        '0x7f000001'   → '127.0.0.1'   (hex)
        '017700000001' → '127.0.0.1'   (legacy-octal, leading 0)

    cypherpunk MEDIUM 1 vector — getaddrinfo on most HTTP clients accepts
    these forms but urllib.parse keeps them as opaque strings, so the
    blocked-IP check needs explicit coercion to fire.
    """
    if not host or "." in host or ":" in host:
        # Dotted-quad already, IPv6, or not an integer form.
        return None
    s = host.lower()
    try:
        if s.startswith("0x"):
            n = int(s, 16)
        elif s.startswith("0") and len(s) > 1 and s[1].isdigit():
            n = int(s, 8)
        elif s.isdigit():
            n = int(s, 10)
        else:
            return None
    except ValueError:
        return None
    if n < 0 or n > 0xFFFFFFFF:
        return None
    try:
        return str(ipaddress.IPv4Address(n))
    except (ValueError, ipaddress.AddressValueError):
        return None


# Per SDD §6.5 step 7: path-traversal + RTL-override rejection. We reject
# raw `..`, leading `./`, repeated `//`, fully or partially percent-encoded
# `%2e` (one or both dots encoded; case-insensitive), encoded forward slash
# `%2[fF]` (legitimate paths shouldn't carry encoded `/`), and bidi-control
# characters (U+202E RTL OVERRIDE etc.). Reviews — general-purpose H3 +
# cypherpunk HIGH 1 — noted that the original regex missed `.%2e` and `%2e.`
# and the cypherpunk pass added `%00`/`%2f`/CRLF/TAB defense.
_PATH_TRAVERSAL_RE = re.compile(
    r"(?:\.\.)"                      # raw ..
    r"|(?:^|/)\.(?:/|$)"             # ./ at any path boundary
    r"|(?://)"                       # repeated slash
    r"|(?:%2[eE]%2[eE])"             # both dots encoded
    r"|(?:\.%2[eE])"                 # one literal + one encoded
    r"|(?:%2[eE]\.)"                 # one encoded + one literal
    r"|(?:%2[fF])"                   # encoded forward slash
    r"|(?:%00)"                      # encoded NUL
)

# Raw control bytes that must never appear in a URL path. CR/LF would split
# HTTP requests in some clients; NUL truncates strings on the C side; TAB is
# used in some smuggling vectors. (cypherpunk HIGH 2)
_PATH_FORBIDDEN_BYTES = ("\x00", "\r", "\n", "\t")

# Visible/invisible Unicode controls in the path that we treat as injection.
_PATH_CONTROL_CHARS = (
    "‪",  # LRE
    "‫",  # RLE
    "‬",  # PDF
    "‭",  # LRO
    "‮",  # RLO
    "‎",  # LRM
    "‏",  # RLM
    "⁦",  # LRI
    "⁧",  # RLI
    "⁨",  # FSI
    "⁩",  # PDI
)


@dataclass
class ValidationResult:
    """Outcome of validating one URL.

    `valid` True → all 8 steps passed; the canonicalized fields are populated.
    `valid` False → `code` carries the SDD §6.5 rejection code; `detail` has
    a single-line operator-readable description.
    """

    valid: bool
    url: str
    code: str | None = None
    detail: str | None = None
    scheme: str | None = None
    host: str | None = None
    port: int | None = None
    path: str | None = None
    matched_provider: str | None = None
    extra: dict[str, Any] = field(default_factory=dict)

    def as_dict(self) -> dict[str, Any]:
        d: dict[str, Any] = {"valid": self.valid, "url": self.url}
        for key in ("code", "detail", "scheme", "host", "port", "path", "matched_provider"):
            value = getattr(self, key)
            if value is not None:
                d[key] = value
        if self.extra:
            d["extra"] = self.extra
        return d


def _reject(url: str, code: str, detail: str) -> ValidationResult:
    return ValidationResult(valid=False, url=url, code=code, detail=detail)


# =============================================================================
# DNS rebinding + redirect enforcement (cycle-099 SDD §1.9.1 NFR-Sec-1 v1.2,
# Sprint 1E.c.2). The validator's offline string-validation (steps 1-8) catches
# attacker-supplied URL forms; the runtime DNS rebinding check catches the
# OPERATOR-supplied URL whose hostname resolves to an attacker IP at a later
# point. The pattern:
#
#   1. Operator config-load time: validate(url) → resolve host once (lock_ip).
#   2. Each subsequent request: verify_locked_ip(locked) → re-resolve, refuse
#      if a different IP is returned (DNS rebinding).
#   3. HTTP redirect: validate_redirect(orig_locked, new_url, allowlist) →
#      re-runs the 8-step pipeline AND requires the redirect-target to
#      resolve to the ORIGINAL locked IP (same-host + same-IP).
# =============================================================================


@dataclass(frozen=True)
class LockedIP:
    """Immutable record of a host-IP binding established at validate-time.

    Subsequent requests against the same host are required to resolve to the
    SAME IP (or any IP in the same multi-record set captured at lock time);
    a different IP triggers DNS-rebinding rejection.

    Hardening (sprint-1E.c.2 cypherpunk LOW): __post_init__ normalizes the
    host (lowercase + strip trailing FQDN dot) so deserialized LockedIPs
    don't drift from the form the validator emits. Also validates that
    `ip` and every entry in `initial_ips` parse cleanly — a forged LockedIP
    constructed with garbage fields fails fast at construction time.

    KNOWN LIMITATION (TOCTOU): the lock-then-verify pattern has an inherent
    race window between `verify_locked_ip()` returning OK and the actual
    `socket.connect()`. The validator cannot close this; callers needing
    transport-level pinning should use `LockedIP.ip` for direct connect
    with `Host:` header set to `LockedIP.host`. This is per NFR-Sec-1 v1.2
    contract — DNS rebinding defense is best-effort, not transport-level.
    """

    host: str
    ip: str
    family: int  # socket.AF_INET / AF_INET6
    port: int
    # All IPs returned by the initial getaddrinfo. We accept any of them on
    # re-resolve so legitimate CDN round-robin doesn't trip the gate.
    initial_ips: tuple[str, ...] = field(default_factory=tuple)

    def __post_init__(self) -> None:
        # Normalize host: lowercase + strip trailing FQDN dot. Mirrors the
        # canonical-form treatment in `_idna_normalize`.
        normalized = self.host.lower().rstrip(".")
        if normalized != self.host:
            object.__setattr__(self, "host", normalized)
        # Validate ip + initial_ips parse cleanly so a forged LockedIP from
        # JSON deserialization can't carry "169.254.169.254" past type-check.
        try:
            ipaddress.ip_address(self.ip)
        except (ValueError, ipaddress.AddressValueError) as exc:
            raise ValueError(f"LockedIP.ip {self.ip!r} is not a valid IP: {exc}") from exc
        # Guard against accidental empty initial_ips after deserialization.
        if not self.initial_ips:
            object.__setattr__(self, "initial_ips", (self.ip,))
        for entry in self.initial_ips:
            try:
                ipaddress.ip_address(entry)
            except (ValueError, ipaddress.AddressValueError) as exc:
                raise ValueError(
                    f"LockedIP.initial_ips contains invalid {entry!r}: {exc}"
                ) from exc


class EndpointDnsError(Exception):
    """Common base for DNS-related validator failures (gp MEDIUM remediation).

    A loader catching ``except EndpointDnsError`` will catch resolution
    failures AND rebinding rejections without enumerating every subclass.
    """


class DnsResolutionError(EndpointDnsError):
    """Raised when getaddrinfo fails for a host the validator was asked to lock."""

    def __init__(self, host: str, detail: str):
        super().__init__(
            f"[ENDPOINT-DNS-RESOLUTION-FAILED] host={host!r} detail={detail}"
        )
        self.host = host
        self.detail = detail


class DnsRebindingError(EndpointDnsError):
    """Raised when DNS resolution returns a different IP than initially locked,
    OR when the resolved IP falls in a blocked range AND no
    `cdn_cidr_exemptions` covers it (per SDD §1.9)."""

    def __init__(self, code: str, detail: str):
        super().__init__(f"[{code}] {detail}")
        self.code = code
        self.detail = detail


def _resolve_addrinfo(host: str, port: int = 443) -> list[tuple[int, str]]:
    """Wrap socket.getaddrinfo, returning a list of (family, ip-string) pairs.

    Raises DnsResolutionError on failure. Filters out non-INET/INET6 entries
    (no Bluetooth, no Unix sockets reaching this code path).
    """
    try:
        records = socket.getaddrinfo(
            host, port, type=socket.SOCK_STREAM, proto=socket.IPPROTO_TCP
        )
    except (socket.gaierror, OSError) as exc:
        raise DnsResolutionError(host, str(exc)) from exc
    out: list[tuple[int, str]] = []
    for family, _socktype, _proto, _canon, sockaddr in records:
        if family not in (socket.AF_INET, socket.AF_INET6):
            continue
        ip = sockaddr[0]
        # Strip IPv6 zone-id from the resolved form (RFC 6874).
        if family == socket.AF_INET6 and "%" in ip:
            ip = ip.split("%", 1)[0]
        out.append((family, ip))
    if not out:
        raise DnsResolutionError(host, "no usable INET/INET6 records returned")
    return out


def _is_resolved_ip_blocked(ip: str) -> tuple[bool, str]:
    """Defense-in-depth at resolve time. The 8-step canonicalization pipeline
    already rejects IP-literal hostnames, but a HOSTNAME that resolves to a
    blocked range is the DNS rebinding scenario this function exists to
    catch. Returns (blocked, reason).

    Diagnostic readability (gp HIGH 2): the IPv6 IMDS / link-local /
    NAT64 /  ULA ranges all fall in `fc00::/7` or `fe80::/10`; the bare
    "falls in blocked range" message obscures the threat identity. We
    add a more specific reason for well-known operational endpoints.
    """
    try:
        addr = ipaddress.ip_address(ip)
    except (ValueError, ipaddress.AddressValueError):
        return False, ""
    if isinstance(addr, ipaddress.IPv6Address):
        # Well-known IPv6 endpoints — surface their identity in diagnostics.
        if str(addr) == "fd00:ec2::254":
            return True, f"resolved IPv6 {ip} is the AWS IPv6 IMDS metadata endpoint"
        for net in _BLOCKED_IPV6_NETWORKS:
            if addr in net:
                # Attach a more specific reason when the range is well-known.
                if net == ipaddress.IPv6Network("fe80::/10"):
                    return True, f"resolved IPv6 {ip} is link-local (fe80::/10)"
                if net == ipaddress.IPv6Network("64:ff9b::/96"):
                    return True, f"resolved IPv6 {ip} is NAT64 well-known (64:ff9b::/96)"
                if net == ipaddress.IPv6Network("::1/128"):
                    return True, f"resolved IPv6 {ip} is loopback (::1/128)"
                return True, f"resolved IPv6 {ip} falls in blocked range {net}"
    if isinstance(addr, ipaddress.IPv4Address):
        # Reuse the literal-IPv4 blocked-set logic via _is_ip_literal_blocked.
        blocked, reason = _is_ip_literal_blocked(ip)
        if blocked:
            return True, reason or f"resolved IPv4 {ip} falls in blocked range"
    return False, ""


def _ip_in_cidrs(ip: str, cidrs: list[str]) -> bool:
    """True iff `ip` falls in any of the configured CIDR ranges."""
    try:
        addr = ipaddress.ip_address(ip)
    except (ValueError, ipaddress.AddressValueError):
        return False
    for cidr in cidrs:
        try:
            net = ipaddress.ip_network(cidr, strict=False)
        except (ValueError, ipaddress.AddressValueError):
            continue
        if addr.version != net.version:
            continue
        if addr in net:
            return True
    return False


def lock_resolved_ip(
    host: str,
    *,
    port: int = 443,
    allowlist: dict[str, list[dict[str, Any]]] | None = None,
    provider_id: str | None = None,
) -> LockedIP:
    """Resolve `host` once via getaddrinfo and lock the (host, IP) pair.

    Per SDD §1.9 (cycle-099 SKP-005 reconciliation): if `allowlist` and
    `provider_id` are supplied AND the matching provider entry has a
    `cdn_cidr_exemptions` list, a resolved IP that falls in one of those
    CIDRs SKIPS the RFC-1918/loopback/IMDS rebinding check — accepting the
    legitimate CDN-fronted provider behavior (e.g., anthropic.com via
    Cloudflare resolving to a CF range that's "public" but the CF range
    has been vetted at cycle-level System Zone review).

    Without the exemption, any resolution to a blocked range raises
    DnsRebindingError. The exemption ONLY relaxes the blocked-range trip;
    the per-request rebinding check (verify_locked_ip) still applies on
    subsequent calls.

    Raises:
        DnsResolutionError: if getaddrinfo fails.
        DnsRebindingError:  if the resolved IP is in a blocked range
                            AND no cdn_cidr_exemption applies.
    """
    records = _resolve_addrinfo(host, port=port)
    family, ip = records[0]
    # Determine the CDN-CIDR exemption set (if any) for this provider+host.
    exemption_cidrs: list[str] = []
    if allowlist is not None and provider_id is not None:
        for entry in allowlist.get(provider_id, []):
            if not isinstance(entry, dict):
                continue
            if entry.get("host", "").lower() != host.lower():
                continue
            cidrs = entry.get("cdn_cidr_exemptions") or []
            extras = entry.get("cdn_cidr_exemptions_extra") or []
            if isinstance(cidrs, list):
                exemption_cidrs.extend(str(c) for c in cidrs)
            if isinstance(extras, list):
                exemption_cidrs.extend(str(c) for c in extras)
            break
    # Apply the relaxing-semantics check to EVERY record (cypherpunk MEDIUM —
    # Happy Eyeballs defense). If TCP connect picks records[1] over
    # records[0], the validator must have already rejected blocked IPs
    # anywhere in the dual-stack record set.
    for _fam, candidate_ip in records:
        if exemption_cidrs and _ip_in_cidrs(candidate_ip, exemption_cidrs):
            continue  # explicitly exempted; do not run blocked-range check
        blocked, reason = _is_resolved_ip_blocked(candidate_ip)
        if blocked:
            raise DnsRebindingError(
                "ENDPOINT-IP-BLOCKED",
                f"host {host!r} resolved to a blocked IP: {reason}",
            )
    return LockedIP(
        host=host,
        ip=ip,
        family=family,
        port=port,
        initial_ips=tuple(r[1] for r in records),
    )


def verify_locked_ip(locked: LockedIP) -> bool:
    """Re-resolve the locked host and verify the IP set still includes the
    locked IP. Returns True on match. Raises DnsRebindingError on mismatch
    (the actual rebinding scenario) or DnsResolutionError if re-resolution
    fails entirely.

    Acceptance rule: any IP in the FRESH record set may match the LOCKED IP
    OR be in the locked initial_ips set. This tolerates legitimate CDN
    round-robin while still catching the case where ALL fresh records
    differ from the locked set.
    """
    fresh = _resolve_addrinfo(locked.host, port=locked.port)
    fresh_ips = {r[1] for r in fresh}
    if locked.ip in fresh_ips:
        return True
    # Tolerate CDN/round-robin: if any of our INITIAL_IPS appears in fresh, OK.
    if any(ip in fresh_ips for ip in locked.initial_ips):
        return True
    # Re-check blocked ranges in the fresh set — even if this isn't the
    # locked IP, an attacker-rebound resolution could now land on a private
    # range, which we want to surface clearly.
    for ip in fresh_ips:
        blocked, reason = _is_resolved_ip_blocked(ip)
        if blocked:
            raise DnsRebindingError(
                "ENDPOINT-DNS-REBOUND",
                f"host {locked.host!r} re-resolved to blocked IP: {reason}",
            )
    raise DnsRebindingError(
        "ENDPOINT-DNS-REBOUND",
        f"host {locked.host!r} re-resolved to {sorted(fresh_ips)!r}; "
        f"none match locked initial_ips {sorted(locked.initial_ips)!r}",
    )


def validate_redirect(
    original_locked: LockedIP,
    new_url: str,
    allowlist: dict[str, list[dict[str, Any]]],
) -> ValidationResult:
    """Validate an HTTP 3xx redirect target.

    Steps:
      1. Run the full 8-step `validate()` pipeline on `new_url`.
      2. Same-host check: redirect target must resolve to the SAME host as
         the locked endpoint (exact lowercased hostname match).
      3. Same-IP check: re-resolve the host and confirm the locked IP is
         still in the resulting record set (verify_locked_ip).

    Returns a ValidationResult; never raises (callers can route on the
    structured rejection code).
    """
    new_result = validate(new_url, allowlist)
    if not new_result.valid:
        return new_result
    # LockedIP.__post_init__ already normalized; new_result.host is also
    # IDNA-normalized + lowercased per step 5.
    if new_result.host != original_locked.host:
        return _reject(
            new_url,
            "ENDPOINT-REDIRECT-DENIED",
            f"redirect target host {new_result.host!r} differs from locked host "
            f"{original_locked.host!r}; same-host policy refuses cross-host redirects",
        )
    # gp MEDIUM remediation: same-port enforcement. A redirect from :443 to
    # an alternate port (even if allowlisted at the provider) lets attacker
    # pivot to a different service if the operator allowlists multiple ports
    # per host. The lock contract was made at a specific port; honor it.
    if new_result.port != original_locked.port:
        return _reject(
            new_url,
            "ENDPOINT-REDIRECT-DENIED",
            f"redirect port {new_result.port} differs from locked port "
            f"{original_locked.port}; same-port policy refuses port pivots",
        )
    try:
        verify_locked_ip(original_locked)
    except DnsRebindingError as exc:
        return _reject(new_url, exc.code, exc.detail)
    except DnsResolutionError as exc:
        return _reject(
            new_url,
            "ENDPOINT-DNS-RESOLUTION-FAILED",
            f"redirect target re-resolution failed: {exc.detail}",
        )
    return new_result


DEFAULT_MAX_REDIRECT_HOPS = 10


def validate_redirect_chain(
    original_locked: LockedIP,
    redirect_urls: list[str],
    allowlist: dict[str, list[dict[str, Any]]],
    *,
    max_hops: int = DEFAULT_MAX_REDIRECT_HOPS,
) -> ValidationResult:
    """Validate a multi-hop HTTP redirect chain.

    Cypherpunk MEDIUM remediation: `validate_redirect` is single-hop. An
    attacker controlling a redirect chain (URL_a → URL_b → evil.com) could
    pass URL_a (same-host as original) and slip URL_b past validation if the
    caller doesn't re-invoke validate_redirect. This helper enforces per-hop
    validation against the SAME `original_locked` — every hop must remain
    same-host AND same-IP. Returns the final ValidationResult; rejects on
    the first hop that fails.

    BB iter-2 F8: enforce a `max_hops` ceiling (default 10, mirroring the
    HTTP RFC 7231 §6.4 recommendation for client-side limits). Chains
    longer than the cap are rejected with ENDPOINT-REDIRECT-DENIED rather
    than allowed to consume unbounded resources.
    """
    if not redirect_urls:
        return ValidationResult(valid=True, url="", scheme="", host="", port=0)
    if len(redirect_urls) > max_hops:
        return _reject(
            redirect_urls[0],
            "ENDPOINT-REDIRECT-DENIED",
            f"redirect chain length {len(redirect_urls)} exceeds max_hops={max_hops}; "
            "refuse to follow potentially unbounded redirect chains",
        )
    result = ValidationResult(valid=False, url="", code="ENDPOINT-RELATIVE", detail="empty chain")
    for url in redirect_urls:
        result = validate_redirect(original_locked, url, allowlist)
        if not result.valid:
            return result
    return result


_ALLOWLIST_MAX_BYTES = 65536  # 64 KiB — see cypherpunk LOW 1


# Cypherpunk MEDIUM M1 + HIGH H1 remediation — control bytes (NUL/CR/LF/TAB)
# and glob characters that DNS-spec hostnames cannot legitimately contain.
# Embedded NUL would terminate a C-string passed to libcurl; embedded CR/LF
# could smuggle HTTP headers downstream. None of these can match a real URL
# host via verbatim-equality, so failing closed at load surfaces the misconfig.
_HOST_FORBIDDEN_CONTROL_BYTES: frozenset[str] = frozenset(
    "\x00\r\n\t\v\f"
)

# Glob look-alikes — both ASCII and Unicode forms. Operators copy-pasting
# wildcard entries from other tooling may use any of these expecting
# glob semantics; verbatim equality has no glob support so we reject all.
_HOST_GLOB_CHARS: frozenset[str] = frozenset(
    [
        "*",            # U+002A ASTERISK
        "?",            # U+003F QUESTION MARK
        "＊",           # U+FF0A FULLWIDTH ASTERISK
        "∗",            # U+2217 ASTERISK OPERATOR
        "﹡",           # U+FE61 SMALL ASTERISK
        "✱",            # U+2731 HEAVY ASTERISK
        "？",           # U+FF1F FULLWIDTH QUESTION MARK
    ]
)


def _validate_allowlist_entries(
    allowlist: dict[str, list[dict[str, Any]]],
) -> None:
    """Sprint-1E.c.3.c HIGH-2 (deferred from 1E.c.3.a) + cypherpunk H1/M1
    remediation: fail-closed at load time on sentinel-shaped, control-byte,
    or glob-shaped hosts that silently no-op the host gate.

    The host predicate in `_provider_for_host` is verbatim equality
    (lowercased str(entry["host"]) == lowercased URL host). Operators
    sometimes copy wildcard-style entries from other allowlist tooling
    expecting glob semantics; with verbatim equality the wildcard never
    matches a real URL and the allowlist silently denies all traffic.
    Surface the misconfig at LOAD time instead of at first runtime denial.

    Tree-restriction (1E.c.3.a) closed the realistic substitution vector
    where an attacker pointed the allowlist path at an attacker-controlled
    file outside the canonical tree. HIGH-2 + cypherpunk is the
    inside-the-tree defense-in-depth: an allowlist living in
    `.claude/scripts/lib/allowlists/` but containing `host: "*"` (or
    `host: "＊"` U+FF0A FULLWIDTH ASTERISK) would still be loadable.
    Reject all variants explicitly.

    Defenses:
      - Non-string host → reject (type-confusion at load)
      - Empty/whitespace-only host → reject (no-op match)
      - Glob character (ASCII `*`/`?` OR Unicode look-alikes
        U+FF0A/U+2217/U+FE61/U+2731/U+FF1F) → reject
      - Control byte (NUL/CR/LF/TAB) → reject (HTTP smuggling +
        C-string-truncation defense)

    Validation is "all-or-nothing" — one bad entry rejects the whole file.
    Silent partial-load would hide the misconfig from operator review.

    Raises:
        ValueError: with provider_id + entry index in the message so
                    operators can pinpoint the bad entry without grepping.
    """
    import unicodedata
    for provider_id, entries in allowlist.items():
        if not isinstance(entries, list):
            continue
        for idx, entry in enumerate(entries):
            if not isinstance(entry, dict):
                continue
            if "host" not in entry:
                # Missing-host is a separate config bug surface; defer to
                # _provider_for_host (which str()-coerces missing keys to "")
                # for the runtime-side fallthrough. We only fail-close at load
                # when host IS present and shaped wrong.
                continue
            host_raw = entry["host"]
            if not isinstance(host_raw, str):
                raise ValueError(
                    f"allowlist provider {provider_id!r} entry #{idx}: "
                    f"`host` must be a string, got {type(host_raw).__name__} "
                    f"(value={host_raw!r})"
                )
            if not host_raw.strip():
                raise ValueError(
                    f"allowlist provider {provider_id!r} entry #{idx}: "
                    f"`host` is empty or whitespace-only ({host_raw!r}); "
                    "the host predicate is verbatim equality, an empty host "
                    "matches no real URL — silently broken allowlist"
                )
            # Reject embedded control bytes (cypherpunk M1). DNS hostnames
            # cannot legitimately contain NUL/CR/LF/TAB; their presence
            # signals injection or a copy-paste artifact.
            for ctrl in _HOST_FORBIDDEN_CONTROL_BYTES:
                if ctrl in host_raw:
                    raise ValueError(
                        f"allowlist provider {provider_id!r} entry #{idx}: "
                        f"`host` {host_raw!r} contains control byte "
                        f"(0x{ord(ctrl):02X}); DNS hostnames cannot contain "
                        "control characters and their presence may smuggle "
                        "HTTP headers or truncate C-strings downstream"
                    )
            # NFKC-normalize then check for glob characters (ASCII + Unicode
            # look-alikes; cypherpunk H1). The NFKC pass folds compatibility-
            # equivalent forms (U+FF0A FULLWIDTH ASTERISK → U+002A) so
            # operator-pasted glob alternatives are caught uniformly.
            normalized = unicodedata.normalize("NFKC", host_raw)
            for glob in _HOST_GLOB_CHARS:
                if glob in host_raw or glob in normalized:
                    raise ValueError(
                        f"allowlist provider {provider_id!r} entry #{idx}: "
                        f"`host` {host_raw!r} contains glob/wildcard character "
                        f"({glob!r}); the host predicate is verbatim equality "
                        "(no glob support). Configure each FQDN explicitly "
                        "(e.g., 'api.openai.com', 'api.anthropic.com')"
                    )


def _warn_overly_permissive_cidr(allowlist: dict[str, list[dict[str, Any]]]) -> None:
    """Cypherpunk MEDIUM remediation: scan cdn_cidr_exemptions for /0 (or
    suspiciously-wide /1../4) entries and emit a stderr WARN per occurrence.
    Operators copy-pasting `0.0.0.0/0` defeat the rebinding defense entirely
    without realizing it; the warning surfaces the misconfig at load time."""
    for provider_id, entries in allowlist.items():
        if not isinstance(entries, list):
            continue
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            for field_name in ("cdn_cidr_exemptions", "cdn_cidr_exemptions_extra"):
                cidrs = entry.get(field_name) or []
                if not isinstance(cidrs, list):
                    continue
                for c in cidrs:
                    try:
                        net = ipaddress.ip_network(str(c), strict=False)
                    except (ValueError, ipaddress.AddressValueError):
                        continue
                    if net.prefixlen <= 4:
                        sys.stderr.write(
                            f"[ALLOWLIST-OVERLY-PERMISSIVE] {field_name}={c!r} "
                            f"(prefix /{net.prefixlen}) for provider {provider_id!r} "
                            "disables the DNS-rebinding defense for matching IPs; "
                            "tighten the CIDR or remove the entry\n"
                        )


def load_allowlist(path: str | Path) -> dict[str, list[dict[str, Any]]]:
    """Read a JSON allowlist file. Top-level shape:

        {"providers": {"<id>": [{"host": "<lowercased>", "ports": [<int>...]}, ...]}}

    Hardening (cypherpunk LOW 1 + LOW 2):
      - Reject non-regular files (FIFO, /dev/stdin, /dev/zero) — those can hang.
      - Reject files > 64 KiB — defends against deep-nest JSON DoS.
    """
    p = Path(path)
    if not p.is_file():
        raise ValueError(f"allowlist {p}: not a regular file")
    size = p.stat().st_size
    if size > _ALLOWLIST_MAX_BYTES:
        raise ValueError(
            f"allowlist {p}: {size} bytes exceeds {_ALLOWLIST_MAX_BYTES} byte cap"
        )
    with p.open("r", encoding="utf-8") as f:
        data = json.load(f)
    providers = data.get("providers", {})
    if not isinstance(providers, dict):
        raise ValueError(
            f"allowlist {p}: top-level `providers` must be a mapping, got {type(providers).__name__}"
        )
    _validate_allowlist_entries(providers)
    _warn_overly_permissive_cidr(providers)
    return providers


def _is_ipv6_blocked(host: str) -> bool:
    """Strip the brackets from an RFC-3986 IPv6 literal, parse it, return True
    if the address falls in any blocked range. False if the host is not an
    IPv6 literal (caller falls through to other checks)."""
    if not (host.startswith("[") and host.endswith("]")):
        return False
    try:
        addr = ipaddress.IPv6Address(host[1:-1])
    except (ValueError, ipaddress.AddressValueError):
        # Malformed IPv6 inside brackets — treat as blocked since we can't
        # safely match against allowlist (the allowlist holds hostnames).
        return True
    return any(addr in net for net in _BLOCKED_IPV6_NETWORKS)


def _validate_path(path: str) -> tuple[bool, str]:
    """Return (ok, detail). False means path-injection vector detected."""
    if not path:
        return True, ""
    for ch in _PATH_FORBIDDEN_BYTES:
        if ch in path:
            return False, f"path contains forbidden control byte (0x{ord(ch):02X})"
    for ch in _PATH_CONTROL_CHARS:
        if ch in path:
            return False, f"path contains bidi/RTL control char (U+{ord(ch):04X})"
    if _PATH_TRAVERSAL_RE.search(path):
        return False, (
            "path contains traversal pattern "
            "(.., ./, //, %2e%2e, .%2e, %2e., %2f, or %00)"
        )
    return True, ""


def _idna_normalize(host: str) -> str:
    """Return the IDNA-normalized + lowercased host. Falls back to lowercase
    when the host is pure ASCII (no encoding needed). Strips a single trailing
    dot (FQDN form) so `api.openai.com.` and `api.openai.com` match the same
    allowlist entry (cypherpunk HIGH 3)."""
    if host.endswith("."):
        host = host[:-1]
    if all(ord(c) < 128 for c in host) and "xn--" not in host.lower():
        return host.lower()
    try:
        encoded = idna.encode(host, uts46=False, transitional=False).decode("ascii")
        return encoded.lower()
    except idna.core.IDNAError:
        # Caller treats failure as ENDPOINT-IDN-NOT-ALLOWED — the encoded form
        # is undefined, so it can't match any allowlist entry verbatim.
        return host.lower()


def _coerce_port(p: Any) -> int | None:
    """Strict port coercion. Reject booleans (which `isinstance(p, int)` would
    otherwise accept), reject out-of-range ints, reject string-form. Returns
    None for invalid inputs so the caller can drop them silently. Per gp M3."""
    if isinstance(p, bool):
        return None
    if not isinstance(p, int):
        return None
    if p < 1 or p > 65535:
        return None
    return p


def _provider_for_host(
    host: str, port: int, allowlist: dict[str, list[dict[str, Any]]]
) -> tuple[str | None, list[int] | None]:
    """Return (provider_id, allowed_ports) if the host is allowlisted under any
    provider; else (None, None). The host must match VERBATIM (lowercased)."""
    for provider_id, entries in allowlist.items():
        if not isinstance(entries, list):
            continue
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            entry_host = str(entry.get("host", "")).lower()
            if entry_host == host:
                raw_ports = entry.get("ports", [])
                if not isinstance(raw_ports, list):
                    return provider_id, []
                # Filter out booleans (which `isinstance(p, int)` would accept),
                # out-of-range ints, and non-int values; gp M3.
                valid_ports = [
                    coerced for p in raw_ports
                    if (coerced := _coerce_port(p)) is not None
                ]
                return provider_id, valid_ports
    return None, None


def validate(url: str, allowlist: dict[str, list[dict[str, Any]]]) -> ValidationResult:
    """Run the SDD §6.5 8-step canonicalization pipeline against `url`.

    Returns a ValidationResult; pure function, no I/O, no network.
    """
    if not isinstance(url, str):
        return _reject(str(url), "ENDPOINT-PARSE-FAILED", "url must be a string")

    # Step 0 (cypherpunk HIGH 2): Python 3.6+ urlsplit silently STRIPS ASCII
    # control bytes (\r, \n, \t) from the URL before parsing — meaning the
    # downstream path-validator never sees them. But the original URL string
    # is preserved in `result.url`, and a downstream caller that re-emits it
    # would pass the smuggling payload to a less-defensive HTTP client. Reject
    # these at entry so the validator and the original URL agree.
    for ch in _PATH_FORBIDDEN_BYTES:
        if ch in url:
            return _reject(
                url,
                "ENDPOINT-PATH-INVALID",
                f"URL contains forbidden control byte (0x{ord(ch):02X}); "
                "CR/LF/TAB/NUL trigger HTTP smuggling in some clients",
            )

    # Step 0.5 (sprint-1E.c.1 review remediation): pre-parse authority gate.
    # Catches percent-encoded hostnames, backslash-confusion, Unicode dot
    # equivalents (full-width, ideographic), zero-width / bidi controls, and
    # obfuscated IPv4 octet forms BEFORE either parser (urlsplit / URL ctor)
    # can normalize them differently. Closes the cross-runtime parity bypass.
    ok, code, detail = _validate_authority(url)
    if not ok:
        return _reject(url, code, detail)

    # Step 1: parse
    try:
        parts = urllib.parse.urlsplit(url)
    except (ValueError, UnicodeError) as exc:
        return _reject(url, "ENDPOINT-PARSE-FAILED", f"urlsplit raised: {exc}")
    # urlsplit doesn't raise on most malformed URLs — it returns an empty
    # netloc instead. We keep the explicit check; empty-netloc is a Step 3
    # concern but we surface the parse-failed flavor when scheme is unknown.
    if not parts.scheme and not parts.netloc:
        return _reject(url, "ENDPOINT-RELATIVE", "missing scheme + netloc")
    # An invalid bracketed IPv6 (e.g., 'http://[invalid-bracket') gives a
    # parse warning on stdlib that depends on Python version; check explicitly.
    if "[" in url and url.count("[") != url.count("]"):
        return _reject(url, "ENDPOINT-PARSE-FAILED", "unmatched IPv6 brackets")

    # Step 2: scheme
    if parts.scheme.lower() != "https":
        return _reject(
            url,
            "ENDPOINT-INSECURE-SCHEME",
            f"scheme {parts.scheme!r} not allowed; only https",
        )

    # Step 2.5 (general-purpose review HIGH 1): userinfo segments are not part
    # of the SDD §6.5 pipeline but allowing them silently has two failure
    # modes: (a) `https://user:pass@api.openai.com/` lets credentials reach
    # the wire if a downstream caller re-emits the original URL string, and
    # (b) phishing-style `https://api.openai.com@evil.com/` is rejected only
    # at step 8, with the misleading code ENDPOINT-NOT-ALLOWED. Reject both
    # forms with a dedicated code so operator diagnostics are unambiguous.
    if parts.username is not None or parts.password is not None:
        return _reject(
            url,
            "ENDPOINT-USERINFO-PRESENT",
            "URL contains userinfo segment; credentials must travel via env vars, not URLs",
        )

    # Step 3: netloc
    if not parts.netloc:
        return _reject(url, "ENDPOINT-RELATIVE", "URL has no netloc (host)")

    # Extract host + port. We have to handle bracketed IPv6 carefully because
    # urllib's `.hostname` strips brackets but `.netloc` retains them.
    raw_host = parts.hostname or ""
    if not raw_host:
        return _reject(url, "ENDPOINT-RELATIVE", "URL has no parseable hostname")

    # Step 4: IP-literal blocking (per SDD §6.5 step 4 for IPv6, plus general-
    # purpose CRIT defense-in-depth for IPv4 — incl. AWS IMDS 169.254.169.254
    # and RFC 1918 private ranges). The cypherpunk pass also flagged decimal/
    # octal/hex IPv4 literals (e.g., 2130706433 == 127.0.0.1) as a vector;
    # `ipaddress.ip_address` only parses dotted-quad form, so we additionally
    # try integer coercion before falling through.
    if "[" in parts.netloc:
        bracketed = "[" + raw_host + "]"
        if _is_ipv6_blocked(bracketed):
            return _reject(
                url,
                "ENDPOINT-IPV6-BLOCKED",
                f"IPv6 literal {raw_host} falls in a blocked range",
            )
        # Public IPv6 falls through here. We fail-closed at step 8 below
        # because Sprint 1E.b's allowlist is hostname-only; the dedicated
        # rejection happens at step 8 with ENDPOINT-IPV6-NOT-ALLOWED so
        # operators see a clear diagnostic.
    elif ":" in raw_host:
        # IPv6-shaped hostname without brackets — RFC 3986 forbids.
        try:
            addr6 = ipaddress.IPv6Address(raw_host)
            if any(addr6 in net for net in _BLOCKED_IPV6_NETWORKS):
                return _reject(
                    url, "ENDPOINT-IPV6-BLOCKED",
                    f"IPv6 literal {raw_host} falls in a blocked range",
                )
            return _reject(
                url, "ENDPOINT-PARSE-FAILED",
                "IPv6 literal must be RFC 3986 bracketed (e.g., https://[::1]/)",
            )
        except (ValueError, ipaddress.AddressValueError):
            pass  # not actually IPv6; fall through

    # IPv4 literal blocking — explicit. SDD §6.5 step 4 wording is IPv6-only,
    # so this is defense-in-depth named ENDPOINT-IP-BLOCKED.
    blocked, reason = _is_ip_literal_blocked(raw_host)
    if blocked:
        return _reject(url, "ENDPOINT-IP-BLOCKED", reason or f"IP {raw_host} is blocked")
    # Decimal / octal / hex coercion for "2130706433"-style obfuscated IPv4.
    # An attacker URL `https://2130706433/` resolves via getaddrinfo on most
    # HTTP clients but urllib.parse keeps the literal as a string. Try int
    # coercion (decimal + 0x hex + 0o octal) and re-check.
    coerced = _coerce_ipv4_obfuscation(raw_host)
    if coerced is not None:
        blocked, reason = _is_ip_literal_blocked(coerced)
        if blocked:
            return _reject(
                url,
                "ENDPOINT-IP-BLOCKED",
                f"obfuscated IPv4 literal {raw_host!r} resolves to {coerced} ({reason})",
            )
        # Even a public-IPv4-decimal-form is a misuse; per SDD §6.5 step 4
        # spirit, only standard dotted-quad host strings should be accepted.
        # Reject all obfuscated forms — no legitimate provider URL uses them.
        return _reject(
            url,
            "ENDPOINT-IP-BLOCKED",
            f"obfuscated IPv4 form {raw_host!r} not allowed; use dotted-quad",
        )

    # Step 5: IDN normalization + allowlist match (allowlist match happens at
    # step 8; here we just ensure the encoded form exists / fail closed).
    try:
        normalized_host = _idna_normalize(raw_host)
    except UnicodeError as exc:
        return _reject(url, "ENDPOINT-IDN-NOT-ALLOWED", f"IDN encode failed: {exc}")

    # Step 6: port — extract from URL, default to 443 if absent.
    try:
        port = parts.port if parts.port is not None else 443
    except ValueError:
        return _reject(url, "ENDPOINT-PARSE-FAILED", "port is not a valid integer")

    # Step 7: path normalization
    path_ok, path_detail = _validate_path(parts.path)
    if not path_ok:
        return _reject(url, "ENDPOINT-PATH-INVALID", path_detail)

    # Step 8: explicit host + port allowlist match.
    provider_id, allowed_ports = _provider_for_host(normalized_host, port, allowlist)
    if provider_id is None:
        # IPv6 literal that wasn't blocked at step 4 falls through here. Use
        # a dedicated code so operators see "the host is an IP, not a
        # hostname allowlist entry" rather than misleading them into thinking
        # the host string is just typo'd (general-purpose review HIGH 2).
        if "[" in parts.netloc:
            return _reject(
                url,
                "ENDPOINT-IPV6-NOT-ALLOWED",
                f"IPv6 literal {raw_host} not in any provider's allowlist; "
                "Sprint 1E.b allowlist is hostname-only",
            )
        if any(ord(c) >= 128 for c in raw_host) or raw_host.lower().startswith("xn--"):
            return _reject(
                url,
                "ENDPOINT-IDN-NOT-ALLOWED",
                f"IDN-encoded host {normalized_host!r} not in any provider's allowlist",
            )
        return _reject(
            url,
            "ENDPOINT-NOT-ALLOWED",
            f"host {normalized_host!r} not in any provider's allowlist",
        )
    # Port allowlist: fail-closed when the provider entry has no valid ports
    # (gp M3). An empty allowed_ports list is a CONFIG bug, not "any port OK".
    if not allowed_ports:
        return _reject(
            url,
            "ENDPOINT-PORT-NOT-ALLOWED",
            f"provider {provider_id!r} has no valid ports configured (allowlist bug?)",
        )
    if port not in allowed_ports:
        return _reject(
            url,
            "ENDPOINT-PORT-NOT-ALLOWED",
            f"port {port} not in allowlist {allowed_ports} for provider {provider_id!r}",
        )

    return ValidationResult(
        valid=True,
        url=url,
        scheme="https",
        host=normalized_host,
        port=port,
        path=parts.path,
        matched_provider=provider_id,
    )


def _emit(result: ValidationResult, *, json_mode: bool) -> str:
    if json_mode:
        return json.dumps(result.as_dict(), indent=2, sort_keys=True)
    if result.valid:
        return f"VALID host={result.host} port={result.port} provider={result.matched_provider}"
    return f"[{result.code}] {result.detail}"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="endpoint-validator",
        description="Validate a URL against the cycle-099 endpoint allowlist (SDD §1.9.1).",
    )
    parser.add_argument("url", help="URL to validate")
    parser.add_argument(
        "--allowlist",
        required=True,
        help=(
            "Path to JSON allowlist with shape "
            '{"providers": {"<id>": [{"host": "...", "ports": [...]}]}}'
        ),
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit machine-readable JSON instead of a human-readable line.",
    )
    args = parser.parse_args(argv)

    try:
        allowlist = load_allowlist(args.allowlist)
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"[ALLOWLIST-LOAD-FAILED] {exc}", file=sys.stderr)
        return EXIT_USAGE

    result = validate(args.url, allowlist)
    out = _emit(result, json_mode=args.json)
    if result.valid:
        # Acceptance always to stdout (operator-visible canonicalized JSON).
        print(out)
        return EXIT_VALID
    # Rejection always to stderr per SDD §6.2 ("All errors emitted via stderr
    # in the structured shape"). gp M1 + cypherpunk LOW 3: tests had merged
    # 2>&1 streams and could not detect a stream-placement regression.
    print(out, file=sys.stderr)
    return EXIT_REJECTED


if __name__ == "__main__":
    raise SystemExit(main())
