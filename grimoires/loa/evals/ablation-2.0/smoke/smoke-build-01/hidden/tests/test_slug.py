from textkit.slug import slugify


def test_basic():
    assert slugify("Hello World") == "hello-world"


def test_strips_edges():
    assert slugify("--Hello--") == "hello"


def test_lowercases():
    assert slugify("ABC") == "abc"


def test_collapses_whitespace_runs():
    assert slugify("Hello   World") == "hello-world"


def test_collapses_mixed_separator_runs():
    assert slugify("a & b") == "a-b"
