"""Live integration test for BedrockAdapter (cycle-096 Sprint 1 / FR-10).

Skips unless ``LOA_RUN_LIVE_BEDROCK_TESTS=1`` is explicitly set and a
Bedrock token is available. An ambient credential alone never enables
provider calls. After opt-in, the token may come from the environment
or the maintainer's repository ``.env`` file.

Test coverage:

* End-to-end Converse call against a real Day-1 Anthropic inference
  profile with normalized response shape assertions
* Bare ``anthropic.*`` model ID returns OnDemandNotSupportedError as
  expected (regression guard against AWS changing the error semantics)
* health_check() returns True against ListFoundationModels

The total cost cap is implicit: each test issues a single Converse call
with ``max_tokens=16``, costing fractions of a cent per Day-1 model.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.providers.bedrock_adapter import (  # noqa: E402
    BedrockAdapter,
    OnDemandNotSupportedError,
    _DAILY_QUOTA_EXCEEDED,
)
from loa_cheval.types import (  # noqa: E402
    CompletionRequest,
    ModelConfig,
    ProviderConfig,
)


@pytest.fixture(autouse=True)
def _reset_circuit_breaker():
    """Daily-quota circuit breaker is process-scoped; clear before each test
    to isolate from other test modules that may have set it."""
    _DAILY_QUOTA_EXCEEDED.clear()
    yield
    _DAILY_QUOTA_EXCEEDED.clear()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _live_token() -> str:
    """Load the live Bedrock token from env or .env file.

    The .env file lives at the repo root and is gitignored. We prefer the
    process env (set by shell or CI), then fall back to .env to make local
    dev work without explicit `source .env`.
    """
    val = os.environ.get("AWS_BEARER_TOKEN_BEDROCK")
    if val:
        return val
    # Fallback: look for repo-root .env. Walk up from this file.
    here = Path(__file__).resolve()
    for parent in here.parents:
        candidate = parent / ".env"
        if candidate.exists():
            for line in candidate.read_text().splitlines():
                line = line.strip()
                if line.startswith("AWS_BEARER_TOKEN_BEDROCK="):
                    return line.split("=", 1)[1]
        if (parent / ".git").exists():
            break
    return ""


def _has_token() -> bool:
    return bool(_live_token())


# Check explicit consent before looking for credentials, including .env files.
pytestmark = pytest.mark.skipif(
    os.environ.get("LOA_RUN_LIVE_BEDROCK_TESTS") != "1" or not _has_token(),
    reason=(
        "Live Bedrock integration requires LOA_RUN_LIVE_BEDROCK_TESTS=1 "
        "and AWS_BEARER_TOKEN_BEDROCK in env or .env."
    ),
)


def _make_provider_config() -> ProviderConfig:
    """Build a minimal but realistic Bedrock ProviderConfig for live tests."""
    token = _live_token()
    region = os.environ.get("AWS_BEDROCK_REGION", "us-east-1")
    return ProviderConfig(
        name="bedrock",
        type="bedrock",
        endpoint="https://bedrock-runtime.{region}.amazonaws.com",
        auth=token,
        region_default=region,
        auth_modes=["api_key", "sigv4"],
        compliance_profile="bedrock_only",
        models={
            "us.anthropic.claude-haiku-4-5-20251001-v1:0": ModelConfig(
                capabilities=["chat", "tools", "function_calling"],
                context_window=200000,
                token_param="max_tokens",
                api_format={"chat": "converse"},
                fallback_to="anthropic:claude-haiku-4-5-20251001",
                fallback_mapping_version=1,
            ),
        },
    )


# ---------------------------------------------------------------------------
# Live tests
# ---------------------------------------------------------------------------


@pytest.mark.integration
def test_live_converse_against_haiku_returns_text():
    """End-to-end: real Bedrock call returns a normalized CompletionResult."""
    config = _make_provider_config()
    adapter = BedrockAdapter(config)

    request = CompletionRequest(
        messages=[{"role": "user", "content": "Reply with the single word: ok."}],
        model="us.anthropic.claude-haiku-4-5-20251001-v1:0",
        temperature=0.0,
        max_tokens=16,
    )
    result = adapter.complete(request)

    # Response must be non-empty.
    assert isinstance(result.content, str)
    assert len(result.content) > 0
    # Usage must be populated and snake_case (cheval canonical, NOT Bedrock camelCase).
    assert result.usage.input_tokens > 0
    assert result.usage.output_tokens > 0
    # Provider tag is correct (cost-ledger queries depend on this).
    assert result.provider == "bedrock"
    # Model echo matches the request.
    assert result.model == "us.anthropic.claude-haiku-4-5-20251001-v1:0"


@pytest.mark.integration
def test_live_bare_anthropic_id_returns_on_demand_not_supported():
    """Regression guard: AWS still rejects bare anthropic.* IDs as of probe date."""
    # Build a config with a bare ID (intentionally invalid; tests the
    # adapter's error classifier against the live API).
    config = _make_provider_config()
    config.models["anthropic.claude-haiku-4-5-20251001-v1:0"] = ModelConfig(
        capabilities=["chat"],
        context_window=200000,
        token_param="max_tokens",
        # No fallback_to needed since compliance_profile=bedrock_only doesn't
        # exercise the fallback path.
    )
    adapter = BedrockAdapter(config)

    request = CompletionRequest(
        messages=[{"role": "user", "content": "ok"}],
        model="anthropic.claude-haiku-4-5-20251001-v1:0",
        temperature=0.0,
        max_tokens=8,
    )
    with pytest.raises(OnDemandNotSupportedError) as exc_info:
        adapter.complete(request)
    # Remediation message names the inference profile namespaces.
    assert "us.anthropic" in str(exc_info.value) or "global.anthropic" in str(exc_info.value)


@pytest.mark.integration
def test_live_health_check_returns_true():
    """ListFoundationModels with Bearer auth — cheap, no token usage."""
    config = _make_provider_config()
    adapter = BedrockAdapter(config)
    assert adapter.health_check() is True
