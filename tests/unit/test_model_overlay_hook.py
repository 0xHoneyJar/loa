"""Pytest unit tests for cycle-099 Sprint 2B model-overlay-hook.

Coverage targets per cycle-099 sprint.md AC-S2.9:
  - shell-escape value gate (validate + emit)
  - SHA256 invalidation under shared lock (cache hit semantics)
  - Atomic-write semantics (chmod 0600 BEFORE rename, same-dir tempfile)
  - Lockfile holder PID write/read + kill -0 stale recovery
  - NFS detection blocklist (mocked /proc/mounts)
  - Overlay-state.json corruption + future-version handlers
  - Bash file emitter (header shape, deterministic alias ordering)
  - Cross-runtime semantic invariant: same input → same merged content (cache key stability)

Each test maps to an SDD § reference in its docstring. Tests use the public
hook entrypoints (`run_hook(paths)`) where possible and inner helpers when a
specific failure mode requires direct invocation.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import textwrap
import time
from pathlib import Path

import pytest


# Load the hook module from its dash-named path. pytest collects this file
# under tests/unit/ → walk up to repo root → .claude/scripts/lib/.
_REPO_ROOT = Path(__file__).resolve().parents[2]
_HOOK_PATH = _REPO_ROOT / ".claude/scripts/lib/model-overlay-hook.py"
_HOOK_SPEC = importlib.util.spec_from_file_location("loa_model_overlay_hook", _HOOK_PATH)
assert _HOOK_SPEC is not None and _HOOK_SPEC.loader is not None
hook = importlib.util.module_from_spec(_HOOK_SPEC)
# Register in sys.modules BEFORE exec_module so dataclasses with
# `from __future__ import annotations` can resolve cls.__module__ correctly
# (Python 3.13 dataclasses internals walk sys.modules to resolve forward refs).
sys.modules["loa_model_overlay_hook"] = hook
_HOOK_SPEC.loader.exec_module(hook)


# -----------------------------------------------------------------------------
# Shell-escape (SDD §3.5)
# -----------------------------------------------------------------------------


@pytest.mark.parametrize(
    "value",
    [
        "opus",
        "claude-opus-4-7",
        "gpt-5.5",
        "my-custom-model",
        "abc",
        "0",
        "X.Y.Z",
        "a_b",
    ],
)
def test_shell_safe_accepts_charset(value):
    """SDD §3.5 rule 1: schema-allowed charset values pass the writer gate."""
    hook._validate_shell_safe_value(value)
    quoted = hook._emit_bash_string(value)
    # Result is either the bare value or single-quoted form; both are valid.
    assert quoted == value or quoted == f"'{value}'"


@pytest.mark.parametrize(
    "value",
    [
        "$(rm -rf /)",
        "$(touch /tmp/pwned)",
        "`whoami`",
        "foo`evil`",
        "back\\slash",
        "with\nnewline",
        "with\rcarriage",
        "nul\x00byte",
        "$VAR",
        "${HOME}",
        "'",
        '"',
        "spaces in value",
        "tab\there",
        ";",
        "|",
        "&",
        "<",
        ">",
        "(",
        ")",
        "",  # empty
        "!",
        "@",
        "+",
        "=",
        "/path/sep",
    ],
)
def test_shell_safe_rejects_metacharacters(value):
    """SDD §3.5 rule 5: hostile probes MUST be rejected before any disk write.
    Per AC-S2.7, all probes exit 1 with structured [MERGED-ALIASES-WRITE-FAILED].
    """
    with pytest.raises(ValueError) as exc_info:
        hook._emit_bash_string(value)
    assert hook._MARK_WRITE_FAILED in str(exc_info.value)


@pytest.mark.parametrize(
    "value, ok",
    [
        (0, True),
        (1, True),
        (5_000_000, True),
        (10_000_000, True),
        (-1, False),
        (1.5, False),
        ("123", False),
        (True, False),  # bool subclass of int — explicitly rejected
        (None, False),
    ],
)
def test_shell_safe_int(value, ok):
    """SDD §3.5 rule 3: cost values are non-negative integers; bools rejected."""
    if ok:
        result = hook._emit_bash_int(value)
        assert result == str(value)
    else:
        with pytest.raises(ValueError):
            hook._emit_bash_int(value)


def test_emit_bash_string_post_quote_charset_assertion():
    """SDD §3.5 rule 1 final clause: post-shlex.quote() result MUST be in
    _SHELL_SAFE_CHARSET. We already enforce input charset, but verify the
    closure assertion runs.
    """
    # All chars in the safe charset (skip `.` since `...` would trip
    # the dot-dot belt-and-suspenders check):
    for ch in "abcXYZ012_-":
        out = hook._emit_bash_string(ch * 3)
        for c in out:
            assert c in hook._SHELL_SAFE_CHARSET
    # Single dot is fine (no dot-dot pattern)
    out = hook._emit_bash_string("a.b")
    for c in out:
        assert c in hook._SHELL_SAFE_CHARSET


def test_dot_dot_companion_check_rejects():
    """cycle-099 feedback_charclass_dotdot_bypass.md: belt-and-suspenders
    rejection of `..` even though it matches the charset regex.
    """
    for value in ["..", "a..", "..b", "a..b", "..foo..", "x.y..z"]:
        with pytest.raises(ValueError) as exc_info:
            hook._emit_bash_string(value)
        assert hook._MARK_WRITE_FAILED in str(exc_info.value)


def test_single_dot_still_accepted():
    """Positive control: single dot in version-style strings IS accepted."""
    for value in ["a.b", "1.0", "gpt-5.5", "v1.2.3"]:
        # Should not raise
        hook._emit_bash_string(value)


# -----------------------------------------------------------------------------
# SHA256 cache key (SDD §1.4.4)
# -----------------------------------------------------------------------------


def test_compute_input_sha256_stable_across_key_order():
    """Cache-key hash MUST be stable under dict key reordering (sort_keys=True
    in JSON canonical encoding).
    """
    sot1 = {"providers": {"a": 1, "b": 2}, "aliases": {"x": "y"}}
    sot2 = {"aliases": {"x": "y"}, "providers": {"b": 2, "a": 1}}
    op = {"model_aliases_extra": {"schema_version": "1.0.0", "entries": []}}
    assert hook._compute_input_sha256(sot1, op) == hook._compute_input_sha256(sot2, op)


def test_compute_input_sha256_only_extras_subblock_matters():
    """Cache invalidation should NOT trigger on unrelated operator-config edits.
    Only the model_aliases_extra block contributes to the hash.
    """
    sot = {"providers": {"x": 1}}
    op_a = {"unrelated_field": "value-A", "model_aliases_extra": {"schema_version": "1.0.0"}}
    op_b = {"unrelated_field": "value-B", "model_aliases_extra": {"schema_version": "1.0.0"}}
    assert hook._compute_input_sha256(sot, op_a) == hook._compute_input_sha256(sot, op_b)


def test_compute_input_sha256_changes_with_extras_change():
    sot = {"providers": {"x": 1}}
    op_a = {"model_aliases_extra": {"schema_version": "1.0.0", "entries": []}}
    op_b = {"model_aliases_extra": {"schema_version": "1.0.0", "entries": [{"id": "x"}]}}
    assert hook._compute_input_sha256(sot, op_a) != hook._compute_input_sha256(sot, op_b)


# -----------------------------------------------------------------------------
# Atomic-write (SDD §1.4.4 + §6.3.3)
# -----------------------------------------------------------------------------


def test_atomic_write_creates_with_0600(tmp_path):
    """SDD §1.4.4: chmod 0600 BEFORE rename — final file is mode 0600.
    Implementation calls os.fchmod on the open fd before rename.
    """
    target = tmp_path / "out.sh"
    hook._atomic_write_text(target, "content\n", mode=0o600)
    assert target.is_file()
    st = target.stat()
    perms = st.st_mode & 0o777
    assert perms == 0o600, f"expected 0o600 got {oct(perms)}"


def test_atomic_write_uses_same_directory_tempfile(tmp_path, monkeypatch):
    """SDD §1.4.4 forbids ${TMPDIR:-/tmp}; tempfile must be in target's dir."""
    target_dir = tmp_path / "subdir"
    target_dir.mkdir()
    target = target_dir / "out.sh"

    seen_paths: list[str] = []
    real_open = os.open

    def spy_open(path, flags, *args, **kwargs):
        seen_paths.append(str(path))
        return real_open(path, flags, *args, **kwargs)

    monkeypatch.setattr(os, "open", spy_open)
    hook._atomic_write_text(target, "ok\n")
    # The tempfile path should be inside target_dir
    tmp_paths = [p for p in seen_paths if ".tmp." in p]
    assert tmp_paths, f"expected a tempfile path; saw: {seen_paths}"
    for tp in tmp_paths:
        assert str(target_dir) in tp, f"tempfile {tp} not in same dir as target {target_dir}"


