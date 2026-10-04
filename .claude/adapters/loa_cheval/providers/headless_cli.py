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

# the files a headless CLI loads from a cwd's project — never at or above an isolated cwd (thirty-third run, d DISS-C-001 /
# DISS-C-003): claude's, and gemini's, codex's and cursor's (thirty-fourth run, d DISS-C-004)
_PROJECT_FILES = ("CLAUDE.md", "CLAUDE.local.md", ".claude", ".mcp.json", "GEMINI.md", ".gemini", "AGENTS.md",
                  "AGENTS.override.md", ".codex", ".cursor", ".cursorrules")


def _group_private(gid: int) -> bool:
    """No other account is in the group: none is a listed member and none has it as its primary group — a user-private group
    (the Debian/Ubuntu default), never macOS `staff` or a shared `users` (thirty-third run, d DISS-001 / DISS-C-002). An
    account database that cannot answer is no proof."""
    try:
        import grp
        import pwd
        me = pwd.getpwuid(os.getuid()).pw_name
        group = grp.getgrgid(gid)
    except (ImportError, KeyError, OSError):
        return False
    # (thirty-fourth run, d DISS-C-001: getpwall() lists only the enumerable accounts — under sssd / LDAP, the local ones — and a
    # shared primary group lists no members, so their absence is no proof; a user-private group carries this account's name)
    # (thirty-sixth run, d DISS-C-005: decided before the enumeration — getpwall() can walk a whole directory)
    if group.gr_name != me or any(m != me for m in group.gr_mem):
        return False
    try:
        accounts = pwd.getpwall()
    except OSError:
        return False
    return all(a.pw_gid != gid or a.pw_uid == os.getuid() for a in accounts)


def _acl_extended(path: str) -> bool:
    """`path` carries a POSIX access ACL: its group bits are then the mask over named users and groups, never the owning
    group's own (thirty-fifth run, d DISS-C-004). A filesystem without xattrs carries none; any other failure is no proof.
    (macOS ACLs are not POSIX xattrs and Python has no os.listxattr there — not judged.)"""
    if not hasattr(os, "listxattr"):
        return False
    try:
        return "system.posix_acl_access" in os.listxattr(path)
    except OSError as exc:
        return exc.errno not in (errno.ENOTSUP, errno.EOPNOTSUPP)


def _dir_trustworthy(st, path: Optional[str] = None) -> bool:
    """A directory no other user can write into: owned by root or this uid, never other-writable, and group-writable only
    for this process's own group when no other account is in it (a user-private group — the Debian/Ubuntu default for
    ~/.cache) and no access ACL makes those bits a mask over other accounts' grants."""
    if not stat.S_ISDIR(st.st_mode) or st.st_uid not in (0, os.getuid()):
        return False
    if st.st_mode & stat.S_IWOTH:
        return False
    if not st.st_mode & stat.S_IWGRP:
        return True
    return st.st_gid == os.getgid() and _group_private(st.st_gid) and not (path and _acl_extended(path))


def _trusted_stop() -> set:
    """The test hook's root and every directory above it (empty outside the tests)."""
    stop = set()
    if _TRUSTED_ABOVE:
        t = os.path.realpath(_TRUSTED_ABOVE)
        while True:
            stop.add(t)
            if os.path.dirname(t) == t:
                break
            t = os.path.dirname(t)
    return stop


def _work_tree_of(path: str) -> Optional[str]:
    """The nearest directory at or above `path` (resolved) that holds a .git: the work tree a process there runs in."""
    p = os.path.realpath(path)
    while True:
        if os.path.lexists(os.path.join(p, ".git")):
            return p
        if os.path.dirname(p) == p:
            return None
        p = os.path.dirname(p)


def _project_marker(path: str) -> Optional[str]:
    """The first project file at or above `path` (resolved) that a CLI started below it would load: a .git — a work tree, the
    reviewed one — or a CLAUDE.md / CLAUDE.local.md / .claude / .mcp.json anywhere but the home directory, whose are the
    user's own (thirty-third run, d DISS-C-001: TMPDIR=.tmp, a read-only /tmp's cwd fallback, an XDG_RUNTIME_DIR in the
    tree). None when there is none."""
    home = os.path.realpath(os.path.expanduser("~"))
    stop = _trusted_stop()
    p = os.path.realpath(path)
    # (thirty-fourth run, d DISS-C-002: a dotfiles ~/.git is the user's own unless the reviewed tree — this process's cwd — is
    # that work tree; refusing it everywhere left a host with no runtime dir no headless voice at all)
    try:
        home_reviewed = _work_tree_of(os.getcwd()) == home
    except OSError:
        home_reviewed = True                  # (a cwd that cannot be read is no proof it is elsewhere)
    while p not in stop:
        for n in (() if p == home else _PROJECT_FILES) + ((".git",) if p != home or home_reviewed else ()):
            if os.path.lexists(os.path.join(p, n)):
                return os.path.join(p, n)
        if os.path.dirname(p) == p:
            break
        p = os.path.dirname(p)
    return None


def _chain_private(path: str) -> bool:
    """`path` (resolved) and every directory above it are trustworthy; a missing one is not."""
    stop = _trusted_stop()
    p = os.path.realpath(path)
    while p not in stop:
        try:
            if not _dir_trustworthy(os.stat(p), p):
                return False
        except OSError:
            return False
        if os.path.dirname(p) == p:
            break
        p = os.path.dirname(p)
    return True


