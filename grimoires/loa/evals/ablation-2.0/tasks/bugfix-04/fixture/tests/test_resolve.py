import pytest

from runopts import DEFAULTS, OptionError, resolve


def test_defaults():
    assert resolve([], {}, {}) == DEFAULTS


def test_cli_beats_env_and_config():
    got = resolve(["--retries", "7", "--timeout", "2.5"], {"RUNTOOL_RETRIES": "2"}, {"retries": 5, "timeout": 9})
    assert got["retries"] == 7
    assert got["timeout"] == 2.5


def test_env_beats_config():
    got = resolve([], {"RUNTOOL_TIMEOUT": "12", "RUNTOOL_PROFILE": "ci"}, {"timeout": 9, "profile": "dev"})
    assert got["timeout"] == 12.0
    assert got["profile"] == "ci"


def test_config_beats_default():
    assert resolve([], {}, {"retries": 5})["retries"] == 5


def test_verbose_counts():
    assert resolve(["-vv"], {}, {})["verbose"] == 2


def test_bad_values():
    with pytest.raises(OptionError):
        resolve([], {"RUNTOOL_COLOR": "maybe"}, {})
    with pytest.raises(OptionError):
        resolve([], {}, {"colour": True})
    with pytest.raises(OptionError):
        resolve(["--retries", "-1"], {}, {})