def test_atomic_write_overwrite_replaces_existing(tmp_path):
    target = tmp_path / "out.sh"
    target.write_text("OLD")
    hook._atomic_write_text(target, "NEW")
    assert target.read_text() == "NEW"


def test_atomic_write_failure_cleans_tempfile(tmp_path, monkeypatch):
    """If write fails mid-way, the tempfile should be unlinked."""
    target = tmp_path / "out.sh"

    real_write = os.write
    call_count = {"n": 0}

    def fail_write(fd, data):
        call_count["n"] += 1
        raise OSError(5, "I/O error")

    monkeypatch.setattr(os, "write", fail_write)
    with pytest.raises(OSError):
        hook._atomic_write_text(target, "anything")
    # Target shouldn't exist after failure
    assert not target.is_file()
    # No leftover .tmp.* in the dir
    leftover = list(tmp_path.glob("*.tmp.*"))
    assert not leftover, f"leftover tempfiles after failure: {leftover}"


# -----------------------------------------------------------------------------
# Lockfile + holder PID (SDD §6.3.1)
# -----------------------------------------------------------------------------


def test_lockfile_write_read_holder_pid(tmp_path):
    lockpath = tmp_path / "merged.sh.lock"
    hook._ensure_lockfile(lockpath)
    hook._write_lockfile_holder(lockpath, pid=12345)
    assert hook._read_lockfile_holder_pid(lockpath) == 12345


def test_read_lockfile_holder_returns_none_for_missing(tmp_path):
    assert hook._read_lockfile_holder_pid(tmp_path / "nonexistent") is None


def test_read_lockfile_holder_returns_none_for_unparseable(tmp_path):
    p = tmp_path / "bad.lock"
    p.write_text("garbage\nno-pid-line-here\n")
    assert hook._read_lockfile_holder_pid(p) is None


def test_try_kill0_alive_process():
    """Check our own PID is alive."""
    assert hook._try_kill0(os.getpid()) is True


def test_try_kill0_dead_process():
    """A PID 1 reaped child is impossible to fake portably; use a clearly
    impossible PID. PIDs above 2^22 typically don't exist on Linux.
    """
    huge_pid = 2 ** 30  # 1073741824
    assert hook._try_kill0(huge_pid) is False


def test_try_kill0_invalid_pid():
    assert hook._try_kill0(0) is False
    assert hook._try_kill0(-1) is False


def test_acquire_release_lock(tmp_path):
    lockfile = tmp_path / "x.lock"
    handle = hook._acquire_lock(lockfile, exclusive=True, timeout_ms=1000)
    assert handle is not None
    assert handle.mode == "exclusive"
    hook._release_lock(handle)


