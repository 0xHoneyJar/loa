# Task: equal-priority jobs run out of order

`jobq` (under `src/jobq/`) schedules named jobs that have a priority and may wait for other jobs. A `Scheduler` has `submit(name, priority=0, after=())`, `ready()`, `next()`, `start(name)`, `complete(name)`, `pause(name)`, `resume(name)`, `reprioritise(name, priority)` and `pending()`. `jobq.drain(scheduler, fn=None)` runs everything that can run and returns the job names in run order, and `jobq.order_key(job)` is the sort key for dispatch.

**Bug (observed):**
- Three jobs submitted as `zeta`, `alpha`, `mid`, all at priority 0, are drained as `alpha, mid, zeta`. With `root`, then `t1` (after `root`), then `t2`, all at priority 0, `next()` hands out `t2` before `t1` once `root` has completed, and `ready()` can list a different first job from the one `next()` returns.
- Raising a job's priority and lowering it back sends it behind the jobs that were submitted after it; so does pausing and resuming it. Reprioritising a job that is paused, or that is still waiting for one of its `after` jobs, makes it run anyway.
- During `drain`, a job that `fn` pauses while another job runs still runs (and then releases the jobs waiting for it), and a high-priority job released by a completion waits until older lower-priority jobs have run.

**Expected:**
- A job is ready when it is not paused, has not started, and every job in its `after` has completed. Among ready jobs the higher priority goes first; among equal priorities the job submitted earlier goes first. A job's submission position is fixed when it is submitted: reprioritising, pausing and resuming never change it.
- `ready()` lists the ready jobs in exactly that order, `next()` starts and returns the first of them (`None` when nothing is ready), and sorting jobs with `order_key` gives the same order.
- Reprioritising changes only the priority: a paused job stays paused, a job still waiting keeps waiting, and a ready job takes its new place at once. Each job runs at most once.
- `drain(scheduler, fn)` dispatches one job at a time: it takes `next()`, calls `fn(name)` when `fn` is given, completes the job and asks again, so a pause, a reprioritise or a release that happens while a job runs counts for the very next dispatch. Paused jobs, and the jobs waiting for them, are left pending. An empty scheduler drains to `[]`.
- The existing errors and their messages are unchanged.

Fix the bug in place and add regression tests of your own. Run the suite with `python3 -m pytest -q tests`.
