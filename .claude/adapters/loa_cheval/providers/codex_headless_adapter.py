"""Codex-headless provider adapter — invokes `codex exec` for ChatGPT subscription auth.

Routes Loa's cheval calls through the OpenAI Codex CLI (`codex exec`) instead of
the OpenAI HTTP API. Auth comes from `~/.codex/auth.json` (populated by
`codex login`), so no `OPENAI_API_KEY` is consumed for these calls. The same
gpt-5.x model line is reachable; only the transport changes.

When to use:
  - You have a ChatGPT Plus / Pro / Team / Enterprise subscription and want
    bridgebuilder / spiraling / flatline-review to draw from the subscription
    quota instead of the API balance.
  - You want a single-process operator workflow (no hosted API key juggling).

Design notes:
  - Single-shot only. Multi-turn message arrays are flattened into one prompt
    with role-prefixed sections. For review / skeptic / scorer / dissenter
    roles (the four flatline modes) this is correct — they're single-pass.
  - Tools / tool_choice are NOT forwarded to the codex agent. Adding tool
    forwarding requires mapping CompletionRequest.tools → codex's
    feature/tool config and parsing tool-call events. Out of scope for v1.
  - Reasoning effort is configurable per-call via:
      1. CompletionRequest.metadata["reasoning_effort"]   (highest priority)
      2. ModelConfig.extra["reasoning_effort"]            (per-model default)
      3. Codex CLI default                                 (lowest)
    Allowed values map 1:1 to codex's `model_reasoning_effort` (low / medium /
    high / xhigh on codex >= 0.125.0).
  - Sandbox defaults to `read-only` and the adapter passes `--ephemeral`
    + `--ignore-user-config` for deterministic, single-call behavior. We never
    enable workspace-write or full-access — the model-router use case is pure
    inference and must not touch the user's files.
  - Token usage maps:
      codex `input_tokens`             → Usage.input_tokens
      codex `output_tokens`             → Usage.output_tokens (excludes reasoning)
      codex `reasoning_output_tokens`   → Usage.reasoning_tokens
    NOTE: this differs from /v1/responses where output_tokens is INCLUSIVE of
    reasoning. Cost ledgers should bill `output_tokens + reasoning_tokens` for
    codex-headless if the operator's billing model treats reasoning as paid.
    For ChatGPT subscription billing, all tokens are subscription-quota-side
    so the cost-ledger micro-USD values should be 0 — see ModelConfig.pricing.
"""

from __future__ import annotations

import json
import logging
import os
import shutil
import subprocess
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

from loa_cheval.providers.base import (
    ProviderAdapter,
    build_headless_subprocess_env,
    enforce_context_window,
)
from loa_cheval.types import (
    CompletionRequest,
    CompletionResult,
    ConfigError,
    ProviderUnavailableError,
    RateLimitError,
    Usage,
)

logger = logging.getLogger("loa_cheval.providers.codex_headless")

# Allowed reasoning effort levels (codex CLI >= 0.125.0)
_ALLOWED_REASONING_EFFORTS = ("low", "medium", "high", "xhigh")

# codex CLI binary name (override via CODEX_HEADLESS_BIN env var for testing)
_CODEX_BIN_DEFAULT = "codex"

# Auth file populated by `codex login` (subscription mode)
_CODEX_AUTH_FILE = "~/.codex/auth.json"

# Conservative defaults for the subprocess wall-clock. ProviderConfig.read_timeout
# wins when set; these are only used if the loader hands us defaults.
_CONNECT_TIMEOUT_FLOOR = 10.0
_READ_TIMEOUT_FLOOR = 600.0  # 10 min — codex sessions with reasoning can be slow


