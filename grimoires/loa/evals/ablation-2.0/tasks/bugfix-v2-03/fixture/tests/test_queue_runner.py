from jobq import Job, ReadyQueue, Scheduler, drain, order_key


def _job(name, priority, seq):
    return Job(name=name, priority=priority, seq=seq)


def test_queue_orders_by_priority_and_keeps_push_order_within_one():
    q = ReadyQueue()
    q.push(_job("a", 1, 0))
    q.push(_job("b", 2, 1))
    q.push(_job("c", 1, 2))
    q.push(_job("d", 2, 3))
    assert q.names() == ["b", "d", "a", "c"]
    assert len(q) == 4
    assert q.pop() == "b"
    q.discard("a")
    assert "a" not in q and "c" in q
    assert q.names() == ["d", "c"]


def test_empty_queue():
    q = ReadyQueue()
    assert q.peek() is None and q.pop() is None and len(q) == 0
    q.discard("missing")


def test_order_key_puts_higher_priority_first():
    jobs = [_job("a", 1, 0), _job("b", 7, 1), _job("c", 3, 2)]
    assert [j.name for j in sorted(jobs, key=order_key)] == ["b", "c", "a"]


def test_drain_runs_a_chain():
    s = Scheduler()
    s.submit("fetch")
    s.submit("build", after=["fetch"])
    s.submit("ship", after=["build"])
    seen = []
    assert drain(s, seen.append) == ["fetch", "build", "ship"]
    assert seen == ["fetch", "build", "ship"]
    assert s.pending() == []


def test_drain_leaves_paused_jobs_and_their_successors():
    s = Scheduler()
    s.submit("a", priority=3)
    s.submit("b", priority=2)
    s.submit("c", priority=1, after=["b"])
    s.pause("b")
    assert drain(s) == ["a"]
    assert s.pending() == ["b", "c"]
    s.resume("b")
    assert drain(s) == ["b", "c"]
