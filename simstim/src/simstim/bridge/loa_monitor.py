"""Loa Monitor (Jack) - PTY wrapper for Loa process.

Provides PTY-based process management for wrapping Claude Code
with bidirectional communication support.
"""

from __future__ import annotations

import asyncio
import logging
import os
from dataclasses import dataclass, field
from typing import TYPE_CHECKING, Callable

import ptyprocess

if TYPE_CHECKING:
    from simstim.config import LoaConfig


logger = logging.getLogger(__name__)


@dataclass
class LoaMonitor:
    """PTY wrapper for Loa process (Jack).

    Manages the lifecycle of a Loa (Claude Code) process with
    PTY-based I/O for real-time stdout monitoring and stdin injection.
    """

    config: LoaConfig
    on_stdout: Callable[[str], None] | None = None
    on_exit: Callable[[int], None] | None = None
    _process: ptyprocess.PtyProcess | None = field(default=None, repr=False)
    _reader_task: asyncio.Task[None] | None = field(default=None, repr=False)
    _running: bool = field(default=False, repr=False)

    async def start(self, initial_command: str | None = None) -> None:
        """Start Loa process in PTY.

        Args:
            initial_command: Optional initial command to pass to Loa
        """
        if self._running:
            raise RuntimeError("Monitor already running")

        # Build command
        cmd = [self.config.command]
        if initial_command:
            # Pass command as argument
            cmd.extend(["--print", initial_command])

        # Prepare environment
        env = {**os.environ, **self.config.environment}

        # Spawn process in PTY
        logger.info(
            "Starting Loa process",
            extra={
                "command": cmd,
                "cwd": str(self.config.working_directory),
            },
        )

        self._process = ptyprocess.PtyProcess.spawn(
            cmd,
            cwd=str(self.config.working_directory),
            env=env,
            dimensions=(24, 120),  # rows, cols
        )

        self._running = True

        # Start reader task
        self._reader_task = asyncio.create_task(
            self._read_loop(),
            name="loa-monitor-reader",
        )

        logger.info("Loa process started", extra={"pid": self._process.pid})

    async def _read_loop(self) -> None:
        """Continuously read from PTY stdout."""
        buffer = ""

        while self._process and self._process.isalive():
            try:
                # Non-blocking read with asyncio
                data = await asyncio.to_thread(
                    self._read_with_timeout,
                    4096,
                    0.1,  # 100ms timeout
                )

                if data:
                    buffer += data

                    # Process complete lines
                    while "\n" in buffer:
                        line, buffer = buffer.split("\n", 1)
                        line = line.rstrip("\r")  # Handle \r\n
                        if self.on_stdout:
                            self.on_stdout(line)

            except EOFError:
                logger.debug("PTY EOF reached")
                break
            except Exception as e:
                logger.exception("PTY read error", extra={"error": str(e)})
                await asyncio.sleep(0.1)

        # Process any remaining buffer
        if buffer and self.on_stdout:
            for line in buffer.split("\n"):
                line = line.rstrip("\r")
                if line:
                    self.on_stdout(line)

        # Handle process exit
        self._running = False
        exit_code = self._process.exitstatus if self._process else -1

        logger.info("Loa process exited", extra={"exit_code": exit_code})

        if self.on_exit:
            self.on_exit(exit_code)

    def _read_with_timeout(self, size: int, timeout: float) -> str:
        """Read from PTY with timeout.

        Args:
            size: Maximum bytes to read
            timeout: Timeout in seconds

        Returns:
            Decoded string data
        """
        if not self._process:
            return ""

        # Use select-based timeout via ptyprocess
        if self._process.isalive():
            try:
                # ptyprocess.read() blocks, so we use a small read
                data = self._process.read(size)
                return data.decode("utf-8", errors="replace")
            except EOFError:
                raise
            except Exception:
                return ""
        return ""

    async def inject(self, text: str) -> bool:
        """Write to Loa process stdin.

        Args:
            text: Text to inject (typically "y\\n" or "n\\n")

        Returns:
            True if injection succeeded
        """
        if not self._process or not self._process.isalive():
            logger.warning("Cannot inject: process not running")
            return False

        try:
            self._process.write(text.encode("utf-8"))
            self._process.flush()

            logger.debug(
                "Injected stdin",
                extra={"text": repr(text)},
            )
            return True

        except Exception as e:
            logger.exception("Inject failed", extra={"error": str(e)})
            return False

    async def stop(self, timeout: float = 5.0) -> int:
        """Stop Loa process and return exit code.

        Args:
            timeout: Timeout for graceful shutdown

        Returns:
            Process exit code
        """
        if not self._running:
            return 0

        logger.info("Stopping Loa process")

        # Cancel reader task
        if self._reader_task:
            self._reader_task.cancel()
            try:
                await asyncio.wait_for(self._reader_task, timeout=1.0)
            except (asyncio.CancelledError, asyncio.TimeoutError):
                pass

        # Stop process
        if self._process:
            if self._process.isalive():
                # Try graceful termination first
                self._process.terminate()

                # Wait for exit
                try:
                    await asyncio.wait_for(
                        asyncio.to_thread(self._process.wait),
                        timeout=timeout,
                    )
                except asyncio.TimeoutError:
                    # Force kill
                    logger.warning("Force killing Loa process")
                    self._process.terminate(force=True)

            exit_code = self._process.exitstatus or 0
            self._running = False
            return exit_code

        return 0

    @property
    def is_running(self) -> bool:
        """Check if process is running."""
        return self._running and bool(self._process and self._process.isalive())

    @property
    def pid(self) -> int | None:
        """Get process PID."""
        return self._process.pid if self._process else None

    async def send_signal(self, signal: int) -> bool:
        """Send signal to process.

        Args:
            signal: Signal number (e.g., signal.SIGINT)

        Returns:
            True if signal was sent
        """
        if not self._process or not self._process.isalive():
            return False

        try:
            self._process.kill(signal)
            return True
        except Exception as e:
            logger.warning(f"Failed to send signal: {e}")
            return False
