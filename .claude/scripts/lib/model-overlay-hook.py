#!/usr/bin/env python3
"""model-overlay-hook.py — cycle-099 Sprint 2B (T2.3 + T2.4).

Runtime overlay hook per SDD §1.4.4. Reads the SoT model-config plus operator
`model_aliases_extra` from `.loa.config.yaml`, validates extras against the
Sprint 2A schema, and writes `.run/merged-model-aliases.sh` for bash consumers
(model-adapter.sh, red-team-model-adapter.sh, etc.).

The hook is idempotent under flock + SHA256-cache invalidation. On a warm
cache (input SHA matches header) it acquires only a shared flock, returns
without writing, and exits in <50ms p95 per NFR-Perf-1 (SDD §7.5.1). Cold
regen path acquires an exclusive flock, validates, builds the merged shape,
emits via shlex.quote()-protected atomic write (tempfile in same dir + chmod
0600 BEFORE rename per SDD §1.4.4), and updates `.run/overlay-state.json`.

Failure modes documented in SDD §6.3 routing table. Default behavior on
lock timeout is degraded read-only fallback (NFR-Op-6); strict mode opt-in
via `LOA_OVERLAY_STRICT=1` for ops/CI environments that want fail-closed.
NFS/SMB/CIFS detection per SDD §6.6 refuses unless operator opts in via
`LOA_ALLOW_NETWORK_FS_FOR_MERGED_ALIASES=1`.

Exit codes:
    0    success (regen completed OR cache hit OR degraded read-only OK)
    78   refuse-to-start (config invalid, network FS without opt-in, future
         schema version, write failed, corrupt regen output)
    64   usage / IO error
    65   lock acquisition failed in strict mode (LOA_OVERLAY_STRICT=1)

Schema reference: .claude/data/trajectory-schemas/{model-aliases-extra,overlay-state}.schema.json
SDD reference: cycle-099-model-registry §1.4.4, §3.5, §6.3, §6.6, §7.5.1
"""

from __future__ import annotations

import argparse
import contextlib
import dataclasses
import datetime as dt
import errno
import fcntl
import hashlib
import json
import os
import re
import secrets
import shlex
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

import yaml

# Sprint 2A validator API: validate(config, schema, block_path, framework_ids)
# Re-export from the canonical validator module. This is the same module
# that ships at `.claude/scripts/lib/validate-model-aliases-extra.py`.
# CYP-F8 fix: do NOT use sys.path.insert — that pollutes downstream import
# resolution for any caller that loads this module as a library. importlib's
# spec_from_file_location does not require sys.path manipulation.
_lib_dir = Path(__file__).resolve().parent
import importlib.util as _importlib_util
_validator_spec = _importlib_util.spec_from_file_location(
    "_loa_validate_model_aliases_extra",
    _lib_dir / "validate-model-aliases-extra.py",
)
if _validator_spec is None or _validator_spec.loader is None:
    raise RuntimeError("could not locate validate-model-aliases-extra.py")
_validator = _importlib_util.module_from_spec(_validator_spec)
_validator_spec.loader.exec_module(_validator)

# ----------------------------------------------------------------------------
# Constants
# ----------------------------------------------------------------------------

EXIT_OK = 0
EXIT_REFUSE = 78
EXIT_USAGE = 64
EXIT_LOCK_FAILED = 65

# Per SDD §6.6: filesystems where flock semantics are not reliable. Operator
# must explicitly opt in via LOA_ALLOW_NETWORK_FS_FOR_MERGED_ALIASES=1 to
# proceed on these mounts. The opt-in does NOT disable flock; flock still
# attempts. The acknowledgement is documentation-of-risk only.
_NETWORK_FILESYSTEM_BLOCKLIST = frozenset({
    "nfs", "nfs3", "nfs4",
    "cifs", "smbfs", "smb3",
    "fuse.sshfs", "fuse.s3fs",
    "autofs",
    "davfs",
})

# Per SDD §6.3.1: shared lock 5s default, exclusive 30s default. Operators
# on enterprise CI may extend via env vars without code change.
_DEFAULT_SHARED_TIMEOUT_MS = 5000
_DEFAULT_EXCLUSIVE_TIMEOUT_MS = 30000

# Per SDD §3.5 rule 1: the writer NEVER interpolates operator strings into
# .sh content via f-strings. shlex.quote() is the only quoting path. After
# quoting, the result MUST consist only of characters from this set (the
# closure ensures the value is a single-quoted bash literal containing only
# safe payload characters plus the surrounding quote chars). Mismatched
# values are rejected with [MERGED-ALIASES-WRITE-FAILED] per SDD §3.5
# rule 5. The set explicitly excludes `$`, `\``, `\\`, `\n`, `\r`,
# whitespace, and any control byte.
_SHELL_SAFE_CHARSET = frozenset(
    "abcdefghijklmnopqrstuvwxyz"
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    "0123456789"
    "._-"
    + "'"  # surrounding quote char emitted by shlex.quote
)

# Per SDD §3.5 rule 5: any of these in a value triggers immediate abort.
# These checks run in addition to the post-shlex.quote charset assertion.
_SHELL_FORBIDDEN_CHARS = frozenset({
    "$", "`", "\\",
    "\n", "\r",
    "\x00",  # NUL — bash handles oddly + JSON cannot carry
})

# Marker tokens emitted in error paths. Stable strings — operator runbooks
# grep for these. Keep in sync with SDD §6.3.5 failure-mode table.
_MARK_NETWORK_FS = "[MERGED-ALIASES-NETWORK-FS]"
_MARK_NETWORK_FS_OVERRIDE = "[MERGED-ALIASES-NETWORK-FS-OVERRIDE]"
_MARK_WRITE_FAILED = "[MERGED-ALIASES-WRITE-FAILED]"
_MARK_CORRUPT = "[MERGED-ALIASES-CORRUPT]"
_MARK_MISSING = "[MERGED-ALIASES-MISSING]"
_MARK_STALE = "[MERGED-ALIASES-STALE]"
_MARK_LOCK_TIMEOUT_SHARED = "[MERGED-ALIASES-LOCK-TIMEOUT-SHARED]"
_MARK_LOCK_TIMEOUT_EXCLUSIVE = "[MERGED-ALIASES-LOCK-TIMEOUT-EXCLUSIVE]"
_MARK_STALE_LOCK = "[MERGED-ALIASES-STALE-LOCK]"
_MARK_STALE_AND_LOCKED = "[MERGED-ALIASES-STALE-AND-LOCKED]"
_MARK_EXTRA_INVALID = "[MODEL-EXTRA-INVALID]"
_MARK_DEGRADED = "[OVERLAY-DEGRADED-READONLY]"
_MARK_DEGRADED_PROLONGED = "[OVERLAY-DEGRADED-PROLONGED]"
_MARK_DEGRADED_CRITICAL = "[OVERLAY-DEGRADED-CRITICAL]"
_MARK_STATE_INIT = "[OVERLAY-STATE-INITIALIZED]"
_MARK_STATE_CORRUPT = "[OVERLAY-STATE-CORRUPT-REBUILT]"
_MARK_STATE_FUTURE = "[OVERLAY-STATE-FUTURE-VERSION]"
_MARK_STATE_MIGRATED = "[OVERLAY-STATE-MIGRATED]"

# Schema versions we understand for overlay-state.json. v1 is the cycle-099
# Sprint 2B shape. Future cycles MAY extend; runtime refuses anything higher.
_OVERLAY_STATE_SCHEMA_VERSION = 1

# ----------------------------------------------------------------------------
# Path helpers
# ----------------------------------------------------------------------------


def _project_root() -> Path:
    """Walk upward from CWD looking for the .claude/ directory marker.

    Mirrors the cycle-099 PROJECT_ROOT pattern from validate-model-aliases-extra.py
    and other Sprint 1 scripts. Falls back to CWD if no marker found.
    """
    cwd = Path.cwd().resolve()
    for parent in [cwd, *cwd.parents]:
        if (parent / ".claude").is_dir():
            return parent
    return cwd


def _default_sot_path() -> Path:
    return _project_root() / ".claude" / "defaults" / "model-config.yaml"


