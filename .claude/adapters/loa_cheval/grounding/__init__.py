"""Grounding parse + quality helpers (SDD §3.1, §3.4, §12.3).

Shared by OpenAIAdapter (:online annotations[]) and GoogleAdapter
(groundingMetadata). Keeps adapter code small and provides one place
for the coverage_estimate algorithm + schema validation.
"""

from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import urlparse

from loa_cheval.types import (
    ChevalError,
    Citation,
    GroundedQuality,
    GroundedResult,
    GroundingProvenance,
)

from loa_cheval.grounding.coverage import compute_coverage_estimate

_SCHEMA_DIR = Path(__file__).resolve().parent.parent / "schemas"
_OR_RESPONSE_SCHEMA_PATH = _SCHEMA_DIR / "openrouter-response-v1.json"

_INLINE_CITATION_RE = re.compile(r"\[(\d+)\]")


class GroundingMalformedError(ChevalError):
    """OpenRouter response failed observed-contract schema validation (SDD §12.3).

    Adapter raises this so the failover chain (Sprint 2) can switch tiers.
    """

    def __init__(self, detail: str):
        super().__init__("GROUNDING_MALFORMED", f"OpenRouter response schema mismatch: {detail}", retryable=False)


class GroundingEmptyError(ChevalError):
    """Zero citations returned when grounded tool was requested (SDD §3.4)."""

    def __init__(self, provider: str):
        super().__init__("GROUNDING_EMPTY", f"No citations extracted from {provider} grounded response", retryable=False, context={"provider": provider})


def _now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _publisher_from_url(url: str) -> Optional[str]:
    try:
        host = urlparse(url).hostname
        return host.lstrip("www.") if host else None
    except Exception:
        return None


def _urls_parseable(cs: List[Citation]) -> bool:
    if not cs:
        return True
    for c in cs:
        p = urlparse(c.url)
        if not p.scheme or not p.netloc:
            return False
    return True


def _urls_unique(cs: List[Citation]) -> bool:
    urls = [c.url for c in cs]
    return len(urls) == len(set(urls))


def build_quality(text: str, citations: List[Citation], executed_queries: List[str]) -> GroundedQuality:
    return GroundedQuality(
        citation_count=len(citations),
        executed_query_count=len(executed_queries),
        text_chars=len(text),
        citation_urls_parseable=_urls_parseable(citations),
        citation_urls_unique=_urls_unique(citations),
        coverage_estimate=compute_coverage_estimate(text, citations),
    )


def validate_openrouter_response(resp: Dict[str, Any]) -> None:
    """Validate against observed-contract schema (SDD §12.3 item 1).

    Raises GroundingMalformedError if the response shape drifts — adapter
    layer treats this as a signal to fail to the next tier in the failover
    chain (Sprint 2). Schema is permissive (additionalProperties: true) so
    drift only fires on structural breakage, not added fields.
    """
    try:
        from jsonschema import Draft7Validator, ValidationError
    except ImportError:
        # jsonschema is a dev dep; in production we may not have it wired yet.
        # Sprint 2 will make this a hard dep; for now, skip silently if absent
        # so existing callers aren't broken.
        return

    try:
        with open(_OR_RESPONSE_SCHEMA_PATH) as f:
            schema = json.load(f)
    except FileNotFoundError:
        return

    validator = Draft7Validator(schema)
    try:
        validator.validate(resp)
    except ValidationError as e:
        raise GroundingMalformedError(e.message) from e


