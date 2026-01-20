"""Telegram bot handler for Simstim (Finn).

Provides the main bot interface for receiving commands and handling
permission request callbacks.

Security Note: This module handles sensitive bot tokens. All exceptions
are filtered through redact_token_from_string() before logging.
"""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING, Callable, Coroutine, Any

from telegram import Update
from telegram.ext import (
    Application,
    CommandHandler,
    CallbackQueryHandler,
    ContextTypes,
)

from simstim.config import redact_token_from_string
from simstim.validation import validate_phase_command, sanitize_for_display
from simstim.telegram.formatters import (
    format_permission_request,
    format_phase_notification,
    format_status,
    format_response_confirmation,
)
from simstim.telegram.keyboards import (
    CallbackAction,
    create_permission_keyboard,
    parse_callback_data,
)

if TYPE_CHECKING:
    from simstim.bridge.permission_queue import PermissionQueue, PermissionRequest, PermissionResponse
    from simstim.bridge.stdout_parser import ParsedPhase, PhaseType
    from simstim.config import TelegramConfig, SecurityConfig


logger = logging.getLogger(__name__)


class SafeLogger:
    """Logger wrapper that redacts sensitive tokens from all messages."""

    def __init__(self, logger: logging.Logger):
        self._logger = logger

    def info(self, msg: str, *args, **kwargs) -> None:
        self._logger.info(redact_token_from_string(str(msg)), *args, **kwargs)

    def debug(self, msg: str, *args, **kwargs) -> None:
        self._logger.debug(redact_token_from_string(str(msg)), *args, **kwargs)

    def warning(self, msg: str, *args, **kwargs) -> None:
        self._logger.warning(redact_token_from_string(str(msg)), *args, **kwargs)

    def error(self, msg: str, *args, **kwargs) -> None:
        self._logger.error(redact_token_from_string(str(msg)), *args, **kwargs)

    def exception(self, msg: str, *args, **kwargs) -> None:
        # Redact from exception info as well
        self._logger.exception(redact_token_from_string(str(msg)), *args, **kwargs)


safe_logger = SafeLogger(logger)


