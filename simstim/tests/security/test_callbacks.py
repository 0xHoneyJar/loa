"""Security tests for SIMSTIM-005: Callback Data Injection.

Tests verify that:
- Callback data is HMAC-signed
- Unsigned callbacks are rejected
- Expired callbacks are rejected (replay attack prevention)
- Tampered callbacks are rejected
"""

import time
import pytest
from simstim.security.crypto import CallbackSigner, generate_secret_key, CALLBACK_MAX_AGE_SECONDS
from simstim.telegram.keyboards import (
    init_callback_signer,
    parse_callback_data,
    create_permission_keyboard,
    CallbackAction,
    get_callback_signer,
)


@pytest.fixture
def signer():
    """Create a CallbackSigner for testing."""
    key = generate_secret_key()
    return CallbackSigner(key)


@pytest.fixture
def setup_signer(signer):
    """Initialize the global signer for tests."""
    init_callback_signer(signer)
    yield signer
    # Cleanup - reset to None
    init_callback_signer(None)  # type: ignore


class TestCallbackSigner:
    """Test CallbackSigner cryptographic operations."""

    def test_sign_produces_signed_string(self, signer):
        """Test signing produces a signed string with timestamp."""
        payload = "approve:request-123"
        signed = signer.sign(payload)

        assert "|" in signed
        parts = signed.split("|")
        assert len(parts) == 3
        assert parts[0] == payload

    def test_verify_valid_signature(self, signer):
        """Test verification of valid signature."""
        payload = "approve:request-123"
        signed = signer.sign(payload)

        result = signer.verify(signed)

        assert result is not None
        assert result.payload == payload
        assert result.timestamp > 0

    def test_verify_invalid_signature_returns_none(self, signer):
        """Test that invalid signatures are rejected."""
        payload = "approve:request-123"
        signed = signer.sign(payload)

        # Tamper with signature
        parts = signed.rsplit("|", 1)
        tampered = parts[0] + "|INVALID_SIG"

        result = signer.verify(tampered)
        assert result is None

    def test_verify_tampered_payload_returns_none(self, signer):
        """Test that tampered payloads are rejected."""
        payload = "approve:request-123"
        signed = signer.sign(payload)

        # Tamper with payload
        parts = signed.split("|")
        parts[0] = "deny:request-456"  # Change action and ID
        tampered = "|".join(parts)

        result = signer.verify(tampered)
        assert result is None

    def test_verify_tampered_timestamp_returns_none(self, signer):
        """Test that tampered timestamps are rejected."""
        payload = "approve:request-123"
        signed = signer.sign(payload)

        # Tamper with timestamp
        parts = signed.split("|")
        parts[1] = str(int(parts[1]) + 1000)
        tampered = "|".join(parts)

        result = signer.verify(tampered)
        assert result is None

    def test_verify_expired_callback_returns_none(self, signer):
        """Test that expired callbacks are rejected."""
        payload = "approve:request-123"

        # Create a signed callback with old timestamp
        old_timestamp = int(time.time()) - CALLBACK_MAX_AGE_SECONDS - 100
        message = f"{payload}|{old_timestamp}"

        import hashlib
        import hmac
        import base64

        signature = hmac.new(
            signer._key,
            message.encode(),
            hashlib.sha256,
        ).digest()
        sig_b64 = base64.urlsafe_b64encode(signature[:16]).decode().rstrip("=")

        expired_signed = f"{payload}|{old_timestamp}|{sig_b64}"

        result = signer.verify(expired_signed)
        assert result is None

    def test_verify_future_timestamp_rejected(self, signer):
        """Test that callbacks with future timestamps are rejected."""
        payload = "approve:request-123"

        # Create a signed callback with future timestamp (>60s ahead)
        future_timestamp = int(time.time()) + 120
        message = f"{payload}|{future_timestamp}"

        import hashlib
        import hmac
        import base64

        signature = hmac.new(
            signer._key,
            message.encode(),
            hashlib.sha256,
        ).digest()
        sig_b64 = base64.urlsafe_b64encode(signature[:16]).decode().rstrip("=")

        future_signed = f"{payload}|{future_timestamp}|{sig_b64}"

        result = signer.verify(future_signed)
        assert result is None


