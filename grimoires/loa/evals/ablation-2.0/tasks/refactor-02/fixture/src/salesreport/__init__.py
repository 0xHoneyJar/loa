"""salesreport: a plain-text sales summary from a CSV-like export."""
from .report import ReportError, build_report

__all__ = ["ReportError", "build_report"]
