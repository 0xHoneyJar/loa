"""
Fault Classifier - Categorize feedback into actionable fault types.

Categories (in tie-break precedence order):
1. skill_bug - Direct evidence of skill malfunction
2. skill_gap - Missing capability in existing skill
3. missing_skill - Need for entirely new skill
4. runtime_bug - Environment/infrastructure issues

Uses calibrated confidence scoring with session confidence adjustment.
"""

from __future__ import annotations

import logging
import re
from typing import Any

from .models import (
    FaultCategory,
    ClassifierOutput,
    MatcherOutput,
    ParseResult,
    TrajectoryEntry,
)

logger = logging.getLogger(__name__)

# Tie-break precedence order (highest priority first)
PRECEDENCE_ORDER = [
    FaultCategory.SKILL_BUG,
    FaultCategory.SKILL_GAP,
    FaultCategory.MISSING_SKILL,
    FaultCategory.RUNTIME_BUG,
]

# Session confidence adjustments
SESSION_CONFIDENCE_ADJUSTMENTS = {
    "high": 10,
    "medium": 0,
    "low": -15,
}

# Signal patterns for each category
SKILL_BUG_SIGNALS = [
    r"\b(error|failed|crash|exception|bug|broken|wrong)\b",
    r"\b(doesn't work|didn't work|not working|stopped working)\b",
    r"\b(skill|command).*(failed|error|broken)\b",
]

SKILL_GAP_SIGNALS = [
    r"\b(should|could|would).*(also|additionally|better)\b",
    r"\b(missing|lacks|needs).*(feature|option|capability)\b",
    r"\b(enhance|improve|extend)\b",
    r"\b(doesn't support|can't handle|unable to)\b",
]

MISSING_SKILL_SIGNALS = [
    r"\b(need|want|wish).*(new|different).*(skill|command|feature)\b",
    r"\b(no (skill|command) for)\b",
    r"\b(add|create|implement).*(skill|command)\b",
    r"\bnew (skill|command|feature)\b",
]

RUNTIME_BUG_SIGNALS = [
    r"\b(timeout|slow|hang|freeze)\b",
    r"\b(permission|access).*(denied|error)\b",
    r"\b(network|connection|api).*(error|failed)\b",
    r"\b(environment|config|setup).*(issue|problem|error)\b",
    r"\b(memory|disk|resource)\b",
]