class SimstimBot:
    """Telegram bot handler (Finn).

    Handles bot initialization, command handlers, and callback query
    processing for permission request interactions.
    """

    def __init__(
        self,
        config: TelegramConfig,
        security: SecurityConfig,
        permission_queue: PermissionQueue,
        on_halt: Callable[[], Coroutine[Any, Any, None]] | None = None,
        on_start_phase: Callable[[str], Coroutine[Any, Any, bool]] | None = None,
    ) -> None:
        """Initialize bot handler.

        Args:
            config: Telegram configuration
            security: Security configuration
            permission_queue: Permission queue for managing requests
            on_halt: Async callback for halt command
            on_start_phase: Async callback for start_phase command (returns success)
        """
        self.config = config
        self.security = security
        self.queue = permission_queue
        self._on_halt = on_halt
        self._on_start_phase = on_start_phase
        self._app: Application | None = None
        self._current_phase: PhaseType | None = None
        self._loa_running = False
        self._policy_count = 0
        self._auto_approved = 0
        self._manual_approved = 0
        self._denied = 0

    async def start(self) -> None:
        """Initialize and start the bot.

        Security Note: Token is obtained via get_token_safe() and never logged.
        """
        try:
            self._app = (
                Application.builder()
                .token(self.config.get_token_safe())
                .build()
            )
        except Exception as e:
            # Redact any token from exception before re-raising
            safe_msg = redact_token_from_string(str(e))
            safe_logger.error(f"Failed to initialize bot: {safe_msg}")
            raise RuntimeError(f"Bot initialization failed: {safe_msg}") from None

        # Register command handlers
        self._app.add_handler(CommandHandler("start", self._cmd_start))
        self._app.add_handler(CommandHandler("status", self._cmd_status))
        self._app.add_handler(CommandHandler("halt", self._cmd_halt))
        self._app.add_handler(CommandHandler("start_phase", self._cmd_start_phase))
        self._app.add_handler(CommandHandler("policies", self._cmd_policies))
        self._app.add_handler(CommandHandler("help", self._cmd_help))

        # Register callback query handler for inline keyboards
        self._app.add_handler(CallbackQueryHandler(self._handle_callback))

        # Initialize and start
        await self._app.initialize()
        await self._app.start()
        if self._app.updater:
            await self._app.updater.start_polling()

        safe_logger.info("Simstim bot started")

    async def stop(self) -> None:
        """Stop the bot."""
        if self._app:
            if self._app.updater:
                await self._app.updater.stop()
            await self._app.stop()
            await self._app.shutdown()
            safe_logger.info("Simstim bot stopped")

    def set_loa_running(self, running: bool) -> None:
        """Update Loa running status.

        Args:
            running: Whether Loa is running
        """
        self._loa_running = running

    def set_current_phase(self, phase: PhaseType | None) -> None:
        """Update current phase.

        Args:
            phase: Current phase or None
        """
        self._current_phase = phase

    def set_policy_count(self, count: int) -> None:
        """Update policy count for status display.

        Args:
            count: Number of active policies
        """
        self._policy_count = count

    def update_stats(
        self,
        auto_approved: int = 0,
        manual_approved: int = 0,
        denied: int = 0,
    ) -> None:
        """Update permission statistics.

        Args:
            auto_approved: Count of auto-approved requests
            manual_approved: Count of manually approved requests
            denied: Count of denied requests
        """
        self._auto_approved = auto_approved
        self._manual_approved = manual_approved
        self._denied = denied

    def _is_authorized(self, user_id: int) -> bool:
        """Check if user is authorized.

        Security Note (SIMSTIM-003): Uses fail-closed authorization.
        Empty authorized_users list denies all unless allow_anonymous is True.

        Args:
            user_id: Telegram user ID

        Returns:
            True if user is authorized
        """
        # SECURITY: Delegate to SecurityConfig.is_authorized() which is fail-closed
        return self.security.is_authorized(user_id)

    async def _log_unauthorized(self, user_id: int, action: str) -> None:
        """Log unauthorized access attempt.

        Args:
            user_id: Telegram user ID
            action: Action that was attempted
        """
        if self.security.log_unauthorized_attempts:
            logger.warning(
                "Unauthorized access attempt",
                extra={
                    "user_id": user_id,
                    "action": action,
                },
            )

    async def _cmd_start(
        self,
        update: Update,
        context: ContextTypes.DEFAULT_TYPE,
    ) -> None:
        """Handle /start command."""
        if not update.effective_user or not update.message:
            return

        user_id = update.effective_user.id

        if not self._is_authorized(user_id):
            await self._log_unauthorized(user_id, "start")
            await update.message.reply_text(
                "⛔ Unauthorized.\n\n"
                f"Your user ID ({user_id}) is not in the allowed list.\n"
                "Contact the administrator to request access."
            )
            return

        await update.message.reply_text(
            "🎮 <b>Simstim Connected</b>\n\n"
            "You will receive permission requests from Loa here.\n\n"
            "<b>Commands:</b>\n"
            "/status - Check bridge status\n"
            "/halt - Stop Loa gracefully\n"
            "/help - Show help",
            parse_mode="HTML",
        )

    async def _cmd_status(
        self,
        update: Update,
        context: ContextTypes.DEFAULT_TYPE,
    ) -> None:
        """Handle /status command."""
        if not update.effective_user or not update.message:
            return

        if not self._is_authorized(update.effective_user.id):
            await self._log_unauthorized(update.effective_user.id, "status")
            return

        status_text = format_status(
            pending_count=self.queue.pending_count,
            current_phase=self._current_phase,
            loa_running=self._loa_running,
            bot_connected=True,
            policy_count=self._policy_count,
            auto_approved=self._auto_approved,
            manual_approved=self._manual_approved,
            denied=self._denied,
        )
        await update.message.reply_text(status_text, parse_mode="HTML")

    async def _cmd_halt(
        self,
        update: Update,
        context: ContextTypes.DEFAULT_TYPE,
    ) -> None:
        """Handle /halt command."""
        if not update.effective_user or not update.message:
            return

        if not self._is_authorized(update.effective_user.id):
            await self._log_unauthorized(update.effective_user.id, "halt")
            return

        await update.message.reply_text(
            "⏹️ Halt signal sent.\n\n"
            "Loa will stop at the next safe point."
        )

        if self._on_halt:
            await self._on_halt()

    async def _cmd_help(
        self,
        update: Update,
        context: ContextTypes.DEFAULT_TYPE,
    ) -> None:
        """Handle /help command."""
        if not update.effective_user or not update.message:
            return

        if not self._is_authorized(update.effective_user.id):
            await self._log_unauthorized(update.effective_user.id, "help")
            return

        await update.message.reply_text(
            "🎮 <b>Simstim Help</b>\n\n"
            "<b>What is Simstim?</b>\n"
            "Simstim bridges your Loa (Claude Code) sessions to Telegram, "
            "allowing you to monitor and approve permissions remotely.\n\n"
            "<b>Commands:</b>\n"
            "/start - Initialize connection\n"
            "/status - Show bridge status\n"
            "/halt - Signal Loa to stop\n"
            "/start_phase &lt;command&gt; - Start a Loa phase\n"
            "/policies - List active auto-approve policies\n"
            "/help - Show this help\n\n"
            "<b>Permission Buttons:</b>\n"
            "✅ Approve - Allow the action\n"
            "❌ Deny - Reject the action\n\n"
            "<b>Risk Levels:</b>\n"
            "🟢 Low - Safe operations\n"
            "🟡 Medium - Review recommended\n"
            "🟠 High - Careful review required\n"
            "🔴 Critical - System-level changes",
            parse_mode="HTML",
        )

    async def _cmd_start_phase(
        self,
        update: Update,
        context: ContextTypes.DEFAULT_TYPE,
    ) -> None:
        """Handle /start_phase command.

        Security Note: This command validates all input against an allowlist
        to prevent command injection (CWE-78 / SIMSTIM-002).
        """
        if not update.effective_user or not update.message:
            return

        if not self._is_authorized(update.effective_user.id):
            await self._log_unauthorized(update.effective_user.id, "start_phase")
            return

        if not self._loa_running:
            await update.message.reply_text(
                "⚠️ <b>Cannot Start Phase</b>\n\n"
                "Loa is not currently running.",
                parse_mode="HTML",
            )
            return

        # Get the phase command from args
        if not context.args:
            await update.message.reply_text(
                "⚠️ <b>Missing Phase Command</b>\n\n"
                "Usage: <code>/start_phase /implement sprint-1</code>\n\n"
                "Examples:\n"
                "• <code>/start_phase /implement sprint-1</code>\n"
                "• <code>/start_phase /review-sprint sprint-1</code>\n"
                "• <code>/start_phase /audit-sprint sprint-1</code>",
                parse_mode="HTML",
            )
            return

        raw_command = " ".join(context.args)

        # SECURITY: Validate command against allowlist (SIMSTIM-002 fix)
        validation = validate_phase_command(raw_command)
        if not validation.valid:
            safe_error = sanitize_for_display(validation.error or "Unknown error")
            safe_logger.warning(
                f"Rejected invalid phase command from user {update.effective_user.id}: "
                f"{sanitize_for_display(raw_command, 50)}"
            )
            await update.message.reply_text(
                f"⚠️ <b>Invalid Command</b>\n\n"
                f"Error: {safe_error}\n\n"
                f"Only allowlisted Loa commands are accepted.",
                parse_mode="HTML",
            )
            return

        # Use the sanitized command
        safe_command = validation.sanitized

        if not self._on_start_phase:
            await update.message.reply_text(
                "⚠️ Phase command handler not configured."
            )
            return

        # Send the validated command
        await update.message.reply_text(
            f"🚀 <b>Starting Phase</b>\n\n"
            f"Sending: <code>{sanitize_for_display(safe_command or '')}</code>",
            parse_mode="HTML",
        )

        await self._on_start_phase(safe_command or "")

    async def _cmd_policies(
        self,
        update: Update,
        context: ContextTypes.DEFAULT_TYPE,
    ) -> None:
        """Handle /policies command."""
        if not update.effective_user or not update.message:
            return

        if not self._is_authorized(update.effective_user.id):
            await self._log_unauthorized(update.effective_user.id, "policies")
            return

        if self._policy_count == 0:
            await update.message.reply_text(
                "📋 <b>Auto-Approve Policies</b>\n\n"
                "No policies configured.\n\n"
                "Add policies to <code>simstim.toml</code> to auto-approve "
                "matching permission requests.",
                parse_mode="HTML",
            )
            return

        await update.message.reply_text(
            f"📋 <b>Auto-Approve Policies</b>\n\n"
            f"Active policies: <code>{self._policy_count}</code>\n\n"
            f"<b>Session Statistics:</b>\n"
            f"• Auto-approved: {self._auto_approved}\n"
            f"• Manually approved: {self._manual_approved}\n"
            f"• Denied: {self._denied}\n\n"
            "<i>View policy details in simstim.toml</i>",
            parse_mode="HTML",
        )

    async def _handle_callback(
        self,
        update: Update,
        context: ContextTypes.DEFAULT_TYPE,
    ) -> None:
        """Handle inline keyboard callbacks."""
        query = update.callback_query
        if not query or not update.effective_user or not query.data:
            return

        user_id = update.effective_user.id

        if not self._is_authorized(user_id):
            await self._log_unauthorized(user_id, "callback")
            await query.answer("⛔ Unauthorized", show_alert=True)
            return

        await query.answer()

        try:
            callback_data = parse_callback_data(query.data)
        except ValueError as e:
            safe_logger.warning(f"Invalid callback data: {e}")
            return

        if callback_data.action in (CallbackAction.APPROVE, CallbackAction.DENY):
            await self._handle_permission_response(
                query=query,
                user_id=user_id,
                approved=(callback_data.action == CallbackAction.APPROVE),
                request_id=callback_data.request_id,
            )

    async def _handle_permission_response(
        self,
        query: Any,
        user_id: int,
        approved: bool,
        request_id: str | None,
    ) -> None:
        """Handle permission response callback.

        Args:
            query: Callback query
            user_id: User who responded
            approved: Whether approved
            request_id: Permission request ID
        """
        if not request_id:
            await query.edit_message_text(
                f"{query.message.text}\n\n⚠️ Invalid request"
            )
            return

        # Import here to avoid circular imports
        from simstim.bridge.permission_queue import PermissionResponse

        response = PermissionResponse(
            request_id=request_id,
            approved=approved,
            responded_by=user_id,
        )

        success = await self.queue.respond(response)

        if success:
            confirmation = format_response_confirmation(
                request_id=request_id,
                approved=approved,
                user_id=user_id,
            )
            # Preserve original message and append confirmation
            original_text = query.message.text or ""
            await query.edit_message_text(
                f"{original_text}{confirmation}",
                parse_mode="HTML",
            )
        else:
            await query.edit_message_text(
                f"{query.message.text}\n\n⚠️ Request expired or already handled"
            )

    async def send_permission_request(
        self,
        request: PermissionRequest,
        timeout_seconds: int,
    ) -> int:
        """Send permission request notification.

        Args:
            request: Permission request to notify about
            timeout_seconds: Timeout for display

        Returns:
            Message ID of sent message
        """
        if not self._app:
            raise RuntimeError("Bot not started")

        text = format_permission_request(
            request=request,
            timeout_seconds=timeout_seconds,
            redact_patterns=self.security.redact_patterns,
        )
        keyboard = create_permission_keyboard(request.id)

        message = await self._app.bot.send_message(
            chat_id=self.config.chat_id,
            text=text,
            reply_markup=keyboard,
            parse_mode="HTML",
        )

        safe_logger.info(
            "Sent permission request",
            extra={
                "request_id": request.id,
                "message_id": message.message_id,
            },
        )

        return message.message_id

    async def send_phase_notification(self, phase: ParsedPhase) -> None:
        """Send phase transition notification.

        Args:
            phase: Parsed phase transition
        """
        if not self._app:
            raise RuntimeError("Bot not started")

        self._current_phase = phase.phase
        text = format_phase_notification(phase)

        await self._app.bot.send_message(
            chat_id=self.config.chat_id,
            text=text,
            parse_mode="HTML",
        )

        safe_logger.info(
            "Sent phase notification",
            extra={"phase": phase.phase.value},
        )

    async def send_message(self, text: str, parse_mode: str = "HTML") -> int:
        """Send a generic message.

        Args:
            text: Message text
            parse_mode: Parse mode (HTML or Markdown)

        Returns:
            Message ID
        """
        if not self._app:
            raise RuntimeError("Bot not started")

        message = await self._app.bot.send_message(
            chat_id=self.config.chat_id,
            text=text,
            parse_mode=parse_mode,
        )

        return message.message_id

    async def update_message(
        self,
        message_id: int,
        text: str,
        parse_mode: str = "HTML",
    ) -> None:
        """Update an existing message.

        Args:
            message_id: Message to update
            text: New text
            parse_mode: Parse mode
        """
        if not self._app:
            raise RuntimeError("Bot not started")

        await self._app.bot.edit_message_text(
            chat_id=self.config.chat_id,
            message_id=message_id,
            text=text,
            parse_mode=parse_mode,
        )
