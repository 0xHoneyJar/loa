"""
Privacy Redactor - Default-deny PII redaction.

Uses a default-deny strategy: unknown fields are hashed, only allowlisted fields pass through.
Applies redaction BEFORE any output to prevent PII leakage.
"""

from __future__ import annotations

import hashlib
import logging
import re
from typing import Any

from .models import TraceAnalysisResult, SAFE_OUTPUT_FIELDS, PII_RISK_FIELDS

logger = logging.getLogger(__name__)

# =============================================================================
# PII Detection Patterns
# =============================================================================

# JWT tokens: header.payload.signature (base64url encoded)
JWT_PATTERN = re.compile(
    r'eyJ[A-Za-z0-9_-]*\.eyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]*'
)

# UUID tokens
UUID_PATTERN = re.compile(
    r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
)

# API keys / bearer tokens (generic patterns)
API_KEY_PATTERNS = [
    re.compile(r'(?:api[_-]?key|apikey|token|bearer|auth)[=:\s]+["\']?([A-Za-z0-9_\-\.]{20,})["\']?', re.IGNORECASE),
    re.compile(r'sk-[A-Za-z0-9]{20,}'),  # OpenAI style
    re.compile(r'ghp_[A-Za-z0-9]{36}'),  # GitHub PAT
    re.compile(r'gho_[A-Za-z0-9]{36}'),  # GitHub OAuth
    re.compile(r'github_pat_[A-Za-z0-9_]{22,}'),  # GitHub fine-grained PAT
    re.compile(r'xox[baprs]-[A-Za-z0-9-]+'),  # Slack tokens
    re.compile(r'AKIA[0-9A-Z]{16}'),  # AWS access key
    # Google Cloud API keys (AIza prefix)
    re.compile(r'AIza[A-Za-z0-9_-]{35}'),
    # Azure connection strings
    re.compile(r'DefaultEndpointsProtocol=https?;[^\s;]+AccountKey=[^\s;]+', re.IGNORECASE),
    re.compile(r'AccountKey=[A-Za-z0-9+/=]{44,}'),  # Azure storage account key
    # Anthropic API keys
    re.compile(r'sk-ant-[A-Za-z0-9_-]{20,}'),
]

# PEM private key patterns (multi-line aware)
PEM_KEY_PATTERNS = [
    re.compile(r'-----BEGIN (?:RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----[\s\S]*?-----END (?:RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----'),
    re.compile(r'-----BEGIN ENCRYPTED PRIVATE KEY-----[\s\S]*?-----END ENCRYPTED PRIVATE KEY-----'),
]

# Email pattern (RFC 5322 simplified)
EMAIL_PATTERN = re.compile(
    r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'
)

# URLs with potential auth tokens
URL_WITH_AUTH_PATTERN = re.compile(
    r'https?://[^\s]*(?:token|key|auth|api_key|apikey|secret|password|pwd)[=][^\s&]*',
    re.IGNORECASE
)

# File paths (absolute paths that might expose system structure)
ABSOLUTE_PATH_PATTERN = re.compile(
    r'(?:/(?:home|Users|var|etc|tmp|opt|usr)/[^\s:]+)|(?:[A-Z]:\\[^\s:]+)',
)

# Stack trace patterns
STACK_TRACE_PATTERNS = [
    re.compile(r'File "[^"]+", line \d+'),
    re.compile(r'at [^\s]+\([^\)]+:\d+:\d+\)'),
    re.compile(r'^\s+at\s+', re.MULTILINE),
]


