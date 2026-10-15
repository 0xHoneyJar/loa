import io

from logq.cli import main
from logq.records import parse_line

LOG = """2026-10-15T08:00:00Z INFO service started
2026-10-15T08:05:00Z DEBUG cache warm
not a log line
2026-10-15T09:00:00+02:00 WARN disk at 81%
2026-10-15T09:10:00Z ERROR request failed: timeout
"""


def run(argv, text=LOG):
    out, err = io.StringIO(), io.StringIO()
    code = main(argv, stdin=io.StringIO(text), stdout=out, stderr=err)
    return code, out.getvalue().splitlines(), err.getvalue()


def test_no_filter_drops_malformed_lines_only():
    code, out, _ = run([])
    assert code == 0
    assert len(out) == 4 and "not a log line" not in out


def test_level_floor():
    code, out, _ = run(["--level", "WARN"])
    assert code == 0
    assert [l.split(" ")[1] for l in out] == ["WARN", "ERROR"]


def test_grep():
    _, out, _ = run(["--grep", "failed"])
    assert out == ["2026-10-15T09:10:00Z ERROR request failed: timeout"]


def test_bad_level_is_usage_error():
    code, out, err = run(["--level", "LOUD"])
    assert code == 2 and out == [] and err.startswith("logq: ")


def test_reads_file(tmp_path):
    p = tmp_path / "app.log"
    p.write_text(LOG, encoding="utf-8")
    code, out, _ = run([str(p)], text="")
    assert code == 0 and len(out) == 4


def test_offset_timestamp_is_normalised():
    rec = parse_line("2026-10-15T09:00:00+02:00 WARN x")
    assert rec.when.utcoffset().total_seconds() == 7200
    assert parse_line("2026-10-15T07:00:00 INFO naive").when.tzinfo is not None
