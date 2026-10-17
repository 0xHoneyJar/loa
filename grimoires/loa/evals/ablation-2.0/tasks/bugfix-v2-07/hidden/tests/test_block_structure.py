"""Acceptance cases for the block-structure specification of the task brief.

Each scenario case is a table of documents and the HTML that markdown-it
14.1.0 renders for them (each row was also checked against the reference
model).  Each conformance case renders a few hundred generated documents
spanning every block kind and nested containers and compares the package with
the reference model in _oracle_mdblocks; one differing document fails the case.
"""

import hashlib
import random

import pytest

from mdblocks import render

import _oracle_mdblocks as O


def check_table(rows):
    bad = [(src, render(src), want) for src, want in rows if render(src) != want]
    assert not bad, "\n\n".join("SOURCE %r\nGOT\n%sWANT\n%s" % b for b in bad)


def test_scenario_thematic_breaks_setext_and_list_markers():
    check_table([
        ('- - -\n',
         '<hr>\n'),
        ('* * *\n',
         '<hr>\n'),
        ('a\n---\n',
         '<h2>a</h2>\n'),
        ('a\n\n---\n',
         '<p>a</p>\n<hr>\n'),
        ('- a\n- - -\n',
         '<ul>\n<li>a</li>\n</ul>\n<hr>\n'),
        ('* a\n\n* * *\n',
         '<ul>\n<li>a</li>\n</ul>\n<hr>\n'),
        ('_ _ _\n',
         '<hr>\n'),
        ('--\n',
         '<p>--</p>\n'),
        ('a\n- - -\n',
         '<p>a</p>\n<hr>\n'),
        ('-  -  -  \n',
         '<hr>\n'),
    ])


def test_scenario_list_items_interrupting_paragraphs():
    check_table([
        ('a\n2. two\n',
         '<p>a\n2. two</p>\n'),
        ('a\n1. one\n',
         '<p>a</p>\n<ol>\n<li>one</li>\n</ol>\n'),
        ('a\n01. one\n',
         '<p>a</p>\n<ol>\n<li>one</li>\n</ol>\n'),
        ('a\n1)\n',
         '<p>a\n1)</p>\n'),
        ('a\n-\n',
         '<h2>a</h2>\n'),
        ('a\n- b\n',
         '<p>a</p>\n<ul>\n<li>b</li>\n</ul>\n'),
        ('a\n10) b\n',
         '<p>a\n10) b</p>\n'),
        ('> a\n3. b\n',
         '<blockquote>\n<p>a</p>\n</blockquote>\n<ol start="3">\n<li>b</li>\n</ol>\n'),
    ])


def test_scenario_ordered_start_numbers():
    check_table([
        ('0. zero\n',
         '<ol start="0">\n<li>zero</li>\n</ol>\n'),
        ('007. x\n',
         '<ol start="7">\n<li>x</li>\n</ol>\n'),
        ('1. a\n2. b\n',
         '<ol>\n<li>a</li>\n<li>b</li>\n</ol>\n'),
        ('3) a\n4) b\n',
         '<ol start="3">\n<li>a</li>\n<li>b</li>\n</ol>\n'),
        ('123456789. a\n',
         '<ol start="123456789">\n<li>a</li>\n</ol>\n'),
        ('1234567890. a\n',
         '<p>1234567890. a</p>\n'),
        ('0) a\n\n   b\n',
         '<ol start="0">\n<li>\n<p>a</p>\n<p>b</p>\n</li>\n</ol>\n'),
    ])


def test_scenario_list_type_changes():
    check_table([
        ('- a\n+ b\n',
         '<ul>\n<li>a</li>\n</ul>\n<ul>\n<li>b</li>\n</ul>\n'),
        ('- a\n* b\n- c\n',
         '<ul>\n<li>a</li>\n</ul>\n<ul>\n<li>b</li>\n</ul>\n<ul>\n<li>c</li>\n</ul>\n'),
        ('1. a\n1) b\n',
         '<ol>\n<li>a</li>\n</ol>\n<ol>\n<li>b</li>\n</ol>\n'),
        ('1. a\n- b\n',
         '<ol>\n<li>a</li>\n</ol>\n<ul>\n<li>b</li>\n</ul>\n'),
        ('- a\n\n+ b\n',
         '<ul>\n<li>a</li>\n</ul>\n<ul>\n<li>b</li>\n</ul>\n'),
        ('> - a\n> * b\n',
         '<blockquote>\n<ul>\n<li>a</li>\n</ul>\n<ul>\n<li>b</li>\n</ul>\n</blockquote>\n'),
    ])


