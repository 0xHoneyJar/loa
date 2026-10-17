import pytest

from kvconf import Config, ConfigError, dumps, load, loads, merge, save


def sample():
    config = Config()
    config.set("user", "name", "alice smith")
    config.set("user", "shell", "/bin/sh")
    config.set("paths", "home", " /home/alice")
    return config


def test_dumps_layout():
    assert dumps(sample()) == (
        "[user]\nname = alice smith\nshell = /bin/sh\n\n[paths]\nhome = \" /home/alice\"\n"
    )
    assert dumps(Config()) == ""


def test_empty_section_is_written():
    config = Config()
    config.add_section("blank")
    assert dumps(config) == "[blank]\n"
    assert loads(dumps(config)) == config


def test_round_trip_of_plain_values(tmp_path):
    config = sample()
    assert loads(dumps(config)) == config
    save(config, tmp_path / "s.ini")
    assert load(tmp_path / "s.ini") == config


def test_equality_is_ordered():
    a, b = Config(), Config()
    a.set("s", "x", "1"); a.set("s", "y", "2")
    b.set("s", "y", "2"); b.set("s", "x", "1")
    assert a != b


def test_set_replaces_same_spelling():
    config = sample()
    config.set("user", "name", "bob")
    assert config.items("user") == [("name", "bob"), ("shell", "/bin/sh")]


@pytest.mark.parametrize("section,key,value", [
    ("", "k", "v"), ("s", "", "v"), ("s", "a=b", "v"), ("s", "#k", "v"),
    ("s]", "k", "v"), ("s", " k", "v"), ("s", "k", 3),
])
def test_bad_names_and_values(section, key, value):
    with pytest.raises(ConfigError):
        Config().set(section, key, value)


def test_merge_layers_values():
    base = sample()
    overlay = Config()
    overlay.set("user", "shell", "/bin/zsh")
    overlay.set("extra", "on", "yes")
    merged = merge(base, overlay)
    assert merged.items("user") == [("name", "alice smith"), ("shell", "/bin/zsh")]
    assert merged.sections() == ["user", "paths", "extra"]
    assert base.get("user", "shell") == "/bin/sh"


def test_keys_lists_in_order():
    assert sample().keys("user") == ["name", "shell"]
    with pytest.raises(ConfigError):
        sample().keys("missing")
