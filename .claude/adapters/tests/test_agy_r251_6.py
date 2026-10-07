"""cycle-127 sprint-251 fix round r251-6 — the Bridgebuilder pass on PR #1275 (cheval's side).

V1 (BB #1): a group-writable opt-in config is trusted only for the owner's USER-PRIVATE group — the file's gid is the owner's
    primary gid, the group is named for the owner, no other account is a member or has it as its primary group, and no POSIX
    ACL turns the group bits into a mask over other accounts' grants. Ubuntu's umask 002 makes every checkout 0664; a shared
    primary group (`users`) still fails. World-writable and a foreign owner stay refused.
V2 (BB #17): no `os.geteuid` (non-POSIX) → the owner half is skipped, the mode half still applies.
V3 (BB #2): the bytes the opt-in is read from and the stat the trust rule judges come from ONE open file.
V4 (BB #3): the agy routing catalog overlay is anchored to the opt-in's root (`_opt_in_root`), never a cwd ancestor.
V5 (BB #5): an alias / non-mapping on an ANCESTOR of the key is said once, not read silently as absent.
V6 (BB #6): the no-PyYAML fallback checks the yq flavour, as the bash lib does.
V7 (BB #10): the "both rungs set" effort WARN is for CLI entries only (an HTTP entry's extra is inert).
V8 (BB #4) / V9 (BB #16): `_plan_around_agy` keeps every ResolvedChain field, never returns an empty chain, and returns an
    all-agy chain unchanged.
No model is called.
"""

from __future__ import annotations

import logging
import os
import shutil
import subprocess
import sys
import types
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import loa_cheval.config.loader as loader  # noqa: E402
from loa_cheval.config.loader import agy_opt_in_enabled  # noqa: E402

_ON = "hounfour:\n  headless:\n    agy_opt_in: true\n"
_OFF = "hounfour:\n  headless:\n    mode: prefer-api\n"
_ME = "loa-me"


@pytest.fixture(autouse=True)
def _fresh_warn_flags(monkeypatch):
    for flag in ("_AGY_TYPE_WARNED", "_AGY_TRUST_WARNED", "_AGY_READ_WARNED"):
        monkeypatch.setattr(loader, flag, False, raising=False)


def _cfg(root: Path, body: str, mode: int = 0o644) -> Path:
    root.mkdir(parents=True, exist_ok=True)
    p = root / ".loa.config.yaml"
    p.write_text(body)
    p.chmod(mode)
    return p


def _accounts(monkeypatch, *, name=_ME, members=(), others_primary=False, known=True, primary_gid=None):
    """The account database as the trust rule sees it: this user `loa-me` (primary gid = the process gid unless given) and
    the file's group (`name`, listed `members`); `others_primary` adds an account whose primary group is the same gid."""
    import grp
    import pwd
    uid, gid = os.getuid(), os.getgid()
    me = SimpleNamespace(pw_name=_ME, pw_uid=uid, pw_gid=gid if primary_gid is None else primary_gid)
    accounts = [me] + ([SimpleNamespace(pw_name="staffer", pw_uid=uid + 1, pw_gid=gid)] if others_primary else [])

    def getgrgid(g):
        if not known:
            raise KeyError(g)
        return SimpleNamespace(gr_name=name, gr_mem=list(members), gr_gid=g)
    monkeypatch.setattr(pwd, "getpwuid", lambda u: me if u == uid else (_ for _ in ()).throw(KeyError(u)))
    monkeypatch.setattr(pwd, "getpwall", lambda: list(accounts))
    monkeypatch.setattr(grp, "getgrgid", getgrgid)


def _warns(caplog, needle="agy_opt_in"):
    return [r.getMessage() for r in caplog.records if needle in r.getMessage()]


# --- V1: the user-private-group exception, correctly ---------------------------------------------------------------

@pytest.mark.parametrize("mode", [0o664, 0o660, 0o620])
def test_v1_a_group_writable_config_of_a_user_private_group_opts_in_silently(tmp_path, monkeypatch, caplog, mode):
    _accounts(monkeypatch)
    _cfg(tmp_path, _ON, mode)
    with caplog.at_level(logging.WARNING):
        assert agy_opt_in_enabled(str(tmp_path)) is True
    assert not _warns(caplog), _warns(caplog)


