"""cycle-127 sprint-251 review r251-1 C9 — parse_context_limit reads the
headless CLI's own pre-flight rejection shape (Claude Code 2.1.292):

  Prompt is too long · the request is ~1065182 tokens (limit 1000000) but ...
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from loa_cheval.routing.ceiling import is_context_limit_message, parse_context_limit  # noqa: E402

CLI_MSG = ("Prompt is too long · the request is ~1065182 tokens (limit 1000000) but this conversation is only "
           "~665270 tokens — the rest is system prompt, tool definitions, and attachment content.")


def test_cli_preflight_shape_states_the_count_and_the_limit():
    assert is_context_limit_message(CLI_MSG)
    assert parse_context_limit(CLI_MSG) == {"input_tokens": 1_065_182, "limit": 1_000_000, "max_tokens": None}


def test_cli_shape_variants():
    assert parse_context_limit("request is 1,065,182 tokens (limit 1,000,000)") == {
        "input_tokens": 1_065_182, "limit": 1_000_000, "max_tokens": None}
    assert parse_context_limit("~990000 tokens (limit: 1000000)")["limit"] == 1_000_000


def test_the_api_shapes_are_unchanged():
    assert parse_context_limit("prompt is too long: 1065182 tokens > 1000000 maximum") == {
        "input_tokens": 1_065_182, "limit": 1_000_000, "max_tokens": None}
    assert parse_context_limit("input length and `max_tokens` exceed context limit: 950000 + 64000 > 1000000") == {
        "input_tokens": 950_000, "limit": 1_000_000, "max_tokens": 64_000}
    assert parse_context_limit("something else") == {"input_tokens": None, "limit": None, "max_tokens": None}
