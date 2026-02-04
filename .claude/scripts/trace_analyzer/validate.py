#!/usr/bin/env python3
"""
Validation Runner - Run classifier against validation dataset.

Calculates accuracy, precision, recall, and F1 scores per category.
"""

import argparse
import json
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from typing import Any

import yaml

from .classifier import FaultClassifier
from .matcher import HybridMatcher
from .models import (
    FaultCategory,
    ParseResult,
    SessionInfo,
    TrajectoryEntry,
    SkillInvocation,
    MatcherOutput,
)


def load_validation_dataset(path: str | Path) -> list[dict]:
    """Load validation dataset from YAML."""
    path = Path(path)
    if not path.exists():
        raise FileNotFoundError(f"Validation dataset not found: {path}")

    with open(path, "r") as f:
        data = yaml.safe_load(f)

    return data.get("items", [])


def create_parse_result(trajectory_context: dict) -> ParseResult:
    """Create a ParseResult from trajectory context."""
    entries = []

    # Add recent skill entries
    for skill_name in trajectory_context.get("recent_skills", []):
        entries.append(TrajectoryEntry(
            skill=SkillInvocation(skill_name=skill_name, success=True),
        ))

    # Add recent error entries
    for error_msg in trajectory_context.get("recent_errors", []):
        entries.append(TrajectoryEntry(
            error_message=error_msg,
            error_type="Error",
        ))

    return ParseResult(
        entries=entries,
        session_info=SessionInfo(
            confidence="high" if entries else "low",
            reason="validation_test",
        ),
    )


def run_validation(
    dataset_path: str | Path,
    output_json: bool = False,
    verbose: bool = False,
) -> dict[str, Any]:
    """
    Run validation against the dataset.

    Returns metrics including accuracy, precision, recall, F1.
    """
    items = load_validation_dataset(dataset_path)

    classifier = FaultClassifier()
    matcher = HybridMatcher()

    # Track results
    results = []
    confusion_matrix: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    category_counts: dict[str, int] = defaultdict(int)
    correct_counts: dict[str, int] = defaultdict(int)
    predicted_counts: dict[str, int] = defaultdict(int)

    for item in items:
        item_id = item.get("id", "unknown")
        feedback = item.get("feedback", "")
        expected = item.get("expected_category", "unknown")
        trajectory_context = item.get("trajectory_context", {})

        # Create inputs
        parse_result = create_parse_result(trajectory_context)
        matcher_output = matcher.match(feedback)

        # Classify
        output = classifier.classify(
            feedback_text=feedback,
            parse_result=parse_result,
            matcher_output=matcher_output,
        )

        predicted = output.category.value
        correct = predicted == expected

        # Update metrics
        category_counts[expected] += 1
        predicted_counts[predicted] += 1
        confusion_matrix[expected][predicted] += 1

        if correct:
            correct_counts[expected] += 1

        results.append({
            "id": item_id,
            "feedback": feedback[:100] + "..." if len(feedback) > 100 else feedback,
            "expected": expected,
            "predicted": predicted,
            "confidence": output.confidence,
            "correct": correct,
        })

        if verbose and not correct:
            print(f"MISS: {item_id} - expected={expected}, got={predicted} (conf={output.confidence})")
            print(f"      {feedback[:80]}...")

    # Calculate metrics
    total = len(items)
    total_correct = sum(correct_counts.values())
    accuracy = total_correct / total if total > 0 else 0

    # Per-category metrics
    category_metrics = {}
    for category in ["skill_bug", "skill_gap", "missing_skill", "runtime_bug"]:
        tp = correct_counts.get(category, 0)
        fp = predicted_counts.get(category, 0) - tp
        fn = category_counts.get(category, 0) - tp

        precision = tp / (tp + fp) if (tp + fp) > 0 else 0
        recall = tp / (tp + fn) if (tp + fn) > 0 else 0
        f1 = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0

        category_metrics[category] = {
            "precision": round(precision, 3),
            "recall": round(recall, 3),
            "f1": round(f1, 3),
            "support": category_counts.get(category, 0),
            "correct": tp,
        }

    # Macro and micro F1
    macro_f1 = sum(m["f1"] for m in category_metrics.values()) / len(category_metrics)
    micro_precision = total_correct / sum(predicted_counts.values()) if sum(predicted_counts.values()) > 0 else 0
    micro_recall = total_correct / total if total > 0 else 0
    micro_f1 = 2 * micro_precision * micro_recall / (micro_precision + micro_recall) if (micro_precision + micro_recall) > 0 else 0

    return {
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "dataset": str(dataset_path),
        "total_items": total,
        "total_correct": total_correct,
        "accuracy": round(accuracy, 3),
        "accuracy_percent": round(accuracy * 100, 1),
        "macro_f1": round(macro_f1, 3),
        "micro_f1": round(micro_f1, 3),
        "category_metrics": category_metrics,
        "confusion_matrix": {k: dict(v) for k, v in confusion_matrix.items()},
        "passed_threshold": accuracy >= 0.85,
        "threshold": 0.85,
        "details": results if output_json else None,
    }


