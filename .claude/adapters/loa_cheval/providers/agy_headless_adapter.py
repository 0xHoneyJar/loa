"""Agy-headless provider adapter — invokes `agy -p` (Antigravity CLI) for the Gemini voice.

This is the FR-5 repoint (loa#1096, #1089): the `gemini-headless` terminal shells the
`agy` (Antigravity) CLI instead of `gemini`. Google retired the gemini-cli's individual
Code Assist tier (`IneligibleTierError`, "migrate to Antigravity"); `agy` is that
successor — a multi-model gateway whose **Gemini** models restore the Google-lineage voice.

Grounded in the T4.1 spike (`grimoires/loa/proposals/headless-adapters/agy-spike.md`, run
against `agy` v1.0.12 on the cheval host; gate PASSED):

  - **Invocation** — `agy -p "<prompt>" --model "<label>" --sandbox --dangerously-skip-permissions`
    with stdin closed (the helper keeps stdin on DEVNULL). `-p` takes the prompt on **argv**
    (no `--prompt-file` flag exists → the gemini ARG_MAX cliff persists unchanged; the
    `gemini-api` HTTP fallback covers oversized diffs).
  - **--model** takes a **human-readable label** from `agy models` (e.g. "Gemini 3.1 Pro (High)"),
    NOT an API id — supplied via `extra.cli_model`.
  - **Output** — **PLAIN TEXT** (no JSON, no `--output-format`). So `_build_result` reads stdout
    as the content directly and estimates Usage (no real token counts — like grok). Cheaper to
    parse than gemini; loses exact token stats.
  - **non-TTY** — agy is a coding *agent*; non-TTY agentic output HANGS waiting on a
    tool-permission prompt. `--sandbox --dangerously-skip-permissions` + a closed stdin fixes
    it (clean output, exit 0, zero ANSI). `--sandbox` keeps it terminal-restricted (the
    read-only analog of gemini's `--approval-mode plan`); never `--dangerously-skip-permissions`
    alone on a review path.
  - **Auth** — agy is **OAuth**-authed on host (`agy models` → exit 0; no API-key flag; creds in
    an OAuth store, not `GOOGLE_API_KEY`). The gemini env-strip is a no-op for agy; we keep
    `build_headless_subprocess_env()` (harmless — agy ignores the stripped vars).

Design parity with the sibling headless adapters: single-shot, prompt flattened, tools not
forwarded, empty-as-success (warn, don't raise). Folds onto the FR-1 `HeadlessCLIAdapter`
base in the R8 follow-up; lands first as a standalone sibling so the Gemini voice goes live.
"""

from __future__ import annotations

import json
import logging
import os
import shutil
import subprocess
import time
from typing import Any, Dict, List

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
    AuthRevokedError,
    ConfigError,
    ProviderUnavailableError,
    RateLimitError,
    Usage,
)

logger = logging.getLogger("loa_cheval.providers.agy_headless")

# agy CLI binary name (override via AGY_HEADLESS_BIN env var for testing)
_AGY_BIN_DEFAULT = "agy"

# Conservative defaults for subprocess wall-clock. ProviderConfig.read_timeout
# wins when set; these floors apply only when the loader hands defaults.
_CONNECT_TIMEOUT_FLOOR = 10.0
_READ_TIMEOUT_FLOOR = 600.0  # 10 min


