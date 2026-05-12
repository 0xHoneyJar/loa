"""capability_gate.check tests (cycle-104 Sprint 2, SDD §1.4.2 / §5.2).

Pinned behavior:
- `ok=True` when entry declares every required capability.
- `ok=False` + `missing=[...]` when at least one required cap is absent.
- `request.tools` non-empty ⇒ `tools` is required (conservative inference).
- `request.tools = []` or absent ⇒ `tools` NOT required.
- `metadata.requires_capabilities` overrides inference entirely.
- Skip semantics: result carries the missing list; never raises on a miss.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.routing.capability_gate import (
    METADATA_REQUIRES_KEY,
    check,
)
from loa_cheval.routing.types import (
    CapabilityCheckResult,
    ResolvedEntry,
)
from loa_cheval.types import CompletionRequest


def _entry(caps: list[str], kind: str = "http") -> ResolvedEntry:
    return ResolvedEntry(
        provider="openai",
        model_id="m",
        adapter_kind=kind,  # type: ignore[arg-type]
        capabilities=frozenset(caps),
    )


def _req(**kwargs) -> CompletionRequest:
    base = {
        "messages": [{"role": "user", "content": "hi"}],
        "model": "openai:m",
    }
    base.update(kwargs)
    return CompletionRequest(**base)


# --- ok cases ---


def test_chat_only_passes_when_entry_has_chat():
    result = check(_req(), _entry(["chat"]))
    assert result.ok is True
    assert result.missing == ()


def test_tools_required_only_when_request_has_tools():
    req = _req(tools=[{"name": "fn"}])
    result = check(req, _entry(["chat", "tools"]))
    assert result.ok is True


def test_tools_NOT_required_when_request_tools_absent():
    """A bare chat call to a headless CLI without tools should pass."""
    result = check(_req(), _entry(["chat"]))  # CLI-style entry: chat only
    assert result.ok is True


def test_tools_NOT_required_when_request_tools_empty_list():
    result = check(_req(tools=[]), _entry(["chat"]))
    assert result.ok is True


# --- miss cases ---


def test_missing_tools_returns_skip_signal():
    req = _req(tools=[{"name": "fn"}])
    result = check(req, _entry(["chat"]))  # no `tools` declared
    assert result.ok is False
    assert result.missing == ("tools",)


def test_missing_chat_returns_skip_signal():
    """Pathological case — `chat` is the baseline; missing it is fatal."""
    result = check(_req(), _entry([]))
    assert result.ok is False
    assert "chat" in result.missing


def test_returns_all_missing_caps_sorted():
    req = _req(tools=[{"name": "fn"}], metadata={
        METADATA_REQUIRES_KEY: ["chat", "tools", "structured_json"],
    })
    result = check(req, _entry(["chat"]))
    assert result.ok is False
    assert result.missing == ("structured_json", "tools")  # sorted


# --- metadata.requires_capabilities override ---


def test_metadata_override_replaces_inferred_set():
    """Explicit override wins even when request has no tools."""
    req = _req(metadata={METADATA_REQUIRES_KEY: ["chat", "large_context"]})
    result = check(req, _entry(["chat"]))
    assert result.ok is False
    assert result.missing == ("large_context",)


def test_metadata_override_with_all_caps_satisfied_passes():
    req = _req(metadata={
        METADATA_REQUIRES_KEY: ["chat", "tools", "structured_json"],
    })
    result = check(req, _entry(["chat", "tools", "structured_json"]))
    assert result.ok is True


def test_metadata_override_accepts_set_and_tuple():
    for value in ({"chat"}, ("chat",), ["chat"]):
        req = _req(metadata={METADATA_REQUIRES_KEY: value})
        result = check(req, _entry(["chat"]))
        assert result.ok is True


def test_metadata_override_rejects_bare_string():
    """Bare strings are a frequent typo — coerce_caps fails loudly."""
    req = _req(metadata={METADATA_REQUIRES_KEY: "chat"})
    with pytest.raises(TypeError):
        check(req, _entry(["chat"]))


def test_metadata_override_rejects_non_string_item():
    req = _req(metadata={METADATA_REQUIRES_KEY: ["chat", 123]})
    with pytest.raises(TypeError):
        check(req, _entry(["chat"]))


def test_metadata_override_rejects_empty_string_item():
    req = _req(metadata={METADATA_REQUIRES_KEY: ["chat", ""]})
    with pytest.raises(TypeError):
        check(req, _entry(["chat"]))


# --- Result shape ---


def test_result_is_frozen_dataclass():
    result = check(_req(), _entry(["chat"]))
    assert isinstance(result, CapabilityCheckResult)
    with pytest.raises(AttributeError):
        result.ok = False  # type: ignore[misc]


def test_check_does_not_raise_on_miss():
    """Skip-and-continue contract — never raise on capability gap."""
    result = check(_req(tools=[{"name": "fn"}]), _entry(["chat"]))
    assert result.ok is False  # No exception raised.