def generate_markdown_report(metrics: dict[str, Any]) -> str:
    """Generate a markdown report from metrics."""
    lines = [
        "# Trace Classifier Validation Report",
        "",
        f"**Date**: {metrics['timestamp']}",
        f"**Dataset**: {metrics['dataset']}",
        "",
        "## Summary",
        "",
        f"| Metric | Value |",
        f"|--------|-------|",
        f"| Total Items | {metrics['total_items']} |",
        f"| Correct | {metrics['total_correct']} |",
        f"| **Accuracy** | **{metrics['accuracy_percent']}%** |",
        f"| Macro F1 | {metrics['macro_f1']} |",
        f"| Micro F1 | {metrics['micro_f1']} |",
        f"| Threshold | {metrics['threshold'] * 100}% |",
        f"| **Status** | {'✅ PASS' if metrics['passed_threshold'] else '❌ FAIL'} |",
        "",
        "## Per-Category Metrics",
        "",
        "| Category | Precision | Recall | F1 | Support | Correct |",
        "|----------|-----------|--------|-----|---------|---------|",
    ]

    for category, m in metrics["category_metrics"].items():
        lines.append(
            f"| {category} | {m['precision']} | {m['recall']} | {m['f1']} | {m['support']} | {m['correct']} |"
        )

    lines.extend([
        "",
        "## Confusion Matrix",
        "",
        "```",
        "                    Predicted",
        "                    skill_bug  skill_gap  missing_skill  runtime_bug",
    ])

    categories = ["skill_bug", "skill_gap", "missing_skill", "runtime_bug"]
    cm = metrics["confusion_matrix"]

    for actual in categories:
        row = [str(cm.get(actual, {}).get(pred, 0)).rjust(10) for pred in categories]
        lines.append(f"Actual {actual.ljust(15)} {''.join(row)}")

    lines.extend([
        "```",
        "",
        "---",
        "",
        f"Generated by trace_analyzer validation runner v1.0.0",
    ])

    return "\n".join(lines)


def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        prog="trace_analyzer.validate",
        description="Run classifier validation against dataset",
    )

    parser.add_argument(
        "--dataset",
        "-d",
        type=str,
        default="grimoires/loa/a2a/trace-classifier-validation.yaml",
        help="Path to validation dataset",
    )

    parser.add_argument(
        "--json",
        action="store_true",
        help="Output JSON results",
    )

    parser.add_argument(
        "--markdown",
        "-m",
        type=str,
        help="Generate markdown report to file",
    )

    parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Show misclassified items",
    )

    parser.add_argument(
        "--fail-under",
        type=float,
        default=0.85,
        help="Fail if accuracy below threshold (default: 0.85)",
    )

    args = parser.parse_args()

    try:
        metrics = run_validation(
            dataset_path=args.dataset,
            output_json=args.json,
            verbose=args.verbose,
        )

        metrics["threshold"] = args.fail_under
        metrics["passed_threshold"] = metrics["accuracy"] >= args.fail_under

        if args.json:
            print(json.dumps(metrics, indent=2))
        else:
            print(f"\n{'='*60}")
            print(f"Trace Classifier Validation Results")
            print(f"{'='*60}\n")
            print(f"Dataset: {args.dataset}")
            print(f"Items:   {metrics['total_items']}")
            print(f"Correct: {metrics['total_correct']}")
            print(f"\nAccuracy: {metrics['accuracy_percent']}%")
            print(f"Macro F1: {metrics['macro_f1']}")
            print(f"\nPer-Category:")
            for cat, m in metrics["category_metrics"].items():
                print(f"  {cat}: P={m['precision']:.2f} R={m['recall']:.2f} F1={m['f1']:.2f}")
            print(f"\n{'='*60}")
            status = "✅ PASS" if metrics["passed_threshold"] else "❌ FAIL"
            print(f"Status: {status} (threshold: {args.fail_under * 100}%)")
            print(f"{'='*60}\n")

        if args.markdown:
            report = generate_markdown_report(metrics)
            Path(args.markdown).write_text(report)
            print(f"Report written to: {args.markdown}")

        return 0 if metrics["passed_threshold"] else 1

    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