def test_v1_the_owner_listed_as_its_own_member_is_still_private(tmp_path, monkeypatch):
    _accounts(monkeypatch, members=[_ME])
    _cfg(tmp_path, _ON, 0o664)
    assert agy_opt_in_enabled(str(tmp_path)) is True


@pytest.mark.parametrize("label,kw,needle", [
    ("another member", {"members": ["bob"]}, "'loa-me' has other members (bob)"),
    ("named differently (a shared `users`)", {"name": "users"}, "'users' is not named for the owner 'loa-me'"),
    ("another account's primary group", {"others_primary": True}, "the primary group of another account (staffer)"),
    ("not the owner's primary group", {"primary_gid": -7}, "is not the owner's primary group"),
    ("unknown to the account database", {"known": False}, "could not be looked up"),
])
def test_v1_a_group_writable_config_of_a_shared_group_reads_off_with_one_warn_naming_the_group(
        tmp_path, monkeypatch, caplog, label, kw, needle):
    _accounts(monkeypatch, **kw)
    _cfg(tmp_path, _ON, 0o664)
    with caplog.at_level(logging.WARNING):
        for _ in range(3):
            assert agy_opt_in_enabled(str(tmp_path)) is False, label
    warns = _warns(caplog)
    assert len(warns) == 1, warns
    assert "group-writable (mode 0664)" in warns[0] and needle in warns[0], (label, warns[0])


def test_v1_world_writable_stays_refused_even_for_a_private_group(tmp_path, monkeypatch, caplog):
    _accounts(monkeypatch)
    _cfg(tmp_path, _ON, 0o666)
    with caplog.at_level(logging.WARNING):
        assert agy_opt_in_enabled(str(tmp_path)) is False
    assert "world-writable (mode 0666)" in _warns(caplog)[0]


def test_v1_a_foreign_owner_stays_refused_even_for_a_private_group(tmp_path, monkeypatch, caplog):
    _accounts(monkeypatch)
    _cfg(tmp_path, _ON, 0o644)
    real = os.geteuid()
    monkeypatch.setattr(loader.os, "geteuid", lambda: real + 1)
    with caplog.at_level(logging.WARNING):
        assert agy_opt_in_enabled(str(tmp_path)) is False
    assert "not owned by the current user" in _warns(caplog)[0]


@pytest.mark.skipif(not shutil.which("setfacl"), reason="setfacl not installed")
def test_v1_a_posix_acl_on_a_private_group_config_is_refused(tmp_path, monkeypatch, caplog):
    """With an access ACL the group bits are the MASK over named users' grants: `u:nobody:rw` makes the file writable by
    another account while its mode still reads 0660 — never trusted (the headless workspace's rule, _acl_extended)."""
    _accounts(monkeypatch)
    p = _cfg(tmp_path, _ON, 0o600)
    r = subprocess.run(["setfacl", "-m", "u:nobody:rw", str(p)], capture_output=True, text=True)
    if r.returncode != 0:
        pytest.skip(f"setfacl refused here: {r.stderr.strip()}")
    with caplog.at_level(logging.WARNING):
        assert agy_opt_in_enabled(str(tmp_path)) is False
    assert "extended ACL" in _warns(caplog)[0], _warns(caplog)


def test_v1_the_reason_names_the_mode_and_the_group(tmp_path, monkeypatch):
    _accounts(monkeypatch, name="users")
    p = _cfg(tmp_path, _ON, 0o664)
    assert loader._config_untrusted_reason(p) == ("group-writable (mode 0664) and its group 'users' is not named for the "
                                                  "owner 'loa-me' (not a user-private group)")
    _accounts(monkeypatch)
    assert loader._config_untrusted_reason(p) is None
    p.chmod(0o646)
    assert loader._config_untrusted_reason(p) == "world-writable (mode 0646)"


def test_v1_no_account_enumeration_before_the_cheap_checks_fail(tmp_path, monkeypatch):
    """getpwall() can walk a whole directory (sssd / LDAP): it is consulted only once name, primary gid and members pass."""
    import pwd
    _accounts(monkeypatch, name="users")
    monkeypatch.setattr(pwd, "getpwall", lambda: (_ for _ in ()).throw(AssertionError("enumerated")))
    _cfg(tmp_path, _ON, 0o664)
    assert agy_opt_in_enabled(str(tmp_path)) is False


# --- V2: no geteuid --------------------------------------------------------------------------------------------------

