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
_BLOCKED_IPV6_NETWORKS: tuple[ipaddress.IPv6Network, ...] = (
    ipaddress.IPv6Network("::1/128"),       # loopback
    ipaddress.IPv6Network("fe80::/10"),     # link-local
    ipaddress.IPv6Network("fc00::/7"),      # unique-local (RFC 4193)
    ipaddress.IPv6Network("ff00::/8"),      # multicast
    ipaddress.IPv6Network("::/128"),        # unspecified
    ipaddress.IPv6Network("::ffff:0:0/96"), # IPv4-mapped (might decode to private v4)
    ipaddress.IPv6Network("64:ff9b::/96"),  # NAT64 well-known
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
    # AWS IMDS — explicitly named here even though it falls under is_link_local.
    if isinstance(addr, ipaddress.IPv4Address) and str(addr) == "169.254.169.254":
        return True, "IP 169.254.169.254 is the AWS IMDS metadata endpoint"
    return False, None


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


_ALLOWLIST_MAX_BYTES = 65536  # 64 KiB — see cypherpunk LOW 1


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