def test_lock_timeout_when_held(tmp_path):
    lockfile = tmp_path / "x.lock"
    held = hook._acquire_lock(lockfile, exclusive=True, timeout_ms=1000)
    assert held is not None
    try:
        # second exclusive should time out fast
        t0 = time.monotonic()
        result = hook._acquire_lock(lockfile, exclusive=True, timeout_ms=200)
        elapsed_ms = (time.monotonic() - t0) * 1000
        assert result is None
        # Timeout should be ≥ 200ms but not vastly more (give margin for poll overhead)
        assert 150 <= elapsed_ms <= 800, f"unexpected timeout duration {elapsed_ms}ms"
    finally:
        hook._release_lock(held)


# -----------------------------------------------------------------------------
# NFS detection (SDD §6.6)
# -----------------------------------------------------------------------------


def test_is_network_filesystem_blocklist():
    for fs in ["nfs", "nfs3", "nfs4", "cifs", "smbfs", "smb3", "fuse.sshfs", "fuse.s3fs", "autofs", "davfs"]:
        assert hook._is_network_filesystem(fs), f"{fs} should be blocked"


def test_is_network_filesystem_allowlist():
    for fs in ["ext4", "btrfs", "xfs", "tmpfs", "apfs", "hfs", "zfs", ""]:
        assert not hook._is_network_filesystem(fs), f"{fs} should NOT be blocked"


def test_detect_filesystem_type_via_proc_mounts(tmp_path):
    """Mock a /proc/mounts pointing at our tmp_path with a fake NFS entry."""
    fake_mounts = tmp_path / "mounts"
    target = tmp_path / "subdir" / "lock"
    target.parent.mkdir()
    fake_mounts.write_text(
        "tmpfs / tmpfs rw 0 0\n"
        f"server:/share {tmp_path} nfs4 rw 0 0\n"
    )
    fs = hook._detect_filesystem_type(target, proc_mounts_path=str(fake_mounts))
    assert fs == "nfs4"


def test_detect_filesystem_type_longest_prefix_match(tmp_path):
    fake_mounts = tmp_path / "mounts"
    target = tmp_path / "deep" / "nested" / "file"
    target.parent.mkdir(parents=True)
    fake_mounts.write_text(
        f"tmpfs {tmp_path} tmpfs rw 0 0\n"
        f"server:/share {tmp_path / 'deep'} nfs4 rw 0 0\n"
        "rootfs / rootfs rw 0 0\n"
    )
    # Should match the deepest (nfs4) mountpoint, not tmpfs
    fs = hook._detect_filesystem_type(target, proc_mounts_path=str(fake_mounts))
    assert fs == "nfs4"


def test_detect_filesystem_type_falls_through_when_proc_mounts_missing(tmp_path):
    """When /proc/mounts is unreadable, we should fall to df -T or mount(8).
    On Linux, df -T should give us the real fs type."""
    fs = hook._detect_filesystem_type(tmp_path, proc_mounts_path="/nonexistent/path")
    # On Linux CI runners, the tmp_path is usually tmpfs or ext4. We don't
    # require a specific value, just non-empty (i.e., detection didn't
    # silently fail).
    assert fs != ""


# -----------------------------------------------------------------------------
# Overlay-state.json (SDD §6.3.3)
# -----------------------------------------------------------------------------


def test_overlay_state_initialize_when_missing(tmp_path, capsys):
    state_path = tmp_path / "overlay-state.json"
    state = hook._read_overlay_state(state_path)
    assert state["state"] == "fresh-init"
    assert state["schema_version"] == hook._OVERLAY_STATE_SCHEMA_VERSION
    assert state["degraded_since"] is None
    assert state["cache_sha256"] is None
    assert state_path.is_file()
    captured = capsys.readouterr()
    assert hook._MARK_STATE_INIT in captured.err


def test_overlay_state_rebuild_after_corruption(tmp_path, capsys):
    state_path = tmp_path / "overlay-state.json"
    state_path.write_text("{not valid json{{{")
    state = hook._read_overlay_state(state_path)
    assert state["state"] == "rebuilt-after-corruption"
    assert state["schema_version"] == hook._OVERLAY_STATE_SCHEMA_VERSION
    captured = capsys.readouterr()
    assert hook._MARK_STATE_CORRUPT in captured.err
    # corrupt original preserved
    corrupted = list(tmp_path.glob("overlay-state.json.corrupt-*"))
    assert len(corrupted) == 1


def test_overlay_state_future_version_emits_marker(tmp_path, capsys):
    state_path = tmp_path / "overlay-state.json"
    future = {
        "schema_version": hook._OVERLAY_STATE_SCHEMA_VERSION + 99,
        "degraded_since": None,
        "cache_sha256": None,
        "reason": None,
        "last_updated": "2099-01-01T00:00:00Z",
        "state": "healthy",
    }
    state_path.write_text(json.dumps(future))
    hook._read_overlay_state(state_path)
    captured = capsys.readouterr()
    assert hook._MARK_STATE_FUTURE in captured.err


def test_overlay_state_atomic_write_creates_with_0600(tmp_path):
    state_path = tmp_path / "overlay-state.json"
    state = {
        "schema_version": 1,
        "degraded_since": None,
        "cache_sha256": None,
        "reason": None,
        "last_updated": "2026-01-01T00:00:00Z",
        "state": "healthy",
    }
    hook._write_overlay_state(state_path, state)
    perms = state_path.stat().st_mode & 0o777
    assert perms == 0o600


# -----------------------------------------------------------------------------
# Alias resolution
# -----------------------------------------------------------------------------


def _sample_sot() -> dict:
    return {
        "providers": {
            "anthropic": {
                "models": {
                    "claude-opus-4-7": {
                        "endpoint_family": "messages",
                        "pricing": {"input_per_mtok": 5_000_000, "output_per_mtok": 25_000_000},
                    },
                    "claude-sonnet-4-6": {
                        "endpoint_family": "messages",
                        "pricing": {"input_per_mtok": 3_000_000, "output_per_mtok": 15_000_000},
                    },
                },
            },
            "openai": {
                "models": {
                    "gpt-5.5": {
                        "endpoint_family": "responses",
                        "pricing": {"input_per_mtok": 5_000_000, "output_per_mtok": 30_000_000},
                    },
                },
            },
        },
        "aliases": {
            "opus": "anthropic:claude-opus-4-7",
            "cheap": "anthropic:claude-sonnet-4-6",
            "reviewer": "openai:gpt-5.5",
            "broken-pointer": "anthropic:no-such-model",  # should be skipped
            "non-string-value": 123,  # should be skipped
        },
    }


