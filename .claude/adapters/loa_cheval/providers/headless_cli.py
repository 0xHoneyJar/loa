"""Shared single-shot CLI behavior; transport and output formats stay provider-specific."""

from __future__ import annotations

import errno
import json
import logging
import os
import shutil
import stat
import subprocess
import tempfile
import time
from abc import abstractmethod
from contextlib import contextmanager
from dataclasses import dataclass
from typing import Any, Dict, Iterator, List, Optional

from loa_cheval.providers.base import (
    ProviderAdapter, SubprocessOutputCapExceeded, build_headless_subprocess_env,
    enforce_context_window, run_subprocess_pgkill,
)
from loa_cheval import types as _types   # (the ceiling is read through the module: run 27, d DISS-C-001)
from loa_cheval.types import (
    headless_connect_floor,
    headless_read_floor,
    usable_headless_timeout,
    CompletionRequest,
    CompletionResult,
    ConfigError,
    ProviderUnavailableError,
)


# --- the isolated cwd's private base (cycle-126 thirty-second run, e1 DISS-C-001 / DISS-C-002) -------------------------
# claude reads CLAUDE.md from every ancestor of its cwd, so an isolated cwd under a world-writable /tmp let any local user
# plant /tmp/CLAUDE.md into the reviewer's context. The base is a directory whose every ancestor no other user can write.

_TRUSTED_ABOVE: Optional[str] = None   # a test hook only (the suite's private root and its ancestors are not judged)


def _dir_trustworthy(st) -> bool:
    """A directory no other user can write into: owned by root or this uid, never other-writable, and group-writable only
    for this process's own group (a user-private group — the Debian/Ubuntu default for ~/.cache)."""
    if not stat.S_ISDIR(st.st_mode) or st.st_uid not in (0, os.getuid()):
        return False
    if st.st_mode & stat.S_IWOTH:
        return False
    return not (st.st_mode & stat.S_IWGRP) or st.st_gid == os.getgid()


def _chain_private(path: str) -> bool:
    """`path` (resolved) and every directory above it are trustworthy; a missing one is not."""
    stop = set()
    if _TRUSTED_ABOVE:
        t = os.path.realpath(_TRUSTED_ABOVE)
        while True:
            stop.add(t)
            if os.path.dirname(t) == t:
                break
            t = os.path.dirname(t)
    p = os.path.realpath(path)
    while p not in stop:
        try:
            if not _dir_trustworthy(os.stat(p)):
                return False
        except OSError:
            return False
        if os.path.dirname(p) == p:
            break
        p = os.path.dirname(p)
    return True


def private_workspace_base() -> str:
    """The directory the headless CLIs' isolated cwds live in: $XDG_RUNTIME_DIR, else the temporary directory (a per-user
    one on macOS, or a private $TMPDIR), else ~/.cache/loa — the first whose every ancestor no other user can write.
    None → OSError (fail closed: a hop never runs where another user's CLAUDE.md is on its discovery path)."""
    if not hasattr(os, "getuid"):
        return tempfile.gettempdir()
    tried = []
    xdg = os.environ.get("XDG_RUNTIME_DIR", "")
    for cand in ([xdg] if os.path.isabs(xdg) else []) + [tempfile.gettempdir()]:
        if os.path.isdir(cand) and _chain_private(cand):
            return os.path.realpath(cand)
        tried.append(cand)
    home = os.path.expanduser("~")
    if os.path.isabs(home) and os.path.isdir(home) and _chain_private(home):
        base = os.path.join(os.path.realpath(home), ".cache", "loa")
        os.makedirs(base, mode=0o700, exist_ok=True)
        if _chain_private(base):
            return base
        tried.append(base)
    else:
        tried.append(os.path.join(home, ".cache", "loa"))
    raise OSError(errno.EACCES, "no private directory for a headless CLI's working directory — each candidate has an "
                  "ancestor another user can write into: " + ", ".join(tried) + " (set XDG_RUNTIME_DIR to a 0700 directory)")


def private_workspace(name: str) -> str:
    """A stable working directory `<base>/<name>` only this uid can write. A stable cwd is one Claude Code project key,
    never one left behind per hop (e1 DISS-C-002). A symlink, another owner or an open mode at the path → OSError."""
    path = os.path.join(private_workspace_base(), name)
    try:
        os.mkdir(path, 0o700)
    except FileExistsError:
        pass
    st = os.lstat(path)
    if (not stat.S_ISDIR(st.st_mode) or (hasattr(os, "getuid") and st.st_uid != os.getuid())
            or st.st_mode & (stat.S_IWGRP | stat.S_IWOTH)):
        raise OSError(errno.EEXIST, f"{path} is not a private directory of this user (a symlink, another owner, or "
                      "writable by others): remove it")
    return path


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
        timeout_s = self._compute_timeout(model_config)
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
                        # sixteenth run, d C-001: a catalog bound that was not applied as written is said HERE, where the
                        # message reaches the MODELINV row and the companion diagnostic (cheval's load-time WARNING on
                        # stderr never reaches the dissent path)
                        _note = getattr(model_config, "headless_timeout_note", None)
                        raise ProviderUnavailableError(
                            self.provider,
                            f"{self._command_label} timed out after {timeout_s:.0f}s" + (f" ({_note})" if _note else ""),
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

    def _compute_timeout(self, model_config: Any = None) -> float:
        """Keep the existing 10s connect and 600s read floors; a per-model
        `headless_timeout_seconds` (catalog) raises the read bound above them
        (cycle-126 sprint-248: a long dissent on `claude -p` takes 6-10 min).

        The catalog value was validated and clamped ONCE at load (types.coerce_headless_timeout_seconds);
        this only bounds a bare ModelConfig the same way and never warns per hop (tenth run, d C-001).
        The key only ever RAISES the bound — a provider read_timeout already above the ceiling is never
        lowered (eighth run, d DISS-001 / C-001)."""
        read = headless_read_floor(self.config.read_timeout)   # (the loader's note reads the same floor — run 24, d DISS-C-002)
        per_model = getattr(model_config, "headless_timeout_seconds", None)
        usable_value = usable_headless_timeout(per_model)   # (the loader's own predicate — fourteenth run, d C-001)
        if usable_value is not None:
            # (the types module's own binding, read at the call — the one the loader clamps to; no class copy (run 26 d DISS-C-002)
            # and no import-time copy (run 27 d DISS-C-001))
            value = min(usable_value, _types.HEADLESS_TIMEOUT_CEILING_SECONDS)
            if value > read:
                read = value
            else:
                self._logger.debug("headless_timeout_seconds %r: the %.0fs read bound already meets it", per_model, read)
        elif per_model is not None:
            self._logger.debug("headless_timeout_seconds %r unusable here (the catalog loader reports this at load)", per_model)
        return headless_connect_floor(self.config.connect_timeout) + read   # (run 26, d DISS-C-001)

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