class CodexHeadlessAdapter(ProviderAdapter):
    """Adapter that routes inference through `codex exec`.

    Provider config (no api_key field):

        providers:
          codex-headless:
            type: codex-headless
            # endpoint and auth are ignored; both default to empty.
            connect_timeout: 10.0
            read_timeout: 600.0
            models:
              gpt-5.5:
                context_window: 200000
                pricing: {input_per_mtok: 0, output_per_mtok: 0}
                extra:
                  reasoning_effort: high

    Aliases bind to provider:model-id like other adapters:

        aliases:
          reviewer: codex-headless:gpt-5.5
          reasoning: codex-headless:gpt-5.5
    """

    # Cycle-110 FR-2.3 — subscription-CLI dispatch; circuit-breaker writes
    # route to the (openai, headless) bucket.
    auth_type: str = "headless"

    def complete(self, request: CompletionRequest) -> CompletionResult:
        """Invoke `codex exec` and return a normalized CompletionResult."""
        model_config = self._get_model_config(request.model)
        enforce_context_window(request, model_config)

        prompt = self._build_prompt(request.messages)
        cmd = self._build_command(request, model_config)
        timeout_s = self._compute_timeout()

        logger.debug(
            "codex-headless invoking: model=%s timeout=%.0fs prompt_chars=%d",
            request.model,
            timeout_s,
            len(prompt),
        )

        start = time.monotonic()
        try:
            proc = subprocess.run(
                cmd,
                input=prompt,
                capture_output=True,
                text=True,
                timeout=timeout_s,
                check=False,
                # cycle-109 follow-up (#879 / #880 symmetric): strip
                # OPENAI_API_KEY so codex exec uses OAuth, not API mode.
                env=build_headless_subprocess_env(),
            )
        except subprocess.TimeoutExpired:
            raise ProviderUnavailableError(
                self.provider,
                f"codex exec timed out after {timeout_s:.0f}s",
            )
        except FileNotFoundError as exc:
            raise ConfigError(
                f"codex CLI not found on PATH (set CODEX_HEADLESS_BIN to override). "
                f"Install with: npm install -g @openai/codex. Original: {exc}"
            ) from exc

        latency_ms = int((time.monotonic() - start) * 1000)

        if proc.returncode != 0:
            self._raise_for_subprocess_error(proc.returncode, proc.stderr or "")

        return self._parse_jsonl_output(
            stdout=proc.stdout or "",
            stderr=proc.stderr or "",
            requested_model=request.model,
            latency_ms=latency_ms,
        )

    def validate_config(self) -> List[str]:
        """Validate that the codex CLI is on PATH and auth is configured."""
        errors: List[str] = []
        if self.config.type != "codex-headless":
            errors.append(
                f"Provider '{self.provider}': type must be 'codex-headless' "
                f"(got '{self.config.type}')"
            )

        bin_name = self._codex_bin()
        if not shutil.which(bin_name):
            errors.append(
                f"Provider '{self.provider}': '{bin_name}' CLI not found on PATH. "
                f"Install with: npm install -g @openai/codex"
            )

        # Auth check is best-effort: ~/.codex/auth.json is the subscription
        # mode marker. If it's missing AND OPENAI_API_KEY is also missing,
        # the codex CLI itself will error at first call — no need to duplicate.
        # If the operator authenticates via a non-default CODEX_HOME, they
        # know what they're doing and the codex CLI handles it.
        return errors

    def health_check(self) -> bool:
        """Verify the codex CLI is reachable. Does NOT make a model call."""
        bin_name = self._codex_bin()
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

    # ---------------------------------------------------------------------
    # Internal: command construction
    # ---------------------------------------------------------------------

    def _codex_bin(self) -> str:
        """Resolve the codex CLI binary name (env var override allowed)."""
        return os.environ.get("CODEX_HEADLESS_BIN", _CODEX_BIN_DEFAULT)

    def _build_command(
        self,
        request: CompletionRequest,
        model_config,
    ) -> List[str]:
        """Build the codex exec argv. Single-shot, sandboxed read-only."""
        # cycle-104 sprint-2 T2.11 amendment: honor `extra.cli_model`
        # so a kind:cli alias (e.g. `codex-headless`) translates to the
        # real codex model identifier the CLI binary expects.
        cli_model = (model_config.extra or {}).get("cli_model") or request.model
        cmd: List[str] = [
            self._codex_bin(),
            "exec",
            "--json",
            "--skip-git-repo-check",
            "--ephemeral",
            "--sandbox",
            "read-only",
            "--ignore-user-config",
            "--model",
            cli_model,
        ]

        effort = self._resolve_reasoning_effort(request, model_config)
        if effort:
            cmd.extend(["-c", f"model_reasoning_effort={effort}"])

        # Forward additional codex `-c key=value` overrides if the operator
        # set them in ModelConfig.extra. This is the escape hatch for
        # codex-specific knobs we don't have first-class fields for yet
        # (e.g., model_provider="oss", reasoning_summaries=true).
        extra = (model_config.extra or {}).get("codex_config_overrides")
        if isinstance(extra, dict):
            for key, value in extra.items():
                # Skip the reasoning_effort key — already handled above
                if key == "reasoning_effort":
                    continue
                cmd.extend(["-c", f"{key}={value}"])

        return cmd

    def _resolve_reasoning_effort(
        self,
        request: CompletionRequest,
        model_config,
    ) -> Optional[str]:
        """Resolve reasoning_effort with explicit precedence.

        Priority:
          1. request.metadata["reasoning_effort"]    (per-call override)
          2. ModelConfig.extra["reasoning_effort"]   (per-model default)
          3. None (let codex CLI use its own default)

        Validates against the allowed-set; logs a warning + falls through on
        unknown values rather than failing the request.
        """
        candidates: List[Optional[str]] = []
        if request.metadata and isinstance(request.metadata, dict):
            candidates.append(request.metadata.get("reasoning_effort"))
        if model_config.extra and isinstance(model_config.extra, dict):
            candidates.append(model_config.extra.get("reasoning_effort"))

        for raw in candidates:
            if not raw:
                continue
            value = str(raw).strip().lower()
            if value in _ALLOWED_REASONING_EFFORTS:
                return value
            logger.warning(
                "codex-headless: ignoring unknown reasoning_effort=%r "
                "(allowed: %s)",
                raw,
                ", ".join(_ALLOWED_REASONING_EFFORTS),
            )
        return None

    def _compute_timeout(self) -> float:
        """Resolve the subprocess timeout. read_timeout wins when set."""
        # Floor protects against pathologically small values that would kill
        # codex mid-reasoning. ProviderConfig defaults (10s connect, 120s read)
        # are tuned for HTTP — codex agent loops can run longer.
        connect = max(self.config.connect_timeout, _CONNECT_TIMEOUT_FLOOR)
        read = max(self.config.read_timeout, _READ_TIMEOUT_FLOOR)
        return connect + read

    # ---------------------------------------------------------------------
    # Internal: prompt flattening
    # ---------------------------------------------------------------------

    def _build_prompt(self, messages: List[Dict[str, Any]]) -> str:
        """Flatten the message array into a single prompt for codex exec.

        codex exec is single-shot: it accepts one prompt and starts an agent
        session from there. We role-prefix each message so the model sees the
        conversational structure even though it's collapsed into one input.

        For tool messages (role='tool'), we inline the tool result; this is
        lossy compared to an OpenAI-native function_call_output block but
        sufficient for the review/skeptic/score/dissent flatline modes that
        are the primary consumers of this adapter in v1.
        """
        sections: List[str] = []
        for msg in messages:
            role = (msg.get("role") or "user").lower()
            content = msg.get("content", "")
            if isinstance(content, list):
                # Anthropic-style content blocks
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

            sections.append(f"{label}\n\n{content}".rstrip())

        return "\n\n".join(sections) + "\n"

    # ---------------------------------------------------------------------
    # Internal: JSONL parsing
    # ---------------------------------------------------------------------

    def _parse_jsonl_output(
        self,
        stdout: str,
        stderr: str,
        requested_model: str,
        latency_ms: int,
    ) -> CompletionResult:
        """Parse codex exec --json output stream.

        Event shapes observed (codex CLI 0.125.0):
          {"type":"thread.started","thread_id":"..."}
          {"type":"turn.started"}
          {"type":"item.completed","item":{"id":"...","type":"agent_message","text":"..."}}
          {"type":"item.completed","item":{"id":"...","type":"reasoning","text":"..."}}    [if surfaced]
          {"type":"turn.completed","usage":{"input_tokens":..,"output_tokens":..,
                                            "reasoning_output_tokens":..,"cached_input_tokens":..}}

        Forward-compat: unknown event types are logged once-per-process at
        DEBUG and otherwise ignored. We never raise on unknown shape — codex
        is operator-side software with frequent additive event additions.
        """
        text_parts: List[str] = []
        thinking_parts: List[str] = []
        usage_data: Dict[str, Any] = {}
        thread_id: Optional[str] = None
        actual_model: Optional[str] = None

        for raw_line in stdout.splitlines():
            line = raw_line.strip()
            if not line or not line.startswith("{"):
                continue
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                logger.debug("codex-headless: skipping non-JSON line: %r", line[:120])
                continue

            etype = event.get("type", "")
            if etype == "thread.started":
                thread_id = event.get("thread_id")
            elif etype == "item.completed":
                item = event.get("item") or {}
                item_type = item.get("type", "")
                text = item.get("text") or ""
                if not text:
                    continue
                if item_type == "agent_message":
                    text_parts.append(text)
                elif item_type == "reasoning":
                    thinking_parts.append(text)
                # other item types (e.g., tool_use) — ignored in v1
            elif etype == "turn.completed":
                usage_data = event.get("usage") or {}
            elif etype == "model":
                # forward-compat: if codex starts emitting actual model name
                actual_model = event.get("name") or event.get("model")

        content = "\n".join(text_parts)

        if not content and not stderr:
            logger.warning(
                "codex-headless: empty output from codex exec (model=%s)",
                requested_model,
            )

        usage = Usage(
            input_tokens=int(usage_data.get("input_tokens", 0) or 0),
            output_tokens=int(usage_data.get("output_tokens", 0) or 0),
            reasoning_tokens=int(usage_data.get("reasoning_output_tokens", 0) or 0),
            source="actual" if usage_data else "estimated",
        )

        return CompletionResult(
            content=content,
            tool_calls=None,
            thinking="\n".join(thinking_parts) if thinking_parts else None,
            usage=usage,
            model=actual_model or requested_model,
            latency_ms=latency_ms,
            provider=self.provider,
            interaction_id=thread_id,
        )

    # ---------------------------------------------------------------------
    # Internal: error classification
    # ---------------------------------------------------------------------

    def _raise_for_subprocess_error(self, returncode: int, stderr: str) -> None:
        """Map codex exec exit code + stderr to a typed cheval error."""
        stderr_lower = stderr.lower()

        # Subscription rate-limit: codex CLI surfaces "rate limit" in stderr
        # for both per-minute and per-hour caps.
        if "rate limit" in stderr_lower or "429" in stderr or "too many requests" in stderr_lower:
            raise RateLimitError(self.provider)

        # Auth failure — most actionable for operators new to subscription mode
        if (
            "not authenticated" in stderr_lower
            or "auth.json" in stderr_lower
            or "codex login" in stderr_lower
            or "unauthorized" in stderr_lower
        ):
            raise ConfigError(
                f"codex CLI not authenticated. Run: codex login. "
                f"(Auth file: {_CODEX_AUTH_FILE}; "
                f"stderr: {stderr.strip()[:300]})"
            )

        # Anything else: surface as provider-unavailable so retry/fallback
        # logic in cheval can react.
        snippet = stderr.strip()[:500] or f"exit code {returncode}, no stderr"
        raise ProviderUnavailableError(
            self.provider,
            f"codex exec failed (exit {returncode}): {snippet}",
        )
