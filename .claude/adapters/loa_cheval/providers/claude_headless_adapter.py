"""Claude-headless provider adapter — invokes `claude -p` for Claude subscription auth.

Third sibling to codex_headless_adapter and gemini_headless_adapter — same
shape, different upstream CLI. Routes Loa's cheval calls through the Claude
Code CLI (`claude`) instead of the Anthropic Messages HTTP API. Auth comes
from Claude Code's OAuth-managed credential store (populated by `claude
/login`); no `ANTHROPIC_API_KEY` is consumed for the v1/messages REST path.

When to use:
  - Operator has a Claude Max / Pro / Team subscription and wants flatline /
    bridgebuilder Claude-tier calls (opus / sonnet) to draw against the
    subscription quota instead of the API balance.
  - Operator wants a single-process operator workflow (no API key juggling).

Design notes (sibling of codex / gemini headless):
  - Single-shot only. Multi-turn message arrays flatten into one prompt
    with role-prefixed sections. Sufficient for review / skeptic / scorer /
    dissenter (single-shot).
  - Tools are explicitly disabled (`--tools ""`). The model-router use case
    is pure inference; the Claude Code agent loop must not touch operator
    files. Operators wanting tool-use should not use this adapter — they
    want the existing AnthropicAdapter (HTTP API) instead.
  - Permission mode is `plan` (read-only) as defense in depth, even with
    `--tools ""`.
  - `--no-session-persistence` keeps each call hermetic. No on-disk state.
  - **DO NOT pass `--bare`**: it strips OAuth and forces ANTHROPIC_API_KEY,
    which defeats the subscription-auth purpose of this adapter.
  - **System-prompt overhead**: by default, Claude Code injects ~14K tokens
    of agent-persona system prompt into every -p call. On Max subscription
    that's quota-cost only. Operators wanting to trim the overhead can pass
    a custom `system_prompt` via `ModelConfig.extra` (replaces default) or
    `append_system_prompt` (adds to default).
  - Effort threading: `low | medium | high | xhigh | max` maps 1:1 to
    `--effort`. Wider range than codex (codex tops out at xhigh).
  - Single JSON object output, NOT JSONL stream — different from codex.
  - Token mapping from `usage` block:
      input_tokens                 → Usage.input_tokens (NEW input only)
      output_tokens                → Usage.output_tokens
      cache_read_input_tokens      → metadata.cache_read_input_tokens
      cache_creation_input_tokens  → metadata.cache_creation_input_tokens
    Cache tokens are NOT summed into Usage.input_tokens — that would
    double-count for cost accounting since cache reads/writes are billed at
    different rates.
"""

from __future__ import annotations

import json
import logging
import os
import shutil
import subprocess
import time
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

logger = logging.getLogger("loa_cheval.providers.claude_headless")

# Allowed effort levels per `claude --help` (>= 2.1.x)
_ALLOWED_EFFORTS = ("low", "medium", "high", "xhigh", "max")

# claude CLI binary name (override via CLAUDE_HEADLESS_BIN env var for testing)
_CLAUDE_BIN_DEFAULT = "claude"

# Auth indicator (Claude Code manages this internally; operator runs `claude /login`)
_CLAUDE_LOGIN_HINT = "claude /login"

# Conservative defaults for subprocess wall-clock. ProviderConfig.read_timeout
# wins when set; these floors apply only when the loader hands defaults.
_CONNECT_TIMEOUT_FLOOR = 10.0
_READ_TIMEOUT_FLOOR = 600.0  # 10 min — Claude reasoning passes can be slow


