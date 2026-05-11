"""cycle-103 sprint-2 T2.1 — KF-002 layer-2 trial-result classifier.

Pure-function classifier. Given the raw `content` string returned by a
single Opus replay trial, decides whether the trial was:

- `empty_content` — model returned nothing visible
- `partial_content` — model returned <50 visible tokens
- `full_content` — model returned ≥50 visible tokens AND mentioned at
  least one expected keyword from the seed (cycle-103 / M1 / M2 / M3 /
  cheval). The keyword check defends against generic refusals or
  hallucinated unrelated output.

The aggregate function `classify_replay_run` applies AC-2.1's decision
rule across N trials at a given input size:

> "structural fix viable" requires ≥80% full_content at empirically-safe
> threshold across 5 trials

Returns a `ClassificationResult` with the disposition + supporting
counters. This module is offline-testable — no API calls, no I/O beyond
the input string.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Sequence


_VISIBLE_TOKEN_FULL_THRESHOLD = 50

# Per AC-2.1 + seed.md, full_content requires the model to engage with
# the seed content. Keywords drawn from the seed body. Case-insensitive
# substring match — any one is sufficient.
_FULL_CONTENT_KEYWORDS = (
    "cycle-103",
    "M1",
    "M2",
    "M3",
    "cheval",
    "delegate",
    "unification",
)

# AC-2.1 structural-fix threshold.
_STRUCTURAL_VIABILITY_RATE = 0.80


class TrialOutcome(str, Enum):
    EMPTY = "empty_content"
    PARTIAL = "partial_content"
    FULL = "full_content"


def _estimate_visible_tokens(text: str) -> int:
    """Rough visible-token estimate. Same heuristic as the corpus
    generator (chars / 4)."""
    return max(0, len(text.strip()) // 4)


def classify_trial(content: str | None) -> TrialOutcome:
    """Classify a single trial's `content` field.

    Args:
      content: the raw `content` returned by cheval. `None` or
        whitespace-only strings classify as `EMPTY`.

    Returns:
      One of `TrialOutcome.EMPTY` / `PARTIAL` / `FULL`.
    """
    if content is None:
        return TrialOutcome.EMPTY
    stripped = content.strip()
    if not stripped:
        return TrialOutcome.EMPTY

    visible_tokens = _estimate_visible_tokens(stripped)
    if visible_tokens < _VISIBLE_TOKEN_FULL_THRESHOLD:
        return TrialOutcome.PARTIAL

    # Visible-tokens above threshold — check keyword engagement.
    lower = stripped.lower()
    if any(kw.lower() in lower for kw in _FULL_CONTENT_KEYWORDS):
        return TrialOutcome.FULL

    # Long but off-topic — count as PARTIAL. The model returned text
    # but it didn't engage with the seed content; this is closer to a
    # hallucinated refusal than a successful response.
    return TrialOutcome.PARTIAL


@dataclass(frozen=True)
class ClassificationResult:
    """Aggregate disposition for a set of trials at a given input size."""

    input_tokens: int
    trial_count: int
    empty: int
    partial: int
    full: int
    full_rate: float
    structural_fix_viable: bool

    def __post_init__(self) -> None:
        if self.trial_count != self.empty + self.partial + self.full:
            raise ValueError(
                f"trial_count ({self.trial_count}) != "
                f"empty+partial+full ({self.empty}+{self.partial}+{self.full})"
            )


def classify_replay_run(
    input_tokens: int,
    outcomes: Sequence[TrialOutcome],
) -> ClassificationResult:
    """Aggregate per-trial outcomes into the AC-2.1 disposition.

    Args:
      input_tokens: the target input size for this trial cell (e.g., 30000).
      outcomes: per-trial classifications. n >= 5 expected for AC-2.1.

    Returns:
      A `ClassificationResult` with `structural_fix_viable == True` if
      and only if `full_rate >= 0.80`.

    Raises:
      ValueError: if `outcomes` is empty.
    """
    if not outcomes:
        raise ValueError("outcomes must contain at least one trial")

    empty = sum(1 for o in outcomes if o == TrialOutcome.EMPTY)
    partial = sum(1 for o in outcomes if o == TrialOutcome.PARTIAL)
    full = sum(1 for o in outcomes if o == TrialOutcome.FULL)
    trial_count = len(outcomes)
    full_rate = full / trial_count

    return ClassificationResult(
        input_tokens=input_tokens,
        trial_count=trial_count,
        empty=empty,
        partial=partial,
        full=full,
        full_rate=full_rate,
        structural_fix_viable=full_rate >= _STRUCTURAL_VIABILITY_RATE,
    )


def classify_matrix(
    results: dict[int, Sequence[TrialOutcome]],
) -> dict[int, ClassificationResult]:
    """Classify the entire replay matrix (one entry per input size).

    Args:
      results: mapping `input_tokens -> list of TrialOutcome`.

    Returns:
      `{input_tokens: ClassificationResult}` ordered by input size ascending.
    """
    return {
        size: classify_replay_run(size, outcomes)
        for size, outcomes in sorted(results.items())
    }


def find_safe_threshold(
    matrix: dict[int, ClassificationResult],
) -> int | None:
    """AC-2.1 decision: find the largest input_tokens at which
    `structural_fix_viable == True`. Returns None if no size qualifies
    (vendor-side path triggered).

    A "safe threshold" is the operational ceiling we'd encode into
    `max_input_tokens` for `claude-opus-4-7` if the structural path
    is viable.
    """
    viable = [
        result.input_tokens
        for result in matrix.values()
        if result.structural_fix_viable
    ]
    return max(viable) if viable else None
