"""Request planning primitives.

The planner's settings live in ``SETTINGS``; ``configure()`` changes them and
every function below reads them.
"""
from urllib.parse import quote

SETTINGS = {"base_url": "", "timeout": 10.0, "retries": 2, "backoff": 0.5}


def configure(**values) -> None:
    """Change the planner settings (only the known keys; checked)."""
    unknown = sorted(set(values) - set(SETTINGS))
    if unknown:
        raise ValueError(f"unknown setting(s): {', '.join(unknown)}")
    merged = {**SETTINGS, **values}
    if not str(merged["base_url"]).startswith(("http://", "https://")):
        raise ValueError("base_url must start with http:// or https://")
    if merged["timeout"] <= 0:
        raise ValueError("timeout must be positive")
    if merged["retries"] < 0:
        raise ValueError("retries must not be negative")
    if merged["backoff"] < 0:
        raise ValueError("backoff must not be negative")
    SETTINGS.update(merged)


def build_url(path: str) -> str:
    """The absolute URL for ``path`` under the base URL (the path is percent-encoded)."""
    base = SETTINGS["base_url"].rstrip("/")
    return f"{base}/{quote(path.lstrip('/'), safe='/')}"


def backoff_delays() -> list:
    """Seconds to wait before each retry: backoff, 2*backoff, 4*backoff, ..."""
    return [SETTINGS["backoff"] * (2 ** i) for i in range(SETTINGS["retries"])]


def should_retry(attempt: int, status: int) -> bool:
    """Whether a response ``status`` on the zero-based ``attempt`` is retried."""
    return attempt < SETTINGS["retries"] and (status >= 500 or status == 429)


def request_plan(path: str) -> dict:
    return {"url": build_url(path), "timeout": SETTINGS["timeout"], "delays": backoff_delays()}
