import pytest

from kvconf import ConfigError, ParseError, loads

TEXT = """# settings
[server]
host = example.org
port = 8080   ; the default

[paths]
data = "/var/lib/app"  # quoted
empty = ""
"""


def test_loads_sections_and_values():
    config = loads(TEXT)
    assert config.sections() == ["server", "paths"]
    assert config.items("server") == [("host", "example.org"), ("port", "8080")]
    assert config.get("paths", "data") == "/var/lib/app"
    assert config.get("paths", "empty") == ""


def test_get_is_case_insensitive():
    config = loads(TEXT)
    assert config.get("SERVER", "Host") == "example.org"
    assert config.get("server", "missing", "x") == "x"
    assert config.get("nowhere", "host") is None


def test_inline_comment_needs_whitespace():
    config = loads("[a]\nurl = http://x/#top\nnote = a;b ;tail\n")
    assert config.get("a", "url") == "http://x/#top"
    assert config.get("a", "note") == "a;b"


def test_quoted_escapes():
    config = loads('[a]\nq = "say \\"hi\\"\\tthen\\nleave"\n')
    assert config.get("a", "q") == 'say "hi"\tthen\nleave'


@pytest.mark.parametrize("text,message", [
    ("key = 1\n", "line 1: key outside a section"),
    ("[a]\njunk\n", "line 2: expected key = value"),
    ("[a]\n = 1\n", "line 2: empty key"),
    ("[a\n", "line 1: bad section header"),
    ("[ ]\n", "line 1: empty section name"),
    ("[a]\nx = 1\n[A]\n", "line 3: duplicate section: A"),
    ("[a]\nx = 1\nX = 2\n", "line 3: duplicate key: X"),
    ('[a]\nx = "open\n', "line 2: unterminated quote"),
    ('[a]\nx = "v" w\n', "line 2: text after closing quote"),
])
def test_parse_errors(text, message):
    with pytest.raises(ParseError) as err:
        loads(text)
    assert str(err.value) == message
    assert isinstance(err.value, ConfigError)
