import pytest

from runopts import DEFAULTS, OptionError, resolve


def test_no_color_flag_beats_env():
    assert resolve(["--no-color"], {"RUNTOOL_COLOR": "1"}, {})["color"] is False


def test_color_flag_beats_config_false():
    assert resolve(["--color"], {}, {"color": False})["color"] is True


def test_config_false_beats_default():
    assert resolve([], {}, {"color": False})["color"] is False


def test_env_false_beats_config_true():
    assert resolve([], {"RUNTOOL_COLOR": "off"}, {"color": True})["color"] is False


def test_zero_retries_on_each_layer():
    assert resolve(["--retries", "0"], {"RUNTOOL_RETRIES": "4"}, {"retries": 5})["retries"] == 0
    assert resolve([], {"RUNTOOL_RETRIES": "0"}, {"retries": 5})["retries"] == 0
    assert resolve([], {}, {"retries": 0})["retries"] == 0


def test_unmentioned_options_fall_through():
    got = resolve(["--retries", "1"], {"RUNTOOL_TIMEOUT": "4"}, {"profile": "dev"})
    assert got == {"color": True, "retries": 1, "timeout": 4.0, "profile": "dev", "verbose": 0}
    assert resolve([], {}, {}) == DEFAULTS


def test_empty_profile_in_config_is_kept():
    assert resolve([], {}, {"profile": ""})["profile"] == ""


def test_zero_timeout_is_rejected_not_replaced():
    with pytest.raises(OptionError):
        resolve(["--timeout", "0"], {}, {})