class ClaudeHeadlessAdapter(ProviderAdapter):
    """Adapter that routes inference through `claude -p` (non-interactive).

    Provider config (no auth field — OAuth-managed):

        providers:
          claude-headless:
            type: claude-headless
            connect_timeout: 10.0
            read_timeout: 600.0
            models:
              claude-opus-4-7:
                context_window: 200000
                pricing: {input_per_mtok: 0, output_per_mtok: 0}
                extra:
                  effort: high

    Aliases bind to provider:model-id like other adapters:

        aliases:
          opus: claude-headless:claude-opus-4-7
          cheap: claude-headless:claude-sonnet-4-6
    """

    # Cycle-110 FR-2.3 — subscription-CLI dispatch; circuit-breaker writes
    # route to the (anthropic, headless) bucket.
    auth_type: str = "headless"

    def complete(self, request: CompletionRequest) -> CompletionResult:
        """Invoke `claude -p` and return a normalized CompletionResult."""
        model_config = self._get_model_config(request.model)
        enforce_context_window(request, model_config)

        prompt = self._build_prompt(request.messages)
        cmd = self._build_command(request, model_config, prompt)
        timeout_s = self._compute_timeout()

        logger.debug(
            "claude-headless invoking: model=%s timeout=%.0fs prompt_chars=%d",
            request.model,
            timeout_s,
            len(prompt),
        )

        start = time.monotonic()
        try:
            proc = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=timeout_s,
                check=False,
                # claude -p reads prompt from argv (we passed it via the cmd
                # array). Stdin stays closed to avoid hangs.
                stdin=subprocess.DEVNULL,
                # cycle-109 follow-up (#879 / #880): strip ANTHROPIC_API_KEY
                # so claude -p uses OAuth subscription, not API mode.
                env=build_headless_subprocess_env(),
            )
        except subprocess.TimeoutExpired:
            raise ProviderUnavailableError(
                self.provider,
                f"claude -p timed out after {timeout_s:.0f}s",
            )
        except FileNotFoundError as exc:
            raise ConfigError(
                f"claude CLI not found on PATH (set CLAUDE_HEADLESS_BIN to override). "
                f"Install with: npm install -g @anthropic-ai/claude-code. Original: {exc}"
            ) from exc

        latency_ms = int((time.monotonic() - start) * 1000)

        # Claude Code emits a single structured JSON object even on errors.
        # Parse stdout first; only fall back to subprocess-level error
        # classification when stdout is empty / unparseable.
        parsed: Optional[Dict[str, Any]] = None
        if proc.stdout:
            try:
                parsed = json.loads(proc.stdout)
            except json.JSONDecodeError:
                parsed = None

        if proc.returncode != 0 or (parsed and parsed.get("is_error")):
            self._raise_for_error(
                returncode=proc.returncode,
                stderr=proc.stderr or "",
                parsed=parsed,
            )

        if parsed is None:
            raise ProviderUnavailableError(
                self.provider,
                f"claude returned no parseable JSON output "
                f"(stdout was {len(proc.stdout)} chars, stderr: "
                f"{(proc.stderr or '').strip()[:200]})",
            )

        return self._parse_json_output(
            parsed=parsed,
            requested_model=request.model,
            latency_ms=latency_ms,
        )

    def validate_config(self) -> List[str]:
        """Validate that the claude CLI is on PATH."""
        errors: List[str] = []
        if self.config.type != "claude-headless":
            errors.append(
                f"Provider '{self.provider}': type must be 'claude-headless' "
                f"(got '{self.config.type}')"
            )

        bin_name = self._claude_bin()
        if not shutil.which(bin_name):
            errors.append(
                f"Provider '{self.provider}': '{bin_name}' CLI not found on PATH. "
                f"Install with: npm install -g @anthropic-ai/claude-code"
            )

        # Auth check is deferred to the CLI itself — `claude -p` returns a
        # structured "Not logged in" error which the adapter classifies as
        # ConfigError with a `claude /login` hint.
        return errors

    def health_check(self) -> bool:
        """Verify the claude CLI is reachable. Does NOT make a model call."""
        bin_name = self._claude_bin()
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

    def _claude_bin(self) -> str:
        """Resolve the claude CLI binary name (env var override allowed)."""
        return os.environ.get("CLAUDE_HEADLESS_BIN", _CLAUDE_BIN_DEFAULT)

    def _build_command(
        self,
        request: CompletionRequest,
        model_config,
        prompt: str,
    ) -> List[str]:
        """Build the claude argv. Headless, plan-mode (read-only), no tools."""
        # cycle-104 sprint-2 T2.11 amendment: when the chain entry is a
        # kind:cli alias (e.g. `claude-headless`) the CLI binary doesn't
        # recognize the Loa alias as a model name. Honor `extra.cli_model`
        # if declared so the operator can map the alias to a real CLI
        # model identifier (e.g. `sonnet`, `opus`).
        cli_model = (model_config.extra or {}).get("cli_model") or request.model
        cmd: List[str] = [
            self._claude_bin(),
            "-p",
            prompt,
            "--output-format",
            "json",
            "--permission-mode",
            "plan",
            "--no-session-persistence",
            # Disable all tools: pure inference, no agent loop side effects.
            # Empty string is the documented "disable all" sentinel.
            "--tools",
            "",
            "--model",
            cli_model,
        ]

        effort = self._resolve_effort(request, model_config)
        if effort:
            cmd.extend(["--effort", effort])

        extra = (model_config.extra or {})

        # System prompt overrides — `system_prompt` REPLACES the default
        # Claude Code agent prompt (saves ~14K cache tokens but loses agent
        # context). `append_system_prompt` ADDS to the default. Mutually
        # compatible with the CLI; we pass whichever is set.
        if extra.get("system_prompt"):
            cmd.extend(["--system-prompt", str(extra["system_prompt"])])
        if extra.get("append_system_prompt"):
            cmd.extend(["--append-system-prompt", str(extra["append_system_prompt"])])

        # Allow operators to explicitly enable a curated tool set (overrides
        # the default `--tools ""`). Format: list of tool names. We rebuild
        # the tools flag rather than appending so the deny-all default doesn't
        # clobber it on the CLI side.
        allowed_tools = extra.get("allowed_tools")
        if isinstance(allowed_tools, list) and allowed_tools:
            # Find and replace the "--tools" + "" pair we set above.
            try:
                idx = cmd.index("--tools")
                cmd[idx + 1] = ",".join(str(t) for t in allowed_tools)
            except ValueError:
                cmd.extend(["--tools", ",".join(str(t) for t in allowed_tools)])

        # Forward additional `claude` flags an operator may need but we
        # haven't promoted to first-class fields. Format: list of strings or
        # [flag, value] pairs.
        extra_flags = extra.get("claude_extra_flags")
        if isinstance(extra_flags, list):
            for entry in extra_flags:
                if isinstance(entry, str):
                    cmd.append(entry)
                elif isinstance(entry, list):
                    cmd.extend(str(x) for x in entry)

        return cmd

    def _resolve_effort(
        self,
        request: CompletionRequest,
        model_config,
    ) -> Optional[str]:
        """Resolve effort with explicit precedence (matches codex pattern).

        Priority:
          1. request.metadata["effort"] OR ["reasoning_effort"]
          2. ModelConfig.extra["effort"] OR ["reasoning_effort"]
          3. None (let claude CLI use its own default)
        """
        candidates: List[Optional[str]] = []
        if request.metadata and isinstance(request.metadata, dict):
            candidates.append(request.metadata.get("effort"))
            candidates.append(request.metadata.get("reasoning_effort"))
        if model_config.extra and isinstance(model_config.extra, dict):
            candidates.append(model_config.extra.get("effort"))
            candidates.append(model_config.extra.get("reasoning_effort"))

        for raw in candidates:
            if not raw:
                continue
            value = str(raw).strip().lower()
            if value in _ALLOWED_EFFORTS:
                return value
            logger.warning(
                "claude-headless: ignoring unknown effort=%r (allowed: %s)",
                raw,
                ", ".join(_ALLOWED_EFFORTS),
            )
        return None

    def _compute_timeout(self) -> float:
        """Resolve the subprocess timeout. read_timeout wins when set."""
        connect = max(self.config.connect_timeout, _CONNECT_TIMEOUT_FLOOR)
        read = max(self.config.read_timeout, _READ_TIMEOUT_FLOOR)
        return connect + read

    # ---------------------------------------------------------------------
    # Internal: prompt flattening
    # ---------------------------------------------------------------------

    def _build_prompt(self, messages: List[Dict[str, Any]]) -> str:
        """Flatten message array into a single prompt for claude -p.

        Same pattern as codex/gemini headless — role-prefixed sections
        collapsed into one input string. For multi-turn conversations the
        operator can use `--system-prompt` (via ModelConfig.extra) to
        override the default Claude Code system prompt with a custom
        conversation-context primer.
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
    # Internal: JSON parsing
    # ---------------------------------------------------------------------

    def _parse_json_output(
        self,
        parsed: Dict[str, Any],
        requested_model: str,
        latency_ms: int,
    ) -> CompletionResult:
        """Parse a successful claude --output-format json single object.

        Shape (per Claude Code 2.1.x):
          {
            "type": "result",
            "subtype": "success",
            "is_error": false,
            "result": "<text>",                  ← actual response content
            "stop_reason": "end_turn",
            "session_id": "...",
            "total_cost_usd": 0.05,              ← API-equivalent cost (informational on Max)
            "usage": {
              "input_tokens": <int>,             ← NEW input only (not cache)
              "output_tokens": <int>,
              "cache_read_input_tokens": <int>,
              "cache_creation_input_tokens": <int>,
              ...
            },
            "modelUsage": {                      ← per-model breakdown
              "<model_id>": {
                "inputTokens": ..., "outputTokens": ..., "costUSD": ..., ...
              }
            },
            "permission_denials": [],
            "uuid": "..."
          }
        """
        session_id = parsed.get("session_id") or parsed.get("uuid")
        content = (parsed.get("result") or "").strip("\n")
        stop_reason = parsed.get("stop_reason")

        usage_data = parsed.get("usage") or {}
        usage = Usage(
            input_tokens=int(usage_data.get("input_tokens") or 0),
            output_tokens=int(usage_data.get("output_tokens") or 0),
            # Anthropic's API doesn't surface a separate reasoning_output_tokens
            # field through Claude Code yet — when it does, map it here.
            reasoning_tokens=int(usage_data.get("reasoning_output_tokens") or 0),
            source="actual" if usage_data else "estimated",
        )

        metadata: Dict[str, Any] = {}
        cache_read = usage_data.get("cache_read_input_tokens")
        if cache_read:
            metadata["cache_read_input_tokens"] = int(cache_read)
        cache_creation = usage_data.get("cache_creation_input_tokens")
        if cache_creation:
            metadata["cache_creation_input_tokens"] = int(cache_creation)

        cost = parsed.get("total_cost_usd")
        if cost is not None:
            metadata["total_cost_usd"] = cost

        if stop_reason:
            metadata["stop_reason"] = stop_reason

        permission_denials = parsed.get("permission_denials") or []
        if permission_denials:
            metadata["permission_denials"] = permission_denials

        # Claude Code's modelUsage field reports the model that actually ran.
        # Capture it for the CompletionResult.model field — falls back to
        # requested model when absent.
        actual_model = requested_model
        model_usage = parsed.get("modelUsage")
        if isinstance(model_usage, dict) and model_usage:
            actual_model = next(iter(model_usage.keys()), requested_model)

        if not content:
            logger.warning(
                "claude-headless: empty response (model=%s, session=%s, stop=%s)",
                requested_model,
                session_id,
                stop_reason,
            )

        return CompletionResult(
            content=content,
            tool_calls=None,
            thinking=None,
            usage=usage,
            model=actual_model,
            latency_ms=latency_ms,
            provider=self.provider,
            interaction_id=session_id,
            metadata=metadata,
        )

    # ---------------------------------------------------------------------
    # Internal: error classification
    # ---------------------------------------------------------------------

    def _raise_for_error(
        self,
        returncode: int,
        stderr: str,
        parsed: Optional[Dict[str, Any]],
    ) -> None:
        """Map claude failure to a typed cheval error.

        Claude Code's -p mode emits structured JSON even for errors:
          - is_error: true
          - result: "<error message>"
          - api_error_status: <number?>
        We prefer that over stderr when present.
        """
        if parsed and isinstance(parsed, dict) and parsed.get("is_error"):
            err_msg = str(parsed.get("result") or "")
            api_status = parsed.get("api_error_status")
            full_diag = f"{err_msg}" + (f" (api_status={api_status})" if api_status else "")
        else:
            err_msg = stderr
            full_diag = stderr.strip() or f"exit code {returncode}"

        diag_lower = full_diag.lower()

        # Rate-limit / overload — Anthropic returns 429 + "rate limit" or
        # 529 + "overloaded" when the org / subscription quota is saturated.
        if (
            "rate limit" in diag_lower
            or "429" in full_diag
            or "529" in full_diag
            or "overloaded" in diag_lower
            or "too many requests" in diag_lower
            or "quota" in diag_lower
        ):
            raise RateLimitError(self.provider)

        # Auth failure — Claude Code's most common first-run failure
        if (
            "not logged in" in diag_lower
            or "/login" in diag_lower
            or "unauthorized" in diag_lower
            or "401" in full_diag
            or "authentication" in diag_lower
            or "credential" in diag_lower
        ):
            raise ConfigError(
                f"claude CLI not authenticated. Run: {_CLAUDE_LOGIN_HINT}. "
                f"(diagnostic: {full_diag[:300]})"
            )

        snippet = full_diag[:500] or f"exit code {returncode}, no diagnostic"
        raise ProviderUnavailableError(
            self.provider,
            f"claude -p failed (exit {returncode}): {snippet}",
        )