def test_v2_without_geteuid_the_owner_half_is_skipped_and_the_mode_half_applies(tmp_path, monkeypatch, caplog):
    monkeypatch.delattr(loader.os, "geteuid", raising=False)
    _accounts(monkeypatch, name="users")
    p = _cfg(tmp_path, _ON, 0o644)
    assert loader._config_untrusted_reason(p) is None
    assert agy_opt_in_enabled(str(tmp_path)) is True
    p.chmod(0o666)
    with caplog.at_level(logging.WARNING):
        assert agy_opt_in_enabled(str(tmp_path)) is False
    assert "world-writable" in _warns(caplog)[0]


# --- V3: one open file ------------------------------------------------------------------------------------------------

def test_v3_a_config_swapped_after_the_read_is_judged_on_the_file_that_was_read(tmp_path, monkeypatch):
    """The read sees a world-writable `true`; before the trust check runs, the path is replaced by an owned 0644 file. The
    decision is the read file's (off) — the old path-based stat judged the replacement (on)."""
    p = _cfg(tmp_path, _ON, 0o666)
    real = loader._agy_opt_in_node_of_bytes

    def _read_then_swap(data):
        result = real(data)
        repl = tmp_path / "replacement.yaml"
        repl.write_text(_ON)
        repl.chmod(0o644)
        os.replace(repl, p)
        return result
    monkeypatch.setattr(loader, "_agy_opt_in_node_of_bytes", _read_then_swap)
    assert agy_opt_in_enabled(str(tmp_path)) is False
    assert (p.stat().st_mode & 0o777) == 0o644   # (the swap happened)


def test_v3_the_config_is_opened_once(tmp_path, monkeypatch):
    _cfg(tmp_path, _ON)
    opened = []
    real_open = open

    def _counting_open(file, *a, **kw):
        if str(file).endswith(".loa.config.yaml"):
            opened.append(str(file))
        return real_open(file, *a, **kw)
    monkeypatch.setattr("builtins.open", _counting_open)
    assert agy_opt_in_enabled(str(tmp_path)) is True
    assert len(opened) == 1, opened


# --- V4: the catalog overlay's root -----------------------------------------------------------------------------------

def test_v4_a_planted_cwd_ancestor_alias_never_changes_routes_to_agy(tmp_path, monkeypatch):
    install = tmp_path / "install"
    _cfg(install, _OFF)
    monkeypatch.setattr(loader, "_install_root", lambda: str(install))
    planted = tmp_path / "planted"
    _cfg(planted, "hounfour:\n  aliases:\n    zz-planted: \"google:gemini-2.5-pro\"\n")
    (planted / "deep").mkdir()
    monkeypatch.chdir(planted / "deep")
    loader._CATALOG_PROVIDERS_CACHE.clear()
    try:
        assert loader.catalog_provider_of("zz-planted") == ""
        assert loader.routes_to_agy("zz-planted", "cli-only") is False
        # the install root's own alias IS honoured
        _cfg(install, "hounfour:\n  aliases:\n    zz-mine: \"google:gemini-2.5-pro\"\n")
        loader._CATALOG_PROVIDERS_CACHE.clear()
        assert loader.routes_to_agy("zz-mine", "cli-only") is True
    finally:
        loader._CATALOG_PROVIDERS_CACHE.clear()


# --- V5: an alias / non-mapping ancestor ------------------------------------------------------------------------------

@pytest.mark.parametrize("label,body,path,what", [
    ("aliased headless", "h: &h\n  agy_opt_in: true\nhounfour:\n  headless: *h\n", "hounfour.headless", "a YAML alias"),
    ("aliased hounfour", "h: &h\n  headless:\n    agy_opt_in: true\nhounfour: *h\n", "hounfour", "a YAML alias"),
    ("a sequence headless", "hounfour:\n  headless: [1]\n", "hounfour.headless", "not a mapping (seq)"),
    ("a string hounfour", "hounfour: foo\n", "hounfour", "not a mapping (str)"),
])
@pytest.mark.parametrize("reader", ["pyyaml", "yq"])
def test_v5_an_alias_or_non_mapping_ancestor_reads_off_with_one_warn(tmp_path, monkeypatch, caplog, label, body, path,
                                                                     what, reader):
    if reader == "yq":
        if not _mikefarah_yq():
            pytest.skip("mikefarah yq not installed")
        monkeypatch.setattr(loader, "_HAS_YAML", False, raising=False)
    _cfg(tmp_path, body)
    with caplog.at_level(logging.WARNING):
        for _ in range(2):
            assert agy_opt_in_enabled(str(tmp_path)) is False, label
    warns = _warns(caplog)
    assert len(warns) == 1, (label, warns)
    assert warns[0].startswith(f"{path} is {what} — hounfour.headless.agy_opt_in cannot be read"), (label, warns[0])
    assert "write the mapping inline" in warns[0]


