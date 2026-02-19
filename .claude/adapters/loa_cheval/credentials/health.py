"""Credential health checks — validate API keys against provider endpoints (SDD §4.1.4).

Performs format-only validation by default (dry-run mode). Live HTTP checks
require explicit opt-in via ``live=True`` to prevent plaintext key exposure
to network proxies. (cycle-028 FR-2)
"""

from __future__ import annotations

import logging
import re
import urllib.request
import urllib.error
import json
from typing import Dict, List, NamedTuple, Optional

from loa_cheval.credentials.providers import CredentialProvider

logger = logging.getLogger(__name__)


class HealthResult(NamedTuple):
    """Result of a single credential health check."""
    credential_id: str
    status: str  # "ok" | "error" | "missing" | "skipped" | "format_invalid" | "unknown/weak_validation"
    message: str


# Per-provider format validation rules (cycle-028 FR-2, SDD §3.2.1)
FORMAT_RULES: Dict[str, dict] = {
    "OPENAI_API_KEY": {
        "prefix": "sk-",
        "min_length": 48,
        "charset": re.compile(r"^sk-[A-Za-z0-9_-]+$"),
        "description": "OpenAI API key",
        "spec_version": "2024-01",
    },
    "ANTHROPIC_API_KEY": {
        "prefix": "sk-ant-",
        "min_length": 93,
        "charset": re.compile(r"^sk-ant-[A-Za-z0-9_-]+$"),
        "description": "Anthropic API key",
        "spec_version": "2024-01",
    },
    "MOONSHOT_API_KEY": {
        "prefix": None,
        "min_length": 1,
        "charset": None,
        "description": "Moonshot API key",
        "spec_version": None,
        "validation_confidence": "weak",
    },
}

# Known credential health check configurations (live HTTP endpoints)
HEALTH_CHECKS: Dict[str, dict] = {
    "OPENAI_API_KEY": {
        "url": "https://api.openai.com/v1/models",
        "header": "Authorization",
        "header_prefix": "Bearer ",
        "expected_status": 200,
        "description": "OpenAI API",
    },
    "ANTHROPIC_API_KEY": {
        "url": "https://api.anthropic.com/v1/messages",
        "header": "x-api-key",
        "header_prefix": "",
        "method": "POST",
        # Deliberately malformed body (missing required 'model' field) to get 400
        # without generating a real completion. 401 = bad key, 400 = key is valid.
        "body": json.dumps({"max_tokens": 1, "messages": [{"role": "user", "content": "ping"}]}),
        "content_type": "application/json",
        "extra_headers": {"anthropic-version": "2023-06-01"},
        "expected_status": [400],
        "description": "Anthropic API",
    },
    "MOONSHOT_API_KEY": {
        "url": "https://api.moonshot.cn/v1/models",
        "header": "Authorization",
        "header_prefix": "Bearer ",
        "expected_status": 200,
        "description": "Moonshot API",
    },
}


def _redact_credential_from_error(error_msg: str, credential_value: str) -> str:
    """Remove credential value from error messages/stack traces."""
    if credential_value and credential_value in error_msg:
        return error_msg.replace(credential_value, "[REDACTED]")
    return error_msg


def _check_format(credential_id: str, value: str) -> HealthResult:
    """Validate credential format without making HTTP requests."""
    rule = FORMAT_RULES.get(credential_id)
    if rule is None:
        return HealthResult(credential_id, "skipped", "No format rule configured")

    # Moonshot: no stable format known
    if rule.get("validation_confidence") == "weak":
        return HealthResult(
            credential_id,
            "unknown/weak_validation",
            f"{rule['description']}: no stable format known — validation confidence is weak",
        )

    desc = rule["description"]

    # Check prefix
    if rule["prefix"] and not value.startswith(rule["prefix"]):
        return HealthResult(
            credential_id,
            "format_invalid",
            f"{desc}: expected prefix '{rule['prefix']}'",
        )

    # Check minimum length
    if len(value) < rule["min_length"]:
        return HealthResult(
            credential_id,
            "format_invalid",
            f"{desc}: expected minimum {rule['min_length']} chars, got {len(value)}",
        )

    # Check charset
    if rule["charset"] and not rule["charset"].match(value):
        return HealthResult(
            credential_id,
            "format_invalid",
            f"{desc}: invalid character in key",
        )

    return HealthResult(credential_id, "ok", f"{desc}: format valid")


