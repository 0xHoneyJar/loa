"""cycle-103 sprint-2 T2.1 — deterministic prompt builder for KF-002 layer 2 replay.

Reads `seed.md`, pads to target token count via repeated section markers,
returns a single prompt string. The same `(target_tokens, salt)` pair
always yields the same prompt — required for IMP-008 (corpus stability
across re-runs).

Used by:
- `tests/replay/test_opus_empty_content_thresholds.py` (live replay)
- `tests/replay/test_classifier.py` (offline classifier tests via
  controlled prompt sizes)
"""

from __future__ import annotations

from pathlib import Path
from typing import Iterator


# Char-to-token estimation. Anthropic + OpenAI both average ~3.5-4 chars
# per token for English technical text. We use 4 conservatively — slight
# under-target is acceptable, slight over-target is not (would skew the
# threshold characterization).
_CHARS_PER_TOKEN = 4

# Where the seed lives, relative to this file.
_SEED_PATH = Path(__file__).resolve().parent / "seed.md"


def _read_seed() -> str:
    """Return the seed text. Cached at module load is unnecessary —
    pytest re-imports per test session and the file is small."""
    return _SEED_PATH.read_text(encoding="utf-8")


def estimate_tokens(text: str) -> int:
    """Rough token-count estimate. Matches what cheval's
    `loa_cheval.providers.base.estimate_tokens` uses for input-gate checks
    (char-count / 4). Not exact — but the replay only needs the threshold
    region (30K-80K), so a 5-10% estimation error is acceptable."""
    return max(1, len(text) // _CHARS_PER_TOKEN)


def build_prompt(target_tokens: int, salt: int = 0) -> str:
    """Construct a replay prompt at approximately `target_tokens` tokens.

    Args:
      target_tokens: target input size (e.g., 30_000, 40_000, ...).
      salt: integer suffix appended to the prompt prefix so multiple
        trials at the same size get distinct prompts. Default 0 yields
        the canonical prompt; trial-2 uses salt=1, etc.

    Returns:
      A prompt string whose `estimate_tokens(...)` is within ±5% of
      `target_tokens`. Deterministic for a given `(target_tokens, salt)`.
    """
    if target_tokens <= 0:
        raise ValueError(f"target_tokens must be positive, got {target_tokens}")
    if salt < 0:
        raise ValueError(f"salt must be non-negative, got {salt}")

    seed = _read_seed()
    seed_tokens = estimate_tokens(seed)

    # How many seed repetitions fit?
    # We subtract a small overhead for the prefix + section markers + suffix
    # (~200 tokens total).
    overhead = 200
    payload_tokens = max(target_tokens - overhead, seed_tokens)
    reps = max(1, payload_tokens // seed_tokens)

    parts: list[str] = []
    parts.append(f"## Replay trial — target {target_tokens} tokens (salt={salt})\n\n")
    for i in range(1, reps + 1):
        parts.append(f"\n\n## Section {i} of {reps}\n\n")
        parts.append(seed)
    parts.append(
        "\n\n## Instruction\n\n"
        "Summarize the architectural shifts described above in <=500 tokens. "
        "Mention `cycle-103`, the M1/M2/M3 invariants, and the cheval "
        "delegate role. Output a concise paragraph; no markdown headers."
    )

    return "".join(parts)


def build_corpus() -> Iterator[tuple[int, int, str]]:
    """Yield `(target_tokens, salt, prompt)` triples for every cell of the
    Sprint 2 replay matrix: 5 input sizes × 5 salts = 25 prompts.

    AC-2.1 requires n>=5 trials per input size; this matches.
    """
    sizes = [30_000, 40_000, 50_000, 60_000, 80_000]
    for size in sizes:
        for salt in range(5):
            yield size, salt, build_prompt(size, salt)


if __name__ == "__main__":
    # Smoke check — print one prompt's metadata to stderr if invoked
    # directly. Used by the bats wrapper to verify the generator works
    # before kicking off the live replay.
    import sys

    for size in (30_000, 40_000, 50_000, 60_000, 80_000):
        prompt = build_prompt(size)
        actual = estimate_tokens(prompt)
        delta_pct = (actual - size) * 100 // size
        print(
            f"size={size} actual={actual} delta={delta_pct}% "
            f"chars={len(prompt)}",
            file=sys.stderr,
        )
