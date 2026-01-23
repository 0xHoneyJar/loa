"""Deck - Main orchestrator for Simstim.

Coordinates all components: Loa Monitor (Jack), Telegram Bot (Finn),
Policy Engine (ICE), and handles the main event loop.
"""

from __future__ import annotations

import asyncio
import logging
import signal
from typing import TYPE_CHECKING

from simstim.bridge.loa_monitor import LoaMonitor
from simstim.bridge.permission_queue import (
    PermissionQueue,
    PermissionRequest,
    PermissionResponse,
)
from simstim.bridge.stdout_parser import StdoutParser
from simstim.config import redact_token_from_string
from simstim.policies.engine import PolicyEngine
from simstim.policies.models import PolicyDecision
from simstim.telegram.bot import SimstimBot
from simstim.validation import validate_phase_command, sanitize_for_display

if TYPE_CHECKING:
    from simstim.config import SimstimConfig


logger = logging.getLogger(__name__)


class Deck:
    """Main orchestrator - coordinates all Simstim components.

    The Deck manages the lifecycle of:
    - LoaMonitor (Jack): PTY wrapper for Loa process
    - SimstimBot (Finn): Telegram bot interface
    - PolicyEngine (ICE): Auto-approve policy evaluation
    - StdoutParser: Permission/phase detection
    - PermissionQueue: Async request handling
    """

    def __init__(self, config: SimstimConfig) -> None:
        """Initialize orchestrator.

        Args:
            config: Simstim configuration
        """
        self.config = config
        self._running = False
        self._shutdown_event = asyncio.Event()
        self._exit_code = 0

        # Statistics
        self._auto_approved_count = 0
        self._manual_approved_count = 0
        self._denied_count = 0
        self._timeout_count = 0

        # Initialize components
        self.permission_queue = PermissionQueue(
            timeout_seconds=config.timeouts.permission_timeout_seconds,
            default_action=config.timeouts.default_action,
        )

        self.parser = StdoutParser()

        self.policy_engine = PolicyEngine(config.policies)

        self.bot = SimstimBot(
            config=config.telegram,
            security=config.security,
            permission_queue=self.permission_queue,
            on_halt=self._handle_halt,
            on_start_phase=self._handle_start_phase,
        )

        self.monitor: LoaMonitor | None = None

    async def run(self, initial_command: str | None = None) -> int:
        """Main run loop.

        Args:
            initial_command: Optional initial Loa command

        Returns:
            Exit code from Loa process
        """
        self._running = True
        self._exit_code = 0

        # Setup signal handlers
        loop = asyncio.get_event_loop()
        for sig in (signal.SIGINT, signal.SIGTERM):
            loop.add_signal_handler(sig, self._signal_handler)

        logger.info("Starting Simstim bridge")

        try:
            # Start Telegram bot
            await self.bot.start()
            self.bot.set_loa_running(True)
            self.bot.set_policy_count(self.policy_engine.policy_count)

            # Send startup notification with policy info
            policy_count = self.policy_engine.policy_count
            policy_info = f"Active policies: {policy_count}" if policy_count > 0 else "No auto-approve policies configured"

            await self.bot.send_message(
                "🎮 <b>Simstim Started</b>\n\n"
                f"Bridge is active and monitoring Loa.\n"
                f"{policy_info}"
            )

            # Start Loa monitor
            self.monitor = LoaMonitor(
                config=self.config.loa,
                on_stdout=self._handle_stdout,
                on_exit=self._handle_loa_exit,
            )
            await self.monitor.start(initial_command)

            # Wait for shutdown signal
            await self._shutdown_event.wait()

        except Exception as e:
            logger.exception("Simstim error", extra={"error": str(e)})
            self._exit_code = 1

        finally:
            await self._cleanup()

        return self._exit_code

    def _signal_handler(self) -> None:
        """Handle shutdown signals (SIGINT, SIGTERM)."""
        if not self._shutdown_event.is_set():
            logger.info("Shutdown signal received")
            self._shutdown_event.set()

    def _handle_stdout(self, line: str) -> None:
        """Process a line from Loa stdout.

        Args:
            line: Output line from Loa
        """
        # Add to parser context buffer
        self.parser.add_line(line)

        # Check for permission prompt
        parsed_perm = self.parser.parse_permission(line)
        if parsed_perm:
            asyncio.create_task(
                self._handle_permission(parsed_perm),
                name="permission-handler",
            )
            return

        # Check for phase transition
        if self.config.notifications.phase_transitions:
            parsed_phase = self.parser.parse_phase(line)
            if parsed_phase:
                asyncio.create_task(
                    self.bot.send_phase_notification(parsed_phase),
                    name="phase-notification",
                )
                self.bot.set_current_phase(parsed_phase.phase)

    async def _handle_permission(
        self,
        parsed: "from simstim.bridge.stdout_parser import ParsedPermission",
    ) -> None:
        """Handle a parsed permission request.

        Args:
            parsed: Parsed permission data
        """
        from simstim.bridge.stdout_parser import ParsedPermission

        if not isinstance(parsed, ParsedPermission):
            return

        # Assess risk
        risk = StdoutParser.assess_risk(parsed.action, parsed.target)

        logger.info(
            "Permission request detected",
            extra={
                "action": parsed.action.value,
                "target": parsed.target,
                "risk": risk.value,
            },
        )

        # Check policies first
        policy_result = self.policy_engine.evaluate(
            parsed.action, parsed.target, risk
        )

        if policy_result.match.decision == PolicyDecision.AUTO_APPROVE:
            # Auto-approve via policy
            self._auto_approved_count += 1
            policy_name = policy_result.match.policy.name if policy_result.match.policy else "unknown"

            logger.info(
                "Auto-approved by policy",
                extra={
                    "policy": policy_name,
                    "target": parsed.target,
                },
            )

            # Update bot stats for /status command
            self.bot.update_stats(
                auto_approved=self._auto_approved_count,
                manual_approved=self._manual_approved_count,
                denied=self._denied_count,
            )

            # Inject approval
            if self.monitor:
                await self.monitor.inject("y\n")

            # Send notification about auto-approval (optional)
            if self.config.notifications.phase_transitions:  # Reuse setting for now
                await self.bot.send_message(
                    f"🤖 <b>Auto-Approved</b>\n\n"
                    f"Policy: <code>{policy_name}</code>\n"
                    f"Action: {parsed.action.value}\n"
                    f"Target: <code>{parsed.target}</code>"
                )

            return

        # Manual approval required - create request and queue
        request = PermissionRequest(
            action=parsed.action,
            target=parsed.target,
            context="\n".join(parsed.context_lines[-3:]),
            risk_level=risk,
        )

        # Send notification to Telegram
        try:
            msg_id = await self.bot.send_permission_request(
                request,
                self.config.timeouts.permission_timeout_seconds,
            )
            request.telegram_message_id = msg_id
        except Exception as e:
            logger.exception("Failed to send notification", extra={"error": str(e)})
            # On notification failure, use default action
            answer = "y\n" if self.config.timeouts.default_action == "approve" else "n\n"
            if self.monitor:
                await self.monitor.inject(answer)
            return

        # Wait for response
        response = await self.permission_queue.add(request)

        # Update statistics
        if response.auto_approved:
            if response.policy_name == "timeout":
                self._timeout_count += 1
        elif response.approved:
            self._manual_approved_count += 1
        else:
            self._denied_count += 1

        # Update bot stats for /status command
        self.bot.update_stats(
            auto_approved=self._auto_approved_count,
            manual_approved=self._manual_approved_count,
            denied=self._denied_count,
        )

        # Inject response to Loa
        answer = "y\n" if response.approved else "n\n"
        if self.monitor:
            success = await self.monitor.inject(answer)
            if not success:
                logger.warning("Failed to inject response")

        logger.info(
            "Permission response",
            extra={
                "request_id": request.id,
                "approved": response.approved,
                "auto": response.auto_approved,
                "policy": response.policy_name,
            },
        )

    def _handle_loa_exit(self, exit_code: int) -> None:
        """Handle Loa process exit.

        Args:
            exit_code: Process exit code
        """
        logger.info("Loa process exited", extra={"exit_code": exit_code})
        self._exit_code = exit_code
        self.bot.set_loa_running(False)

        # Send notification with statistics
        stats = (
            f"Auto-approved: {self._auto_approved_count}\n"
            f"Manual approved: {self._manual_approved_count}\n"
            f"Denied: {self._denied_count}\n"
            f"Timeouts: {self._timeout_count}"
        )

        asyncio.create_task(
            self.bot.send_message(
                f"⏹️ <b>Loa Stopped</b>\n\n"
                f"Exit code: <code>{exit_code}</code>\n\n"
                f"<b>Session Stats:</b>\n{stats}"
            ),
            name="exit-notification",
        )

        # Trigger shutdown
        if not self._shutdown_event.is_set():
            self._shutdown_event.set()

    async def _handle_halt(self) -> None:
        """Handle halt command from Telegram."""
        logger.info("Halt requested via Telegram")

        if self.monitor and self.monitor.is_running:
            # Send SIGINT to Loa for graceful shutdown
            import signal as sig
            await self.monitor.send_signal(sig.SIGINT)

    async def _handle_start_phase(self, phase_command: str) -> bool:
        """Handle start phase command from Telegram.

        Security Note: Command validation is performed in bot.py before reaching here,
        but we perform defense-in-depth validation again (SIMSTIM-002 fix).

        Args:
            phase_command: Validated Loa command to start (e.g., "/implement sprint-1")

        Returns:
            True if command was sent successfully
        """
        # Defense-in-depth: validate again even though bot.py already validated
        validation = validate_phase_command(phase_command)
        if not validation.valid:
            safe_error = sanitize_for_display(validation.error or "Unknown error")
            logger.warning(
                f"Rejected invalid phase command in Deck: {sanitize_for_display(phase_command, 50)}"
            )
            await self.bot.send_message(
                f"⚠️ <b>Invalid Command</b>\n\n"
                f"Error: {safe_error}"
            )
            return False

        # Use the sanitized command
        safe_command = validation.sanitized or ""

        logger.info("Start phase requested", extra={"command": safe_command})

        if not self.monitor or not self.monitor.is_running:
            await self.bot.send_message(
                "⚠️ <b>Cannot Start Phase</b>\n\n"
                "Loa is not running."
            )
            return False

        # Inject the validated command to Loa
        success = await self.monitor.inject(f"{safe_command}\n")

        if success:
            await self.bot.send_message(
                f"🚀 <b>Phase Command Sent</b>\n\n"
                f"<code>{sanitize_for_display(safe_command)}</code>"
            )
        else:
            await self.bot.send_message(
                "⚠️ <b>Failed to Send Command</b>\n\n"
                "Could not inject command to Loa."
            )

        return success

    async def _cleanup(self) -> None:
        """Clean up resources on shutdown."""
        self._running = False

        # Cancel all pending permission requests
        cancelled = await self.permission_queue.cancel_all()
        if cancelled > 0:
            logger.info(f"Cancelled {cancelled} pending requests")

        # Stop Loa monitor
        if self.monitor:
            exit_code = await self.monitor.stop()
            if self._exit_code == 0:
                self._exit_code = exit_code

        # Send shutdown notification
        try:
            await self.bot.send_message(
                "🔌 <b>Simstim Shutting Down</b>\n\n"
                "Bridge is disconnecting."
            )
        except Exception:
            pass  # Best effort

        # Stop bot
        await self.bot.stop()

        logger.info("Simstim cleanup complete")

    @property
    def is_running(self) -> bool:
        """Check if orchestrator is running."""
        return self._running

    def get_status(self) -> dict:
        """Get current status information.

        Returns:
            Status dictionary
        """
        return {
            "running": self._running,
            "loa_running": self.monitor.is_running if self.monitor else False,
            "pending_requests": self.permission_queue.pending_count,
            "current_phase": self.bot._current_phase.value if self.bot._current_phase else None,
            "statistics": {
                "auto_approved": self._auto_approved_count,
                "manual_approved": self._manual_approved_count,
                "denied": self._denied_count,
                "timeouts": self._timeout_count,
            },
            "policies": {
                "count": self.policy_engine.policy_count,
                "evaluations": self.policy_engine.evaluation_count,
            },
        }
