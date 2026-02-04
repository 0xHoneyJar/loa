"""
Orchestrator - Main analysis pipeline coordinating all components.

Pipeline: Parser → Matcher → Classifier → Redactor → Output
"""

from __future__ import annotations

import logging
import time
from pathlib import Path
from typing import Any

from .models import (
    TraceAnalysisResult,
    FaultCategory,
    ParseResult,
    SessionInfo,
)
from .parser import TrajectoryParser, discover_trajectory_path
from .matcher import HybridMatcher
from .classifier import FaultClassifier
from .redactor import PrivacyRedactor

logger = logging.getLogger(__name__)


def run_analysis(
    feedback_text: str,
    trajectory_path: str | None = None,
    session_id: str | None = None,
    time_window_hours: int = 24,
    timeout_seconds: float = 5.0,
) -> dict[str, Any]:
    """
    Run the complete trace analysis pipeline.

    Args:
        feedback_text: The user's feedback text
        trajectory_path: Path to trajectory JSONL file (auto-discovered if None)
        session_id: Optional session ID for filtering
        time_window_hours: Hours of history to analyze
        timeout_seconds: Maximum processing time

    Returns:
        Analysis result dictionary
    """
    start_time = time.time()
    partial_results: dict[str, Any] = {}

    def check_timeout(stage: str) -> None:
        """Check if timeout exceeded and raise if so."""
        elapsed = time.time() - start_time
        if elapsed > timeout_seconds:
            raise TimeoutError(stage)

    try:
        # Stage 1: Discover trajectory path if not provided
        if trajectory_path is None:
            discovered = discover_trajectory_path()
            if discovered:
                trajectory_path = str(discovered)
                logger.info(f"Auto-discovered trajectory: {trajectory_path}")
            else:
                # No trajectory - return low-confidence result
                return _build_result(
                    TraceAnalysisResult(
                        category=FaultCategory.UNKNOWN,
                        confidence=0,
                        session_confidence="low",
                        error="No trajectory file found",
                    ),
                    start_time,
                )

        check_timeout("discovery")

        # Stage 2: Parse trajectory
        parser = TrajectoryParser()
        parse_result = parser.parse(
            path=trajectory_path,
            session_id=session_id,
            time_window_hours=time_window_hours,
            timeout_seconds=timeout_seconds - (time.time() - start_time),
        )

        partial_results["parse"] = {
            "entries_found": len(parse_result.entries),
            "corrupt_lines": parse_result.corrupt_lines,
            "parser_used": parse_result.parser_used,
        }

        check_timeout("parser")

        # Stage 3: Match against ontology
        matcher = HybridMatcher()
        matcher_output = matcher.match(feedback_text)

        partial_results["matcher"] = {
            "keyword_matches": len(matcher_output.keyword_matches),
            "fuzzy_matches": len(matcher_output.fuzzy_matches),
            "embedding_matches": len(matcher_output.embedding_matches),
        }

        check_timeout("matcher")

        # Stage 4: Classify fault
        classifier = FaultClassifier()
        classifier_output = classifier.classify(
            feedback_text=feedback_text,
            parse_result=parse_result,
            matcher_output=matcher_output,
        )

        partial_results["classifier"] = {
            "category": classifier_output.category.value,
            "raw_scores": classifier_output.raw_scores,
        }

        check_timeout("classifier")

        # Stage 5: Build result
        result = TraceAnalysisResult(
            category=classifier_output.category,
            confidence=classifier_output.confidence,
            matched_skills=matcher_output.matched_skills,
            matched_domains=matcher_output.matched_domains,
            recent_skills=_extract_recent_skills(parse_result),
            recent_errors=_extract_recent_errors(parse_result),
            session_confidence=parse_result.session_info.confidence,
            entries_analyzed=len(parse_result.entries),
            dependency_missing=matcher_output.dependency_missing,
            partial_results=partial_results,
        )

        # Stage 6: Redact before output
        redactor = PrivacyRedactor()
        result = redactor.redact_trace_output(result)

        return _build_result(result, start_time)

    except TimeoutError as e:
        stage = str(e) if str(e) else "unknown"
        return _build_timeout_result(
            stage=stage,
            start_time=start_time,
            partial_results=partial_results,
        )

    except Exception as e:
        logger.exception("Analysis failed")
        return _build_error_result(
            error=str(e),
            start_time=start_time,
            partial_results=partial_results,
        )


def _build_result(
    result: TraceAnalysisResult,
    start_time: float,
) -> dict[str, Any]:
    """Convert result to dictionary for output."""
    output = result.model_dump()
    output["processing_time_ms"] = int((time.time() - start_time) * 1000)
    return output


def _build_timeout_result(
    stage: str,
    start_time: float,
    partial_results: dict[str, Any],
) -> dict[str, Any]:
    """Build result when timeout occurs."""
    return {
        "category": "unknown",
        "confidence": 0,
        "error": None,
        "timeout": True,
        "timeout_at_stage": stage,
        "partial_results": partial_results,
        "processing_time_ms": int((time.time() - start_time) * 1000),
        "version": "1.0.0",
    }


def _build_error_result(
    error: str,
    start_time: float,
    partial_results: dict[str, Any],
) -> dict[str, Any]:
    """Build result when error occurs."""
    # Redact the error message
    redactor = PrivacyRedactor()
    redacted_error = redactor.redact_text(error)

    return {
        "category": "unknown",
        "confidence": 0,
        "error": redacted_error,
        "timeout": False,
        "timeout_at_stage": None,
        "partial_results": partial_results,
        "processing_time_ms": int((time.time() - start_time) * 1000),
        "version": "1.0.0",
    }


def _extract_recent_skills(parse_result: ParseResult) -> list[str]:
    """Extract recently invoked skill names from trajectory."""
    skills = []
    for entry in parse_result.entries:
        if entry.skill and entry.skill.skill_name:
            if entry.skill.skill_name not in skills:
                skills.append(entry.skill.skill_name)
    return skills[:10]  # Limit to 10 most recent


def _extract_recent_errors(parse_result: ParseResult) -> list[str]:
    """Extract recent error messages from trajectory."""
    errors = []
    for entry in parse_result.entries:
        if entry.error_message and entry.error_message not in errors:
            errors.append(entry.error_message)
        if entry.skill and entry.skill.error_message:
            if entry.skill.error_message not in errors:
                errors.append(entry.skill.error_message)
    return errors[:5]  # Limit to 5 most recent
