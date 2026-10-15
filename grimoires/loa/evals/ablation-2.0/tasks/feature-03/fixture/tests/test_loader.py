import pytest

from confload import ConfigError, load, loads


def test_sections_and_default_section():
    data = loads("top = 1\n[db]\nhost = localhost\nport=5432\n")
    assert data == {"": {"top": "1"}, "db": {"host": "localhost", "port": "5432"}}


def test_comments_blank_lines_and_whitespace():
    data = loads("# comment\n; other\n\n  [ web ]  \n  name   =   site one  \n")
    assert data["web"] == {"name": "site one"}


def test_value_may_be_empty_or_contain_equals():
    assert loads("a =\nb = x=y\n")[""] == {"a": "", "b": "x=y"}


def test_repeated_keys_and_sections():
    data = loads("[s]\nk = 1\n[t]\nk = 2\n[s]\nk = 3\nj = 4\n")
    assert data["s"] == {"k": "3", "j": "4"} and data["t"] == {"k": "2"}


def test_parse_error_carries_line_number():
    with pytest.raises(ConfigError) as e:
        loads("[s]\nok = 1\nnot an assignment\n")
    assert e.value.line == 3 and str(e.value).startswith("line 3: ")


def test_load_reads_a_file(tmp_path):
    p = tmp_path / "app.conf"
    p.write_text("[s]\nk = v\n", encoding="utf-8")
    assert load(p)["s"] == {"k": "v"}