def private_workspace_base() -> str:
    """The directory the headless CLIs' isolated cwds live in: $XDG_RUNTIME_DIR, else the temporary directory (a per-user
    one on macOS, or a private $TMPDIR), else ~/.cache/loa — the first whose every ancestor no other user can write, and
    that is inside no project tree (thirty-third run, d DISS-C-001). None → OSError (fail closed: a hop never runs where
    another user's, or the reviewed tree's, CLAUDE.md is on its discovery path). A host without POSIX ownership (Windows) has
    no other-user check: there the temporary directory is refused only inside a project (thirty-sixth run, d DISS-C-004)."""
    if not hasattr(os, "getuid"):
        base = tempfile.gettempdir()
        marker = _project_marker(base)
        if marker is not None:
            raise OSError(errno.EACCES, f"no private directory for a headless CLI's working directory — {base} is inside a "
                          f"project: {marker} (set TMP/TEMP to a directory outside any project)")
        return base
    tried = []
    xdg = os.environ.get("XDG_RUNTIME_DIR", "")

    def candidates():   # (thirty-sixth run, d DISS-C-001: the temporary directory read lazily — gettempdir() raises when none is
        if os.path.isabs(xdg):   # usable, and that never hides a private runtime dir or the home fallback)
            yield xdg
        try:
            yield tempfile.gettempdir()
        except OSError as exc:
            tried.append(f"the temporary directory ({exc.strerror or exc})")
    for cand in candidates():
        if os.path.isdir(cand) and _chain_private(cand):
            marker = _project_marker(cand)
            if marker is None:
                return os.path.realpath(cand)
            tried.append(f"{cand} (inside a project: {marker})")
            continue
        tried.append(cand)
    home = os.path.expanduser("~")
    if os.path.isabs(home) and os.path.isdir(home) and _chain_private(home):
        cache = os.path.join(os.path.realpath(home), ".cache")
        base = os.path.join(cache, "loa")
        try:
            # (thirty-sixth run, d DISS-C-003: each directory created 0700 itself — makedirs' mode is the leaf's alone, so under
            # umask 000 an absent ~/.cache was made 0777 here, refused, and left world-writable)
            for d in (cache, base):
                try:
                    os.mkdir(d, 0o700)
                except FileExistsError:
                    pass
        except OSError as exc:
            tried.append(f"{base} ({exc.strerror or exc})")
        else:
            marker = _project_marker(base)
            if _chain_private(base) and marker is None:
                return base
            tried.append(f"{base} (inside a project: {marker})" if marker else f"{base} (an ancestor another user can write into)")
    else:
        tried.append(os.path.join(home, ".cache", "loa"))
    raise OSError(errno.EACCES, "no private directory for a headless CLI's working directory — each candidate has an "
                  "ancestor another user can write into, or is inside a project tree: " + ", ".join(tried)
                  + " (set XDG_RUNTIME_DIR to a 0700 directory outside any project)")


def private_workspace(name: str) -> str:
    """A stable working directory `<base>/<name>` only this uid can write. A stable cwd is one Claude Code project key,
    never one left behind per hop (e1 DISS-C-002). A symlink, another owner or an open mode at the path → OSError."""
    path = os.path.join(private_workspace_base(), name)
    try:
        os.mkdir(path, 0o700)
    except FileExistsError:
        pass
    st = os.lstat(path)
    # (no ownership on a host without getuid — Windows reports a directory 0o777 — so the mode test goes with the uid test, as
    # the base's checks do: thirty-third run, d DISS-C-005)
    if not stat.S_ISDIR(st.st_mode) or (hasattr(os, "getuid") and (
            st.st_uid != os.getuid() or st.st_mode & (stat.S_IWGRP | stat.S_IWOTH))):
        raise OSError(errno.EEXIST, f"{path} is not a private directory of this user (a symlink, another owner, or "
                      "writable by others): remove it")
    # (one stable cwd for every hop: a project file left in it would be loaded by every later hop — thirty-third run, d DISS-C-003)
    held = [n for n in _PROJECT_FILES + (".git",) if os.path.lexists(os.path.join(path, n))]
    if held:
        raise OSError(errno.EEXIST, f"{path} holds {', '.join(held)} — a CLI started there would load it: remove it")
    return path


def cwd_vanished(cwd: Optional[str], exc: Optional[BaseException] = None) -> bool:
    """A FileNotFoundError at exec names a missing cwd as it names a missing binary: the cwd is gone — logind clears
    $XDG_RUNTIME_DIR at the last logout, perhaps while the hop waited for a slot — so the failure is the hop's, walkable,
    never 'CLI not found' (thirty-third run, e1 DISS-C-002). The spawn error names the path itself — CPython sets filename
    to the cwd when the child's chdir failed, to the executable when exec did — so a stable workspace a concurrent hop
    re-created since is still this cause (thirty-fifth run, d DISS-C-002); with no filename the stat decides."""
    if not cwd:
        return False
    named = getattr(exc, "filename", None)
    if named is not None:
        return os.fsdecode(named) == cwd
    return not os.path.isdir(cwd)


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
                        _cwd = invocation.kwargs.get("cwd")
                        if cwd_vanished(_cwd, exc):
                            raise ProviderUnavailableError(
                                self.provider, f"{self._command_label} working directory {_cwd} vanished before the CLI "
                                f"started: {exc}",
                            ) from exc
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
        except OSError as exc:
            # (thirty-third run, d DISS-C-004: a refused workspace — or a slot file — before the CLI ran is this hop's typed
            # failure, so the chain walks on; a bare OSError ended the walk as API_ERROR)
            raise ProviderUnavailableError(
                self.provider, f"{self._command_label} could not prepare its run: {exc}",
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
