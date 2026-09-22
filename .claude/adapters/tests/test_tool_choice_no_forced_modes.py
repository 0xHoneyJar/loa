"""cycle-124 Sprint 2 Task 2.2 (FR-7): only `auto` / `none` tool_choice is ever
emitted on the Anthropic adapter; `required` (Anthropic `any`) and unknown
values raise InvalidInputError instead of being rewritten to `auto`."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from loa_cheval.providers.anthropic_adapter import _transform_tool_choice  # noqa: E402
from loa_cheval.types import InvalidInputError  # noqa: E402


@pytest.mark.parametrize("choice, expected", [("auto", {"type": "auto"}), ("none", {"type": "none"})])
def test_supported_modes_pass_through(choice, expected):
    assert _transform_tool_choice(choice) == expected


@pytest.mark.parametrize("choice", ["required", "any", "", "tool", "AUTO", "weird"])
def test_forced_and_unknown_modes_raise(choice):
    with pytest.raises(InvalidInputError):
        _transform_tool_choice(choice)
