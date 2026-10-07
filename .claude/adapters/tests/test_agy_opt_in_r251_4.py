"""cycle-127 sprint-251 audit round r251-4 — the opt-in read's trust anchor and its one strict rule.

S2 (audit n6): the opt-in is read from the project cheval belongs to, never from an arbitrary cwd ancestor — a planted
`/tmp/.loa.config.yaml` must not opt a host in — and a config the current user does not own, or that others can write, is
refused (read as off, one WARN).
S3 (audit n5, n17): one strict rule across the three readers — the EXACT tag `tag:yaml.org,2002:bool` (never a suffix
match: `!<x:bool> true` is off), and a YAML alias or a merge key on the path reads as off.
"""

from __future__ import annotations

import logging
import os
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import loa_cheval.config.loader as loader
from loa_cheval.config.loader import agy_opt_in_enabled

_ADAPTERS = Path(__file__).resolve().parent.parent
_ON = "hounfour:\n  headless:\n    agy_opt_in: true\n"
_OFF = "hounfour:\n  headless:\n    mode: prefer-api\n"


@pytest.fixture(autouse=True)
def _fresh_warn_flags(monkeypatch):
    monkeypatch.setattr(loader, "_AGY_TYPE_WARNED", False, raising=False)
    monkeypatch.setattr(loader, "_AGY_TRUST_WARNED", False, raising=False)


def _cfg(root: Path, body: str, mode: int = 0o644) -> Path:
    root.mkdir(parents=True, exist_ok=True)
    p = root / ".loa.config.yaml"
    p.write_text(body)
    p.chmod(mode)
    return p


def _this_cheval_project(root: Path, body: str) -> Path:
    """A project whose `.claude/adapters` IS this cheval (the submodule mount's shape: a symlink into the framework)."""
    (root / ".claude").mkdir(parents=True)
    (root / ".claude" / "adapters").symlink_to(_ADAPTERS, target_is_directory=True)
    _cfg(root, body)
    return root


# --- S2: the trust anchor --------------------------------------------------------------------------------------------

def test_s2_a_planted_cwd_ancestor_config_never_opts_in(tmp_path, monkeypatch):
    """The verifier's probe: `$T/parent/.loa.config.yaml` opts in, cwd `$T/parent/child/deep` — cheval's own project
    (the install root) does not. The planted file is not this cheval's project: off."""
    install = tmp_path / "install"
    _cfg(install, _OFF)
    monkeypatch.setattr(loader, "_install_root", lambda: str(install))
    _cfg(tmp_path / "parent", _ON)
    deep = tmp_path / "parent" / "child" / "deep"
    deep.mkdir(parents=True)
    monkeypatch.chdir(deep)
    assert agy_opt_in_enabled() is False


def test_s2_a_planted_ancestor_with_a_bare_claude_dir_is_still_not_this_cheval(tmp_path, monkeypatch):
    install = tmp_path / "install"
    _cfg(install, _OFF)
    monkeypatch.setattr(loader, "_install_root", lambda: str(install))
    planted = tmp_path / "planted"
    (planted / ".claude" / "adapters").mkdir(parents=True)   # a look-alike tree, not this cheval
    _cfg(planted, _ON)
    monkeypatch.chdir(planted)
    assert agy_opt_in_enabled() is False


def test_s2_the_install_root_config_is_honoured_from_any_cwd(tmp_path, monkeypatch):
    install = tmp_path / "install"
    _cfg(install, _ON)
    monkeypatch.setattr(loader, "_install_root", lambda: str(install))
    elsewhere = tmp_path / "elsewhere"
    elsewhere.mkdir()
    monkeypatch.chdir(elsewhere)
    assert agy_opt_in_enabled() is True


def test_s2_a_cwd_project_whose_adapters_are_this_cheval_is_honoured(tmp_path, monkeypatch):
    """Submodule mount: `<project>/.claude/adapters` symlinks into the framework — the project is this cheval's."""
    install = tmp_path / "install"
    _cfg(install, _OFF)
    monkeypatch.setattr(loader, "_install_root", lambda: str(install))
    proj = _this_cheval_project(tmp_path / "proj", _ON)
    (proj / "sub").mkdir()
    monkeypatch.chdir(proj / "sub")
    assert agy_opt_in_enabled() is True


def test_s2_the_default_install_root_is_the_tree_holding_these_adapters():
    root = Path(loader._install_root())
    assert (root / ".claude" / "adapters" / "loa_cheval" / "config" / "loader.py").is_file(), root


def test_s2_a_world_writable_config_reads_off_with_one_warn(tmp_path, monkeypatch, caplog):
    _cfg(tmp_path, _ON, 0o666)
    with caplog.at_level(logging.WARNING):
        for _ in range(3):
            assert agy_opt_in_enabled(str(tmp_path)) is False
    warns = [r.getMessage() for r in caplog.records if "agy_opt_in" in r.getMessage()]
    assert len(warns) == 1, warns
    assert "world-writable" in warns[0] and str(tmp_path / ".loa.config.yaml") in warns[0], warns[0]


def test_s2_a_config_owned_by_another_user_reads_off_with_one_warn(tmp_path, monkeypatch, caplog):
    _cfg(tmp_path, _ON)
    real = os.geteuid()
    monkeypatch.setattr(loader.os, "geteuid", lambda: real + 1)
    with caplog.at_level(logging.WARNING):
        assert agy_opt_in_enabled(str(tmp_path)) is False
    warns = [r.getMessage() for r in caplog.records if "agy_opt_in" in r.getMessage()]
    assert len(warns) == 1 and "not owned by the current user" in warns[0], warns