def test_scenario_item_content_column():
    check_table([
        ('-     code\n',
         '<ul>\n<li>\n<pre><code>code\n</code></pre>\n</li>\n</ul>\n'),
        ('-     code\n  more\n',
         '<ul>\n<li>\n<pre><code>code\n</code></pre>\nmore</li>\n</ul>\n'),
        ('- a\n\n     b\n',
         '<ul>\n<li>\n<p>a</p>\n<p>b</p>\n</li>\n</ul>\n'),
        (' - a\n  b\n',
         '<ul>\n<li>a\nb</li>\n</ul>\n'),
        ('  1. a\n\n     b\n',
         '<ol>\n<li>\n<p>a</p>\n<p>b</p>\n</li>\n</ol>\n'),
        ('  1. a\n\n    b\n',
         '<ol>\n<li>a</li>\n</ol>\n<pre><code>b\n</code></pre>\n'),
        ('10.  a\n     b\n',
         '<ol start="10">\n<li>a\nb</li>\n</ol>\n'),
        ('   - a\n\n     b\n',
         '<ul>\n<li>\n<p>a</p>\n<p>b</p>\n</li>\n</ul>\n'),
    ])


def test_scenario_empty_items_and_blank_lines():
    check_table([
        ('-\n  foo\n',
         '<ul>\n<li>foo</li>\n</ul>\n'),
        ('-\n\n  foo\n',
         '<ul>\n<li></li>\n</ul>\n<p>foo</p>\n'),
        ('- a\n-\n- c\n',
         '<ul>\n<li>a</li>\n<li></li>\n<li>c</li>\n</ul>\n'),
        ('1.\n2. b\n',
         '<ol>\n<li></li>\n<li>b</li>\n</ol>\n'),
        ('-\n\n- b\n',
         '<ul>\n<li></li>\n<li>\n<p>b</p>\n</li>\n</ul>\n'),
        ('*\n',
         '<ul>\n<li></li>\n</ul>\n'),
        ('- \n  x\n',
         '<ul>\n<li>x</li>\n</ul>\n'),
    ])


def test_scenario_tight_and_loose_lists():
    check_table([
        ('- a\n- b\n',
         '<ul>\n<li>a</li>\n<li>b</li>\n</ul>\n'),
        ('- a\n\n- b\n',
         '<ul>\n<li>\n<p>a</p>\n</li>\n<li>\n<p>b</p>\n</li>\n</ul>\n'),
        ('- a\n- b\n\n  c\n',
         '<ul>\n<li>\n<p>a</p>\n</li>\n<li>\n<p>b</p>\n<p>c</p>\n</li>\n</ul>\n'),
        ('- a\n\n  - b\n',
         '<ul>\n<li>\n<p>a</p>\n<ul>\n<li>b</li>\n</ul>\n</li>\n</ul>\n'),
        ('- a\n- b\n\nc\n',
         '<ul>\n<li>a</li>\n<li>b</li>\n</ul>\n<p>c</p>\n'),
        ('-     code\n\n- b\n',
         '<ul>\n<li>\n<pre><code>code\n</code></pre>\n</li>\n<li>\n<p>b</p>\n</li>\n</ul>\n'),
        ('1. a\n\n   b\n2. c\n',
         '<ol>\n<li>\n<p>a</p>\n<p>b</p>\n</li>\n<li>\n<p>c</p>\n</li>\n</ol>\n'),
    ])


