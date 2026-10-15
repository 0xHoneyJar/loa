import io

from logq.cli import main

LOG = """2026-10-14T23:59:59Z INFO before midnight
2026-10-15T00:00:00Z INFO midnight
2026-10-15T09:59:59Z DEBUG just before ten
2026-10-15T10:00:00Z WARN ten sharp
2026-10-15T12:30:00+02:00 ERROR half past ten in UTC
2026-10-15T23:59:59.900Z INFO last of the day
2026-10-16T00:00:00Z INFO next day
"""


def run(argv, text=LOG):
    out, err = io.StringIO(), io.StringIO()
    code = main(argv, stdin=io.StringIO(text), stdout=out, stderr=err)
    return code, [l.split(" ", 2)[2] for l in out.getvalue().splitlines()], err.getvalue()


def test_since_is_inclusive():
    code, out, err = run(["--since", "2026-10-15T10:00:00Z"])
    assert code == 0 and err == ""
    assert out == ["ten sharp", "half past ten in UTC", "last of the day", "next day"]


def test_until_is_inclusive_and_minutes_mean_zero_seconds():
    code, out, _ = run(["--until", "2026-10-15T10:00Z"])
    assert code == 0
    assert out[-1] == "ten sharp" and "half past ten in UTC" not in out
    _, out2, _ = run(["--since", "2026-10-15T10:00", "--until", "2026-10-15T10:30:00"])
    assert out2 == ["ten sharp", "half past ten in UTC"]


def test_date_only_since_starts_at_midnight_utc():
    _, out, _ = run(["--since", "2026-10-15"])
    assert out[0] == "midnight" and "before midnight" not in out


def test_date_only_until_covers_the_whole_day():
    _, out, _ = run(["--until", "2026-10-15"])
    assert out[-1] == "last of the day" and "next day" not in out
    _, same_day, _ = run(["--since", "2026-10-15", "--until", "2026-10-15"])
    assert same_day == ["midnight", "just before ten", "ten sharp", "half past ten in UTC", "last of the day"]


def test_bounds_compare_instants_across_offsets():
    _, out, _ = run(["--since", "2026-10-15T12:00:00+02:00", "--until", "2026-10-15T08:30:00-02:00"])
    assert out == ["ten sharp", "half past ten in UTC"]


def test_bound_without_offset_is_utc():
    _, out, _ = run(["--since", "2026-10-15T10:30:00"])
    assert out[0] == "half past ten in UTC"


def test_window_combines_with_other_filters():
    _, out, _ = run(["--since", "2026-10-15", "--until", "2026-10-15", "--level", "WARN"])
    assert out == ["ten sharp", "half past ten in UTC"]
    _, out2, _ = run(["--since", "2026-10-15T00:00:00Z", "--grep", "day"])
    assert out2 == ["last of the day", "next day"]


def test_invalid_bound_is_a_usage_error():
    for value in ("yesterday", "2026-13-01", "2026-10-15T25:00", "2026-10-15T10", "15/10/2026",
                  "2026-10-15T10:00:00.5", "2026-10-15Z", ""):
        code, out, err = run(["--since", value])
        assert (code, out, err) == (2, [], f"logq: invalid --since value: {value}\n"), value
    code, out, err = run(["--until", "soon"])
    assert (code, out, err) == (2, [], "logq: invalid --until value: soon\n")


def test_since_after_until_is_a_usage_error():
    code, out, err = run(["--since", "2026-10-16", "--until", "2026-10-15T23:00"])
    assert (code, out, err) == (2, [], "logq: --since is after --until\n")
    code2, out2, _ = run(["--since", "2026-10-15T10:00:00Z", "--until", "2026-10-15T10:00:00Z"])
    assert code2 == 0 and out2 == ["ten sharp"]