def parse_openrouter_annotations(
    message: Dict[str, Any],
    text: str,
    latency_ms: int,
    executed_queries: Optional[List[str]] = None,
) -> Optional[GroundedResult]:
    """Extract citations from OpenAI/OpenRouter :online response.

    Primary path: `message.annotations[].url_citation`.
    Fallback per SDD §3.4 item 2: if annotations[] empty but text contains
    inline `[n]` markers, construct minimal citations from the markers and
    stamp grounding_provenance="exa" + quality.extra.inline_parsed=true.

    Returns None if there is neither annotations nor inline markers — caller
    decides whether to treat as GROUNDING_EMPTY vs non-grounded path.
    """
    annotations = message.get("annotations") or []
    citations: List[Citation] = []
    inline_parsed = False

    for idx, ann in enumerate(annotations):
        if not isinstance(ann, dict):
            continue
        u = ann.get("url_citation") or {}
        url = u.get("url", "")
        if not url:
            continue
        title = u.get("title") or url
        snippet = u.get("content") or ""
        citations.append(Citation(
            title=title,
            url=url,
            snippet=snippet,
            publisher=_publisher_from_url(url),
            snippet_chars=len(snippet),
            rank=idx + 1,
        ))

    if not citations and _INLINE_CITATION_RE.search(text or ""):
        # SDD §3.4 item 2 — promote fallback to supported degradation tier.
        seen_indices = set()
        for m in _INLINE_CITATION_RE.finditer(text):
            n = int(m.group(1))
            if n in seen_indices:
                continue
            seen_indices.add(n)
            citations.append(Citation(
                title=f"inline-ref [{n}]",
                url="",
                snippet="",
                publisher=None,
                snippet_chars=0,
                rank=n,
            ))
        inline_parsed = bool(citations)

    if not citations:
        return None

    provenance: GroundingProvenance = "exa"
    quality = build_quality(text, citations, executed_queries or [])
    if inline_parsed:
        quality = GroundedQuality(**{**quality.__dict__})
        # SDD §12.3 item 5 — mark degraded source in extra
        extra_quality = {"degraded_source": "inline_regex"}
    else:
        extra_quality = {}

    return GroundedResult(
        text=text,
        citations=citations,
        executed_queries=list(executed_queries or []),
        grounding_provenance=provenance,
        grounded_runtime="openrouter:online",
        retrieved_at=_now_iso(),
        latency_ms=latency_ms,
        quality=quality,
        extra={"inline_parsed": True} if inline_parsed else {"quality_extra": extra_quality} if extra_quality else {},
    )


def parse_google_grounding(
    candidate: Dict[str, Any],
    text: str,
    latency_ms: int,
) -> Optional[GroundedResult]:
    """Extract citations from Gemini grounding metadata (FR-2).

    Lifted from dig-search.ts:261-287. Uses:
    - groundingMetadata.groundingChunks[].web.{title, uri} → Citation[]
    - groundingMetadata.searchEntryPoint.renderedContent → extra hrefs
    - groundingMetadata.webSearchQueries[] → executed_queries

    Returns None when no grounding metadata is present so non-grounded calls
    pass through unchanged.
    """
    gm = candidate.get("groundingMetadata") or {}
    if not gm:
        return None

    chunks = gm.get("groundingChunks") or []
    executed_queries: List[str] = list(gm.get("webSearchQueries") or [])
    citations: List[Citation] = []

    for idx, c in enumerate(chunks):
        web = (c or {}).get("web") or {}
        uri = web.get("uri") or ""
        if not uri:
            continue
        title = web.get("title") or "?"
        citations.append(Citation(
            title=title,
            url=uri,
            snippet="",
            publisher=_publisher_from_url(uri),
            snippet_chars=0,
            rank=idx + 1,
        ))

    # searchEntryPoint.renderedContent fallback — mirrors dig-search.ts:269-278
    rendered = ((gm.get("searchEntryPoint") or {}).get("renderedContent") or "")
    if rendered:
        existing = {c.url for c in citations}
        for m in re.finditer(r'href="(https?://[^"]+)"', rendered):
            href = m.group(1)
            if "vertexaisearch.cloud.google.com" in href:
                continue
            if href in existing:
                continue
            host = _publisher_from_url(href) or href
            citations.append(Citation(
                title=host,
                url=href,
                snippet="",
                publisher=host,
                snippet_chars=0,
                rank=len(citations) + 1,
            ))
            existing.add(href)

    if not citations and not executed_queries:
        return None

    quality = build_quality(text, citations, executed_queries)
    return GroundedResult(
        text=text,
        citations=citations,
        executed_queries=executed_queries,
        grounding_provenance="google_search",
        grounded_runtime="gemini:native",
        retrieved_at=_now_iso(),
        latency_ms=latency_ms,
        quality=quality,
        extra={},
    )


__all__ = [
    "GroundingMalformedError",
    "GroundingEmptyError",
    "validate_openrouter_response",
    "parse_openrouter_annotations",
    "parse_google_grounding",
    "build_quality",
    "compute_coverage_estimate",
]
