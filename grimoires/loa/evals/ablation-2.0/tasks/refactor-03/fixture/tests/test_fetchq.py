import pytest

from fetchq import plan, replay


def test_plan_urls_and_dedupe():
    got = plan(["/a", "b c", "/a", "x/y"], base_url="https://api.example/v1/")
    assert [p["url"] for p in got] == ["https://api.example/v1/a", "https://api.example/v1/b%20c", "https://api.example/v1/x/y"]
    assert got[0]["timeout"] == 10.0
    assert got[0]["delays"] == [0.5, 1.0]


def test_plan_options():
    got = plan(["a"], base_url="http://h", timeout=3, retries=3, backoff=1)
    assert got == [{"url": "http://h/a", "timeout": 3, "delays": [1, 2, 4]}]


def test_options_do_not_leak_between_calls():
    plan(["a"], base_url="http://h", retries=5)
    assert plan(["a"], base_url="http://h")[0]["delays"] == [0.5, 1.0]


def test_replay_retries_then_succeeds():
    rows = replay("a", [503, 429, 200], base_url="https://h")
    assert [(r["attempt"], r["status"], r["action"]) for r in rows] == [
        (0, 503, "retry in 0.5s"), (1, 429, "retry in 1s"), (2, 200, "done")]


def test_replay_gives_up():
    rows = replay("a", [500, 500, 500, 200], base_url="https://h", retries=2)
    assert [r["action"] for r in rows] == ["retry in 0.5s", "retry in 1s", "give-up"]
    rows = replay("a", [404, 200], base_url="https://h")
    assert [r["action"] for r in rows] == ["give-up"]


def test_zero_retries():
    assert replay("a", [503], base_url="https://h", retries=0)[0]["action"] == "give-up"
    assert plan(["a"], base_url="https://h", retries=0)[0]["delays"] == []


@pytest.mark.parametrize("kw,msg", [
    ({"base_url": "ftp://h"}, "base_url must start with http:// or https://"),
    ({"base_url": "https://h", "timeout": 0}, "timeout must be positive"),
    ({"base_url": "https://h", "retries": -1}, "retries must not be negative"),
    ({"base_url": "https://h", "backoff": -0.1}, "backoff must not be negative"),
])
def test_bad_options(kw, msg):
    with pytest.raises(ValueError) as ei:
        plan(["a"], **kw)
    assert str(ei.value) == msg
