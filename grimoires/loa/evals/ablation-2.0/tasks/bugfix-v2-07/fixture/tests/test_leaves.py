from mdblocks import render


def test_paragraphs():
    assert render("one\ntwo\n\nthree\n") == "<p>one\ntwo</p>\n<p>three</p>\n"


def test_paragraph_lines_are_trimmed():
    assert render("  a\n   b\n") == "<p>a\nb</p>\n"


def test_escaping():
    assert render('a & b < c > "d"\n') == "<p>a &amp; b &lt; c &gt; &quot;d&quot;</p>\n"


def test_atx_headings():
    assert render("# one\n### three ###\n") == "<h1>one</h1>\n<h3>three</h3>\n"


def test_atx_needs_a_space():
    assert render("#5 bolt\n") == "<p>#5 bolt</p>\n"


def test_setext_headings():
    assert render("a\n===\n\nb\n---\n") == "<h1>a</h1>\n<h2>b</h2>\n"


def test_thematic_breaks():
    assert render("***\n\n---\n___\n") == "<hr>\n<hr>\n<hr>\n"


def test_indented_code():
    assert render("    a\n      b\n\n    c\n") == "<pre><code>a\n  b\n\nc\n</code></pre>\n"


def test_fenced_code():
    assert render("```\n<a>\n```\n") == "<pre><code>&lt;a&gt;\n</code></pre>\n"


def test_fenced_code_with_info():
    assert render("~~~ py\nx = 1\n~~~\n") == '<pre><code class="language-py">x = 1\n</code></pre>\n'


def test_unclosed_fence_runs_to_the_end():
    assert render("```\na\n\nb\n") == "<pre><code>a\n\nb\n</code></pre>\n"


def test_crlf_line_endings():
    assert render("a\r\nb\r\n") == "<p>a\nb</p>\n"
