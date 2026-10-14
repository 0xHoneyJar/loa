"""cycle-126 Sprint 1 Task 1.1 / 1.3 (PRD FR-1.4, SDD D-1.4) — the estimate
carries its uncertainty: ASCII prose is `low`; CJK-dense text, emoji-dense
text and tool payloads are `high` (the content classes where `chars / 3.5`
and an OpenAI encoding undercount Claude tokens).
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from loa_cheval.providers.base import NON_ASCII_HIGH_SHARE, estimate_input, estimate_tokens  # noqa: E402

ASCII = "The quick brown fox jumps over the lazy dog. " * 200
CJK = "東京都は日本の首都であり、政治・経済の中心地である。" * 100
EMOJI = "🚀🔥✨🎉🙂👍💡📈🧪🛠️ " * 200


def _msgs(text):
    return [{"role": "user", "content": text}]


def test_ascii_prose_is_low_and_matches_estimate_tokens():
    e = estimate_input(_msgs(ASCII))
    assert e.uncertainty == "low" and e.non_ascii_share == 0.0 and e.tool_payload is False
    assert e.tokens == estimate_tokens(_msgs(ASCII)) and e.chars == len(ASCII)
    assert e.method in ("tiktoken", "heuristic")


def test_cjk_and_emoji_dense_text_are_high():
    for text in (CJK, EMOJI):
        e = estimate_input(_msgs(text))
        assert e.non_ascii_share > NON_ASCII_HIGH_SHARE and e.uncertainty == "high", text[:10]


def test_a_little_non_ascii_inside_prose_stays_low():
    e = estimate_input(_msgs(ASCII + "東京"))
    assert 0 < e.non_ascii_share < NON_ASCII_HIGH_SHARE and e.uncertainty == "low"


def test_tool_payloads_are_high_in_every_shape():
    assert estimate_input(_msgs(ASCII), tools=[{"name": "t"}]).uncertainty == "high"
    assert estimate_input([{"role": "tool", "tool_call_id": "x", "content": ASCII}]).uncertainty == "high"
    assert estimate_input([{"role": "user", "content": [{"type": "tool_result", "tool_use_id": "x", "content": "ok"},
                                                          {"type": "text", "text": ASCII}]}]).uncertainty == "high"
    assert estimate_input([{"role": "assistant", "content": [{"type": "tool_use", "id": "x", "name": "t", "input": {}}]}]).tool_payload


def test_envelope_shape():
    env = estimate_input(_msgs(ASCII)).as_envelope()
    assert set(env) == {"method", "chars", "tokens", "uncertainty", "non_ascii_share", "tool_payload"}


def test_content_blocks_count_their_text():
    blocks = [{"role": "user", "content": [{"type": "text", "text": ASCII}, {"type": "text", "text": ASCII}]}]
    assert estimate_input(blocks).chars == 2 * len(ASCII)