def test_resolve_framework_aliases_happy_path():
    sot = _sample_sot()
    aliases = hook._resolve_framework_aliases(sot)
    assert "opus" in aliases
    assert aliases["opus"].provider == "anthropic"
    assert aliases["opus"].api_id == "claude-opus-4-7"
    assert aliases["opus"].endpoint_family == "messages"
    assert aliases["opus"].input_per_mtok == 5_000_000
    assert aliases["opus"].output_per_mtok == 25_000_000


def test_resolve_framework_aliases_skips_broken_pointer():
    sot = _sample_sot()
    aliases = hook._resolve_framework_aliases(sot)
    assert "broken-pointer" not in aliases
    assert "non-string-value" not in aliases


def test_resolve_operator_extras_happy_path():
    extras = {
        "schema_version": "1.0.0",
        "entries": [
            {
                "id": "my-custom",
                "provider": "openai",
                "api_id": "gpt-5.7-pro",
                "endpoint_family": "responses",
                "capabilities": ["chat"],
                "context_window": 256000,
                "pricing": {"input_per_mtok": 40_000_000, "output_per_mtok": 200_000_000},
            },
        ],
    }
    out = hook._resolve_operator_extras(extras)
    assert "my-custom" in out
    assert out["my-custom"].provider == "openai"
    assert out["my-custom"].api_id == "gpt-5.7-pro"
    assert out["my-custom"].endpoint_family == "responses"


def test_resolve_operator_extras_default_endpoint_family():
    extras = {
        "schema_version": "1.0.0",
        "entries": [
            {
                "id": "no-family",
                "provider": "openai",
                "api_id": "x",
                "capabilities": ["chat"],
                "context_window": 1024,
                "pricing": {"input_per_mtok": 0, "output_per_mtok": 0},
            },
        ],
    }
    out = hook._resolve_operator_extras(extras)
    assert out["no-family"].endpoint_family == "chat"


def test_resolve_operator_extras_returns_empty_for_none():
    assert hook._resolve_operator_extras(None) == {}
    assert hook._resolve_operator_extras({}) == {}
    assert hook._resolve_operator_extras({"entries": "not-a-list"}) == {}


def test_merge_aliases_framework_wins_on_collision():
    fw = {"opus": hook.ResolvedAlias("opus", "anthropic", "old", "messages", 1, 2)}
    ex = {"opus": hook.ResolvedAlias("opus", "openai", "evil", "chat", 99, 99)}
    merged = hook._merge_aliases(fw, ex)
    # framework wins
    assert merged["opus"].provider == "anthropic"
    assert merged["opus"].api_id == "old"


# -----------------------------------------------------------------------------
# Bash file emitter (SDD §3.5)
# -----------------------------------------------------------------------------


def test_build_bash_content_header_shape():
    aliases = {
        "opus": hook.ResolvedAlias("opus", "anthropic", "claude-opus-4-7", "messages", 5_000_000, 25_000_000),
    }
    content = hook._build_bash_content(
        aliases,
        source_sha="a" * 64,
        version=42,
        holder_pid=12345,
        timestamp="2026-05-06T12:00:00Z",
    )
    assert "# Generated by .claude/scripts/lib/model-overlay-hook.py at 2026-05-06T12:00:00Z" in content
    assert "# version=42" in content
    assert f"# source-sha256={'a' * 64}" in content
    assert "# holder-pid=12345" in content
    assert "# DO NOT EDIT" in content
    assert "declare -gA LOA_MODEL_PROVIDERS=(" in content
    assert "declare -gA LOA_MODEL_IDS=(" in content
    assert "declare -gA LOA_MODEL_ENDPOINT_FAMILIES=(" in content
    assert "declare -gA LOA_MODEL_COST_INPUT_PER_MTOK=(" in content
    assert "declare -gA LOA_MODEL_COST_OUTPUT_PER_MTOK=(" in content
    assert "LOA_OVERLAY_FINGERPRINT=" in content


def test_build_bash_content_deterministic_alias_order():
    aliases = {
        "zeta": hook.ResolvedAlias("zeta", "anthropic", "z", "messages", 1, 1),
        "alpha": hook.ResolvedAlias("alpha", "anthropic", "a", "messages", 1, 1),
        "mu": hook.ResolvedAlias("mu", "anthropic", "m", "messages", 1, 1),
    }
    content = hook._build_bash_content(
        aliases, source_sha="b" * 64, version=1, holder_pid=1, timestamp="2026-01-01T00:00:00Z",
    )
    # alpha < mu < zeta in the providers block
    providers_block = content.split("LOA_MODEL_PROVIDERS=(")[1].split(")")[0]
    alpha_idx = providers_block.index("alpha")
    mu_idx = providers_block.index("mu")
    zeta_idx = providers_block.index("zeta")
    assert alpha_idx < mu_idx < zeta_idx


def test_build_bash_content_passes_bash_syntax_check(tmp_path):
    aliases = {
        "opus": hook.ResolvedAlias("opus", "anthropic", "claude-opus-4-7", "messages", 5_000_000, 25_000_000),
        "reviewer": hook.ResolvedAlias("reviewer", "openai", "gpt-5.5", "responses", 5_000_000, 30_000_000),
    }
    content = hook._build_bash_content(
        aliases, source_sha="c" * 64, version=1, holder_pid=999, timestamp="2026-01-01T00:00:00Z",
    )
    assert hook._bash_syntax_check(content) is True


