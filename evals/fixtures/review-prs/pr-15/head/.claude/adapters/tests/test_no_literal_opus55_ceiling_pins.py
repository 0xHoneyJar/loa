"""cycle-127 FR-3.4 guard (SDD D-3.4): the suites whose Opus 5.5 ceiling pins
were swept to read the catalog must not grow a literal 180K back.

The uncalibrated policy cap (`CEILING_CAP = 180_000`, the 4.x/5-family
entries' bound until a probe calibrates them) is the one literal allowed, and
it is allowed only as that named constant and in its SDD §2.1 docstring. Every
other `180000` / `180_000` / `180,000` in these files fails this test — a
literal there would turn red when the probe writes the measured Opus 5.5 bound.
"""
from __future__ import annotations

import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
LITERAL = re.compile(r"(?<![\d_,])180[_,]?000(?![\d_,])")

# file → the exact lines allowed to carry the literal (the policy cap, not the Opus 5.5 value)
SWEPT = {
    ".claude/adapters/tests/test_anthropic_catalog_floor.py": {
        "CEILING_CAP = 180_000",
        '"""SDD §2.1: ceiling = min(180000, context_window − default_max_tokens(entry)) — computed, not a constant."""',
    },
    "tests/unit/loa-status-providers.bats": set(),
}


@pytest.mark.parametrize("rel", sorted(SWEPT))
def test_no_literal_opus_5_5_ceiling_in_a_swept_suite(rel):
    path = ROOT / rel
    assert path.is_file(), rel
    offenders = [
        f"{rel}:{n}: {line.strip()}"
        for n, line in enumerate(path.read_text().splitlines(), 1)
        if LITERAL.search(line) and line.strip() not in SWEPT[rel]
    ]
    assert offenders == [], "read the catalog instead of pinning the Opus 5.5 bound:\n" + "\n".join(offenders)


def test_the_policy_cap_is_never_compared_against_the_opus_5_5_entry_directly():
    text = (ROOT / ".claude/adapters/tests/test_anthropic_catalog_floor.py").read_text()
    for line in text.splitlines():
        if "CEILING_CAP" in line and "claude-opus-5-5" in line:
            pytest.fail(f"CEILING_CAP pinned against claude-opus-5-5: {line.strip()}")


@pytest.mark.parametrize("line, hit", [
    ("x == 180000", True), ("x == 180_000", True), ("probed 180,000 tokens", True),
    ("1800000000", False), ("180_000_000", False), ("1180000", False), ("18000", False),
])
def test_the_guard_pattern(line, hit):
    assert bool(LITERAL.search(line)) is hit
