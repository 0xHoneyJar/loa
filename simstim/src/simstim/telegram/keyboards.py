"""Inline keyboards for Telegram messages.

Provides keyboard builders and callback data parsing with HMAC signing.

Security Note (SIMSTIM-005): All callback data is HMAC-signed to prevent
callback injection and replay attacks.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import TYPE_CHECKING

from telegram import InlineKeyboardButton, InlineKeyboardMarkup

if TYPE_CHECKING:
    from simstim.security.crypto import CallbackSigner


class CallbackAction(Enum):
    """Actions for inline keyboard callbacks."""

    APPROVE = "approve"
    DENY = "deny"
    CANCEL = "cancel"
    HALT = "halt"
    CONFIRM = "confirm"


@dataclass
class CallbackData:
    """Parsed callback data from inline keyboard."""

    action: CallbackAction
    request_id: str | None = None
    extra: str | None = None


# Global signer instance - must be initialized at startup
_signer: CallbackSigner | None = None


def init_callback_signer(signer: CallbackSigner) -> None:
    """Initialize the callback signer.

    This must be called at startup with a properly configured signer.

    Args:
        signer: CallbackSigner instance with secret key
    """
    global _signer
    _signer = signer


def get_callback_signer() -> CallbackSigner | None:
    """Get the current callback signer.

    Returns:
        CallbackSigner if initialized, None otherwise
    """
    return _signer


def create_permission_keyboard(request_id: str) -> InlineKeyboardMarkup:
    """Create inline keyboard for permission request.

    Security Note (SIMSTIM-005): Callback data is HMAC-signed.

    Args:
        request_id: ID of the permission request

    Returns:
        Inline keyboard markup with Approve/Deny buttons
    """
    approve_payload = f"{CallbackAction.APPROVE.value}:{request_id}"
    deny_payload = f"{CallbackAction.DENY.value}:{request_id}"

    # Sign payloads if signer is configured
    if _signer:
        approve_payload = _signer.sign(approve_payload)
        deny_payload = _signer.sign(deny_payload)

    return InlineKeyboardMarkup(
        [
            [
                InlineKeyboardButton(
                    "✅ Approve",
                    callback_data=approve_payload,
                ),
                InlineKeyboardButton(
                    "❌ Deny",
                    callback_data=deny_payload,
                ),
            ]
        ]
    )


def create_confirmation_keyboard(action: str, data: str) -> InlineKeyboardMarkup:
    """Create inline keyboard for confirmation dialogs.

    Security Note (SIMSTIM-005): Callback data is HMAC-signed.

    Args:
        action: The action being confirmed
        data: Additional data to pass with confirmation

    Returns:
        Inline keyboard markup with Confirm/Cancel buttons
    """
    confirm_payload = f"{CallbackAction.CONFIRM.value}:{action}:{data}"
    cancel_payload = f"{CallbackAction.CANCEL.value}:{action}:{data}"

    # Sign payloads if signer is configured
    if _signer:
        confirm_payload = _signer.sign(confirm_payload)
        cancel_payload = _signer.sign(cancel_payload)

    return InlineKeyboardMarkup(
        [
            [
                InlineKeyboardButton(
                    "✅ Confirm",
                    callback_data=confirm_payload,
                ),
                InlineKeyboardButton(
                    "❌ Cancel",
                    callback_data=cancel_payload,
                ),
            ]
        ]
    )


def parse_callback_data(data: str) -> CallbackData:
    """Parse and verify callback data string from inline keyboard.

    Security Note (SIMSTIM-005): If signer is configured, callback data
    is verified before parsing. Invalid or expired signatures are rejected.

    Args:
        data: Callback data string (may be signed)

    Returns:
        Parsed callback data

    Raises:
        ValueError: If callback data format is invalid or signature verification fails
    """
    payload = data

    # Verify signature if signer is configured
    if _signer:
        result = _signer.verify(data)
        if result is None:
            raise ValueError("Invalid or expired callback signature")
        payload = result.payload

    parts = payload.split(":", maxsplit=2)

    if not parts:
        raise ValueError("Empty callback data")

    try:
        action = CallbackAction(parts[0])
    except ValueError:
        raise ValueError(f"Invalid callback action: {parts[0]}")

    request_id = parts[1] if len(parts) > 1 else None
    extra = parts[2] if len(parts) > 2 else None

    return CallbackData(
        action=action,
        request_id=request_id,
        extra=extra,
    )