@pytest.mark.parametrize("body", ["hounfour: {}\n", "hounfour:\n  headless:\n", "x: 1\n", "hounfour:\n"])
def test_v5_an_absent_or_null_ancestor_is_silent(tmp_path, caplog, body):
    _cfg(tmp_path, body)
    with caplog.at_level(logging.WARNING):
        assert agy_opt_in_enabled(str(tmp_path)) is False
    assert not _warns(caplog), _warns(caplog)


# --- V6: the no-PyYAML fallback's yq flavour --------------------------------------------------------------------------

def _mikefarah_yq() -> bool:
    if not shutil.which("yq"):
        return False
    r = subprocess.run(["yq", "--version"], capture_output=True, text=True)
    return "mikefarah" in (r.stdout + r.stderr)


def test_v6_a_python_yq_never_runs_the_go_yq_program_and_the_cause_is_said_once(tmp_path, monkeypatch, caplog):
    shim = tmp_path / "bin"
    shim.mkdir()
    marker = tmp_path / "go-yq-program-ran"
    (shim / "yq").write_text(f"#!/bin/sh\n[ \"$1\" = --version ] && {{ echo 'yq 3.4.3'; exit 0; }}\ntouch {marker}\necho true\n")
    (shim / "yq").chmod(0o755)
    monkeypatch.setenv("PATH", f"{shim}:{os.environ.get('PATH', '')}")
    monkeypatch.setattr(loader, "_HAS_YAML", False, raising=False)
    _cfg(tmp_path / "p", _ON)
    with caplog.at_level(logging.WARNING):
        for _ in range(2):
            assert agy_opt_in_enabled(str(tmp_path / "p")) is False
    assert not marker.exists(), "the go-yq program ran under a python yq"
    warns = _warns(caplog)
    assert len(warns) == 1 and "yq 3.4.3" in warns[0] and "mikefarah" in warns[0], warns


def test_v6_no_yq_at_all_is_said_once_too(tmp_path, monkeypatch, caplog):
    monkeypatch.setenv("PATH", str(tmp_path / "empty"))
    monkeypatch.setattr(loader, "_HAS_YAML", False, raising=False)
    _cfg(tmp_path / "p", _ON)
    with caplog.at_level(logging.WARNING):
        assert agy_opt_in_enabled(str(tmp_path / "p")) is False
        assert agy_opt_in_enabled(str(tmp_path / "p")) is False
    warns = _warns(caplog)
    assert len(warns) == 1 and "PyYAML" in warns[0], warns


@pytest.mark.skipif(not _mikefarah_yq(), reason="mikefarah yq not installed")
def test_v6_mikefarah_yq_still_reads_the_opt_in(tmp_path, monkeypatch):
    monkeypatch.setattr(loader, "_HAS_YAML", False, raising=False)
    _cfg(tmp_path, _ON)
    assert agy_opt_in_enabled(str(tmp_path)) is True


# --- V7: the "both rungs" WARN is for CLI entries -------------------------------------------------------------------

def test_v7_both_rungs_warn_only_for_a_cli_entry(caplog, monkeypatch):
    import cheval  # type: ignore[import-not-found]
    monkeypatch.setattr(cheval, "_EFFORT_WARNED", set())
    ns = types.SimpleNamespace(effort=None)
    http = {"auth_type": "http_api", "extra": {"effort": "low"}, "params": {"default_effort": "high"}}
    cli = {"kind": "cli", "extra": {"effort": "low"}, "params": {"default_effort": "high"}}
    with caplog.at_level(logging.WARNING):
        assert cheval.resolve_effort(ns, http, model_key="openai:gpt-5.5") == ("high", "catalog")
    assert not [r for r in caplog.records if "sets both" in r.getMessage()], [r.getMessage() for r in caplog.records]
    with caplog.at_level(logging.WARNING):
        assert cheval.resolve_effort(ns, cli, model_key="anthropic:claude-headless") == ("high", "catalog")
    assert len([r for r in caplog.records if "sets both" in r.getMessage()]) == 1


