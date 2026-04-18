"""Coverage estimate (IMP-002 algorithm).

SDD §3.1: "fraction of non-trivial sentences in `text` that have at least
one citation mention nearby (±2 sentences)." Normalized 0.0-1.0.

Heuristic (keep simple, deterministic, cheap to run on every parse):

1. Split text on sentence-ending punctuation → non-trivial sentences = those
   longer than MIN_SENTENCE_CHARS (default 30) after strip.
2. A sentence "has a citation mention" when any of:
   - inline `[n]` marker is present (classic Exa-style); OR
   - a citation's URL hostname substring appears; OR
   - a citation's title substring appears (case-insensitive) when long enough
     to be meaningful (> 12 chars).
3. A non-trivial sentence is "covered" if itself or any sentence within ±2 is
   a has-citation sentence.
4. coverage_estimate = covered / non_trivial. 0.0 on empty text. 1.0 when
   every non-trivial sentence is covered.
"""

from __future__ import annotations

import re
from typing import Iterable, List

from loa_cheval.types import Citation

_SENTENCE_SPLIT_RE = re.compile(r"(?<=[.!?])\s+")
_INLINE_CITATION_RE = re.compile(r"\[\d+\]")

MIN_SENTENCE_CHARS = 30
MIN_TITLE_CHARS = 12


def _split_sentences(text: str) -> List[str]:
    parts = _SENTENCE_SPLIT_RE.split(text.strip()) if text else []
    return [p.strip() for p in parts if p.strip()]


def _has_citation_mention(sentence: str, citations: List[Citation]) -> bool:
    if _INLINE_CITATION_RE.search(sentence):
        return True
    lower = sentence.lower()
    for c in citations:
        host = c.publisher or ""
        if host and host.lower() in lower:
            return True
        title = (c.title or "")
        if len(title) >= MIN_TITLE_CHARS and title.lower() in lower:
            return True
    return False


def compute_coverage_estimate(text: str, citations: List[Citation]) -> float:
    """Return a 0.0-1.0 coverage ratio (IMP-002).

    Empty text → 0.0. No non-trivial sentences → 0.0.
    """
    if not text:
        return 0.0
    sentences = _split_sentences(text)
    if not sentences:
        return 0.0

    has_cite = [
        _has_citation_mention(s, citations) for s in sentences
    ]
    non_trivial_idx = [
        i for i, s in enumerate(sentences) if len(s) >= MIN_SENTENCE_CHARS
    ]
    if not non_trivial_idx:
        return 0.0

    covered = 0
    for i in non_trivial_idx:
        lo = max(0, i - 2)
        hi = min(len(sentences), i + 3)
        if any(has_cite[j] for j in range(lo, hi)):
            covered += 1
    return round(covered / len(non_trivial_idx), 4)


__all__ = ["compute_coverage_estimate", "MIN_SENTENCE_CHARS", "MIN_TITLE_CHARS"]