def _check_live(
    credential_id: str,
    value: str,
    timeout: float = 10.0,
) -> HealthResult:
    """Check a credential against its provider endpoint via HTTP."""
    config = HEALTH_CHECKS.get(credential_id)
    if config is None:
        return HealthResult(credential_id, "skipped", "No health check configured")

    logger.warning(
        "[health] WARN: live credential check for %s — key may be visible to network proxies",
        credential_id,
    )

    url = config["url"]
    header_name = config["header"]
    header_value = config.get("header_prefix", "") + value

    try:
        req = urllib.request.Request(url, method=config.get("method", "GET"))
        req.add_header(header_name, header_value)

        for k, v in config.get("extra_headers", {}).items():
            req.add_header(k, v)

        if config.get("body"):
            req.data = config["body"].encode()
        if config.get("content_type"):
            req.add_header("Content-Type", config["content_type"])

        # Disable debug output that could leak headers
        opener = urllib.request.build_opener(
            urllib.request.HTTPHandler(debuglevel=0),
            urllib.request.HTTPSHandler(debuglevel=0),
        )
        response = opener.open(req, timeout=timeout)
        status = response.status

        expected = config["expected_status"]
        if isinstance(expected, list):
            if status in expected:
                return HealthResult(credential_id, "ok", f"{config['description']}: valid (HTTP {status})")
        elif status == expected:
            return HealthResult(credential_id, "ok", f"{config['description']}: valid (HTTP {status})")

        return HealthResult(credential_id, "error", f"{config['description']}: unexpected HTTP {status}")

    except urllib.error.HTTPError as e:
        expected = config["expected_status"]
        if isinstance(expected, list) and e.code in expected:
            return HealthResult(credential_id, "ok", f"{config['description']}: valid (HTTP {e.code})")
        if e.code == 401:
            return HealthResult(credential_id, "error", f"{config['description']}: invalid key (HTTP 401)")
        if e.code == 403:
            return HealthResult(credential_id, "error", f"{config['description']}: access denied (HTTP 403)")
        return HealthResult(credential_id, "error", f"{config['description']}: HTTP {e.code}")

    except Exception as e:
        redacted_msg = _redact_credential_from_error(str(e), value)
        return HealthResult(credential_id, "error", f"{config['description']}: {redacted_msg}")


def check_credential(
    credential_id: str,
    value: str,
    timeout: float = 10.0,
    live: bool = False,
) -> HealthResult:
    """Check a single credential's validity.

    By default (live=False), performs format-only validation without HTTP requests.
    With live=True, makes HTTP requests to provider endpoints.
    """
    if live:
        return _check_live(credential_id, value, timeout)
    return _check_format(credential_id, value)


def check_all(
    provider: CredentialProvider,
    credential_ids: Optional[List[str]] = None,
    timeout: float = 10.0,
    live: bool = False,
) -> List[HealthResult]:
    """Check all known credentials using the given provider.

    Args:
        provider: Credential provider to read values from
        credential_ids: Specific IDs to check (default: all known)
        timeout: HTTP timeout per check
        live: If True, make HTTP requests (default: format-only)
    """
    ids = credential_ids or list(HEALTH_CHECKS.keys())
    results = []

    for cred_id in ids:
        value = provider.get(cred_id)
        if value is None:
            results.append(HealthResult(cred_id, "missing", f"{cred_id} not configured"))
        else:
            results.append(check_credential(cred_id, value, timeout, live=live))

    return results
