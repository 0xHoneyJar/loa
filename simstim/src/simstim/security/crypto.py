"""Cryptographic utilities for Simstim.

Security Note (SIMSTIM-005): This module provides HMAC signing for callback
data to prevent callback injection and replay attacks.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import os
import secrets
import time
from typing import NamedTuple


# Maximum age for callback data (5 minutes)
CALLBACK_MAX_AGE_SECONDS = 300


class SignedCallbackData(NamedTuple):
    """Signed callback data with timestamp."""

    payload: str  # Original callback data
    timestamp: int  # Unix timestamp when signed
    signature: str  # HMAC signature (base64)


class CallbackSigner:
    """HMAC-based callback data signer.

    Security Features:
    - HMAC-SHA256 for tamper detection
    - Timestamp for replay attack prevention
    - URL-safe base64 encoding for Telegram compatibility
    """

    def __init__(self, secret_key: bytes | str) -> None:
        """Initialize signer with secret key.

        Args:
            secret_key: Secret key for HMAC (bytes or hex string)
        """
        if isinstance(secret_key, str):
            # Assume hex-encoded string
            secret_key = bytes.fromhex(secret_key)
        self._key = secret_key

    def sign(self, payload: str) -> str:
        """Sign callback payload with timestamp.

        Args:
            payload: Original callback data (e.g., "approve:request-123")

        Returns:
            Signed callback string in format: "payload|timestamp|signature"
        """
        timestamp = int(time.time())
        message = f"{payload}|{timestamp}"

        signature = hmac.new(
            self._key,
            message.encode(),
            hashlib.sha256,
        ).digest()

        # Use URL-safe base64 for Telegram compatibility (64 byte limit)
        sig_b64 = base64.urlsafe_b64encode(signature[:16]).decode().rstrip("=")

        return f"{payload}|{timestamp}|{sig_b64}"

    def verify(
        self,
        signed_data: str,
        max_age: int = CALLBACK_MAX_AGE_SECONDS,
    ) -> SignedCallbackData | None:
        """Verify and extract callback data.

        Args:
            signed_data: Signed callback string
            max_age: Maximum age in seconds (default 5 minutes)

        Returns:
            SignedCallbackData if valid, None if invalid or expired
        """
        try:
            parts = signed_data.rsplit("|", 2)
            if len(parts) != 3:
                return None

            payload, timestamp_str, signature = parts
            timestamp = int(timestamp_str)

            # Check timestamp freshness (replay attack prevention)
            now = int(time.time())
            if now - timestamp > max_age:
                return None
            if timestamp > now + 60:  # Clock skew tolerance
                return None

            # Recompute signature
            message = f"{payload}|{timestamp_str}"
            expected = hmac.new(
                self._key,
                message.encode(),
                hashlib.sha256,
            ).digest()

            # Decode received signature (add padding back)
            sig_padded = signature + "=" * (4 - len(signature) % 4) if len(signature) % 4 else signature
            try:
                received = base64.urlsafe_b64decode(sig_padded)
            except Exception:
                return None

            # Constant-time comparison
            if not hmac.compare_digest(expected[:16], received):
                return None

            return SignedCallbackData(
                payload=payload,
                timestamp=timestamp,
                signature=signature,
            )

        except (ValueError, TypeError):
            return None


def generate_secret_key(length: int = 32) -> str:
    """Generate a cryptographically secure secret key.

    Args:
        length: Key length in bytes (default 32 = 256 bits)

    Returns:
        Hex-encoded secret key
    """
    return secrets.token_hex(length)
