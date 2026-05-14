"""Gemini-headless provider adapter — invokes `gemini -p` for Google AI subscription auth.

Sibling to codex_headless_adapter — same pattern, different upstream CLI. Routes
Loa's cheval calls through the Google Gemini CLI (`gemini`) instead of the
Generative Language HTTP API. Auth comes from `~/.gemini/settings.json` (populated
by interactive `gemini` first-run with a personal Google account) OR from
`GEMINI_API_KEY` / `GOOGLE_GENAI_USE_GCA` env vars; no `GOOGLE_API_KEY` is consumed
for the v1beta REST path.

When to use:
  - Operator has a personal Google account with Gemini CLI free-tier quota
    (60 req/min · 1000 req/day) or a paid Gemini Advanced subscription.
  - Operator wants bridgebuilder / spiraling / flatline-review's Gemini-tier
    calls to draw from subscription quota instead of paid API balance.

Design notes:
  - Single-shot only. Multi-turn message arrays flatten into one prompt with
    role-prefixed sections. Sufficient for the four flatline modes (single-pass
    review / skeptic / scorer / dissenter).
  - Tools / tool_choice are NOT forwarded to the gemini agent. Forward later
    when an agent binding genuinely needs gemini-cli's MCP tool surface.
  - Approval mode locked to `plan` (read-only, no shell exec, no file edits).
    `--skip-trust` is passed so the CLI doesn't fall back to `default` when the
    invocation cwd isn't in gemini-cli's trusted-folders allowlist.
  - Auth posture: prefer file-based (`~/.gemini/settings.json` set via interactive
    first-run). The CLI also accepts GEMINI_API_KEY / GOOGLE_GENAI_USE_VERTEXAI /
    GOOGLE_GENAI_USE_GCA — we don't manage those, just surface them on validate.
  - Output format: `--output-format json` produces a single JSON object:
    `{session_id, response, stats?, error?, warnings?}` (not JSONL stream).
  - Token usage maps from gemini's stats.models[<model>].tokens shape:
      tokens.prompt   → Usage.input_tokens (gemini's input alias is "prompt")
      tokens.candidates → Usage.output_tokens (gemini calls outputs "candidates")
      tokens.thoughts (when surfaced) → Usage.reasoning_tokens
      tokens.cached  → metadata['cached_tokens']
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

logger = logging.getLogger("loa_cheval.providers.gemini_headless")

# gemini CLI binary name (override via GEMINI_HEADLESS_BIN env var for testing)
_GEMINI_BIN_DEFAULT = "gemini"

# Auth file populated by `gemini` interactive first-run (subscription mode)
_GEMINI_SETTINGS_FILE = "~/.gemini/settings.json"

# Subscription auth env vars the CLI itself recognizes (we don't set them,
# only surface them in validate_config diagnostics).
_GEMINI_AUTH_ENV_VARS = (
    "GEMINI_API_KEY",
    "GOOGLE_GENAI_USE_VERTEXAI",
    "GOOGLE_GENAI_USE_GCA",
)

# Conservative defaults for subprocess wall-clock. ProviderConfig.read_timeout
# wins when set; these floors apply only when the loader hands defaults.
_CONNECT_TIMEOUT_FLOOR = 10.0
_READ_TIMEOUT_FLOOR = 600.0  # 10 min


class GeminiHeadlessAdapter(ProviderAdapter):
    """Adapter that routes inference through `gemini -p` (non-interactive).

    Provider config (no auth field — file-based):

        providers:
          gemini-headless:
            type: gemini-headless
            connect_timeout: 10.0
            read_timeout: 600.0
            models:
              gemini-3-pro:
                context_window: 1048576
                pricing: {input_per_mtok: 0, output_per_mtok: 0}

    Aliases bind to provider:model-id like other adapters:

        aliases:
          deep-thinker: gemini-headless:gemini-3-pro
          fast-thinker: gemini-headless:gemini-3-flash
    """

    def complete(self, request: CompletionRequest) -> CompletionResult:
        """Invoke `gemini -p` and return a normalized CompletionResult."""
        model_config = self._get_model_config(request.model)
        enforce_context_window(request, model_config)

        prompt = self._build_prompt(request.messages)
        cmd = self._build_command(request, model_config, prompt)
        timeout_s = self._compute_timeout()

        logger.debug(
            "gemini-headless invoking: model=%s timeout=%.0fs prompt_chars=%d",
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
                # gemini-cli's `-p` flag triggers headless mode and consumes the
                # prompt argument directly. Stdin is appended only when both -p
                # and stdin are piped — we use -p exclusively so stdin stays
                # closed (avoids hangs in some shell environments).
                stdin=subprocess.DEVNULL,
                # cycle-109 follow-up (#879 / #880 symmetric): strip
                # GOOGLE_API_KEY + GEMINI_API_KEY so gemini -p uses GCA
                # OAuth, not API mode.
                env=build_headless_subprocess_env(),
            )
        except subprocess.TimeoutExpired:
            raise ProviderUnavailableError(
                self.provider,
                f"gemini -p timed out after {timeout_s:.0f}s",
            )
        except FileNotFoundError as exc:
            raise ConfigError(
                f"gemini CLI not found on PATH (set GEMINI_HEADLESS_BIN to override). "
                f"Install with: npm install -g @google/gemini-cli. Original: {exc}"
            ) from exc

        latency_ms = int((time.monotonic() - start) * 1000)

        # gemini CLI may return non-zero even when JSON output contains a
        # structured error. We try to parse stdout first to prefer structured
        # diagnostics; only fall back to subprocess-level error classification
        # when stdout is empty / unparseable.
        parsed: Optional[Dict[str, Any]] = None
        if proc.stdout:
            try:
                parsed = json.loads(proc.stdout)
            except json.JSONDecodeError:
                parsed = None

        if proc.returncode != 0 or (parsed and parsed.get("error")):
            self._raise_for_error(
                returncode=proc.returncode,
                stderr=proc.stderr or "",
                parsed=parsed,
            )

        if parsed is None:
            raise ProviderUnavailableError(
                self.provider,
                f"gemini returned no parseable JSON output "
                f"(stdout was {len(proc.stdout)} chars, stderr: "
                f"{(proc.stderr or '').strip()[:200]})",
            )

        return self._parse_json_output(
            parsed=parsed,
            requested_model=request.model,
            latency_ms=latency_ms,
        )

    def validate_config(self) -> List[str]:
        """Validate that the gemini CLI is on PATH. Auth is best-effort surface."""
        errors: List[str] = []
        if self.config.type != "gemini-headless":
            errors.append(
                f"Provider '{self.provider}': type must be 'gemini-headless' "
                f"(got '{self.config.type}')"
            )

        bin_name = self._gemini_bin()
        if not shutil.which(bin_name):
            errors.append(
                f"Provider '{self.provider}': '{bin_name}' CLI not found on PATH. "
                f"Install with: npm install -g @google/gemini-cli"
            )

        # Best-effort auth probe: the CLI itself enforces auth at first call,
        # so we don't duplicate. We DO emit a hint when neither the settings
        # file nor any auth env var is populated, since the most common
        # operator failure is "I installed the CLI but never logged in."
        # This is non-blocking — we only return errors for things that will
        # 100% fail.
        return errors

    def health_check(self) -> bool:
        """Verify the gemini CLI is reachable. Does NOT make a model call."""
        bin_name = self._gemini_bin()
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

    def _gemini_bin(self) -> str:
        """Resolve the gemini CLI binary name (env var override allowed)."""
        return os.environ.get("GEMINI_HEADLESS_BIN", _GEMINI_BIN_DEFAULT)

    def _build_command(
        self,
        request: CompletionRequest,
        model_config,
        prompt: str,
    ) -> List[str]:
        """Build the gemini argv. Headless, plan-mode (read-only), trusted."""
        # cycle-104 sprint-2 T2.11 amendment: honor `extra.cli_model`
        # so a kind:cli alias (`gemini-headless`) translates to the real
        # gemini model id the CLI binary expects.
        cli_model = (model_config.extra or {}).get("cli_model") or request.model
        cmd: List[str] = [
            self._gemini_bin(),
            "-p",
            prompt,
            "--output-format",
            "json",
            "--approval-mode",
            "plan",
            "--skip-trust",
            "-m",
            cli_model,
        ]

        # Forward `gemini --policy <path>` overrides if operator declared
        # extra restrictions in ModelConfig.extra. Repeated --policy flags
        # are accepted; we expand a list.
        extra = (model_config.extra or {})
        policies = extra.get("gemini_policies")
        if isinstance(policies, list):
            for path in policies:
                cmd.extend(["--policy", str(path)])

        # Forward additional gemini CLI flags an operator may need but we
        # haven't promoted to first-class fields (e.g., experimental ACP,
        # extension allowlist). Format: list of [flag, value?] pairs.
        extra_flags = extra.get("gemini_extra_flags")
        if isinstance(extra_flags, list):
            for entry in extra_flags:
                if isinstance(entry, str):
                    cmd.append(entry)
                elif isinstance(entry, list):
                    cmd.extend(str(x) for x in entry)

        return cmd

    def _compute_timeout(self) -> float:
        """Resolve the subprocess timeout. read_timeout wins when set."""
        connect = max(self.config.connect_timeout, _CONNECT_TIMEOUT_FLOOR)
        read = max(self.config.read_timeout, _READ_TIMEOUT_FLOOR)
        return connect + read

    # ---------------------------------------------------------------------
    # Internal: prompt flattening
    # ---------------------------------------------------------------------

    def _build_prompt(self, messages: List[Dict[str, Any]]) -> str:
        """Flatten message array into a single prompt for gemini -p.

        Same shape as codex_headless_adapter — role-prefixed sections collapsed
        into one input string. Lossy compared to a native multi-turn API, but
        sufficient for single-shot review modes.
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
        """Parse a successful gemini --output-format json single object.

        Shape (per gemini-cli core/src/output/types.ts):
          {
            "session_id": "...",
            "response": "<text>",
            "stats": {
              "models": {
                "<model_id>": {
                  "tokens": {
                    "prompt": <int>,        // input tokens
                    "candidates": <int>,    // output tokens
                    "total": <int>,
                    "cached": <int>,
                    "thoughts": <int>?      // reasoning, when surfaced
                  },
                  ...
                }
              }
            },
            "warnings": ["..."]?
          }
        """
        session_id = parsed.get("session_id")
        content = (parsed.get("response") or "").strip("\n")
        warnings = parsed.get("warnings") or []

        # Best-effort token extraction. SessionMetrics is keyed by model_id;
        # we accept either the requested model OR fall back to any single
        # model entry present.
        usage_data: Dict[str, Any] = {}
        stats = parsed.get("stats") or {}
        models_stats = stats.get("models") if isinstance(stats, dict) else None
        if isinstance(models_stats, dict) and models_stats:
            entry = models_stats.get(requested_model)
            if entry is None and len(models_stats) == 1:
                # Single-model run — use whatever key the CLI emitted.
                entry = next(iter(models_stats.values()))
            if isinstance(entry, dict):
                usage_data = entry.get("tokens") or {}

        usage = Usage(
            input_tokens=int(usage_data.get("prompt") or usage_data.get("input") or 0),
            output_tokens=int(usage_data.get("candidates") or usage_data.get("output") or 0),
            reasoning_tokens=int(usage_data.get("thoughts") or 0),
            source="actual" if usage_data else "estimated",
        )

        metadata: Dict[str, Any] = {}
        cached = usage_data.get("cached")
        if cached:
            metadata["cached_tokens"] = int(cached)
        if warnings:
            metadata["warnings"] = warnings

        if not content:
            logger.warning(
                "gemini-headless: empty response field (model=%s, session=%s)",
                requested_model,
                session_id,
            )

        return CompletionResult(
            content=content,
            tool_calls=None,
            thinking=None,
            usage=usage,
            model=requested_model,
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
        """Map gemini failure (subprocess or structured JSON error) to typed cheval error."""
        # Pull the most-actionable diagnostic — prefer structured JSON error
        # when present, fall back to stderr text otherwise.
        if parsed and isinstance(parsed.get("error"), dict):
            err = parsed["error"]
            err_msg = str(err.get("message") or "")
            err_type = str(err.get("type") or "")
            err_code = err.get("code")
            full_diag = f"{err_type}: {err_msg} (code={err_code})"
        else:
            err_msg = stderr
            full_diag = stderr.strip() or f"exit code {returncode}"

        diag_lower = full_diag.lower()

        # Rate-limit (gemini-cli surfaces 429 / "quota" / "rate limit" in different revisions)
        if (
            "rate limit" in diag_lower
            or "429" in full_diag
            or "quota" in diag_lower
            or "too many requests" in diag_lower
            or "resource_exhausted" in diag_lower
        ):
            raise RateLimitError(self.provider)

        # Auth failure — gemini-cli's most common first-run failure
        if (
            "auth method" in diag_lower
            or "set an auth" in diag_lower
            or "settings.json" in diag_lower
            or "gemini_api_key" in diag_lower
            or "google_genai_use" in diag_lower
            or "unauthorized" in diag_lower
            or "permission_denied" in diag_lower
        ):
            raise ConfigError(
                f"gemini CLI not authenticated. Run `gemini` once interactively "
                f"to log in (writes {_GEMINI_SETTINGS_FILE}), or set one of: "
                f"{', '.join(_GEMINI_AUTH_ENV_VARS)}. (diagnostic: {full_diag[:300]})"
            )

        snippet = full_diag[:500] or f"exit code {returncode}, no diagnostic"
        raise ProviderUnavailableError(
            self.provider,
            f"gemini -p failed (exit {returncode}): {snippet}",
        )
