"""Grok-headless provider adapter — invokes `grok` (xAI Grok Build CLI) for subscription auth.

Routes Loa's cheval calls through the xAI Grok Build CLI (`grok --prompt-file ...
--output-format json`) instead of an HTTP API. Auth comes from `grok login`
(OIDC against auth.x.ai — `auth_mode: oidc`), so no API key is consumed for
these calls.

A headless CLI is a multi-model CLIENT, not a single-company port. It serves a
set of models that can span providers. Grounded 2026-06-13 (`<cli> models`):
  - `grok models`         → grok-build (default), grok-composer-2.5-fast
  - `cursor-agent models` → Claude, GPT/Codex, Gemini, Grok-4.3, Kimi, Composer
So "grok = a distinct new-company voice" is NOT grounded — models cross-serve
(cursor brokers Grok and Kimi; grok exposes a Composer variant). What this
adapter actually adds is direct xAI-subscription access (`grok login`, OIDC, no
API key) to grok's served models — notably grok-build, an xAI agentic model not
pinned elsewhere in the cheval roster (cursor exposes grok-4.3, a different
grok model). Any council-diversity benefit is a property of the MODEL run
(grok-build ≠ claude/gpt/gemini), not of "which company's CLI" — and is left
unclaimed here beyond what `<cli> models` shows.

ROUTER-OF-ROUTERS — one CLI, a model set behind it:
  Cheval PINS each headless entry to a served model via `extra.cli_model`. The
  `xai` provider declares >1 (grok-build + grok-composer-2.5-fast), chosen by
  `--model <cli_model>` per call; the CLI itself is model-agnostic. Cheval
  routes by the intelligence tier it needs → (this CLI, a served model).

When to use:
  - You have an xAI/Grok subscription (`grok login`) and want flatline /
    bridgebuilder / FAGAN councils (or any cheval consumer) to reach grok-build
    from the subscription quota — no API key provisioned.

Design notes (grounded against grok 0.2.51, probed live 2026-06-13):
  - Single-shot. Multi-turn message arrays are flattened into one role-prefixed
    prompt (parity with codex/cursor headless). The review/skeptic/scorer/
    dissenter flatline modes are single-pass, so this is correct.
  - The prompt is fed via `--prompt-file <path>` (a file inside an isolated
    mkdtemp workspace), NOT argv: this dodges the OS ARG_MAX cliff on large
    review diffs AND keeps prompt-derived content off argv entirely (no
    flag-parsing / process-listing surface). Mirrors the cursor-headless
    refinement (which used stdin); grok exposes a purpose-built --prompt-file.
  - SECURITY: the prompt is UNTRUSTED (it carries the diff/content under
    review). The call is hardened to pure inference: `--permission-mode dontAsk`
    (no tool-execution approval), `--no-subagents`, `--no-plan`,
    `--disable-web-search`, `--max-turns 1`, and an isolated empty cwd
    (mkdtemp) so a denied tool call has nothing to reach. Tools are not
    forwarded. (grok's operator MCP servers fail to spawn under this posture
    and emit NON-FATAL stderr noise — see the JSON/stderr contract below.)
  - OUTPUT is a SINGLE JSON object on stdout (not codex's JSONL stream):
        {"text": ..., "stopReason": ..., "sessionId": ..., "requestId": ...,
         "thought": ...}
    Map: content←text · thinking←thought · interaction_id←sessionId. There is
    NO token usage in the JSON, so Usage.source="estimated" (base.estimate_tokens)
    and subscription cost is 0 micro-USD (no pricing entry in model-config).
  - STDERR carries non-fatal noise: operator MCP servers fail to spawn
    ("Failed to spawn MCP server ...") and their workers log
    "Transport channel closed, when Auth(AuthorizationRequired)". The call
    STILL exits 0 with valid JSON on stdout. So: parse the stdout envelope and
    key SUCCESS off (returncode == 0 AND a parseable envelope) — NEVER treat
    stderr presence (incl. the "AuthorizationRequired" worker noise) as
    failure. Error classification only runs when there is no valid envelope.
  - reasoning_effort ∈ {low, medium, high, xhigh, max} (grok `--reasoning-effort`).
    Resolved per-call from request.metadata, then ModelConfig.extra, else the
    CLI default.
  - AUTH: subscription (OIDC). XAI_API_KEY / GROK_CODE_XAI_API_KEY (+ the
    forward-compat GROK_API_KEY) are stripped in build_headless_subprocess_env
    so the CLI uses its persisted OAuth login, not an API-key path.
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
from pathlib import Path
from typing import Any, Dict, List, Optional

from loa_cheval.providers.base import (
    ProviderAdapter,
    SubprocessOutputCapExceeded,
    build_headless_subprocess_env,
    enforce_context_window,
    estimate_tokens,
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

logger = logging.getLogger("loa_cheval.providers.grok_headless")

# grok CLI binary name (override via GROK_HEADLESS_BIN for testing)
_GROK_BIN_DEFAULT = "grok"

# Allowed reasoning-effort levels (grok 0.2.51 `--reasoning-effort`).
_ALLOWED_REASONING_EFFORTS = ("low", "medium", "high", "xhigh", "max")

# Conservative subprocess wall-clock floors (parity with codex/cursor headless).
# A configured value BELOW the floor does NOT lower it — the floor wins so an
# agent session is not killed mid-reasoning.
_CONNECT_TIMEOUT_FLOOR = 10.0
_READ_TIMEOUT_FLOOR = 600.0  # 10 min — agent sessions can be slow


def _extract_envelope(stdout: str) -> Optional[Dict[str, Any]]:
    """Locate grok's single JSON result object in stdout.

    grok --output-format json prints a (pretty-printed, multi-line) JSON object:
        {"text": ..., "stopReason": ..., "sessionId": ..., "requestId": ...,
         "thought": ...}
    Tolerates any non-JSON preamble. Returns the FIRST dict carrying a STABLE
    grok envelope identifier ("stopReason" / "sessionId" / "requestId") — a
    JSON-formatted log/preamble line carrying only "text" must neither shadow
    nor stand in for the real envelope. Returns None when no grok-shaped object
    is present (caller classifies/raises accordingly).
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
        # BB #1057 (F4): gate on a stable envelope identifier, not a lone
        # "text" key — the real grok result always carries stopReason +
        # session/request ids; a "text"-only log line must not shadow it.
        if isinstance(obj, dict) and any(
            k in obj for k in ("stopReason", "sessionId", "requestId")
        ):
            return obj
        # Resume AFTER the consumed object so its nested dicts aren't rescanned.
        idx = text.find("{", idx + consumed)
    return None