class FaultClassifier:
    """
    Classify feedback into fault categories with calibrated confidence.

    Uses deterministic tie-breaking based on precedence order.
    """

    def __init__(self):
        # Compile regex patterns
        self._skill_bug_patterns = [re.compile(p, re.IGNORECASE) for p in SKILL_BUG_SIGNALS]
        self._skill_gap_patterns = [re.compile(p, re.IGNORECASE) for p in SKILL_GAP_SIGNALS]
        self._missing_skill_patterns = [re.compile(p, re.IGNORECASE) for p in MISSING_SKILL_SIGNALS]
        self._runtime_bug_patterns = [re.compile(p, re.IGNORECASE) for p in RUNTIME_BUG_SIGNALS]

    def classify(
        self,
        feedback_text: str,
        parse_result: ParseResult,
        matcher_output: MatcherOutput,
    ) -> ClassifierOutput:
        """
        Classify feedback into a fault category.

        Args:
            feedback_text: The user's feedback text
            parse_result: Result from trajectory parsing
            matcher_output: Result from hybrid matching

        Returns:
            ClassifierOutput with category and confidence
        """
        # Calculate raw scores for each category
        scores: dict[str, float] = {
            FaultCategory.SKILL_BUG.value: self._score_skill_bug(
                feedback_text, parse_result, matcher_output
            ),
            FaultCategory.SKILL_GAP.value: self._score_skill_gap(
                feedback_text, parse_result, matcher_output
            ),
            FaultCategory.MISSING_SKILL.value: self._score_missing_skill(
                feedback_text, parse_result, matcher_output
            ),
            FaultCategory.RUNTIME_BUG.value: self._score_runtime_bug(
                feedback_text, parse_result, matcher_output
            ),
        }

        # Collect detected signals for rationale
        signals_detected = self._collect_signals(feedback_text)

        # Find category with highest score
        max_score = max(scores.values())

        if max_score == 0:
            return ClassifierOutput(
                category=FaultCategory.UNKNOWN,
                confidence=0,
                raw_scores=scores,
                signals_detected=signals_detected,
                rationale="No signals detected in feedback text",
            )

        # Find all categories with max score (potential tie)
        max_categories = [
            cat for cat, score in scores.items()
            if score == max_score
        ]

        # Apply deterministic tie-break if needed
        tie_broken = len(max_categories) > 1
        tie_break_reason = None
        tie_break_scores = None

        if tie_broken:
            # Use precedence order for tie-breaking
            for precedence_cat in PRECEDENCE_ORDER:
                if precedence_cat.value in max_categories:
                    winning_category = precedence_cat
                    tie_break_reason = f"Precedence: {precedence_cat.value} > {[c for c in max_categories if c != precedence_cat.value]}"
                    tie_break_scores = {c: scores[c] for c in max_categories}
                    break
            else:
                winning_category = FaultCategory(max_categories[0])
        else:
            winning_category = FaultCategory(max_categories[0])

        # Calculate confidence with session adjustment
        base_confidence = min(100, int(max_score * 100))
        session_confidence = parse_result.session_info.confidence
        if isinstance(session_confidence, str):
            adjustment = SESSION_CONFIDENCE_ADJUSTMENTS.get(session_confidence, 0)
        else:
            adjustment = SESSION_CONFIDENCE_ADJUSTMENTS.get(session_confidence.value, 0)

        final_confidence = max(0, min(100, base_confidence + adjustment))

        # Build rationale
        rationale = self._build_rationale(
            winning_category,
            scores,
            signals_detected,
            session_confidence,
            adjustment,
        )

        return ClassifierOutput(
            category=winning_category,
            confidence=final_confidence,
            raw_scores=scores,
            signals_detected=signals_detected,
            tie_broken=tie_broken,
            tie_break_reason=tie_break_reason,
            tie_break_scores=tie_break_scores,
            rationale=rationale,
        )

    def _score_skill_bug(
        self,
        feedback_text: str,
        parse_result: ParseResult,
        matcher_output: MatcherOutput,
    ) -> float:
        """Score likelihood of skill_bug category."""
        score = 0.0

        # Text signal matching
        for pattern in self._skill_bug_patterns:
            if pattern.search(feedback_text):
                score += 0.3

        # Recent errors in trajectory
        error_entries = [
            e for e in parse_result.entries
            if e.error_message or e.error_type
        ]
        if error_entries:
            score += 0.3 * min(1.0, len(error_entries) / 5)

        # Skill invocations with errors
        skill_errors = [
            e for e in parse_result.entries
            if e.skill and e.skill.error_message
        ]
        if skill_errors:
            score += 0.4

        # Matched skills in ontology
        if matcher_output.matched_skills:
            score += 0.2

        return min(1.0, score)

    def _score_skill_gap(
        self,
        feedback_text: str,
        parse_result: ParseResult,
        matcher_output: MatcherOutput,
    ) -> float:
        """Score likelihood of skill_gap category."""
        score = 0.0

        # Text signal matching
        for pattern in self._skill_gap_patterns:
            if pattern.search(feedback_text):
                score += 0.3

        # Recent successful skill usage (skill exists but lacks feature)
        successful_skills = [
            e for e in parse_result.entries
            if e.skill and e.skill.success
        ]
        if successful_skills:
            score += 0.2

        # Matched skills suggest enhancement to existing
        if matcher_output.matched_skills:
            score += 0.3

        return min(1.0, score)

    def _score_missing_skill(
        self,
        feedback_text: str,
        parse_result: ParseResult,
        matcher_output: MatcherOutput,
    ) -> float:
        """Score likelihood of missing_skill category."""
        score = 0.0

        # Text signal matching
        for pattern in self._missing_skill_patterns:
            if pattern.search(feedback_text):
                score += 0.4

        # No matched skills (suggesting new capability needed)
        if not matcher_output.matched_skills:
            score += 0.3

        # Domain match but no skill (domain exists, skill doesn't)
        if matcher_output.matched_domains and not matcher_output.matched_skills:
            score += 0.3

        return min(1.0, score)

    def _score_runtime_bug(
        self,
        feedback_text: str,
        parse_result: ParseResult,
        matcher_output: MatcherOutput,
    ) -> float:
        """Score likelihood of runtime_bug category."""
        score = 0.0

        # Text signal matching
        for pattern in self._runtime_bug_patterns:
            if pattern.search(feedback_text):
                score += 0.3

        # Timeout or system errors in trajectory
        runtime_errors = [
            e for e in parse_result.entries
            if e.error_type and any(
                term in e.error_type.lower()
                for term in ["timeout", "permission", "network", "resource"]
            )
        ]
        if runtime_errors:
            score += 0.4

        return min(1.0, score)

    def _collect_signals(self, feedback_text: str) -> list[str]:
        """Collect all detected signals from feedback text."""
        signals = []

        for pattern in self._skill_bug_patterns:
            match = pattern.search(feedback_text)
            if match:
                signals.append(f"skill_bug: {match.group()}")

        for pattern in self._skill_gap_patterns:
            match = pattern.search(feedback_text)
            if match:
                signals.append(f"skill_gap: {match.group()}")

        for pattern in self._missing_skill_patterns:
            match = pattern.search(feedback_text)
            if match:
                signals.append(f"missing_skill: {match.group()}")

        for pattern in self._runtime_bug_patterns:
            match = pattern.search(feedback_text)
            if match:
                signals.append(f"runtime_bug: {match.group()}")

        return signals

    def _build_rationale(
        self,
        category: FaultCategory,
        scores: dict[str, float],
        signals: list[str],
        session_confidence: str,
        adjustment: int,
    ) -> str:
        """Build human-readable rationale for classification."""
        parts = [
            f"Category: {category.value}",
            f"Scores: {', '.join(f'{k}={v:.2f}' for k, v in scores.items())}",
        ]

        if signals:
            parts.append(f"Signals: {', '.join(signals[:5])}")

        if adjustment != 0:
            parts.append(f"Session adjustment: {adjustment:+d} ({session_confidence})")

        return "; ".join(parts)