class AgyHeadlessAdapter(ProviderAdapter):
    """Adapter that routes inference through `agy -p` (non-interactive, sandboxed).

    Registered as the `gemini-headless` terminal (the FR-5 repoint) so existing
    `gemini-headless` configs/aliases resolve unchanged onto agy's Gemini models:

        providers:
          gemini-headless:
            type: gemini-headless          # registry key unchanged; class is agy
            connect_timeout: 10.0
            read_timeout: 600.0
            models:
              gemini-3-pro:
                context_window: 1048576
                pricing: {input_per_mtok: 0, output_per_mtok: 0}
                extra:
                  cli_model: "Gemini 3.1 Pro (High)"   # agy label, NOT an api id

        aliases:
          deep-thinker: gemini-headless:gemini-3-pro
    """

    # Cycle-110 FR-2.3 — subscription-CLI dispatch; circuit-breaker writes route
    # to the (google, headless) bucket (agy's Gemini models are Google-lineage).
    auth_type: str = "headless"

    def complete(self, request: CompletionRequest) -> CompletionResult:
        """Invoke `agy -p` and return a normalized CompletionResult (plain-text)."""
        model_config = self._get_model_config(request.model)
        enforce_context_window(request, model_config)

        prompt = self._build_prompt(request.messages)
        cmd = self._build_command(request, model_config, prompt)
        timeout_s = self._compute_timeout()
        n_slots = getattr(model_config, "headless_concurrency_limit", None) or 50

        logger.debug(
            "agy-headless invoking: model=%s timeout=%.0fs prompt_chars=%d slots=%d",
            request.model,
            timeout_s,
            len(prompt),
            n_slots,
        )

        from loa_cheval.adapters.headless_concurrency import (
            SemaphoreExhausted as _SemaphoreExhausted,
            acquire_slot as _acquire_slot,
        )

        start = time.monotonic()
        try:
            with _acquire_slot(self.provider, n_slots=n_slots):
                try:
                    # #982: process-group-killing drop-in for subprocess.run — on
                    # timeout the whole CLI tree dies and the fallback chain advances
                    # instead of hanging on orphaned pipes. No `input=` → the helper
                    # keeps stdin on DEVNULL, which (paired with --sandbox
                    # --dangerously-skip-permissions in argv) is the spike's non-TTY
                    # fix: agy doesn't hang on a tool-permission prompt.
                    proc = run_subprocess_pgkill(
                        cmd,
                        timeout=timeout_s,
                        # agy is OAuth-authed; the gemini env-strip is a no-op for it
                        # (agy ignores GOOGLE_API_KEY/GEMINI_API_KEY). Kept for parity.
                        env=build_headless_subprocess_env(),
                    )
                except subprocess.TimeoutExpired:
                    raise ProviderUnavailableError(
                        self.provider,
                        f"agy -p timed out after {timeout_s:.0f}s",
                    )
                except SubprocessOutputCapExceeded as exc:
                    # Truncated output is a provider failure, not a successful
                    # completion — chain advances like a timeout.
                    raise ProviderUnavailableError(
                        self.provider,
                        f"agy -p {exc}",
                    ) from exc
                except FileNotFoundError as exc:
                    raise ConfigError(
                        f"agy CLI not found on PATH (set AGY_HEADLESS_BIN to override). "
                        f"Install + authenticate the Antigravity CLI on the cheval host. "
                        f"Original: {exc}"
                    ) from exc
                except OSError as exc:
                    # E2BIG (ARG_MAX — a huge diff on argv; agy is argv-transport, no
                    # --prompt-file exists) or another exec failure → WALK the chain,
                    # never crash with a raw OSError. The gemini-api HTTP fallback
                    # covers oversized diffs. (FileNotFoundError is handled above.)
                    raise ProviderUnavailableError(
                        self.provider,
                        f"agy -p exec failed (likely ARG_MAX on an oversized prompt): {exc}",
                    ) from exc
                except ValueError as exc:
                    # An untrusted prompt with an embedded NUL byte makes subprocess raise
                    # ValueError("embedded null byte") at exec — NOT an OSError, so the
                    # catch above misses it. WALK the chain, never crash raw. (Found by the
                    # Gemini council voice via agy — codex+cursor missed it. The review
                    # content is untrusted, so a NUL in a diff is a real reachable input.)
                    raise ProviderUnavailableError(
                        self.provider,
                        f"agy -p got un-execable argv (embedded NUL in the prompt?): {exc}",
                    ) from exc
        except _SemaphoreExhausted as exc:
            raise ProviderUnavailableError(
                self.provider,
                f"[CHAIN-EXHAUSTED-CONCURRENCY] {self.provider} semaphore "
                f"exhausted after {exc.waited_seconds:.1f}s "
                f"(n_slots={exc.n_slots})",
            ) from exc

        latency_ms = int((time.monotonic() - start) * 1000)

        # agy output is PLAIN TEXT (no JSON envelope). A non-zero exit is a
        # failure; otherwise stdout IS the content.
        if proc.returncode != 0:
            self._raise_for_error(
                returncode=proc.returncode,
                stdout=proc.stdout or "",
                stderr=proc.stderr or "",
            )

        return self._build_result(
            stdout=proc.stdout or "",
            requested_model=request.model,
            messages=request.messages,
            latency_ms=latency_ms,
        )

    def validate_config(self) -> List[str]:
        """Validate that the agy CLI is on PATH. Auth is best-effort (CLI enforces)."""
        errors: List[str] = []
        if self.config.type != "gemini-headless":
            errors.append(
                f"Provider '{self.provider}': type must be 'gemini-headless' "
                f"(the agy repoint keeps the registry key; got '{self.config.type}')"
            )

        bin_name = self._agy_bin()
        if not shutil.which(bin_name):
            errors.append(
                f"Provider '{self.provider}': '{bin_name}' CLI not found on PATH. "
                f"Install + OAuth-authenticate the Antigravity CLI on the cheval host."
            )

        # Each model needs an agy --model LABEL (agy rejects internal ids — without it
        # _build_command raises) — surface at config-validate time, not first dispatch
        # (council #1109).
        for model_id, mc in (self.config.models or {}).items():
            if not (mc.extra or {}).get("cli_model"):
                errors.append(
                    f"Provider '{self.provider}': model '{model_id}' needs extra.cli_model "
                    f'— the agy --model LABEL (e.g. "Gemini 3.1 Pro (High)"); agy rejects '
                    f"internal model ids."
                )
        return errors

    def health_check(self) -> bool:
        """Verify the agy CLI is reachable (`agy --version`). Does NOT make a model call."""
        bin_name = self._agy_bin()
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

    def _agy_bin(self) -> str:
        """Resolve the agy CLI binary name (env var override allowed)."""
        return os.environ.get("AGY_HEADLESS_BIN", _AGY_BIN_DEFAULT)

    def _build_command(
        self,
        request: CompletionRequest,
        model_config,
        prompt: str,
    ) -> List[str]:
        """Build the agy argv (spike T4.1). Prompt on argv; sandboxed; non-TTY-safe.

        The stdin-close is NOT part of this argv — it is a subprocess setting
        (`run_subprocess_pgkill` keeps stdin on DEVNULL when no `input=` is passed).
        """
        # `extra.cli_model` is REQUIRED — an agy MODEL LABEL (e.g. "Gemini 3.1 Pro
        # (High)"), not an api id (agy's `--model` wants the human-readable label).
        # No fallback to request.model: agy rejects internal ids, so a silent fallback
        # would just fail at dispatch with a confusing error (council #1109).
        cli_model = (model_config.extra or {}).get("cli_model")
        if not cli_model:
            raise ConfigError(
                f"Provider '{self.provider}': model '{request.model}' is missing "
                f'extra.cli_model (the agy --model LABEL, e.g. "Gemini 3.1 Pro (High)").'
            )

        # The argv is FIXED — there is deliberately no operator-supplied extra-flags
        # escape hatch. The prompt is untrusted review content; an extra-flags surface
        # was a sandbox-bypass foothold (council #1109 found a split-token bypass that a
        # denylist can't reliably close). The non-TTY pairing (--sandbox keeps agy
        # terminal-restricted, the read-only analog of gemini's plan mode;
        # --dangerously-skip-permissions + a closed stdin stops the non-TTY hang) is
        # non-negotiable. A genuinely-needed flag is a deliberate, reviewed code change.
        return [
            self._agy_bin(),
            "-p",
            prompt,
            "--model",
            cli_model,
            "--sandbox",
            "--dangerously-skip-permissions",
        ]

    def _compute_timeout(self) -> float:
        """Resolve the subprocess timeout. read_timeout wins when set."""
        connect = max(self.config.connect_timeout, _CONNECT_TIMEOUT_FLOOR)
        read = max(self.config.read_timeout, _READ_TIMEOUT_FLOOR)
        return connect + read

    # ---------------------------------------------------------------------
    # Internal: prompt flattening (parity with the sibling headless adapters)
    # ---------------------------------------------------------------------

    def _build_prompt(self, messages: List[Dict[str, Any]]) -> str:
        """Flatten message array into a single prompt for agy -p.

        Role-prefixed sections collapsed into one input string — lossy vs a native
        multi-turn API, but sufficient for the single-shot flatline review modes.
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
    # Internal: plain-text result (agy emits no JSON / no token stats)
    # ---------------------------------------------------------------------

    def _build_result(
        self,
        stdout: str,
        requested_model: str,
        messages: List[Dict[str, Any]],
        latency_ms: int,
    ) -> CompletionResult:
        """Map agy's plain-text stdout to a normalized CompletionResult.

        agy reports NO token usage, so Usage is estimated from the flattened input
        + returned text (source="estimated"); subscription cost is 0 (no pricing
        entry → metered at $0 by design).
        """
        content = (stdout or "").strip()

        if not content:
            # Empty-as-success matches the codex/gemini/cursor/grok headless
            # adapters (warn + return, NOT raise) — peer-contract consistency.
            logger.warning(
                "agy-headless: empty stdout from agy (model=%s)", requested_model
            )

        usage = Usage(
            input_tokens=estimate_tokens(messages),
            output_tokens=estimate_tokens(
                [{"role": "assistant", "content": content}]
            ),
            reasoning_tokens=0,
            source="estimated",
        )

        return CompletionResult(
            content=content,
            tool_calls=None,
            thinking=None,
            usage=usage,
            # agy does not report a served model id — fall back to requested.
            model=requested_model,
            latency_ms=latency_ms,
            provider=self.provider,
            interaction_id=None,
            metadata={},
        )

    # ---------------------------------------------------------------------
    # Internal: error classification
    # ---------------------------------------------------------------------

    def _raise_for_error(
        self,
        returncode: int,
        stdout: str,
        stderr: str,
    ) -> None:
        """Map an agy failure (non-zero exit) to a typed cheval error.

        agy is plain-text, so the diagnostic comes from stderr (preferred) or
        stdout. Unlike the dead gemini-cli, agy is OAuth — there is no
        IneligibleTier path; we classify rate-limit, token-revocation (walkable),
        and not-authenticated (hard-abort), else provider-unavailable (walkable).
        """
        # Classify against STDERR ONLY — the error channel. On a failed agy run, stdout
        # may carry untrusted review TEXT, which must NEVER drive classification
        # (council #1109): "line 401" / "rate limit" inside a review would misroute the
        # fallback chain. stdout is allowed only in the final operator-facing snippet.
        err_diag = stderr.strip()
        diag_lower = err_diag.lower()

        # Rate-limit / quota. Bare "429" is safe here — it's stderr (the error/HTTP
        # channel), never review text.
        if (
            "rate limit" in diag_lower
            or "429" in diag_lower
            or "quota" in diag_lower
            or "resource_exhausted" in diag_lower
            or "too many requests" in diag_lower
        ):
            raise RateLimitError(self.provider)

        # A static "never authenticated" marker pins the failure to hard-abort and
        # makes an ambiguous 401/unauthorized NON-walkable (parity with the gemini
        # adapter's _static_auth guard; council #1109 — without it a never-authed
        # failure carrying "401" wrongly walks the chain forever).
        _static_auth = (
            "not authenticated" in diag_lower
            or "not logged in" in diag_lower
            or "no auth" in diag_lower
            or "please log in" in diag_lower
            or "run `agy`" in diag_lower
        )

        # Runtime OAuth-token revocation/expiry → WALKABLE (re-auth fixes it).
        # Ambiguous 401/unauthorized is walkable ONLY when no static marker is present.
        if (
            "session expired" in diag_lower
            or "token expired" in diag_lower
            or "token revoked" in diag_lower
            or "re-authenticate" in diag_lower
            or "reauthenticate" in diag_lower
            or (("401" in diag_lower or "unauthorized" in diag_lower) and not _static_auth)
        ):
            raise AuthRevokedError(
                self.provider,
                f"agy OAuth token revoked/expired — re-auth by running `agy` "
                f"interactively on the host. (diagnostic: {err_diag[:300]})",
            )

        # Never authenticated (no OAuth session) → hard-abort (static misconfig).
        # (permission_denied is NOT mapped here — for OAuth it is ambiguous/often
        # transient, so it falls through to a WALKABLE ProviderUnavailableError.)
        if _static_auth:
            raise ConfigError(
                f"agy CLI not authenticated. Run `agy` once interactively to log in "
                f"(OAuth) on the cheval host. (diagnostic: {err_diag[:300]})"
            )

        # Generic failure → WALKABLE. The snippet MAY include stdout for operator
        # diagnostics, but it never drove classification above.
        snippet = (err_diag or stdout.strip())[:500] or f"exit code {returncode}, no diagnostic"
        raise ProviderUnavailableError(
            self.provider,
            f"agy -p failed (exit {returncode}): {snippet}",
        )