def test_s2_a_group_writable_config_of_a_shared_group_reads_off(tmp_path, monkeypatch, caplog):
    _cfg(tmp_path, _ON, 0o664)
    real = os.getegid()
    monkeypatch.setattr(loader.os, "getegid", lambda: real + 1)   # the file's group is not this user's own group
    with caplog.at_level(logging.WARNING):
        assert agy_opt_in_enabled(str(tmp_path)) is False
    assert any("group-writable" in r.getMessage() for r in caplog.records), [r.getMessage() for r in caplog.records]


def test_s2_a_group_writable_config_of_the_users_private_group_is_honoured(tmp_path, monkeypatch):
    """User-private groups (umask 002, the Debian default): the group is the owner's own — no one else can write."""
    _cfg(tmp_path, _ON, 0o664)
    monkeypatch.setattr(loader, "_group_is_private", lambda gid: True)
    assert agy_opt_in_enabled(str(tmp_path)) is True


def test_s2_an_owned_0644_config_is_honoured(tmp_path):
    _cfg(tmp_path, _ON, 0o644)
    assert agy_opt_in_enabled(str(tmp_path)) is True


# --- S3: one strict rule — the exact tag; aliases and merge keys read off -------------------------------------------

@pytest.mark.parametrize("label,body,want", [
    ("plain true", _ON, True),
    ("!!bool true", "hounfour:\n  headless:\n    agy_opt_in: !!bool true\n", True),
    ("full tag", "hounfour:\n  headless:\n    agy_opt_in: !<tag:yaml.org,2002:bool> true\n", True),
    ("anchored definition", "hounfour:\n  headless:\n    agy_opt_in: &a true\n", True),
    ("foreign tag ending :bool", "hounfour:\n  headless:\n    agy_opt_in: !<x:bool> true\n", False),
    ("local tag !bool", "hounfour:\n  headless:\n    agy_opt_in: !bool true\n", False),
    ("alias", "x: &t true\nhounfour:\n  headless:\n    agy_opt_in: *t\n", False),
    ("merge key", "b: &b\n  agy_opt_in: true\nhounfour:\n  headless:\n    <<: *b\n", False),
    ("aliased headless", "h: &h\n  agy_opt_in: true\nhounfour:\n  headless: *h\n", False),
    ("aliased hounfour", "h: &h\n  headless:\n    agy_opt_in: true\nhounfour: *h\n", False),
])
@pytest.mark.parametrize("reader", ["pyyaml", "yq"])
def test_s3_one_strict_rule(tmp_path, monkeypatch, label, body, want, reader):
    if reader == "yq":
        import shutil
        if not shutil.which("yq"):
            pytest.skip("yq not installed")
        monkeypatch.setattr(loader, "_HAS_YAML", False, raising=False)
    _cfg(tmp_path, body)
    assert agy_opt_in_enabled(str(tmp_path)) is want, (label, reader)


def test_s3_a_foreign_bool_tag_warns_as_not_a_yaml_boolean(tmp_path, caplog):
    _cfg(tmp_path, "hounfour:\n  headless:\n    agy_opt_in: !<x:bool> true\n")
    with caplog.at_level(logging.WARNING):
        assert agy_opt_in_enabled(str(tmp_path)) is False
    warns = [r.getMessage() for r in caplog.records if "agy_opt_in" in r.getMessage()]
    assert len(warns) == 1 and "not a YAML boolean" in warns[0], warns


def test_s3_an_alias_warns_once(tmp_path, caplog):
    _cfg(tmp_path, "x: &t true\nhounfour:\n  headless:\n    agy_opt_in: *t\n")
    with caplog.at_level(logging.WARNING):
        assert agy_opt_in_enabled(str(tmp_path)) is False
    warns = [r.getMessage() for r in caplog.records if "agy_opt_in" in r.getMessage()]
    assert len(warns) == 1 and "alias" in warns[0], warns


# --- S5 (audit run 2 n1, n8): a catalog read failure is said once and never cached --------------------------------

def test_s5_a_failed_catalog_read_is_not_cached_and_warns_once(monkeypatch, caplog):
    monkeypatch.setattr(loader, "_CATALOG_MAPS_WARNED", False, raising=False)
    loader._CATALOG_PROVIDERS_CACHE.clear()
    real = loader._load_yaml

    def _boom(path):
        raise OSError("catalog unreadable")
    monkeypatch.setattr(loader, "_load_yaml", _boom)
    with caplog.at_level(logging.WARNING):
        # the name rule is the fallback: a gemini* name is still google, a catalog-only Google alias is unknown
        assert loader.catalog_provider_of("gemini-2.5-pro") == "google"
        assert loader.catalog_provider_of("deep-research-pro") == ""
        assert loader.catalog_provider_of("researcher") == ""
    warns = [r.getMessage() for r in caplog.records if "catalog" in r.getMessage() and "name rule" in r.getMessage()]
    assert len(warns) == 1, [r.getMessage() for r in caplog.records]
    assert "catalog unreadable" in warns[0], warns[0]
    assert not loader._CATALOG_PROVIDERS_CACHE, "a partial result was cached"
    monkeypatch.setattr(loader, "_load_yaml", real)
    assert loader.catalog_provider_of("deep-research-pro") == "google"   # the next read recovers
    assert loader._CATALOG_PROVIDERS_CACHE