def test_scenario_looseness_through_nested_blocks():
    check_table([
        ('- a\n  - b\n\n- c\n',
         '<ul>\n<li>\n<p>a</p>\n<ul>\n<li>b</li>\n</ul>\n</li>\n<li>\n<p>c</p>\n</li>\n</ul>\n'),
        ('1. a\n   - b\n   - c\n\n2. d\n',
         '<ol>\n<li>\n<p>a</p>\n<ul>\n<li>b</li>\n<li>c</li>\n</ul>\n</li>\n<li>\n<p>d</p>\n</li>\n</ol>\n'),
        ('- a\n  > q\n\n- b\n',
         '<ul>\n<li>\n<p>a</p>\n<blockquote>\n<p>q</p>\n</blockquote>\n</li>\n<li>\n<p>b</p>\n</li>\n</ul>\n'),
        ('- a\n  - b\n\n  c\n',
         '<ul>\n<li>\n<p>a</p>\n<ul>\n<li>b</li>\n</ul>\n<p>c</p>\n</li>\n</ul>\n'),
        ('- a\n\n      code\n\n- b\n',
         '<ul>\n<li>\n<p>a</p>\n<pre><code>code\n</code></pre>\n</li>\n<li>\n<p>b</p>\n</li>\n</ul>\n'),
        ('- a\n  - b\n  - c\n- d\n',
         '<ul>\n<li>a\n<ul>\n<li>b</li>\n<li>c</li>\n</ul>\n</li>\n<li>d</li>\n</ul>\n'),
    ])


def test_scenario_fence_closing():
    check_table([
        ('````\nx\n```\n````\n',
         '<pre><code>x\n```\n</code></pre>\n'),
        ('```\nx\n````\n',
         '<pre><code>x\n</code></pre>\n'),
        ('~~~\nx\n```\n~~~\n',
         '<pre><code>x\n```\n</code></pre>\n'),
        ('```\nx\n   ```\n',
         '<pre><code>x\n</code></pre>\n'),
        ('```\nx\n    ```\n',
         '<pre><code>x\n    ```\n</code></pre>\n'),
        ('```\nx\n``` y\n```\n',
         '<pre><code>x\n``` y\n</code></pre>\n'),
        ('~~~~~\na\n~~~~\n',
         '<pre><code>a\n~~~~\n</code></pre>\n'),
    ])


def test_scenario_fence_indentation():
    check_table([
        ('  ```\n  a\n b\n    c\n  ```\n',
         '<pre><code>a\nb\n  c\n</code></pre>\n'),
        ('   ~~~ py\n   x\n  y\n~~~\n',
         '<pre><code class="language-py">x\ny\n</code></pre>\n'),
        ('- ```\n  a\n   b\n  ```\n',
         '<ul>\n<li>\n<pre><code>a\n b\n</code></pre>\n</li>\n</ul>\n'),
        ('> ```\n> x\n>  y\n',
         '<blockquote>\n<pre><code>x\n y\n</code></pre>\n</blockquote>\n'),
        ('   ~~~~\n   x\n   ~~~\n   ~~~~\n',
         '<pre><code>x\n~~~\n</code></pre>\n'),
    ])


def test_scenario_fence_info_and_language():
    check_table([
        ('``` c extra\nx\n```\n',
         '<pre><code class="language-c">x\n</code></pre>\n'),
        ('~~~   py  \nx\n~~~\n',
         '<pre><code class="language-py">x\n</code></pre>\n'),
        ('```js\n```\n',
         '<pre><code class="language-js"></code></pre>\n'),
        ('~~~ a&b\n~~~\n',
         '<pre><code class="language-a&amp;b"></code></pre>\n'),
        ('``` x y z\n```\n',
         '<pre><code class="language-x"></code></pre>\n'),
        ('````\n````\n',
         '<pre><code></code></pre>\n'),
    ])


def test_scenario_atx_headings():
    check_table([
        ('# foo#\n',
         '<h1>foo#</h1>\n'),
        ('# foo #\n',
         '<h1>foo</h1>\n'),
        ('## foo ##   \n',
         '<h2>foo</h2>\n'),
        ('### #\n',
         '<h3></h3>\n'),
        ('#\n',
         '<h1></h1>\n'),
        ('####### x\n',
         '<p>####### x</p>\n'),
        ('#5 bolt\n',
         '<p>#5 bolt</p>\n'),
        ('  # x\n',
         '<h1>x</h1>\n'),
        ('    # x\n',
         '<pre><code># x\n</code></pre>\n'),
        ('# a # b\n',
         '<h1>a # b</h1>\n'),
        ('# a ##b\n',
         '<h1>a ##b</h1>\n'),
    ])


def test_scenario_setext_and_lazy_lines():
    check_table([
        ('> a\n---\n',
         '<blockquote>\n<p>a</p>\n</blockquote>\n<hr>\n'),
        ('> a\n===\n',
         '<blockquote>\n<p>a\n===</p>\n</blockquote>\n'),
        ('a\n  b\n===\n',
         '<h1>a\nb</h1>\n'),
        ('- a\n---\n',
         '<ul>\n<li>a</li>\n</ul>\n<hr>\n'),
        ('> a\nb\n---\n',
         '<blockquote>\n<p>a\nb</p>\n</blockquote>\n<hr>\n'),
        ('- a\n  b\n  ===\n',
         '<ul>\n<li>\n<h1>a\nb</h1>\n</li>\n</ul>\n'),
    ])