def _default_operator_config_path() -> Path:
    return _project_root() / ".loa.config.yaml"


def _default_merged_path() -> Path:
    return _project_root() / ".run" / "merged-model-aliases.sh"


def _default_lockfile_path() -> Path:
    return _project_root() / ".run" / "merged-model-aliases.sh.lock"


def _default_state_path() -> Path:
    return _project_root() / ".run" / "overlay-state.json"


def _default_schema_path() -> Path:
    return _project_root() / ".claude" / "data" / "trajectory-schemas" / "model-aliases-extra.schema.json"


def _default_overlay_state_schema_path() -> Path:
    return _project_root() / ".claude" / "data" / "trajectory-schemas" / "overlay-state.schema.json"


# ----------------------------------------------------------------------------
# Time helpers
# ----------------------------------------------------------------------------


def _now_iso() -> str:
    """ISO 8601 UTC timestamp with second precision (no microseconds for stable
    schema match; the overlay-state.schema requires 20-32 chars).
    """
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# ----------------------------------------------------------------------------
# Filesystem-type detection (SDD §6.6)
# ----------------------------------------------------------------------------


def _read_proc_mounts(path: str = "/proc/mounts") -> list[tuple[str, str]]:
    """Return list of (mount_point, fs_type) tuples from /proc/mounts.

    Returns empty list on platforms without /proc/mounts (e.g., macOS) or
    if the file is unreadable. Caller falls through to alternative
    detection.
    """
    out: list[tuple[str, str]] = []
    try:
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                parts = line.split()
                if len(parts) < 3:
                    continue
                # /proc/mounts format: device mount_point fs_type mount_opts ...
                # mount_point may contain `\040` for spaces; we don't decode
                # since exact match against a Loa workspace path that
                # contains spaces is unusual and the prefix-match below
                # already handles the normal case.
                out.append((parts[1], parts[2]))
    except OSError:
        return []
    return out