class PrivacyRedactor:
    """
    Default-deny privacy redactor for trace analysis output.

    Strategy:
    - Unknown fields are hashed or dropped
    - Only allowlisted fields pass through unchanged
    - PII patterns are detected and redacted
    """

    def __init__(
        self,
        workspace_root: str = ".",
        hash_salt: str = "loa-trace-redactor",
    ):
        self.workspace_root = workspace_root
        self.hash_salt = hash_salt
        self._redacted_fields: list[str] = []

    def redact_trace_output(
        self,
        result: TraceAnalysisResult,
    ) -> TraceAnalysisResult:
        """
        Apply redaction to the complete trace analysis result.

        This must be called BEFORE any output.

        Args:
            result: The analysis result to redact

        Returns:
            Redacted result with tracking
        """
        self._redacted_fields = []

        # Redact PII-risk fields
        if result.recent_errors:
            result.recent_errors = [
                self._redact_text(e, "recent_errors")
                for e in result.recent_errors
            ]

        # Redact partial results
        if result.partial_results:
            result.partial_results = self._redact_dict(
                result.partial_results, "partial_results"
            )

        # Update redaction tracking
        result.redaction_applied = bool(self._redacted_fields)
        result.redaction_fields = list(set(self._redacted_fields))

        return result

    def redact_text(self, text: str) -> str:
        """Redact PII patterns from text."""
        return self._redact_text(text, "text")

    def _redact_text(self, text: str, field_name: str) -> str:
        """Internal text redaction with field tracking."""
        if not text:
            return text

        original = text

        # PEM private keys (check first, multi-line patterns)
        for pattern in PEM_KEY_PATTERNS:
            text = pattern.sub("[REDACTED:PRIVATE_KEY]", text)

        # JWT tokens
        text = JWT_PATTERN.sub("[REDACTED:JWT]", text)

        # UUIDs (may be session IDs, but safer to redact in error messages)
        text = UUID_PATTERN.sub("[REDACTED:UUID]", text)

        # API keys (includes Google Cloud, Azure, Anthropic)
        for pattern in API_KEY_PATTERNS:
            text = pattern.sub("[REDACTED:API_KEY]", text)

        # Emails
        text = EMAIL_PATTERN.sub("[REDACTED:EMAIL]", text)

        # URLs with auth
        text = URL_WITH_AUTH_PATTERN.sub("[REDACTED:URL_WITH_AUTH]", text)

        # File paths - convert to workspace-relative or hash
        text = self._redact_paths(text)

        # Stack traces
        for pattern in STACK_TRACE_PATTERNS:
            if pattern.search(text):
                text = pattern.sub("[REDACTED:STACK_TRACE]", text)

        if text != original:
            self._redacted_fields.append(field_name)

        return text

    def _redact_paths(self, text: str) -> str:
        """Redact or relativize file paths."""
        def replace_path(match: re.Match) -> str:
            path = match.group(0)

            # If path is within workspace, make it relative
            if path.startswith(self.workspace_root):
                return path[len(self.workspace_root):].lstrip("/\\")

            # Otherwise, hash it
            return f"[PATH:{self._hash_value(path)[:8]}]"

        return ABSOLUTE_PATH_PATTERN.sub(replace_path, text)

    def _redact_dict(
        self,
        data: dict[str, Any],
        parent_field: str,
    ) -> dict[str, Any]:
        """Redact PII from dictionary values."""
        result = {}

        for key, value in data.items():
            full_key = f"{parent_field}.{key}"

            if isinstance(value, str):
                result[key] = self._redact_text(value, full_key)
            elif isinstance(value, dict):
                result[key] = self._redact_dict(value, full_key)
            elif isinstance(value, list):
                result[key] = [
                    self._redact_text(str(v), full_key) if isinstance(v, str)
                    else self._redact_dict(v, full_key) if isinstance(v, dict)
                    else v
                    for v in value
                ]
            else:
                result[key] = value

        return result

    def _hash_value(self, value: str) -> str:
        """Create a deterministic hash of a value."""
        salted = f"{self.hash_salt}:{value}"
        return hashlib.sha256(salted.encode()).hexdigest()

    def redact_entry_for_output(
        self,
        entry: dict[str, Any],
    ) -> dict[str, Any]:
        """
        Redact a trajectory entry for safe inclusion in output.

        Uses default-deny: only safe fields pass through.
        """
        safe_entry = {}

        for key, value in entry.items():
            if key in SAFE_OUTPUT_FIELDS:
                safe_entry[key] = value
            elif key in PII_RISK_FIELDS:
                if isinstance(value, str):
                    safe_entry[key] = self._redact_text(value, key)
                else:
                    safe_entry[key] = "[REDACTED]"
            else:
                # Unknown field - hash the key to indicate it was present
                safe_entry[f"_redacted_{self._hash_value(key)[:6]}"] = True

        return safe_entry


def create_redactor(workspace_root: str = ".") -> PrivacyRedactor:
    """Factory function to create a configured redactor."""
    return PrivacyRedactor(workspace_root=workspace_root)
