#!/usr/bin/env python3
"""Offline verifier and sealed-candidate writer for aleph-for-loa releases.

This is deliberately a Loa-owned, Python-stdlib-only trust boundary.  It never
imports or executes code from a release, bundle, or installation candidate.
GitHub release and asset attestations are checked by the read-only workflow
before this program is invoked; this program verifies every local byte and the
complete transitive identity graph before materializing a bundle.
"""

from __future__ import annotations

import argparse
import base64
import binascii
import hashlib
import json
import os
import re
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path, PurePosixPath
from typing import Any, Iterable, Mapping, NoReturn, Sequence


PIN_FORMAT = "loa-aleph-release-pin/v1"
RELEASE_FORMAT = "aleph-loa-release/v1"
BUNDLE_LOCK_FORMAT = "aleph-bundle-lock/v1"
PROVENANCE_FORMAT = "aleph-source-provenance/v1"
INSTALL_LOCK_FORMAT = "aleph-loa-install-lock/v1"
INSTALL_MAP_FORMAT = "aleph-loa-installation-map/v1"
SEAL_FORMAT = "loa-aleph-candidate-seal/v1"
DIGEST_ALGORITHM = "sha256-path-file-digest-v1"
UPSTREAM_REPOSITORY = "0xHoneyJar/loa-aleph"
BUNDLE_ID = "aleph-for-loa"
CORE_ID = "aleph-core"
ADAPTER_ID = "loa"
BUNDLE_PREFIX = f"{BUNDLE_ID}/"
ASSEMBLY_TOOL_PATH = "scripts/assemble-bundles.ts"
INSTALLER_PATH = "runtime-js/adapters/loa/src/installer.js"
INSTALL_MAP_PATH = "adapters/loa/installation.map.json"
ADAPTER_MANIFEST_PATH = "adapters/loa/adapter.manifest.json"
RUNTIME_ROOT = ".claude/aleph/runtime/bundle"
INSTALL_RECORD = ".claude/aleph/install.lock.json"
PIN_PATH = ".loa-aleph.lock.json"
FORBIDDEN_CANDIDATE_PATHS = frozenset({
    ".claude/settings.json",
    ".claude/checksums.json",
})
EXPECTED_EXPOSURES = (
    {
        "id": "command",
        "source": "adapters/loa/command/loa-aleph.md",
        "destination": ".claude/commands/loa-aleph.md",
    },
    {
        "id": "skill",
        "source": "adapters/loa/skill/loa-aleph/SKILL.md",
        "destination": ".claude/skills/loa-aleph/SKILL.md",
    },
    {
        "id": "launcher",
        "source": "runtime-js/adapters/loa/src/launcher.js",
        "destination": ".claude/aleph/bin/loa-aleph.mjs",
    },
)

SHA256_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
COMMIT_RE = re.compile(r"^(?:[0-9a-f]{40}|[0-9a-f]{64})$")
VERSION_RE = re.compile(r"^[0-9A-Za-z][0-9A-Za-z.-]*$")
REPOSITORY_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
COMMAND_EXPOSURE_RE = re.compile(r"^\.claude/commands/loa-aleph(?:[.-][^/]*)?\.md$")

MAX_RELEASE_ASSET_BYTES = 64 * 1024 * 1024
MAX_TAR_BYTES = 64 * 1024 * 1024
MAX_ENTRY_BYTES = 16 * 1024 * 1024
MAX_FILE_COUNT = 4096
MAX_JSON_BYTES = 4 * 1024 * 1024
TAR_BLOCK = 512


class VerificationError(Exception):
    """A fail-closed verification error suitable for CLI reporting."""


def fail(message: str) -> NoReturn:
    raise VerificationError(message)


def _utf8_key(value: str) -> bytes:
    try:
        return value.encode("utf-8")
    except UnicodeEncodeError as error:
        fail(f"string contains an unpaired Unicode surrogate: {error}")


def _sorted_strings(values: Iterable[str]) -> list[str]:
    return sorted(values, key=_utf8_key)