def test_build_bash_content_rejects_hostile_alias_name():
    """If an alias somehow slips past schema validation with a `$`, the
    writer MUST refuse before emitting."""
    aliases = {
        "$(rm -rf /)": hook.ResolvedAlias("$(rm -rf /)", "anthropic", "claude-opus-4-7", "messages", 1, 1),
    }
    with pytest.raises(ValueError) as exc_info:
        hook._build_bash_content(
            aliases, source_sha="d" * 64, version=1, holder_pid=1, timestamp="2026-01-01T00:00:00Z",
        )
    assert hook._MARK_WRITE_FAILED in str(exc_info.value)


def test_build_bash_content_sourceable_in_bash(tmp_path):
    """End-to-end: emit content, write to file, source it in a bash subshell,
    and verify the arrays are populated. This is the cross-runtime parity
    smoke test for the writer.
    """
    aliases = {
        "opus": hook.ResolvedAlias("opus", "anthropic", "claude-opus-4-7", "messages", 5_000_000, 25_000_000),
    }
    content = hook._build_bash_content(
        aliases, source_sha="e" * 64, version=1, holder_pid=1, timestamp="2026-01-01T00:00:00Z",
    )
    out = tmp_path / "merged.sh"
    out.write_text(content)
    script = textwrap.dedent(f"""
        source {out}
        echo "PROVIDERS_OPUS=${{LOA_MODEL_PROVIDERS[opus]}}"
        echo "IDS_OPUS=${{LOA_MODEL_IDS[opus]}}"
        echo "FAMILY_OPUS=${{LOA_MODEL_ENDPOINT_FAMILIES[opus]}}"
        echo "COST_IN_OPUS=${{LOA_MODEL_COST_INPUT_PER_MTOK[opus]}}"
        echo "COST_OUT_OPUS=${{LOA_MODEL_COST_OUTPUT_PER_MTOK[opus]}}"
        echo "FINGERPRINT=${{LOA_OVERLAY_FINGERPRINT}}"
    """)
    result = subprocess.run(
        ["bash", "-c", script], capture_output=True, text=True, check=False, timeout=10,
    )
    assert result.returncode == 0, f"bash sourcing failed: {result.stderr}"
    assert "PROVIDERS_OPUS=anthropic" in result.stdout
    assert "IDS_OPUS=claude-opus-4-7" in result.stdout
    assert "FAMILY_OPUS=messages" in result.stdout
    assert "COST_IN_OPUS=5000000" in result.stdout
    assert "COST_OUT_OPUS=25000000" in result.stdout


# -----------------------------------------------------------------------------
# End-to-end run_hook smoke (cache hit + cold regen)
# -----------------------------------------------------------------------------


def _write_yaml(path: Path, doc: dict) -> None:
    import yaml
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(yaml.safe_dump(doc, sort_keys=True))


def _build_paths(tmp_path: Path, sot_doc: dict, op_doc: dict, schema_path: Path) -> "hook.HookPaths":
    sot = tmp_path / "model-config.yaml"
    op = tmp_path / ".loa.config.yaml"
    merged = tmp_path / "run" / "merged.sh"
    lockfile = tmp_path / "run" / "merged.sh.lock"
    state = tmp_path / "run" / "overlay-state.json"
    _write_yaml(sot, sot_doc)
    _write_yaml(op, op_doc)
    return hook.HookPaths(
        sot=sot, operator=op, merged=merged, lockfile=lockfile,
        state=state, schema=schema_path,
    )


def test_run_hook_cold_regen_writes_merged_file(tmp_path, monkeypatch):
    """End-to-end: no merged file exists; hook regens; bash arrays populated."""
    schema_src = _REPO_ROOT / ".claude/data/trajectory-schemas/model-aliases-extra.schema.json"
    paths = _build_paths(tmp_path, _sample_sot(), {}, schema_src)
    rc = hook.run_hook(paths)
    assert rc == hook.EXIT_OK, "cold regen should succeed"
    assert paths.merged.is_file()
    perms = paths.merged.stat().st_mode & 0o777
    assert perms == 0o600


def test_run_hook_cache_hit_skips_regen(tmp_path):
    """After a successful regen, a second run should NOT modify the file
    (mtime + content stable). Cache-key invalidation under shared lock.
    """
    schema_src = _REPO_ROOT / ".claude/data/trajectory-schemas/model-aliases-extra.schema.json"
    paths = _build_paths(tmp_path, _sample_sot(), {}, schema_src)
    rc = hook.run_hook(paths)
    assert rc == hook.EXIT_OK
    first_mtime = paths.merged.stat().st_mtime_ns
    first_content = paths.merged.read_text()

    # Wait long enough to be sure mtime would change if rewritten
    time.sleep(0.05)

    rc2 = hook.run_hook(paths)
    assert rc2 == hook.EXIT_OK
    assert paths.merged.stat().st_mtime_ns == first_mtime, "cache hit should NOT rewrite"
    assert paths.merged.read_text() == first_content


def test_run_hook_invalid_extras_refuses(tmp_path):
    """Validation failure at refuse-to-start surface (NFR-Op-2)."""
    schema_src = _REPO_ROOT / ".claude/data/trajectory-schemas/model-aliases-extra.schema.json"
    bad_op = {
        "model_aliases_extra": {
            "schema_version": "1.0.0",
            "entries": [
                # Missing required `provider`, `api_id`, etc. — invalid per schema.
                {"id": "broken"},
            ],
        },
    }
    paths = _build_paths(tmp_path, _sample_sot(), bad_op, schema_src)
    rc = hook.run_hook(paths)
    assert rc == hook.EXIT_REFUSE


def test_run_hook_network_fs_refuses_without_override(tmp_path, monkeypatch):
    """SDD §6.6: network FS detection; refuse without LOA_ALLOW_NETWORK_FS_FOR_MERGED_ALIASES=1."""
    schema_src = _REPO_ROOT / ".claude/data/trajectory-schemas/model-aliases-extra.schema.json"
    paths = _build_paths(tmp_path, _sample_sot(), {}, schema_src)

    def fake_detect(target_path, proc_mounts_path="/proc/mounts"):
        return "nfs4"

    monkeypatch.setattr(hook, "_detect_filesystem_type", fake_detect)
    monkeypatch.delenv("LOA_ALLOW_NETWORK_FS_FOR_MERGED_ALIASES", raising=False)
    rc = hook.run_hook(paths)
    assert rc == hook.EXIT_REFUSE


