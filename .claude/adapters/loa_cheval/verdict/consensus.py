"""cycle-109 Sprint 2 T2.9 — consensus-outcome classifier per SDD §3.2.2.1
(SKP-001 v6 closure).

Sets the ``consensus_outcome`` field on a verdict_quality envelope BEFORE
``compute_verdict_status`` is called. The algorithm compares BLOCKER-class
findings across voices: if ANY voice's BLOCKER is contradicted (same
location, non-BLOCKER severity) by another voice, the outcome is
``"impossible"`` — meaning the substrate cannot agree on the safety
status of that location, which compute_verdict_status converts into
``status: FAILED``.

Inputs:
  envelope            — the multi-voice envelope (provides voices_planned,
                        voices_succeeded, voices_succeeded_ids).
  findings_per_voice  — list of finding-sets, one set per SUCCEEDED voice.
                        Each finding is a dict with at minimum a
                        ``severity`` key; ``file_path`` and
                        ``line_number_or_section`` (or ``line_number``)
                        identify the location for the cross-voice
                        comparison.

Algorithm:
  1. Trivial cases: voices_succeeded < 2 → "consensus" (cannot have
     contradiction with fewer than 2 voices).
  2. Per-finding cross-voice comparison: for each BLOCKER-severity finding
     emitted by any voice, check whether at least one other voice's
     findings cover the same (file_path, line_number) location AND
     classify it as non-BLOCKER (severity < HIGH).
  3. Contradiction threshold: ANY contradicted pair → "impossible".
  4. Edge case: BLOCKER without location field — single-voice signal,
     treated as "consensus" (absence of agreement is NOT contradiction).

Output: one of ``"consensus" | "impossible"``.

The function is pure (no I/O, no global state, no time-dependence) and
MUST NOT mutate inputs. The conformance fixtures in
``tests/fixtures/cycle-109/verdict-quality-conformance/`` rely on
deterministic output.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional


_OUTCOME_CONSENSUS = "consensus"
_OUTCOME_IMPOSSIBLE = "impossible"


# Severity ordering for the contradiction check.
# SDD §3.2.2.1: "non-BLOCKER (any severity < HIGH)" — so HIGH itself is
# NOT a contradiction (HIGH from V₂ is roughly affirmative). Only severities
# strictly below HIGH constitute contradiction: MED, LOW, INFO, etc.
_SEVERITY_RANK = {
    "BLOCKER": 4,
    "HIGH": 3,
    "MED": 2,
    "MEDIUM": 2,
    "LOW": 1,
    "INFO": 0,
}


def _severity_rank(severity: Any) -> int:
    if not isinstance(severity, str):
        return 0
    return _SEVERITY_RANK.get(severity.upper(), 0)


def _is_blocker(severity: Any) -> bool:
    return _severity_rank(severity) >= _SEVERITY_RANK["BLOCKER"]


def _is_contradiction(severity: Any) -> bool:
    """A severity counts as a contradiction iff it is strictly less than
    HIGH (per SDD §3.2.2.1 algorithm step 2)."""
    return _severity_rank(severity) < _SEVERITY_RANK["HIGH"]


def _location_key(finding: Dict[str, Any]) -> Optional[tuple]:
    """Return a hashable location key for the finding, or None when the
    finding has no location (structural-class — SDD §3.2.2.1 edge case)."""
    if not isinstance(finding, dict):
        return None
    file_path = finding.get("file_path") or finding.get("file") or finding.get("path")
    if not file_path:
        return None
    # Accept any of these location forms (defensive across BB / FL / RT
    # finding schemas which differ slightly).
    line = (
        finding.get("line_number")
        or finding.get("line_number_or_section")
        or finding.get("line")
        or finding.get("section")
    )
    return (str(file_path), str(line) if line is not None else "")


def classify_consensus(
    envelope: Dict[str, Any],
    findings_per_voice: List[List[Dict[str, Any]]],
) -> str:
    """Return ``"consensus" | "impossible"`` per SDD §3.2.2.1.

    Args:
      envelope: the multi-voice envelope (for voices_succeeded counts).
      findings_per_voice: list of finding-sets, one set per succeeded voice.
        Index ordering matches voices_succeeded_ids by convention.

    Returns:
      ``"consensus"`` when no contradictions found (or fewer than 2 voices).
      ``"impossible"`` when at least one BLOCKER from one voice is
      contradicted by a non-BLOCKER (severity < HIGH) finding at the same
      location from another voice.
    """
    voices_succeeded = int(envelope.get("voices_succeeded") or 0)
    if voices_succeeded < 2:
        return _OUTCOME_CONSENSUS

    # Build a per-voice location → severity-rank map for fast lookup.
    # voice_index → { location_key: max_severity_rank_at_that_location }
    voice_locations: List[Dict[tuple, int]] = []
    for voice_findings in findings_per_voice:
        loc_map: Dict[tuple, int] = {}
        if isinstance(voice_findings, list):
            for finding in voice_findings:
                key = _location_key(finding)
                if key is None:
                    continue
                rank = _severity_rank(finding.get("severity"))
                # Keep the MAX severity seen for this location within
                # this voice's findings — if a voice double-reports the
                # same location, the higher severity wins.
                if rank > loc_map.get(key, -1):
                    loc_map[key] = rank
        voice_locations.append(loc_map)

    # For each BLOCKER finding from voice V₁, check whether some other
    # voice V₂ reports the same location at severity < HIGH.
    for i, voice_findings in enumerate(findings_per_voice):
        if not isinstance(voice_findings, list):
            continue
        for finding in voice_findings:
            if not _is_blocker(finding.get("severity")):
                continue
            key = _location_key(finding)
            if key is None:
                # Structural BLOCKER with no location — SDD edge case 4:
                # absence of corroboration is NOT contradiction. Move on.
                continue
            for j, other_loc_map in enumerate(voice_locations):
                if j == i:
                    continue
                if key in other_loc_map:
                    other_rank = other_loc_map[key]
                    if other_rank < _SEVERITY_RANK["HIGH"]:
                        return _OUTCOME_IMPOSSIBLE

    return _OUTCOME_CONSENSUS
