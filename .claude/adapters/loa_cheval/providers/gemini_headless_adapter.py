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
  - The prompt rides stdin (gemini-cli joins piped stdin before the `-p` text), never argv: an argv prompt is readable by any
    local user through /proc/<pid>/cmdline and one argument over 128 KiB fails at exec (cycle-126 thirty-third run, e1b
    DISS-C-002). gemini-cli truncates stdin past 8 MiB, so a larger prompt is refused, walkable. A sandboxed run re-injects
    stdin into the sandbox child's argv, so the hop runs with GEMINI_SANDBOX=false (it outranks --sandbox and settings.json's
    tools.sandbox — verified on gemini-cli 0.41.2); only an operator `--sandbox` in `gemini_extra_flags` keeps a sandbox, and
    that exposure (thirty-fourth run, e1b DISS-C-001) — `--sandbox false`, `--sandbox=false` and `--no-sandbox` ask for
    none, read as yargs reads a boolean, the last flag winning (thirty-fifth run, e1b DISS-C-002) — `=<v>` is a sandbox only
    for exactly `true`, a following token its value only when exactly true / false (thirty-sixth run, e1b DISS-C-001).
    `--skip-trust` is passed so the CLI doesn't fall back to `default` when the
    invocation cwd isn't in gemini-cli's trusted-folders allowlist — the cwd is
    an isolated empty directory, never the reviewed tree (cycle-126).
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
import shutil  # Preserve the provider module's shutil.which patch point.
import subprocess
import time
from contextlib import contextmanager
from typing import Any, Dict, List, Optional

from loa_cheval.providers.headless_cli import CLIInvocation, HeadlessCLIAdapter, private_workspace
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


def _asks_sandbox(args) -> bool:
    """The operator's own flags ask for a sandbox, read as yargs reads a boolean: `-s` / `--sandbox` (a following literal
    true / false is its value), `--sandbox=<v>`, `--no-sandbox`; the last one wins (thirty-fifth run, e1b DISS-C-002).
    Exactly as gemini-cli 0.41.2 parses it: `=<v>` is `v === "true"`, and only the case-sensitive literals are consumed as a
    following value (thirty-sixth run, e1b DISS-C-001). A short-option group (`-sd`, `-ds=true`) sets each of its letters, as
    yargs' short-option-groups do; its last letter takes the `=value` or the following literal (thirty-seventh run, e1b
    DISS-C-002)."""
    want = False
    for i, a in enumerate(args):
        if a in ("-s", "--sandbox"):
            want = not (i + 1 < len(args) and args[i + 1] == "false")
        elif a.startswith(("--sandbox=", "-s=")):
            want = a.split("=", 1)[1] == "true"
        elif a == "--no-sandbox":
            want = False
        elif len(a) > 2 and a[0] == "-" and a[1] != "-":
            letters, eq, value = a[1:].partition("=")
            if letters.isalpha() and "s" in letters:
                if letters[-1] != "s":
                    want = True
                elif eq:
                    want = value == "true"
                else:
                    want = not (i + 1 < len(args) and args[i + 1] == "false")
    return want


