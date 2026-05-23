"""Cursor-headless provider adapter — invokes `cursor-agent` for Composer subscription auth.

Routes Loa's cheval calls through the Cursor Agent CLI (`cursor-agent -p`) instead
of an HTTP API. Auth comes from `cursor-agent login` (Cursor account; a paid plan
that includes Composer is required), so no API key is consumed for these calls.
This brings Cursor's **Composer** model line — built on a Moonshot Kimi base with
heavy agentic RL — into the cheval roster as a coding-specialist voice with a base
corpus distinct from the OpenAI / Anthropic / Google adapters. That corpus
independence is the point: in a consensus panel (flatline / FAGAN) it fails
differently, so it catches what the same-lab voices miss.

When to use:
  - You have a Cursor Pro/Business subscription and want flatline / bridgebuilder /
    code-review voices to draw a distinct-corpus model from the subscription quota.
  - You want cross-lab diversity in a review panel without provisioning another API key.

Design notes:
  - Single-shot only. Multi-turn message arrays are flattened into one role-prefixed
    prompt (same approach as codex-headless). The flatline review/skeptic/scorer/
    dissenter modes are single-pass, so this is correct.
  - SECURITY: the prompt is UNTRUSTED (it carries the diff/content under review).
    cursor-agent -p has full tool access by default, so the adapter hardens every
    call: `--mode plan` (read-only — analyze, no edits), `--sandbox enabled` (OS
    confinement), an isolated empty working directory, and NEVER `-f`/`--yolo`
    (force-allow). Verified empirically: without `-f`, cursor denies tool execution
    ("rejected by sandbox policy"). Tools are not forwarded; this is pure inference.
  - Auth-class env vars are stripped via `build_headless_subprocess_env()` for parity
    with the other headless adapters (cursor uses its own login, so this is a no-op
    for Cursor itself but keeps the subprocess env clean).
  - Token usage maps cursor's `usage.inputTokens`/`outputTokens` → Usage. cursor-agent
    does NOT report the served model id, so `CompletionResult.model` falls back to the
    requested model (a silent `-fast` downgrade cannot be detected from CLI output
    today — documented limitation). Subscription billing → pricing should be 0.
"""

from __future__ import annotations

import json
import logging
import os
import shutil
import signal
import subprocess
import tempfile
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

logger = logging.getLogger("loa_cheval.providers.cursor_headless")

# cursor-agent CLI binary name (override via CURSOR_HEADLESS_BIN for testing)
_CURSOR_BIN_DEFAULT = "cursor-agent"

# Conservative subprocess wall-clock floors. The effective timeout is connect+read,
# each clamped UP to its floor — a configured value BELOW the floor does NOT lower it
# (the floor wins; this protects agent sessions from being killed mid-reasoning).
# (BB CURSOR-007: comment now matches _compute_timeout's actual max()-with-floor behavior.)
_CONNECT_TIMEOUT_FLOOR = 10.0
_READ_TIMEOUT_FLOOR = 600.0  # 10 min — agent sessions can be slow


def _safe_int(v: Any) -> int:
    """Coerce a usage value to a non-negative int; never raise on bad input.

    cursor-agent sets usage (not the model), but a malformed/None field must not
    turn an already-billed successful inference into a hard failure. (panel cleanup)
    """
    try:
        return max(0, int(v or 0))
    except (TypeError, ValueError):
        return 0


