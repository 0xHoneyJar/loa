"""Token estimation benchmark: Python with type hints and docstrings."""

from typing import Dict, List, Optional
import json
import logging

logger = logging.getLogger(__name__)


class ReviewResult:
    """Represents the result of a code review."""

    def __init__(self, verdict: str, findings: List[Dict], summary: str = ""):
        self.verdict = verdict
        self.findings = findings
        self.summary = summary

    def is_approved(self) -> bool:
        return self.verdict == "APPROVED"

    def to_json(self) -> str:
        return json.dumps({
            "verdict": self.verdict,
            "findings": self.findings,
            "summary": self.summary,
        })

    @classmethod
    def from_json(cls, data: str) -> "ReviewResult":
        parsed = json.loads(data)
        return cls(
            verdict=parsed.get("verdict", "UNKNOWN"),
            findings=parsed.get("findings", []),
            summary=parsed.get("summary", ""),
        )


def validate_verdict(verdict: str) -> bool:
    """Check if verdict is in the allowed enum."""
    allowed = {"APPROVED", "CHANGES_REQUIRED", "DECISION_NEEDED", "SKIPPED"}
    return verdict in allowed


def merge_findings(results: List[ReviewResult]) -> ReviewResult:
    """Merge multiple review results into a single result."""
    all_findings = []
    for r in results:
        all_findings.extend(r.findings)
    worst = "APPROVED"
    for r in results:
        if r.verdict == "CHANGES_REQUIRED":
            worst = "CHANGES_REQUIRED"
            break
    return ReviewResult(verdict=worst, findings=all_findings)