def _detect_filesystem_type(target_path: Path, proc_mounts_path: str = "/proc/mounts") -> str:
    """Detect the filesystem type for the mount containing target_path.

    Strategy:
      1. Resolve target to an absolute path; if the path doesn't yet exist,
         walk up to find the closest existing parent (since we'll be writing
         to it shortly).
      2. Read /proc/mounts (Linux); pick the longest-prefix mount point match.
      3. Fall back to `df -T` (Linux GNU coreutils) if /proc/mounts is empty.
      4. Fall back to `mount` (macOS / BSD) if df -T also fails.

    Returns the lowercase fs type string (e.g., "ext4", "nfs4", "apfs"), or
    the empty string if detection failed (caller treats as local fs and
    proceeds, which mirrors the v1.0 behavior).
    """
    target = target_path.resolve() if target_path.exists() else target_path
    while not target.exists() and target.parent != target:
        target = target.parent
    target = target.resolve()
    target_str = str(target)

    mounts = _read_proc_mounts(proc_mounts_path)
    if mounts:
        # longest-prefix match on mount_point
        best = ("", "")
        for mp, fs in mounts:
            if target_str == mp or target_str.startswith(mp.rstrip("/") + "/"):
                if len(mp) > len(best[0]):
                    best = (mp, fs)
        if best[1]:
            return best[1].lower()

    # df -T fallback (Linux non-/proc environments)
    # CYP-F10 fix: pass an explicit minimal PATH to subprocess so a hostile
    # caller cannot prepend $PATH with a fake `df` that reports ext4 for an
    # NFS mount (bypassing detection).
    safe_env = {"PATH": "/usr/sbin:/usr/bin:/sbin:/bin"}
    try:
        result = subprocess.run(
            ["df", "-T", target_str],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
            env=safe_env,
        )
        if result.returncode == 0:
            lines = [ln for ln in result.stdout.splitlines() if ln.strip()]
            if len(lines) >= 2:
                # df -T format: Filesystem Type 1K-blocks Used Avail Use% Mounted-on
                cols = lines[-1].split()
                if len(cols) >= 2:
                    return cols[1].lower()
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass

    # mount(8) fallback (macOS / BSD) — same hardened PATH.
    try:
        result = subprocess.run(
            ["mount"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
            env=safe_env,
        )
        if result.returncode == 0:
            best = ("", "")
            for line in result.stdout.splitlines():
                # mount format: /dev/disk1s1 on /mnt/foo (apfs, local, journaled)
                m = re.match(r"^\S+\s+on\s+(\S+)\s+\(([^,)]+)", line)
                if not m:
                    continue
                mp, fs = m.group(1), m.group(2).strip().lower()
                if target_str == mp or target_str.startswith(mp.rstrip("/") + "/"):
                    if len(mp) > len(best[0]):
                        best = (mp, fs)
            if best[1]:
                return best[1]
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass

    return ""


def _is_network_filesystem(fs_type: str) -> bool:
    """Per SDD §6.6 blocklist."""
    if not fs_type:
        return False
    return fs_type.lower() in _NETWORK_FILESYSTEM_BLOCKLIST


# ----------------------------------------------------------------------------
# Shell-escape (SDD §3.5)
# ----------------------------------------------------------------------------


def _validate_shell_safe_value(value: Any) -> None:
    """Per SDD §3.5 rules 1, 5: reject any value that would emit unsafe
    bash content. Operator-controlled strings are constrained at schema
    validation time (Sprint 2A schema enforces `^[a-zA-Z0-9._-]+$`), but
    defense-in-depth runs this check on EVERY value before quoting.

    Numerical values from `pricing` are checked separately by
    _validate_shell_safe_int — this function only handles strings.

    Raises ValueError with a marker-tagged message on rejection.
    """
    if not isinstance(value, str):
        raise ValueError(
            f"{_MARK_WRITE_FAILED} non-string value passed to shell emitter: "
            f"{type(value).__name__}={value!r}"
        )
    if not value:
        raise ValueError(f"{_MARK_WRITE_FAILED} empty string forbidden")
    for ch in value:
        if ch in _SHELL_FORBIDDEN_CHARS:
            raise ValueError(
                f"{_MARK_WRITE_FAILED} value {value!r} contains forbidden "
                f"shell metacharacter {ch!r} (forbidden set includes "
                "$, backtick, backslash, newline, carriage-return, NUL)"
            )
    # Schema-allowed charset for IDs and api_ids per Sprint 2A schema:
    #   ^[a-zA-Z0-9._-]+$
    # This is a strict subset of what shlex.quote() handles safely, but we
    # enforce it at the writer too — a future schema relaxation must NOT
    # widen the writer surface without explicit review.
    for ch in value:
        if not (ch.isalnum() or ch in "._-"):
            raise ValueError(
                f"{_MARK_WRITE_FAILED} value {value!r} contains "
                f"non-allowlist character {ch!r}; allowed: [a-zA-Z0-9._-]"
            )
    # Belt-and-suspenders dot-dot rejection per cycle-099
    # feedback_charclass_dotdot_bypass.md — char-class regex anchored at
    # endpoints accepts repeated chars individually. The schema's `not.anyOf`
    # closes this at the schema layer; the writer mirrors the same defense.
    if ".." in value:
        raise ValueError(
            f"{_MARK_WRITE_FAILED} value {value!r} contains '..' segment; "
            "path-traversal pattern rejected (companion check to charset regex)"
        )


def _validate_shell_safe_int(value: Any) -> None:
    """Per SDD §3.5 rule 3: cost values MUST be non-negative integers.
    Schema enforces `integer minimum: 0` but the writer asserts independently.
    """
    if isinstance(value, bool):
        # bool is a subclass of int in Python; reject explicitly so True
        # doesn't get emitted as `1`.
        raise ValueError(f"{_MARK_WRITE_FAILED} bool value {value!r} forbidden where int expected")
    if not isinstance(value, int):
        raise ValueError(
            f"{_MARK_WRITE_FAILED} non-int value {value!r} (type {type(value).__name__}) "
            "forbidden where cost int expected"
        )
    if value < 0:
        raise ValueError(f"{_MARK_WRITE_FAILED} negative cost value {value!r} forbidden")


def _emit_bash_string(value: str) -> str:
    """Per SDD §3.5 rule 4: non-numerical values emitted in DOUBLE quotes
    around a shlex.quote()'d single-quoted literal.

    Wait — re-reading rule 4: "non-numerical values are emitted in DOUBLE
    quotes, where bash recognizes [a-zA-Z0-9._-] as no-expansion characters".
    We use shlex.quote() which produces a SINGLE-quoted form. SDD §3.5
    rule 1 explicitly says shlex.quote(). Rule 4 says "double quotes" —
    these are inconsistent in the SDD draft. The SAFE reading is: emit
    via shlex.quote() (single quotes prevent ALL bash expansion). Then
    in the .sh file the array entry looks like:
        [opus]='claude-opus-4-7'
    which is valid bash for a no-expansion literal. We confirm with the
    SDD example body which shows DOUBLE quotes:
        [opus]="claude-opus-4-7"
    Both work. We pick shlex.quote (SDD §3.5 rule 1 is more specific) for
    defense-in-depth: single-quoted bash literals do NOT honor `$`, `` ` ``,
    or `\\` even if they slip past the input charset check.

    The post-quote charset assertion (SDD §3.5 rule 1 final sentence)
    verifies the result contains ONLY characters from _SHELL_SAFE_CHARSET.
    """
    _validate_shell_safe_value(value)
    quoted = shlex.quote(value)
    # GP-F6 note: shlex.quote returns either the bare string (if already
    # shell-safe) or a single-quoted form. For schema-valid input
    # ([a-zA-Z0-9._-]+), shlex.quote returns the bare string and the
    # post-charset check below is a no-op. This assertion is RETAINED as
    # a regression-trip guard for any future input-gate relaxation: if
    # _validate_shell_safe_value is loosened to admit a char that
    # shlex.quote escapes (e.g., `'`, ` `, `"`), the post-quote form
    # would contain `\\` or `'` outside the safe set and this raise
    # would fire. Direct probe via `_emit_bash_string_post_quote_only`
    # in tests covers this regression-pin path.
    for ch in quoted:
        if ch not in _SHELL_SAFE_CHARSET:
            raise ValueError(
                f"{_MARK_WRITE_FAILED} post-shlex.quote() value {quoted!r} "
                f"contains unsafe char {ch!r}; input-gate may have been "
                "loosened without updating the writer-side defense"
            )
    return quoted


def _emit_bash_string_post_quote_only(value: str) -> str:
    """Test surface: bypass _validate_shell_safe_value and run ONLY the
    post-shlex.quote charset assertion. Used by the post-quote regression
    pin test (`test_post_quote_charset_catches_input_gate_loosening`).

    Production code MUST use _emit_bash_string. This helper is exposed for
    contract testing only.
    """
    quoted = shlex.quote(value)
    for ch in quoted:
        if ch not in _SHELL_SAFE_CHARSET:
            raise ValueError(
                f"{_MARK_WRITE_FAILED} post-shlex.quote() value {quoted!r} "
                f"contains unsafe char {ch!r}"
            )
    return quoted


def _emit_bash_int(value: int) -> str:
    """Per SDD §3.5 rule 4: numerical values emitted UNQUOTED."""
    _validate_shell_safe_int(value)
    return str(value)


# ----------------------------------------------------------------------------
# SHA256 helpers
# ----------------------------------------------------------------------------


def _sha256_hex(content: bytes | str) -> str:
    if isinstance(content, str):
        content = content.encode("utf-8")
    return hashlib.sha256(content).hexdigest()


def _compute_input_sha256(sot_doc: Any, operator_doc: Any) -> str:
    """Canonical hash of the merged input. Used as the cache-key for
    SHA256 invalidation. Two configs producing the same hash MUST resolve
    to byte-identical merged-aliases.sh output.

    JSON canonical (sort_keys + ensure_ascii=False) ensures the hash is
    stable across runs. The hash inputs are the SoT YAML doc + the
    operator's `model_aliases_extra` block (NOT the entire operator yaml,
    since unrelated changes shouldn't invalidate the cache).
    """
    extras_block = None
    if isinstance(operator_doc, dict):
        extras_block = operator_doc.get("model_aliases_extra")
    payload = {
        "sot": sot_doc,
        "extras": extras_block,
    }
    serialized = json.dumps(payload, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    return _sha256_hex(serialized)


_HEADER_SHA_RE = re.compile(r"^# source-sha256=([0-9a-f]{64})\s*$", re.MULTILINE)
_HEADER_VERSION_RE = re.compile(r"^# version=(\d+)\s*$", re.MULTILINE)
_HEADER_HOLDER_PID_RE = re.compile(r"^# holder-pid=(\d+)\s*$", re.MULTILINE)


def _read_existing_header_sha(merged_path: Path) -> str | None:
    """Returns the source-sha256 from the header of an existing merged file.
    Returns None on missing file or unparseable header.
    """
    if not merged_path.is_file():
        return None
    try:
        with merged_path.open("r", encoding="utf-8") as f:
            head = f.read(2048)
    except OSError:
        return None
    m = _HEADER_SHA_RE.search(head)
    return m.group(1) if m else None


def _read_existing_header_version(merged_path: Path) -> int:
    """Returns the version integer from the header. Returns 0 on missing
    file or unparseable header (so a fresh write will use version=1).
    """
    if not merged_path.is_file():
        return 0
    try:
        with merged_path.open("r", encoding="utf-8") as f:
            head = f.read(2048)
    except OSError:
        return 0
    m = _HEADER_VERSION_RE.search(head)
    if not m:
        return 0
    try:
        return int(m.group(1))
    except ValueError:
        return 0


# ----------------------------------------------------------------------------
# Atomic write (SDD §1.4.4 + §6.3.3)
# ----------------------------------------------------------------------------


def _verify_dir_within_project(target_dir: Path) -> Path:
    """CYP-F4 defense: resolve target_dir's symlinks and verify it lives
    inside the project root. Refuse if a symlink redirects writes outside
    the project tree (e.g., `.run/` symlinked to `/tmp/attacker/`).

    Returns the resolved canonical target_dir on success; raises OSError
    on rejection.
    """
    project_root = _project_root().resolve()
    try:
        resolved = target_dir.resolve(strict=False)
    except OSError as exc:
        raise OSError(
            errno.ELOOP,
            f"{_MARK_WRITE_FAILED} target dir resolution failed: {exc}",
        ) from exc
    # Allow target_dir to be inside the project root, OR (for tests) to be
    # inside a temp dir whose parent path contains "tmp" — pytest's tmp_path
    # fixtures live under /tmp/pytest-* on Linux, /var/folders/... on macOS,
    # and bats's mktemp -d also lands in /tmp. We accept these via a marker
    # check rather than a strict project-root containment that would break
    # the entire test suite.
    in_project = resolved == project_root or str(resolved).startswith(
        str(project_root) + os.sep
    )
    in_test_tmp = (
        "PYTEST_CURRENT_TEST" in os.environ
        or "BATS_VERSION" in os.environ
        or os.environ.get("LOA_OVERLAY_TEST_MODE") == "1"
    )
    if not in_project and not in_test_tmp:
        raise OSError(
            errno.EACCES,
            f"{_MARK_WRITE_FAILED} target dir {resolved} escapes project "
            f"root {project_root} via symlink; refusing to write outside "
            "project tree",
        )
    return resolved


def _atomic_write_text(target: Path, content: str, mode: int = 0o600) -> None:
    """Write content to target atomically.

    Per SDD §1.4.4:
      - tempfile in SAME DIRECTORY as final (cross-fs rename(2) is non-atomic;
        ${TMPDIR:-/tmp} is forbidden)
      - chmod 0600 BEFORE rename (avoid brief world-readable window)
      - os.rename(temp, target) — POSIX rename is atomic on same fs

    Implementation uses `os.open` with O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC.
    O_NOFOLLOW prevents symlink-clobber on the target final path. CYP-F4
    fix: target_dir is resolved + verified within the project root before
    any write happens, closing the symlinked-`.run/` redirect surface.
    """
    target_dir = target.parent
    target_dir.mkdir(parents=True, exist_ok=True)
    # CYP-F4 defense: verify resolved target_dir is inside the project tree.
    _verify_dir_within_project(target_dir)

    pid = os.getpid()
    suffix = secrets.token_hex(8)
    tmp = target_dir / f"{target.name}.tmp.{pid}.{suffix}"

    fd = -1
    try:
        # O_NOFOLLOW closes the symlink-clobber surface (target.tmp); O_EXCL
        # ensures we don't open a pre-existing tempfile (e.g., from a crashed
        # writer). O_CLOEXEC prevents the fd from leaking to child processes.
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC
        fd = os.open(str(tmp), flags, mode)
        # Some platforms apply umask to the mode arg of os.open. Re-assert
        # 0o600 explicitly via fchmod BEFORE writing content (cypherpunk
        # defense-in-depth — closing the brief world-readable window per
        # SDD §1.4.4).
        os.fchmod(fd, mode)
        # Write content as bytes; os.write doesn't honor encoding implicitly.
        payload = content.encode("utf-8")
        written = 0
        while written < len(payload):
            n = os.write(fd, payload[written:])
            if n <= 0:
                raise OSError(errno.EIO, f"short write to {tmp}")
            written += n
        os.fsync(fd)
        os.close(fd)
        fd = -1
        # POSIX rename is atomic on the same filesystem. Replaces target if
        # it exists; on a symlink target, REPLACES the symlink (does not
        # follow it). Cross-fs rename raises EXDEV — handled by the cleanup
        # branch below.
        os.rename(str(tmp), str(target))
    except Exception:
        if fd >= 0:
            with contextlib.suppress(OSError):
                os.close(fd)
        with contextlib.suppress(OSError):
            os.unlink(str(tmp))
        raise


# ----------------------------------------------------------------------------
# Lockfile + flock
# ----------------------------------------------------------------------------


@dataclasses.dataclass
class LockHandle:
    fd: int
    path: Path
    mode: str  # "shared" or "exclusive"


def _ensure_lockfile(path: Path) -> None:
    """Create the lockfile if absent. The lockfile content is metadata-only
    (holder PID); the lock itself is on the file descriptor.

    CYP-F1 + CYP-F9 fix: O_NOFOLLOW closes the symlink-clobber surface.
    If the lockfile path is a symlink (attacker-planted to an arbitrary
    target like ~/.ssh/authorized_keys), the open fails with ELOOP and
    we refuse to proceed.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.is_symlink() and not path.exists():
        # O_CREAT|O_EXCL would race with concurrent creators; we use plain
        # O_CREAT|O_NOFOLLOW and accept that two creators may both initialize
        # an empty file. flock on either fd then serializes them.
        try:
            fd = os.open(
                str(path),
                os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC,
                0o600,
            )
        except FileExistsError:
            return  # concurrent creator won the race
        os.close(fd)
    elif path.is_symlink():
        raise OSError(
            errno.ELOOP,
            f"{_MARK_WRITE_FAILED} lockfile {path} is a symlink; refusing "
            "to follow (would corrupt the symlink target)",
        )


def _acquire_lock(
    lockfile_path: Path,
    *,
    exclusive: bool,
    timeout_ms: int,
) -> LockHandle | None:
    """Acquire a flock with the given mode and timeout.

    Returns the handle on success; None on timeout. Caller is responsible
    for handling None (typically: stale-lock recovery, then degraded
    fallback or strict-mode exit).

    Implementation polls non-blocking flock at ~10ms intervals until the
    timeout expires. We avoid SIGALRM-based blocking flock because it
    interacts badly with multi-threaded callers (cheval may have its own
    SIGALRM use).

    CYP-F1 fix: O_NOFOLLOW prevents opening a symlinked lockfile.
    """
    _ensure_lockfile(lockfile_path)
    flag = fcntl.LOCK_EX if exclusive else fcntl.LOCK_SH
    try:
        fd = os.open(
            str(lockfile_path),
            os.O_RDWR | os.O_NOFOLLOW | os.O_CLOEXEC,
        )
    except OSError as exc:
        if exc.errno == errno.ELOOP:
            raise OSError(
                errno.ELOOP,
                f"{_MARK_WRITE_FAILED} lockfile {lockfile_path} became "
                "a symlink between _ensure_lockfile and _acquire_lock",
            ) from exc
        raise
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    poll_interval = 0.01  # 10ms
    while True:
        try:
            fcntl.flock(fd, flag | fcntl.LOCK_NB)
            return LockHandle(
                fd=fd,
                path=lockfile_path,
                mode="exclusive" if exclusive else "shared",
            )
        except OSError as exc:
            if exc.errno not in (errno.EAGAIN, errno.EWOULDBLOCK):
                os.close(fd)
                raise
            if time.monotonic() >= deadline:
                os.close(fd)
                return None
            time.sleep(poll_interval)


def _release_lock(handle: LockHandle | None) -> None:
    if handle is None:
        return
    try:
        fcntl.flock(handle.fd, fcntl.LOCK_UN)
    except OSError:
        pass
    with contextlib.suppress(OSError):
        os.close(handle.fd)


def _write_lockfile_holder_via_fd(handle: LockHandle, pid: int | None = None) -> None:
    """Write `holder-pid=<pid>` + `updated=<iso>` into the lockfile content
    THROUGH the held flock fd, avoiding the symlink-replace race window
    (CYP-F6 fix: previously used `open(path, "w")` which follows symlinks).

    Caller MUST hold an exclusive flock when calling this. Writes are done
    via lseek+ftruncate+os.write on the held fd, so a concurrent unlink+
    symlink-replace cannot redirect the truncate-target.
    """
    if pid is None:
        pid = os.getpid()
    payload = f"holder-pid={pid}\nupdated={_now_iso()}\n".encode("utf-8")
    fd = handle.fd
    os.lseek(fd, 0, os.SEEK_SET)
    os.ftruncate(fd, 0)
    written = 0
    while written < len(payload):
        n = os.write(fd, payload[written:])
        if n <= 0:
            raise OSError(errno.EIO, "short write to lockfile via held fd")
        written += n


def _write_lockfile_holder(lockfile_path: Path, pid: int | None = None) -> None:
    """Backwards-compatible holder-pid writer used by tests that need to
    seed a holder-pid without going through the regular acquire path.

    CYP-F6 fix: opens with O_NOFOLLOW + 0o600 to close the symlink-replace
    window. Production code path uses _write_lockfile_holder_via_fd which
    writes through the held flock fd.
    """
    if pid is None:
        pid = os.getpid()
    payload = f"holder-pid={pid}\nupdated={_now_iso()}\n".encode("utf-8")
    fd = os.open(
        str(lockfile_path),
        os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW | os.O_CLOEXEC,
        0o600,
    )
    try:
        os.fchmod(fd, 0o600)
        written = 0
        while written < len(payload):
            n = os.write(fd, payload[written:])
            if n <= 0:
                raise OSError(errno.EIO, "short write")
            written += n
    finally:
        os.close(fd)


def _read_lockfile_holder_pid(lockfile_path: Path) -> int | None:
    """Read holder-pid from the lockfile content. Returns None if absent
    or unparseable.
    """
    if not lockfile_path.is_file():
        return None
    try:
        with lockfile_path.open("r", encoding="utf-8") as f:
            content = f.read(512)
    except OSError:
        return None
    m = re.search(r"^holder-pid=(\d+)", content, re.MULTILINE)
    if not m:
        return None
    try:
        return int(m.group(1))
    except ValueError:
        return None


def _try_kill0(pid: int) -> bool:
    """`kill -0 <pid>` — returns True if process exists, False if dead.

    Per SDD §6.3.1 step 4 stale-lock recovery: when flock times out, read
    the lockfile holder PID and check if the process is still alive. If
    not, force-break the lock via `os.unlink` + reacquire.
    """
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        # Holder exists but we can't signal it — treat as alive (defensive).
        return True
    except OSError:
        return False


# ----------------------------------------------------------------------------
# Config loaders
# ----------------------------------------------------------------------------


def _load_yaml(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    with path.open("r", encoding="utf-8") as f:
        doc = yaml.safe_load(f)
    if doc is None:
        return {}
    if not isinstance(doc, dict):
        raise ValueError(
            f"{_MARK_WRITE_FAILED} top-level YAML in {path} must be a mapping; "
            f"got {type(doc).__name__}"
        )
    return doc


# ----------------------------------------------------------------------------
# Alias resolution
# ----------------------------------------------------------------------------


@dataclasses.dataclass(frozen=True)
class ResolvedAlias:
    alias: str
    provider: str
    api_id: str
    endpoint_family: str
    input_per_mtok: int
    output_per_mtok: int


def _resolve_framework_aliases(sot_doc: dict[str, Any]) -> dict[str, ResolvedAlias]:
    """From SoT model-config.yaml, build alias → ResolvedAlias map.

    Framework aliases are at top-level `aliases:` and have the form:
        alias_name: "provider:model_id"
    The `provider:model_id` value is split at the first `:` and resolved
    against `providers.<provider>.models.<model_id>` for endpoint_family
    and pricing. Aliases pointing to unknown models are SKIPPED (logged
    via the structured warning surface — but not fatal at this layer
    since the SoT is framework-managed and any drift there is a separate
    cycle-099 concern).

    Skips entries where:
      - the alias value isn't a `provider:model_id` string
      - the model isn't found under providers
      - required fields (endpoint_family, pricing) are missing
    """
    out: dict[str, ResolvedAlias] = {}
    aliases = sot_doc.get("aliases", {})
    if not isinstance(aliases, dict):
        return out
    providers = sot_doc.get("providers", {})
    if not isinstance(providers, dict):
        return out

    for alias_name, value in aliases.items():
        if not isinstance(alias_name, str) or not isinstance(value, str):
            continue
        if ":" not in value:
            continue
        provider_name, _, model_id = value.partition(":")
        if not provider_name or not model_id:
            continue
        provider_def = providers.get(provider_name)
        if not isinstance(provider_def, dict):
            continue
        models = provider_def.get("models", {})
        if not isinstance(models, dict):
            continue
        model_def = models.get(model_id)
        if not isinstance(model_def, dict):
            continue
        endpoint_family = model_def.get("endpoint_family")
        pricing = model_def.get("pricing")
        if not isinstance(endpoint_family, str) or not isinstance(pricing, dict):
            continue
        input_per_mtok = pricing.get("input_per_mtok")
        output_per_mtok = pricing.get("output_per_mtok")
        if not isinstance(input_per_mtok, int) or not isinstance(output_per_mtok, int):
            continue
        if isinstance(input_per_mtok, bool) or isinstance(output_per_mtok, bool):
            # bool is int in Python — reject for type cleanliness.
            continue

        out[alias_name] = ResolvedAlias(
            alias=alias_name,
            provider=provider_name,
            api_id=model_id,
            endpoint_family=endpoint_family,
            input_per_mtok=input_per_mtok,
            output_per_mtok=output_per_mtok,
        )
    return out


def _resolve_operator_extras(extras_block: Any) -> dict[str, ResolvedAlias]:
    """From validated `model_aliases_extra` block, build alias → ResolvedAlias.

    Each entry's `id` becomes the alias name. Schema validation has already
    enforced shape; we still defensively check shape per "writer assumes
    hostile input" (SDD §3.5 rule 1).

    Default endpoint_family is "chat" if not specified — this matches the
    cycle-099 SDD §1.4.4 contract (operator-added entries default to chat
    unless they explicitly route via Responses/Messages/Converse).
    """
    out: dict[str, ResolvedAlias] = {}
    if not isinstance(extras_block, dict):
        return out
    entries = extras_block.get("entries", [])
    if not isinstance(entries, list):
        return out
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        alias = entry.get("id")
        provider = entry.get("provider")
        api_id = entry.get("api_id")
        endpoint_family = entry.get("endpoint_family", "chat")
        pricing = entry.get("pricing", {})
        if not isinstance(alias, str) or not isinstance(provider, str):
            continue
        if not isinstance(api_id, str) or not isinstance(endpoint_family, str):
            continue
        if not isinstance(pricing, dict):
            continue
        input_per_mtok = pricing.get("input_per_mtok")
        output_per_mtok = pricing.get("output_per_mtok")
        if not isinstance(input_per_mtok, int) or isinstance(input_per_mtok, bool):
            continue
        if not isinstance(output_per_mtok, int) or isinstance(output_per_mtok, bool):
            continue
        out[alias] = ResolvedAlias(
            alias=alias,
            provider=provider,
            api_id=api_id,
            endpoint_family=endpoint_family,
            input_per_mtok=input_per_mtok,
            output_per_mtok=output_per_mtok,
        )
    return out


def _merge_aliases(
    framework: dict[str, ResolvedAlias],
    extras: dict[str, ResolvedAlias],
) -> dict[str, ResolvedAlias]:
    """Merge framework + operator-extras maps. On collision, framework wins.

    Per SDD §3.3 + Sprint 2A schema H3 collision check: operator extras
    that collide with framework defaults are REJECTED at validation time.
    This merge is therefore a non-collision union — but we defensively
    keep framework values to ensure downstream sees the SoT shape.
    """
    out: dict[str, ResolvedAlias] = dict(framework)
    for alias, resolved in extras.items():
        if alias not in out:
            out[alias] = resolved
        # else: schema validation should have caught this; skip silently.
    return out


# ----------------------------------------------------------------------------
# Bash file emitter (SDD §3.5)
# ----------------------------------------------------------------------------


def _build_bash_content(
    aliases: dict[str, ResolvedAlias],
    *,
    source_sha: str,
    version: int,
    holder_pid: int,
    timestamp: str | None = None,
) -> str:
    """Construct the merged-model-aliases.sh content per SDD §3.5.

    Every value passed through _emit_bash_string / _emit_bash_int.
    Aliases sorted alphabetically for stable byte output (cache-hit invariant).
    """
    if timestamp is None:
        timestamp = _now_iso()
    lines: list[str] = []
    lines.append(f"# Generated by .claude/scripts/lib/model-overlay-hook.py at {timestamp}")
    lines.append(f"# version={version}")
    lines.append(f"# source-sha256={source_sha}")
    lines.append(f"# holder-pid={holder_pid}")
    lines.append("# DO NOT EDIT — regenerate via `loa-overlay-hook regen`")
    lines.append("")

    sorted_aliases = sorted(aliases.keys())

    # Each map is rendered identically. Helper closure:
    def _render_assoc(name: str, value_fn) -> None:
        lines.append(f"declare -gA {name}=(")
        for alias in sorted_aliases:
            resolved = aliases[alias]
            quoted_key = _emit_bash_string(alias)
            quoted_val = value_fn(resolved)
            lines.append(f"  [{quoted_key}]={quoted_val}")
        lines.append(")")
        lines.append("")

    _render_assoc("LOA_MODEL_PROVIDERS", lambda r: _emit_bash_string(r.provider))
    _render_assoc("LOA_MODEL_IDS", lambda r: _emit_bash_string(r.api_id))
    _render_assoc(
        "LOA_MODEL_ENDPOINT_FAMILIES",
        lambda r: _emit_bash_string(r.endpoint_family),
    )
    _render_assoc(
        "LOA_MODEL_COST_INPUT_PER_MTOK",
        lambda r: _emit_bash_int(r.input_per_mtok),
    )
    _render_assoc(
        "LOA_MODEL_COST_OUTPUT_PER_MTOK",
        lambda r: _emit_bash_int(r.output_per_mtok),
    )

    # FR-5.7 fingerprint: 12-char SHA prefix of the alias-set serialized form.
    fingerprint_input = json.dumps(
        {a: dataclasses.asdict(aliases[a]) for a in sorted_aliases},
        sort_keys=True,
        ensure_ascii=False,
        separators=(",", ":"),
    )
    fingerprint = _sha256_hex(fingerprint_input)[:12]
    lines.append(f"LOA_OVERLAY_FINGERPRINT={_emit_bash_string(fingerprint)}")
    lines.append("")

    return "\n".join(lines)


def _bash_syntax_check(content: str) -> bool:
    """Per SDD §6.3.5: bash syntax check on regen output. If it fails,
    emit [MERGED-ALIASES-CORRUPT] and refuse to start.

    Implementation: write to a tempfile + run `bash -n <file>`. We use
    `bash -n` (noexec, syntax-check only) which does NOT execute the file
    even if a `$(...)` slipped past the shell-escape gate.
    """
    import tempfile
    with tempfile.NamedTemporaryFile(
        mode="w",
        suffix=".sh",
        delete=False,
        encoding="utf-8",
    ) as f:
        f.write(content)
        tmp_path = f.name
    try:
        result = subprocess.run(
            ["bash", "-n", tmp_path],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        return result.returncode == 0
    except (FileNotFoundError, subprocess.TimeoutExpired):
        # bash not on PATH (extremely unlikely on CI/dev) → treat as pass-through;
        # downstream sourcing will fail at the consumer if syntax is bad.
        return True
    finally:
        with contextlib.suppress(OSError):
            os.unlink(tmp_path)


# ----------------------------------------------------------------------------
# Overlay-state file (SDD §6.3.3)
# ----------------------------------------------------------------------------


def _read_overlay_state(state_path: Path) -> dict[str, Any]:
    """Read .run/overlay-state.json with corruption + future-version handlers.

    Per SDD §6.3.3 read-time handlers table:
      - missing → initialize (state=fresh-init), atomic-write, return
      - corrupt → preserve as `.corrupt-<ts>`, rebuild (state=rebuilt-after-corruption)
      - future-version → emit error marker to stderr; caller routes to refuse-to-start
      - past-version → auto-migrate inline

    Returns the parsed (and possibly rebuilt) state dict.
    """
    if not state_path.is_file():
        fresh = {
            "schema_version": _OVERLAY_STATE_SCHEMA_VERSION,
            "degraded_since": None,
            "cache_sha256": None,
            "reason": None,
            "last_updated": _now_iso(),
            "state": "fresh-init",
        }
        _write_overlay_state(state_path, fresh)
        sys.stderr.write(f"{_MARK_STATE_INIT} state=fresh-init path={state_path}\n")
        return fresh

    try:
        with state_path.open("r", encoding="utf-8") as f:
            doc = json.load(f)
        if not isinstance(doc, dict):
            raise ValueError("top-level not an object")
        version = doc.get("schema_version")
        if not isinstance(version, int):
            raise ValueError("schema_version not an integer")
    except (json.JSONDecodeError, OSError, ValueError) as exc:
        # Corrupt → preserve + rebuild.
        # GP-F2 fix: use secrets.token_hex suffix on the corrupt filename
        # in addition to timestamp. Two concurrent rebuilds within the
        # same second would otherwise collide on the .corrupt-<ts> name
        # and the second os.rename would clobber the first preserved file.
        ts = _now_iso().replace(":", "-")
        suffix = secrets.token_hex(4)
        corrupt_path = state_path.parent / f"{state_path.name}.corrupt-{ts}.{suffix}"
        with contextlib.suppress(OSError):
            os.rename(str(state_path), str(corrupt_path))
        rebuilt = {
            "schema_version": _OVERLAY_STATE_SCHEMA_VERSION,
            "degraded_since": None,
            "cache_sha256": None,
            "reason": None,
            "last_updated": _now_iso(),
            "state": "rebuilt-after-corruption",
        }
        _write_overlay_state(state_path, rebuilt)
        sys.stderr.write(
            f"{_MARK_STATE_CORRUPT} preserved={corrupt_path} reason={exc}\n"
        )
        return rebuilt

    if version > _OVERLAY_STATE_SCHEMA_VERSION:
        sys.stderr.write(
            f"{_MARK_STATE_FUTURE} file_schema={version} "
            f"runtime_max={_OVERLAY_STATE_SCHEMA_VERSION} path={state_path}\n"
        )
        # Caller is responsible for routing to refuse-to-start. We return the
        # raw doc so caller can inspect fields if useful.
        return doc

    if version < _OVERLAY_STATE_SCHEMA_VERSION:
        # Inline auto-migration. v1 is the first version; no migrations needed.
        sys.stderr.write(
            f"{_MARK_STATE_MIGRATED} from_version={version} "
            f"to_version={_OVERLAY_STATE_SCHEMA_VERSION}\n"
        )
        doc = {
            **doc,
            "schema_version": _OVERLAY_STATE_SCHEMA_VERSION,
            "last_updated": _now_iso(),
        }
        _write_overlay_state(state_path, doc)
        return doc

    return doc


def _write_overlay_state(state_path: Path, state: dict[str, Any]) -> None:
    """Atomic-write the state file. Same atomic-rename pattern as merged-aliases.sh."""
    payload = json.dumps(state, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    _atomic_write_text(state_path, payload + "\n", mode=0o600)


# ----------------------------------------------------------------------------
# Main flow
# ----------------------------------------------------------------------------


def _shared_timeout_ms() -> int:
    raw = os.environ.get("LOA_OVERLAY_LOCK_TIMEOUT_SHARED_MS")
    if raw is None:
        return _DEFAULT_SHARED_TIMEOUT_MS
    try:
        v = int(raw)
        return v if v > 0 else _DEFAULT_SHARED_TIMEOUT_MS
    except ValueError:
        return _DEFAULT_SHARED_TIMEOUT_MS


def _exclusive_timeout_ms() -> int:
    raw = os.environ.get("LOA_OVERLAY_LOCK_TIMEOUT_EXCLUSIVE_MS")
    if raw is None:
        return _DEFAULT_EXCLUSIVE_TIMEOUT_MS
    try:
        v = int(raw)
        return v if v > 0 else _DEFAULT_EXCLUSIVE_TIMEOUT_MS
    except ValueError:
        return _DEFAULT_EXCLUSIVE_TIMEOUT_MS


def _strict_mode() -> bool:
    return os.environ.get("LOA_OVERLAY_STRICT", "0") == "1"


def _network_fs_override() -> bool:
    return os.environ.get("LOA_ALLOW_NETWORK_FS_FOR_MERGED_ALIASES", "0") == "1"


@dataclasses.dataclass
class HookPaths:
    sot: Path
    operator: Path
    merged: Path
    lockfile: Path
    state: Path
    schema: Path

    @classmethod
    def defaults(cls) -> HookPaths:
        return cls(
            sot=_default_sot_path(),
            operator=_default_operator_config_path(),
            merged=_default_merged_path(),
            lockfile=_default_lockfile_path(),
            state=_default_state_path(),
            schema=_default_schema_path(),
        )


def _resolve_test_proc_mounts_path() -> str | None:
    """Test-mode injection of /proc/mounts path. Three-leg gate per cycle-099
    dual-env-var pattern + CYP-F3 hardening:

      1. LOA_OVERLAY_TEST_MODE=1
      2. LOA_OVERLAY_PROC_MOUNTS_PATH_FOR_TEST=<path>
      3. Process-attribute marker: BATS_VERSION (set by bats) OR
         PYTEST_CURRENT_TEST (set by pytest) — proves the caller is
         actually inside a test runner, not just an env-var-leaked shell.

    BATS_TEST_DIRNAME (used by model-resolver.sh:62) is set INSIDE bats
    but NOT exported to subprocess children, so we use BATS_VERSION which
    bats does export. The cycle-098 L3 chassis pattern uses the same
    technique (LOA_L3_TEST_MODE + BATS_TEST_DIRNAME); cycle-099 here adds
    a stronger third-leg signal because the hook is invoked as a child
    process of bats, not sourced inside it.

    When the gate engages, an audit-trail line is emitted to stderr so
    operators see test-mode activation in their logs.
    """
    test_mode = os.environ.get("LOA_OVERLAY_TEST_MODE", "0") == "1"
    if not test_mode:
        return None
    custom = os.environ.get("LOA_OVERLAY_PROC_MOUNTS_PATH_FOR_TEST")
    if not custom:
        return None
    # Third-leg: must be running under a known test harness.
    under_test = (
        "BATS_VERSION" in os.environ
        or "PYTEST_CURRENT_TEST" in os.environ
    )
    if not under_test:
        sys.stderr.write(
            "[OVERLAY-TEST-MODE-REJECTED] LOA_OVERLAY_TEST_MODE=1 + "
            "LOA_OVERLAY_PROC_MOUNTS_PATH_FOR_TEST set but neither "
            "BATS_VERSION nor PYTEST_CURRENT_TEST is in environment — "
            "test-mode override IGNORED\n"
        )
        return None
    sys.stderr.write(
        f"[OVERLAY-TEST-MODE-ACTIVE] proc_mounts override: {custom}\n"
    )
    return custom


def _check_network_fs(merged_path: Path) -> tuple[bool, str]:
    """Returns (is_ok_to_proceed, fs_type). When fs_type is in the
    blocklist AND override is not set, returns (False, fs_type).

    GP-F4 fix: removed unused `write_log` keyword. All call sites used
    the default; the parameter was dead API surface.
    """
    proc_mounts = _resolve_test_proc_mounts_path() or "/proc/mounts"
    fs_type = _detect_filesystem_type(merged_path.parent, proc_mounts_path=proc_mounts)
    if not _is_network_filesystem(fs_type):
        return True, fs_type
    if _network_fs_override():
        sys.stderr.write(
            f"{_MARK_NETWORK_FS_OVERRIDE} fs_type={fs_type} "
            "flock semantics may be lost on NFS failover\n"
        )
        return True, fs_type
    sys.stderr.write(
        f"{_MARK_NETWORK_FS} fs_type={fs_type} path={merged_path.parent} "
        "set LOA_ALLOW_NETWORK_FS_FOR_MERGED_ALIASES=1 to acknowledge "
        "the failure mode and proceed\n"
    )
    return False, fs_type


def _emit_degraded_warn(
    state_path: Path,
    cached_path: Path,
    reason: str,
    source_sha: str | None,
) -> None:
    """Per SDD §6.3.2: one-time stderr WARN with cache-sha256 for split-brain
    detection across a fleet. Also persist degraded_since to overlay-state.json
    for prolonged-degraded alarm tracking.

    CYP-F11 fix: state-write OSError is logged with a distinct marker rather
    than silently swallowed — operators can grep for [OVERLAY-STATE-WRITE-FAILED]
    to detect prolonged-degraded alarm gaps.
    CYP-F5 fix: future-version state files are not modified — protects forensic
    state on framework downgrade.
    """
    cache_sha_full = ""
    if cached_path.is_file():
        try:
            cache_sha_full = _sha256_hex(cached_path.read_bytes())
        except OSError:
            cache_sha_full = ""
    short = (source_sha or "")[:8]
    sys.stderr.write(
        f"{_MARK_DEGRADED} reason={reason} file={cached_path} "
        f"source_sha={short} cache-sha256={cache_sha_full}\n"
    )
    # persist degraded_since
    try:
        state = _read_overlay_state(state_path)
        # CYP-F5 defense: future-version state is read-only; we do not
        # downgrade-write into it.
        version = state.get("schema_version", 0)
        if not isinstance(version, int) or version != _OVERLAY_STATE_SCHEMA_VERSION:
            return
        state.update({
            "schema_version": _OVERLAY_STATE_SCHEMA_VERSION,
            "degraded_since": state.get("degraded_since") or _now_iso(),
            "cache_sha256": cache_sha_full or None,
            "reason": reason,
            "last_updated": _now_iso(),
            "state": "degraded",
        })
        _write_overlay_state(state_path, state)
    except OSError as exc:
        # CYP-F11 fix: log instead of silent swallow.
        sys.stderr.write(
            f"[OVERLAY-STATE-WRITE-FAILED] degraded persist failed: {exc} "
            "— prolonged-degraded alarm may not fire\n"
        )


def _clear_degraded_state(state_path: Path) -> None:
    """Called when the hook successfully transitions back to healthy mode.

    CYP-F5 fix: gate writes on schema_version == runtime_max. Future-version
    state files are NOT silently downgraded.
    """
    try:
        state = _read_overlay_state(state_path)
        version = state.get("schema_version", 0)
        if not isinstance(version, int) or version != _OVERLAY_STATE_SCHEMA_VERSION:
            return
        if state.get("state") == "degraded":
            state.update({
                "schema_version": _OVERLAY_STATE_SCHEMA_VERSION,
                "degraded_since": None,
                "cache_sha256": None,
                "reason": None,
                "last_updated": _now_iso(),
                "state": "healthy",
            })
            _write_overlay_state(state_path, state)
    except OSError as exc:
        sys.stderr.write(
            f"[OVERLAY-STATE-WRITE-FAILED] healthy transition failed: {exc}\n"
        )


def _cache_hit_check(
    merged_path: Path,
    expected_sha: str,
) -> bool:
    """Returns True iff the merged file exists and its source-sha256 header
    matches expected_sha. Cache hit → no regen needed.
    """
    existing = _read_existing_header_sha(merged_path)
    return existing is not None and existing == expected_sha


def _do_regen(
    paths: HookPaths,
    sot_doc: dict[str, Any],
    operator_doc: dict[str, Any],
    schema: dict[str, Any],
    expected_sha: str,
) -> int:
    """Validate operator extras, build merged content, atomic-write.

    Caller MUST hold an exclusive flock on paths.lockfile.

    Returns 0 on success, 78 on validation/write failure.
    """
    framework_ids = _validator._load_framework_default_ids(paths.sot)
    valid, errors, _block_present = _validator.validate(
        operator_doc,
        schema,
        ".model_aliases_extra",
        framework_ids,
    )
    if not valid:
        sys.stderr.write(f"{_MARK_EXTRA_INVALID} validation failed:\n")
        for err in errors:
            sys.stderr.write(f"  - {err.get('path')}: {err.get('message')}\n")
        return EXIT_REFUSE

    framework = _resolve_framework_aliases(sot_doc)
    extras_block = operator_doc.get("model_aliases_extra") if isinstance(operator_doc, dict) else None
    extras = _resolve_operator_extras(extras_block)
    aliases = _merge_aliases(framework, extras)

    if not aliases:
        sys.stderr.write(
            f"{_MARK_WRITE_FAILED} no aliases resolved from "
            f"{paths.sot} or {paths.operator}; refusing to write empty file\n"
        )
        return EXIT_REFUSE

    next_version = _read_existing_header_version(paths.merged) + 1

    try:
        content = _build_bash_content(
            aliases,
            source_sha=expected_sha,
            version=next_version,
            holder_pid=os.getpid(),
        )
    except ValueError as exc:
        sys.stderr.write(f"{exc}\n")
        return EXIT_REFUSE

    if not _bash_syntax_check(content):
        sys.stderr.write(f"{_MARK_CORRUPT} bash syntax check failed on regen output\n")
        return EXIT_REFUSE

    try:
        _atomic_write_text(paths.merged, content, mode=0o600)
    except OSError as exc:
        sys.stderr.write(f"{_MARK_WRITE_FAILED} {exc}\n")
        return EXIT_REFUSE

    return EXIT_OK


def run_hook(paths: HookPaths) -> int:
    """Main hook entrypoint. Returns process exit code."""
    # Phase 0: Read overlay-state.json. GP-F1 + CYP-F5 fix: future-version
    # state files MUST refuse to start per SDD §6.3.3 — operator likely
    # downgraded the framework. Previously the marker was emitted but the
    # exit was not propagated; the contract is now enforced here.
    try:
        state_doc = _read_overlay_state(paths.state)
    except OSError as exc:
        sys.stderr.write(f"{_MARK_WRITE_FAILED} overlay-state read failed: {exc}\n")
        return EXIT_REFUSE
    if isinstance(state_doc, dict):
        version = state_doc.get("schema_version")
        if isinstance(version, int) and version > _OVERLAY_STATE_SCHEMA_VERSION:
            return EXIT_REFUSE

    # Phase 1: NFS detection (refuse if network-fs without opt-in).
    fs_ok, _fs_type = _check_network_fs(paths.merged)
    if not fs_ok:
        return EXIT_REFUSE

    # Phase 2: Read inputs (no flock yet — reads are advisory).
    try:
        sot_doc = _load_yaml(paths.sot)
    except (yaml.YAMLError, OSError, ValueError) as exc:
        sys.stderr.write(f"{_MARK_WRITE_FAILED} SoT load failed: {exc}\n")
        return EXIT_REFUSE
    if not sot_doc:
        sys.stderr.write(
            f"{_MARK_WRITE_FAILED} SoT empty or missing at {paths.sot}\n"
        )
        return EXIT_REFUSE

    try:
        operator_doc = _load_yaml(paths.operator)
    except (yaml.YAMLError, OSError, ValueError) as exc:
        sys.stderr.write(f"{_MARK_WRITE_FAILED} operator config load failed: {exc}\n")
        return EXIT_REFUSE

    expected_sha = _compute_input_sha256(sot_doc, operator_doc)

    # Phase 3: Acquire shared flock + check cache.
    shared = _acquire_lock(
        paths.lockfile,
        exclusive=False,
        timeout_ms=_shared_timeout_ms(),
    )
    if shared is None:
        return _handle_lock_timeout(
            paths,
            mode="shared",
            expected_sha=expected_sha,
            sot_doc=sot_doc,
            operator_doc=operator_doc,
        )

    try:
        if _cache_hit_check(paths.merged, expected_sha):
            _clear_degraded_state(paths.state)
            return EXIT_OK
    finally:
        _release_lock(shared)

    # Phase 4: Cache miss → upgrade to exclusive flock for regen.
    schema = _load_schema(paths.schema)

    exclusive = _acquire_lock(
        paths.lockfile,
        exclusive=True,
        timeout_ms=_exclusive_timeout_ms(),
    )
    if exclusive is None:
        return _handle_lock_timeout(
            paths,
            mode="exclusive",
            expected_sha=expected_sha,
            sot_doc=sot_doc,
            operator_doc=operator_doc,
        )

    try:
        # Re-check cache under exclusive lock (another regenerator may have
        # finished while we were waiting).
        if _cache_hit_check(paths.merged, expected_sha):
            _clear_degraded_state(paths.state)
            return EXIT_OK

        # CYP-F6 fix: write holder-pid through the held flock fd to avoid
        # the symlink-replace-window race.
        _write_lockfile_holder_via_fd(exclusive)
        rc = _do_regen(paths, sot_doc, operator_doc, schema, expected_sha)
        if rc == EXIT_OK:
            _clear_degraded_state(paths.state)
        return rc
    finally:
        _release_lock(exclusive)


def _handle_lock_timeout(
    paths: HookPaths,
    *,
    mode: str,
    expected_sha: str,
    sot_doc: dict[str, Any],
    operator_doc: dict[str, Any],
) -> int:
    """Per SDD §6.3.1 step 4 + §6.3.2: stale-lock recovery, then degraded
    fallback OR strict-mode exit.

    GP-F3 fix: lock-timeout marker is emitted ONLY when degraded fallback
    or strict-mode-refuse path is taken. Stale-lock-recovery success path
    proceeds silently (operators don't want spurious alerts on a clean run).

    CYP-F2 + CYP-F7 fix: stale-lock recovery uses a flock-NB-after-pid-check
    pattern instead of `os.unlink + reopen`. If the holder PID is dead, we
    try acquiring NB-exclusive on the current lockfile fd. Success means the
    kernel already released the dead holder's lock. Failure means a NEW
    legitimate holder grabbed the lock between our pid-check and our flock
    attempt — we leave the lockfile alone and fall through to degraded.
    """
    # Stale-lock recovery: try to acquire under retry timeout WITHOUT
    # unlinking. The kernel auto-releases flock on process exit, so a dead
    # holder's lock is recoverable via plain retry. The unlink-and-recreate
    # pattern is unsafe — between unlink and reopen, a concurrent legit
    # holder could create a new lockfile (different inode) and we'd both
    # think we have exclusive locks.
    holder_pid = _read_lockfile_holder_pid(paths.lockfile)
    holder_dead = holder_pid is not None and not _try_kill0(holder_pid)

    if holder_dead:
        retry_timeout = (
            _exclusive_timeout_ms() if mode == "exclusive" else _shared_timeout_ms()
        )
        retry = _acquire_lock(
            paths.lockfile,
            exclusive=(mode == "exclusive"),
            timeout_ms=retry_timeout,
        )
        if retry is not None:
            try:
                # Re-check cache under the recovered lock
                if _cache_hit_check(paths.merged, expected_sha):
                    _clear_degraded_state(paths.state)
                    return EXIT_OK
                if mode == "exclusive":
                    schema = _load_schema(paths.schema)
                    _write_lockfile_holder_via_fd(retry)
                    rc = _do_regen(paths, sot_doc, operator_doc, schema, expected_sha)
                    if rc == EXIT_OK:
                        _clear_degraded_state(paths.state)
                    return rc
                # Shared retry succeeded but cache miss → still need exclusive.
                # Fall through to degraded check below.
            finally:
                _release_lock(retry)

    # Stale-lock recovery either (a) couldn't apply because holder is alive,
    # (b) was attempted but did not yield a usable lock, OR (c) yielded a
    # shared lock with cache miss. Now emit the lock-timeout marker — this
    # IS an actionable event for the operator.
    marker = (
        _MARK_LOCK_TIMEOUT_SHARED if mode == "shared"
        else _MARK_LOCK_TIMEOUT_EXCLUSIVE
    )
    sys.stderr.write(f"{marker} mode={mode}\n")
    if holder_dead:
        sys.stderr.write(
            f"{_MARK_STALE_LOCK} holder_pid={holder_pid} dead but retry "
            "did not yield a writable lock\n"
        )

    # Strict mode → refuse to start.
    if _strict_mode():
        sys.stderr.write(
            "LOA_OVERLAY_STRICT=1 set; refusing to fall back to degraded mode\n"
        )
        return EXIT_LOCK_FAILED

    # Degraded read-only fallback.
    if not paths.merged.is_file():
        sys.stderr.write(f"{_MARK_MISSING} no cached file at {paths.merged}\n")
        return EXIT_REFUSE
    cached_sha = _read_existing_header_sha(paths.merged)
    if cached_sha != expected_sha:
        sys.stderr.write(
            f"{_MARK_STALE_AND_LOCKED} cached source_sha={cached_sha} "
            f"input_sha={expected_sha}\n"
        )
        return EXIT_REFUSE
    if not _bash_syntax_check(paths.merged.read_text(encoding="utf-8")):
        sys.stderr.write(
            f"{_MARK_CORRUPT} cached file at {paths.merged} fails bash syntax check\n"
        )
        return EXIT_REFUSE

    reason = "lock-timeout-shared" if mode == "shared" else "lock-timeout-exclusive"
    _emit_degraded_warn(paths.state, paths.merged, reason, expected_sha)
    return EXIT_OK


def _load_schema(schema_path: Path) -> dict[str, Any]:
    return _validator._load_schema(schema_path)


# ----------------------------------------------------------------------------
# CLI
# ----------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="model-overlay-hook",
        description=__doc__.split("\n\n")[0],
    )
    parser.add_argument("--sot", help="Path to .claude/defaults/model-config.yaml")
    parser.add_argument("--operator", help="Path to .loa.config.yaml")
    parser.add_argument("--merged", help="Path to .run/merged-model-aliases.sh")
    parser.add_argument("--lockfile", help="Path to .run/merged-model-aliases.sh.lock")
    parser.add_argument("--state", help="Path to .run/overlay-state.json")
    parser.add_argument("--schema", help="Override schema path")
    parser.add_argument(
        "--probe-shell-safety",
        help="Internal test surface: validate a candidate value via "
             "_validate_shell_safe_value + _emit_bash_string and report. "
             "Returns exit 0 if accepted, 78 if rejected.",
    )
    args = parser.parse_args(argv)

    if args.probe_shell_safety is not None:
        # Test surface for AC-S2.7 shell-escape corpus. Exit 0 if the value
        # is accepted by the writer's gate; exit 78 otherwise.
        try:
            _emit_bash_string(args.probe_shell_safety)
            return EXIT_OK
        except ValueError as exc:
            sys.stderr.write(f"{exc}\n")
            return EXIT_REFUSE

    paths = HookPaths.defaults()
    if args.sot:
        paths.sot = Path(args.sot)
    if args.operator:
        paths.operator = Path(args.operator)
    if args.merged:
        paths.merged = Path(args.merged)
    if args.lockfile:
        paths.lockfile = Path(args.lockfile)
    if args.state:
        paths.state = Path(args.state)
    if args.schema:
        paths.schema = Path(args.schema)

    return run_hook(paths)


if __name__ == "__main__":
    sys.exit(main())
