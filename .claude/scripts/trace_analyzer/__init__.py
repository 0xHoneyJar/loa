"""
Trace Analyzer - Feedback trace-based routing for Loa Framework.

This module analyzes execution trajectories to automatically route feedback
to the appropriate repository and construct based on recent skill invocations.

Version: 1.0.0
"""

__version__ = "1.0.0"
__all__ = [
    "TrajectoryParser",
    "HybridMatcher",
    "FaultClassifier",
    "PrivacyRedactor",
    "analyze_trace",
]

from .parser import TrajectoryParser
from .matcher import HybridMatcher
from .classifier import FaultClassifier
from .redactor import PrivacyRedactor


def analyze_trace(
    feedback_text: str,
    trajectory_path: str | None = None,
    session_id: str | None = None,
    time_window_hours: int = 24,
    timeout_seconds: float = 5.0,
) -> dict:
    """
    Analyze feedback against recent execution trajectory.

    Args:
        feedback_text: The user's feedback text
        trajectory_path: Path to trajectory JSONL file (auto-discovered if None)
        session_id: Optional session ID for filtering
        time_window_hours: Hours of history to analyze
        timeout_seconds: Maximum processing time

    Returns:
        Analysis result dictionary with category, confidence, and context
    """
    from .orchestrator import run_analysis
    return run_analysis(
        feedback_text=feedback_text,
        trajectory_path=trajectory_path,
        session_id=session_id,
        time_window_hours=time_window_hours,
        timeout_seconds=timeout_seconds,
    )
