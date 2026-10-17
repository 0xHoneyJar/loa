import pytest

from kvconf import Config, ParseError, dumps, load, loads, merge, save


def one(value, key="k", section="s"):
    config = Config()
    config.set(section, key, value)
    return config


def survives(value):
    config = one(value)
    assert loads(dumps(config)).get("s", "k") == value, value
    assert loads(dumps(config)) == config, value


def test_whitespace_quotes_and_comment_characters_survive():
    for value in ["trailing ", "  both  ", " ", "red # blue", "a ;b", "#first", ";first",
                  "x#y", '"quoted"', 'say "hi"', "", "caf\u00e9 "]:
        survives(value)


def test_backslashes_and_control_characters_survive():
    for value in ["C:\\new\\temp", "back\\\\slash", "line1\nC:\\temp\\n", "\t",
                  "tab\there\\t", "cr\r\nlf", "end\\", "\\\""]:
        survives(value)


def test_files_round_trip(tmp_path):
    config = Config()
    config.set("Paths", "Data", "C:\\new\\table ")
    config.set("Paths", "Note", "keep # this")
    config.set("Paths", "Lines", "a\nb\r\nc")
    save(config, tmp_path / "x.ini")
    assert load(tmp_path / "x.ini") == config
    save(load(tmp_path / "x.ini"), tmp_path / "y.ini")
    assert (tmp_path / "y.ini").read_text(encoding="utf-8") == (tmp_path / "x.ini").read_text(encoding="utf-8")


def test_plain_values_stay_bare():
    config = one("alice smith", key="name", section="user")
    config.set("user", "url", "http://x/a?b=c")
    assert dumps(config) == "[user]\nname = alice smith\nurl = http://x/a?b=c\n"


def test_spelling_of_names_survives():
    config = Config()
    config.set("User Prefs", "DisplayName", "Al")
    config.set("User Prefs", "theme", "dark")
    loaded = loads(dumps(config))
    assert loaded == config
    assert loaded.sections() == ["User Prefs"]
    assert loaded.keys("user prefs") == ["DisplayName", "theme"]


def test_set_matches_names_case_insensitively():
    config = loads("[user]\nDisplayName = Al\nshell = sh\n")
    config.set("USER", "displayname", "Bo")
    config.set("user", "SHELL", "zsh")
    config.set("User", "new", "1")
    assert config.sections() == ["user"]
    assert config.items("user") == [("DisplayName", "Bo"), ("shell", "zsh"), ("new", "1")]
    config.add_section("USER")
    assert config.sections() == ["user"]


def test_bad_escape_is_refused():
    with pytest.raises(ParseError) as err:
        loads('[s]\nok = "fine"\nk = "a\\qb"\n')
    assert str(err.value) == "line 3: bad escape: \\q"
    with pytest.raises(ParseError) as err:
        loads('[s]\nk = "\\x41"\n')
    assert str(err.value) == "line 2: bad escape: \\x"


def test_merge_matches_names_case_insensitively():
    base = loads("[User]\nName = a\nshell = sh\n")
    overlay = loads("[user]\nname = b\nEditor = vi\n\n[Extra]\nOn = yes\n")
    merged = merge(base, overlay)
    assert merged.sections() == ["User", "Extra"]
    assert merged.items("User") == [("Name", "b"), ("shell", "sh"), ("Editor", "vi")]
    assert merged.items("extra") == [("On", "yes")]
    assert base.items("User") == [("Name", "a"), ("shell", "sh")]
    assert overlay.items("user") == [("name", "b"), ("Editor", "vi")]


def test_merged_config_survives_a_round_trip(tmp_path):
    base = loads('[User]\nName = "a "\nPath = "C:\\\\new"\n')
    overlay = loads("[USER]\nNAME = b # inline\n")
    merged = merge(base, overlay)
    save(merged, tmp_path / "m.ini")
    again = load(tmp_path / "m.ini")
    assert again == merged
    assert again.get("user", "name") == "b"
    assert again.get("user", "path") == "C:\\new"


def test_round_trip_is_stable_for_many_values():
    config = Config()
    values = ["", " ", "x ", " x", "a # b", "a; b", "a\\nb", "a\nb", 'q"', "\\", "\\t\t"]
    for i, value in enumerate(values):
        config.set("Mixed Case", f"Key{i}", value)
    text = dumps(config)
    assert loads(text) == config
    assert dumps(loads(text)) == text


def test_merge_of_empty_configs():
    empty = Config()
    assert merge(empty, empty) == Config()
    config = one("v ", key="K", section="S")
    assert merge(empty, config) == config
    assert merge(config, empty) == config
