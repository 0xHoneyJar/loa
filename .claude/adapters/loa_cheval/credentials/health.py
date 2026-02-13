"""Credential health checks — validate API keys against provider endpoints (SDD §4.1.4).

Performs lightweight HTTP checks to verify credentials are valid
without consuming API quotas.
"""

from __future__ import annotations

import urllib.request
import urllib.error
import json
from typing import Dict, List, NamedTuple, Optional

from loa_cheval.credentials.providers import CredentialProvider


class HealthResult(NamedTuple):
    """Result of a single credential health check."""
    credential_id: str
    status: str  # "ok" | "error" | "missing" | "skipped"
    message: str


# Known credential health check configurations
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


def check_credential(
    credential_id: str,
    value: str,
    timeout: float = 10.0,
) -> HealthResult:
    """Check a single credential against its provider endpoint."""
    config = HEALTH_CHECKS.get(credential_id)
    if config is None:
        return HealthResult(credential_id, "skipped", "No health check configured")

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

        response = urllib.request.urlopen(req, timeout=timeout)
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
        return HealthResult(credential_id, "error", f"{config['description']}: {e}")


def check_all(
    provider: CredentialProvider,
    credential_ids: Optional[List[str]] = None,
    timeout: float = 10.0,
) -> List[HealthResult]:
    """Check all known credentials using the given provider.

    Args:
        provider: Credential provider to read values from
        credential_ids: Specific IDs to check (default: all known)
        timeout: HTTP timeout per check
    """
    ids = credential_ids or list(HEALTH_CHECKS.keys())
    results = []

    for cred_id in ids:
        value = provider.get(cred_id)
        if value is None:
            results.append(HealthResult(cred_id, "missing", f"{cred_id} not configured"))
        else:
            results.append(check_credential(cred_id, value, timeout))

    return results
