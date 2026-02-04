#!/usr/bin/env python3
"""
Trace Analyzer CLI - Entry point for trace-based feedback routing.

Usage:
    python3 -m trace_analyzer --help
    python3 -m trace_analyzer --feedback "The commit skill failed" --trajectory path/to/trajectory.jsonl
    python3 -m trace_analyzer --feedback "Missing feature X" --session-id abc123
"""

import argparse
import json
import sys
import time
from pathlib import Path
from typing import Any

# Version info
__version__ = "1.0.0"


def get_fallback_result(
    error: str | None = None,
    timeout: bool = False,
    timeout_at_stage: str | None = None,
) -> dict[str, Any]:
    """Return fallback JSON when analysis cannot complete."""
    return {
        "category": "unknown",
        "confidence": 0,
        "error": error,
        "timeout": timeout,
        "timeout_at_stage": timeout_at_stage,
        "partial_results": {},
        "version": __version__,
    }


def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        prog="trace_analyzer",
        description="Analyze execution trajectory to route feedback",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 -m trace_analyzer --feedback "The commit skill failed"
  python3 -m trace_analyzer --feedback "Need feature X" --session-id abc123
  python3 -m trace_analyzer --feedback "Bug in review" --time-window 48
        """,
    )

    parser.add_argument(
        "--version",
        action="version",
        version=f"%(prog)s {__version__}",
    )

    parser.add_argument(
        "--feedback",
        "-f",
        type=str,
        required=True,
        help="The feedback text to analyze",
    )

    parser.add_argument(
        "--trajectory",
        "-t",
        type=str,
        default=None,
        help="Path to trajectory JSONL file (auto-discovered if not specified)",
    )

    parser.add_argument(
        "--session-id",
        "-s",
        type=str,
        default=None,
        help="Filter by specific session ID",
    )

    parser.add_argument(
        "--time-window",
        "-w",
        type=int,
        default=24,
        help="Hours of history to analyze (default: 24)",
    )

    parser.add_argument(
        "--timeout",
        type=float,
        default=5.0,
        help="Maximum processing time in seconds (default: 5.0)",
    )

    parser.add_argument(
        "--json",
        action="store_true",
        default=True,
        help="Output JSON (default)",
    )

    parser.add_argument(
        "--pretty",
        action="store_true",
        help="Pretty-print JSON output",
    )

    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate inputs without running analysis",
    )

    args = parser.parse_args()

    # Dry run validation
    if args.dry_run:
        result = {
            "dry_run": True,
            "feedback_length": len(args.feedback),
            "trajectory": args.trajectory,
            "session_id": args.session_id,
            "time_window": args.time_window,
            "timeout": args.timeout,
            "version": __version__,
        }
        print(json.dumps(result, indent=2 if args.pretty else None))
        return 0

    # Import here to fail fast if dependencies missing
    try:
        from .orchestrator import run_analysis
    except ImportError as e:
        result = get_fallback_result(error=f"Import error: {e}")
        print(json.dumps(result, indent=2 if args.pretty else None))
        return 1

    # Run analysis
    start_time = time.time()
    try:
        result = run_analysis(
            feedback_text=args.feedback,
            trajectory_path=args.trajectory,
            session_id=args.session_id,
            time_window_hours=args.time_window,
            timeout_seconds=args.timeout,
        )
        result["processing_time_ms"] = int((time.time() - start_time) * 1000)
        result["version"] = __version__
    except TimeoutError as e:
        elapsed_ms = int((time.time() - start_time) * 1000)
        result = get_fallback_result(
            timeout=True,
            timeout_at_stage=str(e) if str(e) else "unknown",
        )
        result["processing_time_ms"] = elapsed_ms
    except Exception as e:
        elapsed_ms = int((time.time() - start_time) * 1000)
        result = get_fallback_result(error=str(e))
        result["processing_time_ms"] = elapsed_ms

    # Output
    print(json.dumps(result, indent=2 if args.pretty else None))
    return 0 if result.get("confidence", 0) > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