def test_scenario_indented_code_and_paragraphs():
    check_table([
        ('> a\n    b\n',
         '<blockquote>\n<p>a\nb</p>\n</blockquote>\n'),
        ('a\n    b\n',
         '<p>a\nb</p>\n'),
        ('    a\n\n    b\n',
         '<pre><code>a\n\nb\n</code></pre>\n'),
        ('- a\n\n      b\n',
         '<ul>\n<li>\n<p>a</p>\n<pre><code>b\n</code></pre>\n</li>\n</ul>\n'),
        ('> a\n\n    b\n',
         '<blockquote>\n<p>a</p>\n</blockquote>\n<pre><code>b\n</code></pre>\n'),
        ('    a\n      \n    b\n',
         '<pre><code>a\n  \nb\n</code></pre>\n'),
        ('    a\n\n\n',
         '<pre><code>a\n</code></pre>\n'),
    ])


def test_scenario_block_quotes():
    check_table([
        ('> a\n> b\n',
         '<blockquote>\n<p>a\nb</p>\n</blockquote>\n'),
        ('> a\nb\n',
         '<blockquote>\n<p>a\nb</p>\n</blockquote>\n'),
        ('>a\n>  b\n',
         '<blockquote>\n<p>a\nb</p>\n</blockquote>\n'),
        ('> > a\n> b\n',
         '<blockquote>\n<blockquote>\n<p>a\nb</p>\n</blockquote>\n</blockquote>\n'),
        ('>     code\n',
         '<blockquote>\n<pre><code>code\n</code></pre>\n</blockquote>\n'),
        ('> - a\n> - b\n',
         '<blockquote>\n<ul>\n<li>a</li>\n<li>b</li>\n</ul>\n</blockquote>\n'),
        ('> a\n\n> b\n',
         '<blockquote>\n<p>a</p>\n</blockquote>\n<blockquote>\n<p>b</p>\n</blockquote>\n'),
        ('> # h\n> - - -\n',
         '<blockquote>\n<h1>h</h1>\n<hr>\n</blockquote>\n'),
    ])


def test_scenario_lazy_lines_and_lists():
    check_table([
        ('- a\nb\n',
         '<ul>\n<li>a\nb</li>\n</ul>\n'),
        ('- a\n\nb\n',
         '<ul>\n<li>a</li>\n</ul>\n<p>b</p>\n'),
        ('> - a\nb\n',
         '<blockquote>\n<ul>\n<li>a\nb</li>\n</ul>\n</blockquote>\n'),
        ('1. a\n    b\n',
         '<ol>\n<li>a\nb</li>\n</ol>\n'),
        ('- a\n  > b\nc\n',
         '<ul>\n<li>a\n<blockquote>\n<p>b\nc</p>\n</blockquote>\n</li>\n</ul>\n'),
        ('- a\n  b\n- c\n\n  d\ne\n',
         '<ul>\n<li>\n<p>a\nb</p>\n</li>\n<li>\n<p>c</p>\n<p>d\ne</p>\n</li>\n</ul>\n'),
    ])


def test_scenario_escaping():
    check_table([
        ('a & b < c > d "e"\n',
         '<p>a &amp; b &lt; c &gt; d &quot;e&quot;</p>\n'),
        ('# "q" & r\n',
         '<h1>&quot;q&quot; &amp; r</h1>\n'),
        ('```\n<x> & "y"\n```\n',
         '<pre><code>&lt;x&gt; &amp; &quot;y&quot;\n</code></pre>\n'),
        ('- a > b\n',
         '<ul>\n<li>a &gt; b</li>\n</ul>\n'),
        ('0. "zero"\n',
         '<ol start="0">\n<li>&quot;zero&quot;</li>\n</ol>\n'),
    ])


