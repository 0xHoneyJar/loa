import pytest

from jobq import Scheduler, SchedulerError, drain, order_key


def _sched(*specs):
    s = Scheduler()
    for spec in specs:
        name, priority, *after = spec
        s.submit(name, priority=priority, after=after[0] if after else ())
    return s


def _next_all(s):
    out = []
    while (name := s.next()) is not None:
        out.append(name)
        s.complete(name)
    return out


def test_equal_priority_drains_in_submission_order():
    s = _sched(("zeta", 0), ("alpha", 0), ("mid", 0))
    assert drain(s) == ["zeta", "alpha", "mid"]


def test_ready_lists_ties_by_submission():
    s = _sched(("w", 1), ("x", 2), ("b", 1), ("a", 2))
    assert s.ready() == ["x", "a", "w", "b"]
    jobs = [s.job(n) for n in ("b", "a", "w", "x")]
    assert [j.name for j in sorted(jobs, key=order_key)] == ["x", "a", "w", "b"]


def test_released_job_takes_its_submission_place():
    s = _sched(("root", 0), ("t1", 0, ["root"]), ("t2", 0))
    assert s.ready() == ["root", "t2"]
    assert s.next() == "root"
    s.complete("root")
    assert s.ready() == ["t1", "t2"]
    assert s.next() == "t1"


def test_next_always_returns_the_first_ready_job():
    s = _sched(("m", 1), ("k", 0, ["m"]), ("q", 0), ("c", 1, ["q"]), ("b", 0))
    order = []
    while s.ready():
        first = s.ready()[0]
        assert s.next() == first
        s.complete(first)
        order.append(first)
    assert order == ["m", "k", "q", "c", "b"]


def test_priority_round_trip_keeps_submission_position():
    s = _sched(("m", 0), ("k", 0), ("q", 0))
    s.reprioritise("m", 5)
    assert s.ready()[0] == "m"
    s.reprioritise("m", 0)
    assert s.ready() == ["m", "k", "q"]
    assert _next_all(s) == ["m", "k", "q"]


def test_pause_and_resume_keep_submission_position():
    s = _sched(("m", 0), ("k", 0), ("q", 0))
    s.pause("m")
    assert s.ready() == ["k", "q"]
    s.resume("m")
    assert _next_all(s) == ["m", "k", "q"]


def test_reprioritising_a_waiting_job_does_not_start_it():
    s = _sched(("build", 0), ("deploy", 0, ["build"]))
    s.reprioritise("deploy", 9)
    assert s.ready() == ["build"]
    assert s.next() == "build"
    assert s.next() is None
    s.complete("build")
    assert s.ready() == ["deploy"]


def test_reprioritising_a_paused_job_keeps_it_paused():
    s = _sched(("x", 0), ("y", 0))
    s.pause("x")
    s.reprioritise("x", 9)
    assert s.ready() == ["y"]
    assert drain(s) == ["y"]
    assert s.pending() == ["x"]
    s.resume("x")
    assert drain(s) == ["x"]


def test_pause_from_fn_counts_for_the_next_dispatch():
    s = _sched(("one", 0), ("two", 0), ("three", 0), ("four", 0, ["two"]))

    def fn(name):
        if name == "one":
            s.pause("two")

    assert drain(s, fn) == ["one", "three"]
    assert s.pending() == ["two", "four"]


def test_released_high_priority_job_runs_next():
    s = _sched(("seed", 0), ("low1", 0), ("urgent", 9, ["seed"]), ("low2", 0))
    assert drain(s) == ["seed", "urgent", "low1", "low2"]


def test_reprioritise_from_fn_counts_for_the_next_dispatch():
    s = _sched(("p", 0), ("r", 0), ("s", 0), ("last", 0))

    def fn(name):
        if name == "p":
            s.reprioritise("last", 1)

    assert drain(s, fn) == ["p", "last", "r", "s"]


def test_each_job_runs_once_and_empty_drains_to_nothing():
    assert drain(Scheduler()) == []
    s = Scheduler()
    assert s.ready() == [] and s.next() is None
    s = _sched(("a", 0), ("b", 0))
    for prio in (3, 1, 0, 2):
        s.reprioritise("b", prio)
    assert drain(s) == ["b", "a"]
    with pytest.raises(SchedulerError, match="job b is done"):
        s.reprioritise("b", 1)