def _exact_keys(value: Any, keys: Sequence[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != set(keys):
        fail(f"{label} keys are malformed")
    return value


def _string(value: Any, label: str) -> str:
    if not isinstance(value, str):
        fail(f"{label} must be a string")
    return value


def _digest(value: Any, label: str) -> str:
    text = _string(value, label)
    if not SHA256_RE.fullmatch(text):
        fail(f"{label} must be sha256:<64 lowercase hex>")
    return text


def _commit(value: Any, label: str) -> str:
    text = _string(value, label)
    if not COMMIT_RE.fullmatch(text) or set(text) == {"0"}:
        fail(f"{label} must be a full nonzero Git object ID")
    return text


def _valid_relative_path(value: Any, label: str) -> str:
    path = _string(value, label)
    if (not path or path.startswith("/") or "\\" in path or "\x00" in path
            or path == "." or "//" in path):
        fail(f"{label} is not a normalized repository path")
    parts = path.split("/")
    if any(part in ("", ".", "..") or part.lower() == ".git" for part in parts):
        fail(f"{label} is not a normalized repository path")
    if str(PurePosixPath(path)) != path:
        fail(f"{label} is not a normalized repository path")
    return path


def _sha256_bytes(data: bytes) -> str:
    return f"sha256:{hashlib.sha256(data).hexdigest()}"


def _digest_entries(entries: Iterable[Mapping[str, str]]) -> str:
    records: list[tuple[str, str]] = []
    for item in entries:
        path = _valid_relative_path(item.get("path"), "digest entry path")
        digest = _digest(item.get("digest"), f"digest for {path}")
        records.append((path, digest.removeprefix("sha256:")))
    records.sort(key=lambda item: _utf8_key(item[0]))
    raw = b"".join(
        path.encode("utf-8") + b"\0" + bare.encode("ascii") + b"\n"
        for path, bare in records
    )
    return _sha256_bytes(raw)


def _json_string(value: str) -> str:
    result = ['"']
    index = 0
    while index < len(value):
        code = ord(value[index])
        if code == 0x22:
            result.append('\\"')
        elif code == 0x5C:
            result.append("\\\\")
        elif code == 0x08:
            result.append("\\b")
        elif code == 0x09:
            result.append("\\t")
        elif code == 0x0A:
            result.append("\\n")
        elif code == 0x0C:
            result.append("\\f")
        elif code == 0x0D:
            result.append("\\r")
        elif code <= 0x1F:
            result.append(f"\\u{code:04x}")
        elif 0xD800 <= code <= 0xDFFF:
            fail("canonical JSON forbids unpaired Unicode surrogates")
        else:
            result.append(value[index])
        index += 1
    result.append('"')
    return "".join(result)


def _canonical_json(value: Any) -> str:
    if value is None:
        return "null"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, str):
        return _json_string(value)
    if isinstance(value, (int, float)):
        fail("canonical JSON forbids numbers")
    if isinstance(value, list):
        return "[" + ",".join(_canonical_json(item) for item in value) + "]"
    if isinstance(value, dict):
        if not all(isinstance(key, str) for key in value):
            fail("canonical JSON object keys must be strings")
        keys = sorted(value, key=_utf8_key)
        return "{" + ",".join(
            f"{_json_string(key)}:{_canonical_json(value[key])}" for key in keys
        ) + "}"
    fail(f"canonical JSON cannot serialize {type(value).__name__}")


def _canonical_json_bytes(value: Any) -> bytes:
    return (_canonical_json(value) + "\n").encode("utf-8")


def _reject_number(value: str) -> NoReturn:
    fail(f"JSON numbers are forbidden: {value}")


def _pairs_no_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            fail(f"JSON contains duplicate key: {key}")
        result[key] = value
    return result


def _parse_json(raw: bytes, label: str, *, canonical: bool) -> Any:
    if len(raw) > MAX_JSON_BYTES:
        fail(f"{label} exceeds the JSON size limit")
    try:
        text = raw.decode("utf-8", errors="strict")
    except UnicodeDecodeError as error:
        fail(f"{label} is not UTF-8: {error}")
    try:
        value = json.loads(
            text,
            object_pairs_hook=_pairs_no_duplicates,
            parse_int=_reject_number,
            parse_float=_reject_number,
            parse_constant=_reject_number,
        )
    except VerificationError:
        raise
    except (json.JSONDecodeError, UnicodeError) as error:
        fail(f"{label} is invalid JSON: {error}")
    if canonical and raw != _canonical_json_bytes(value):
        fail(f"{label} is not canonical JSON plus one LF")
    return value


def _absolute(path: os.PathLike[str] | str) -> Path:
    return Path(os.path.abspath(os.fspath(path)))


def _regular_bytes(path: Path, label: str, maximum: int) -> bytes:
    try:
        info = path.lstat()
    except FileNotFoundError:
        fail(f"{label} is missing")
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        fail(f"{label} is not a regular non-symlink file")
    if info.st_size > maximum:
        fail(f"{label} exceeds the size limit")
    flags = os.O_RDONLY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        fail(f"cannot safely open {label}: {error}")
    try:
        opened = os.fstat(descriptor)
        if not stat.S_ISREG(opened.st_mode) or (opened.st_dev, opened.st_ino) != (
                info.st_dev, info.st_ino):
            fail(f"{label} changed while being opened")
        chunks: list[bytes] = []
        total = 0
        while True:
            chunk = os.read(descriptor, min(1024 * 1024, maximum + 1 - total))
            if not chunk:
                break
            chunks.append(chunk)
            total += len(chunk)
            if total > maximum:
                fail(f"{label} exceeds the size limit")
        return b"".join(chunks)
    finally:
        os.close(descriptor)


def _directory(path: Path, label: str) -> None:
    try:
        mode = path.lstat().st_mode
    except FileNotFoundError:
        fail(f"{label} is missing")
    if stat.S_ISLNK(mode) or not stat.S_ISDIR(mode):
        fail(f"{label} is not a non-symlink directory")


def _join(root: Path, relative: str) -> Path:
    safe = _valid_relative_path(relative, "path")
    target = root.joinpath(*safe.split("/"))
    if os.path.commonpath((str(root), str(target))) != str(root):
        fail(f"path escapes root: {relative}")
    return target


def _inventory_tree(root: Path, *, label: str) -> tuple[list[str], list[str]]:
    _directory(root, label)
    files: list[str] = []
    directories: list[str] = []

    def visit(directory: Path, prefix: str) -> None:
        try:
            entries = sorted(os.scandir(directory), key=lambda item: _utf8_key(item.name))
        except OSError as error:
            fail(f"cannot inventory {label}: {error}")
        for entry in entries:
            relative = f"{prefix}/{entry.name}" if prefix else entry.name
            _valid_relative_path(relative, f"{label} entry")
            try:
                info = entry.stat(follow_symlinks=False)
            except OSError as error:
                fail(f"cannot inspect {label} entry {relative}: {error}")
            if stat.S_ISLNK(info.st_mode):
                fail(f"{label} contains a symlink: {relative}")
            if stat.S_ISDIR(info.st_mode):
                directories.append(relative)
                if len(directories) > MAX_FILE_COUNT:
                    fail(f"{label} exceeds the directory-count limit")
                visit(Path(entry.path), relative)
            elif stat.S_ISREG(info.st_mode):
                files.append(relative)
                if len(files) > MAX_FILE_COUNT:
                    fail(f"{label} exceeds the file-count limit")
            else:
                fail(f"{label} contains a non-regular entry: {relative}")

    visit(root, "")
    return _sorted_strings(files), _sorted_strings(directories)


def _inventory(root: Path, *, label: str) -> list[str]:
    return _inventory_tree(root, label=label)[0]


def _parent_directories(paths: Iterable[str]) -> list[str]:
    directories: set[str] = set()
    for path in paths:
        parts = _valid_relative_path(path, "inventory path").split("/")[:-1]
        for length in range(1, len(parts) + 1):
            directories.add("/".join(parts[:length]))
    return _sorted_strings(directories)


def _tar_octal(value: int, length: int) -> bytes:
    if value < 0:
        fail("negative tar integer")
    digits = format(value, "o")
    if len(digits) > length - 1:
        fail("tar integer exceeds field width")
    return (digits.rjust(length - 1, "0") + "\0").encode("ascii")


def _split_tar_path(path: str) -> tuple[str, str]:
    encoded = _utf8_key(path)
    if len(encoded) <= 100:
        return path, ""
    slash_indexes = [index for index, character in enumerate(path) if character == "/"]
    for index in reversed(slash_indexes):
        prefix, name = path[:index], path[index + 1:]
        if len(_utf8_key(prefix)) <= 155 and len(_utf8_key(name)) <= 100:
            return name, prefix
    fail(f"tar path exceeds ustar limits: {path}")


def _tar_header(path: str, size: int) -> bytes:
    name, prefix = _split_tar_path(path)
    header = bytearray(TAR_BLOCK)

    def field(offset: int, length: int, value: bytes) -> None:
        if len(value) > length:
            fail(f"tar field is too long for {path}")
        header[offset:offset + len(value)] = value

    field(0, 100, _utf8_key(name))
    field(100, 8, _tar_octal(0o644, 8))
    field(108, 8, _tar_octal(0, 8))
    field(116, 8, _tar_octal(0, 8))
    field(124, 12, _tar_octal(size, 12))
    field(136, 12, _tar_octal(0, 12))
    header[148:156] = b" " * 8
    header[156] = ord("0")
    field(257, 6, b"ustar\0")
    field(263, 2, b"00")
    field(329, 8, _tar_octal(0, 8))
    field(337, 8, _tar_octal(0, 8))
    field(345, 155, _utf8_key(prefix))
    checksum = sum(header)
    header[148:156] = f"{checksum:06o}\0 ".encode("ascii")
    return bytes(header)


def _tar_text(field: bytes, label: str) -> str:
    zero = field.find(b"\0")
    data = field if zero < 0 else field[:zero]
    if zero >= 0 and any(field[zero + 1:]):
        fail(f"{label} has nonzero bytes after NUL")
    try:
        return data.decode("utf-8", errors="strict")
    except UnicodeDecodeError as error:
        fail(f"{label} is not UTF-8: {error}")


def _tar_size(field: bytes, label: str) -> int:
    if len(field) != 12 or field[-1:] != b"\0" or not re.fullmatch(rb"[0-7]{11}\0", field):
        fail(f"{label} is not canonical octal")
    return int(field[:-1], 8)


def _encode_tar(entries: Sequence[tuple[str, bytes]]) -> bytes:
    chunks: list[bytes] = []
    for path, data in entries:
        chunks.extend((_tar_header(path, len(data)), data))
        padding = (-len(data)) % TAR_BLOCK
        if padding:
            chunks.append(b"\0" * padding)
    chunks.append(b"\0" * TAR_BLOCK * 2)
    return b"".join(chunks)


def _parse_tar(raw: bytes) -> list[tuple[str, bytes]]:
    if not raw or len(raw) > MAX_TAR_BYTES or len(raw) % TAR_BLOCK:
        fail("tar size is empty, oversized, or not block-aligned")
    entries: list[tuple[str, bytes]] = []
    seen: set[str] = set()
    offset = 0
    while True:
        if offset + TAR_BLOCK * 2 > len(raw):
            fail("tar is missing its two zero terminator blocks")
        if raw[offset:offset + TAR_BLOCK] == b"\0" * TAR_BLOCK:
            if raw[offset:] != b"\0" * TAR_BLOCK * 2:
                fail("tar must end with exactly two zero blocks and no trailing bytes")
            break
        if len(entries) >= MAX_FILE_COUNT:
            fail("tar exceeds the file-count limit")
        header = raw[offset:offset + TAR_BLOCK]
        offset += TAR_BLOCK
        name = _tar_text(header[0:100], "tar name")
        prefix = _tar_text(header[345:500], "tar prefix")
        path = f"{prefix}/{name}" if prefix else name
        path = _valid_relative_path(path, "tar path")
        if not path.startswith(BUNDLE_PREFIX) or path == BUNDLE_PREFIX.rstrip("/"):
            fail(f"tar path is outside {BUNDLE_ID}: {path}")
        if path in seen:
            fail(f"tar contains duplicate path: {path}")
        if entries and _utf8_key(entries[-1][0]) >= _utf8_key(path):
            fail("tar entries are not strictly ordered by UTF-8 path bytes")
        seen.add(path)
        size = _tar_size(header[124:136], f"tar size for {path}")
        if size > MAX_ENTRY_BYTES:
            fail(f"tar entry exceeds the per-file limit: {path}")
        if header != _tar_header(path, size):
            fail(f"tar header is not normalized canonical ustar: {path}")
        if offset + size > len(raw):
            fail(f"tar entry is truncated: {path}")
        data = raw[offset:offset + size]
        padded = (size + TAR_BLOCK - 1) // TAR_BLOCK * TAR_BLOCK
        if any(raw[offset + size:offset + padded]):
            fail(f"tar entry padding is not zeroed: {path}")
        offset += padded
        entries.append((path, data))
    if not entries:
        fail("tar inventory is empty")
    if _encode_tar(entries) != raw:
        fail("tar bytes are not the canonical normalized ustar encoding")
    return entries


def _encode_gzip(raw: bytes) -> bytes:
    header = b"\x1f\x8b\x08\x00\x00\x00\x00\x00\x00\xff"
    chunks: list[bytes] = []
    if not raw:
        chunks.append(b"\x01\x00\x00\xff\xff")
    for offset in range(0, len(raw), 0xFFFF):
        block = raw[offset:offset + 0xFFFF]
        final = offset + len(block) == len(raw)
        chunks.append(bytes((1 if final else 0,)))
        chunks.append(struct.pack("<HH", len(block), (~len(block)) & 0xFFFF))
        chunks.append(block)
    trailer = struct.pack("<II", zlib.crc32(raw) & 0xFFFFFFFF, len(raw) & 0xFFFFFFFF)
    return header + b"".join(chunks) + trailer


def _parse_gzip(raw: bytes) -> bytes:
    if len(raw) > MAX_RELEASE_ASSET_BYTES or len(raw) < 23:
        fail("release archive gzip is empty, oversized, or truncated")
    expected_header = b"\x1f\x8b\x08\x00\x00\x00\x00\x00\x00\xff"
    if raw[:10] != expected_header:
        fail("release archive gzip header is not normalized")
    trailer_offset = len(raw) - 8
    offset = 10
    chunks: list[bytes] = []
    total = 0
    final_seen = False
    while offset < trailer_offset:
        if final_seen or offset + 5 > trailer_offset:
            fail("release archive has malformed stored DEFLATE blocks")
        control = raw[offset]
        offset += 1
        if control not in (0, 1):
            fail("release archive does not use byte-aligned stored DEFLATE blocks")
        length, complement = struct.unpack_from("<HH", raw, offset)
        offset += 4
        if complement != ((~length) & 0xFFFF):
            fail("release archive stored-block length complement mismatch")
        if control == 0 and length != 0xFFFF:
            fail("release archive has a noncanonical short non-final block")
        if offset + length > trailer_offset:
            fail("release archive stored block is truncated")
        chunks.append(raw[offset:offset + length])
        offset += length
        total += length
        if total > MAX_TAR_BYTES:
            fail("release archive expands beyond the tar size limit")
        final_seen = control == 1
    if not final_seen or offset != trailer_offset:
        fail("release archive has no exact final stored DEFLATE block")
    expanded = b"".join(chunks)
    crc, size = struct.unpack_from("<II", raw, trailer_offset)
    if crc != (zlib.crc32(expanded) & 0xFFFFFFFF) or size != (len(expanded) & 0xFFFFFFFF):
        fail("release archive gzip trailer mismatch")
    if _encode_gzip(expanded) != raw:
        fail("release archive does not use canonical stored-block gzip encoding")
    return expanded


def _validate_manifest_projection(value: Any, lock: dict[str, Any]) -> None:
    projection = _exact_keys(value, (
        "manifest_format", "core", "manual_execution_binding", "files",
        "checker_paths", "reference_documents", "bundle_targets",
    ), "source manifest projection")
    if projection["manifest_format"] != "aleph-core-manifest/v1":
        fail("source manifest projection format is invalid")
    core = _exact_keys(projection["core"], (
        "id", "version", "adapter_protocol_version", "run_format_version",
        "digest_algorithm",
    ), "source manifest core")
    if core != {
        "id": lock["core"]["id"],
        "version": lock["core"]["version"],
        "adapter_protocol_version": lock["adapter_protocol_version"],
        "run_format_version": lock["run_format_version"],
        "digest_algorithm": DIGEST_ALGORITHM,
    }:
        fail("source manifest Core identity disagrees with the bundle lock")
    files = _exact_keys(projection["files"], (
        "core", "adapter", "packaging", "repository_administration",
    ), "source manifest files")
    adapters = _exact_keys(files["adapter"], (ADAPTER_ID,), "source manifest adapters")
    core_paths = files["core"]
    adapter_paths = adapters[ADAPTER_ID]
    checker_paths = projection["checker_paths"]
    for values, label in (
        (core_paths, "source manifest Core paths"),
        (adapter_paths, "source manifest adapter paths"),
        (checker_paths, "source manifest checker paths"),
        (projection["reference_documents"], "source manifest references"),
    ):
        if not isinstance(values, list) or not all(isinstance(item, str) for item in values):
            fail(f"{label} must be a string array")
        for item in values:
            _valid_relative_path(item, label)
        if values != _sorted_strings(set(values)):
            fail(f"{label} must be unique and UTF-8 sorted")
    locked_core = [item["path"] for item in lock["files"] if item["classification"] == "core"]
    locked_adapter = [item["path"] for item in lock["files"] if item["classification"] == "adapter"]
    if core_paths != locked_core or adapter_paths != locked_adapter:
        fail("source manifest inventories disagree with locked classifications")
    if any(path not in set(core_paths) for path in checker_paths):
        fail("source manifest checker inventory is not a Core subset")
    if files["packaging"] != ["core.manifest.json"] or files["repository_administration"] != []:
        fail("source manifest packaging or repository-administration projection is invalid")
    targets = projection["bundle_targets"]
    expected_target = {
        "id": BUNDLE_ID,
        "version": lock["bundle"]["version"],
        "adapter_id": ADAPTER_ID,
    }
    if targets != [expected_target]:
        fail("source manifest target disagrees with the selected bundle")


def _validate_provenance(value: Any) -> dict[str, Any]:
    provenance = _exact_keys(value, ("format", "vcs", "digest"), "provenance")
    if provenance["format"] != PROVENANCE_FORMAT:
        fail("provenance format is invalid")
    vcs = _exact_keys(provenance["vcs"], (
        "kind", "object_format", "commit", "commit_object", "commit_tree",
        "resolved", "mutable_ref", "worktree_state",
    ), "provenance vcs")
    if vcs["kind"] != "git-dependency-closure-snapshot":
        fail("provenance kind is invalid")
    object_format = vcs["object_format"]
    if object_format not in ("sha1", "sha256"):
        fail("provenance Git object format is invalid")
    commit = _commit(vcs["commit"], "provenance commit")
    tree = _commit(vcs["commit_tree"], "provenance tree")
    expected_length = 40 if object_format == "sha1" else 64
    if len(commit) != expected_length or len(tree) != expected_length:
        fail("provenance object IDs disagree with the Git object format")
    encoded = _string(vcs["commit_object"], "provenance commit object")
    try:
        commit_bytes = base64.b64decode(encoded, validate=True)
    except (binascii.Error, ValueError) as error:
        fail(f"provenance commit object is not canonical base64: {error}")
    if base64.b64encode(commit_bytes).decode("ascii") != encoded:
        fail("provenance commit object is not canonical base64")
    object_id = hashlib.new(object_format, b"commit " + str(len(commit_bytes)).encode("ascii")
                            + b"\0" + commit_bytes).hexdigest()
    if object_id != commit:
        fail("provenance commit object does not hash to the recorded commit")
    first_line = commit_bytes.split(b"\n", 1)[0]
    if first_line != f"tree {tree}".encode("ascii"):
        fail("provenance commit object tree disagrees with the recorded tree")
    if vcs["resolved"] is not True or vcs["mutable_ref"] is not None:
        fail("provenance must be resolved and contain no mutable ref")
    if vcs["worktree_state"] != "clean":
        fail("release provenance must record a clean worktree")
    if _digest(provenance["digest"], "provenance digest") != _sha256_bytes(
            _canonical_json_bytes(vcs)):
        fail("provenance digest mismatch")
    return provenance


def _validate_installation_map(raw: bytes) -> dict[str, Any]:
    value = _parse_json(raw, "installation map", canonical=False)
    mapping = _exact_keys(value, ("format", "runtime_root", "record_path", "exposures"),
                          "installation map")
    if (mapping["format"] != INSTALL_MAP_FORMAT or mapping["runtime_root"] != RUNTIME_ROOT
            or mapping["record_path"] != INSTALL_RECORD
            or mapping["exposures"] != list(EXPECTED_EXPOSURES)):
        fail("installation map identity or exposures disagree with the Loa host layout")
    return mapping


def _validate_adapter_manifest(raw: bytes, lock: dict[str, Any]) -> None:
    manifest = _parse_json(raw, "adapter manifest", canonical=False)
    if not isinstance(manifest, dict):
        fail("adapter manifest must be an object")
    adapter = manifest.get("adapter")
    if not isinstance(adapter, dict) or any(adapter.get(key) != expected for key, expected in {
        "id": ADAPTER_ID,
        "version": lock["adapter"]["version"],
        "lifecycle": lock["adapter"]["lifecycle"],
        "protocol_version": lock["adapter_protocol_version"],
        "run_format_version": lock["run_format_version"],
    }.items()):
        fail("adapter manifest identity disagrees with the bundle lock")
    evidence = manifest.get("evidence")
    if not isinstance(evidence, dict) or evidence.get("validation") != [] or evidence.get("sanction") != []:
        fail("Loa ingestion requires empty adapter validation and sanction evidence")
    if not isinstance(evidence.get("implementation"), list) or not evidence["implementation"]:
        fail("implemented Loa adapter omits implementation evidence")
    if not isinstance(manifest.get("full_mode"), dict) or manifest["full_mode"].get("claimed") is not True:
        fail("Loa adapter does not structurally claim full mode")


def _validate_bundle(files: Mapping[str, bytes]) -> dict[str, Any]:
    if "bundle.lock.json" not in files:
        fail("bundle.lock.json is missing")
    lock_raw = files["bundle.lock.json"]
    lock = _exact_keys(_parse_json(lock_raw, "bundle.lock.json", canonical=True), (
        "lock_format", "digest_algorithm", "lock_digest", "bundle", "core", "adapter",
        "checker_digest", "adapter_protocol_version", "run_format_version", "source",
        "provenance", "files",
    ), "bundle lock")
    if lock["lock_format"] != BUNDLE_LOCK_FORMAT or lock["digest_algorithm"] != DIGEST_ALGORITHM:
        fail("bundle lock format or digest algorithm is invalid")
    bundle = _exact_keys(lock["bundle"], ("id", "version", "payload_digest", "digest"),
                         "bundle identity")
    core = _exact_keys(lock["core"], ("id", "version", "tree_digest"), "Core identity")
    adapter = _exact_keys(lock["adapter"], ("id", "version", "lifecycle", "tree_digest"),
                          "adapter identity")
    if bundle["id"] != BUNDLE_ID or core["id"] != CORE_ID or adapter["id"] != ADAPTER_ID:
        fail("bundle, Core, or adapter identity is invalid")
    if not VERSION_RE.fullmatch(_string(bundle["version"], "bundle version")):
        fail("bundle version is unsafe")
    if core["version"] != bundle["version"] or adapter["version"] != bundle["version"]:
        fail("bundle, Core, and adapter versions disagree")
    if adapter["lifecycle"] != "implemented":
        fail("Loa release ingestion requires adapter lifecycle implemented")
    for value, label in (
        (lock["lock_digest"], "lock digest"),
        (bundle["payload_digest"], "payload digest"),
        (bundle["digest"], "bundle digest"),
        (core["tree_digest"], "Core digest"),
        (adapter["tree_digest"], "adapter digest"),
        (lock["checker_digest"], "checker digest"),
    ):
        _digest(value, label)
    if not isinstance(lock["adapter_protocol_version"], str) or not isinstance(
            lock["run_format_version"], str):
        fail("bundle protocol or run-format version is malformed")
    records = lock["files"]
    if not isinstance(records, list) or not records or len(records) > MAX_FILE_COUNT:
        fail("bundle file inventory is empty or oversized")
    paths: list[str] = []
    for index, item in enumerate(records):
        record = _exact_keys(item, ("path", "classification", "digest"),
                             f"bundle files[{index}]")
        path = _valid_relative_path(record["path"], f"bundle files[{index}].path")
        if path == "bundle.lock.json":
            fail("bundle payload inventory must not include bundle.lock.json")
        if record["classification"] not in ("core", "adapter"):
            fail(f"bundle files[{index}] classification is invalid")
        _digest(record["digest"], f"bundle files[{index}] digest")
        paths.append(path)
    if paths != _sorted_strings(set(paths)):
        fail("bundle file inventory must be unique and UTF-8 sorted")
    if _sorted_strings(files) != _sorted_strings(["bundle.lock.json", *paths]):
        fail("bundle on-disk inventory disagrees with bundle.lock.json")
    actual_records: list[dict[str, str]] = []
    for record in records:
        actual = _sha256_bytes(files[record["path"]])
        if actual != record["digest"]:
            fail(f"bundle file digest mismatch: {record['path']}")
        actual_records.append({
            "path": record["path"],
            "classification": record["classification"],
            "digest": actual,
        })
    source = _exact_keys(lock["source"], (
        "manifest_projection", "manifest_projection_digest", "assembly_tool",
    ), "bundle source")
    _validate_manifest_projection(source["manifest_projection"], lock)
    if _digest(source["manifest_projection_digest"], "manifest projection digest") != _sha256_bytes(
            _canonical_json_bytes(source["manifest_projection"])):
        fail("source manifest projection digest mismatch")
    tool = _exact_keys(source["assembly_tool"], ("path", "digest"), "assembly tool identity")
    if tool["path"] != ASSEMBLY_TOOL_PATH:
        fail("assembly tool path is invalid")
    tool_record = next((item for item in records if item["path"] == ASSEMBLY_TOOL_PATH), None)
    if not tool_record or tool_record["classification"] != "core" or tool_record["digest"] != tool["digest"]:
        fail("assembly tool identity does not resolve to locked Core bytes")
    provenance = _validate_provenance(lock["provenance"])
    core_digest = _digest_entries(item for item in actual_records if item["classification"] == "core")
    adapter_digest = _digest_entries(item for item in actual_records if item["classification"] == "adapter")
    payload_digest = _digest_entries(actual_records)
    checker_paths = set(source["manifest_projection"]["checker_paths"])
    checker_digest = _digest_entries(item for item in actual_records if item["path"] in checker_paths)
    if core_digest != core["tree_digest"]:
        fail("Core tree digest mismatch")
    if adapter_digest != adapter["tree_digest"]:
        fail("adapter tree digest mismatch")
    if payload_digest != bundle["payload_digest"]:
        fail("payload digest mismatch")
    if checker_digest != lock["checker_digest"]:
        fail("checker digest mismatch")
    identity = {
        "lock_format": lock["lock_format"],
        "digest_algorithm": lock["digest_algorithm"],
        "bundle": {
            "id": bundle["id"],
            "version": bundle["version"],
            "payload_digest": bundle["payload_digest"],
        },
        "core": core,
        "adapter": adapter,
        "checker_digest": lock["checker_digest"],
        "adapter_protocol_version": lock["adapter_protocol_version"],
        "run_format_version": lock["run_format_version"],
        "source": source,
        "provenance": provenance,
        "files": records,
    }
    if _sha256_bytes(_canonical_json_bytes(identity)) != lock["lock_digest"]:
        fail("bundle lock digest mismatch")
    bundle_digest = _digest_entries([
        *actual_records,
        {"path": "bundle.lock.json", "digest": lock["lock_digest"]},
    ])
    if bundle_digest != bundle["digest"]:
        fail("bundle aggregate digest mismatch")
    for required in (INSTALLER_PATH, INSTALL_MAP_PATH, ADAPTER_MANIFEST_PATH,
                     "runtime-js/adapters/loa/src/launcher.js"):
        record = next((item for item in records if item["path"] == required), None)
        if not record or record["classification"] != "adapter":
            fail(f"authenticated adapter inventory omits {required}")
    _validate_installation_map(files[INSTALL_MAP_PATH])
    _validate_adapter_manifest(files[ADAPTER_MANIFEST_PATH], lock)
    return lock


def _metadata(raw: bytes) -> dict[str, Any]:
    value = _exact_keys(_parse_json(raw, "release metadata", canonical=True),
                        ("format", "release", "source", "bundle", "asset"),
                        "release metadata")
    release = _exact_keys(value["release"], ("id", "version", "maturity"), "release identity")
    source = _exact_keys(value["source"], (
        "build_commit", "dependency_closure_commit", "provenance_digest",
    ), "release source")
    bundle = _exact_keys(value["bundle"], (
        "digest", "payload_digest", "lock_digest", "core_digest", "adapter_digest",
        "checker_digest", "adapter_lifecycle",
    ), "release bundle")
    asset = _exact_keys(value["asset"], ("filename", "digest", "checksum_filename"),
                        "release asset")
    if value["format"] != RELEASE_FORMAT or release["id"] != BUNDLE_ID:
        fail("release metadata format or id is invalid")
    if release["maturity"] != "structural-prerelease":
        fail("release metadata maturity is invalid")
    if not VERSION_RE.fullmatch(_string(release["version"], "release version")):
        fail("release version is unsafe")
    _commit(source["build_commit"], "release build commit")
    _commit(source["dependency_closure_commit"], "release dependency-closure commit")
    for key in ("provenance_digest",):
        _digest(source[key], f"release source {key}")
    for key in ("digest", "payload_digest", "lock_digest", "core_digest",
                "adapter_digest", "checker_digest"):
        _digest(bundle[key], f"release bundle {key}")
    if bundle["adapter_lifecycle"] != "implemented":
        fail("release metadata lifecycle must remain implemented")
    _string(asset["filename"], "archive filename")
    _string(asset["checksum_filename"], "checksum filename")
    _digest(asset["digest"], "archive digest")
    return value


def _pin(raw: bytes) -> dict[str, Any]:
    value = _exact_keys(_parse_json(raw, "Aleph release pin", canonical=True),
                        ("format", "repository", "release", "assets", "bundle", "source"),
                        "Aleph release pin")
    if value["format"] != PIN_FORMAT or value["repository"] != UPSTREAM_REPOSITORY:
        fail("Aleph release pin format or repository is invalid")
    release = _exact_keys(value["release"], ("tag", "commit", "version", "maturity"),
                          "pin release")
    bundle = _exact_keys(value["bundle"], (
        "id", "digest", "payload_digest", "lock_digest", "lock_file_digest",
        "core_digest", "adapter", "checker_digest",
    ), "pin bundle")
    adapter = _exact_keys(bundle["adapter"], ("id", "lifecycle", "digest"), "pin adapter")
    source = _exact_keys(value["source"], ("dependency_closure_commit", "provenance_digest"),
                         "pin source")
    if release["maturity"] != "structural-prerelease" or not VERSION_RE.fullmatch(
            _string(release["version"], "pin release version")):
        fail("pin release maturity or version is invalid")
    commit = _commit(release["commit"], "pin release commit")
    if _commit(source["dependency_closure_commit"], "pin dependency-closure commit") != commit:
        fail("pin release and dependency-closure commits disagree")
    if bundle["id"] != BUNDLE_ID or adapter["id"] != ADAPTER_ID or adapter["lifecycle"] != "implemented":
        fail("pin bundle or adapter identity is invalid")
    for key in ("digest", "payload_digest", "lock_digest", "lock_file_digest", "core_digest",
                "checker_digest"):
        _digest(bundle[key], f"pin bundle {key}")
    _digest(adapter["digest"], "pin adapter digest")
    _digest(source["provenance_digest"], "pin provenance digest")
    expected_tag = f"aleph-for-loa-sha256-{bundle['digest'].removeprefix('sha256:')}"
    if release["tag"] != expected_tag:
        fail("pin tag is not the full bundle-digest tag")
    assets = value["assets"]
    if not isinstance(assets, list) or len(assets) != 3:
        fail("pin must bind exactly three release assets")
    names: list[str] = []
    for index, item in enumerate(assets):
        record = _exact_keys(item, ("name", "digest"), f"pin assets[{index}]")
        name = _string(record["name"], f"pin assets[{index}].name")
        if "/" in name or "\\" in name or name in ("", ".", ".."):
            fail("pin asset name is unsafe")
        _digest(record["digest"], f"pin asset {name} digest")
        names.append(name)
    if names != _sorted_strings(set(names)):
        fail("pin assets must be unique and UTF-8 sorted")
    expected_base = (
        f"{BUNDLE_ID}-{release['version']}-sha256-"
        f"{bundle['digest'].removeprefix('sha256:')}"
    )
    expected_names = _sorted_strings((
        f"{expected_base}.tar.gz",
        f"{expected_base}.sha256",
        f"{expected_base}.release.json",
    ))
    if names != expected_names:
        fail("pin asset names disagree with pinned version and bundle digest")
    return value


def _release_directory(path: Path) -> tuple[list[str], dict[str, bytes]]:
    _directory(path, "release directory")
    names: list[str] = []
    try:
        entries = sorted(os.scandir(path), key=lambda item: _utf8_key(item.name))
    except OSError as error:
        fail(f"cannot inventory release directory: {error}")
    for entry in entries:
        info = entry.stat(follow_symlinks=False)
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
            fail(f"release contains a non-regular top-level entry: {entry.name}")
        names.append(entry.name)
    if len(names) != 3:
        fail("release must contain exactly three top-level regular files")
    archives = [name for name in names if name.endswith(".tar.gz")]
    checksums = [name for name in names if name.endswith(".sha256")]
    metadata = [name for name in names if name.endswith(".release.json")]
    if len(archives) != 1 or len(checksums) != 1 or len(metadata) != 1:
        fail("release must contain one archive, checksum, and metadata asset")
    blobs = {
        name: _regular_bytes(path / name, f"release asset {name}", MAX_RELEASE_ASSET_BYTES)
        for name in names
    }
    return names, blobs


def _verify_release(path: Path, pin_path: Path | None = None) -> dict[str, Any]:
    names, blobs = _release_directory(path)
    archive_name = next(name for name in names if name.endswith(".tar.gz"))
    checksum_name = next(name for name in names if name.endswith(".sha256"))
    metadata_name = next(name for name in names if name.endswith(".release.json"))
    metadata = _metadata(blobs[metadata_name])
    expected_base = f"{BUNDLE_ID}-{metadata['release']['version']}-sha256-" \
                    f"{metadata['bundle']['digest'].removeprefix('sha256:')}"
    if (archive_name != f"{expected_base}.tar.gz"
            or checksum_name != f"{expected_base}.sha256"
            or metadata_name != f"{expected_base}.release.json"):
        fail("release filenames disagree with version and bundle identity")
    if metadata["asset"] != {
        "filename": archive_name,
        "digest": _sha256_bytes(blobs[archive_name]),
        "checksum_filename": checksum_name,
    }:
        fail("release metadata asset identity mismatch")
    expected_checksum = (
        f"{_sha256_bytes(blobs[archive_name]).removeprefix('sha256:')}  {archive_name}\n"
    ).encode("ascii")
    if blobs[checksum_name] != expected_checksum:
        fail("release checksum sidecar is not exact canonical sha256sum syntax")
    tar_entries = _parse_tar(_parse_gzip(blobs[archive_name]))
    bundle_files = {path.removeprefix(BUNDLE_PREFIX): data for path, data in tar_entries}
    if len(bundle_files) != len(tar_entries):
        fail("release archive contains duplicate bundle-relative paths")
    lock = _validate_bundle(bundle_files)
    comparisons = (
        (metadata["bundle"]["digest"], lock["bundle"]["digest"], "bundle digest"),
        (metadata["bundle"]["payload_digest"], lock["bundle"]["payload_digest"], "payload digest"),
        (metadata["bundle"]["lock_digest"], lock["lock_digest"], "lock digest"),
        (metadata["bundle"]["core_digest"], lock["core"]["tree_digest"], "Core digest"),
        (metadata["bundle"]["adapter_digest"], lock["adapter"]["tree_digest"], "adapter digest"),
        (metadata["bundle"]["checker_digest"], lock["checker_digest"], "checker digest"),
        (metadata["bundle"]["adapter_lifecycle"], lock["adapter"]["lifecycle"], "adapter lifecycle"),
        (metadata["source"]["build_commit"], lock["provenance"]["vcs"]["commit"], "build commit"),
        (metadata["source"]["dependency_closure_commit"], lock["provenance"]["vcs"]["commit"],
         "dependency-closure commit"),
        (metadata["source"]["provenance_digest"], lock["provenance"]["digest"],
         "provenance digest"),
    )
    for actual, expected, label in comparisons:
        if actual != expected:
            fail(f"release metadata {label} mismatch")
    pin = None
    pin_raw = None
    if pin_path is not None:
        pin_raw = _regular_bytes(pin_path, "Aleph release pin", MAX_JSON_BYTES)
        pin = _pin(pin_raw)
        expected_assets = [
            {"name": name, "digest": _sha256_bytes(blobs[name])}
            for name in _sorted_strings(names)
        ]
        expected_pin = {
            "format": PIN_FORMAT,
            "repository": UPSTREAM_REPOSITORY,
            "release": {
                "tag": f"aleph-for-loa-sha256-{lock['bundle']['digest'].removeprefix('sha256:')}",
                "commit": lock["provenance"]["vcs"]["commit"],
                "version": lock["bundle"]["version"],
                "maturity": "structural-prerelease",
            },
            "assets": expected_assets,
            "bundle": {
                "id": BUNDLE_ID,
                "digest": lock["bundle"]["digest"],
                "payload_digest": lock["bundle"]["payload_digest"],
                "lock_digest": lock["lock_digest"],
                "lock_file_digest": _sha256_bytes(bundle_files["bundle.lock.json"]),
                "core_digest": lock["core"]["tree_digest"],
                "adapter": {
                    "id": ADAPTER_ID,
                    "lifecycle": lock["adapter"]["lifecycle"],
                    "digest": lock["adapter"]["tree_digest"],
                },
                "checker_digest": lock["checker_digest"],
            },
            "source": {
                "dependency_closure_commit": lock["provenance"]["vcs"]["commit"],
                "provenance_digest": lock["provenance"]["digest"],
            },
        }
        if pin != expected_pin:
            fail("Aleph release pin disagrees with the verified release identity")
    return {
        "names": names,
        "blobs": blobs,
        "metadata": metadata,
        "lock": lock,
        "bundle_files": bundle_files,
        "pin": pin,
        "pin_raw": pin_raw,
    }


def _pin_from_release(info: dict[str, Any], repository: str, tag: str, commit: str) -> dict[str, Any]:
    if repository != UPSTREAM_REPOSITORY or not REPOSITORY_RE.fullmatch(repository):
        fail(f"repository must be exactly {UPSTREAM_REPOSITORY}")
    lock = info["lock"]
    expected_commit = lock["provenance"]["vcs"]["commit"]
    if _commit(commit, "release tag commit") != expected_commit:
        fail("release tag commit disagrees with authenticated bundle provenance")
    expected_tag = f"aleph-for-loa-sha256-{lock['bundle']['digest'].removeprefix('sha256:')}"
    if tag != expected_tag:
        fail("release tag is not the full authenticated bundle-digest tag")
    return {
        "format": PIN_FORMAT,
        "repository": repository,
        "release": {
            "tag": tag,
            "commit": commit,
            "version": lock["bundle"]["version"],
            "maturity": "structural-prerelease",
        },
        "assets": [
            {"name": name, "digest": _sha256_bytes(info["blobs"][name])}
            for name in _sorted_strings(info["names"])
        ],
        "bundle": {
            "id": BUNDLE_ID,
            "digest": lock["bundle"]["digest"],
            "payload_digest": lock["bundle"]["payload_digest"],
            "lock_digest": lock["lock_digest"],
            "lock_file_digest": _sha256_bytes(info["bundle_files"]["bundle.lock.json"]),
            "core_digest": lock["core"]["tree_digest"],
            "adapter": {
                "id": ADAPTER_ID,
                "lifecycle": lock["adapter"]["lifecycle"],
                "digest": lock["adapter"]["tree_digest"],
            },
            "checker_digest": lock["checker_digest"],
        },
        "source": {
            "dependency_closure_commit": expected_commit,
            "provenance_digest": lock["provenance"]["digest"],
        },
    }


def _write_new(path: Path, raw: bytes, mode: int = 0o644) -> None:
    parent = path.parent
    _directory(parent, f"output parent {parent}")
    if path.exists() or path.is_symlink():
        fail(f"output already exists: {path}")
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(path, flags, mode)
    try:
        os.fchmod(descriptor, mode)
        view = memoryview(raw)
        while view:
            written = os.write(descriptor, view)
            view = view[written:]
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _materialize_bundle(files: Mapping[str, bytes], output: Path) -> None:
    if output.exists() or output.is_symlink():
        fail(f"bundle output already exists: {output}")
    parent = output.parent
    _directory(parent, "bundle output parent")
    stage = Path(tempfile.mkdtemp(prefix=".aleph-bundle-stage-", dir=parent))
    try:
        for relative in _sorted_strings(files):
            destination = _join(stage, relative)
            destination.parent.mkdir(parents=True, exist_ok=True, mode=0o755)
            _write_new(destination, files[relative], 0o644)
        for directory, subdirs, _ in os.walk(stage, topdown=False):
            os.chmod(directory, 0o755, follow_symlinks=False)
            for subdir in subdirs:
                os.chmod(Path(directory) / subdir, 0o755, follow_symlinks=False)
        os.rename(stage, output)
    finally:
        if stage.exists():
            shutil.rmtree(stage)


def _bundle_from_directory(root: Path) -> tuple[dict[str, Any], dict[str, bytes]]:
    paths = _inventory(root, label="installed Aleph bundle")
    files = {
        path: _regular_bytes(_join(root, path), f"installed bundle file {path}", MAX_ENTRY_BYTES)
        for path in paths
    }
    return _validate_bundle(files), files


def _install_identity(lock: dict[str, Any]) -> dict[str, Any]:
    return {key: lock[key] for key in (
        "format", "digest_algorithm", "bundle", "core", "adapter", "checker_digest",
        "adapter_protocol_version", "run_format_version", "layout", "managed_tree_digest", "files",
    )}


def _expected_install_files(bundle: dict[str, Any], bundle_files: Mapping[str, bytes]) -> list[dict[str, str]]:
    records = [
        {
            "kind": "runtime",
            "classification": item["classification"],
            "source_path": item["path"],
            "destination_path": f"{RUNTIME_ROOT}/{item['path']}",
            "digest": item["digest"],
        }
        for item in bundle["files"]
    ]
    records.append({
        "kind": "runtime",
        "classification": "lock",
        "source_path": "bundle.lock.json",
        "destination_path": f"{RUNTIME_ROOT}/bundle.lock.json",
        "digest": _sha256_bytes(bundle_files["bundle.lock.json"]),
    })
    by_path = {item["path"]: item for item in bundle["files"]}
    for exposure in EXPECTED_EXPOSURES:
        source = by_path.get(exposure["source"])
        if not source or source["classification"] != "adapter":
            fail(f"installation exposure is not authenticated adapter content: {exposure['source']}")
        records.append({
            "kind": "exposure",
            "classification": "adapter",
            "source_path": exposure["source"],
            "destination_path": exposure["destination"],
            "digest": source["digest"],
        })
    return sorted(records, key=lambda item: _utf8_key(item["destination_path"]))


def _validate_install_lock(raw: bytes, bundle: dict[str, Any], bundle_files: Mapping[str, bytes]) -> dict[str, Any]:
    lock = _exact_keys(_parse_json(raw, "Aleph installation record", canonical=True), (
        "format", "digest_algorithm", "install_digest", "bundle", "core", "adapter",
        "checker_digest", "adapter_protocol_version", "run_format_version", "layout",
        "managed_tree_digest", "files",
    ), "Aleph installation record")
    if lock["format"] != INSTALL_LOCK_FORMAT or lock["digest_algorithm"] != DIGEST_ALGORITHM:
        fail("installation record format or digest algorithm is invalid")
    expected_bundle = {
        "id": bundle["bundle"]["id"],
        "version": bundle["bundle"]["version"],
        "payload_digest": bundle["bundle"]["payload_digest"],
        "lock_digest": bundle["lock_digest"],
        "digest": bundle["bundle"]["digest"],
        "lock_file_digest": _sha256_bytes(bundle_files["bundle.lock.json"]),
    }
    _exact_keys(lock["bundle"], tuple(expected_bundle), "installation bundle identity")
    _exact_keys(lock["core"], ("id", "version", "tree_digest"), "installation Core identity")
    _exact_keys(lock["adapter"], ("id", "version", "lifecycle", "tree_digest"),
                "installation adapter identity")
    layout = _exact_keys(lock["layout"], (
        "map_format", "map_digest", "runtime_root", "record_path",
    ), "installation layout")
    map_record = next(item for item in bundle["files"] if item["path"] == INSTALL_MAP_PATH)
    expected_identity = {
        "bundle": expected_bundle,
        "core": bundle["core"],
        "adapter": bundle["adapter"],
        "checker_digest": bundle["checker_digest"],
        "adapter_protocol_version": bundle["adapter_protocol_version"],
        "run_format_version": bundle["run_format_version"],
    }
    actual_identity = {key: lock[key] for key in expected_identity}
    if actual_identity != expected_identity:
        fail("installation record identity disagrees with installed bundle")
    if layout != {
        "map_format": INSTALL_MAP_FORMAT,
        "map_digest": map_record["digest"],
        "runtime_root": RUNTIME_ROOT,
        "record_path": INSTALL_RECORD,
    }:
        fail("installation record layout disagrees with authenticated mapping")
    expected_files = _expected_install_files(bundle, bundle_files)
    if lock["files"] != expected_files:
        fail("installation record does not cover the exact runtime and exposures")
    managed_digest = _digest_entries(
        {"path": item["destination_path"], "digest": item["digest"]} for item in expected_files
    )
    if lock["managed_tree_digest"] != managed_digest:
        fail("installation managed-tree digest mismatch")
    for label in ("install_digest", "managed_tree_digest", "checker_digest"):
        _digest(lock[label], f"installation {label}")
    if lock["install_digest"] != _sha256_bytes(_canonical_json_bytes(_install_identity(lock))):
        fail("installation record digest mismatch")
    return lock


def _pin_matches_bundle(pin: dict[str, Any], pin_raw: bytes, bundle: dict[str, Any],
                        bundle_files: Mapping[str, bytes]) -> None:
    del pin_raw
    comparisons = (
        (pin["bundle"]["digest"], bundle["bundle"]["digest"], "bundle digest"),
        (pin["bundle"]["payload_digest"], bundle["bundle"]["payload_digest"], "payload digest"),
        (pin["bundle"]["lock_digest"], bundle["lock_digest"], "lock digest"),
        (pin["bundle"]["lock_file_digest"], _sha256_bytes(bundle_files["bundle.lock.json"]),
         "raw lock digest"),
        (pin["bundle"]["core_digest"], bundle["core"]["tree_digest"], "Core digest"),
        (pin["bundle"]["adapter"]["digest"], bundle["adapter"]["tree_digest"], "adapter digest"),
        (pin["bundle"]["adapter"]["lifecycle"], bundle["adapter"]["lifecycle"], "adapter lifecycle"),
        (pin["bundle"]["checker_digest"], bundle["checker_digest"], "checker digest"),
        (pin["release"]["commit"], bundle["provenance"]["vcs"]["commit"], "release commit"),
        (pin["source"]["dependency_closure_commit"], bundle["provenance"]["vcs"]["commit"],
         "dependency-closure commit"),
        (pin["source"]["provenance_digest"], bundle["provenance"]["digest"], "provenance digest"),
        (pin["release"]["version"], bundle["bundle"]["version"], "version"),
    )
    for actual, expected, label in comparisons:
        if actual != expected:
            fail(f"pin {label} disagrees with installed bundle")


def _managed_inventory(root: Path) -> list[str]:
    files: list[str] = []
    aleph_root = _join(root, ".claude/aleph")
    for path in _inventory(aleph_root, label="Loa-managed Aleph subtree"):
        files.append(f".claude/aleph/{path}")
    skill_path = ".claude/skills/loa-aleph"
    skill_files = set(_inventory(_join(root, skill_path), label="managed Aleph skill"))
    if skill_files != {"SKILL.md"}:
        fail("managed Aleph skill inventory mismatch")
    files.append(f"{skill_path}/SKILL.md")
    commands = _join(root, ".claude/commands")
    _directory(commands, "Loa commands directory")
    for entry in os.scandir(commands):
        relative = f".claude/commands/{entry.name}"
        if COMMAND_EXPOSURE_RE.fullmatch(relative):
            info = entry.stat(follow_symlinks=False)
            if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
                fail(f"managed command is not a regular file: {relative}")
            files.append(relative)
    return _sorted_strings(files)


def _verify_installed(root: Path, pin_path: Path, *, exact_candidate: bool) -> dict[str, Any]:
    _directory(root, "Loa root")
    pin_raw = _regular_bytes(pin_path, "Aleph release pin", MAX_JSON_BYTES)
    pin = _pin(pin_raw)
    installed_pin_path = _join(root, PIN_PATH)
    installed_pin_raw = _regular_bytes(installed_pin_path, "installed Aleph release pin", MAX_JSON_BYTES)
    if installed_pin_raw != pin_raw:
        fail("installed Aleph pin bytes disagree with the selected pin")
    if stat.S_IMODE(installed_pin_path.lstat().st_mode) != 0o644:
        fail("installed Aleph release pin mode must be 0644")
    runtime = _join(root, RUNTIME_ROOT)
    bundle, bundle_files = _bundle_from_directory(runtime)
    _pin_matches_bundle(pin, pin_raw, bundle, bundle_files)
    record_raw = _regular_bytes(_join(root, INSTALL_RECORD), "Aleph installation record", MAX_JSON_BYTES)
    install = _validate_install_lock(record_raw, bundle, bundle_files)
    expected_managed = _sorted_strings([
        *(item["destination_path"] for item in install["files"]),
        INSTALL_RECORD,
    ])
    actual_managed = _managed_inventory(root)
    if actual_managed != expected_managed:
        fail("managed installation inventory disagrees with installation record")
    expected_aleph_relative = [
        path.removeprefix(".claude/aleph/")
        for path in expected_managed
        if path.startswith(".claude/aleph/")
    ]
    _, actual_aleph_directories = _inventory_tree(
        _join(root, ".claude/aleph"), label="Loa-managed Aleph subtree",
    )
    expected_aleph_directories = _parent_directories(expected_aleph_relative)
    if actual_aleph_directories != expected_aleph_directories:
        fail("Loa-managed Aleph directory topology disagrees with installation record")
    _, actual_skill_directories = _inventory_tree(
        _join(root, ".claude/skills/loa-aleph"), label="managed Aleph skill",
    )
    if actual_skill_directories:
        fail("managed Aleph skill contains unauthorized directories")
    for item in install["files"]:
        path = item["destination_path"]
        raw = _regular_bytes(_join(root, path), f"managed installation file {path}", MAX_ENTRY_BYTES)
        if _sha256_bytes(raw) != item["digest"]:
            fail(f"managed installation file digest mismatch: {path}")
        mode = stat.S_IMODE(_join(root, path).lstat().st_mode)
        if mode != 0o644:
            fail(f"managed installation file mode must be 0644: {path}")
    record_mode = stat.S_IMODE(_join(root, INSTALL_RECORD).lstat().st_mode)
    if record_mode != 0o644:
        fail("Aleph installation record mode must be 0644")
    if exact_candidate:
        candidate_files, candidate_directories = _inventory_tree(root, label="sealed candidate")
        expected_candidate = _sorted_strings([PIN_PATH, *expected_managed])
        if candidate_files != expected_candidate:
            extras = _sorted_strings(set(candidate_files) - set(expected_candidate))
            forbidden = _sorted_strings(set(candidate_files) & FORBIDDEN_CANDIDATE_PATHS)
            if forbidden:
                fail(f"candidate contains explicitly forbidden paths: {','.join(forbidden)}")
            fail(f"candidate inventory exceeds exact allowlist: {','.join(extras)}")
        expected_directories = _parent_directories(expected_candidate)
        if candidate_directories != expected_directories:
            extras = _sorted_strings(set(candidate_directories) - set(expected_directories))
            missing = _sorted_strings(set(expected_directories) - set(candidate_directories))
            fail(
                "candidate directory topology exceeds exact allowlist; "
                f"extra={','.join(extras)}; missing={','.join(missing)}"
            )
    return {
        "pin": pin,
        "pin_raw": pin_raw,
        "bundle": bundle,
        "bundle_files": bundle_files,
        "install": install,
        "paths": _sorted_strings([PIN_PATH, *expected_managed]) if exact_candidate else expected_managed,
    }


def _seal_projection(pin_digest: str, files: list[dict[str, str]]) -> dict[str, Any]:
    return {"format": SEAL_FORMAT, "pin_digest": pin_digest, "files": files}


def _candidate_records(root: Path, paths: Sequence[str]) -> list[dict[str, str]]:
    records: list[dict[str, str]] = []
    for path in paths:
        absolute = _join(root, path)
        raw = _regular_bytes(absolute, f"candidate file {path}", MAX_ENTRY_BYTES)
        mode = stat.S_IMODE(absolute.lstat().st_mode)
        if mode != 0o644:
            fail(f"candidate file mode must be 0644: {path}")
        records.append({"path": path, "mode": "0644", "digest": _sha256_bytes(raw)})
    return sorted(records, key=lambda item: _utf8_key(item["path"]))


def _make_seal(candidate: Path, pin_path: Path) -> dict[str, Any]:
    verified = _verify_installed(candidate, pin_path, exact_candidate=True)
    records = _candidate_records(candidate, verified["paths"])
    projection = _seal_projection(_sha256_bytes(verified["pin_raw"]), records)
    return {**projection, "digest": _sha256_bytes(_canonical_json_bytes(projection))}


def _verify_seal(candidate: Path, pin_path: Path, seal_path: Path) -> dict[str, Any]:
    expected = _make_seal(candidate, pin_path)
    raw = _regular_bytes(seal_path, "candidate seal", MAX_JSON_BYTES)
    actual = _exact_keys(_parse_json(raw, "candidate seal", canonical=True),
                         ("format", "pin_digest", "files", "digest"), "candidate seal")
    if actual != expected:
        fail("candidate seal disagrees with exact candidate bytes or modes")
    return expected


def _safe_parent(root: Path, relative: str) -> Path:
    destination = _join(root, relative)
    current = root
    for part in relative.split("/")[:-1]:
        current = current / part
        if current.exists() or current.is_symlink():
            info = current.lstat()
            if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
                fail(f"destination parent is unsafe: {current}")
        else:
            current.mkdir(mode=0o755)
    if destination.is_symlink():
        fail(f"destination is a symlink: {relative}")
    return destination


def _atomic_replace(root: Path, relative: str, raw: bytes, mode: int) -> None:
    destination = _safe_parent(root, relative)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{destination.name}.aleph-", dir=destination.parent)
    temporary_path = Path(temporary)
    try:
        os.fchmod(descriptor, mode)
        view = memoryview(raw)
        while view:
            written = os.write(descriptor, view)
            view = view[written:]
        os.fsync(descriptor)
        os.close(descriptor)
        descriptor = -1
        os.replace(temporary_path, destination)
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        if temporary_path.exists():
            temporary_path.unlink()


def _replace_runtime_tree(candidate: Path, root: Path) -> None:
    source = _join(candidate, RUNTIME_ROOT)
    parent = _safe_parent(root, RUNTIME_ROOT).parent
    destination = parent / "bundle"
    stage = Path(tempfile.mkdtemp(prefix=".bundle.aleph-stage-", dir=parent))
    backup = parent / (".bundle.aleph-backup-" + next(tempfile._get_candidate_names()))
    try:
        for relative in _inventory(source, label="candidate runtime bundle"):
            target = _join(stage, relative)
            target.parent.mkdir(parents=True, exist_ok=True, mode=0o755)
            _write_new(target, _regular_bytes(_join(source, relative),
                                              f"candidate runtime {relative}", MAX_ENTRY_BYTES), 0o644)
        for directory, subdirs, _ in os.walk(stage, topdown=False):
            os.chmod(directory, 0o755, follow_symlinks=False)
            for subdir in subdirs:
                os.chmod(Path(directory) / subdir, 0o755, follow_symlinks=False)
        had_prior = destination.exists()
        if destination.is_symlink():
            fail("installed runtime destination is a symlink")
        if had_prior:
            _directory(destination, "existing runtime bundle")
            os.rename(destination, backup)
        try:
            os.rename(stage, destination)
        except BaseException:
            if had_prior and backup.exists() and not destination.exists():
                os.rename(backup, destination)
            raise
        if backup.exists():
            shutil.rmtree(backup)
    finally:
        if stage.exists():
            shutil.rmtree(stage)
        if backup.exists() and not destination.exists():
            os.rename(backup, destination)


def _write_candidate(candidate: Path, pin_path: Path, seal_path: Path, root: Path) -> None:
    verified = _verify_installed(candidate, pin_path, exact_candidate=True)
    _verify_seal(candidate, pin_path, seal_path)
    _directory(root, "destination Loa root")
    if os.path.commonpath((str(candidate), str(root))) in (str(candidate), str(root)):
        fail("candidate and destination roots must be disjoint")
    _replace_runtime_tree(candidate, root)
    paths = [path for path in verified["paths"] if not path.startswith(f"{RUNTIME_ROOT}/")]
    # Publish the consumer pin last so it never names a runtime tree that has
    # not yet been copied into the worktree.
    paths = [path for path in paths if path != PIN_PATH] + [PIN_PATH]
    for path in paths:
        source = _join(candidate, path)
        _atomic_replace(root, path, _regular_bytes(source, f"candidate file {path}", MAX_ENTRY_BYTES),
                        stat.S_IMODE(source.lstat().st_mode))
    _verify_installed(root, _join(root, PIN_PATH), exact_candidate=False)


def _git_output(root: Path, arguments: Sequence[str], label: str) -> bytes:
    environment = os.environ.copy()
    environment["GIT_NO_REPLACE_OBJECTS"] = "1"
    for name in (
        "GIT_DIR",
        "GIT_WORK_TREE",
        "GIT_INDEX_FILE",
        "GIT_OBJECT_DIRECTORY",
        "GIT_ALTERNATE_OBJECT_DIRECTORIES",
    ):
        environment.pop(name, None)
    process = subprocess.run(
        ["git", *arguments],
        cwd=root,
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if process.returncode != 0:
        detail = process.stderr.decode("utf-8", errors="replace").strip()
        fail(f"{label} failed: {detail or f'exit {process.returncode}'}")
    return process.stdout


def _verify_index(candidate: Path, pin_path: Path, seal_path: Path, root: Path) -> dict[str, Any]:
    seal = _verify_seal(candidate, pin_path, seal_path)
    _directory(root, "destination Git worktree")
    top_level_raw = _git_output(root, ("rev-parse", "--show-toplevel"), "Git root discovery")
    top_level = Path(top_level_raw.decode("utf-8").strip()).resolve()
    if top_level != root.resolve():
        fail("destination root is not the exact Git worktree root")

    for item in seal["files"]:
        path = _valid_relative_path(item.get("path"), "sealed candidate path")
        expected_digest = _digest(item.get("digest"), f"sealed digest for {path}")
        expected_mode = _string(item.get("mode"), f"sealed mode for {path}")
        if expected_mode != "0644":
            fail(f"sealed candidate mode is not 0644: {path}")

        index_raw = _git_output(
            root,
            ("ls-files", "--stage", "-z", "--", path),
            f"index lookup for {path}",
        )
        entries = [entry for entry in index_raw.split(b"\0") if entry]
        if len(entries) != 1 or b"\t" not in entries[0]:
            fail(f"sealed candidate path is missing or ambiguous in the index: {path}")
        metadata, indexed_path = entries[0].split(b"\t", 1)
        fields = metadata.split(b" ")
        if len(fields) != 3 or fields[0] != b"100644" or fields[2] != b"0":
            fail(f"staged mode or stage is not exact for sealed candidate path: {path}")
        if indexed_path != path.encode("utf-8"):
            fail(f"index path disagrees with sealed candidate path: {path}")
        object_id = fields[1].decode("ascii")
        staged_raw = _git_output(root, ("cat-file", "blob", object_id), f"blob read for {path}")
        candidate_raw = _regular_bytes(
            _join(candidate, path), f"candidate file {path}", MAX_ENTRY_BYTES
        )
        if staged_raw != candidate_raw or _sha256_bytes(staged_raw) != expected_digest:
            fail(f"staged blob differs from sealed candidate bytes: {path}")
    return seal


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    create = subparsers.add_parser("create-pin", help="derive a canonical pin from verified bytes")
    create.add_argument("--release", required=True)
    create.add_argument("--repository", required=True)
    create.add_argument("--tag", required=True)
    create.add_argument("--commit", required=True)
    create.add_argument("--output", required=True)

    verify = subparsers.add_parser("verify-release", help="verify pinned release bytes offline")
    verify.add_argument("--release", required=True)
    verify.add_argument("--pin", required=True)
    verify.add_argument("--bundle-out")

    seal = subparsers.add_parser("seal-candidate", help="seal an exact installed candidate")
    seal.add_argument("--candidate", required=True)
    seal.add_argument("--pin", required=True)
    seal.add_argument("--output", required=True)

    verify_candidate = subparsers.add_parser("verify-candidate", help="revalidate a sealed candidate")
    verify_candidate.add_argument("--candidate", required=True)
    verify_candidate.add_argument("--pin", required=True)
    verify_candidate.add_argument("--seal", required=True)

    write = subparsers.add_parser("write-candidate", help="copy a sealed exact candidate into Loa")
    write.add_argument("--candidate", required=True)
    write.add_argument("--pin", required=True)
    write.add_argument("--seal", required=True)
    write.add_argument("--root", required=True)

    verify_index = subparsers.add_parser(
        "verify-index", help="verify exact sealed candidate bytes and modes in the Git index"
    )
    verify_index.add_argument("--candidate", required=True)
    verify_index.add_argument("--pin", required=True)
    verify_index.add_argument("--seal", required=True)
    verify_index.add_argument("--root", required=True)

    installed = subparsers.add_parser("verify-installed", help="verify the pinned installed tree")
    installed.add_argument("--root", required=True)
    installed.add_argument("--pin", required=True)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    options = _parser().parse_args(argv)
    try:
        if options.command == "create-pin":
            info = _verify_release(_absolute(options.release))
            pin = _pin_from_release(info, options.repository, options.tag, options.commit)
            output = _absolute(options.output)
            _write_new(output, _canonical_json_bytes(pin))
            print(f"PASS create-pin {_sha256_bytes(_canonical_json_bytes(pin))}")
        elif options.command == "verify-release":
            info = _verify_release(_absolute(options.release), _absolute(options.pin))
            if options.bundle_out:
                _materialize_bundle(info["bundle_files"], _absolute(options.bundle_out))
            print(f"PASS verify-release {info['lock']['bundle']['digest']}")
        elif options.command == "seal-candidate":
            seal = _make_seal(_absolute(options.candidate), _absolute(options.pin))
            _write_new(_absolute(options.output), _canonical_json_bytes(seal))
            print(f"PASS seal-candidate {seal['digest']}")
        elif options.command == "verify-candidate":
            seal = _verify_seal(_absolute(options.candidate), _absolute(options.pin),
                                _absolute(options.seal))
            print(f"PASS verify-candidate {seal['digest']}")
        elif options.command == "write-candidate":
            _write_candidate(_absolute(options.candidate), _absolute(options.pin),
                             _absolute(options.seal), _absolute(options.root))
            print("PASS write-candidate")
        elif options.command == "verify-index":
            seal = _verify_index(
                _absolute(options.candidate),
                _absolute(options.pin),
                _absolute(options.seal),
                _absolute(options.root),
            )
            print(f"PASS verify-index {seal['digest']}")
        elif options.command == "verify-installed":
            verified = _verify_installed(_absolute(options.root), _absolute(options.pin),
                                         exact_candidate=False)
            print(f"PASS verify-installed {verified['bundle']['bundle']['digest']}")
        else:  # pragma: no cover - argparse enforces this.
            fail("unknown command")
        return 0
    except VerificationError as error:
        print(f"FAIL {error}", file=sys.stderr)
        return 1
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"FAIL verifier rejected malformed input: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