def test_run_hook_network_fs_proceeds_with_override(tmp_path, monkeypatch, capsys):
    """SDD §6.6: opt-in proceeds with WARN log."""
    schema_src = _REPO_ROOT / ".claude/data/trajectory-schemas/model-aliases-extra.schema.json"
    paths = _build_paths(tmp_path, _sample_sot(), {}, schema_src)

    def fake_detect(target_path, proc_mounts_path="/proc/mounts"):
        return "nfs4"

    monkeypatch.setattr(hook, "_detect_filesystem_type", fake_detect)
    monkeypatch.setenv("LOA_ALLOW_NETWORK_FS_FOR_MERGED_ALIASES", "1")
    rc = hook.run_hook(paths)
    assert rc == hook.EXIT_OK
    captured = capsys.readouterr()
    assert hook._MARK_NETWORK_FS_OVERRIDE in captured.err


def test_run_hook_with_operator_extras_emits_extra_aliases(tmp_path):
    """End-to-end: operator adds a new model; merged file contains it."""
    schema_src = _REPO_ROOT / ".claude/data/trajectory-schemas/model-aliases-extra.schema.json"
    op = {
        "model_aliases_extra": {
            "schema_version": "1.0.0",
            "entries": [
                {
                    "id": "my-extra",
                    "provider": "openai",
                    "api_id": "gpt-5.7-pro",
                    "endpoint_family": "responses",
                    "capabilities": ["chat"],
                    "context_window": 256000,
                    "pricing": {"input_per_mtok": 40_000_000, "output_per_mtok": 200_000_000},
                    "acknowledge_permissions_baseline": True,
                },
            ],
        },
    }
    paths = _build_paths(tmp_path, _sample_sot(), op, schema_src)
    rc = hook.run_hook(paths)
    assert rc == hook.EXIT_OK
    content = paths.merged.read_text()
    assert "[my-extra]=" in content
    assert "gpt-5.7-pro" in content


# -----------------------------------------------------------------------------
# Env-var configurability
# -----------------------------------------------------------------------------


def test_shared_timeout_env_override(monkeypatch):
    monkeypatch.setenv("LOA_OVERLAY_LOCK_TIMEOUT_SHARED_MS", "12345")
    assert hook._shared_timeout_ms() == 12345


def test_exclusive_timeout_env_override(monkeypatch):
    monkeypatch.setenv("LOA_OVERLAY_LOCK_TIMEOUT_EXCLUSIVE_MS", "67890")
    assert hook._exclusive_timeout_ms() == 67890


def test_shared_timeout_env_invalid_falls_back(monkeypatch):
    monkeypatch.setenv("LOA_OVERLAY_LOCK_TIMEOUT_SHARED_MS", "not-a-number")
    assert hook._shared_timeout_ms() == hook._DEFAULT_SHARED_TIMEOUT_MS


def test_strict_mode_env(monkeypatch):
    monkeypatch.setenv("LOA_OVERLAY_STRICT", "1")
    assert hook._strict_mode() is True
    monkeypatch.setenv("LOA_OVERLAY_STRICT", "0")
    assert hook._strict_mode() is False
    monkeypatch.delenv("LOA_OVERLAY_STRICT", raising=False)
    assert hook._strict_mode() is False


# -----------------------------------------------------------------------------
# Strict mode + lock timeout → EXIT_LOCK_FAILED
# -----------------------------------------------------------------------------


def test_strict_mode_lock_timeout_refuses_to_start(tmp_path, monkeypatch):
    """When LOA_OVERLAY_STRICT=1 AND a lock cannot be acquired AND the
    holder isn't dead, the hook exits 65 (EXIT_LOCK_FAILED) — does NOT
    fall back to degraded read-only mode.
    """
    schema_src = _REPO_ROOT / ".claude/data/trajectory-schemas/model-aliases-extra.schema.json"
    paths = _build_paths(tmp_path, _sample_sot(), {}, schema_src)

    # First, populate the merged file via a normal run
    rc = hook.run_hook(paths)
    assert rc == hook.EXIT_OK
    assert paths.merged.is_file()

    # Now hold an exclusive lock from this process; the next hook
    # invocation should time out trying to acquire shared.
    held = hook._acquire_lock(paths.lockfile, exclusive=True, timeout_ms=1000)
    assert held is not None
    # Write a pid that's THIS process (alive) so stale-recovery fails.
    hook._write_lockfile_holder(paths.lockfile, pid=os.getpid())
    try:
        # Force tiny timeouts to make the test fast
        monkeypatch.setenv("LOA_OVERLAY_STRICT", "1")
        monkeypatch.setenv("LOA_OVERLAY_LOCK_TIMEOUT_SHARED_MS", "100")
        monkeypatch.setenv("LOA_OVERLAY_LOCK_TIMEOUT_EXCLUSIVE_MS", "100")
        # Modify the merged file's source-sha so it will be considered stale
        # for any new run, but in this test the lock-acquisition fails first.
        rc = hook.run_hook(paths)
        # Strict mode: refuses to start (EXIT_LOCK_FAILED)
        assert rc == hook.EXIT_LOCK_FAILED
    finally:
        hook._release_lock(held)