# --- V8 / V9: _plan_around_agy ----------------------------------------------------------------------------------------

def _entry(provider, model_id, kind="http"):
    from loa_cheval.routing.types import ResolvedEntry
    return ResolvedEntry(provider=provider, model_id=model_id, adapter_kind=kind, capabilities=frozenset({"chat"}),
                         auth_type="headless" if kind == "cli" else "http_api")


def _chain(entries, mode="prefer-api"):
    from loa_cheval.routing.types import ResolvedChain
    return ResolvedChain(primary_alias=entries[0].canonical, entries=tuple(entries), headless_mode=mode,
                         headless_mode_source="default")


@pytest.fixture
def _gate_off(monkeypatch):
    import cheval  # type: ignore[import-not-found]
    monkeypatch.setattr(cheval, "_AGY_NOT_PLANNED_WARNED", True, raising=False)
    with patch("loa_cheval.config.loader.agy_opt_in_enabled", lambda *a, **k: False), \
         patch("loa_cheval.config.loader.warn_agy_available_once", lambda *a, **k: None):
        yield cheval


_H = {"providers": {"google": {"type": "google"}}}


def test_v9_an_all_agy_chain_is_returned_unchanged(_gate_off):
    for chain in (_chain([_entry("google", "gemini-headless", "cli")], "cli-only"),
                  _chain([_entry("google", "gemini-headless", "cli"), _entry("google", "gemini-headless", "cli")], "prefer-cli")):
        out, skipped = _gate_off._plan_around_agy(chain, _H)
        assert out is chain and skipped == []


@pytest.mark.parametrize("models", [
    [("gemini-2.5-pro", "http"), ("gemini-headless", "cli")],
    [("gemini-headless", "cli"), ("gemini-2.5-pro", "http")],
    [("gemini-headless", "cli"), ("gemini-2.5-pro", "http"), ("gemini-headless", "cli")],
])
def test_v9_whenever_a_hop_is_skipped_at_least_one_is_kept(_gate_off, models):
    chain = _chain([_entry("google", m, k) for m, k in models])
    out, skipped = _gate_off._plan_around_agy(chain, _H)
    assert skipped and len(out.entries) >= 1
    assert [e.model_id for e in out.entries] == ["gemini-2.5-pro"]
    assert len(skipped) + len(out.entries) == len(chain.entries)


def test_v8_the_planned_around_chain_keeps_every_other_field(_gate_off):
    import dataclasses
    chain = _chain([_entry("google", "gemini-2.5-pro"), _entry("google", "gemini-headless", "cli")])
    out, _ = _gate_off._plan_around_agy(chain, _H)
    for f in dataclasses.fields(chain):
        if f.name != "entries":
            assert getattr(out, f.name) == getattr(chain, f.name), f.name
    assert type(out.entries) is type(chain.entries)
    src = Path(_gate_off.__file__).read_text()
    body = src[src.index("def _plan_around_agy"):src.index("def _get_adapter_for_entry")]
    assert "_dc_replace(chain, entries=" in body and "_RC(" not in body


def test_v9_a_google_model_under_cli_only_with_no_fallback_refuses_without_an_index_error(capsys, monkeypatch):
    """The claimed crash path: a Google voice under cli-only whose chain has no CLI hop. The resolver refuses before the
    planner runs (NO_ELIGIBLE_ADAPTER); nothing reaches `_chain.entries[0]` on an empty chain."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import test_agy_chain_walk_opt_in as walk
    monkeypatch.setenv("LOA_HEADLESS_MODE", "cli-only")
    cfg = walk._cfg()
    del cfg["providers"]["google"]["models"]["gemini-2.5-pro"]["fallback_chain"]
    monkeypatch.setattr(walk, "_cfg", lambda: cfg)
    import cheval  # type: ignore[import-not-found]
    monkeypatch.setattr(cheval, "_load_persona", lambda *_a, **_kw: None)
    monkeypatch.setattr(cheval, "_load_persona_parts", lambda *_a, **_kw: (None, None))
    monkeypatch.setattr(cheval, "_check_feature_flags", lambda *_a, **_kw: None)
    rc, _payload, seen = walk._invoke(opt_in=False)
    err = capsys.readouterr().err
    assert "IndexError" not in err and "Traceback" not in err, err
    assert rc == cheval.EXIT_CODES["NO_ELIGIBLE_ADAPTER"], err
    assert seen == []
