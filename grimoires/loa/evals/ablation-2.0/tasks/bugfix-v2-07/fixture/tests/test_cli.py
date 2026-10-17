import io

from mdblocks.cli import main


def test_cli_renders_a_file(tmp_path):
    f = tmp_path / "doc.md"
    f.write_text("# t\n")
    out = io.StringIO()
    assert main([str(f)], out) == 0
    assert out.getvalue() == "<h1>t</h1>\n"


def test_cli_usage():
    assert main(["a", "b"], io.StringIO()) == 2


def test_cli_missing_file(tmp_path):
    assert main([str(tmp_path / "nope.md")], io.StringIO()) == 1
