"""logq — filter structured log lines."""
from .records import Record, parse_line

__all__ = ["Record", "parse_line"]