def test_default_mode_degraded_fallback_when_cache_valid(tmp_path, monkeypatch, capsys):
    """When LOA_OVERLAY_STRICT is unset AND the lock times out AND the cached
    file IS the up-to-date answer (source-sha matches current input), the hook
    proceeds in degraded read-only mode with [OVERLAY-DEGRADED-READONLY] WARN.
    """
    schema_src = _REPO_ROOT / ".claude/data/trajectory-schemas/model-aliases-extra.schema.json"
    paths = _build_paths(tmp_path, _sample_sot(), {}, schema_src)

    # Populate the cache
    assert hook.run_hook(paths) == hook.EXIT_OK
    assert paths.merged.is_file()

    # Hold the lock
    held = hook._acquire_lock(paths.lockfile, exclusive=True, timeout_ms=1000)
    assert held is not None
    hook._write_lockfile_holder(paths.lockfile, pid=os.getpid())
    try:
        monkeypatch.delenv("LOA_OVERLAY_STRICT", raising=False)
        monkeypatch.setenv("LOA_OVERLAY_LOCK_TIMEOUT_SHARED_MS", "100")
        monkeypatch.setenv("LOA_OVERLAY_LOCK_TIMEOUT_EXCLUSIVE_MS", "100")
        rc = hook.run_hook(paths)
        # Default mode + cache valid: proceed (EXIT_OK) with degraded WARN
        assert rc == hook.EXIT_OK
        captured = capsys.readouterr()
        assert hook._MARK_DEGRADED in captured.err
        # State file should reflect degraded mode
        state = json.loads(paths.state.read_text())
        assert state["state"] == "degraded"
        assert state["degraded_since"] is not None
    finally:
        hook._release_lock(held)


# -----------------------------------------------------------------------------
# Iter-1 review-fix regression pins
# -----------------------------------------------------------------------------


def test_lockfile_symlink_refused_at_ensure(tmp_path):
    """CYP-F1: a symlinked lockfile path MUST be refused (not followed).
    Attacker plants `.lock` as a symlink to ~/.ssh/authorized_keys; the
    hook MUST raise rather than open-and-corrupt the symlink target.
    """
    target = tmp_path / "decoy"
    target.write_text("decoy content")
    lockpath = tmp_path / "merged.sh.lock"
    os.symlink(str(target), str(lockpath))
    with pytest.raises(OSError) as exc_info:
        hook._ensure_lockfile(lockpath)
    assert hook._MARK_WRITE_FAILED in str(exc_info.value)


def test_lockfile_symlink_refused_at_acquire(tmp_path):
    """CYP-F1: O_NOFOLLOW on the lockfile open in `_acquire_lock` rejects
    a symlinked path even if `_ensure_lockfile` somehow let it pass.
    """
    decoy = tmp_path / "decoy"
    decoy.write_text("decoy")
    lockpath = tmp_path / "evil.lock"
    os.symlink(str(decoy), str(lockpath))
    with pytest.raises(OSError):
        hook._acquire_lock(lockpath, exclusive=True, timeout_ms=200)


def test_atomic_write_refuses_target_dir_symlink_escape(tmp_path, monkeypatch):
    """CYP-F4: target_dir resolves through symlinks; a `.run/` symlinked to
    `/tmp/attacker/` MUST be refused before any write. The verification gate
    (project-root containment) is bypassed in tests via the test-runner
    marker (PYTEST_CURRENT_TEST is set), but we exercise the function
    `_verify_dir_within_project` directly to prove the contract.
    """
    # In the production path, _verify_dir_within_project rejects when the
    # resolved target_dir is outside project_root AND no test-runner marker
    # is present. Strip the test markers AND verify rejection.
    monkeypatch.delenv("PYTEST_CURRENT_TEST", raising=False)
    monkeypatch.delenv("BATS_VERSION", raising=False)
    monkeypatch.delenv("LOA_OVERLAY_TEST_MODE", raising=False)
    # Construct a target dir that's clearly outside the project root
    outside = Path("/tmp") / f"loa-attacker-{os.getpid()}"
    outside.mkdir(exist_ok=True)
    try:
        with pytest.raises(OSError) as exc_info:
            hook._verify_dir_within_project(outside)
        assert hook._MARK_WRITE_FAILED in str(exc_info.value)
        assert "escapes project" in str(exc_info.value).lower() or \
               "outside project" in str(exc_info.value).lower()
    finally:
        outside.rmdir()


def test_run_hook_refuses_future_version_state(tmp_path):
    """GP-F1 + CYP-F5: when `.run/overlay-state.json` carries a
    schema_version higher than the runtime supports, run_hook MUST exit 78
    (refuse-to-start) per SDD §6.3.3 future-version row.
    """
    schema_src = _REPO_ROOT / ".claude/data/trajectory-schemas/model-aliases-extra.schema.json"
    paths = _build_paths(tmp_path, _sample_sot(), {}, schema_src)
    paths.state.parent.mkdir(parents=True, exist_ok=True)
    paths.state.write_text(json.dumps({
        "schema_version": hook._OVERLAY_STATE_SCHEMA_VERSION + 99,
        "degraded_since": None,
        "cache_sha256": None,
        "reason": None,
        "last_updated": "2099-01-01T00:00:00Z",
        "state": "healthy",
    }))
    rc = hook.run_hook(paths)
    assert rc == hook.EXIT_REFUSE


def test_clear_degraded_state_does_not_downgrade_future_version(tmp_path):
    """CYP-F5: future-version state files MUST NOT be silently rewritten
    with a lower schema_version. Operator who upgraded then downgraded
    keeps their forensic state.
    """
    state_path = tmp_path / "overlay-state.json"
    future = {
        "schema_version": hook._OVERLAY_STATE_SCHEMA_VERSION + 5,
        "degraded_since": "2099-01-01T00:00:00Z",
        "cache_sha256": "f" * 64,
        "reason": "future-cycle-degraded",
        "last_updated": "2099-01-01T00:00:00Z",
        "state": "degraded",
    }
    state_path.write_text(json.dumps(future))
    hook._clear_degraded_state(state_path)
    after = json.loads(state_path.read_text())
    # State is preserved at the future schema_version
    assert after["schema_version"] == hook._OVERLAY_STATE_SCHEMA_VERSION + 5
    assert after["state"] == "degraded"