class CursorHeadlessAdapter(ProviderAdapter):
    """Adapter that routes inference through `cursor-agent -p` (Composer).

    Provider config (no api_key field):

        providers:
          cursor-headless:
            type: cursor-headless
            # endpoint and auth are ignored; auth is cursor-agent's own login.
            connect_timeout: 10.0
            read_timeout: 600.0
            models:
              composer-2.5:
                context_window: 200000
                pricing: {input_per_mtok: 0, output_per_mtok: 0}

    Aliases bind to provider:model-id like the other adapters:

        aliases:
          reviewer: cursor-headless:composer-2.5
    """

    def complete(self, request: CompletionRequest) -> CompletionResult:
        """Invoke `cursor-agent -p` and return a normalized CompletionResult."""
        model_config = self._get_model_config(request.model)
        enforce_context_window(request, model_config)

        prompt = self._build_prompt(request.messages)
        cmd = self._build_command(request, model_config)
        timeout_s = self._compute_timeout()

        logger.debug(
            "cursor-headless invoking: model=%s timeout=%.0fs prompt_chars=%d",
            request.model,
            timeout_s,
            len(prompt),
        )

        # Isolated empty cwd so a (denied) tool call has nothing to reach. Combined
        # with --mode plan + --sandbox enabled, this is defense-in-depth for the
        # untrusted prompt.
        workspace = tempfile.mkdtemp(prefix="loa-cursor-ws-")
        start = time.monotonic()
        # cursor-agent is an agent runtime that forks helpers (node, MCP servers).
        # start_new_session puts the whole tree in its own process group so a
        # timeout can SIGKILL ALL of it — subprocess.run(timeout=) reaps only the
        # direct child and leaks grandchildren on every hung call (host DoS under
        # the error path). `--` ends option parsing so the untrusted prompt can
        # never be read as a flag, regardless of formatting. (panel: opus-skeptic)
        try:
            proc = subprocess.Popen(
                cmd + ["--", prompt],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                stdin=subprocess.DEVNULL,
                text=True,
                cwd=workspace,
                env=build_headless_subprocess_env(),
                start_new_session=True,
            )
        except FileNotFoundError as exc:
            shutil.rmtree(workspace, ignore_errors=True)
            raise ConfigError(
                f"cursor-agent CLI not found on PATH (set CURSOR_HEADLESS_BIN to "
                f"override). Install Cursor + run `cursor-agent login`. Original: {exc}"
            ) from exc
        except OSError as exc:
            # PermissionError / ENOMEM / "Exec format error" etc. — Popen never
            # started, so clean up the workspace it would otherwise leak. (BB CURSOR-004)
            shutil.rmtree(workspace, ignore_errors=True)
            raise ProviderUnavailableError(
                self.provider, f"failed to spawn cursor-agent: {type(exc).__name__}: {exc}"
            ) from exc

        try:
            stdout, stderr = proc.communicate(timeout=timeout_s)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
            # Bound the reap — if killpg failed (PermissionError) the tree may be
            # alive and an unbounded communicate() would block forever, re-creating
            # the host-DoS hang the process-group design exists to prevent. (BB CURSOR-005)
            try:
                proc.communicate(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()  # last resort: SIGKILL the direct child
                try:
                    proc.communicate(timeout=5)
                except subprocess.TimeoutExpired:
                    pass  # abandon the reap rather than block the caller forever
            raise ProviderUnavailableError(
                self.provider,
                f"cursor-agent timed out after {timeout_s:.0f}s",
            )
        finally:
            shutil.rmtree(workspace, ignore_errors=True)

        latency_ms = int((time.monotonic() - start) * 1000)
        stdout = stdout or ""
        stderr = stderr or ""

        # cursor-agent can surface transport errors (e.g. resource_exhausted) on
        # stdout with a zero exit code, so classify from BOTH the exit code and the
        # transport-safe output text (NOT the model's `result`) before parsing.
        self._raise_for_known_errors(proc.returncode, stdout, stderr)

        return self._parse_output(stdout, stderr, request.model, latency_ms)

    def validate_config(self) -> List[str]:
        """Validate that cursor-agent is on PATH and the type is correct."""
        errors: List[str] = []
        if self.config.type != "cursor-headless":
            errors.append(
                f"Provider '{self.provider}': type must be 'cursor-headless' "
                f"(got '{self.config.type}')"
            )
        bin_name = self._cursor_bin()
        if not shutil.which(bin_name):
            errors.append(
                f"Provider '{self.provider}': '{bin_name}' CLI not found on PATH. "
                f"Install Cursor and run `cursor-agent login`."
            )
        # Auth is best-effort: `cursor-agent login` populates ~/.cursor. If absent,
        # the CLI errors at first call — no need to duplicate the check here.
        return errors

    def health_check(self) -> bool:
        """Verify the cursor-agent CLI is reachable. Does NOT make a model call."""
        bin_name = self._cursor_bin()
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

    def _cursor_bin(self) -> str:
        return os.environ.get("CURSOR_HEADLESS_BIN", _CURSOR_BIN_DEFAULT)

    def _build_command(self, request: CompletionRequest, model_config) -> List[str]:
        """Build the cursor-agent argv. Read-only, sandboxed, no force-allow."""
        cli_model = (model_config.extra or {}).get("cli_model") or request.model
        # --mode plan: read-only (analyze, no edits). --sandbox enabled: OS confinement.
        # --trust: skip the interactive Workspace-Trust prompt for the empty cwd.
        # NEVER -f/--yolo. Tools are not forwarded — this is pure inference.
        return [
            self._cursor_bin(),
            "-p",
            "--output-format",
            "json",
            "--model",
            cli_model,
            "--mode",
            "plan",
            "--sandbox",
            "enabled",
            "--trust",
        ]

    def _compute_timeout(self) -> float:
        connect = max(self.config.connect_timeout, _CONNECT_TIMEOUT_FLOOR)
        read = max(self.config.read_timeout, _READ_TIMEOUT_FLOOR)
        return connect + read

    # ---------------------------------------------------------------------
    # Internal: prompt flattening (parity with codex-headless)
    # ---------------------------------------------------------------------

    def _build_prompt(self, messages: List[Dict[str, Any]]) -> str:
        """Flatten the message array into a single role-prefixed prompt."""
        sections: List[str] = []
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

            sections.append(f"{label}\n\n{content}".rstrip())

        return "\n\n".join(sections) + "\n"

    # ---------------------------------------------------------------------
    # Internal: output parsing
    # ---------------------------------------------------------------------

    def _parse_output(
        self,
        stdout: str,
        stderr: str,
        requested_model: str,
        latency_ms: int,
    ) -> CompletionResult:
        """Parse cursor-agent --output-format json (a single JSON object).

        Observed shape (cursor-agent 2025.09.18):
          {"type":"result","subtype":"success","is_error":false,
           "result":"<model answer text>","session_id":"...","request_id":"...",
           "usage":{"inputTokens":N,"outputTokens":N,"cacheReadTokens":N,"cacheWriteTokens":N}}
        """
        payload: Optional[Dict[str, Any]] = None
        text = stdout.strip()
        if text.startswith("{"):
            try:
                payload = json.loads(text)
            except json.JSONDecodeError:
                payload = None

        if payload is None:
            # Non-JSON output that wasn't caught by _raise_for_known_errors.
            snippet = (text or stderr.strip())[:500] or "empty output"
            raise ProviderUnavailableError(
                self.provider, f"cursor-agent produced no parseable JSON: {snippet}"
            )

        if payload.get("is_error"):
            self._raise_for_known_errors(1, json.dumps(payload), stderr)
            raise ProviderUnavailableError(
                self.provider,
                f"cursor-agent reported is_error: {str(payload.get('result'))[:300]}",
            )

        content = payload.get("result") or ""
        if not isinstance(content, str):
            content = json.dumps(content)

        usage_data = payload.get("usage") or {}
        usage = Usage(
            input_tokens=_safe_int(usage_data.get("inputTokens")),
            output_tokens=_safe_int(usage_data.get("outputTokens")),
            reasoning_tokens=0,
            source="actual" if usage_data else "estimated",
        )

        if not content:
            # Empty-as-success deliberately matches the codex/gemini headless adapters
            # (warn + return, NOT raise) — consistency with the peer contract over
            # divergence. (BB CURSOR-003: finding accepted, suggested EmptyContent raise
            # rejected with evidence — neither codex_headless nor gemini_headless raises;
            # they warn + return empty. Diverging here would make this adapter the odd one.)
            logger.warning(
                "cursor-headless: empty result from cursor-agent (model=%s)",
                requested_model,
            )

        return CompletionResult(
            content=content,
            tool_calls=None,
            thinking=None,
            usage=usage,
            # cursor-agent does not report the served model — fall back to requested.
            model=payload.get("model") or requested_model,
            latency_ms=latency_ms,
            provider=self.provider,
            interaction_id=payload.get("session_id"),
        )

    # ---------------------------------------------------------------------
    # Internal: error classification
    # ---------------------------------------------------------------------

    def _transport_probe_text(self, stdout: str, stderr: str) -> str:
        """Text safe for transport-error substring heuristics.

        The `result` field carries TWO different trust levels depending on the
        sibling `is_error` flag, so the trust decision MUST branch on that flag
        (BB CURSOR-001 — a field-name-keyed rule is eventually wrong):

        - is_error == false (success): `result` is the model's answer — untrusted
          reviewed content. This adapter REVIEWS untrusted diffs, which routinely
          quote `401 unauthorized` / `429` / `resource_exhausted`; scanning it would
          misclassify a successful review as a transport failure and let an attacker
          silence this voice by embedding those tokens. EXCLUDE it.
        - is_error == true: `result` is cursor's OWN diagnostic (the actual
          `resource_exhausted` / `unauthorized` message). EXCLUDING it here blinds
          the classifier exactly when classification matters — collapsing a
          non-retryable auth failure into a retryable generic outage. INCLUDE it.

        Non-JSON output (a raw transport dump) is scanned in full — that is where
        genuine zero-exit transport errors appear.
        """
        trimmed = (stdout or "").strip()
        if trimmed.startswith("{"):
            try:
                envelope = json.loads(trimmed)
            except json.JSONDecodeError:
                return f"{stdout}\n{stderr}"
            if isinstance(envelope, dict):
                meta = {k: v for k, v in envelope.items() if k != "result"}
                if envelope.get("is_error"):
                    return f"{json.dumps(meta)}\n{envelope.get('result', '')}\n{stderr}"
                return f"{json.dumps(meta)}\n{stderr}"
        return f"{stdout}\n{stderr}"

    def _raise_for_known_errors(self, returncode: int, stdout: str, stderr: str) -> None:
        """Map cursor-agent failures to typed cheval errors.

        cursor-agent may surface transport errors on stdout with exit 0, so this
        inspects transport-safe text regardless of return code (the model's own
        `result` is excluded — see _transport_probe_text). Returns silently when
        no known error is present (the caller then parses the JSON envelope).
        """
        combined = self._transport_probe_text(stdout, stderr).lower()

        # Quota / rate limit. Cursor surfaces gRPC "resource_exhausted" (plan quota
        # depleted or free tier without Composer headless access) and rate-limit text.
        if (
            "resource_exhausted" in combined
            or "rate limit" in combined
            or "429" in combined
            or "too many requests" in combined
        ):
            raise RateLimitError(self.provider)

        # Auth failure — most actionable for operators new to Cursor headless.
        if (
            "not logged in" in combined
            or "press any key to sign in" in combined
            or "unauthorized" in combined
            or "please log in" in combined
        ):
            raise ConfigError(
                f"cursor-agent not authenticated. Run: cursor-agent login "
                f"(a Cursor plan including Composer is required). "
                f"stderr: {stderr.strip()[:300]}"
            )

        # A non-zero exit with no recognized class → provider-unavailable so the
        # retry/fallback layer can react.
        if returncode != 0:
            snippet = (stderr.strip() or stdout.strip())[:500] or f"exit {returncode}"
            raise ProviderUnavailableError(
                self.provider, f"cursor-agent failed (exit {returncode}): {snippet}"
            )
