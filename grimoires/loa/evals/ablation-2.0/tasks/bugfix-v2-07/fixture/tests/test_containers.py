from mdblocks import parse, render


def test_block_quote():
    assert render("> a\n> b\n") == "<blockquote>\n<p>a\nb</p>\n</blockquote>\n"


def test_lazy_paragraph_continuation():
    assert render("> a\nb\n") == "<blockquote>\n<p>a\nb</p>\n</blockquote>\n"


def test_nested_quotes():
    assert render("> > a\n") == "<blockquote>\n<blockquote>\n<p>a</p>\n</blockquote>\n</blockquote>\n"


def test_tight_bullet_list():
    assert render("- a\n- b\n") == "<ul>\n<li>a</li>\n<li>b</li>\n</ul>\n"


def test_loose_bullet_list():
    assert render("- a\n\n- b\n") == "<ul>\n<li>\n<p>a</p>\n</li>\n<li>\n<p>b</p>\n</li>\n</ul>\n"


def test_ordered_list_start():
    assert render("3. a\n4. b\n") == '<ol start="3">\n<li>a</li>\n<li>b</li>\n</ol>\n'


def test_ordered_list_from_one():
    assert render("1) a\n2) b\n") == "<ol>\n<li>a</li>\n<li>b</li>\n</ol>\n"


def test_nested_list():
    assert render("- a\n  - b\n") == "<ul>\n<li>a\n<ul>\n<li>b</li>\n</ul>\n</li>\n</ul>\n"


def test_list_item_with_code():
    assert render("- ```\n  x\n  ```\n") == "<ul>\n<li>\n<pre><code>x\n</code></pre>\n</li>\n</ul>\n"


def test_list_in_quote():
    assert render("> - a\n> - b\n") == "<blockquote>\n<ul>\n<li>a</li>\n<li>b</li>\n</ul>\n</blockquote>\n"


def test_list_interrupts_paragraph():
    assert render("a\n- b\n") == "<p>a</p>\n<ul>\n<li>b</li>\n</ul>\n"


def test_parse_tree_shape():
    doc = parse("> a\n\n- b\n- c\n")
    assert [n.kind for n in doc.children] == ["block_quote", "list"]
    assert [n.kind for n in doc.children[1].children] == ["item", "item"]
    assert doc.children[0].start_line == 1 and doc.children[1].children[1].start_line == 4


def test_empty_document():
    assert render("") == ""
    assert render("\n\n") == ""
