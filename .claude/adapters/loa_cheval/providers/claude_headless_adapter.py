"""Claude-headless provider adapter — invokes `claude -p` for Claude subscription auth.

Third sibling to codex_headless_adapter and gemini_headless_adapter — same
shape, different upstream CLI. Routes Loa's cheval calls through the Claude
Code CLI (`claude`) instead of the Anthropic Messages HTTP API. Auth comes
from Claude Code's OAuth-managed credential store (populated by `claude
/login`); no `ANTHROPIC_API_KEY` is consumed for the v1/messages REST path.

When to use:
  - Operator has a Claude Max / Pro / Team subscription and wants flatline /
    bridgebuilder Claude-tier calls (opus / sonnet) to draw against the
    CLI's OAuth-managed account. Billing depends on the account and upstream
    behavior; OAuth alone does not establish that a call is free (KF-020).
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
    of agent-persona system prompt into every -p call. That overhead can affect
    quota and CLI-reported cost. Operators wanting to trim it can pass
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
import shutil  # Preserve the provider module's shutil.which patch point.
import subprocess
import threading
from decimal import Decimal
from typing import Any, Dict, List, Optional

from loa_cheval.metering.pricing import cli_cost_micro_usd
from loa_cheval.providers.headless_cli import HeadlessCLIAdapter
from loa_cheval.providers.base import (
    run_subprocess_pgkill,
)
from loa_cheval.types import (
    CompletionRequest,
    CompletionResult,
    AuthRevokedError,
    ConfigError,
    ProviderUnavailableError,
    RateLimitError,
    Usage,
)

logger = logging.getLogger("loa_cheval.providers.claude_headless")
_CLI_COST_WARNED = False
_CLI_COST_WARN_LOCK = threading.Lock()

# Allowed effort levels per `claude --help` (>= 2.1.x)
_ALLOWED_EFFORTS = ("low", "medium", "high", "xhigh", "max")

# cycle-124 FR-7: `claude -p --json-schema <schema>` (Claude Code ≥ 2.1.27x)
# returns the enforced object in `structured_output`. Probed ONCE per process
# from `claude --help`; an older CLI simply runs unenforced (never an
# unknown-flag failure).
_JSON_SCHEMA_FLAG: Optional[bool] = None
_JSON_SCHEMA_FLAG_LOCK = threading.Lock()


def _is_schema_rejection(proc) -> bool:
    text = (getattr(proc, "stderr", "") or "") + (getattr(proc, "stdout", "") or "")
    return "not a valid JSON Schema" in text


def _cli_supports_json_schema(cli_bin: str) -> bool:
    global _JSON_SCHEMA_FLAG
    with _JSON_SCHEMA_FLAG_LOCK:
        if _JSON_SCHEMA_FLAG is None:
            try:
                proc = subprocess.run(
                    [cli_bin, "--help"], capture_output=True, text=True, timeout=20, check=False,
                )
                _JSON_SCHEMA_FLAG = "--json-schema" in ((proc.stdout or "") + (proc.stderr or ""))
            except Exception:  # noqa: BLE001 — missing binary etc.: treated as unsupported
                _JSON_SCHEMA_FLAG = False
        return bool(_JSON_SCHEMA_FLAG)

# claude CLI binary name (override via CLAUDE_HEADLESS_BIN env var for testing)
_CLAUDE_BIN_DEFAULT = "claude"

# Auth indicator (Claude Code manages this internally; operator runs `claude /login`)
_CLAUDE_LOGIN_HINT = "claude /login"


class ClaudeHeadlessAdapter(HeadlessCLIAdapter):
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

    _cli_type = "claude-headless"
    _cli_name = "claude"
    _command_label = "claude -p"
    _install_hint = 'Install with: npm install -g @anthropic-ai/claude-code'
    _logger = logger

    def _run_subprocess(self, command, **kwargs):
        # Keep the provider's subprocess seam available to callers and tests.
        proc = run_subprocess_pgkill(command, **kwargs)
        # cycle-124 FR-7: the CLI validates the schema itself ("--json-schema
        # is not a valid JSON Schema: …", measured live 2026-09-18 on a
        # 2020-12 `$schema` URI). That is a schema/CLI mismatch, not a model
        # or transport failure — retry ONCE unenforced so the voice still
        # answers (schema_enforced reports false) instead of dropping out of
        # the chain.
        if (
            proc.returncode != 0
            and "--json-schema" in command
            and _is_schema_rejection(proc)
        ):
            logger.warning(
                "claude rejected --json-schema (%s); retrying once without it (unenforced)",
                ((proc.stderr or proc.stdout or "").strip().splitlines() or ["?"])[0][:200],
            )
            idx = list(command).index("--json-schema")
            stripped = list(command[:idx]) + list(command[idx + 2:])
            proc = run_subprocess_pgkill(stripped, **kwargs)
        return proc

    def _finish_completion(
        self, proc: subprocess.CompletedProcess, request: CompletionRequest, latency_ms: int,
    ) -> CompletionResult:
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

    # ---------------------------------------------------------------------
    # Internal: command construction
    # ---------------------------------------------------------------------

    def _cli_bin(self) -> str:
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
            self._cli_bin(),
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

        # cycle-124 FR-7: forward the schema compactly when the CLI knows the
        # flag; otherwise the call proceeds unenforced (schema_enforced false).
        if request.output_schema is not None and _cli_supports_json_schema(self._cli_bin()):
            cmd.extend(["--json-schema", json.dumps(request.output_schema, separators=(",", ":"))])

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
          1. request.effort (cheval --effort, cycle-124)
          2. request.metadata["effort"] OR ["reasoning_effort"]
          3. ModelConfig.extra["effort"] OR ["reasoning_effort"]
          4. None (let claude CLI use its own default)
        """
        candidates: List[Optional[str]] = []
        # cycle-124 FR-2: cheval threads `--effort` onto CompletionRequest.effort
        # (validated against the same levels); it is the first candidate so the
        # CLI hop honours what the MODELINV envelope records.
        candidates.append(getattr(request, "effort", None))
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
            "total_cost_usd": 0.05,              ← CLI-reported cost; billing unverified (KF-020)
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
        # cycle-124 FR-7: with --json-schema the enforced object lives in
        # `structured_output` (the `result` string may be prose or empty);
        # prefer it, compactly serialized, and record the enforcement.
        structured = parsed.get("structured_output")
        if structured is not None:
            content = json.dumps(structured, separators=(",", ":"))

        usage_data = parsed.get("usage") or {}
        usage = Usage(
            input_tokens=int(usage_data.get("input_tokens") or 0),
            output_tokens=int(usage_data.get("output_tokens") or 0),
            # Anthropic's API doesn't surface a separate reasoning_output_tokens
            # field through Claude Code yet — when it does, map it here.
            reasoning_tokens=int(usage_data.get("reasoning_output_tokens") or 0),
            # cycle-124 FR-4: cache telemetry on Usage as well as metadata so
            # the MODELINV / CLI-JSON capture reads one place for every transport.
            cache_read_input_tokens=int(usage_data.get("cache_read_input_tokens") or 0),
            cache_creation_input_tokens=int(usage_data.get("cache_creation_input_tokens") or 0),
            source="actual" if usage_data else "estimated",
        )

        metadata: Dict[str, Any] = {"schema_enforced": structured is not None}
        cache_read = usage_data.get("cache_read_input_tokens")
        if cache_read:
            metadata["cache_read_input_tokens"] = int(cache_read)
        cache_creation = usage_data.get("cache_creation_input_tokens")
        if cache_creation:
            metadata["cache_creation_input_tokens"] = int(cache_creation)

        cost = parsed.get("total_cost_usd")
        if cost is not None:
            metadata["total_cost_usd"] = cost
        cost_micro = cli_cost_micro_usd(cost)
        if cost_micro is not None:
            metadata["pricing_source"] = "cli_reported"
            global _CLI_COST_WARNED
            with _CLI_COST_WARN_LOCK:
                warn_cost = Decimal(str(cost)) > 0 and not _CLI_COST_WARNED
                if warn_cost:
                    _CLI_COST_WARNED = True
            if warn_cost:
                logger.warning(
                    "claude-headless: non-zero CLI-reported cost recorded; "
                    "actual billing is unverified (KF-020). "
                    "LOA_HEADLESS_MODE=api-only excludes subscription CLI dispatch."
                )

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
            cost_micro_usd=cost_micro,
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

        # Runtime auth revocation → WALKABLE (KF-017/#1071). Ambiguous
        # "unauthorized"/"401" walkable only when no static-misconfig marker.
        _static_auth = (
            "not logged in" in diag_lower
            or "/login" in diag_lower
        )
        if (
            "invalidated" in diag_lower
            or "session expired" in diag_lower
            or "token expired" in diag_lower
            or (("unauthorized" in diag_lower or "401" in full_diag) and not _static_auth)
        ):
            raise AuthRevokedError(
                self.provider,
                f"claude token revoked/expired — re-auth with {_CLAUDE_LOGIN_HINT}. "
                f"(diagnostic: {full_diag[:300]})",
            )

        # Static misconfig (never authenticated / no key) → hard-abort.
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