def test_corruption_rebuild_uses_unique_suffix(tmp_path, capsys):
    """GP-F2: two concurrent rebuilds within the same second MUST produce
    distinct `corrupt-<ts>.<suffix>` filenames. The suffix is a 4-byte
    secrets.token_hex (8 hex chars), so the collision space is 2^32.
    """
    state_path = tmp_path / "overlay-state.json"

    # Simulate two concurrent rebuilds: write corrupt content + read; repeat.
    state_path.write_text("corrupt-A")
    hook._read_overlay_state(state_path)
    state_path.write_text("corrupt-B")
    hook._read_overlay_state(state_path)

    corrupt_files = list(tmp_path.glob("overlay-state.json.corrupt-*"))
    assert len(corrupt_files) == 2, f"expected 2 distinct corrupt files; got {corrupt_files}"
    # All filenames have a hex suffix beyond the timestamp
    for cf in corrupt_files:
        # name format: overlay-state.json.corrupt-<iso>.<8-hex>
        parts = cf.name.split(".")
        assert len(parts) >= 4
        suffix = parts[-1]
        # 4-byte token_hex = 8 hex chars
        assert len(suffix) == 8
        assert all(c in "0123456789abcdef" for c in suffix)


def test_post_quote_charset_catches_input_gate_loosening():
    """GP-F6 regression pin: if a future code change loosens
    `_validate_shell_safe_value` to admit a char that shlex.quote escapes
    (e.g., space, single-quote), the post-shlex.quote charset assertion
    MUST fire. We exercise this via the test-only entry point that
    bypasses the input gate.
    """
    # These would each cause shlex.quote to emit a single-quoted form
    # containing characters outside _SHELL_SAFE_CHARSET (e.g., space).
    for hostile in ["a b", "x'y", 'a"b', "$x", "a;b"]:
        with pytest.raises(ValueError) as exc_info:
            hook._emit_bash_string_post_quote_only(hostile)
        assert hook._MARK_WRITE_FAILED in str(exc_info.value)


def test_test_mode_third_leg_gate_rejects_without_runner_marker(monkeypatch):
    """CYP-F3: when LOA_OVERLAY_TEST_MODE=1 + LOA_OVERLAY_PROC_MOUNTS_PATH_FOR_TEST
    are set BUT no BATS_VERSION/PYTEST_CURRENT_TEST is in the environment,
    the test-mode override MUST be IGNORED (footgun guard).
    """
    monkeypatch.setenv("LOA_OVERLAY_TEST_MODE", "1")
    monkeypatch.setenv("LOA_OVERLAY_PROC_MOUNTS_PATH_FOR_TEST", "/tmp/whatever")
    # Strip both runner markers
    monkeypatch.delenv("BATS_VERSION", raising=False)
    monkeypatch.delenv("PYTEST_CURRENT_TEST", raising=False)
    result = hook._resolve_test_proc_mounts_path()
    assert result is None, "expected test-mode override to be IGNORED without runner marker"


def test_test_mode_third_leg_gate_accepts_with_runner_marker(monkeypatch):
    """CYP-F3 positive control: with all three legs (TEST_MODE + PATH +
    runner marker), the override is honored.
    """
    monkeypatch.setenv("LOA_OVERLAY_TEST_MODE", "1")
    monkeypatch.setenv("LOA_OVERLAY_PROC_MOUNTS_PATH_FOR_TEST", "/tmp/whatever")
    # PYTEST_CURRENT_TEST is automatically set by pytest, but ensure presence
    monkeypatch.setenv("PYTEST_CURRENT_TEST", "fake-test-marker")
    result = hook._resolve_test_proc_mounts_path()
    assert result == "/tmp/whatever"


def test_lockfile_holder_write_via_fd_uses_held_lock(tmp_path):
    """CYP-F6: writing the holder-pid through the held flock fd avoids
    the symlink-replace window. Verify the write succeeds via the helper
    and the content is correct (functional smoke test).
    """
    lockpath = tmp_path / "x.lock"
    handle = hook._acquire_lock(lockpath, exclusive=True, timeout_ms=1000)
    assert handle is not None
    try:
        hook._write_lockfile_holder_via_fd(handle, pid=98765)
        # Re-read via the public read helper
        assert hook._read_lockfile_holder_pid(lockpath) == 98765
    finally:
        hook._release_lock(handle)


def test_lockfile_holder_legacy_writer_uses_o_nofollow(tmp_path):
    """CYP-F6: the legacy `_write_lockfile_holder` now uses O_NOFOLLOW. If
    the lockfile path is a symlink, the write MUST fail rather than
    redirecting to the symlink target.
    """
    decoy = tmp_path / "decoy"
    decoy.write_text("decoy content unchanged")
    lockpath = tmp_path / "lock-as-symlink"
    os.symlink(str(decoy), str(lockpath))
    with pytest.raises(OSError):
        hook._write_lockfile_holder(lockpath, pid=12345)
    # Decoy file is untouched
    assert decoy.read_text() == "decoy content unchanged"


def test_degraded_state_clears_on_healthy_recovery(tmp_path, monkeypatch):
    """When the hook later succeeds in healthy mode, overlay-state.json
    transitions back from `degraded` to `healthy`.
    """
    schema_src = _REPO_ROOT / ".claude/data/trajectory-schemas/model-aliases-extra.schema.json"
    paths = _build_paths(tmp_path, _sample_sot(), {}, schema_src)

    # Manually seed degraded state
    paths.state.parent.mkdir(parents=True, exist_ok=True)
    paths.state.write_text(json.dumps({
        "schema_version": 1,
        "degraded_since": "2026-01-01T00:00:00Z",
        "cache_sha256": "x" * 64,
        "reason": "lock-timeout-shared",
        "last_updated": "2026-01-01T00:00:00Z",
        "state": "degraded",
    }))

    # Run normally; cache miss → cold regen succeeds → state transitions
    assert hook.run_hook(paths) == hook.EXIT_OK
    state = json.loads(paths.state.read_text())
    assert state["state"] == "healthy"
    assert state["degraded_since"] is None
