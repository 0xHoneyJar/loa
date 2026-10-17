import pytest

from jobq import DuplicateJob, Scheduler, SchedulerError, UnknownJob


def test_submit_assigns_submission_numbers():
    s = Scheduler()
    assert s.submit("a").seq == 0
    assert s.submit("b", priority=3).seq == 1
    assert s.job("b").priority == 3


def test_higher_priority_dispatches_first():
    s = Scheduler()
    s.submit("low", priority=1)
    s.submit("high", priority=5)
    s.submit("mid", priority=3)
    assert s.ready() == ["high", "mid", "low"]
    assert [s.next(), s.next(), s.next(), s.next()] == ["high", "mid", "low", None]


def test_job_waits_for_its_after_jobs():
    s = Scheduler()
    s.submit("build", priority=1)
    s.submit("test", priority=9, after=["build"])
    assert s.ready() == ["build"]
    assert s.next() == "build"
    assert s.ready() == []
    s.complete("build")
    assert s.ready() == ["test"]


def test_pause_and_resume():
    s = Scheduler()
    s.submit("a", priority=2)
    s.submit("b", priority=1)
    s.pause("a")
    assert s.ready() == ["b"]
    s.resume("a")
    assert s.ready() == ["a", "b"]


def test_reprioritise_a_ready_job():
    s = Scheduler()
    s.submit("a", priority=1)
    s.submit("b", priority=2)
    s.reprioritise("a", 3)
    assert s.ready() == ["a", "b"]
    assert s.job("a").priority == 3


def test_errors():
    s = Scheduler()
    s.submit("a")
    with pytest.raises(DuplicateJob, match="duplicate job: a"):
        s.submit("a")
    with pytest.raises(UnknownJob) as exc:
        s.submit("b", after=["nope"])
    assert str(exc.value) == "unknown job: nope"
    with pytest.raises(ValueError, match="non-empty string"):
        s.submit("")
    with pytest.raises(TypeError, match="priority must be an int"):
        s.submit("c", priority="high")
    with pytest.raises(UnknownJob):
        s.pause("ghost")


def test_state_errors():
    s = Scheduler()
    s.submit("a")
    with pytest.raises(SchedulerError, match="job a is pending"):
        s.complete("a")
    assert s.next() == "a"
    with pytest.raises(SchedulerError, match="job a is running"):
        s.reprioritise("a", 4)
    s.complete("a")
    with pytest.raises(SchedulerError, match="job a is done"):
        s.pause("a")


def test_start_a_specific_job():
    s = Scheduler()
    s.submit("a", priority=5)
    s.submit("b", priority=1)
    s.submit("c", after=["a"])
    assert s.start("b").state == "running"
    assert s.ready() == ["a"]
    with pytest.raises(SchedulerError, match="job c is waiting"):
        s.start("c")


def test_pending_lists_unfinished_jobs_in_submission_order():
    s = Scheduler()
    for name, prio in (("x", 1), ("y", 9), ("z", 5)):
        s.submit(name, priority=prio)
    assert s.pending() == ["x", "y", "z"]
    s.complete(s.next())
    assert s.pending() == ["x", "z"]