class GrokHeadlessAdapter(ProviderAdapter):
    """Adapter that routes inference through `grok --prompt-file ... --output-format json`.

    Provider config (no api_key field; one port, MULTIPLE models):

        providers:
          xai:
            type: grok-headless
            # endpoint and auth are ignored; auth is grok's own OIDC login.
            models:
              grok-build:
                kind: cli
                auth_type: headless
                dispatch_group: xai-grok
                context_window: 256000
                extra: {cli_model: grok-build}
              grok-composer-2.5-fast:
                kind: cli
                auth_type: headless
                dispatch_group: xai-grok
                context_window: 256000
                extra: {cli_model: grok-composer-2.5-fast}

    Aliases bind to provider:model-id like the other adapters:

        aliases:
          grok-build: xai:grok-build
          grok-fast:  xai:grok-composer-2.5-fast
    """

    # Subscription-CLI dispatch — circuit-breaker writes route to the
    # (xai, headless) bucket; headless-mode transforms keep this adapter under
    # cli-only mode (parity with the codex/gemini/claude/cursor headless peers).
    auth_type: str = "headless"

    def complete(self, request: CompletionRequest) -> CompletionResult:
        """Invoke `grok --prompt-file ... --output-format json` → CompletionResult."""
        model_config = self._get_model_config(request.model)
        enforce_context_window(request, model_config)

        prompt = self._build_prompt(request.messages)
        timeout_s = self._compute_timeout()
        # Per-model headless concurrency slots (peer pattern). Default 50 when
        # the operator hasn't seeded a stress-test-discovered value.
        n_slots = getattr(model_config, "headless_concurrency_limit", None) or 50

        logger.debug(
            "grok-headless invoking: model=%s timeout=%.0fs prompt_chars=%d slots=%d",
            request.model,
            timeout_s,
            len(prompt),
            n_slots,
        )

        # Import BEFORE mkdtemp so an import failure can't leak the workspace
        # (cursor #966 round-2 lesson).
        from loa_cheval.adapters.headless_concurrency import (
            SemaphoreExhausted as _SemaphoreExhausted,
            acquire_slot as _acquire_slot,
        )

        # Isolated empty cwd so a (denied) tool call has nothing to reach. The
        # prompt is written to a file INSIDE this workspace and passed via
        # --prompt-file — never argv (no ARG_MAX cliff, no flag-parsing surface).
        workspace: Optional[str] = None
        start = time.monotonic()
        try:
            try:
                workspace = tempfile.mkdtemp(prefix="loa-grok-ws-")
                prompt_path = str(Path(workspace) / "prompt.txt")
                # write_text on a fresh 0700 mkdtemp dir; UTF-8 explicit so a
                # non-ASCII review diff round-trips intact.
                Path(prompt_path).write_text(prompt, encoding="utf-8")
            except OSError as exc:
                raise ProviderUnavailableError(
                    self.provider,
                    f"grok-headless: failed to stage isolated workspace: "
                    f"{type(exc).__name__}",
                ) from exc
            cmd = self._build_command(request, model_config, prompt_path)
            with _acquire_slot("grok-headless", n_slots=n_slots):
                try:
                    # Process-group-killing drop-in (#982): on timeout the whole
                    # grok CLI tree dies and the fallback chain advances instead
                    # of hanging on orphaned pipes. The prompt rides --prompt-file,
                    # so stdin stays DEVNULL (input=None).
                    proc = run_subprocess_pgkill(
                        cmd,
                        timeout=timeout_s,
                        # Strip XAI_API_KEY / GROK_CODE_XAI_API_KEY / GROK_API_KEY
                        # so grok uses its persisted OIDC login, not an API path.
                        env=build_headless_subprocess_env(),
                        cwd=workspace,
                    )
                except subprocess.TimeoutExpired:
                    raise ProviderUnavailableError(
                        self.provider,
                        f"grok timed out after {timeout_s:.0f}s",
                    )
                except SubprocessOutputCapExceeded as exc:
                    # Truncated output is a provider failure, not a successful
                    # completion — the chain advances like a timeout.
                    raise ProviderUnavailableError(
                        self.provider,
                        f"grok {exc}",
                    ) from exc
                except FileNotFoundError as exc:
                    raise ConfigError(
                        f"grok CLI not found on PATH (set GROK_HEADLESS_BIN to "
                        f"override). Install Grok + run `grok login`. Original: {exc}"
                    ) from exc
                except OSError as exc:
                    # PermissionError / ENOMEM / "Exec format error" etc. — the
                    # CLI never started.
                    raise ProviderUnavailableError(
                        self.provider,
                        f"failed to spawn grok: {type(exc).__name__}: {exc}",
                    ) from exc
        except _SemaphoreExhausted as exc:
            # Distinct exit class so MODELINV records semaphore_exhausted=true and
            # the caller routes the failure separately from CHAIN_EXHAUSTED.
            raise ProviderUnavailableError(
                self.provider,
                f"[CHAIN-EXHAUSTED-CONCURRENCY] grok-headless semaphore "
                f"exhausted after {exc.waited_seconds:.1f}s "
                f"(n_slots={exc.n_slots})",
            ) from exc
        finally:
            if workspace is not None:
                shutil.rmtree(workspace, ignore_errors=True)

        latency_ms = int((time.monotonic() - start) * 1000)
        stdout = proc.stdout or ""
        stderr = proc.stderr or ""

        # SUCCESS contract: returncode == 0 AND a parseable grok envelope. grok
        # emits non-fatal stderr noise (MCP workers logging
        # "Auth(AuthorizationRequired)") even on a clean call, so the envelope —
        # never stderr — is the success signal. This sidesteps the stderr-noise
        # trap entirely: a successful review whose stderr quotes auth/429 tokens
        # can never be misclassified as a transport failure.
        if proc.returncode == 0:
            payload = _extract_envelope(stdout)
            if payload is not None:
                return self._build_result(
                    payload, request.model, latency_ms, request.messages
                )

        # No valid envelope OR non-zero exit → classify the failure.
        self._raise_for_subprocess_error(proc.returncode, stdout, stderr)
        # rc == 0 but no parseable envelope and no recognized error class.
        snippet = (stdout.strip() or stderr.strip())[:500] or "empty output"
        raise ProviderUnavailableError(
            self.provider, f"grok produced no parseable JSON: {snippet}"
        )

    def validate_config(self) -> List[str]:
        """Validate that grok is on PATH and the provider type is correct."""
        errors: List[str] = []
        if self.config.type != "grok-headless":
            errors.append(
                f"Provider '{self.provider}': type must be 'grok-headless' "
                f"(got '{self.config.type}')"
            )
        bin_name = self._grok_bin()
        if not shutil.which(bin_name):
            errors.append(
                f"Provider '{self.provider}': '{bin_name}' CLI not found on PATH. "
                f"Install Grok and run `grok login`."
            )
        # Auth is best-effort: `grok login` populates ~/.grok/auth.json. If
        # absent, the CLI errors at first call — no need to duplicate here.
        return errors

    def health_check(self) -> bool:
        """Verify the grok CLI is reachable. Does NOT make a model call."""
        bin_name = self._grok_bin()
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

    def _grok_bin(self) -> str:
        return os.environ.get("GROK_HEADLESS_BIN", _GROK_BIN_DEFAULT)

    def _build_command(
        self,
        request: CompletionRequest,
        model_config,
        prompt_path: str,
    ) -> List[str]:
        """Build the grok argv. Single-shot, pure inference, prompt via file.

        The prompt is NEVER on argv — `--prompt-file` points at a file in the
        isolated workspace. Hardened to pure inference: dontAsk + no-subagents +
        no-plan + no-web-search + max-turns 1. `extra.cli_model` selects the
        real grok model (grok-build / grok-composer-2.5-fast) the CLI expects.
        """
        cli_model = (model_config.extra or {}).get("cli_model") or request.model
        cmd: List[str] = [
            self._grok_bin(),
            "--prompt-file",
            prompt_path,
            "--output-format",
            "json",
            "--model",
            cli_model,
            "--no-plan",
            "--no-subagents",
            "--disable-web-search",
            "--max-turns",
            "1",
            "--permission-mode",
            "dontAsk",
        ]
        effort = self._resolve_reasoning_effort(request, model_config)
        if effort:
            cmd.extend(["--reasoning-effort", effort])
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
          3. None (let the grok CLI use its own default)

        Validates against {low, medium, high, xhigh, max}; logs a warning +
        falls through on unknown values rather than failing the request.
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
                "grok-headless: ignoring unknown reasoning_effort=%r (allowed: %s)",
                raw,
                ", ".join(_ALLOWED_REASONING_EFFORTS),
            )
        return None

    def _compute_timeout(self) -> float:
        connect = max(self.config.connect_timeout, _CONNECT_TIMEOUT_FLOOR)
        read = max(self.config.read_timeout, _READ_TIMEOUT_FLOOR)
        return connect + read

    # ---------------------------------------------------------------------
    # Internal: prompt flattening (parity with codex/cursor headless)
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

    def _build_result(
        self,
        payload: Dict[str, Any],
        requested_model: str,
        latency_ms: int,
        messages: List[Dict[str, Any]],
    ) -> CompletionResult:
        """Map a parsed grok envelope to a normalized CompletionResult.

        grok reports NO token usage in its JSON, so Usage is estimated from the
        flattened input + returned text (source="estimated"); subscription cost
        is 0 (no pricing entry → metered at $0 by design).
        """
        content = payload.get("text") or ""
        if not isinstance(content, str):
            content = json.dumps(content)

        thought = payload.get("thought")
        thinking = thought if isinstance(thought, str) and thought else None

        if not content:
            # Empty-as-success matches the codex/gemini/cursor headless adapters
            # (warn + return, NOT raise) — peer-contract consistency.
            logger.warning(
                "grok-headless: empty text from grok (model=%s)", requested_model
            )

        usage = Usage(
            input_tokens=estimate_tokens(messages),
            output_tokens=estimate_tokens(
                [{"role": "assistant", "content": content}]
            ),
            reasoning_tokens=0,
            source="estimated",
        )

        # BB #1057 (low-001/002): interaction_id MUST be str-or-None for
        # downstream logging/envelopes (parity with the content/thinking guards
        # above). Prefer sessionId; fall back to requestId; a numeric/null id
        # normalizes to None rather than leaking a non-string downstream.
        _sid = payload.get("sessionId")
        _rid = payload.get("requestId")
        interaction_id = (
            _sid if isinstance(_sid, str)
            else _rid if isinstance(_rid, str)
            else None
        )

        return CompletionResult(
            content=content,
            tool_calls=None,
            thinking=thinking,
            usage=usage,
            # grok does not report a served model id — fall back to requested.
            model=requested_model,
            latency_ms=latency_ms,
            provider=self.provider,
            interaction_id=interaction_id,
        )

    # ---------------------------------------------------------------------
    # Internal: error classification
    # ---------------------------------------------------------------------

    def _raise_for_subprocess_error(
        self, returncode: int, stdout: str, stderr: str
    ) -> None:
        """Map a grok failure (no valid envelope) to a typed cheval error.

        Only reached when there is NO parseable success envelope, so stdout here
        is transport/error text (not model output) and is safe to scan. Returns
        silently when no known error class is present (the caller then raises the
        generic no-parseable-JSON ProviderUnavailableError).
        """
        combined = f"{stdout}\n{stderr}".lower()

        # Quota / rate limit. "429" matches only as a standalone token so an
        # incidental digit run (request ids, "1429ms") does not misclassify.
        if (
            "rate limit" in combined
            or "resource_exhausted" in combined
            or "too many requests" in combined
            or "quota" in combined
            or re.search(r"(?<![0-9a-z])429(?![0-9a-z])", combined)
        ):
            raise RateLimitError(self.provider)

        # Auth failure — keyed on login-ACTION phrases, NOT the bare
        # "unauthorized"/"AuthorizationRequired" substring: grok's non-fatal MCP
        # worker noise carries "Auth(AuthorizationRequired)" on EVERY call, so
        # matching it would misfire. The login-action phrases only appear when
        # the operator genuinely needs to (re)authenticate.
        if (
            "not logged in" in combined
            or "logged out" in combined
            or "grok login" in combined
            or "please sign in" in combined
            or "sign in to grok" in combined
            or "session expired" in combined
            or "re-authenticate" in combined
            or "not authenticated" in combined
        ):
            diagnostic = (stderr.strip() or stdout.strip())[:300]
            raise ConfigError(
                f"grok CLI not authenticated. Run: grok login. "
                f"diagnostic: {diagnostic}"
            )

        # A non-zero exit with no recognized class → provider-unavailable so the
        # retry/fallback layer can react.
        if returncode != 0:
            snippet = (stderr.strip() or stdout.strip())[:500] or f"exit {returncode}"
            raise ProviderUnavailableError(
                self.provider, f"grok failed (exit {returncode}): {snippet}"
            )
