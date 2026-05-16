"""cycle-109 Sprint 5 T5.1 — closes #874.

The peek path in cheval.py cmd_invoke ([1009-1015]) hardcodes
``_advisor_inferred_provider = "anthropic"`` on ANY peek failure
(unknown agent, broken alias chain). This silently mutates
``args.model`` with the wrong provider for non-anthropic bindings
when the failure mode is benign (e.g., a stale `aliases:` entry).

The fix extracts the peek into a helper ``_peek_provider_for_advisor``
that returns ``Optional[str]`` (None on failure). cmd_invoke then
treats None as "disable advisor for this invocation" instead of
defaulting to a provider.

Test-first: these pin the helper's failure semantics BEFORE the
helper exists. They will fail until T5.1 lands the implementation.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


# ---------------------------------------------------------------------------
# Helper-level tests
# ---------------------------------------------------------------------------


def test_peek_returns_provider_for_valid_anthropic_binding():
    """Happy path: a known agent bound to an anthropic alias returns
    'anthropic' from the peek helper."""
    cheval = _import_cheval_module()
    hounfour = {
        "agents": {
            "test-agent": {"model": "claude-opus-4-7"},
        },
        "aliases": {
            "claude-opus-4-7": "anthropic:claude-opus-4-7-20260101",
        },
    }
    result = cheval._peek_provider_for_advisor("test-agent", hounfour)
    assert result == "anthropic"


def test_peek_returns_provider_for_valid_openai_binding():
    """Happy path: an agent bound to an openai alias returns 'openai',
    NOT 'anthropic' (the bug class #874 documents)."""
    cheval = _import_cheval_module()
    hounfour = {
        "agents": {
            "test-agent": {"model": "gpt-5.5-pro"},
        },
        "aliases": {
            "gpt-5.5-pro": "openai:gpt-5.5-pro-20260101",
        },
    }
    result = cheval._peek_provider_for_advisor("test-agent", hounfour)
    assert result == "openai"


def test_peek_returns_none_on_unknown_agent():
    """Unhappy path #1: unknown agent. Helper returns None (disable
    advisor) instead of defaulting to 'anthropic'."""
    cheval = _import_cheval_module()
    hounfour = {
        "agents": {"known-agent": {"model": "claude-opus-4-7"}},
        "aliases": {"claude-opus-4-7": "anthropic:claude-opus-4-7-20260101"},
    }
    result = cheval._peek_provider_for_advisor("totally-unknown-agent", hounfour)
    assert result is None


def test_peek_returns_none_on_broken_alias_chain():
    """Unhappy path #2: agent binds to an alias that doesn't exist
    in the aliases table. Helper returns None instead of defaulting
    to 'anthropic'."""
    cheval = _import_cheval_module()
    hounfour = {
        "agents": {"test-agent": {"model": "nonexistent-alias-xyz"}},
        "aliases": {"claude-opus-4-7": "anthropic:claude-opus-4-7-20260101"},
    }
    result = cheval._peek_provider_for_advisor("test-agent", hounfour)
    assert result is None


def test_peek_returns_none_on_empty_hounfour():
    """Edge case: empty hounfour config. Helper returns None
    instead of raising."""
    cheval = _import_cheval_module()
    result = cheval._peek_provider_for_advisor("any-agent", {})
    assert result is None


# ---------------------------------------------------------------------------
# Module loader (handles cheval.py being a script-style module)
# ---------------------------------------------------------------------------


def _import_cheval_module():
    """Load cheval.py via importlib so the test module can reach
    the private helper without invoking the CLI entrypoint.

    cheval.py uses dataclasses; dataclasses' internals walk sys.modules
    via __module__ to resolve forward-refs, so we must register the
    module under its assigned name BEFORE exec_module."""
    import importlib.util

    module_name = "cheval_t51_advisor_peek"
    if module_name in sys.modules:
        return sys.modules[module_name]
    cheval_path = ROOT / "cheval.py"
    spec = importlib.util.spec_from_file_location(module_name, cheval_path)
    if spec is None or spec.loader is None:
        pytest.skip("could not load cheval module spec")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module  # register BEFORE exec_module (dataclasses needs this)
    try:
        spec.loader.exec_module(module)
    except Exception:
        sys.modules.pop(module_name, None)
        raise
    return module
