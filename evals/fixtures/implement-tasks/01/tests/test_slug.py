from textkit.slug import slugify


def test_basic():
    assert slugify("Hello World") == "hello-world"


def test_strips_edges():
    assert slugify("--Hello--") == "hello"


def test_lowercases():
    assert slugify("ABC") == "abc"