def test_scenario_tight_item_newlines():
    check_table([
        ('- a\n  ```\n  x\n  ```\n',
         '<ul>\n<li>a<pre><code>x\n</code></pre>\n</li>\n</ul>\n'),
        ('- a\n  # h\n',
         '<ul>\n<li>a\n<h1>h</h1>\n</li>\n</ul>\n'),
        ('- a\n  > q\n',
         '<ul>\n<li>a\n<blockquote>\n<p>q</p>\n</blockquote>\n</li>\n</ul>\n'),
        ('- a\n  ***\n',
         '<ul>\n<li>a\n<hr>\n</li>\n</ul>\n'),
        ('- a\n      code\n',
         '<ul>\n<li>a\ncode</li>\n</ul>\n'),
        ('- a\n  - b\n',
         '<ul>\n<li>a\n<ul>\n<li>b</li>\n</ul>\n</li>\n</ul>\n'),
    ])


def test_scenario_nested_containers():
    check_table([
        ('> 1. > - a\n>    >   b\n',
         '<blockquote>\n<ol>\n<li>\n<blockquote>\n<ul>\n<li>a\nb</li>\n</ul>\n</blockquote>\n</li>\n</ol>\n</blockquote>\n'),
        ('- > a\n  > b\n- c\n',
         '<ul>\n<li>\n<blockquote>\n<p>a\nb</p>\n</blockquote>\n</li>\n<li>c</li>\n</ul>\n'),
        ('1. - a\n\n   - b\n2. c\n',
         '<ol>\n<li>\n<ul>\n<li>\n<p>a</p>\n</li>\n<li>\n<p>b</p>\n</li>\n</ul>\n</li>\n<li>c</li>\n</ol>\n'),
        ('> > > a\n> > b\n> c\n',
         '<blockquote>\n<blockquote>\n<blockquote>\n<p>a\nb\nc</p>\n</blockquote>\n</blockquote>\n</blockquote>\n'),
        ('> 1. a\n>\n>    b\n',
         '<blockquote>\n<ol>\n<li>\n<p>a</p>\n<p>b</p>\n</li>\n</ol>\n</blockquote>\n'),
    ])


def test_scenario_whole_document():
    check_table([
        ('# Title\n\nSome text\nmore text\n\n- one\n- two\n\n  - nested\n1. first\n\n> quote\nlazy\n\n```py\ncode\n```\n\n    indented\n\nlast\n===\n* * *\n',
         '<h1>Title</h1>\n<p>Some text\nmore text</p>\n<ul>\n<li>\n<p>one</p>\n</li>\n<li>\n<p>two</p>\n<ul>\n<li>nested</li>\n</ul>\n</li>\n</ul>\n<ol>\n<li>first</li>\n</ol>\n<blockquote>\n<p>quote\nlazy</p>\n</blockquote>\n<pre><code class="language-py">code\n</code></pre>\n<pre><code>indented\n</code></pre>\n<h1>last</h1>\n<hr>\n'),
    ])


# ---- document generators ---------------------------------------------------------------

WORDS = ["foo", "bar", "baz", "qux", "alpha", "beta", "one", "two", "x", "y", "zed", "ok"]
TEXT_BITS = ['say "hi"', "a & b", "x < y", "p > q", "end.", "1 + 1", "a = b", "#tag", "c - d", "e: f", "(g)", "h, i"]


def text(r, lo=1, hi=4):
    parts = [r.choice(WORDS)]
    for _ in range(r.randint(lo, hi) - 1):
        parts.append(r.choice(WORDS) if r.random() < 0.7 else r.choice(TEXT_BITS))
    return " ".join(parts)


LEAF_LINES = [
    lambda r: text(r),
    lambda r: text(r),
    lambda r: text(r),
    lambda r: "",
    lambda r: "",
    lambda r: " " * r.randint(1, 6),
    lambda r: r.choice(["---", "***", "- - -", "* * *", "___", "_ _ _", "--", "----", "  ***", "-  -  -", "--- -"]),
    lambda r: r.choice(["==", "=", "===", "= =", "-", "--", "---  "]).rstrip() if r.random() < 0.9 else "=== x",
    lambda r: "#" * r.randint(1, 7) + r.choice(["", " ", "  "]) + (text(r, 1, 2) if r.random() < 0.8 else "") + r.choice(["", " #", " ##", "#", " # x"]),
    lambda r: r.choice(["#h", "#5 bolt", "# #", "##"]),
    lambda r: " " * r.randint(0, 3) + r.choice(["```", "````", "~~~", "~~~~", "`````"]) + r.choice(["", "", " js", "py", " c x y", "  sh  "]),
    lambda r: " " * r.randint(0, 5) + r.choice(["```", "````", "~~~", "~~~~"]),
    lambda r: " " * r.randint(4, 7) + text(r, 1, 2),
    lambda r: r.choice(["-", "+", "*", "1.", "2)", "0.", "3.", "10.", "007.", "1234567890.", "123456789)"]) + r.choice([" ", "  ", "   ", "    ", "     ", "      "]) + text(r, 1, 2),
    lambda r: r.choice(["-", "+", "*", "1.", "2."]) + r.choice(["", " ", "   "]),
    lambda r: r.choice(["-", "+", "*", "1."]) + " " + r.choice(["-", "*", ">", "1.", "#", "```", "    x", "- - -"]) + " " + text(r, 1, 1),
    lambda r: ">" + r.choice(["", " ", "  ", "     "]) + text(r, 1, 2),
    lambda r: ">",
]

