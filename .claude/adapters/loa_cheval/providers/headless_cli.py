"""Shared single-shot CLI behavior; transport and output formats stay provider-specific."""

from __future__ import annotations

import json
import logging
import shutil
import subprocess
import time
from abc import abstractmethod
from contextlib import contextmanager
from dataclasses import dataclass
from typing import Any, Dict, Iterator, List

from loa_cheval.providers.base import (
    ProviderAdapter, SubprocessOutputCapExceeded, build_headless_subprocess_env,
    enforce_context_window, run_subprocess_pgkill,
)
from loa_cheval.types import CompletionRequest, CompletionResult, ConfigError, ProviderUnavailableError


@dataclass
class CLIInvocation:
    """Prepared command and transport arguments, owned by a provider context."""

    command: List[str]
    kwargs: Dict[str, Any]
    started_at: float


class HeadlessCLIAdapter(ProviderAdapter):
    """Common completion, validation, prompt, health, and timeout scaffold.

    Providers retain command/workspace preparation, response parsing, and any
    differing spawn-error semantics. Authentication is checked by the CLI.
    """

    _cli_type: str
    _cli_name: str
    _command_label: str
    _install_hint: str
    _spawn_install_hint: str = ""
    _logger = logging.getLogger("loa_cheval.providers.headless")

    def complete(self, request: CompletionRequest) -> CompletionResult:
        model_config = self._get_model_config(request.model)
        enforce_context_window(request, model_config)
        prompt = self._build_prompt(request.messages)
        timeout_s = self._compute_timeout()
        n_slots = getattr(model_config, "headless_concurrency_limit", None) or 50
        self._logger.debug(
            "%s invoking: model=%s timeout=%.0fs prompt_chars=%d slots=%d",
            self._cli_type, request.model, timeout_s, len(prompt), n_slots,
        )

        # Import before provider contexts create resources, so import failure
        # cannot leak a workspace. Every dispatch uses the same slot/kill path.
        from loa_cheval.adapters.headless_concurrency import SemaphoreExhausted, acquire_slot

        try:
            with self._prepare_invocation(request, model_config, prompt) as invocation:
                with acquire_slot(self._cli_type, n_slots=n_slots):
                    try:
                        proc = self._run_subprocess(
                            invocation.command, timeout=timeout_s,
                            env=build_headless_subprocess_env(), **invocation.kwargs,
                        )
                    except subprocess.TimeoutExpired:
                        raise ProviderUnavailableError(
                            self.provider, f"{self._command_label} timed out after {timeout_s:.0f}s",
                        )
                    except SubprocessOutputCapExceeded as exc:
                        raise ProviderUnavailableError(
                            self.provider, f"{self._command_label} {exc}",
                        ) from exc
                    except FileNotFoundError as exc:
                        env_name = self._cli_type.upper().replace("-", "_") + "_BIN"
                        hint = self._spawn_install_hint or self._install_hint
                        raise ConfigError(
                            f"{self._cli_name} CLI not found on PATH (set {env_name} to override). "
                            f"{hint}. Original: {exc}"
                        ) from exc
                    except (OSError, ValueError) as exc:
                        self._raise_spawn_error(exc)
        except SemaphoreExhausted as exc:
            raise ProviderUnavailableError(
                self.provider,
                f"[CHAIN-EXHAUSTED-CONCURRENCY] {self._cli_type} semaphore "
                f"exhausted after {exc.waited_seconds:.1f}s (n_slots={exc.n_slots})",
            ) from exc

        # Context exit performs provider-specific cleanup before parsing.
        latency_ms = int((time.monotonic() - invocation.started_at) * 1000)
        return self._finish_completion(proc, request, latency_ms)

    @contextmanager
    def _prepare_invocation(self, request, model_config, prompt) -> Iterator[CLIInvocation]:
        """Default argv transport; stdin and workspace providers override."""
        command = self._build_command(request, model_config, prompt)
        yield CLIInvocation(command, {}, time.monotonic())

    def _run_subprocess(self, command, **kwargs):
        return run_subprocess_pgkill(command, **kwargs)

    def _raise_spawn_error(self, exc: Exception) -> None:
        """Argv CLI errors; providers with different contracts override."""
        if isinstance(exc, OSError):
            message = f"{self._command_label} spawn failed (ARG_MAX / ENOMEM / exec error?): {exc}"
        else:
            message = f"{self._command_label} got un-executable argv (embedded NUL in the prompt?): {exc}"
        raise ProviderUnavailableError(self.provider, message) from exc

    def _finish_completion(self, proc, request, latency_ms) -> CompletionResult:
        raise NotImplementedError

    def validate_config(self) -> List[str]:
        errors: List[str] = []
        if self.config.type != self._cli_type:
            errors.append(
                f"Provider '{self.provider}': type must be '{self._cli_type}' "
                f"(got '{self.config.type}')"
            )
        bin_name = self._cli_bin()
        if not shutil.which(bin_name):
            errors.append(
                f"Provider '{self.provider}': '{bin_name}' CLI not found on PATH. "
                f"{self._install_hint}"
            )
        return errors

    @abstractmethod
    def _cli_bin(self) -> str:
        """Return the provider's executable, honoring its environment override."""

    def health_check(self) -> bool:
        """Probe binary presence/version only; this does not prove authentication."""
        bin_name = self._cli_bin()
        if not shutil.which(bin_name):
            return False
        try:
            proc = subprocess.run(
                [bin_name, "--version"],
                capture_output=True,
                text=True,
                timeout=5.0,
                check=False,
            )
            return proc.returncode == 0
        except (subprocess.TimeoutExpired, OSError):
            return False

    def _compute_timeout(self) -> float:
        """Keep the existing 10s connect and 600s read floors."""
        return max(self.config.connect_timeout, 10.0) + max(self.config.read_timeout, 600.0)

    def _build_prompt(self, messages: List[Dict[str, Any]]) -> str:
        """Flatten messages into role-prefixed sections for single-shot inference."""
        sections: List[str] = []
        last_role = ""
        for msg in messages:
            role = (msg.get("role") or "user").lower()
            content = msg.get("content", "")
            if isinstance(content, list):
                content = "\n".join(
                    block.get("text", "")
                    for block in content
                    if isinstance(block, dict)
                )
            elif not isinstance(content, str):
                try:
                    content = json.dumps(content)
                except (TypeError, ValueError):
                    content = str(content)
            label = {
                "system": "## System",
                "user": "## User",
                "assistant": "## Assistant",
                "tool": "## Tool result",
            }.get(role, f"## {role.capitalize()}")
            # cycle-124 FR-4: consecutive system messages (persona + context
            # split for the Anthropic cache breakpoint) render as ONE section
            # joined with "\n\n" — byte-identical to the merged prompt.
            if role == "system" and sections and last_role == "system":
                sections[-1] = f"{sections[-1]}\n\n{content}".rstrip()
            else:
                sections.append(f"{label}\n\n{content}".rstrip())
            last_role = role
        return "\n\n".join(sections) + "\n"
