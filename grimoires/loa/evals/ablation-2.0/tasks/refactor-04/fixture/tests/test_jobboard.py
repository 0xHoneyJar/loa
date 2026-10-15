import json

import pytest

from jobboard import Board, BoardError, can_cancel, counts, is_terminal, next_actions, summary_line


def run(board, ok):
    job = board.start_next()
    return board.finish(job["id"], ok)


def test_lifecycle():
    b = Board(max_attempts=2)
    a = b.submit("a")
    assert a["status"] == "pending"
    assert can_cancel(a) and not is_terminal(a)
    assert next_actions(a) == ["start", "cancel"]
    started = b.start_next()
    assert started is a and a["status"] == "running" and a["attempts"] == 1
    assert next_actions(a) == ["finish"]
    assert run_finish(b, a, ok=False)["status"] == "pending"
    run(b, ok=False)
    assert a["status"] == "failed" and is_terminal(a)
    assert next_actions(a) == ["resubmit"]


def run_finish(b, job, ok):
    return b.finish(job["id"], ok)


def test_done_is_terminal():
    b = Board()
    b.submit("x")
    job = run(b, ok=True)
    assert job["status"] == "done"
    assert is_terminal(job) and not can_cancel(job)
    assert next_actions(job) == []


def test_finish_requires_running():
    b = Board()
    j = b.submit("x")
    with pytest.raises(BoardError):
        b.finish(j["id"], True)
    assert b.start_next() is j
    assert b.start_next() is None


def test_counts_and_summary():
    b = Board(max_attempts=1)
    for n in "abcd":
        b.submit(n)
    run(b, ok=True)
    run(b, ok=False)
    b.start_next()
    assert counts(b.jobs) == {"pending": 1, "running": 1, "done": 1, "failed": 1}
    assert summary_line(b.jobs) == "4 jobs (1 pending, 1 running, 1 done, 1 failed); 50% finished"
    assert summary_line([]) == "no jobs"


def test_with_status():
    b = Board()
    b.submit("a")
    b.submit("b")
    b.start_next()
    assert [j["name"] for j in b.with_status("pending")] == ["b"]
    assert [j["name"] for j in b.with_status("running")] == ["a"]
    with pytest.raises(BoardError):
        b.with_status("queued")


def test_jobs_serialise_as_plain_strings():
    b = Board()
    b.submit("a")
    assert json.loads(json.dumps(b.jobs)) == [{"id": 1, "name": "a", "status": "pending", "attempts": 0}]
    assert json.dumps(counts(b.jobs)) == '{"pending": 1, "running": 0, "done": 0, "failed": 0}'