PREFIXES = [">", "> ", "- ", "* ", "1. ", "2) ", "  ", "   ", "    ", " ", "+ ", "10. ", ">>"]


def soup(r, n_lines=None):
    """Random lines: block markers, container prefixes, indentation, text."""
    lines = []
    for _ in range(n_lines or r.randint(1, 14)):
        line = r.choice(LEAF_LINES)(r)
        k = r.random()
        if k < 0.45 and line != "":
            pre = "".join(r.choice(PREFIXES) for _ in range(r.randint(1, 2)))
            line = pre + line
        line = line.rstrip(" ") if line.strip(" ") else line
        lines.append(line)
    return "\n".join(lines) + "\n"


# ---- structured documents ---------------------------------------------------------------

def _indent(lines, n, first_prefix=None):
    out = []
    for i, line in enumerate(lines):
        if i == 0 and first_prefix is not None:
            out.append(first_prefix + line if line else first_prefix.rstrip(" "))
        else:
            out.append((" " * n + line) if line.strip(" ") else line)
    return out


def block(r, depth):
    k = r.random()
    if depth > 0 and k < 0.22:
        return list_block(r, depth - 1)
    if depth > 0 and k < 0.34:
        inner = blocks(r, depth - 1, r.randint(1, 3))
        out = []
        for line in inner:
            if line == "" and r.random() < 0.3:
                out.append("")          # ends the quote
                continue
            if out and r.random() < 0.15 and line and not line.startswith(" "):
                out.append(line)        # a lazy line
            else:
                out.append((">" + r.choice([" ", "", "  "]) + line).rstrip(" ") if line else ">")
        return out
    if k < 0.45:
        fence = r.choice(["```", "~~~", "````", "~~~~"])
        ind = " " * r.randint(0, 3)
        body = [(" " * r.randint(0, 5) + text(r, 1, 3)) if r.random() < 0.85 else "" for _ in range(r.randint(0, 3))]
        close = [ind + fence[0] * (len(fence) + r.randint(-1, 1))] if r.random() < 0.85 else []
        return [ind + fence + r.choice(["", " js", "py", " c d"])] + [ind[:r.randint(0, len(ind))] + b if b else b for b in body] + close
    if k < 0.53:
        return [" " * r.randint(4, 6) + text(r, 1, 3) if r.random() < 0.85 else " " * r.randint(0, 8) for _ in range(r.randint(1, 4))]
    if k < 0.6:
        return [r.choice(["---", "***", "* * *", "___", "- - -"])]
    if k < 0.7:
        return ["#" * r.randint(1, 6) + " " + text(r, 1, 3) + r.choice(["", " ##", " #"])]
    if k < 0.77:
        return [text(r) for _ in range(r.randint(1, 2))] + [r.choice(["===", "---", "=", "-", "  ---"])]
    lines = [text(r) for _ in range(r.randint(1, 3))]
    return [(" " * r.randint(0, 3) + l) if i and r.random() < 0.3 else l for i, l in enumerate(lines)]


