"""Sprint 1 Task 1.9 (bd-20u) — GroundedResult parse + quality coverage.

Verifies SDD §3.1 / §3.4 / §12.3 behavior:
- OpenRouter annotations[] → Citation[] with rank + publisher
- Google groundingMetadata → Citation[] + executed_queries with
  searchEntryPoint href fallback and vertex URL filter
- Malformed OR response → GROUNDING_MALFORMED (schema validation)
- Inline [n] fallback when annotations[] empty
- coverage_estimate (IMP-002) bounds + monotonicity
- URL parseability/uniqueness invariants

All tests are offline — no HTTP. Adapter smoke tests use
`adapter._parse_response(...)` with literal response dicts.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.grounding import (
    GroundingMalformedError,
    compute_coverage_estimate,
    parse_google_grounding,
    parse_openrouter_annotations,
    validate_openrouter_response,
)
from loa_cheval.providers.google_adapter import _parse_response as google_parse_response
from loa_cheval.providers.openai_adapter import OpenAIAdapter
from loa_cheval.types import Citation, ModelConfig, ProviderConfig


# --- OpenRouter :online annotations path ---


def test_openrouter_annotations_primary_path():
    msg = {
        "role": "assistant",
        "content": "Phosphor decays [1]. Memory persists [2].",
        "annotations": [
            {"type": "url_citation", "url_citation": {"url": "https://a.com", "title": "A", "content": "snippet-a"}},
            {"type": "url_citation", "url_citation": {"url": "https://b.com", "title": "B", "content": "snippet-b"}},
        ],
    }
    gr = parse_openrouter_annotations(msg, msg["content"], latency_ms=1200)
    assert gr is not None
    assert gr.grounding_provenance == "exa"
    assert gr.grounded_runtime == "openrouter:online"
    assert len(gr.citations) == 2
    assert [c.url for c in gr.citations] == ["https://a.com", "https://b.com"]
    assert [c.rank for c in gr.citations] == [1, 2]
    assert gr.citations[0].publisher == "a.com"
    assert gr.citations[0].snippet == "snippet-a"
    assert gr.quality.citation_count == 2
    assert gr.quality.executed_query_count == 0
    assert gr.quality.citation_urls_parseable is True
    assert gr.quality.citation_urls_unique is True


def test_openrouter_inline_fallback_dedup():
    """Empty annotations[] + inline [n] markers → construct citations from
    markers, dedup repeated ranks (SDD §3.4 item 2)."""
    msg = {"role": "assistant", "content": "alpha [1][1] beta [2] gamma [1]", "annotations": []}
    gr = parse_openrouter_annotations(msg, msg["content"], latency_ms=200)
    assert gr is not None
    assert gr.extra.get("inline_parsed") is True
    # [1] appears 3×, [2] once → 2 unique after dedup
    assert len(gr.citations) == 2
    assert sorted(c.rank for c in gr.citations) == [1, 2]


def test_openrouter_no_grounding_returns_none():
    msg = {"role": "assistant", "content": "plain text with no markers"}
    assert parse_openrouter_annotations(msg, msg["content"], latency_ms=1) is None


# --- Google groundingMetadata path ---


def test_google_grounding_primary_plus_search_entry_point():
    """Lift of dig-search.ts:261-287 — groundingChunks merged with
    searchEntryPoint href fallback; vertex URLs are filtered."""
    candidate = {
        "groundingMetadata": {
            "groundingChunks": [
                {"web": {"title": "Wiki", "uri": "https://en.wikipedia.org/wiki/CRT"}},
                {"web": {"title": "Nature", "uri": "https://nature.com/a"}},
            ],
            "webSearchQueries": ["CRT phosphor decay", "cathode ray tube afterglow"],
            "searchEntryPoint": {
                "renderedContent": (
                    '<a href="https://extra.com/link">extra</a>'
                    '<a href="https://vertexaisearch.cloud.google.com/skip">skip</a>'
                ),
            },
        }
    }
    gr = parse_google_grounding(candidate, "CRT phosphors decay.", latency_ms=2800)
    assert gr is not None
    assert gr.grounding_provenance == "google_search"
    assert gr.grounded_runtime == "gemini:native"
    assert gr.executed_queries == ["CRT phosphor decay", "cathode ray tube afterglow"]
    urls = [c.url for c in gr.citations]
    assert "https://en.wikipedia.org/wiki/CRT" in urls
    assert "https://nature.com/a" in urls
    assert "https://extra.com/link" in urls
    # vertex URL filtered per dig-search.ts:274
    assert not any("vertexaisearch" in u for u in urls)


def test_google_no_grounding_metadata_returns_none():
    assert parse_google_grounding({}, "plain", latency_ms=100) is None


# --- Schema validation (SDD §12.3) ---


def test_validate_openrouter_response_rejects_malformed():
    malformed = {"choices": "not-a-list"}  # choices should be array
    with pytest.raises(GroundingMalformedError) as exc:
        validate_openrouter_response(malformed)
    assert exc.value.code == "GROUNDING_MALFORMED"


def test_validate_openrouter_response_accepts_valid_shape():
    valid = {
        "choices": [
            {
                "message": {
                    "role": "assistant",
                    "content": "ok",
                    "annotations": [
                        {"type": "url_citation", "url_citation": {"url": "https://a.com"}}
                    ],
                }
            }
        ]
    }
    # Should not raise
    validate_openrouter_response(valid)


def test_validate_openrouter_requires_choices_min_items():
    with pytest.raises(GroundingMalformedError):
        validate_openrouter_response({"choices": []})


# --- coverage_estimate (IMP-002) ---


def test_coverage_empty_text_is_zero():
    assert compute_coverage_estimate("", []) == 0.0


def test_coverage_inline_markers_yield_full_coverage():
    """Every non-trivial sentence has an inline [n] → 1.0."""
    text = "Alpha phosphor decays within microseconds [1]. Beta memory clears similarly [2]."
    c = Citation(title="t", url="https://a.com", snippet="", publisher="a.com")
    assert compute_coverage_estimate(text, [c]) == 1.0


def test_coverage_no_citations_no_markers_is_zero():
    text = "Alpha phosphor decays within microseconds. Beta memory clears similarly."
    assert compute_coverage_estimate(text, []) == 0.0


def test_coverage_bounded_0_1():
    """Coverage must always be in [0.0, 1.0] regardless of input."""
    text = "Alpha [1]. " * 10
    cs = [Citation(title="x", url="https://x.com", snippet="", publisher="x.com")]
    val = compute_coverage_estimate(text, cs)
    assert 0.0 <= val <= 1.0


def test_coverage_nearby_window_plus_minus_two():
    """Citation in sentence 0 covers sentence 2 (within ±2) but not sentence 5."""
    # 6 non-trivial sentences; only sentence 0 has [1] marker
    sentences = [
        "Alpha is a non-trivial sentence [1] with citation.",
        "Beta is a non-trivial sentence with no citation marker.",
        "Gamma is a non-trivial sentence with no citation marker.",
        "Delta is a non-trivial sentence with no citation marker.",
        "Epsilon is a non-trivial sentence with no citation marker.",
        "Zeta is a non-trivial sentence with no citation marker.",
    ]
    text = " ".join(sentences)
    cs = [Citation(title="x", url="https://x.com", snippet="", publisher="x.com")]
    val = compute_coverage_estimate(text, cs)
    # sentences 0,1,2 covered (within ±2 of sentence 0); 3,4,5 not covered
    assert val == pytest.approx(0.5, abs=0.0001)


# --- URL parseability + uniqueness invariants ---


def test_quality_urls_unique_false_on_duplicate():
    msg = {
        "role": "assistant",
        "content": "",
        "annotations": [
            {"type": "url_citation", "url_citation": {"url": "https://same.com", "title": "a"}},
            {"type": "url_citation", "url_citation": {"url": "https://same.com", "title": "b"}},
        ],
    }
    gr = parse_openrouter_annotations(msg, "text", latency_ms=1)
    assert gr is not None
    assert gr.quality.citation_urls_parseable is True
    assert gr.quality.citation_urls_unique is False


def test_quality_urls_parseable_false_on_bogus_url():
    """Citations with missing scheme/netloc fail parseability."""
    # Construct GroundedQuality path directly via parse w/ a weird url — the
    # inline fallback generates empty urls which should trip parseability.
    msg = {"role": "assistant", "content": "seg [1] seg", "annotations": []}
    gr = parse_openrouter_annotations(msg, "seg [1] seg", latency_ms=1)
    assert gr is not None
    # inline fallback citations have empty urls → not parseable
    assert gr.quality.citation_urls_parseable is False


# --- End-to-end: adapter._parse_response populates GroundedResult ---


def _make_openai_config() -> ProviderConfig:
    return ProviderConfig(
        name="openrouter",
        type="openai_compat",
        endpoint="https://openrouter.ai/api/v1",
        auth="test-key",
        models={"openrouter/google/gemini-3-flash-preview:online": ModelConfig()},
    )


def test_openai_adapter_plain_response_leaves_grounded_none():
    adapter = OpenAIAdapter(_make_openai_config())
    resp = {
        "choices": [{"message": {"role": "assistant", "content": "hello"}}],
        "usage": {"prompt_tokens": 1, "completion_tokens": 1},
        "model": "gpt-5.2",
    }
    r = adapter._parse_response(resp, latency_ms=10)
    assert r.content == "hello"
    assert r.grounded is None


def test_openai_adapter_online_response_attaches_grounded():
    adapter = OpenAIAdapter(_make_openai_config())
    resp = {
        "choices": [
            {
                "message": {
                    "role": "assistant",
                    "content": "phosphor persists [1].",
                    "annotations": [
                        {"type": "url_citation", "url_citation": {"url": "https://a.com", "title": "A", "content": "s"}}
                    ],
                }
            }
        ],
        "usage": {"prompt_tokens": 1, "completion_tokens": 1},
        "model": "openrouter/google/gemini-3-flash-preview:online",
    }
    r = adapter._parse_response(resp, latency_ms=1200)
    assert r.grounded is not None
    assert r.grounded.grounding_provenance == "exa"
    assert len(r.grounded.citations) == 1
    assert r.grounded.grounded_runtime == "openrouter:online"


def test_google_adapter_plain_response_leaves_grounded_none():
    resp = {
        "candidates": [{"content": {"parts": [{"text": "hello"}]}}],
        "usageMetadata": {"promptTokenCount": 1, "candidatesTokenCount": 1},
    }
    r = google_parse_response(resp, "gemini-3", 10, "google", ModelConfig(), input_text_length=10)
    assert r.grounded is None


def test_google_adapter_grounded_response_attaches_grounded():
    resp = {
        "candidates": [
            {
                "content": {"parts": [{"text": "CRT phosphor decays."}]},
                "groundingMetadata": {
                    "groundingChunks": [{"web": {"title": "w", "uri": "https://w.com"}}],
                    "webSearchQueries": ["q"],
                },
            }
        ],
        "usageMetadata": {"promptTokenCount": 1, "candidatesTokenCount": 1},
    }
    r = google_parse_response(resp, "gemini-3", 100, "google", ModelConfig(), input_text_length=10)
    assert r.grounded is not None
    assert r.grounded.grounding_provenance == "google_search"
    assert r.grounded.executed_queries == ["q"]
    assert len(r.grounded.citations) == 1