class GeminiHeadlessAdapter(HeadlessCLIAdapter):
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

    # Cycle-110 FR-2.3 — subscription-CLI dispatch; circuit-breaker writes
    # route to the (google, headless) bucket.
    auth_type: str = "headless"

    _cli_type = "gemini-headless"
    _cli_name = "gemini"
    _command_label = "gemini -p"
    _install_hint = 'Install with: npm install -g @google/gemini-cli'
    _logger = logger

    # (the fixed `-p` text: headless mode, the prompt itself on stdin — e1b DISS-C-002)
    _ARGV_PROMPT = "Answer the request above."
    _STDIN_CAP = 8 * 1024 * 1024   # gemini-cli's MAX_STDIN_SIZE (UTF-16 code units of the decoded stdin)

    def _run_subprocess(self, command, **kwargs):
        # Keep the provider's subprocess seam available to callers and tests.
        # (thirty-fourth run, e1b DISS-C-001: an ambient sandbox — GEMINI_SANDBOX, or tools.sandbox in the user's settings —
        # would fold the stdin prompt into argv; "false" closes both unless the operator's own flags ask for one)
        if not _asks_sandbox(command[1:]):
            kwargs["env"] = {**(kwargs["env"] if kwargs.get("env") is not None else os.environ), "GEMINI_SANDBOX": "false"}
        return run_subprocess_pgkill(command, **kwargs)

    @contextmanager
    def _prepare_invocation(self, request, model_config, prompt):
        """An isolated empty cwd under the private base, as its siblings: gemini-cli reads GEMINI.md and `.gemini/` from its
        cwd, and `--skip-trust` trusts that directory — the caller's cwd is the tree under review, so a reviewed branch would
        shape its own reviewer (cycle-126 thirty-second run, e2a DISS-C-004). Relative policy paths are resolved first. One
        stable directory, as claude's: gemini-cli registers each project root it starts in (~/.gemini/projects.json and a
        ~/.gemini/tmp/<id>), so a directory per hop would leave one registration per hop (thirty-sixth run, e1b DISS-C-002)."""
        # (gemini-cli counts its cap in decoded string length — UTF-16 code units; a lone surrogate is one unit, counted here, and
        # stdin's own encode fails it as the base's typed spawn error: thirty-seventh run, e1b DISS-C-001)
        if len(prompt.encode("utf-16-le", "surrogatepass")) // 2 >= self._STDIN_CAP:
            raise ProviderUnavailableError(
                self.provider, f"gemini -p reads at most 8 MiB of stdin and would truncate this {len(prompt)}-character prompt",
            )
        command = self._build_command(request, model_config, prompt)
        workspace = private_workspace("loa-gemini-ws")
        started_at = time.monotonic()
        yield CLIInvocation(command, {"input": prompt, "cwd": workspace}, started_at)

    def _finish_completion(
        self, proc: subprocess.CompletedProcess, request: CompletionRequest, latency_ms: int,
    ) -> CompletionResult:
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

    # ---------------------------------------------------------------------
    # Internal: command construction
    # ---------------------------------------------------------------------

    def _cli_bin(self) -> str:
        """Resolve the gemini CLI binary name (env var override allowed)."""
        return os.environ.get("GEMINI_HEADLESS_BIN", _GEMINI_BIN_DEFAULT)

    def _build_command(
        self,
        request: CompletionRequest,
        model_config,
        prompt: str,
    ) -> List[str]:
        """Build the gemini argv. Headless, plan-mode (read-only), trusted. `prompt` is never on it: it rides stdin."""
        # cycle-104 sprint-2 T2.11 amendment: honor `extra.cli_model`
        # so a kind:cli alias (`gemini-headless`) translates to the real
        # gemini model id the CLI binary expects.
        cli_model = (model_config.extra or {}).get("cli_model") or request.model
        cmd: List[str] = [
            self._cli_bin(),
            "-p",
            self._ARGV_PROMPT,
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
                # (resolved against the caller's directory — the CLI runs in an isolated cwd: e2a DISS-C-004)
                # (and `~/…` expanded first — thirty-sixth run, e1b DISS-C-003)
                cmd.extend(["--policy", os.path.abspath(os.path.expanduser(str(path)))])

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

        # Runtime auth revocation → WALKABLE (KF-017/#1071). Ambiguous
        # "unauthorized"/"401" walkable only when no static-misconfig marker.
        _static_auth = (
            "auth method" in diag_lower
            or "set an auth" in diag_lower
            or "settings.json" in diag_lower
            or "gemini_api_key" in diag_lower
            or "google_genai_use" in diag_lower
        )
        if (
            "invalidated" in diag_lower
            or "session expired" in diag_lower
            or "token expired" in diag_lower
            or (("unauthorized" in diag_lower or "401" in full_diag) and not _static_auth)
        ):
            raise AuthRevokedError(
                self.provider,
                f"gemini token revoked/expired — re-auth by running `gemini` "
                f"interactively. (diagnostic: {full_diag[:300]})",
            )

        # Static misconfig (never authenticated / no key) → hard-abort.
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