def list_block(r, depth):
    kind = r.choice(["-", "+", "*", ".", ")"])
    start = r.choice([1, 1, 1, 2, 0, 9, 10, 123])
    out = []
    loose = r.random() < 0.35
    for i in range(r.randint(1, 4)):
        if kind in ".)":
            num = start + i if r.random() < 0.9 else r.randint(0, 20)
            marker = f"{num}{kind}"
        else:
            marker = kind if r.random() < 0.9 else r.choice("-+*")
        offset = " " * r.randint(0, 3) if r.random() < 0.3 else ""
        gap = " " * (1 if r.random() < 0.8 else r.randint(2, 5))
        width = len(offset) + len(marker) + len(gap)
        if r.random() < 0.08:
            content = []
        else:
            content = blocks(r, depth, r.randint(1, 3))
        if not content:
            out.append(offset + marker)
        else:
            first = content[0]
            if first == "":
                out.append(offset + marker)
                rest = content[1:] if r.random() < 0.7 else content
                out.extend(_indent(rest, width) if r.random() < 0.9 else _indent(rest, max(0, width - 1)))
            else:
                out.append(offset + marker + gap + first)
                out.extend(_indent(content[1:], width if r.random() < 0.9 else len(offset) + len(marker) + 1))
        if loose or r.random() < 0.15:
            out.append("")
    return out


def blocks(r, depth, n):
    out = []
    for i in range(n):
        if i and r.random() < 0.6:
            out.append("")
        out.extend(block(r, depth))
    return out


def structured(r, depth=3):
    lines = blocks(r, depth, r.randint(1, 5))
    lines = [l.rstrip(" ") if l.strip(" ") else l for l in lines]
    return "\n".join(lines) + "\n"



def top_blocks(r, depth, kind):
    """Top-level blocks forced to one container kind (``list`` or ``quote``)."""
    out = []
    for i in range(r.randint(1, 4)):
        if i and r.random() < 0.5:
            out.append("")
        if kind == "list":
            out.extend(list_block(r, depth))
        else:
            inner = blocks(r, depth, r.randint(1, 3))
            out.extend((">" + r.choice([" ", ""]) + line).rstrip(" ") if line else ">" for line in inner)
    return out


INLINE_CHARS = set("`*_~[]\\")


def in_domain(doc):
    """Rule 2: no paragraph or heading text holds a character inline rules would interpret."""
    for node in O.parse(doc).walk():
        if node.kind in ("paragraph", "heading") and INLINE_CHARS & set(O.paragraph_text(node.content)):
            return False
    return True


def documents(seed, count, kind, **kw):
    r = random.Random(seed)
    docs = []
    while len(docs) < count:
        if kind == "soup":
            doc = soup(r, r.randint(*kw.get("lines", (1, 14))))
        elif kind == "structured":
            doc = structured(r, kw.get("depth", 3))
        else:
            lines = top_blocks(r, kw.get("depth", 2), kind)
            doc = "\n".join(l.rstrip(" ") if l.strip(" ") else l for l in lines) + "\n"
        if not in_domain(doc):
            continue
        if hashlib.sha256(doc.encode()).hexdigest()[:16] in O.EXCLUDED:
            continue   # markdown-it departs from CommonMark on this document (see the oracle's docstring)
        docs.append(doc)
    return docs


PROFILES = {
    "soup_short_documents": (101, 400, "soup", {"lines": (1, 6)}),
    "soup_medium_documents": (102, 300, "soup", {"lines": (6, 14)}),
    "soup_long_documents": (103, 200, "soup", {"lines": (14, 30)}),
    "structured_depth_1": (201, 300, "structured", {"depth": 1}),
    "structured_depth_2": (202, 300, "structured", {"depth": 2}),
    "structured_depth_3": (203, 250, "structured", {"depth": 3}),
    "structured_depth_4": (204, 200, "structured", {"depth": 4}),
    "lists_depth_1": (301, 300, "list", {"depth": 1}),
    "lists_depth_2": (302, 250, "list", {"depth": 2}),
    "lists_depth_3": (303, 200, "list", {"depth": 3}),
    "quotes_depth_1": (401, 300, "quote", {"depth": 1}),
    "quotes_depth_3": (402, 200, "quote", {"depth": 3}),
    "mixed_seed_a": (501, 300, "structured", {"depth": 3}),
    "mixed_seed_b": (502, 300, "soup", {"lines": (4, 20)}),
    "mixed_seed_c": (503, 250, "list", {"depth": 4}),
}


@pytest.mark.parametrize("profile", sorted(PROFILES))
def test_conformance(profile):
    seed, count, kind, kw = PROFILES[profile]
    for doc in documents(seed, count, kind, **kw):
        got, want = render(doc), O.render(doc)
        assert got == want, "SOURCE %r\nGOT\n%sWANT\n%s" % (doc, got, want)
