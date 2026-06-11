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
  - `request.max_tokens` and `request.temperature` are IGNORED: cursor-agent exposes
    no flags for them. Documented limitation (BB #966 round-3), same class as the
    served-model gap above.
"""

from __future__ import annotations

import json
import logging
import os
import re
import shutil
import subprocess
import tempfile
import time
from typing import Any, Dict, List, Optional

from loa_cheval.providers.base import (
    ProviderAdapter,
    SubprocessOutputCapExceeded,
    build_headless_subprocess_env,
    enforce_context_window,
    run_subprocess_pgkill,
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


def _extract_envelope(stdout: str) -> Optional[Dict[str, Any]]:
    """Locate cursor-agent's JSON result envelope in stdout.

    Tolerates non-JSON preamble (node experimental warnings, deprecation
    notices). Without this, the strict startswith("{") check failed on any
    preamble, which (a) turned a billed success into ProviderUnavailableError
    in _parse_output and (b) made _transport_probe_text fall back to scanning
    FULL stdout — re-exposing the untrusted `result` to the substring probes,
    the CURSOR-001 silencing channel. (BB #966 round-2, 2-voice converged)
    """
    text = (stdout or "").strip()
    idx = text.find("{")
    decoder = json.JSONDecoder()
    while idx != -1:
        try:
            obj, consumed = decoder.raw_decode(text[idx:])
        except json.JSONDecodeError:
            idx = text.find("{", idx + 1)
            continue
        if isinstance(obj, dict):
            # ONLY a dict SHAPED like cursor's result envelope counts — a
            # JSON-formatted log line must neither shadow the real envelope
            # (BB #966 round-3) nor stand in for it: returning a non-envelope
            # dict turned classifiable failures into silent EMPTY successes
            # (BB #966 round-4). No fallback — callers treat None as
            # no-parseable-envelope and classify/raise accordingly.
            if obj.get("type") == "result" or "is_error" in obj or "result" in obj:
                return obj
        # Resume AFTER the consumed object so its nested dicts aren't rescanned.
        idx = text.find("{", idx + consumed)
    return None


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

    # Review #966 (Bundle-E parity): subscription-CLI dispatch; circuit-breaker
    # writes route to the (cursor-headless, headless) bucket, and headless-mode
    # transforms keep this adapter under cli-only mode.
    auth_type: str = "headless"

    def complete(self, request: CompletionRequest) -> CompletionResult:
        """Invoke `cursor-agent -p` and return a normalized CompletionResult."""
        model_config = self._get_model_config(request.model)
        enforce_context_window(request, model_config)

        prompt = self._build_prompt(request.messages)
        cmd = self._build_command(request, model_config)
        timeout_s = self._compute_timeout()
        # Review #966: per-model headless concurrency slots (peer pattern,
        # cycle-110 SDD §5.6). Default 50 when the operator hasn't seeded a
        # stress-test-discovered value.
        n_slots = getattr(model_config, "headless_concurrency_limit", None) or 50

        logger.debug(
            "cursor-headless invoking: model=%s timeout=%.0fs prompt_chars=%d slots=%d",
            request.model,
            timeout_s,
            len(prompt),
            n_slots,
        )

        # Import BEFORE mkdtemp — an import failure after it would leak the
        # workspace (it sits outside the try/finally). (BB #966 round-2)
        from loa_cheval.adapters.headless_concurrency import (
            SemaphoreExhausted as _SemaphoreExhausted,
            acquire_slot as _acquire_slot,
        )

        # Isolated empty cwd so a (denied) tool call has nothing to reach. Combined
        # with --mode plan + --sandbox enabled, this is defense-in-depth for the
        # untrusted prompt.
        workspace = tempfile.mkdtemp(prefix="loa-cursor-ws-")

        start = time.monotonic()
        try:
            with _acquire_slot("cursor-headless", n_slots=n_slots):
                try:
                    # Review #966 / #982 parity: run_subprocess_pgkill replaces the
                    # hand-rolled Popen + communicate + killpg block — whole-tree
                    # SIGKILL on timeout (cursor-agent forks node/MCP helpers),
                    # bounded output capture, BaseException teardown. The prompt
                    # is fed via STDIN (verified live 2026-06-11: cursor-agent -p
                    # reads the prompt from stdin when no positional arg is
                    # given) — it never touches argv, which (a) removes the OS
                    # ARG_MAX cliff on large-diff reviews (BB #966 round-4
                    # HIGH_CONSENSUS: argv caps ~256KB, ~6x below the advertised
                    # context window) and (b) removes the flag-parsing surface
                    # entirely (stronger than the previous `--` terminator).
                    # cwd= keeps the isolated-workspace defense.
                    proc = run_subprocess_pgkill(
                        cmd,
                        input=prompt,
                        timeout=timeout_s,
                        env=build_headless_subprocess_env(),
                        cwd=workspace,
                    )
                except subprocess.TimeoutExpired:
                    raise ProviderUnavailableError(
                        self.provider,
                        f"cursor-agent timed out after {timeout_s:.0f}s",
                    )
                except SubprocessOutputCapExceeded as exc:
                    # Truncated output is a provider failure, not a successful
                    # completion — the chain advances like a timeout.
                    raise ProviderUnavailableError(
                        self.provider,
                        f"cursor-agent {exc}",
                    ) from exc
                except FileNotFoundError as exc:
                    raise ConfigError(
                        f"cursor-agent CLI not found on PATH (set CURSOR_HEADLESS_BIN to "
                        f"override). Install Cursor + run `cursor-agent login`. Original: {exc}"
                    ) from exc
                except OSError as exc:
                    # PermissionError / ENOMEM / "Exec format error" etc. — the CLI
                    # never started. (BB CURSOR-004)
                    raise ProviderUnavailableError(
                        self.provider,
                        f"failed to spawn cursor-agent: {type(exc).__name__}: {exc}",
                    ) from exc
        except _SemaphoreExhausted as exc:
            # Distinct exit class so MODELINV records semaphore_exhausted=true and
            # the caller routes the failure separately from CHAIN_EXHAUSTED.
            raise ProviderUnavailableError(
                self.provider,
                f"[CHAIN-EXHAUSTED-CONCURRENCY] cursor-headless semaphore "
                f"exhausted after {exc.waited_seconds:.1f}s "
                f"(n_slots={exc.n_slots})",
            ) from exc
        finally:
            shutil.rmtree(workspace, ignore_errors=True)

        latency_ms = int((time.monotonic() - start) * 1000)
        stdout = proc.stdout or ""
        stderr = proc.stderr or ""

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
        payload = _extract_envelope(stdout)

        if payload is None:
            # Non-JSON output that wasn't caught by _raise_for_known_errors.
            snippet = (stdout.strip() or stderr.strip())[:500] or "empty output"
            raise ProviderUnavailableError(
                self.provider, f"cursor-agent produced no parseable JSON: {snippet}"
            )

        if payload.get("is_error"):
            # returncode=0: only the typed rate-limit/auth branches can fire —
            # the generic nonzero-exit branch stays quiet, so the descriptive
            # raise below is REACHABLE for unrecognized diagnostics. (BB #966
            # round-2: rc=1 made it dead code and fabricated "exit 1".)
            self._raise_for_known_errors(0, json.dumps(payload), stderr)
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

        BB #966 round-2 (HIGH, 2-voice converged): envelope META is excluded
        from the probe on BOTH branches. Usage token counts and session/request
        ids are numeric/opaque strings that substring-match "429" stochastically
        — a billed success must never classify as RateLimitError off its own
        token counts. On success, only stderr is probe-safe; on is_error, the
        classifying strings are `subtype` and `result` (cursor's own
        diagnostic), never ids/usage.
        """
        envelope = _extract_envelope(stdout)
        if envelope is not None:
            if envelope.get("is_error"):
                subtype = envelope.get("subtype") or ""
                result = envelope.get("result") or ""
                return f"{subtype}\n{result}\n{stderr}"
            return stderr or ""
        return f"{stdout}\n{stderr}"

    def _raise_for_known_errors(self, returncode: int, stdout: str, stderr: str) -> None:
        """Map cursor-agent failures to typed cheval errors.

        cursor-agent may surface transport errors on stdout with exit 0, so this
        inspects transport-safe text regardless of return code (the model's own
        `result` is excluded — see _transport_probe_text). Returns silently when
        no known error is present (the caller then parses the JSON envelope).
        """
        probe = self._transport_probe_text(stdout, stderr)
        combined = probe.lower()

        # Quota / rate limit. Cursor surfaces gRPC "resource_exhausted" (plan quota
        # depleted or free tier without Composer headless access) and rate-limit text.
        # "429" matches only as a standalone token (BB #966 rounds 3-4): stderr
        # is probe surface even on success, and incidental runs ("14290ms",
        # "429ms", request ids) must not classify a billed success as
        # rate-limited. Alphanumeric boundaries on both sides; "http 429" and
        # "code=429." still match.
        if (
            "resource_exhausted" in combined
            or "rate limit" in combined
            or re.search(r"(?<![0-9a-z])429(?![0-9a-z])", combined)
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
            # Diagnostic from the probe text, not stderr alone — cursor often
            # delivers the auth message on stdout or in the is_error result.
            # (BB #966 round-2)
            raise ConfigError(
                f"cursor-agent not authenticated. Run: cursor-agent login "
                f"(a Cursor plan including Composer is required). "
                f"diagnostic: {probe.strip()[:300]}"
            )

        # A non-zero exit with no recognized class → provider-unavailable so the
        # retry/fallback layer can react.
        if returncode != 0:
            snippet = (stderr.strip() or stdout.strip())[:500] or f"exit {returncode}"
            raise ProviderUnavailableError(
                self.provider, f"cursor-agent failed (exit {returncode}): {snippet}"
            )