class TestCallbackSignerWithDifferentKeys:
    """Test that different keys produce different signatures."""

    def test_different_keys_produce_different_signatures(self):
        """Test that different keys result in different signatures."""
        signer1 = CallbackSigner(generate_secret_key())
        signer2 = CallbackSigner(generate_secret_key())

        payload = "approve:request-123"
        signed1 = signer1.sign(payload)
        signed2 = signer2.sign(payload)

        # Payloads are the same but signatures differ
        parts1 = signed1.rsplit("|", 1)
        parts2 = signed2.rsplit("|", 1)
        assert parts1[-1] != parts2[-1]

    def test_signature_from_wrong_key_rejected(self):
        """Test that signatures from wrong key are rejected."""
        signer1 = CallbackSigner(generate_secret_key())
        signer2 = CallbackSigner(generate_secret_key())

        payload = "approve:request-123"
        signed = signer1.sign(payload)

        # Try to verify with wrong key
        result = signer2.verify(signed)
        assert result is None


class TestKeyboardIntegration:
    """Test keyboard functions with signing."""

    def test_permission_keyboard_signs_callbacks(self, setup_signer):
        """Test that permission keyboard signs callback data."""
        keyboard = create_permission_keyboard("request-123")

        buttons = keyboard.inline_keyboard[0]
        approve_data = buttons[0].callback_data
        deny_data = buttons[1].callback_data

        # Both should be signed (contain |timestamp|signature)
        assert approve_data.count("|") == 2
        assert deny_data.count("|") == 2

    def test_parse_callback_verifies_signature(self, setup_signer):
        """Test that parse_callback_data verifies signature."""
        keyboard = create_permission_keyboard("request-123")
        approve_data = keyboard.inline_keyboard[0][0].callback_data

        # Should parse successfully
        result = parse_callback_data(approve_data)
        assert result.action == CallbackAction.APPROVE
        assert result.request_id == "request-123"

    def test_parse_callback_rejects_unsigned(self, setup_signer):
        """Test that unsigned callbacks are rejected when signer is configured."""
        unsigned_data = "approve:request-123"

        with pytest.raises(ValueError, match="Invalid or expired callback signature"):
            parse_callback_data(unsigned_data)

    def test_parse_callback_rejects_tampered(self, setup_signer):
        """Test that tampered callbacks are rejected."""
        keyboard = create_permission_keyboard("request-123")
        approve_data = keyboard.inline_keyboard[0][0].callback_data

        # Tamper with the data
        parts = approve_data.split("|")
        parts[0] = "deny:request-456"
        tampered = "|".join(parts)

        with pytest.raises(ValueError, match="Invalid or expired callback signature"):
            parse_callback_data(tampered)


class TestWithoutSigner:
    """Test behavior when signer is not configured."""

    def test_permission_keyboard_works_without_signer(self):
        """Test keyboard works without signer (backward compatibility)."""
        # Ensure no signer is set
        init_callback_signer(None)  # type: ignore

        keyboard = create_permission_keyboard("request-123")
        approve_data = keyboard.inline_keyboard[0][0].callback_data

        # Should be unsigned format
        assert approve_data == "approve:request-123"

    def test_parse_callback_works_without_signer(self):
        """Test parsing works without signer (backward compatibility)."""
        init_callback_signer(None)  # type: ignore

        result = parse_callback_data("approve:request-123")
        assert result.action == CallbackAction.APPROVE
        assert result.request_id == "request-123"


class TestGenerateSecretKey:
    """Test secret key generation."""

    def test_generate_key_default_length(self):
        """Test default key length is 32 bytes (64 hex chars)."""
        key = generate_secret_key()
        assert len(key) == 64  # 32 bytes = 64 hex chars

    def test_generate_key_custom_length(self):
        """Test custom key length."""
        key = generate_secret_key(16)
        assert len(key) == 32  # 16 bytes = 32 hex chars

    def test_generate_key_uniqueness(self):
        """Test that generated keys are unique."""
        keys = [generate_secret_key() for _ in range(100)]
        assert len(set(keys)) == 100  # All unique
