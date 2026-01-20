"""Inline keyboards for Telegram messages.

Provides keyboard builders and callback data parsing.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

from telegram import InlineKeyboardButton, InlineKeyboardMarkup


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


def create_permission_keyboard(request_id: str) -> InlineKeyboardMarkup:
    """Create inline keyboard for permission request.

    Args:
        request_id: ID of the permission request

    Returns:
        Inline keyboard markup with Approve/Deny buttons
    """
    return InlineKeyboardMarkup(
        [
            [
                InlineKeyboardButton(
                    "✅ Approve",
                    callback_data=f"{CallbackAction.APPROVE.value}:{request_id}",
                ),
                InlineKeyboardButton(
                    "❌ Deny",
                    callback_data=f"{CallbackAction.DENY.value}:{request_id}",
                ),
            ]
        ]
    )


def create_confirmation_keyboard(action: str, data: str) -> InlineKeyboardMarkup:
    """Create inline keyboard for confirmation dialogs.

    Args:
        action: The action being confirmed
        data: Additional data to pass with confirmation

    Returns:
        Inline keyboard markup with Confirm/Cancel buttons
    """
    return InlineKeyboardMarkup(
        [
            [
                InlineKeyboardButton(
                    "✅ Confirm",
                    callback_data=f"{CallbackAction.CONFIRM.value}:{action}:{data}",
                ),
                InlineKeyboardButton(
                    "❌ Cancel",
                    callback_data=f"{CallbackAction.CANCEL.value}:{action}:{data}",
                ),
            ]
        ]
    )


def parse_callback_data(data: str) -> CallbackData:
    """Parse callback data string from inline keyboard.

    Args:
        data: Callback data string in format "action:request_id[:extra]"

    Returns:
        Parsed callback data

    Raises:
        ValueError: If callback data format is invalid
    """
    parts = data.split(":", maxsplit=2)

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
