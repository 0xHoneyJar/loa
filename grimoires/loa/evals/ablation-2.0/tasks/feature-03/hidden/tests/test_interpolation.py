import pytest

from confload import ConfigError, load, loads
from confload import loader


def interp_error():
    return loader.InterpolationError

ENV = {"HOST": "db.internal", "PORT": "5432", "EMPTY": "", "SPACED": "  x ", "REF": "${HOST}", "U_1": "u"}


def val(text, env=ENV, key="k"):
    return loads(f"k = {text}\n", env=env)[""][key]


def test_variables_are_substituted_in_values():
    assert val("${HOST}") == "db.internal"
    assert val("postgres://${HOST}:${PORT}/app") == "postgres://db.internal:5432/app"
    assert val("${U_1}${U_1}") == "uu"
    assert val("[${SPACED}]") == "[  x ]"
    assert val("${SPACED}") == "  x "


def test_defaults_apply_when_unset_or_empty():
    assert val("${MISSING:-fallback}") == "fallback"
    assert val("${EMPTY:-fallback}") == "fallback"
    assert val("${HOST:-fallback}") == "db.internal"
    assert val("${MISSING:-}") == ""
    assert val("${MISSING:-a b:-c=d}") == "a b:-c=d"
    assert val("${EMPTY}") == ""


def test_double_dollar_is_a_literal_dollar():
    assert val("$$") == "$"
    assert val("$${HOST}") == "${HOST}"
    assert val("$$$${HOST}") == "$${HOST}"
    assert val("$$${HOST}") == "$db.internal"
    assert val("price $$5") == "price $5"


def test_other_dollars_stay_literal():
    assert val("cost $5") == "cost $5"
    assert val("a$") == "a$"
    assert val("$HOST") == "$HOST"
    assert val("$ {HOST}") == "$ {HOST}"


def test_undefined_variable_is_an_error_with_its_line():
    with pytest.raises(interp_error()) as e:
        loads("[db]\nport = 1\nhost = ${DB_HOST}\n", env=ENV)
    assert isinstance(e.value, ConfigError)
    assert e.value.line == 3
    assert str(e.value) == "line 3: undefined variable: DB_HOST"


def test_unterminated_reference_is_an_error():
    with pytest.raises(interp_error()) as e:
        loads("a = 1\nb = ${HOST\n", env=ENV)
    assert str(e.value) == "line 2: unterminated variable reference"


def test_invalid_names_are_errors():
    for ref, name in (("${}", ""), ("${1X}", "1X"), ("${A B}", "A B"), ("${A:x}", "A:x"), ("${:-d}", "")):
        with pytest.raises(interp_error()) as e:
            val(ref)
        assert str(e.value) == f"line 1: invalid variable name: {name}", ref


def test_substitution_is_a_single_pass():
    assert val("${REF}") == "${HOST}"
    assert val("${MISSING:-$$}") == "$$"


def test_comments_keys_and_sections_are_not_interpolated():
    data = loads("# ${MISSING}\n; ${MISSING}\n[s]\nk = ${HOST}\n", env=ENV)
    assert data == {"": {}, "s": {"k": "db.internal"}}


def test_environment_defaults_to_the_process_environment(monkeypatch, tmp_path):
    monkeypatch.setenv("CONFLOAD_TEST_VAR", "from-env")
    assert loads("k = ${CONFLOAD_TEST_VAR}\n")[""]["k"] == "from-env"
    monkeypatch.delenv("CONFLOAD_TEST_VAR")
    with pytest.raises(interp_error()):
        loads("k = ${CONFLOAD_TEST_VAR}\n")
    p = tmp_path / "app.conf"
    p.write_text("[s]\nurl = http://${HOST}/\n", encoding="utf-8")
    assert load(p, env=ENV)["s"]["url"] == "http://db.internal/"
